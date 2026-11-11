import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

import 'source_store.dart';

/// Guida TV (EPG) della fonte corrente.
///
/// Fonti in ordine di priorità: la guida di Vista ([defaultEpgUri], XMLTV di
/// epg.lat) e, come riserva, quella della lista (`x-tvg-url` per le M3U,
/// `xmltv.php` per Xtream). I file restano in cache e si riscaricano dopo
/// [_maxAge]; in memoria si tengono solo i programmi delle prossime ore.
class EpgStore {
  EpgStore(this.sources) {
    sources.library.addListener(_onLibrary);
    _onLibrary();
  }

  static const _maxAge = Duration(hours: 6);

  final SourceStore sources;
  final guide = ValueNotifier<EpgGuide>(EpgGuide.empty);

  /// Stato da mostrare (guida vecchia, non disponibile…), vuoto se tutto ok.
  final status = ValueNotifier<String>('');

  int _generation = 0;

  void dispose() => sources.library.removeListener(_onLibrary);

  /// URL delle guide per una fonte, in ordine di priorità.
  static List<Uri> urisFor(Library lib) => [
    defaultEpgUri,
    ...switch (lib.source) {
      XtreamSource(:final credentials) => [
        Uri.parse('${credentials.server}/xmltv.php').replace(
          queryParameters: {
            'username': credentials.username,
            'password': credentials.password,
          },
        ),
      ],
      M3uSource() => [
        for (final u in lib.catalog.live.report.epgUrl.split(','))
          if (Uri.tryParse(u.trim()) case final uri?
              when uri.isScheme('http') || uri.isScheme('https'))
            uri,
      ],
    },
  ];

  void _onLibrary() {
    final lib = sources.library.value;
    final gen = ++_generation;
    if (lib == null || lib.catalog.live.channels.isEmpty) {
      guide.value = EpgGuide.empty;
      return;
    }
    unawaited(_load(lib, gen));
  }

  /// Aggiorna subito le guide, anche se la cache è recente.
  Future<void> refresh() async {
    final lib = sources.library.value;
    if (lib != null) await _load(lib, ++_generation, force: true);
  }

  Future<void> _load(Library lib, int gen, {bool force = false}) async {
    final uris = urisFor(lib);
    final dir = await getApplicationSupportDirectory();
    final files = [
      for (var i = 0; i < uris.length; i++)
        File('${dir.path}${Platform.pathSeparator}epg_$i.xml'),
    ];

    // 1. Subito quello che c'è in cache.
    await _publish(gen, uris, files);

    // 2. Poi riscarica i file vecchi o di un'altra fonte.
    var changed = false;
    for (var i = 0; i < uris.length; i++) {
      if (gen != _generation) return;
      if (!force && await _fresh(files[i], uris[i])) continue;
      changed |= await _download(uris[i], files[i]);
    }
    if (changed) await _publish(gen, uris, files);
  }

  Future<void> _publish(int gen, List<Uri> uris, List<File> files) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(const Duration(hours: 3));
    final to = now.add(const Duration(hours: 30));
    final data = <EpgData>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (!await f.exists() || !await _sameSource(f, uris[i])) {
        data.add(EpgData.empty);
        continue;
      }
      final path = f.path;
      try {
        data.add(
          await Isolate.run(
            () => parseXmltv(File(path).openRead(), from: from, to: to),
          ),
        );
      } catch (_) {
        data.add(EpgData.empty);
      }
    }
    if (gen != _generation) return;
    guide.value = EpgGuide(data);
    status.value = _describe(data, now);
  }

  String _describe(List<EpgData> data, DateTime now) {
    final main = data.isEmpty ? EpgData.empty : data.first;
    final listHasData = data.skip(1).any((d) => d.programmes.isNotEmpty);
    if (main.programmes.isEmpty) {
      return listHasData
          ? 'Guida epg.lat non disponibile: uso quella della lista.'
          : 'Guida TV non disponibile al momento.';
    }
    return '';
  }

  // --- cache ------------------------------------------------------------------

  /// Il file .meta ricorda quando e da quale URL (solo un'impronta, non l'URL:
  /// con Xtream contiene la password) è stato scaricato.
  File _meta(File f) => File('${f.path}.meta');

  static String _fingerprint(Uri u) => u.toString().hashCode.toRadixString(16);

  Future<bool> _sameSource(File f, Uri u) async {
    try {
      final m =
          jsonDecode(await _meta(f).readAsString()) as Map<String, dynamic>;
      return m['source'] == _fingerprint(u);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fresh(File f, Uri u) async {
    if (!await f.exists() || !await _sameSource(f, u)) return false;
    try {
      final m =
          jsonDecode(await _meta(f).readAsString()) as Map<String, dynamic>;
      final at = DateTime.tryParse(m['at'] as String? ?? '');
      return at != null && DateTime.now().difference(at) < _maxAge;
    } catch (_) {
      return false;
    }
  }

  /// Scarica a flusso su un file temporaneo e lo sostituisce solo se è
  /// andato a buon fine. Gli errori restano silenziosi (e senza URL).
  Future<bool> _download(Uri u, File target) async {
    final tmp = File('${target.path}.part');
    final client = http.Client();
    try {
      final req = http.Request('GET', u)..headers['User-Agent'] = 'Vista/0.1';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      final sink = tmp.openWrite();
      await res.stream.timeout(const Duration(seconds: 60)).pipe(sink);
      if (await tmp.length() < 64) return false;
      await tmp.rename(target.path);
      await _meta(target).writeAsString(
        jsonEncode({
          'source': _fingerprint(u),
          'at': DateTime.now().toIso8601String(),
        }),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
      if (await tmp.exists()) await tmp.delete();
    }
  }
}
