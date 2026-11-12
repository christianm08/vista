import 'models.dart';
import 'normalize.dart';

/// Aggancio per il confronto approssimato con `channels.json` di iptv-org:
/// riceve la chiave normalizzata e restituisce la chiave canonica del canale
/// (o `null` se non trova nulla). Non ancora implementato: vedi README.
typedef ChannelMatcher = String? Function(String normalizedKey);

/// Suffissi `@...` del `tvg-id` che indicano solo la qualità, non un feed.
final _qualityFeed = RegExp(
  r'^(sd|hd|fhd|uhd|4k|480p|576p|576i|720p|1080p|1080i|2160p)$',
);

/// Chiave di raggruppamento del `tvg-id`.
///
/// `Rai1.it@HD` → `rai1.it` (stesso canale). Un suffisso che non è una
/// qualità, come `Rai3.it@Lazio`, è un feed regionale secondo la convenzione
/// iptv-org e resta un canale separato: `rai3.it@lazio`.
String tvgIdKey(String tvgId) {
  final id = tvgId.trim().toLowerCase();
  final at = id.indexOf('@');
  if (at < 0) return id;
  final base = id.substring(0, at);
  final feed = id.substring(at + 1);
  if (feed.isEmpty || _qualityFeed.hasMatch(feed)) return base;
  return '$base@$feed';
}

/// Raggruppa le voci di una lista in canali.
///
/// Ordine: prima per `tvg-id` ([tvgIdKey]), poi per nome normalizzato, poi
/// l'eventuale [matcher] (iptv-org) e infine le unioni manuali [merges]
/// (chiave → chiave di destinazione, scelte dall'utente e sincronizzate).
/// Ogni canale ha i flussi senza URL doppi, ordinati 4K > FHD > HD > SD > Auto;
/// a parità di qualità resta l'ordine della lista.
ResolveResult resolveChannels(
  M3uPlaylist playlist, {
  ChannelMatcher? matcher,
  Map<String, String> merges = const {},
}) {
  final parent = <String, String>{};
  String root(String k) {
    while (parent.containsKey(k)) {
      k = parent[k]!;
    }
    return k;
  }

  // Attacca la radice di [child] a quella di [target]; la prima vista resta.
  void union(String child, String target) {
    final a = root(child);
    final b = root(target);
    if (a != b) parent[a] = b;
  }

  final prepared = [
    for (final e in playlist.entries) (entry: e, norm: normalizeName(e.name)),
  ];

  final idOwner = <String, String>{};
  for (final p in prepared) {
    if (p.entry.tvgId.isEmpty) continue;
    final idKey = tvgIdKey(p.entry.tvgId);
    final owner = idOwner[idKey];
    if (owner == null) {
      idOwner[idKey] = root(p.norm.key);
    } else {
      union(p.norm.key, owner);
    }
  }

  if (matcher != null) {
    for (final p in prepared) {
      final canonical = matcher(p.norm.key);
      if (canonical != null && canonical.isNotEmpty) {
        union(p.norm.key, canonical);
      }
    }
  }

  merges.forEach(union);

  final groups = <String, List<({M3uEntry entry, NormalizedName norm})>>{};
  for (final p in prepared) {
    groups.putIfAbsent(root(p.norm.key), () => []).add(p);
  }

  final channels = <Channel>[];
  var n = 1;
  for (final MapEntry(key: key, value: items) in groups.entries) {
    final seen = <String>{};
    final streams = <ChannelStream>[];
    for (final p in items) {
      if (!seen.add(p.entry.url)) continue;
      streams.add(ChannelStream(
        quality: p.norm.quality,
        url: p.entry.url,
        sourceName: p.entry.name,
      ));
    }
    sortStreamsByQuality(streams);

    final name = displayName(key);
    channels.add(Channel(
      key: key,
      number: n++,
      name: name,
      monogram: monogram(name),
      group: items.first.entry.group,
      streams: streams,
      sourceNames: [for (final p in items) p.entry.name],
      tvgId: items
          .map((p) => p.entry.tvgId)
          .firstWhere((id) => id.isNotEmpty, orElse: () => ''),
      logo: items
          .map((p) => p.entry.logo)
          .firstWhere((l) => l.isNotEmpty, orElse: () => ''),
    ));
  }

  return ResolveResult(
    channels,
    ResolveReport(
      entries: playlist.entries.length,
      channels: channels.length,
      merged: channels.where((c) => c.isMerged).length,
      epgUrl: playlist.epgUrl,
    ),
  );
}

/// Ordina i flussi dal migliore al peggiore, mantenendo l'ordine a parità di
/// qualità (`List.sort` di Dart non è stabile: l'indice fa da spareggio).
void sortStreamsByQuality(List<ChannelStream> streams) {
  final indexed = [for (var i = 0; i < streams.length; i++) (i, streams[i])];
  indexed.sort((a, b) {
    final c = b.$2.quality.rank.compareTo(a.$2.quality.rank);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    streams[i] = indexed[i].$2;
  }
}
