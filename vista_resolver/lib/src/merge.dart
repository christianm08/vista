import 'models.dart';
import 'resolver.dart' show sortStreamsByQuality;

/// Unisce i cataloghi di più fonti (liste M3U e account Xtream) in uno solo.
///
/// - Canali: lo stesso canale (stessa chiave normalizzata) presente in più
///   fonti diventa un canale solo con tutti i flussi, ordinati per qualità:
///   se una fonte si blocca il player passa all'altra. Valgono nome,
///   categoria e logo della prima fonte che ha il canale; i numeri si
///   riassegnano in ordine.
/// - Film e serie: restano separati, con [idPrefix] davanti agli ID (anche
///   degli episodi) per non confondere titoli di fonti diverse. La fonte con
///   prefisso vuoto tiene gli ID originali.
Catalog mergeCatalogs(List<(String idPrefix, Catalog catalog)> parts) {
  if (parts.isEmpty) {
    return const Catalog(
      live: ResolveResult(
        [],
        ResolveReport(entries: 0, channels: 0, merged: 0, epgUrl: ''),
      ),
    );
  }
  if (parts.length == 1 && parts.first.$1.isEmpty) return parts.first.$2;

  final index = <String, int>{};
  final channels = <Channel>[];
  var entries = 0;
  final epg = <String>[];
  for (final (_, c) in parts) {
    entries += c.live.report.entries;
    if (c.live.report.epgUrl.isNotEmpty) epg.add(c.live.report.epgUrl);
    for (final ch in c.live.channels) {
      final i = index[ch.key];
      if (i == null) {
        index[ch.key] = channels.length;
        channels.add(ch);
        continue;
      }
      final a = channels[i];
      final seen = {for (final s in a.streams) s.url};
      final streams = [
        ...a.streams,
        for (final s in ch.streams)
          if (seen.add(s.url)) s,
      ];
      sortStreamsByQuality(streams);
      channels[i] = Channel(
        key: a.key,
        number: a.number,
        name: a.name,
        monogram: a.monogram,
        group: a.group,
        streams: streams,
        sourceNames: [...a.sourceNames, ...ch.sourceNames],
        tvgId: a.tvgId.isNotEmpty ? a.tvgId : ch.tvgId,
        logo: a.logo.isNotEmpty ? a.logo : ch.logo,
      );
    }
  }
  final numbered = [
    for (var i = 0; i < channels.length; i++) channels[i].copyWith(number: i + 1),
  ];
  return Catalog(
    live: ResolveResult(
      numbered,
      ResolveReport(
        entries: entries,
        channels: numbered.length,
        merged: numbered.where((c) => c.isMerged).length,
        epgUrl: epg.join(','),
      ),
    ),
    movies: [
      for (final (p, c) in parts)
        for (final m in c.movies) p.isEmpty ? m : m.withId('$p${m.id}'),
    ],
    series: [
      for (final (p, c) in parts)
        for (final s in c.series) s.withIdPrefix(p),
    ],
  );
}
