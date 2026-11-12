import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Immagine di rete con copia su disco: locandine e loghi si scaricano una
/// volta sola, poi si leggono dalla cache dell'app (anche dopo un riavvio).
///
/// Si usa dentro [ResizeImage] per decodificarla già alla misura giusta.
@immutable
class CachedNetImage extends ImageProvider<CachedNetImage> {
  const CachedNetImage(this.url);

  final String url;

  @override
  Future<CachedNetImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedNetImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'immagine di rete',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await ImageDiskCache.instance.bytes(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is CachedNetImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Cartella delle immagini scaricate, con un limite di spazio: oltre
/// [_maxBytes] all'avvio si tolgono le più vecchie.
class ImageDiskCache {
  ImageDiskCache._();

  static final instance = ImageDiskCache._();

  static const _maxBytes = 300 * 1024 * 1024;
  static const _trimTo = 200 * 1024 * 1024;

  final _client = http.Client();
  final _inflight = <String, Future<Uint8List>>{};
  Future<Directory>? _dir;

  Future<Directory> get _folder => _dir ??= _open();

  Future<Directory> _open() async {
    final base = await getApplicationCacheDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}immagini');
    await d.create(recursive: true);
    unawaited(_trim(d));
    return d;
  }

  /// I byte dell'immagine: dal disco se c'è, altrimenti dalla rete (e poi
  /// salvata). Più richieste della stessa immagine ne fanno una sola.
  Future<Uint8List> bytes(String url) =>
      _inflight[url] ??= _fetch(url).whenComplete(() {
        // Graffe necessarie: `remove` restituisce questo stesso Future e
        // whenComplete lo aspetterebbe, bloccandosi per sempre.
        _inflight.remove(url);
      });

  Future<Uint8List> _fetch(String url) async {
    final d = await _folder;
    final f = File('${d.path}${Platform.pathSeparator}${_name(url)}');
    try {
      if (await f.exists()) {
        final b = await f.readAsBytes();
        if (b.isNotEmpty) return b;
      }
    } on FileSystemException {
      // File illeggibile: si riscarica.
    }
    final uri = Uri.parse(url);
    // Intestazioni predefinite di Dart: alcuni server di loghi (es.
    // Wikimedia) rifiutano agenti sconosciuti.
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw NetworkImageLoadException(statusCode: res.statusCode, uri: uri);
    }
    unawaited(_save(f, res.bodyBytes));
    return res.bodyBytes;
  }

  /// Scrive su un file temporaneo e poi lo rinomina: mai file a metà.
  Future<void> _save(File f, Uint8List bytes) async {
    final tmp = File('${f.path}.part');
    try {
      await tmp.writeAsBytes(bytes);
      await tmp.rename(f.path);
    } on FileSystemException {
      // Disco pieno o cartella sparita: l'immagine resta solo in memoria.
    }
  }

  /// Nome del file: impronta FNV-1a a 64 bit dell'indirizzo (l'indirizzo
  /// non finisce sul disco).
  static String _name(String url) {
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h.toUnsigned(63).toRadixString(16)}.img';
  }

  Future<void> _trim(Directory d) async {
    try {
      final files = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in d.list()) {
        if (e is! File) continue;
        final s = await e.stat();
        files.add((e, s.size, s.modified));
        total += s.size;
      }
      if (total <= _maxBytes) return;
      files.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (f, size, _) in files) {
        if (total <= _trimTo) break;
        try {
          await f.delete();
          total -= size;
        } on FileSystemException {
          // In uso: si riprova al prossimo avvio.
        }
      }
    } on FileSystemException {
      // Cartella non leggibile: niente pulizia questa volta.
    }
  }
}
