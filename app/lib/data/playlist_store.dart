import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

/// Lista caricata dall'utente (Vista non include nessuna lista).
class StoredPlaylist {
  const StoredPlaylist({required this.text, required this.source});

  /// Testo M3U.
  final String text;

  /// Da dove viene: URL o nome del file. Resta solo sul dispositivo.
  final String source;

  ResolveResult resolve() => resolveChannels(parseM3u(text));
}

class PlaylistException implements Exception {
  PlaylistException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Salva la lista nella memoria privata dell'app (offline-first).
///
/// TODO(sync): con l'account, URL e credenziali andranno cifrati sul
/// dispositivo prima dell'invio a Supabase.
class PlaylistStore {
  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<StoredPlaylist?> load() async {
    final text = await _file('playlist.m3u');
    if (!await text.exists()) return null;
    final meta = await _file('playlist.json');
    var source = '';
    if (await meta.exists()) {
      source = (jsonDecode(await meta.readAsString()) as Map)['source'] as String? ?? '';
    }
    return StoredPlaylist(text: await text.readAsString(), source: source);
  }

  Future<StoredPlaylist> save(String text, String source) async {
    if (parseM3u(text).entries.isEmpty) {
      throw PlaylistException(
          'Nessun canale trovato: il file non sembra una lista M3U valida.');
    }
    await (await _file('playlist.m3u')).writeAsString(text);
    await (await _file('playlist.json'))
        .writeAsString(jsonEncode({'source': source}));
    return StoredPlaylist(text: text, source: source);
  }

  Future<void> clear() async {
    for (final n in ['playlist.m3u', 'playlist.json']) {
      final f = await _file(n);
      if (await f.exists()) await f.delete();
    }
  }

  /// Scarica una lista da URL.
  Future<String> download(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw PlaylistException('Indirizzo non valido: deve iniziare con http:// o https://');
    }
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'User-Agent': 'Vista/0.1'})
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      throw PlaylistException('Download non riuscito: $e');
    }
    if (res.statusCode != 200) {
      throw PlaylistException('Il server ha risposto ${res.statusCode}.');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}
