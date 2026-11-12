import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

/// Da dove arrivano i contenuti. Vista non include nessuna lista: la fonte
/// la porta sempre l'utente. Se ne possono avere più insieme.
sealed class VistaSource {
  const VistaSource({this.name = '', this.userAgent = '', this.idPrefix = ''});

  /// Nome scelto dall'utente (vuoto = [label]).
  final String name;

  /// User-agent per scaricare la lista e guardarne i canali (vuoto = quello
  /// predefinito). Alcuni fornitori lo richiedono.
  final String userAgent;

  /// Prefisso degli ID di film, serie ed episodi di questa fonte, per non
  /// confonderli con quelli delle altre. Vuoto per la prima fonte (così
  /// preferiti e avanzamento di chi ne aveva una sola restano validi).
  final String idPrefix;

  Map<String, dynamic> toJson();

  /// Testo breve da mostrare, senza credenziali.
  String get label;

  /// Nome da mostrare.
  String get displayName => name.isNotEmpty ? name : label;

  /// Cosa identifica la fonte (indirizzo o server + utente).
  String get _identity;

  /// Server da cui arrivano i flussi (per lo user-agent).
  String get host;

  /// Identificativo stabile, usato per i file della cache: un'impronta
  /// (l'indirizzo, che può avere credenziali, non finisce nel nome).
  String get id => _fnv(_identity);

  /// La stessa fonte con nome, user-agent o prefisso diversi.
  VistaSource withMeta({String? name, String? userAgent, String? idPrefix});

  bool get canRefresh => true;

  Map<String, dynamic> _meta() => {
    if (name.isNotEmpty) 'name': name,
    if (userAgent.isNotEmpty) 'userAgent': userAgent,
    if (idPrefix.isNotEmpty) 'idPrefix': idPrefix,
  };

  static VistaSource fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    final ua = j['userAgent'] as String? ?? '';
    final prefix = j['idPrefix'] as String? ?? '';
    return switch (j['type']) {
      'xtream' => XtreamSource(
        XtreamCredentials.fromJson(j['credentials'] as Map<String, dynamic>),
        liveExtension: j['liveExtension'] as String? ?? 'ts',
        name: name,
        userAgent: ua,
        idPrefix: prefix,
      ),
      _ => M3uSource(
        j['location'] as String? ?? '',
        isFile: j['isFile'] as bool? ?? false,
        name: name,
        userAgent: ua,
        idPrefix: prefix,
      ),
    };
  }
}

String _fnv(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(63).toRadixString(16);
}

/// Lista M3U da indirizzo o da file.
class M3uSource extends VistaSource {
  const M3uSource(
    this.location, {
    this.isFile = false,
    super.name,
    super.userAgent,
    super.idPrefix,
  });

  /// URL (può contenere credenziali) o nome del file.
  final String location;
  final bool isFile;

  @override
  String get label {
    if (isFile) return location;
    final host = Uri.tryParse(location)?.host ?? '';
    return host.isEmpty ? 'Lista M3U' : host;
  }

  @override
  String get _identity => 'm3u|$location';

  @override
  String get host => isFile ? '' : (Uri.tryParse(location)?.host ?? '');

  @override
  bool get canRefresh => !isFile;

  @override
  M3uSource withMeta({String? name, String? userAgent, String? idPrefix}) =>
      M3uSource(
        location,
        isFile: isFile,
        name: name ?? this.name,
        userAgent: userAgent ?? this.userAgent,
        idPrefix: idPrefix ?? this.idPrefix,
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'm3u',
    'location': location,
    'isFile': isFile,
    ..._meta(),
  };
}

/// Account Xtream Codes.
class XtreamSource extends VistaSource {
  const XtreamSource(
    this.credentials, {
    this.liveExtension = 'ts',
    super.name,
    super.userAgent,
    super.idPrefix,
  });

  final XtreamCredentials credentials;
  final String liveExtension;

  @override
  String get label => '${credentials.username} · ${credentials.host}';

  @override
  String get _identity =>
      'xtream|${credentials.server}|${credentials.username}';

  @override
  String get host => credentials.host;

