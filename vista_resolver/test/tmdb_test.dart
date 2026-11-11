import 'dart:convert';

import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

/// TMDB finto: risponde in base al percorso; registra le richieste.
HttpGet fakeTmdb(Map<String, Object> byPath, {List<(Uri, Map<String, String>)>? log}) =>
    (uri, headers) async {
      log?.add((uri, headers));
      final r = byPath[uri.path.replaceFirst('/3', '')];
      if (r == null) return jsonEncode({'success': false, 'status_message': 'non trovato'});
      return jsonEncode(r);
    };

void main() {
  group('client', () {
    test('chiave v3 nella query, token v4 nell\'intestazione', () async {
      final log = <(Uri, Map<String, String>)>[];
      final get = fakeTmdb({'/configuration': {'images': {}}}, log: log);
      await TmdbClient('abc123', get).check();
      await TmdbClient('eyJhbGciOi.x.y', get).check();
      expect(log[0].$1.queryParameters['api_key'], 'abc123');
      expect(log[0].$1.queryParameters['language'], 'it-IT');
      expect(log[1].$1.queryParameters.containsKey('api_key'), isFalse);
      expect(log[1].$2['Authorization'], 'Bearer eyJhbGciOi.x.y');
    });

    test('chiave sbagliata', () {
      Future<String> get(Uri u, Map<String, String> h) async =>
          jsonEncode({'status_code': 7, 'status_message': 'Invalid API key', 'success': false});
      expect(TmdbClient('x', get).check(), throwsA(isA<TmdbException>()));
    });

    test('servizi: film e serie uniti, ordinati per priorità in Italia', () async {
      final get = fakeTmdb({
        '/watch/providers/movie': {
          'results': [
            {'provider_id': 8, 'provider_name': 'Netflix', 'logo_path': '/n.jpg', 'display_priorities': {'IT': 2}},
            {'provider_id': 119, 'provider_name': 'Amazon Prime Video', 'logo_path': '/p.jpg', 'display_priorities': {'IT': 1}},
          ],
        },
        '/watch/providers/tv': {
          'results': [
            {'provider_id': 8, 'provider_name': 'Netflix', 'logo_path': '/n.jpg', 'display_priorities': {'IT': 3}},
            {'provider_id': 222, 'provider_name': 'RaiPlay', 'logo_path': '/r.jpg', 'display_priority': 5},
          ],
        },
      });
      final ps = await TmdbClient('k', get).providers();
      expect(ps.map((p) => (p.id, p.priority)), [(119, 1), (8, 2), (222, 5)]);
      expect(ps.first.logo, 'https://image.tmdb.org/t/p/w154/p.jpg');
    });

    test('discover filtra per servizi e restituisce i titoli', () async {
      final log = <(Uri, Map<String, String>)>[];
      final get = fakeTmdb({
        '/discover/tv': {
          'page': 1,
          'total_pages': 3,
          'results': [
            {'id': 5920, 'name': 'The Mentalist', 'original_name': 'The Mentalist', 'first_air_date': '2008-09-23', 'poster_path': '/m.jpg', 'vote_average': 8.3},
          ],
        },
      }, log: log);
      final page = await TmdbClient('k', get)
          .discover(MediaType.tv, providers: [8, 384], recent: true, now: DateTime(2026, 11, 11));
      final q = log.single.$1.queryParameters;
      expect(q['with_watch_providers'], '8|384');
      expect(q['watch_region'], 'IT');
      expect(q['first_air_date.lte'], '2026-11-11');
      expect(page.hasMore, isTrue);
      final t = page.results.single;
      expect((t.type, t.id, t.title, t.year, t.key), (MediaType.tv, 5920, 'The Mentalist', 2008, 'tm:tv:5920'));
    });

    test('ricerca multipla: solo film e serie', () async {
      final get = fakeTmdb({
        '/search/multi': {
          'results': [
            {'media_type': 'person', 'id': 1, 'name': 'Simon Baker'},
            {'media_type': 'tv', 'id': 5920, 'name': 'The Mentalist'},
            {'media_type': 'movie', 'id': 603, 'title': 'Matrix', 'release_date': '1999-03-31'},
          ],
        },
      });
      final r = (await TmdbClient('k', get).search('mental')).results;
      expect(r.map((t) => t.key), ['tm:tv:5920', 'tm:movie:603']);
    });
  });

  group('dettagli', () {
    final mentalist = {
      'id': 5920,
      'name': 'The Mentalist',
      'original_name': 'The Mentalist',
      'first_air_date': '2008-09-23',
      'episode_run_time': [43],
      'genres': [
        {'id': 80, 'name': 'Crime'},
        {'id': 18, 'name': 'Dramma'},
      ],
      'created_by': [
        {'name': 'Bruno Heller'},
      ],
      'seasons': [
        {'season_number': 0, 'name': 'Speciali', 'episode_count': 2},
        {'season_number': 1, 'name': 'Stagione 1', 'episode_count': 23},
      ],
      'credits': {
        'cast': [
          {'name': 'Simon Baker', 'character': 'Patrick Jane', 'profile_path': '/s.jpg'},
        ],
      },
      'videos': {
        'results': [
          {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser1'},
          {'site': 'YouTube', 'type': 'Trailer', 'key': 'trailer1'},
        ],
      },
      'external_ids': {'imdb_id': 'tt1196946'},
      'watch/providers': {
        'results': {
          'IT': {
            'link': 'https://www.themoviedb.org/tv/5920/watch?locale=IT',
            'flatrate': [
              {'provider_id': 384, 'provider_name': 'HBO Max', 'logo_path': '/h.jpg', 'display_priority': 4},
              {'provider_id': 8, 'provider_name': 'Netflix', 'logo_path': '/n.jpg', 'display_priority': 1},
            ],
            'buy': [
              {'provider_id': 8, 'provider_name': 'Netflix', 'logo_path': '/n.jpg', 'display_priority': 1},
              {'provider_id': 2, 'provider_name': 'Apple TV', 'logo_path': '/a.jpg', 'display_priority': 6},
            ],
          },
          'US': {
            'flatrate': [
              {'provider_id': 9, 'provider_name': 'Other'},
            ],
          },
        },
      },
    };

    test('serie: generi, ideatori, stagioni, trailer, IMDb, disponibilità', () async {
      final d = await TmdbClient('k', fakeTmdb({'/tv/5920': mentalist})).details(MediaType.tv, 5920);
      expect(d.genres, ['Crime', 'Dramma']);
      expect(d.directors, ['Bruno Heller']);
      expect(d.runtime, const Duration(minutes: 43));
      expect(d.seasons.map((s) => s.number), [1]);
      expect(d.trailerKey, 'trailer1');
      expect(d.imdbUrl, 'https://www.imdb.com/title/tt1196946/');
      expect(d.cast.single.character, 'Patrick Jane');
      // Ogni servizio una volta sola, incluso prima di acquisto.
      expect(d.availability.distinct.map((e) => (e.$1.name, e.$2)), [
        ('Netflix', OfferKind.flatrate),
        ('HBO Max', OfferKind.flatrate),
        ('Apple TV', OfferKind.buy),
      ]);
      expect(d.availability.streamingIds, {8, 384});
      expect(d.availability.link, contains('watch?locale=IT'));
    });

    test('nessuna disponibilità nel paese', () {
      final a = Availability.fromJson({
        'results': {'US': {}},
      }, 'IT');
      expect(a.isEmpty, isTrue);
      expect(Availability.fromJson(null, 'IT').isEmpty, isTrue);
    });
  });

  group('abbinamento con la lista', () {
    const matrix = TmdbTitle(
      type: MediaType.movie,
      id: 603,
      title: 'Matrix',
      originalTitle: 'The Matrix',
      date: '1999-03-31',
    );

    test('chiave del titolo', () {
      expect(titleMatchKey('Il Signore degli Anelli: La Compagnia dell\'Anello (2001) [4K]'),
          'signore degli anelli la compagnia dell anello');
      expect(titleMatchKey('Amélie'), 'amelie');
      expect(titleMatchKey('The Matrix'), 'matrix');
    });

    test('titolo o titolo originale, anno vicino', () {
      expect(sameTitle('The Matrix', 1999, matrix), isTrue);
      expect(sameTitle('Matrix', 2000, matrix), isTrue);
      expect(sameTitle('Matrix', null, matrix), isTrue);
      expect(sameTitle('Matrix', 2003, matrix), isFalse);
      expect(sameTitle('Matrix Reloaded', 2003, matrix), isFalse);
      expect(bestMatch('matrix', 1999, [matrix])?.id, 603);
    });

    test('ID TMDB dal pannello Xtream', () {
      final c = buildXtreamCatalog(
        const XtreamData(
          liveCategories: '[]',
          live: '[]',
          vodCategories: '[]',
          vod: '[{"name":"Matrix","stream_id":1,"tmdb":"603"},{"name":"Altro","stream_id":2,"tmdb":""}]',
          seriesCategories: '[]',
          series: '[{"name":"The Mentalist","series_id":7,"tmdb":5920}]',
        ),
        XtreamCredentials(server: 'http://x', username: 'u', password: 'p'),
      );
      expect(c.movies.map((m) => m.tmdbId), [603, null]);
      expect(c.series.single.tmdbId, 5920);
    });
  });

  test('link ai servizi', () {
    expect(providerSearchUrl('Netflix', 'The Mentalist'), 'https://www.netflix.com/search?q=The+Mentalist');
    expect(providerSearchUrl('Amazon Prime Video', 'Matrix'), contains('primevideo.com'));
    expect(providerSearchUrl('Servizio sconosciuto', 'x', fallback: 'https://tmdb'), 'https://tmdb');
    expect(providerAndroidPackages('Netflix'), contains('com.netflix.ninja'));
  });
}
