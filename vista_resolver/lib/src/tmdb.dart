import 'dart:convert';

import 'normalize.dart' show removeAccents;

/// Richiesta HTTP GET che restituisce il corpo come testo.
typedef HttpGet = Future<String> Function(Uri uri, Map<String, String> headers);

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum MediaType { movie, tv }

/// Immagine TMDB: `w92` loghi piccoli, `w342` locandine, `w780`/`w1280`
/// sfondi, `original` per la qualità massima.
String tmdbImage(String path, {String size = 'w342'}) =>
    path.isEmpty ? '' : 'https://image.tmdb.org/t/p/$size$path';

/// Un film o una serie nel catalogo TMDB.
class TmdbTitle {
  const TmdbTitle({
    required this.type,
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.overview = '',
    this.posterPath = '',
    this.backdropPath = '',
    this.date = '',
    this.rating = 0,
    this.voteCount = 0,
    this.genreIds = const [],
    this.popularity = 0,
  });

  final MediaType type;
  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterPath;
  final String backdropPath;

  /// `aaaa-mm-gg` (uscita del film o prima messa in onda della serie).
  final String date;
  final double rating;
  final int voteCount;
  final List<int> genreIds;
  final double popularity;

  int? get year => date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;

  /// Chiave stabile (preferiti, cache): `tm:movie:603`.
  String get key => 'tm:${type.name}:$id';

  String get poster => tmdbImage(posterPath);
  String get backdrop => tmdbImage(backdropPath, size: 'w1280');

  static TmdbTitle? fromJson(Map j, {MediaType? type}) {
    final mt = type ??
        switch (j['media_type']) {
          'movie' => MediaType.movie,
          'tv' => MediaType.tv,
          _ => null,
        };
    final id = _int(j['id']);
    if (mt == null || id == null) return null;
    final movie = mt == MediaType.movie;
    return TmdbTitle(
      type: mt,
      id: id,
      title: _str(j[movie ? 'title' : 'name']),
      originalTitle: _str(j[movie ? 'original_title' : 'original_name']),
      overview: _str(j['overview']),
      posterPath: _str(j['poster_path']),
      backdropPath: _str(j['backdrop_path']),
      date: _str(j[movie ? 'release_date' : 'first_air_date']),
      rating: _double(j['vote_average']),
      voteCount: _int(j['vote_count']) ?? 0,
      genreIds: [for (final g in (j['genre_ids'] as List? ?? const [])) if (g is int) g],
      popularity: _double(j['popularity']),
    );
  }
}

/// Un servizio di streaming (Netflix, Prime Video, RaiPlay…).
class WatchProvider {
  const WatchProvider({
    required this.id,
    required this.name,
    this.logoPath = '',
    this.priority = 999,
  });

  final int id;
  final String name;
  final String logoPath;
  final int priority;

  String get logo => tmdbImage(logoPath, size: 'w154');

  static WatchProvider? fromJson(Object? j, {String region = 'IT'}) {
    if (j is! Map) return null;
    final id = _int(j['provider_id']);
    if (id == null) return null;
    final prio = j['display_priorities'] is Map
        ? _int((j['display_priorities'] as Map)[region])
        : null;
    return WatchProvider(
      id: id,
      name: _str(j['provider_name']),
      logoPath: _str(j['logo_path']),
      priority: prio ?? _int(j['display_priority']) ?? 999,
    );
  }
}

/// Modo in cui un titolo è disponibile su un servizio.
enum OfferKind {
  flatrate('Incluso'),
  free('Gratis'),
  ads('Gratis con pubblicità'),
  rent('Noleggio'),
  buy('Acquisto');

  const OfferKind(this.label);
  final String label;
}

/// Dove si guarda un titolo in un paese (dati JustWatch via TMDB).
class Availability {
  const Availability({this.link = '', this.offers = const {}});

  /// Pagina TMDB/JustWatch con tutte le opzioni.
  final String link;
  final Map<OfferKind, List<WatchProvider>> offers;