  @override
  XtreamSource withMeta({String? name, String? userAgent, String? idPrefix}) =>
      XtreamSource(
        credentials,
        liveExtension: liveExtension,
        name: name ?? this.name,
        userAgent: userAgent ?? this.userAgent,
        idPrefix: idPrefix ?? this.idPrefix,
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'xtream',
    'credentials': credentials.toJson(),
    'liveExtension': liveExtension,
    ..._meta(),
  };
}

/// Fonti + catalogo unito, pronto da mostrare.
class Library {
  const Library(this.sources, this.catalog);
  final List<VistaSource> sources;
  final Catalog catalog;

  /// La prima fonte.
  VistaSource get source => sources.first;
}

final _urlPattern = RegExp(r'\b[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);

/// Testo di un errore da mostrare a schermo senza indirizzi: gli URL Xtream
/// contengono nome utente e password.
String redactError(Object e) =>
    e.toString().replaceAll(_urlPattern, '[indirizzo]');

class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Salva le fonti e la cache dei contenuti (offline-first).
///
/// La configurazione (URL delle liste, credenziali Xtream) sta nel
/// portachiavi del sistema: Keystore su Android, Gestione credenziali su
/// Windows. Nella cartella privata dell'app restano solo i contenuti in
/// cache, un file per fonte.
///
/// TODO(sync): con l'account, URL e credenziali andranno cifrati sul
/// dispositivo prima dell'invio a Supabase.
class SourceStore {
  static const _sourcesKey = 'vista.sources';
  static const _legacySourceKey = 'vista.source';
  static const _legacyM3u = 'catalog.m3u';
  static const _legacyXtream = 'catalog.xtream.json';
  static const _prefsFile = 'channel_prefs.json';
  static const _defaultUserAgent = 'Vista/0.2';

  final _secure = const FlutterSecureStorage();

  /// Fonti e catalogo correnti: le schermate lo ascoltano e si aggiornano
  /// da sole (nuova lista, aggiornamento, canali rinominati o uniti).
  final library = ValueNotifier<Library?>(null);

  /// Nomi, loghi e unioni scelti dall'utente. Restano anche cambiando fonte.
  ChannelPrefs prefs = const ChannelPrefs();

  List<VistaSource> _sources = const [];

  /// Catalogo di ogni fonte (per id), risolto con le unioni [_rawMerges] ma
  /// senza le altre preferenze dell'utente.
  final _parts = <String, Catalog>{};
  Map<String, String> _rawMerges = const {};
  Catalog? _raw;

  List<VistaSource> get sources => List.unmodifiable(_sources);

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<File> _cacheOf(VistaSource s) =>
      _file(s is XtreamSource ? 'src_${s.id}.xtream.json' : 'src_${s.id}.m3u');

  // --- caricamento ------------------------------------------------------------

  /// Fonti salvate e catalogo dalla cache, oppure `null` al primo avvio.
  Future<Library?> load() async {
    final pf = await _file(_prefsFile);
    if (await pf.exists()) {
      try {
        prefs = ChannelPrefs.fromJson(
          jsonDecode(await pf.readAsString()) as Map<String, dynamic>,
        );
      } on FormatException {
        prefs = const ChannelPrefs();
      }
    }
    _sources = await _readSources();
    if (_sources.isEmpty) return null;
    final errors = <String>[];
    for (final s in _sources) {
      try {
        if (!await _loadCached(s)) await _download(s);
      } on SourceException catch (e) {
        errors.add('${s.displayName}: ${e.message}');
      }
    }
    if (_parts.isEmpty) {
      throw SourceException(
        errors.isEmpty ? 'Nessun contenuto nelle fonti salvate.' : errors.first,
      );
    }
    return _rebuild();
  }

  Future<List<VistaSource>> _readSources() async {
    var raw = await _secure.read(key: _sourcesKey);
    if (raw != null) {
      try {
        return [
          for (final j in jsonDecode(raw) as List)
            VistaSource.fromJson(j as Map<String, dynamic>),
        ];
      } on FormatException {
        return const [];
      }
    }
    // Versioni precedenti: una sola fonte, cache con nome fisso.
    var legacy = await _secure.read(key: _legacySourceKey);
    if (legacy == null &&
        (await (await _file(_legacyM3u)).exists() ||
            await (await _file(_legacyXtream)).exists())) {
      // Visto una volta su Windows: lettura vuota all'avvio, si riprova.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      legacy = await _secure.read(key: _legacySourceKey);
    }
    if (legacy == null) return const [];
    final s = VistaSource.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
    final old = await _file(s is XtreamSource ? _legacyXtream : _legacyM3u);
    if (await old.exists()) await old.rename((await _cacheOf(s)).path);
    _sources = [s];
    await _saveSources();
    await _secure.delete(key: _legacySourceKey);
    return [s];
  }

  Future<void> _saveSources() => _secure.write(
    key: _sourcesKey,
    value: jsonEncode([for (final s in _sources) s.toJson()]),
  );

  /// Catalogo di una fonte dalla cache; `false` se la cache non c'è.
  Future<bool> _loadCached(VistaSource s) async {
    final f = await _cacheOf(s);
    if (!await f.exists()) return false;
    _parts[s.id] = await _build(s, await f.readAsString());
    return true;
  }

  Future<Catalog> _build(VistaSource s, String cached) => switch (s) {
    M3uSource() => _isolateM3u(cached, prefs.merges),
    XtreamSource() => _isolateXtream(
      XtreamData.fromJson(jsonDecode(cached) as Map<String, dynamic>),
      s.credentials,
      s.liveExtension,
      prefs.merges,
    ),
  };

  /// Scarica di nuovo i contenuti di una fonte e li mette in cache.
  Future<void> _download(VistaSource s) async {
    switch (s) {
      case M3uSource(isFile: true):
        throw SourceException(
          'Questa lista viene da un file: per aggiornarla scegli di nuovo il file.',
        );
      case M3uSource(:final location):
        await _store(s, await _get(_checkedUri(location), s.userAgent));
      case XtreamSource(:final credentials):
        final data = await _xtream(
          XtreamClient(credentials, (u) => _get(u, s.userAgent)).fetchData,
        );
        await _store(s, jsonEncode(data.toJson()));
    }
  }

  /// Controlla il contenuto, lo salva in cache e lo tiene pronto.
  Future<void> _store(VistaSource s, String content) async {
    final catalog = await _build(s, content);
    if (catalog.isEmpty) {
      throw SourceException(
        s is XtreamSource ? 'L\'account non contiene canali, film o serie.' : 'Nessun contenuto trovato: il file non sembra una lista M3U valida.',
      );
    }
    await (await _cacheOf(s)).writeAsString(content);
    _parts[s.id] = catalog;
  }

  /// Unisce i cataloghi delle fonti, applica le preferenze e pubblica.
  Library _rebuild() {
    _rawMerges = prefs.merges;
    _raw = mergeCatalogs([
      for (final s in _sources)
        if (_parts[s.id] case final c?) (s.idPrefix, c),
    ]);
    return library.value = Library(
      List.unmodifiable(_sources),
      _withPrefs(_raw!, prefs),
    );
  }

  // --- preferenze dei canali --------------------------------------------------

  /// Salva le preferenze e aggiorna il catalogo: istantaneo, tranne quando
  /// cambiano le unioni (allora si risolvono di nuovo le liste dalla cache).
  Future<void> updatePrefs(ChannelPrefs next) async {
    prefs = next;
    await (await _file(_prefsFile)).writeAsString(jsonEncode(next.toJson()));
    if (_sources.isEmpty) return;
    final raw = _raw;
    if (raw != null && _sameMerges(_rawMerges, next.merges)) {
      library.value = Library(
        List.unmodifiable(_sources),
        _withPrefs(raw, next),
      );
      return;
    }
    for (final s in _sources) {
      await _loadCached(s);
    }
    _rebuild();
  }

  // --- aggiungere, aggiornare, togliere fonti ---------------------------------

  /// Aggiunge (o sostituisce, se è la stessa) una fonte già scaricata.
  Future<Library> _add(VistaSource s, String content) async {
    final existing = _sources.where((x) => x.id == s.id).firstOrNull;
    final source = s.withMeta(
      idPrefix:
          existing?.idPrefix ??
          (_sources.isEmpty ? '' : '${s.id.substring(0, 6)}~'),
      name: existing?.name,
      userAgent: s.userAgent.isNotEmpty ? s.userAgent : existing?.userAgent,
    );
    await _store(source, content);
    _sources = [
      for (final x in _sources) x.id == source.id ? source : x,
      if (existing == null) source,
    ];
    await _saveSources();
    return _rebuild();
  }

  /// Lista M3U letta da un file scelto dall'utente.
  Future<Library> importM3uFile(String name, List<int> bytes) => _add(
    M3uSource(name, isFile: true),
    utf8.decode(bytes, allowMalformed: true),
  );

  /// Lista M3U da indirizzo. Un link `get.php` di un pannello Xtream passa
  /// dall'API Xtream, che dà anche locandine, trame ed episodi.
  Future<Library> importM3uUrl(String url, {String userAgent = ''}) async {
    final xtream = xtreamFromM3uUrl(url);
    if (xtream != null) return loginXtream(xtream, userAgent: userAgent);
    final uri = _checkedUri(url);
    return _add(
      M3uSource(uri.toString(), userAgent: userAgent),
      await _get(uri, userAgent),
    );
  }

  Future<Library> loginXtream(
    XtreamCredentials c, {
    String userAgent = '',
  }) async {
    if (!c.isComplete) {
      throw SourceException('Inserisci server, nome utente e password.');
    }
    _checkedUri(c.server);
    final client = XtreamClient(c, (u) => _get(u, userAgent));
    final account = await _xtream(client.login);
    final data = await _xtream(client.fetchData);
    return _add(
      XtreamSource(
        c,
        liveExtension: account.liveExtension,
        userAgent: userAgent,
      ),
      jsonEncode(data.toJson()),
    );
  }

  /// Scarica di nuovo i contenuti di una fonte.
  Future<Library> refresh(VistaSource source) async {
    await _download(source);
    _seriesInfo.clear();
    _movieInfo.clear();
    return _rebuild();
  }

  /// Aggiorna tutte le fonti che si possono aggiornare; restituisce gli
  /// errori (una fonte che non risponde non blocca le altre).
  Future<List<String>> refreshAll({Duration? olderThan}) async {
    final errors = <String>[];
    var changed = false;
    for (final s in _sources) {
      if (!s.canRefresh) continue;
      if (olderThan != null) {
        final f = await _cacheOf(s);
        if (await f.exists() &&
            DateTime.now().difference(await f.lastModified()) < olderThan) {
          continue;
        }
      }
      try {
        await _download(s);
        changed = true;
      } on SourceException catch (e) {
        errors.add('${s.displayName}: ${e.message}');
      }
    }
    if (changed) {
      _seriesInfo.clear();
      _movieInfo.clear();
      _rebuild();
    }
    return errors;
  }

  /// Cambia nome o user-agent di una fonte.
  Future<void> updateSource(
    VistaSource s, {
    String? name,
    String? userAgent,
  }) async {
    _sources = [
      for (final x in _sources)
        x.id == s.id ? x.withMeta(name: name, userAgent: userAgent) : x,
    ];
    await _saveSources();
    _rebuild();
  }

  /// Toglie una fonte; se era l'ultima si torna alla schermata iniziale.
  Future<void> remove(VistaSource s) async {
    if (_sources.length <= 1) return clear();
    final f = await _cacheOf(s);
    if (await f.exists()) await f.delete();
    _parts.remove(s.id);
    _sources = [
      for (final x in _sources)
        if (x.id != s.id) x,
    ];
    await _saveSources();
    _rebuild();
  }

  /// Toglie tutte le fonti.
  Future<void> clear() async {
    _seriesInfo.clear();
    _movieInfo.clear();
    for (final s in _sources) {
      final f = await _cacheOf(s);
      if (await f.exists()) await f.delete();
    }
    _parts.clear();
    _raw = null;
    _sources = const [];
    await _secure.delete(key: _sourcesKey);
    library.value = null;
  }

  // --- dettagli di film e serie -----------------------------------------------

  /// La fonte di un film, di una serie o di un episodio (dal prefisso
  /// dell'ID) e l'ID originale sulla fonte.
  (VistaSource?, String) _origin(String id) {
    for (final s in _sources) {
      if (s.idPrefix.isNotEmpty && id.startsWith(s.idPrefix)) {
        return (s, id.substring(s.idPrefix.length));
      }
    }
    return (_sources.where((s) => s.idPrefix.isEmpty).firstOrNull, id);
  }

  final _seriesInfo = <String, SeriesInfo>{};
  final _movieInfo = <String, TitleDetails>{};

  /// Dettagli ed episodi di una serie; con Xtream chiesti una volta per
  /// sessione, con M3U ci sono solo gli episodi della lista.
  Future<SeriesInfo> seriesInfo(Series series) async {
    final (source, id) = _origin(series.id);
    if (source is! XtreamSource) {
      return SeriesInfo(TitleDetails.empty, series.episodes);
    }
    final cached = _seriesInfo[series.id];
    if (cached != null) return cached;
    final client = XtreamClient(
      source.credentials,
      (u) => _get(u, source.userAgent),
    );
    final info = await _xtream(() => client.seriesInfo(id));
    final p = source.idPrefix;
    return _seriesInfo[series.id] = p.isEmpty
        ? info
        : SeriesInfo(info.details, [
            for (final e in info.episodes) e.withId('$p${e.id}'),
          ]);
  }

  /// Dettagli di un film (solo Xtream; altrimenti vuoti).
  Future<TitleDetails> movieDetails(Movie movie) async {
    final (source, id) = _origin(movie.id);
    if (source is! XtreamSource) return TitleDetails.empty;
    final cached = _movieInfo[movie.id];
    if (cached != null) return cached;
    final client = XtreamClient(
      source.credentials,
      (u) => _get(u, source.userAgent),
    );
    return _movieInfo[movie.id] = await _xtream(() => client.movieDetails(id));
  }

  /// User-agent da usare per un flusso: quello della fonte che ha lo stesso
  /// server, se l'utente ne ha scelto uno.
  String? userAgentFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return null;
    for (final s in _sources) {
      if (s.userAgent.isNotEmpty && s.host == host) return s.userAgent;
    }
    return null;
  }

  // ---------------------------------------------------------------------------

  static bool _sameMerges(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// Le liste grandi (decine di migliaia di voci) si elaborano fuori dal
  /// thread dell'interfaccia. (Statiche: le funzioni inviate all'isolate non
  /// devono catturare lo store.)
  static Future<Catalog> _isolateM3u(String text, Map<String, String> merges) =>
      Isolate.run(() => buildM3uCatalog(parseM3u(text), merges: merges));

  static Future<Catalog> _isolateXtream(
    XtreamData data,
    XtreamCredentials creds,
    String ext,
    Map<String, String> merges,
  ) => Isolate.run(
    () => buildXtreamCatalog(data, creds, liveExtension: ext, merges: merges),
  );

  static Catalog _withPrefs(Catalog c, ChannelPrefs prefs) => Catalog(
    live: ResolveResult(prefs.apply(c.live.channels), c.live.report),
    movies: c.movies,
    series: c.series,
  );

  Future<T> _xtream<T>(Future<T> Function() job) async {
    try {
      return await job();
    } on XtreamException catch (e) {
      throw SourceException(e.message);
    }
  }

  Uri _checkedUri(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw SourceException(
        'Indirizzo non valido: deve iniziare con http:// o https://',
      );
    }
    return uri;
  }

  Future<String> _get(Uri uri, [String userAgent = '']) async {
    final http.Response res;
    // I messaggi non riportano mai l'URL: con Xtream contiene la password.
    try {
      res = await http
          .get(
            uri,
            headers: {
              'User-Agent': userAgent.isEmpty ? _defaultUserAgent : userAgent,
            },
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw SourceException('${uri.host} non ha risposto in tempo.');
    } on SocketException {
      throw SourceException(
        'Impossibile raggiungere ${uri.host}: controlla l\'indirizzo e la connessione.',
      );
    } on HandshakeException {
      throw SourceException('Connessione sicura con ${uri.host} non riuscita.');
    } on Exception {
      throw SourceException('Connessione non riuscita con ${uri.host}.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SourceException(
        'Accesso negato da ${uri.host} (${res.statusCode}): controlla le credenziali.',
      );
    }
    if (res.statusCode != 200) {
      throw SourceException('${uri.host} ha risposto ${res.statusCode}.');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}
