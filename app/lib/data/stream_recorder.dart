import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Registra un flusso su file scaricandolo, senza ricodificare.
///
/// - Flusso continuo (Xtream `.ts`, MPEG-TS via HTTP): i byte si scrivono
///   così come arrivano.
/// - HLS (`.m3u8`): si sceglie la qualità più alta che rispetta [maxHeight]
///   e [maxBandwidth] (per occupare meno spazio) e si scaricano i segmenti
///   man mano che compaiono nella playlist; i segmenti TS si accodano in un
///   `.ts`, quelli fMP4 (con `EXT-X-MAP`) in un `.mp4` frammentato.
///
/// Usa una connessione in più verso il fornitore. Gli errori non riportano
/// mai l'indirizzo (può contenere credenziali).
class StreamRecorder {
  StreamRecorder(
    this.url,
    this.basePath, {
    this.headers,
    this.maxHeight,
    this.maxBandwidth,
  });

  final String url;

  /// Limiti per scegliere la variante HLS (`null` = la migliore).
  final int? maxHeight;
  final int? maxBandwidth;

  /// Percorso senza estensione: l'estensione dipende dal formato.
  final String basePath;
  final Map<String, String>? headers;

  // HttpClient di dart:io: dice l'indirizzo finale dopo i reindirizzamenti
  // (i pannelli spesso rimandano al server vero), che serve per trovare i
  // segmenti HLS indicati con percorsi relativi.
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  bool _stopped = false;
  int _written = 0;
  File? _file;
  IOSink? _sink;
  final _done = Completer<void>();

  /// Il file scritto (noto dopo [start]).
  File? get file => _file;

  /// Byte scritti finora.
  int get written => _written;

  bool get isRunning => !_stopped;

  /// Finisce quando la registrazione si ferma (anche per un errore).
  Future<void> get done => _done.future;

  /// Avvia la registrazione; si completa quando è partita (o lancia se il
  /// flusso non risponde).
  Future<void> start() async {
    final (res, finalUri) = await _request(Uri.parse(url));
    if (res.statusCode != 200) {
      _client.close(force: true);
      throw StateError('Il flusso ha risposto ${res.statusCode}.');
    }
    final type = res.headers.contentType?.mimeType ?? '';
    final isHls =
        finalUri.path.toLowerCase().endsWith('.m3u8') ||
        type.contains('mpegurl') ||
        type.contains('m3u');
    if (!isHls) {
      _open('.ts');
      unawaited(_pipe(res));
      return;
    }
    final text = await utf8.decodeStream(res);
    unawaited(_hls(finalUri, text));
  }

