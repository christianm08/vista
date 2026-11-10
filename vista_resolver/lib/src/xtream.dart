import 'dart:convert';

import 'classify.dart';
import 'models.dart';
import 'resolver.dart';

/// Scarica il testo di un URL. Il pacchetto resta senza dipendenze di rete:
/// l'app passa la sua implementazione (e i test una finta).
typedef FetchText = Future<String> Function(Uri uri);

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server, utente e password di un account Xtream Codes.
class XtreamCredentials {
  XtreamCredentials({
    required String server,
    required String username,
    required String password,
  })  : server = normalizeXtreamServer(server),
        username = username.trim(),
        password = password.trim();

  factory XtreamCredentials.fromJson(Map<String, dynamic> j) =>
      XtreamCredentials(
        server: j['server'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );

  /// `http://host:porta` più l'eventuale percorso, senza `/` finale.
  final String server;
  final String username;
  final String password;

  String get host => Uri.tryParse(server)?.host ?? server;

  bool get isComplete =>
      server.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  Map<String, String> toJson() =>
      {'server': server, 'username': username, 'password': password};
}

/// `host:8080/` → `http://host:8080`; toglie `player_api.php` e `get.php`.
String normalizeXtreamServer(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return s.replaceAll(RegExp(r'/+$'), '');
  var path = u.path;
  for (final suffix in const [
    '/player_api.php',
    '/get.php',
    '/xmltv.php',
    '/panel_api.php',
  ]) {
    if (path.toLowerCase().endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  path = path.replaceAll(RegExp(r'/+$'), '');
  return '${u.scheme}://${u.authority}$path';
}

/// Riconosce il link M3U di un pannello Xtream
/// (`…/get.php?username=…&password=…`) e ne ricava le credenziali.
XtreamCredentials? xtreamFromM3uUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return null;
  if (!u.path.toLowerCase().endsWith('/get.php') &&
      !u.path.toLowerCase().endsWith('/player_api.php')) {
    return null;
  }
  final user = u.queryParameters['username'] ?? '';
  final pass = u.queryParameters['password'] ?? '';
  if (user.isEmpty || pass.isEmpty) return null;
  return XtreamCredentials(server: url, username: user, password: pass);
}

/// Stato dell'account (`user_info`).
class XtreamAccount {
  const XtreamAccount({
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
    this.formats = const [],
  });

  final String status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;

  /// `allowed_output_formats`, es. `[m3u8, ts]`.
  final List<String> formats;

  /// Formato dei flussi live: `ts` se ammesso, altrimenti il primo.
  String get liveExtension {
    if (formats.isEmpty || formats.contains('ts')) return 'ts';
    if (formats.contains('m3u8')) return 'm3u8';
    return formats.first;
  }
}

/// Risposte grezze del pannello, così come arrivano: si salvano in cache
/// (non contengono la password) e si ricostruisce il catalogo all'avvio.
class XtreamData {
  const XtreamData({
    required this.liveCategories,
    required this.live,
    required this.vodCategories,
    required this.vod,
    required this.seriesCategories,
    required this.series,
  });

  factory XtreamData.fromJson(Map<String, dynamic> j) => XtreamData(
        liveCategories: j['liveCategories'] as String? ?? '[]',
        live: j['live'] as String? ?? '[]',
        vodCategories: j['vodCategories'] as String? ?? '[]',
        vod: j['vod'] as String? ?? '[]',
        seriesCategories: j['seriesCategories'] as String? ?? '[]',
        series: j['series'] as String? ?? '[]',
      );

  final String liveCategories;
  final String live;
  final String vodCategories;
  final String vod;
  final String seriesCategories;
  final String series;

  Map<String, String> toJson() => {
        'liveCategories': liveCategories,
        'live': live,
        'vodCategories': vodCategories,
        'vod': vod,
        'seriesCategories': seriesCategories,
        'series': series,
      };
}

/// Client dell'API `player_api.php`.
class XtreamClient {
  XtreamClient(this.credentials, this._fetch);

  final XtreamCredentials credentials;
  final FetchText _fetch;

  Uri apiUri([String? action, Map<String, String> extra = const {}]) =>
      Uri.parse('${credentials.server}/player_api.php').replace(
        queryParameters: {
          'username': credentials.username,
          'password': credentials.password,
          if (action != null) 'action': action,
          ...extra,
        },
      );

  /// Verifica le credenziali e lo stato dell'abbonamento.
  Future<XtreamAccount> login({DateTime? now}) async {
    final j = _decode(await _fetch(apiUri()));
    if (j is! Map || j['user_info'] is! Map) {
      throw XtreamException(
          'Il server non risponde come un pannello Xtream: controlla l\'indirizzo.');
    }
    final u = j['user_info'] as Map;
    if (_int(u['auth']) != 1) {
      throw XtreamException('Nome utente o password non corretti.');
    }
    final exp = _int(u['exp_date']);
    final account = XtreamAccount(
      status: _str(u['status']),
      expiresAt: exp == null || exp <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      maxConnections: _int(u['max_connections']),
      activeConnections: _int(u['active_cons']),
      isTrial: _int(u['is_trial']) == 1,
      formats: [
        for (final f in (u['allowed_output_formats'] is List
            ? u['allowed_output_formats'] as List
            : const []))
          _str(f).toLowerCase(),
      ],
    );
    final status = account.status.toLowerCase();
    if (status.isNotEmpty && status != 'active') {
      throw XtreamException('Account non attivo (stato: ${account.status}).');
    }
    final at = account.expiresAt;
    if (at != null && at.isBefore(now ?? DateTime.now())) {
      final d = at.toLocal();
      throw XtreamException(
          'Abbonamento scaduto il ${d.day}/${d.month}/${d.year}.');
    }
    return account;
  }

  /// Scarica categorie e contenuti di live, film e serie.
  Future<XtreamData> fetchData() async {
    const actions = [
      'get_live_categories',
      'get_live_streams',
      'get_vod_categories',
      'get_vod_streams',
      'get_series_categories',
      'get_series',
    ];
    final r = await Future.wait([for (final a in actions) _fetch(apiUri(a))]);
    for (var i = 0; i < r.length; i++) {
      final v = _decodeOrNull(r[i]);
      if (v is! List && v is! Map) {
        throw XtreamException(
            'Risposta non valida dal server Xtream (${actions[i]}).');
      }
    }
    return XtreamData(
      liveCategories: r[0],
      live: r[1],
      vodCategories: r[2],
      vod: r[3],
      seriesCategories: r[4],
      series: r[5],
    );
  }

  /// Episodi di una serie (`get_series_info`).
  Future<List<Episode>> episodes(String seriesId) async {
    final j = _decode(
        await _fetch(apiUri('get_series_info', {'series_id': seriesId})));
    return parseXtreamEpisodes(j, credentials);
  }
}

String _segment(String s) => Uri.encodeComponent(s);

String xtreamLiveUrl(XtreamCredentials c, String id, String ext) =>
    '${c.server}/live/${_segment(c.username)}/${_segment(c.password)}/$id.$ext';

String xtreamMovieUrl(XtreamCredentials c, String id, String ext) =>
    '${c.server}/movie/${_segment(c.username)}/${_segment(c.password)}/$id.$ext';

String xtreamEpisodeUrl(XtreamCredentials c, String id, String ext) =>
    '${c.server}/series/${_segment(c.username)}/${_segment(c.password)}/$id.$ext';

/// Costruisce il catalogo dalle risposte grezze. I canali live passano dal
/// resolver come le voci M3U (stesso raggruppamento per tvg-id e nome).
Catalog buildXtreamCatalog(
  XtreamData data,
  XtreamCredentials c, {
  String liveExtension = 'ts',
  ChannelMatcher? matcher,
  Map<String, String> merges = const {},
}) {
  final liveCats = _categories(data.liveCategories);
  final vodCats = _categories(data.vodCategories);
  final seriesCats = _categories(data.seriesCategories);

  final entries = <M3uEntry>[];
  for (final s in _list(data.live)) {
    final id = _str(s['stream_id']);
    if (id.isEmpty || isSeparatorEntry(_str(s['name']))) continue;
    entries.add(M3uEntry(
      name: _nameOr(s['name']),
      url: xtreamLiveUrl(c, id, liveExtension),
      tvgId: _str(s['epg_channel_id']),
      logo: _str(s['stream_icon']),
      group: liveCats[_str(s['category_id'])] ?? 'Altri',
    ));
  }

  final movies = <Movie>[];
  for (final s in _list(data.vod)) {
    final id = _str(s['stream_id']);
    if (id.isEmpty) continue;
    final t = splitTitleYear(_nameOr(s['name']));
    final ext = _str(s['container_extension']);
    movies.add(Movie(
      id: id,
      title: t.title,
      year: _year(s['year']) ?? t.year,
      url: xtreamMovieUrl(c, id, ext.isEmpty ? 'mp4' : ext),
      poster: _str(s['stream_icon']),
      group: vodCats[_str(s['category_id'])] ?? 'Altri',
      rating: _rating(s['rating']),
      plot: _str(s['plot']),
    ));
  }

  final series = <Series>[];
  for (final s in _list(data.series)) {
    final id = _str(s['series_id']);
    if (id.isEmpty) continue;
    final t = splitTitleYear(_nameOr(s['name']));
    series.add(Series(
      id: id,
      title: t.title,
      year: _year(s['releaseDate']) ?? _year(s['release_date']) ?? t.year,
      poster: _str(s['cover']),
      group: seriesCats[_str(s['category_id'])] ?? 'Altri',
      rating: _rating(s['rating']),
      plot: _str(s['plot']),
    ));
  }

  return Catalog(
    live: resolveChannels(
      M3uPlaylist(entries: entries),
      matcher: matcher,
      merges: merges,
    ),
    movies: movies,
    series: series,
  );
}

/// Legge `episodes` di `get_series_info`: una mappa stagione → lista oppure,
/// su alcuni pannelli, una lista di liste.
List<Episode> parseXtreamEpisodes(Object? json, XtreamCredentials c) {
  if (json is! Map) return const [];
  final raw = json['episodes'];
  final groups = raw is Map ? raw.values : (raw is List ? raw : const []);
  final out = <Episode>[];
  for (final g in groups) {
    final items = g is List ? g : (g is Map ? [g] : const []);
    for (final e in items) {
      if (e is! Map) continue;
      final id = _str(e['id']);
      if (id.isEmpty) continue;
      final info = e['info'] is Map ? e['info'] as Map : const {};
      final number = _int(e['episode_num']) ?? out.length + 1;
      final rawTitle = _str(e['title']).trim();
      final marker = parseEpisodeMarker(rawTitle);
      final title = marker != null && marker.rest.isNotEmpty
          ? marker.rest
          : (marker == null && rawTitle.isNotEmpty
              ? rawTitle
              : 'Episodio $number');
      final ext = _str(e['container_extension']);
      final secs = _int(info['duration_secs']);
      out.add(Episode(
        id: id,
        title: title,
        url: xtreamEpisodeUrl(c, id, ext.isEmpty ? 'mp4' : ext),
        season: _int(e['season']) ?? marker?.season ?? 1,
        number: number,
        plot: _str(info['plot']),
        image: _str(info['movie_image']),
        duration: secs == null || secs <= 0 ? null : Duration(seconds: secs),
      ));
    }
  }
  return sortEpisodes(out);
}

// --- lettura tollerante del JSON dei pannelli --------------------------------

Object? _decodeOrNull(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

Object? _decode(String body) {
  final v = _decodeOrNull(body);
  if (v == null) {
    throw XtreamException('Risposta non valida dal server Xtream.');
  }
  return v;
}

/// Alcuni pannelli restituiscono una mappa indicizzata al posto della lista.
List<Map> _list(String raw) {
  final v = _decodeOrNull(raw);
  final items = v is List ? v : (v is Map ? v.values.toList() : const []);
  return [for (final i in items) if (i is Map) i];
}

Map<String, String> _categories(String raw) => {
      for (final c in _list(raw))
        if (_str(c['category_id']).isNotEmpty)
          _str(c['category_id']): _nameOr(c['category_name'], 'Altri'),
    };

String _str(Object? v) => v == null ? '' : (v is String ? v : v.toString());

String _nameOr(Object? v, [String fallback = 'Senza nome']) {
  final s = _str(v).trim();
  return s.isEmpty ? fallback : s;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    final s = v.trim();
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
  if (v is bool) return v ? 1 : 0;
  return null;
}

final _yearIn = RegExp(r'(?:19|20)\d{2}');

int? _year(Object? v) {
  final m = _yearIn.firstMatch(_str(v));
  return m == null ? null : int.parse(m.group(0)!);
}

String _rating(Object? v) {
  final d = double.tryParse(_str(v).trim().replaceAll(',', '.'));
  if (d == null || d <= 0) return '';
  return d.toStringAsFixed(1).replaceAll('.', ',');
}
