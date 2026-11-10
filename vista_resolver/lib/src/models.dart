import 'normalize.dart' as normalize show monogram;

String _monogram(String name) => normalize.monogram(name);

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

/// Tipo di contenuto di una voce: canale in diretta, film o episodio di serie.
enum ContentKind { live, movie, series }

/// Una voce `#EXTINF` + URL di una lista M3U.
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId = '',
    this.logo = '',
    this.group = 'Altri',
    this.declaredType = '',
  });

  final String name;
  final String url;
  final String tvgId;
  final String logo;
  final String group;

  /// Tipo dichiarato dalla lista (`tvg-type` o `type`), spesso assente.
  final String declaredType;

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
    this.customLogo = '',
    this.renamed = false,
    this.hidden = false,
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

  /// Primo `tvg-logo` trovato fra le voci.
  final String logo;

  /// Logo scelto dall'utente: vince su tutto il resto.
  final String customLogo;

  /// Il nome è stato cambiato dall'utente.
  final bool renamed;

  /// Nascosto dall'utente: non compare in Live né nella guida, solo nelle
  /// impostazioni dei canali.
  final bool hidden;

  bool get isMerged => sourceNames.length > 1;
  Quality get bestQuality => streams.first.quality;

  Channel copyWith({String? name, String? customLogo, bool? renamed, bool? hidden}) =>
      Channel(
        key: key,
        number: number,
        name: name ?? this.name,
        monogram: name == null ? monogram : _monogram(name),
        group: group,
        streams: streams,
        sourceNames: sourceNames,
        tvgId: tvgId,
        logo: logo,
        customLogo: customLogo ?? this.customLogo,
        renamed: renamed ?? this.renamed,
        hidden: hidden ?? this.hidden,
      );
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

/// Un film (on demand).
class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.url,
    this.poster = '',
    this.group = 'Altri',
    this.year,
    this.rating = '',
    this.plot = '',
  });

  final String id;
  final String title;
  final String url;
  final String poster;
  final String group;
  final int? year;
  final String rating;
  final String plot;
}

/// Un episodio di una serie.
class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.url,
    required this.season,
    required this.number,
    this.plot = '',
    this.image = '',
    this.duration,
  });

  final String id;
  final String title;
  final String url;
  final int season;
  final int number;
  final String plot;
  final String image;
  final Duration? duration;

  /// `S01E02`.
  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
}

/// Una serie. Con le liste M3U gli episodi sono già noti; con Xtream
/// arrivano a richiesta (`get_series_info`) e [episodes] parte vuoto.
class Series {
  const Series({
    required this.id,
    required this.title,
    this.poster = '',
    this.group = 'Altri',
    this.year,
    this.rating = '',
    this.plot = '',
    this.episodes = const [],
  });

  final String id;
  final String title;
  final String poster;
  final String group;
  final int? year;
  final String rating;
  final String plot;
  final List<Episode> episodes;

  Series withEpisodes(List<Episode> eps) => Series(
        id: id,
        title: title,
        poster: poster,
        group: group,
        year: year,
        rating: rating,
        plot: plot,
        episodes: eps,
      );
}

/// Tutto ciò che offre una fonte: canali risolti, film e serie.
class Catalog {
  const Catalog({
    required this.live,
    this.movies = const [],
    this.series = const [],
  });

  final ResolveResult live;
  final List<Movie> movies;
  final List<Series> series;

  bool get isEmpty =>
      live.channels.isEmpty && movies.isEmpty && series.isEmpty;
}
