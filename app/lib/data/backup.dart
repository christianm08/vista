import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import 'image_cache.dart';

/// Backup delle impostazioni in un file JSON.
///
/// Contiene preferiti, avanzamento, servizi, preferenze del player, canali
/// (nomi, numeri, categorie, nascosti, unioni), spostamento degli orari della
/// guida e i blocchi del controllo genitori. **Non** contiene credenziali né
/// indirizzi: la fonte, la chiave TMDB, il link personale della guida (può
/// avere una password) e il PIN restano solo sul dispositivo.
abstract final class Backup {
  static const _format = 'vista-backup';

  static Map<String, dynamic> create(AppScope app) => {
    'format': _format,
    'version': 1,
    'createdAt': DateTime.now().toIso8601String(),
    'user': app.user.toJson(),
    'channels': app.store.prefs.toJson(),
    'guide': {'shift': app.epg.shift.value.inMinutes},
    'parental': app.parental.toBackup(),
  };

  /// Salva il backup dove sceglie l'utente. Restituisce dove è finito
  /// (`null` se annullato). Se il sistema non ha una finestra per scegliere
  /// (alcune TV), lo salva nella cartella dell'app.
  static Future<String?> save(AppScope app) async {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(create(app))),
    );
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'vista-backup-${d.year}${two(d.month)}${two(d.day)}.json';
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Salva il backup di Vista',
      );
      if (uri == null) return null;
      return uri.isScheme('file') ? uri.toFilePath() : name;
    } catch (_) {
      final dir =
          (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
          await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsBytes(bytes);
      return f.path;
    }
  }

  /// Fa scegliere un file di backup e lo legge. `null` se annullato; lancia
  /// [FormatException] se non è un backup di Vista.
  static Future<Map<String, dynamic>?> pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Scegli un backup di Vista',
    );
    if (files.isEmpty) return null;
    final j = jsonDecode(utf8.decode(await files.first.readAsBytes()));
    if (j is! Map<String, dynamic> || j['format'] != _format) {
      throw const FormatException('Questo file non è un backup di Vista.');
    }
    return j;
  }

  /// Applica un backup (sostituisce le impostazioni attuali).
  static Future<void> restore(AppScope app, Map<String, dynamic> j) async {
    if (j['user'] case final Map<String, dynamic> u) {
      await app.user.restore(u);
    }
    if (j['channels'] case final Map<String, dynamic> c) {
      await app.store.updatePrefs(ChannelPrefs.fromJson(c));
    }
    if (j['guide'] case {'shift': final int minutes}) {
      await app.epg.setShift(Duration(minutes: minutes));
    }
    if (j['parental'] case final Map<String, dynamic> p) {
      // I blocchi valgono solo se su questo dispositivo c'è un PIN.
      await app.parental.restore(p);
    }
  }
}

/// Spazio usato dalle cache (immagini, guide TV, dati di TMDB) e pulizia.
abstract final class CacheCleaner {
  static Future<List<File>> _files() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final out = <File>[];
    Future<void> scan(Directory d, bool Function(String name) keep) async {
      if (!await d.exists()) return;
      await for (final e in d.list()) {
        if (e is File && keep(e.uri.pathSegments.last)) out.add(e);
      }
    }

    await scan(
      support,
      (n) =>
          n.startsWith('epg_') ||
          (n.startsWith('tmdb_') && n.endsWith('.json')),
    );
    await scan(
      Directory('${cache.path}${Platform.pathSeparator}immagini'),
      (_) => true,
    );
    return out;
  }

  /// Byte occupati dalle cache.
  static Future<int> size() async {
    var total = 0;
    for (final f in await _files()) {
      try {
        total += await f.length();
      } on FileSystemException {
        // Sparito nel frattempo.
      }
    }
    return total;
  }

  /// Cancella le cache (anche le immagini in memoria) e riscarica la guida.
  static Future<void> clear(AppScope app) async {
    for (final f in await _files()) {
      try {
        await f.delete();
      } on FileSystemException {
        // In uso: resterà fino alla prossima pulizia.
      }
    }
    ImageDiskCache.instance.forget();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await app.epg.refresh();
  }

  static String format(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
