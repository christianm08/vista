import 'models.dart';
import 'resolver.dart';

/// Estensioni dei file on demand. `.ts` e `.m3u8` restano live: sono i
/// formati tipici delle dirette.
const _vodExtensions = {
  'mp4', 'mkv', 'avi', 'mov', 'm4v', 'wmv', 'webm', 'mpg', 'mpeg', 'divx',
  'flv', '3gp', 'ogv',
};

final _seasonEpisode = RegExp(
  r'^(.*?)[\s._\-|:]*\bS(\d{1,2})[\s._-]?E(\d{1,4})(?!\d)(.*)$',
  caseSensitive: false,
);
final _crossEpisode = RegExp(
  r'^(.*?)[\s._\-|:]*\b(\d{1,2})x(\d{1,3})(?!\d)(.*)$',
  caseSensitive: false,
);
final _leadingSeparators = RegExp(r'^[\s._\-|:]+');
final _trailingSeparators = RegExp(r'[\s._\-|:]+$');

/// Prefisso di paese in maiuscolo, es. `IT: `, `|IT| `, `[ITA] `.
final _countryPrefix = RegExp(r'^\s*[\[(|]?\s*[A-Z]{2,3}\s*[\])|:]+\s*');
final _yearSuffix = RegExp(r'\s*[\[(]((?:19|20)\d{2})[\])]\s*$');
final _yearDash = RegExp(r'\s+-\s+((?:19|20)\d{2})\s*$');
final _spaces = RegExp(r'\s+');

final _separatorStart = RegExp(r'^\s*[#*=~_\-–—•●★☆▬►◄|]{2,}');
final _separatorEnd = RegExp(r'[#*=~_\-–—•●★☆▬►◄|]{3,}\s*$');

/// Voci "separatore" che molte liste usano come titoli di sezione
/// (`##### SPORT #####`, `*** Italy ***`): non sono canali.
bool isSeparatorEntry(String name) =>
    _separatorStart.hasMatch(name) || _separatorEnd.hasMatch(name);

/// Stagione ed episodio letti dal nome (`Serie S01E02 Titolo`, `Serie 1x02`).
typedef EpisodeMarker = ({String show, int season, int episode, String rest});

EpisodeMarker? parseEpisodeMarker(String name) {
  final m = _seasonEpisode.firstMatch(name) ?? _crossEpisode.firstMatch(name);
  if (m == null) return null;
  return (
    show: m.group(1)!.replaceAll(_trailingSeparators, '').trim(),
    season: int.parse(m.group(2)!),
    episode: int.parse(m.group(3)!),
    rest: m.group(4)!.replaceAll(_leadingSeparators, '').trim(),
  );
}

/// Toglie il prefisso di paese e separa l'anno finale: `IT: Nord (2025)` →
/// `Nord`, 2025.
({String title, int? year}) splitTitleYear(String raw) {
  var t = raw.trim().replaceFirst(_countryPrefix, '');
  int? year;
  final m = _yearSuffix.firstMatch(t) ?? _yearDash.firstMatch(t);
  if (m != null) {
    year = int.parse(m.group(1)!);
    t = t.substring(0, m.start);
  }
  t = t.replaceAll(_spaces, ' ').trim();
  return (title: t.isEmpty ? raw.trim() : t, year: year);
}

/// Decide se una voce è un canale live, un film o un episodio.
///
/// Il nome del gruppo non conta: "Rai Movie" nel gruppo "Film" resta un
/// canale. Contano, in ordine, il tipo dichiarato, il percorso dell'URL
/// (`/movie/`, `/series/`, `/live/` dei pannelli Xtream) e l'estensione.
ContentKind classifyEntry(M3uEntry e) {
  final declared = e.declaredType.toLowerCase();
  if (declared.contains('serie')) return ContentKind.series;
  if (declared.contains('movie') ||
      declared.contains('vod') ||
      declared.contains('film')) {
    return ContentKind.movie;
  }
  if (declared.contains('live') || declared.contains('channel')) {
    return ContentKind.live;
  }

  final path = (Uri.tryParse(e.url.trim())?.path ?? e.url).toLowerCase();
  if (path.contains('/series/')) return ContentKind.series;
  final ondemand = path.contains('/movie/') ||
      path.contains('/movies/') ||
      path.contains('/vod/') ||
      _vodExtensions.contains(_extension(path));
  if (path.contains('/live/') || !ondemand) return ContentKind.live;
  return parseEpisodeMarker(e.name) != null
      ? ContentKind.series
      : ContentKind.movie;
}

String _extension(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  return dot > slash ? path.substring(dot + 1) : '';
}

/// Divide una lista M3U in canali (risolti con [resolveChannels]), film e
/// serie (episodi raggruppati per titolo e ordinati per stagione/episodio).
Catalog buildM3uCatalog(
  M3uPlaylist playlist, {
  ChannelMatcher? matcher,
  Map<String, String> merges = const {},
}) {
  final live = <M3uEntry>[];
  final movies = <Movie>[];
  final movieUrls = <String>{};
  final shows = <String, _Show>{};

  void addMovie(M3uEntry e) {
    if (!movieUrls.add(e.url)) return;
    final t = splitTitleYear(e.name);
    movies.add(Movie(
      id: e.url,
      title: t.title,
      year: t.year,
      url: e.url,
      poster: e.logo,
      group: e.group,
    ));
  }

  for (final e in playlist.entries) {
    final kind = classifyEntry(e);
    if (kind == ContentKind.live) {
      if (!isSeparatorEntry(e.name)) live.add(e);
      continue;
    }
    final marker = kind == ContentKind.series ? parseEpisodeMarker(e.name) : null;
    if (marker == null) {
      addMovie(e);
      continue;
    }
    final t = splitTitleYear(marker.show.isEmpty ? e.group : marker.show);
    final key = t.title.toLowerCase();
    final show = shows.putIfAbsent(
      key,
      () => _Show(title: t.title, year: t.year, group: e.group),
    );
    if (show.poster.isEmpty) show.poster = e.logo;
    if (!show.urls.add(e.url)) continue;
    show.episodes.add(Episode(
      id: e.url,
      title: marker.rest.isEmpty ? 'Episodio ${marker.episode}' : marker.rest,
      url: e.url,
      season: marker.season,
      number: marker.episode,
    ));
  }

  return Catalog(
    live: resolveChannels(
      M3uPlaylist(epgUrl: playlist.epgUrl, entries: live),
      matcher: matcher,
      merges: merges,
    ),
    movies: movies,
    series: [
      for (final MapEntry(key: key, value: s) in shows.entries)
        Series(
          id: 'm3u:$key',
          title: s.title,
          year: s.year,
          poster: s.poster,
          group: s.group,
          episodes: sortEpisodes(s.episodes),
        ),
    ],
  );
}

/// Ordina per stagione ed episodio; a parità resta l'ordine originale.
List<Episode> sortEpisodes(List<Episode> eps) {
  final indexed = [for (var i = 0; i < eps.length; i++) (i, eps[i])];
  indexed.sort((a, b) {
    var c = a.$2.season.compareTo(b.$2.season);
    if (c == 0) c = a.$2.number.compareTo(b.$2.number);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final p in indexed) p.$2];
}

class _Show {
  _Show({required this.title, required this.year, required this.group});
  final String title;
  final int? year;
  final String group;
  String poster = '';
  final urls = <String>{};
  final episodes = <Episode>[];
}
