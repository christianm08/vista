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
/// la porta sempre l'utente.
sealed class VistaSource {
  const VistaSource();

  Map<String, dynamic> toJson();

  /// Testo breve da mostrare, senza credenziali.
  String get label;

  static VistaSource fromJson(Map<String, dynamic> j) => switch (j['type']) {
    'xtream' => XtreamSource(
      XtreamCredentials.fromJson(j['credentials'] as Map<String, dynamic>),
      liveExtension: j['liveExtension'] as String? ?? 'ts',
    ),
    _ => M3uSource(
      j['location'] as String? ?? '',
      isFile: j['isFile'] as bool? ?? false,
    ),
  };
}

/// Lista M3U da indirizzo o da file.
class M3uSource extends VistaSource {
  const M3uSource(this.location, {this.isFile = false});

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
  Map<String, dynamic> toJson() => {
    'type': 'm3u',
    'location': location,
    'isFile': isFile,
  };
}

/// Account Xtream Codes.
class XtreamSource extends VistaSource {
  const XtreamSource(this.credentials, {this.liveExtension = 'ts'});

  final XtreamCredentials credentials;
  final String liveExtension;

  @override
  String get label => '${credentials.username} · ${credentials.host}';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'xtream',
    'credentials': credentials.toJson(),
    'liveExtension': liveExtension,
  };
}

/// Fonte + catalogo pronto da mostrare.
class Library {
  const Library(this.source, this.catalog);
  final VistaSource source;
  final Catalog catalog;
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

/// Salva la fonte e la cache dei contenuti (offline-first).
///
/// La configurazione (URL della lista, credenziali Xtream) sta nel portachiavi
/// del sistema: Keystore su Android, Gestione credenziali su Windows. Nella
/// cartella privata dell'app restano solo i contenuti in cache.
///
/// TODO(sync): con l'account, URL e credenziali andranno cifrati sul
/// dispositivo prima dell'invio a Supabase.
class SourceStore {
  static const _sourceKey = 'vista.source';
  static const _m3uCache = 'catalog.m3u';
  static const _xtreamCache = 'catalog.xtream.json';
  static const _prefsFile = 'channel_prefs.json';

  final _secure = const FlutterSecureStorage();

  /// Fonte e catalogo correnti: le schermate lo ascoltano e si aggiornano
  /// da sole (nuova lista, aggiornamento, canali rinominati o uniti).
  final library = ValueNotifier<Library?>(null);

