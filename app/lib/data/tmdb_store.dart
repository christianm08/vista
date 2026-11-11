import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

/// Catalogo dei servizi di streaming tramite TMDB (dati di disponibilità di
/// JustWatch). La chiave TMDB è dell'utente e resta nel portachiavi.
///
/// Per le build di prova si può passare `--dart-define=TMDB_KEY=…` e, per un
/// server finto, `--dart-define=TMDB_BASE=http://…`.
class TmdbStore {
  TmdbStore();

  static const _keyName = 'vista.tmdb';
  static const _builtInKey = String.fromEnvironment('TMDB_KEY');
  static const _base = String.fromEnvironment(
    'TMDB_BASE',
    defaultValue: 'https://api.themoviedb.org',
  );
  static const region = 'IT';

  final _secure = const FlutterSecureStorage();

  /// Client pronto, oppure `null` se manca la chiave.
  final client = ValueNotifier<TmdbClient?>(null);

  bool get ready => client.value != null;

  /// La chiave è quella inserita dall'utente (non quella di build).
  bool userKey = false;

  // Cache in memoria (e su disco per i servizi e gli abbinamenti).
  List<WatchProvider>? _providers;
  final _details = <String, TmdbDetails>{};
  final _pages = <String, (DateTime, TmdbPage)>{};
  final _seasons = <String, List<TmdbEpisode>>{};
  Map<String, int> _matches = {}; // chiave titolo lista → id TMDB (0 = nessuno)
  Timer? _saveMatches;

