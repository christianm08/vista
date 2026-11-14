import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/list_titles.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_detail.dart';
import '../widgets/vista_row.dart';

/// Scheda di un film o di una serie della lista IPTV: backdrop, titolo,
/// metadati, azioni, dove altro si guarda e, per le serie, stagioni ed
/// episodi con l'avanzamento; in fondo il cast.
class TitleScreen extends StatefulWidget {
  const TitleScreen.movie(Movie this.movie, {super.key, this.heroTag})
    : series = null,
      resumeEpisode = null;
  const TitleScreen.series(
    Series this.series, {
    super.key,
    this.resumeEpisode,
    this.heroTag,
  }) : movie = null;

  final Movie? movie;
  final Series? series;

  /// Episodio da riprendere subito (da "Continua a guardare").
  final String? resumeEpisode;

  /// La locandina da cui si è aperta: atterra nel backdrop.
  final Object? heroTag;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  TitleDetails _details = TitleDetails.empty;

  /// Lo stesso titolo su TMDB: dati mancanti, cast e altri servizi.
  TmdbDetails? _tmdb;
  List<Episode>? _episodes;
  String? _error;
  int? _season;
  bool _loading = true;

  bool get _isMovie => widget.movie != null;
  String get _rawTitle => widget.movie?.title ?? widget.series!.title;
  String get _title => listTitle(_rawTitle, _tmdb?.title);
  String get _id =>
      _isMovie ? 'mv:${widget.movie!.id}' : 'sr:${widget.series!.id}';

  String get _poster {
    // Le locandine TMDB sono affidabili; quelle dei pannelli spesso no.
    final tm = _tmdb?.title.poster ?? '';
    if (tm.isNotEmpty) return tm;
    if (_details.poster.isNotEmpty) return _details.poster;
    return widget.movie?.poster ?? widget.series!.poster;
  }

  String get _backdrop {
    if (_details.backdrop.isNotEmpty) return _details.backdrop;
    final own = widget.series?.backdrop ?? '';
    return own.isNotEmpty ? own : (_tmdb?.title.backdrop ?? '');
  }

  String get _key => _isMovie
      ? UserKey.movie(widget.movie!.id)
      : UserKey.series(widget.series!.id);

  @override
  void initState() {
    super.initState();
    _load();
    _loadTmdb();
  }

  final _primaryFocus = FocusNode(debugLabel: 'azione principale');
  final _listFocus = FocusNode(debugLabel: 'la mia lista');

