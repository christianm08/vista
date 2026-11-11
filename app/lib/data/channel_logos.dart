import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

/// Loghi da github.com/tv-logo/tv-logos, presi dinamicamente.
///
/// L'app non contiene né le immagini né l'indice: all'avvio legge l'elenco
/// dei file del repository dall'API di GitHub (una richiesta, al massimo una
/// volta a settimana), lo tiene in cache e carica ogni logo dal suo link raw.
abstract final class ChannelLogos {
  static const _cacheName = 'tv_logos_index.json';
  static const _maxAge = Duration(days: 7);

  /// Indice corrente; i loghi si aggiornano da soli quando arriva.
  static final notifier = ValueNotifier<TvLogos>(TvLogos.empty);
  static TvLogos get tvLogos => notifier.value;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_cacheName');
  }

  /// Usa subito la cache, se c'è, e la rinnova in background se è vecchia.
  static Future<void> init() async {
    DateTime? fetchedAt;
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        notifier.value = TvLogos(Map<String, String>.from(j['logos'] as Map));
        fetchedAt = DateTime.tryParse(j['fetchedAt'] as String? ?? '');
      }
    } catch (_) {
      // cache illeggibile: si riscarica
    }
    if (fetchedAt == null || DateTime.now().difference(fetchedAt) > _maxAge) {
      unawaited(refresh());
    }
  }

  /// Scarica di nuovo l'elenco da GitHub. Senza rete resta la cache.
  static Future<void> refresh() async {
    try {
      final res = await http
          .get(
            tvLogoTreeUri,
            headers: {
              'User-Agent': 'Vista/0.1',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final body = utf8.decode(res.bodyBytes);
      final index = await Isolate.run(
        () => buildTvLogoIndex(pathsFromGithubTree(body)),
      );
      if (index.isEmpty) return;
      notifier.value = TvLogos(index);
      await (await _file()).writeAsString(
        jsonEncode({
          'fetchedAt': DateTime.now().toIso8601String(),
          'logos': index,
        }),
      );
    } catch (_) {
      // rete assente o limite di GitHub: si riprova al prossimo avvio
    }
  }

  /// Catena dei loghi: scelto dall'utente, tv-logos, `tvg-logo` della lista.
  /// Le iniziali sono l'ultima scelta, in `ChannelLogo`.
  static List<String> candidates(Channel c) => {
    if (c.customLogo.isNotEmpty) c.customLogo,
    ?tvLogos.urlFor(c),
    if (c.logo.isNotEmpty) c.logo,
  }.toList();
}