  Future<void> init() async {
    String? key;
    try {
      key = await _secure.read(key: _keyName);
    } catch (_) {
      key = null;
    }
    userKey = key != null && key.isNotEmpty;
    final k = userKey ? key! : _builtInKey;
    if (k.isNotEmpty) client.value = _make(k);
    try {
      final f = await _file('tmdb_matches.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          _matches = {
            for (final e in j.entries) '${e.key}': (e.value as num).toInt(),
          };
        }
      }
    } catch (_) {
      _matches = {};
    }
  }

  TmdbClient _make(String key) =>
      TmdbClient(key.trim(), _get, region: region, base: _base);

  /// Verifica e salva la chiave. Lancia [TmdbException] se non va.
  Future<void> setKey(String key) async {
    final c = _make(key);
    await c.check();
    await _secure.write(key: _keyName, value: key.trim());
    userKey = true;
    _clear();
    client.value = c;
  }

  Future<void> removeKey() async {
    await _secure.delete(key: _keyName);
    userKey = false;
    _clear();
    client.value = _builtInKey.isEmpty ? null : _make(_builtInKey);
  }

  void _clear() {
    _providers = null;
    _details.clear();
    _pages.clear();
    _seasons.clear();
  }

  // --- dati ----------------------------------------------------------------------

  /// Servizi disponibili in Italia (cache di 7 giorni).
  Future<List<WatchProvider>> providers() async {
    final cached = _providers;
    if (cached != null) return cached;
    final c = _need();
    final f = await _file('tmdb_providers.json');
    if (await f.exists() &&
        DateTime.now().difference(await f.lastModified()) <
            const Duration(days: 7)) {
      try {
        final list = jsonDecode(await f.readAsString()) as List;
        return _providers = [
          for (final p in list)
            WatchProvider(
              id: p['id'] as int,
              name: p['name'] as String,
              logoPath: p['logo'] as String? ?? '',
              priority: p['prio'] as int? ?? 999,
            ),
        ];
      } catch (_) {
        // cache rovinata: si riscarica
      }
    }
    final list = await c.providers();
    await f.writeAsString(
      jsonEncode([
        for (final p in list)
          {'id': p.id, 'name': p.name, 'logo': p.logoPath, 'prio': p.priority},
      ]),
    );
    return _providers = list;
  }

  /// Pagine di catalogo, in cache per un'ora.
  Future<TmdbPage> discover(
    MediaType type, {
    Iterable<int> providers = const [],
    String sortBy = 'popularity.desc',
    int page = 1,
    bool recent = false,
    int? genre,
  }) => _cachedPage(
    'd:${type.name}:${providers.join('|')}:$sortBy:$page:$recent:$genre',
    () => _need().discover(
      type,
      providers: providers,
      sortBy: sortBy,
      page: page,
      recent: recent,
      genre: genre,
    ),
  );

  Future<TmdbPage> trending() =>
      _cachedPage('trending', () => _need().trending());

  Future<TmdbPage> search(String q) =>
      _cachedPage('s:$q', () => _need().search(q));

  Future<TmdbPage> _cachedPage(
    String key,
    Future<TmdbPage> Function() load,
  ) async {
    final hit = _pages[key];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(hours: 1)) {
      return hit.$2;
    }
    final p = await load();
    _pages[key] = (DateTime.now(), p);
    return p;
  }

  Future<TmdbDetails> details(MediaType type, int id) async {
    final k = '${type.name}:$id';
    return _details[k] ??= await _need().details(type, id);
  }

  Future<List<TmdbEpisode>> season(int tvId, int n) async =>
      _seasons['$tvId:$n'] ??= await _need().season(tvId, n);

  // --- abbinamento con la lista IPTV ---------------------------------------------------

  /// Il titolo TMDB di un film della lista (ID dal pannello o ricerca per
  /// titolo e anno). `null` se non si trova.
  Future<TmdbTitle?> matchMovie(Movie m) =>
      _match(MediaType.movie, m.title, m.year, m.tmdbId);

  Future<TmdbTitle?> matchSeries(Series s) =>
      _match(MediaType.tv, s.title, s.year, s.tmdbId);

  Future<TmdbTitle?> _match(
    MediaType type,
    String title,
    int? year,
    int? knownId,
  ) async {
    if (!ready) return null;
    if (knownId != null) {
      return (await details(type, knownId)).title;
    }
    final key = '${type.name}:${titleMatchKey(title)}:${year ?? ''}';
    final saved = _matches[key];
    if (saved != null) {
      return saved == 0 ? null : (await details(type, saved)).title;
    }
    var results = await _need().searchTitle(type, title, year: year);
    var best = bestMatch(title, year, results);
    // Alcune liste hanno l'anno sbagliato: si riprova senza.
    if (best == null && year != null) {
      results = await _need().searchTitle(type, title);
      best =
          bestMatch(title, year, results) ??
          bestMatch(title, null, results.take(1).toList());
    }
    _matches[key] = best?.id ?? 0;
    _saveMatchesSoon();
    return best;
  }

  void _saveMatchesSoon() {
    _saveMatches?.cancel();
    _saveMatches = Timer(const Duration(seconds: 3), () async {
      try {
        await (await _file('tmdb_matches.json'))
            .writeAsString(jsonEncode(_matches));
      } catch (_) {}
    });
  }

  // Indice dei titoli della lista per trovare un titolo TMDB tra film e serie.
  Catalog? _indexFor;
  Map<String, List<Movie>> _movieIndex = {};
  Map<String, List<Series>> _seriesIndex = {};
  Map<int, Movie> _movieById = {};
  Map<int, Series> _seriesById = {};

  void _index(Catalog c) {
    if (identical(_indexFor, c)) return;
    _indexFor = c;
    _movieIndex = {};
    _seriesIndex = {};
    _movieById = {};
    _seriesById = {};
    for (final m in c.movies) {
      (_movieIndex[titleMatchKey(m.title)] ??= []).add(m);
      if (m.tmdbId != null) _movieById[m.tmdbId!] = m;
    }
    for (final s in c.series) {
      (_seriesIndex[titleMatchKey(s.title)] ??= []).add(s);
      if (s.tmdbId != null) _seriesById[s.tmdbId!] = s;
    }
  }

  /// Il film della lista IPTV che corrisponde al titolo TMDB, se c'è.
  Movie? localMovie(Catalog c, TmdbTitle t) {
    _index(c);
    final byId = _movieById[t.id];
    if (byId != null) return byId;
    for (final k in {titleMatchKey(t.title), titleMatchKey(t.originalTitle)}) {
      for (final m in _movieIndex[k] ?? const <Movie>[]) {
        if (sameTitle(m.title, m.year, t)) return m;
      }
    }
    return null;
  }

  Series? localSeries(Catalog c, TmdbTitle t) {
    _index(c);
    final byId = _seriesById[t.id];
    if (byId != null) return byId;
    for (final k in {titleMatchKey(t.title), titleMatchKey(t.originalTitle)}) {
      for (final s in _seriesIndex[k] ?? const <Series>[]) {
        if (sameTitle(s.title, s.year, t)) return s;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------

  TmdbClient _need() {
    final c = client.value;
    if (c == null) {
      throw TmdbException('Aggiungi la chiave TMDB nelle impostazioni.');
    }
    return c;
  }

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// I messaggi non riportano mai l'URL: con la chiave v3 la contiene.
  static Future<String> _get(Uri uri, Map<String, String> headers) async {
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw TmdbException('TMDB non ha risposto in tempo.');
    } on Exception {
      throw TmdbException(
        'Impossibile raggiungere TMDB: controlla la connessione.',
      );
    }
    if (res.statusCode == 401) throw TmdbException('Chiave TMDB non valida.');
    if (res.statusCode == 404) {
      throw TmdbException('Titolo non trovato su TMDB.');
    }
    if (res.statusCode == 429) {
      throw TmdbException('Troppe richieste a TMDB: riprova tra poco.');
    }
    if (res.statusCode != 200) {
      throw TmdbException('TMDB ha risposto ${res.statusCode}.');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}