  static const empty = Availability();

  bool get isEmpty => offers.values.every((l) => l.isEmpty);

  /// Ogni servizio una volta sola, col modo migliore (incluso prima di
  /// gratis, noleggio, acquisto).
  List<(WatchProvider, OfferKind)> get distinct {
    final seen = <int>{};
    final out = <(WatchProvider, OfferKind)>[];
    for (final kind in OfferKind.values) {
      final list = [...?offers[kind]]..sort((a, b) => a.priority.compareTo(b.priority));
      for (final p in list) {
        if (seen.add(p.id)) out.add((p, kind));
      }
    }
    return out;
  }

  /// Servizi su cui si guarda con un abbonamento o gratis.
  Set<int> get streamingIds => {
        for (final k in [OfferKind.flatrate, OfferKind.free, OfferKind.ads])
          for (final p in offers[k] ?? const <WatchProvider>[]) p.id,
      };

  static Availability fromJson(Object? j, String region) {
    if (j is! Map) return empty;
    final results = j['results'];
    final r = results is Map ? results[region] : null;
    if (r is! Map) return empty;
    return Availability(
      link: _str(r['link']),
      offers: {
        for (final k in OfferKind.values)
          k: [
            for (final p in (r[k.name] as List? ?? const []))
              if (WatchProvider.fromJson(p, region: region) case final w?) w,
          ],
      },
    );
  }
}

class CastMember {
  const CastMember({required this.name, this.character = '', this.profilePath = ''});
  final String name;
  final String character;
  final String profilePath;
  String get photo => tmdbImage(profilePath, size: 'w185');
}

class TmdbSeason {
  const TmdbSeason({
    required this.number,
    required this.name,
    this.episodeCount = 0,
    this.posterPath = '',
    this.airDate = '',
  });
  final int number;
  final String name;
  final int episodeCount;
  final String posterPath;
  final String airDate;
}

class TmdbEpisode {
  const TmdbEpisode({
    required this.season,
    required this.number,
    required this.name,
    this.overview = '',
    this.stillPath = '',
    this.runtime,
    this.airDate = '',
  });
  final int season;
  final int number;
  final String name;
  final String overview;
  final String stillPath;
  final Duration? runtime;
  final String airDate;
  String get still => tmdbImage(stillPath, size: 'w300');
}

/// Scheda completa: dati, cast, trailer, IMDb e disponibilità.
class TmdbDetails {
  const TmdbDetails({
    required this.title,
    this.runtime,
    this.genres = const [],
    this.tagline = '',
    this.cast = const [],
    this.directors = const [],
    this.imdbId = '',
    this.trailerKey = '',
    this.seasons = const [],
    this.availability = Availability.empty,
    this.status = '',
  });

  final TmdbTitle title;
  final Duration? runtime;
  final List<String> genres;
  final String tagline;
  final List<CastMember> cast;

  /// Regia (film) o ideatori (serie).
  final List<String> directors;
  final String imdbId;

  /// ID YouTube del trailer.
  final String trailerKey;
  final List<TmdbSeason> seasons;
  final Availability availability;
  final String status;

  String get imdbUrl => imdbId.isEmpty ? '' : 'https://www.imdb.com/title/$imdbId/';
}

class TmdbPage {
  const TmdbPage(this.results, {this.page = 1, this.totalPages = 1});
  final List<TmdbTitle> results;
  final int page;
  final int totalPages;
  bool get hasMore => page < totalPages;
}

/// Client dell'API TMDB v3. La chiave è dell'utente: una "API key" v3
/// (32 caratteri) o un "API Read Access Token" v4 (JWT, inizia con `eyJ`).
class TmdbClient {
  TmdbClient(
    this.credential,
    this._get, {
    this.language = 'it-IT',
    this.region = 'IT',
    String base = 'https://api.themoviedb.org',
  }) : _base = base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  final String credential;
  final HttpGet _get;
  final String language;
  final String region;
  final String _base;

  bool get _bearer => credential.startsWith('eyJ');

