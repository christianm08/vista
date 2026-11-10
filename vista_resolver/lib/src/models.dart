/// Qualità di un flusso, ordinabile per [rank] (più alto = migliore).
enum Quality {
  uhd4k('4K', 4),
  fhd('FHD', 3),
  hd('HD', 2),
  sd('SD', 1),

  /// Qualità non dichiarata nel nome: andrà letta dal manifest HLS.
  auto('Auto', 0);

  const Quality(this.label, this.rank);
  final String label;
  final int rank;

  @override
  String toString() => label;
}

/// Una voce `#EXTINF` + URL di una lista M3U.
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId = '',
    this.logo = '',
    this.group = 'Altri',
  });

  final String name;
  final String url;
  final String tvgId;
  final String logo;
  final String group;

  @override
  String toString() => 'M3uEntry($name, $url)';
}

/// Risultato del parsing di una lista M3U.
class M3uPlaylist {
  const M3uPlaylist({this.epgUrl = '', this.entries = const []});

  /// `x-tvg-url` / `url-tvg` dall'intestazione `#EXTM3U`, se presente.
  final String epgUrl;
  final List<M3uEntry> entries;
}

/// Nome normalizzato + qualità riconosciuta.
class NormalizedName {
  const NormalizedName(this.key, this.quality);
  final String key;
  final Quality quality;

  @override
  bool operator ==(Object other) =>
      other is NormalizedName && other.key == key && other.quality == quality;

  @override
  int get hashCode => Object.hash(key, quality);

  @override
  String toString() => 'NormalizedName($key, ${quality.label})';
}

/// Un flusso di un canale.
class ChannelStream {
  const ChannelStream({
    required this.quality,
    required this.url,
    required this.sourceName,
  });

  final Quality quality;
  final String url;

  /// Nome originale della voce nella lista.
  final String sourceName;
}

/// Un canale risolto: più voci della lista raggruppate, con i flussi ordinati
/// dal migliore (4K) al peggiore (Auto).
class Channel {
  const Channel({
    required this.key,
    required this.number,
    required this.name,
    required this.monogram,
    required this.group,
    required this.streams,
    required this.sourceNames,
    this.tvgId = '',
    this.logo = '',
  });

  /// Nome normalizzato usato per raggruppare (es. `rai 1`).
  final String key;
  final int number;

  /// Nome da mostrare (es. `Rai 1`).
  final String name;

  /// Iniziali per il logo generato (ultima scelta nella catena dei loghi).
  final String monogram;

  /// `group-title` della prima voce.
  final String group;
  final List<ChannelStream> streams;

  /// Nomi originali di tutte le voci raggruppate (anche quelle con URL doppio).
  final List<String> sourceNames;

  /// Primo `tvg-id` trovato fra le voci, per l'abbinamento EPG.
  final String tvgId;

  /// Primo `tvg-logo` trovato fra le voci (primo anello della catena dei loghi).
  final String logo;

  bool get isMerged => sourceNames.length > 1;
  Quality get bestQuality => streams.first.quality;
}

class ResolveReport {
  const ResolveReport({
    required this.entries,
    required this.channels,
    required this.merged,
    required this.epgUrl,
  });

  final int entries;
  final int channels;

  /// Canali che raggruppano più di una voce.
  final int merged;
  final String epgUrl;
}

class ResolveResult {
  const ResolveResult(this.channels, this.report);
  final List<Channel> channels;
  final ResolveReport report;
}
