import 'dart:convert';

import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

final creds = XtreamCredentials(
  server: 'demo.example:8080/',
  username: 'mario',
  password: 'p@ss/1',
);

/// Pannello finto: risponde in base ad `action`.
FetchText fakePanel(Map<String?, Object> responses, {List<Uri>? log}) {
  return (uri) async {
    log?.add(uri);
    final r = responses[uri.queryParameters['action']];
    if (r == null) throw StateError('azione inattesa: $uri');
    return r is String ? r : jsonEncode(r);
  };
}

Map<String, Object> userInfo({
  Object auth = 1,
  String status = 'Active',
  Object? exp = '4102444800', // 2100
}) =>
    {
      'user_info': {
        'auth': auth,
        'status': status,
        'exp_date': exp,
        'max_connections': '2',
        'active_cons': 0,
        'is_trial': '0',
        'allowed_output_formats': ['m3u8', 'ts'],
      },
      'server_info': {'url': 'demo.example', 'port': '8080'},
    };

void main() {
  group('indirizzo del server', () {
    test('normalizeXtreamServer', () {
      expect(normalizeXtreamServer('demo.example:8080/'), 'http://demo.example:8080');
      expect(normalizeXtreamServer('https://demo.example/player_api.php'),
          'https://demo.example');
      expect(normalizeXtreamServer(' http://demo.example/xc/get.php '),
          'http://demo.example/xc');
    });

    test('xtreamFromM3uUrl riconosce il link get.php', () {
      final c = xtreamFromM3uUrl(
          'http://demo.example:8080/get.php?username=mario&password=segreta&type=m3u_plus&output=ts')!;
      expect((c.server, c.username, c.password),
          ('http://demo.example:8080', 'mario', 'segreta'));
      expect(xtreamFromM3uUrl('https://iptv.example/lista.m3u'), isNull);
      expect(xtreamFromM3uUrl('http://demo.example/get.php?username=mario'), isNull);
    });
  });

  group('login', () {
    test('account attivo', () async {
      final log = <Uri>[];
      final a = await XtreamClient(creds, fakePanel({null: userInfo()}, log: log))
          .login();
      expect(a.status, 'Active');
      expect(a.maxConnections, 2);
      expect(a.expiresAt!.year, 2100);
      expect(a.liveExtension, 'ts');
      expect(log.single.path, '/player_api.php');
      expect(log.single.queryParameters['password'], 'p@ss/1');
    });

    test('credenziali errate', () {
      expect(
        XtreamClient(creds, fakePanel({null: userInfo(auth: 0)})).login(),
        throwsA(isA<XtreamException>().having(
            (e) => e.message, 'message', contains('non corretti'))),
      );
    });

    test('account scaduto o disattivato', () {
      expect(
        XtreamClient(creds, fakePanel({null: userInfo(exp: 1700000000)}))
            .login(now: DateTime.utc(2026, 11, 10)),
        throwsA(isA<XtreamException>().having(
            (e) => e.message, 'message', contains('scaduto'))),
      );
      expect(
        XtreamClient(creds, fakePanel({null: userInfo(status: 'Banned')})).login(),
        throwsA(isA<XtreamException>().having(
            (e) => e.message, 'message', contains('Banned'))),
      );
    });

    test('un sito qualunque non è un pannello Xtream', () {
      expect(
        XtreamClient(creds, fakePanel({null: '<html>ciao</html>'})).login(),
        throwsA(isA<XtreamException>()),
      );
      expect(
        XtreamClient(creds, fakePanel({null: {'ok': true}})).login(),
        throwsA(isA<XtreamException>()),
      );
    });
  });

  test('catalogo: live, film e serie con le categorie', () async {
    final client = XtreamClient(
      creds,
      fakePanel({
        'get_live_categories': [
          {'category_id': '1', 'category_name': 'Nazionali'},
        ],
        'get_live_streams': [
          {'num': 1, 'name': 'IT: Rai 1 HD', 'stream_id': 101, 'stream_icon': 'https://img.example/rai1.png', 'epg_channel_id': 'Rai1.it', 'category_id': '1'},
          {'num': 2, 'name': 'IT: Rai 1 FHD', 'stream_id': '102', 'epg_channel_id': 'Rai1.it@FHD', 'category_id': '1'},
          {'num': 3, 'name': 'Rai Movie', 'stream_id': 103, 'category_id': null},
          {'num': 4, 'name': 'senza id'},
        ],
        'get_vod_categories': {
          '0': {'category_id': '5', 'category_name': 'Thriller'},
        },
        'get_vod_streams': [
          {'name': 'Vetro (2024)', 'stream_id': 501, 'stream_icon': 'https://img.example/vetro.jpg', 'rating': '7.2', 'category_id': '5', 'container_extension': 'mkv'},
          {'name': 'Orbita', 'stream_id': '502', 'rating': 0, 'category_id': '5', 'container_extension': ''},
        ],
        'get_series_categories': [],
        'get_series': [
          {'name': 'Marea', 'series_id': 77, 'cover': 'https://img.example/marea.jpg', 'plot': 'Una biologa…', 'releaseDate': '2026-03-01', 'rating': '8.1', 'category_id': '9'},
        ],
      }),
    );

    final data = await client.fetchData();
    // La cache non deve contenere la password.
    expect(jsonEncode(data.toJson()), isNot(contains('p@ss')));

    final cat = buildXtreamCatalog(
      XtreamData.fromJson(data.toJson()),
      creds,
      liveExtension: 'm3u8',
    );

    final rai1 = cat.live.channels.first;
    expect(rai1.name, 'Rai 1');
    expect(rai1.group, 'Nazionali');
    expect(rai1.streams.map((s) => s.url), [
      'http://demo.example:8080/live/mario/p%40ss%2F1/102.m3u8',
      'http://demo.example:8080/live/mario/p%40ss%2F1/101.m3u8',
    ]);
    expect(cat.live.channels[1].group, 'Altri');
    expect(cat.live.report.entries, 3);

    expect(cat.movies.map((m) => (m.title, m.year, m.rating, m.group)), [
      ('Vetro', 2024, '7,2', 'Thriller'),
      ('Orbita', null, '', 'Thriller'),
    ]);
    expect(cat.movies[0].url, 'http://demo.example:8080/movie/mario/p%40ss%2F1/501.mkv');
    expect(cat.movies[1].url, endsWith('/502.mp4'));

    final marea = cat.series.single;
    expect((marea.id, marea.title, marea.year, marea.rating, marea.group),
        ('77', 'Marea', 2026, '8,1', 'Altri'));
    expect(marea.episodes, isEmpty);
  });

  test('una risposta HTML al posto del catalogo è un errore', () {
    final client = XtreamClient(creds, (uri) async => '<html>');
    expect(client.fetchData(), throwsA(isA<XtreamException>()));
  });

  group('episodi', () {
    test('mappa stagione → lista, titoli puliti e ordinati', () async {
      final eps = await XtreamClient(
        creds,
        fakePanel({
          'get_series_info': {
            'info': {'name': 'Marea'},
            'episodes': {
              '2': [
                {'id': '9001', 'episode_num': '1', 'season': 2, 'title': 'Marea - S02E01 - Ritorno', 'container_extension': 'mp4', 'info': {'duration_secs': 2700, 'plot': 'Torna.'}},
              ],
              '1': [
                {'id': 8002, 'episode_num': 2, 'season': '1', 'title': 'Marea - S01E02', 'container_extension': 'mkv', 'info': []},
                {'id': 8001, 'episode_num': 1, 'season': 1, 'title': 'La partenza', 'container_extension': 'mkv', 'info': {'movie_image': 'https://img.example/e1.jpg'}},
              ],
            },
          },
        }),
      ).episodes('77');

      expect(eps.map((e) => (e.code, e.title)), [
        ('S01E01', 'La partenza'),
        ('S01E02', 'Episodio 2'),
        ('S02E01', 'Ritorno'),
      ]);
      expect(eps.first.image, 'https://img.example/e1.jpg');
      expect(eps.first.url, 'http://demo.example:8080/series/mario/p%40ss%2F1/8001.mkv');
      expect(eps.last.duration, const Duration(minutes: 45));
      expect(eps.last.plot, 'Torna.');
    });

    test('lista di liste e risposta vuota', () {
      final eps = parseXtreamEpisodes({
        'episodes': [
          [
            {'id': '1', 'episode_num': 1, 'season': 1, 'title': 'Uno'},
          ],
        ],
      }, creds);
      expect(eps.single.title, 'Uno');
      expect(eps.single.url, endsWith('/1.mp4'));
      expect(parseXtreamEpisodes({'episodes': []}, creds), isEmpty);
      expect(parseXtreamEpisodes(null, creds), isEmpty);
    });
  });
}