  Uri uri(String path, [Map<String, String> query = const {}]) => Uri.parse('$_base/3$path').replace(
        queryParameters: {
          if (!_bearer) 'api_key': credential,
          'language': language,
          ...query,
        },
      );

  Future<Map> _json(String path, [Map<String, String> query = const {}]) async {
    final body = await _get(uri(path, query), {
      'Accept': 'application/json',
      if (_bearer) 'Authorization': 'Bearer $credential',
    });
    final Object? j;
    try {
      j = jsonDecode(body);
    } on FormatException {
      throw TmdbException('Risposta non valida da TMDB.');
    }
    if (j is! Map) throw TmdbException('Risposta non valida da TMDB.');
    if (j['success'] == false || j['status_code'] == 7) {
      throw TmdbException(_str(j['status_message']).isEmpty
          ? 'Chiave TMDB non valida.'
          : 'TMDB: ${j['status_message']}');
    }
    return j;
  }

  /// Verifica la chiave (una richiesta leggera).
  Future<void> check() => _json('/configuration');

  /// Servizi disponibili nel paese, film e serie insieme, nell'ordine di
  /// importanza di JustWatch.
  Future<List<WatchProvider>> providers() async {
    final out = <int, WatchProvider>{};
    for (final t in ['movie', 'tv']) {
      final j = await _json('/watch/providers/$t', {'watch_region': region});
      for (final p in (j['results'] as List? ?? const [])) {
        final w = WatchProvider.fromJson(p, region: region);
        if (w != null) {
          final prev = out[w.id];
          if (prev == null || w.priority < prev.priority) out[w.id] = w;
        }
      }
    }
    return out.values.toList()..sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Catalogo filtrato per servizi (in abbonamento o gratis).
  Future<TmdbPage> discover(
    MediaType type, {
    Iterable<int> providers = const [],
    String sortBy = 'popularity.desc',
    int page = 1,
    int? genre,
    bool recent = false,
    DateTime? now,
  }) async {
    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final since = (now ?? DateTime.now())
        .subtract(const Duration(days: 180))
        .toIso8601String()
        .substring(0, 10);
    final dateField = type == MediaType.movie ? 'primary_release_date' : 'first_air_date';
    final j = await _json('/discover/${type.name}', {
      'watch_region': region,
      'sort_by': sortBy,
      'page': '$page',
      'include_adult': 'false',
      if (providers.isNotEmpty) ...{
        'with_watch_providers': providers.join('|'),
        'with_watch_monetization_types': 'flatrate|free|ads',
      },
      if (genre != null) 'with_genres': '$genre',
      if (recent) ...{'$dateField.gte': since, '$dateField.lte': today},
      if (sortBy.startsWith('vote_average')) 'vote_count.gte': '300',
    });
    return _page(j, type);
  }

  Future<TmdbPage> trending({int page = 1}) async =>
      _page(await _json('/trending/all/week', {'page': '$page'}), null);

  Future<TmdbPage> search(String query, {int page = 1}) async => _page(
        await _json('/search/multi', {'query': query, 'page': '$page', 'include_adult': 'false'}),
        null,
      );

  /// Ricerca di un titolo preciso (per abbinare film e serie della lista).
  Future<List<TmdbTitle>> searchTitle(MediaType type, String query, {int? year}) async {
    final j = await _json('/search/${type.name}', {
      'query': query,
      'include_adult': 'false',
      if (year != null) (type == MediaType.movie ? 'year' : 'first_air_date_year'): '$year',
    });
    return _page(j, type).results;
  }

  Future<TmdbDetails> details(MediaType type, int id) async {
    final j = await _json('/${type.name}/$id', {
      'append_to_response': 'credits,videos,external_ids,watch/providers',
      'include_video_language': 'it,en,null',
    });
    return parseTmdbDetails(j, type, region: region);
  }

  Future<List<TmdbEpisode>> season(int tvId, int number) async {
    final j = await _json('/tv/$tvId/season/$number');
    return [
      for (final e in (j['episodes'] as List? ?? const []))
        if (e is Map)
          TmdbEpisode(
            season: number,
            number: _int(e['episode_number']) ?? 0,
            name: _str(e['name']),
            overview: _str(e['overview']),
            stillPath: _str(e['still_path']),
            runtime: (_int(e['runtime']) ?? 0) > 0 ? Duration(minutes: _int(e['runtime'])!) : null,
            airDate: _str(e['air_date']),
          ),
    ];
  }

  TmdbPage _page(Map j, MediaType? type) => TmdbPage(
        [
          for (final r in (j['results'] as List? ?? const []))
            if (r is Map)
              if (TmdbTitle.fromJson(r, type: type) case final t?) t,
        ],
        page: _int(j['page']) ?? 1,
        totalPages: _int(j['total_pages']) ?? 1,
      );
}

TmdbDetails parseTmdbDetails(Map j, MediaType type, {String region = 'IT'}) {
  final title = TmdbTitle.fromJson(j, type: type)!;
  final credits = j['credits'] is Map ? j['credits'] as Map : const {};
  final runtime = type == MediaType.movie
      ? _int(j['runtime'])
      : ((j['episode_run_time'] as List?)?.whereType<int>().firstOrNull);
  final videos = (j['videos'] is Map ? (j['videos'] as Map)['results'] as List? : null) ?? const [];
  String trailer = '';
  for (final want in ['Trailer', 'Teaser']) {
    for (final v in videos) {
      if (v is Map && v['site'] == 'YouTube' && v['type'] == want) {
        trailer = _str(v['key']);
        break;
      }
    }
    if (trailer.isNotEmpty) break;
  }
  final ext = j['external_ids'] is Map ? j['external_ids'] as Map : const {};
  return TmdbDetails(
    title: title,
    runtime: runtime == null || runtime <= 0 ? null : Duration(minutes: runtime),
    genres: [
      for (final g in (j['genres'] as List? ?? const []))
        if (g is Map && _str(g['name']).isNotEmpty) _str(g['name']),
    ],
    tagline: _str(j['tagline']),
    cast: [
      for (final c in (credits['cast'] as List? ?? const []).take(20))
        if (c is Map)
          CastMember(
            name: _str(c['name']),
            character: _str(c['character']),
            profilePath: _str(c['profile_path']),
          ),
    ],
    directors: type == MediaType.movie
        ? [
            for (final c in (credits['crew'] as List? ?? const []))
              if (c is Map && c['job'] == 'Director') _str(c['name']),
          ]
        : [
            for (final c in (j['created_by'] as List? ?? const []))
              if (c is Map) _str(c['name']),
          ],
    imdbId: _str(j['imdb_id']).isNotEmpty ? _str(j['imdb_id']) : _str(ext['imdb_id']),
    trailerKey: trailer,
    seasons: [
      for (final s in (j['seasons'] as List? ?? const []))
        if (s is Map && (_int(s['season_number']) ?? 0) > 0)
          TmdbSeason(
            number: _int(s['season_number'])!,
            name: _str(s['name']),
            episodeCount: _int(s['episode_count']) ?? 0,
            posterPath: _str(s['poster_path']),
            airDate: _str(s['air_date']),
          ),
    ],
    availability: Availability.fromJson(j['watch/providers'], region),
    status: _str(j['status']),
  );
}

// --- abbinamento con la lista IPTV --------------------------------------------

/// Chiave per confrontare i titoli: minuscole, senza accenti, punteggiatura
/// né articoli iniziali ("Il", "The"…).
String titleMatchKey(String title) {
  var s = removeAccents(title).toLowerCase();
  // Etichette tra parentesi ([4K], [ITA]) e anno tra parentesi.
  s = s.replaceAll(RegExp(r'\[[^\]]*\]|\((?:19|20)\d{2}\)'), ' ');
  s = s.replaceAll('&', ' e ');
  s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^(the|il|lo|la|i|gli|le|l|un|uno|una)\s+'), '');
  return s;
}

/// Lo stesso titolo? Titolo (o titolo originale) uguale e anno vicino.
bool sameTitle(String a, int? yearA, TmdbTitle t) {
  final k = titleMatchKey(a);
  if (k.isEmpty) return false;
  final names = {titleMatchKey(t.title), titleMatchKey(t.originalTitle)};
  if (!names.contains(k)) return false;
  final y = t.year;
  return yearA == null || y == null || (yearA - y).abs() <= 1;
}

/// Il miglior risultato di ricerca per un titolo della lista.
TmdbTitle? bestMatch(String title, int? year, List<TmdbTitle> results) {
  for (final r in results) {
    if (sameTitle(title, year, r)) return r;
  }
  return null;
}

// --- link ai servizi -------------------------------------------------------------

/// Pagina del servizio dove cercare il titolo. TMDB non dà i link diretti ai
/// contenuti: si apre la ricerca del servizio (o, se non lo conosciamo, la
/// pagina JustWatch con tutte le opzioni).
String providerSearchUrl(String providerName, String title, {String fallback = ''}) {
  final q = Uri.encodeQueryComponent(title);
  final n = providerName.toLowerCase();
  bool has(String s) => n.contains(s);
  if (has('netflix')) return 'https://www.netflix.com/search?q=$q';
  if (has('prime video') || has('amazon video') || n == 'amazon prime video') {
    return 'https://www.primevideo.com/search/ref=atv_nb_sr?phrase=$q';
  }
  if (has('disney')) return 'https://www.disneyplus.com/it-it/search?q=$q';
  if (has('apple tv')) return 'https://tv.apple.com/it/search?term=$q';
  if (has('raiplay')) return 'https://www.raiplay.it/ricerca.html?q=$q';
  if (has('paramount')) return 'https://www.paramountplus.com/it/search/';
  if (has('youtube')) return 'https://www.youtube.com/results?search_query=$q';
  if (has('google play')) return 'https://play.google.com/store/search?q=$q&c=movies';
  if (has('mubi')) return 'https://mubi.com/it/search/films?query=$q';
  if (has('rakuten')) return 'https://www.rakuten.tv/it/search?q=$q';
  if (has('crunchyroll')) return 'https://www.crunchyroll.com/search?q=$q';
  if (has('plex')) return 'https://watch.plex.tv/search?q=$q';
  if (has('pluto')) return 'https://pluto.tv/it/search/details?query=$q';
  if (has('mediaset')) return 'https://mediasetinfinity.mediaset.it/';
  if (has('now')) return 'https://www.nowtv.it/';
  if (has('sky go')) return 'https://www.skygo.sky.it/';
  if (has('timvision')) return 'https://www.timvision.it/';
  if (has('discovery')) return 'https://www.discoveryplus.com/it/';
  if (has('chili')) return 'https://it.chili.com/';
  return fallback;
}

/// App Android dei servizi principali (telefono e TV), per aprirle anche
/// dove il link web non basta (le app TV di solito non gestiscono i link).
List<String> providerAndroidPackages(String providerName) {
  final n = providerName.toLowerCase();
  if (n.contains('netflix')) return ['com.netflix.ninja', 'com.netflix.mediaclient'];
  if (n.contains('prime video') || n.contains('amazon video')) {
    return ['com.amazon.amazonvideo.livingroom', 'com.amazon.avod.thirdpartyclient'];
  }
  if (n.contains('disney')) return ['com.disney.disneyplus'];
  if (n.contains('youtube')) return ['com.google.android.youtube.tv', 'com.google.android.youtube'];
  if (n.contains('apple tv')) return ['com.apple.atve.androidtv.appletv', 'com.apple.atve.android.appletv'];
  if (n.contains('plex')) return ['com.plexapp.android'];
  if (n.contains('pluto')) return ['tv.pluto.android'];
  return const [];
}

String _str(Object? v) => v == null ? '' : (v is String ? v : v.toString());

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