  @override
  void dispose() {
    _primaryFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  /// Cerca il titolo su TMDB (se collegato). Gli errori non disturbano: la
  /// scheda resta con i dati della lista.
  Future<void> _loadTmdb() async {
    final tmdb = AppScope.of(context).tmdb;
    if (!tmdb.ready) return;
    try {
      final t = _isMovie
          ? await tmdb.matchMovie(widget.movie!)
          : await tmdb.matchSeries(widget.series!);
      if (t == null) return;
      final d = await tmdb.details(t.type, t.id);
      if (mounted) setState(() => _tmdb = d);
    } catch (_) {
      // nessun dato TMDB
    }
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final source = app.library?.source;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isMovie) {
        final d = await app.store.movieDetails(widget.movie!);
        if (mounted) setState(() => _details = d);
      } else {
        final info = await app.store.seriesInfo(widget.series!);
        if (!mounted) return;
        setState(() {
          _details = info.details;
          _episodes = info.episodes;
          _season =
              _startEpisode(app.user)?.season ??
              (info.episodes.isEmpty ? null : info.episodes.first.season);
        });
        // Durante il caricamento il fuoco era su "La mia lista" (Riproduci
        // era spento): ora passa all'azione principale.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _listFocus.hasFocus && _primaryFocus.context != null) {
            _primaryFocus.requestFocus();
          }
        });
        final id = widget.resumeEpisode;
        if (id != null) {
          final e = info.episodes.where((x) => x.id == id).firstOrNull;
          if (e != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Nav.playEpisodes(context, widget.series!, info.episodes, e);
              }
            });
          }
        }
      }
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Dettagli non disponibili: ${redactError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// L'episodio da cui partire: quello in corso, altrimenti il successivo
  /// all'ultimo visto, altrimenti il primo.
  Episode? _startEpisode(UserStore user) {
    final eps = _episodes;
    if (eps == null || eps.isEmpty) return null;
    WatchProgress? last;
    var lastIndex = -1;
    for (var i = 0; i < eps.length; i++) {
      final p = user.progressOf(UserKey.episode(eps[i].id));
      if (p != null && (last == null || p.updatedAt.isAfter(last.updatedAt))) {
        last = p;
        lastIndex = i;
      }
    }
    if (last == null) return eps.first;
    if (last.finished) {
      return lastIndex + 1 < eps.length ? eps[lastIndex + 1] : eps[lastIndex];
    }
    return eps[lastIndex];
  }

  List<int> get _seasons =>
      {for (final e in _episodes ?? <Episode>[]) e.season}.toList();

  void _toggleList() {
    final user = AppScope.of(context).user;
    user.toggleFavorite(_key);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: VistaMotion.toast,
          content: Text(
            user.isFavorite(_key)
                ? 'Aggiunto alla tua lista'
                : 'Tolto dalla tua lista',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: DetailTint(
        image: _backdrop.isNotEmpty ? _backdrop : _poster,
        child: ListenableBuilder(
          listenable: app.user,
          builder: (context, _) => _body(context, app.user),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, UserStore user) {
    final tmdb = _tmdb;
    return VistaRowsPage(
      rows: [
        DetailHeader(
          key: const ValueKey('head'),
          id: _id,
          kicker: _isMovie ? 'Film' : 'Serie',
          title: _title,
          meta: _meta,
          plot: _plot,
          notes: _notes,
          backdrop: _backdrop,
          poster: _poster,
          heroTag: widget.heroTag,
          actions: [..._actions(context, user), _listButton(user)],
          status: _error != null
              ? DetailStatus.error(_error!, onRetry: _load)
              : (_loading ? const DetailStatus.loading() : null),
          availability: tmdb == null
              ? null
              : AvailabilitySection(
                  title: tmdb.title.title,
                  availability: tmdb.availability,
                  heading: 'Disponibile anche su',
                ),
        ),
        if (!_isMovie) ?_episodesRow(context, user),
        if (tmdb != null && tmdb.cast.isNotEmpty)
          CastRow(key: const ValueKey('cast'), tmdb.cast),
      ],
    );
  }

  // --- intestazione ------------------------------------------------------------

  String get _meta {
    final m = widget.movie;
    final s = widget.series;
    final year =
        m?.year ?? s?.year ?? _tmdb?.title.year ?? yearInTitle(_rawTitle);
    final own = _details.genre.isNotEmpty
        ? _details.genre
        : (m?.genre ?? s?.genre ?? '');
    final genre = own.isNotEmpty
        ? own
        : (_tmdb?.genres.take(3).join(', ') ?? '');
    final rating = _details.rating.isNotEmpty
        ? _details.rating
        : (m?.rating ?? s?.rating ?? '');
    final seasons = _episodes == null || _seasons.isEmpty
        ? null
        : (_seasons.length == 1 ? '1 stagione' : '${_seasons.length} stagioni');
    return metaLine([
      if (year != null) '$year',
      ?seasons,
      genre,
      if (_isMovie && (_details.duration ?? _tmdb?.runtime) != null)
        formatDuration((_details.duration ?? _tmdb?.runtime)!),
      if (rating.isNotEmpty) '★ $rating',
    ]);
  }

  String get _plot {
    if (_details.plot.isNotEmpty) return _details.plot;
    final own = widget.movie?.plot ?? widget.series?.plot ?? '';
    return own.isNotEmpty ? own : (_tmdb?.title.overview ?? '');
  }

  List<String> get _notes => [
    if (_details.director.isNotEmpty) 'Regia  ${_details.director}',
    // Il cast con le foto c'è più sotto, se TMDB lo conosce.
    if (_details.cast.isNotEmpty && (_tmdb?.cast.isEmpty ?? true))
      'Cast  ${_details.cast}',
  ];

  Widget _listButton(UserStore user) {
    final fav = user.isFavorite(_key);
    return DetailButton(
      key: const ValueKey('list'),
      focusNode: _listFocus,
      // Finché Riproduci è spento (episodi in arrivo) il fuoco sta qui.
      autofocus: !_isMovie && _startEpisode(user) == null,
      icon: fav ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
      label: fav ? 'Nella tua lista' : 'La mia lista',
      onPressed: _toggleList,
    );
  }

  List<Widget> _actions(BuildContext context, UserStore user) {
    if (_isMovie) {
      final m = widget.movie!;
      final p = user.progressOf(UserKey.movie(m.id));
      final resumable = p != null && p.resumable;
      return [
        VistaButton.primary(
          key: const ValueKey('play'),
          autofocus: true,
          icon: Icons.play_arrow_rounded,
          label: resumable ? 'Riprendi da ${_clock(p.position)}' : 'Riproduci',
          onPressed: () => Nav.playMovie(context, m),
        ),
        if (resumable)
          DetailButton(
            key: const ValueKey('restart'),
            icon: Icons.replay_rounded,
            label: 'Dall\'inizio',
            onPressed: () => Nav.playMovie(context, m, fromStart: true),
          ),
      ];
    }
    final eps = _episodes;
    final start = _startEpisode(user);
    if (eps == null || start == null) {
      return [
        const VistaButton.primary(
          key: ValueKey('play'),
          icon: Icons.play_arrow_rounded,
          label: 'Riproduci',
          onPressed: null,
        ),
      ];
    }
    final p = user.progressOf(UserKey.episode(start.id));
    final resumable = p != null && p.resumable;
    return [
      VistaButton.primary(
        key: const ValueKey('play'),
        focusNode: _primaryFocus,
        autofocus: true,
        icon: Icons.play_arrow_rounded,
        label: '${resumable ? 'Riprendi' : 'Guarda'} ${start.code}',
        onPressed: () => Nav.playEpisodes(context, widget.series!, eps, start),
      ),
    ];
  }

  // --- episodi -----------------------------------------------------------------

  Widget? _episodesRow(BuildContext context, UserStore user) {
    final eps = _episodes;
    if (eps == null) {
      return _error == null
          ? const EpisodesSkeleton(key: ValueKey('episodes'), title: 'Episodi')
          : null;
    }
    if (eps.isEmpty) {
      return const DetailNote(
        'Nessun episodio disponibile.',
        key: ValueKey('episodes'),
      );
    }
    final layout = VistaLayout.of(context);
    final w = layout.wideCardWidth;
    final seasons = _seasons;
    final visible = eps.where((e) => e.season == _season).toList();
    final fallback = _backdrop.isNotEmpty ? _backdrop : _poster;
    return Column(
      key: const ValueKey('episodes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seasons.length > 1) ...[
          SeasonChips(
            labels: [for (final n in seasons) 'Stagione $n'],
            selected: seasons.indexOf(_season ?? seasons.first),
            onSelected: (i) => setState(() => _season = seasons[i]),
          ),
          const SizedBox(height: VistaSpace.s16),
        ],
        VistaRow(
          // Cambiando stagione la riga riparte dal primo episodio.
          key: ValueKey('season:$_season'),
          title: seasons.length > 1 ? 'Episodi' : 'Stagione ${_season ?? 1}',
          itemCount: visible.length,
          itemKey: (i) => ValueKey('ep:${visible[i].id}'),
          itemWidth: w,
          itemHeight: VistaWideCard.heightFor(context, w),
          itemBuilder: (context, i) {
            final e = visible[i];
            final p = user.progressOf(UserKey.episode(e.id));
            return VistaWideCard(
              title: '${e.number}. ${e.title}',
              meta: _episodeMeta(e, p),
              image: e.image.isNotEmpty ? e.image : fallback,
              restWidth: w,
              progress: p?.fraction,
              onTap: () => Nav.playEpisodes(context, widget.series!, eps, e),
            );
          },
        ),
      ],
    );
  }

  /// "48 min · visto", "51 min · 36 min rimanenti".
  static String _episodeMeta(Episode e, WatchProgress? p) => metaLine([
    if (e.duration != null) formatDuration(e.duration!) else e.code,
    if (p != null && p.finished)
      'visto'
    else if (p != null && p.resumable)
      '${formatDuration(p.duration - p.position)} rimanenti',
  ]);

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
