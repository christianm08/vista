import 'models.dart';

final _headerEpg = RegExp(r'(?:x-tvg-url|url-tvg)="([^"]*)"', caseSensitive: false);
final _attr = RegExp(r'([\w-]+)="([^"]*)"');
final _newline = RegExp(r'\r?\n');

/// Legge una lista M3U/M3U8 estesa.
///
/// Riconosce `x-tvg-url`/`url-tvg` nell'intestazione e, per ogni `#EXTINF`,
/// `tvg-id`, `tvg-logo`, `group-title` e il nome dopo l'ultima virgola.
/// Le altre righe che iniziano con `#` (es. `#EXTVLCOPT`) vengono ignorate.
M3uPlaylist parseM3u(String text) {
  var epgUrl = '';
  final entries = <M3uEntry>[];
  _Pending? cur;

  for (final raw in text.split(_newline)) {
    final line = raw.replaceAll('﻿', '').trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTM3U')) {
      final m = _headerEpg.firstMatch(line);
      if (m != null) epgUrl = m.group(1)!;
    } else if (line.startsWith('#EXTINF')) {
      final attrs = <String, String>{};
      for (final m in _attr.allMatches(line)) {
        attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
      }
      final ci = line.lastIndexOf(',');
      cur = _Pending(
        name: ci >= 0 ? line.substring(ci + 1).trim() : 'Senza nome',
        tvgId: attrs['tvg-id'] ?? '',
        logo: attrs['tvg-logo'] ?? '',
        group: _orDefault(attrs['group-title'], 'Altri'),
      );
    } else if (!line.startsWith('#') && cur != null) {
      entries.add(M3uEntry(
        name: cur.name,
        url: line,
        tvgId: cur.tvgId,
        logo: cur.logo,
        group: cur.group,
      ));
      cur = null;
    }
  }

  return M3uPlaylist(epgUrl: epgUrl, entries: entries);
}

String _orDefault(String? v, String d) => (v == null || v.isEmpty) ? d : v;

class _Pending {
  _Pending({
    required this.name,
    required this.tvgId,
    required this.logo,
    required this.group,
  });
  final String name;
  final String tvgId;
  final String logo;
  final String group;
}