  /// GET con le intestazioni scelte; restituisce la risposta e l'indirizzo
  /// finale (dopo i reindirizzamenti).
  Future<(HttpClientResponse, Uri)> _request(Uri u) async {
    final req = await _client.getUrl(u).timeout(const Duration(seconds: 20));
    headers?.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 20));
    var finalUri = u;
    for (final r in res.redirects) {
      finalUri = finalUri.resolveUri(r.location);
    }
    return (res, finalUri);
  }

  void _open(String ext) {
    _file = File('$basePath$ext');
    _sink = _file!.openWrite();
  }

  Future<void> _pipe(Stream<List<int>> body) async {
    try {
      await for (final chunk in body) {
        if (_stopped) break;
        _sink!.add(chunk);
        _written += chunk.length;
      }
    } catch (_) {
      // Connessione caduta: si chiude il file con quello che c'è.
    } finally {
      await _finish();
    }
  }

  Future<(String, Uri)> _getText(Uri u) async {
    final (r, finalUri) = await _request(u);
    if (r.statusCode != 200) {
      await r.drain<void>();
      throw StateError('HTTP ${r.statusCode}');
    }
    return (await utf8.decodeStream(r), finalUri);
  }

  Future<void> _hls(Uri playlistUri, String text) async {
    try {
      var uri = playlistUri;
      var body = text;
      // Playlist principale: la variante con la banda più alta.
      if (body.contains('#EXT-X-STREAM-INF')) {
        (body, uri) = await _getText(_bestVariant(uri, body));
      }
      var lastSeq = -1;
      var mapWritten = false;
      while (!_stopped) {
        final lines = body.split('\n').map((l) => l.trim()).toList();
        var seq = 0;
        var target = 6;
        String? map;
        final segments = <Uri>[];
        for (final l in lines) {
          if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
            seq = int.tryParse(l.split(':').last) ?? 0;
          } else if (l.startsWith('#EXT-X-TARGETDURATION:')) {
            target = int.tryParse(l.split(':').last) ?? 6;
          } else if (l.startsWith('#EXT-X-MAP:')) {
            final m = RegExp(r'URI="([^"]+)"').firstMatch(l);
            if (m != null) map = m.group(1);
          } else if (l.isNotEmpty && !l.startsWith('#')) {
            segments.add(uri.resolve(l));
          }
        }
        if (_sink == null) _open(map != null ? '.mp4' : '.ts');
        if (map != null && !mapWritten) {
          _add(await _bytes(uri.resolve(map)));
          mapWritten = true;
        }
        for (var i = 0; i < segments.length && !_stopped; i++) {
          final n = seq + i;
          // Al primo giro si parte dagli ultimi segmenti (il "live").
          if (lastSeq < 0 && i < segments.length - 3) continue;
          if (n <= lastSeq) continue;
          _add(await _bytes(segments[i]));
          lastSeq = n;
        }
        if (body.contains('#EXT-X-ENDLIST')) break;
        await Future<void>.delayed(
          Duration(milliseconds: (target * 1000 / 2).round().clamp(1000, 6000)),
        );
        if (_stopped) break;
        (body, uri) = await _getText(uri);
      }
    } catch (_) {
      // Rete o server: si chiude il file con quello che c'è.
    } finally {
      await _finish();
    }
  }

  void _add(List<int> bytes) {
    _sink!.add(bytes);
    _written += bytes.length;
  }

  /// La variante più ricca che sta nei limiti; se nessuna ci sta, la più
  /// leggera.
  Uri _bestVariant(Uri base, String master) {
    final variants = parseHlsVariants(master);
    if (variants.isEmpty) return base;
    bool fits(HlsVariant v) =>
        (maxHeight == null || v.height == 0 || v.height <= maxHeight!) &&
        (maxBandwidth == null || v.bandwidth <= maxBandwidth!);
    final ok = variants.where(fits).toList()
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    if (ok.isNotEmpty) return base.resolve(ok.first.uri);
    variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
    return base.resolve(variants.first.uri);
  }

  Future<List<int>> _bytes(Uri u) async {
    final (r, _) = await _request(u);
    if (r.statusCode != 200) {
      await r.drain<void>();
      throw StateError('HTTP ${r.statusCode}');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in r.timeout(const Duration(seconds: 30))) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  Future<void> _finish() async {
    _stopped = true;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // File già chiuso.
    }
    _client.close(force: true);
    if (!_done.isCompleted) _done.complete();
  }

  /// Ferma la registrazione e chiude il file.
  Future<void> stop() async {
    if (_stopped) return done;
    _stopped = true;
    // Il ciclo HLS o il flusso si accorgono dello stop e chiudono il file.
    _client.close(force: true);
    await done.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (!_done.isCompleted) await _finish();
  }
}

/// Una variante di una playlist HLS principale.
class HlsVariant {
  const HlsVariant(this.uri, this.bandwidth, this.height);
  final String uri;

  /// Bit al secondo dichiarati.
  final int bandwidth;

  /// Altezza in pixel (0 se la playlist non la dice).
  final int height;
}

/// Le varianti di una playlist HLS principale (`#EXT-X-STREAM-INF`).
List<HlsVariant> parseHlsVariants(String master) {
  final lines = master.split('\n').map((l) => l.trim()).toList();
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length - 1; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    final info = lines[i];
    final bw =
        int.tryParse(
          RegExp(r'BANDWIDTH=(\d+)').firstMatch(info)?.group(1) ?? '',
        ) ??
        0;
    final h =
        int.tryParse(
          RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(info)?.group(1) ?? '',
        ) ??
        0;
    final next = lines
        .skip(i + 1)
        .firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('#'),
          orElse: () => '',
        );
    if (next.isNotEmpty) out.add(HlsVariant(next, bw, h));
  }
  return out;
}