  /// Nomi, loghi e unioni scelti dall'utente. Restano anche cambiando fonte.
  ChannelPrefs prefs = const ChannelPrefs();

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Fonte salvata e catalogo dalla cache, oppure `null` al primo avvio.
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
    var raw = await _secure.read(key: _sourceKey);
    // Se la cache c'è ma la lettura torna vuota (visto una volta su Windows
    // all'avvio), si riprova un attimo dopo prima di chiedere la fonte.
    if (raw == null &&
        (await (await _file(_m3uCache)).exists() ||
            await (await _file(_xtreamCache)).exists())) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      raw = await _secure.read(key: _sourceKey);
    }
    if (raw == null) return null;
    final source = VistaSource.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return _publish(await _fromCache(source) ?? await refresh(source));
  }

  /// Salva le preferenze e ricostruisce il catalogo dalla cache.
  Future<void> updatePrefs(ChannelPrefs next) async {
    prefs = next;
    await (await _file(_prefsFile)).writeAsString(jsonEncode(next.toJson()));
    final current = library.value;
    if (current == null) return;
    final lib = await _fromCache(current.source);
    if (lib != null) _publish(lib);
  }

  Future<Library?> _fromCache(VistaSource source) async {
    switch (source) {
      case M3uSource():
        final f = await _file(_m3uCache);
        if (!await f.exists()) return null;
        return Library(source, await _buildM3u(await f.readAsString()));
      case XtreamSource():
        final f = await _file(_xtreamCache);
        if (!await f.exists()) return null;
        final data = XtreamData.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
        return Library(source, await _buildXtream(data, source));
    }
  }

  Library _publish(Library lib) => library.value = lib;

  /// Lista M3U letta da un file scelto dall'utente.
  Future<Library> importM3uFile(String name, List<int> bytes) => _saveM3u(
    utf8.decode(bytes, allowMalformed: true),
    M3uSource(name, isFile: true),
  );

  /// Lista M3U da indirizzo. Un link `get.php` di un pannello Xtream passa
  /// dall'API Xtream, che dà anche locandine, trame ed episodi.
  Future<Library> importM3uUrl(String url) async {
    final xtream = xtreamFromM3uUrl(url);
    if (xtream != null) return loginXtream(xtream);
    final uri = _checkedUri(url);
    return _saveM3u(await _get(uri), M3uSource(uri.toString()));
  }

  Future<Library> loginXtream(XtreamCredentials c) async {
    if (!c.isComplete) {
      throw SourceException('Inserisci server, nome utente e password.');
    }
    _checkedUri(c.server);
    final client = XtreamClient(c, _get);
    final account = await _xtream(client.login);
    return _saveXtream(
      XtreamSource(c, liveExtension: account.liveExtension),
      await _xtream(client.fetchData),
    );
  }

  /// Scarica di nuovo i contenuti. Una lista da file non si può aggiornare.
  Future<Library> refresh(VistaSource source) async {
    switch (source) {
      case M3uSource(isFile: true):
        throw SourceException(
          'Questa lista viene da un file: per aggiornarla scegli di nuovo il file.',
        );
      case M3uSource(:final location):
        return _saveM3u(await _get(_checkedUri(location)), source);
      case XtreamSource(:final credentials):
        final data = await _xtream(XtreamClient(credentials, _get).fetchData);
        return _saveXtream(source, data);
    }
  }

  /// Episodi di una serie Xtream (le liste M3U li hanno già).
  Future<List<Episode>> episodes(VistaSource source, Series series) async =>
      (await seriesInfo(source, series)).episodes;

  final _seriesInfo = <String, SeriesInfo>{};
  final _movieInfo = <String, TitleDetails>{};

  /// Dettagli ed episodi di una serie; con Xtream chiesti una volta per
  /// sessione, con M3U ci sono solo gli episodi della lista.
  Future<SeriesInfo> seriesInfo(VistaSource source, Series series) async {
    if (source is! XtreamSource) {
      return SeriesInfo(TitleDetails.empty, series.episodes);
    }
    final cached = _seriesInfo[series.id];
    if (cached != null) return cached;
    final client = XtreamClient(source.credentials, _get);
    return _seriesInfo[series.id] = await _xtream(
      () => client.seriesInfo(series.id),
    );
  }

  /// Dettagli di un film (solo Xtream; altrimenti vuoti).
  Future<TitleDetails> movieDetails(VistaSource source, Movie movie) async {
    if (source is! XtreamSource) return TitleDetails.empty;
    final cached = _movieInfo[movie.id];
    if (cached != null) return cached;
    final client = XtreamClient(source.credentials, _get);
    return _movieInfo[movie.id] = await _xtream(
      () => client.movieDetails(movie.id),
    );
  }

  Future<void> clear() async {
    _seriesInfo.clear();
    _movieInfo.clear();
    await _secure.delete(key: _sourceKey);
    for (final n in [_m3uCache, _xtreamCache]) {
      final f = await _file(n);
      if (await f.exists()) await f.delete();
    }
    library.value = null;
  }

  // ---------------------------------------------------------------------------

  Future<Library> _saveM3u(String text, M3uSource source) async {
    final catalog = await _buildM3u(text);
    if (catalog.isEmpty) {
      throw SourceException(
        'Nessun contenuto trovato: il file non sembra una lista M3U valida.',
      );
    }
    await (await _file(_m3uCache)).writeAsString(text);
    await _remember(source, _xtreamCache);
    return _publish(Library(source, catalog));
  }

  Future<Library> _saveXtream(XtreamSource source, XtreamData data) async {
    final catalog = await _buildXtream(data, source);
    if (catalog.isEmpty) {
      throw SourceException('L\'account non contiene canali, film o serie.');
    }
    await (await _file(_xtreamCache)).writeAsString(jsonEncode(data.toJson()));
    await _remember(source, _m3uCache);
    return _publish(Library(source, catalog));
  }

  Future<void> _remember(VistaSource source, String staleCache) async {
    await _secure.write(key: _sourceKey, value: jsonEncode(source.toJson()));
    final f = await _file(staleCache);
    if (await f.exists()) await f.delete();
  }

  /// Le liste grandi (decine di migliaia di voci) si elaborano fuori dal
  /// thread dell'interfaccia; unioni, nomi e loghi dell'utente inclusi.
  /// (Statiche: le funzioni inviate all'isolate non devono catturare lo store.)
  Future<Catalog> _buildM3u(String text) => _isolateM3u(text, prefs);

  Future<Catalog> _buildXtream(XtreamData data, XtreamSource s) =>
      _isolateXtream(data, s.credentials, s.liveExtension, prefs);

  static Future<Catalog> _isolateM3u(String text, ChannelPrefs prefs) =>
      Isolate.run(
        () => _withPrefs(
          buildM3uCatalog(parseM3u(text), merges: prefs.merges),
          prefs,
        ),
      );

  static Future<Catalog> _isolateXtream(
    XtreamData data,
    XtreamCredentials creds,
    String ext,
    ChannelPrefs prefs,
  ) => Isolate.run(
    () => _withPrefs(
      buildXtreamCatalog(data, creds, liveExtension: ext, merges: prefs.merges),
      prefs,
    ),
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

  Future<String> _get(Uri uri) async {
    final http.Response res;
    // I messaggi non riportano mai l'URL: con Xtream contiene la password.
    try {
      res = await http
          .get(uri, headers: {'User-Agent': 'Vista/0.1'})
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
