import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';

/// Scheda di un film o di una serie: sfondo, metadati, azioni, trama, cast
/// e, per le serie, stagioni ed episodi con l'avanzamento.
class TitleScreen extends StatefulWidget {
  const TitleScreen.movie(Movie this.movie, {super.key})
    : series = null,
      resumeEpisode = null;
  const TitleScreen.series(Series this.series, {super.key, this.resumeEpisode})
    : movie = null;

  final Movie? movie;
  final Series? series;

  /// Episodio da riprendere subito (da "Continua a guardare").
  final String? resumeEpisode;

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
  String get _title => widget.movie?.title ?? widget.series!.title;
  String get _poster {
    if (_details.poster.isNotEmpty) return _details.poster;
    final own = widget.movie?.poster ?? widget.series!.poster;
    return own.isNotEmpty ? own : (_tmdb?.title.poster ?? '');
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
        final d = await app.store.movieDetails(source, widget.movie!);
        if (mounted) setState(() => _details = d);
      } else {
        final info = await app.store.seriesInfo(source, widget.series!);
        if (!mounted) return;
        setState(() {
          _details = info.details;
          _episodes = info.episodes;
          _season =
              _startEpisode(app.user)?.season ??
              (info.episodes.isEmpty ? null : info.episodes.first.season);
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
          duration: const Duration(seconds: 2),
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
      body: ListenableBuilder(
        listenable: app.user,
        builder: (context, _) => _body(context, app.user),
      ),
    );
  }

  Widget _body(BuildContext context, UserStore user) {
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    final heroHeight = layout.compact
        ? 240.0
        : (layout.height * 0.62).clamp(300.0, 560.0);
    return Stack(
      children: [
        // Sfondo in alto: immagine orizzontale o locandina sfocata.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: TitleBackdrop(
            backdrop: _backdrop,
            poster: _poster,
            title: _title,
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    g,
                    layout.compact ? 4 : 18,
                    g,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Indietro',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  g,
                  layout.compact ? 60 : heroHeight * 0.18,
                  g,
                  0,
                ),
                child: layout.compact
                    ? _headPhone(context, user)
                    : _headWide(context, layout, user),
              ),
            ),
            if (_tmdb case final d?) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, 26, g, 0),
                sliver: SliverToBoxAdapter(
                  child: AvailabilitySection(
                    title: d.title.title,
                    availability: d.availability,
                    heading: 'Disponibile anche su',
                  ),
                ),
              ),
            ],
            if (!_isMovie) ..._episodesSlivers(context, layout, user),
            if (_tmdb case final d? when d.cast.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.only(top: 26),
                sliver: SliverToBoxAdapter(child: CastRow(d.cast)),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ],
    );
  }

  // --- intestazione ------------------------------------------------------------

  String get _meta {
    final m = widget.movie;
    final s = widget.series;
    final year = m?.year ?? s?.year;
    final own = _details.genre.isNotEmpty
        ? _details.genre
        : (m?.genre ?? s?.genre ?? '');
    final genre = own.isNotEmpty
        ? own
        : (_tmdb?.genres.take(3).join(', ') ?? '');
    final rating = _details.rating.isNotEmpty
        ? _details.rating
        : (m?.rating ?? s?.rating ?? '');
    final seasons = _episodes == null
        ? null
        : (_seasons.length == 1 ? '1 stagione' : '${_seasons.length} stagioni');
    return metaLine([
      if (year != null) '$year',
      genre.isNotEmpty ? genre : (m?.group ?? s?.group),
      if (_isMovie && (_details.duration ?? _tmdb?.runtime) != null)
        formatDuration((_details.duration ?? _tmdb?.runtime)!),
      ?seasons,
      if (rating.isNotEmpty) '★ $rating',
    ]);
  }

  String get _plot {
    if (_details.plot.isNotEmpty) return _details.plot;
    final own = widget.movie?.plot ?? widget.series?.plot ?? '';
    return own.isNotEmpty ? own : (_tmdb?.title.overview ?? '');
  }

  Widget _headWide(BuildContext context, VistaLayout layout, UserStore user) {
    final posterW = layout.tv ? 170.0 : 210.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: posterW,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VistaRadius.poster),
              child: NetImage(
                _poster,
                cacheWidth: 420,
                placeholder: TitlePlaceholder(_title),
              ),
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(child: _info(context, layout, user)),
      ],
    );
  }

  Widget _headPhone(BuildContext context, UserStore user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 110,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VistaRadius.poster),
                  child: NetImage(
                    _poster,
                    cacheWidth: 300,
                    placeholder: TitlePlaceholder(_title),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _info(context, VistaLayout.of(context), user),
      ],
    );
  }

  Widget _info(BuildContext context, VistaLayout layout, UserStore user) {
    final t = Theme.of(context).textTheme;
    final fav = user.isFavorite(_key);
    final actions = _actions(context, user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (layout.compact ? t.headlineSmall : t.headlineMedium)
              ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
        ),
        const SizedBox(height: 8),
        Text(
          _meta,
          style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...actions,
            OutlinedButton.icon(
              onPressed: _toggleList,
              icon: Icon(
                fav ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                size: 20,
              ),
              label: Text(fav ? 'Nella tua lista' : 'La mia lista'),
            ),
          ],
        ),
        if (_loading) ...[
          const SizedBox(height: 14),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF9C8A))),
          TextButton(onPressed: _load, child: const Text('Riprova')),
        ],
        if (_plot.isNotEmpty) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              _plot,
              maxLines: layout.compact ? 6 : 4,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(
                color: VistaColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
        if (_details.cast.isNotEmpty || _details.director.isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text.rich(
              TextSpan(
                children: [
                  if (_details.director.isNotEmpty) ...[
                    const TextSpan(
                      text: 'Regia  ',
                      style: TextStyle(color: VistaColors.textTertiary),
                    ),
                    TextSpan(text: _details.director),
                    if (_details.cast.isNotEmpty) const TextSpan(text: '\n'),
                  ],
                  if (_details.cast.isNotEmpty) ...[
                    const TextSpan(
                      text: 'Cast  ',
                      style: TextStyle(color: VistaColors.textTertiary),
                    ),
                    TextSpan(text: _details.cast),
                  ],
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _actions(BuildContext context, UserStore user) {
    if (_isMovie) {
      final m = widget.movie!;
      final p = user.progressOf(UserKey.movie(m.id));
      final resumable = p != null && p.resumable;
      return [
        FilledButton.icon(
          autofocus: true,
          onPressed: () => Nav.playMovie(context, m),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            resumable ? 'Riprendi da ${_clock(p.position)}' : 'Riproduci',
          ),
        ),
        if (resumable)
          OutlinedButton.icon(
            onPressed: () => Nav.playMovie(context, m, fromStart: true),
            icon: const Icon(Icons.replay_rounded, size: 20),
            label: const Text('Dall\'inizio'),
          ),
      ];
    }
    final eps = _episodes;
    final start = _startEpisode(user);
    if (eps == null || start == null) {
      return [
        FilledButton.icon(
          autofocus: true,
          onPressed: null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Riproduci'),
        ),
      ];
    }
    final p = user.progressOf(UserKey.episode(start.id));
    final resumable = p != null && p.resumable;
    return [
      FilledButton.icon(
        autofocus: true,
        onPressed: () => Nav.playEpisodes(context, widget.series!, eps, start),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text('${resumable ? 'Riprendi' : 'Guarda'} ${start.code}'),
      ),
    ];
  }

  // --- episodi -----------------------------------------------------------------

  List<Widget> _episodesSlivers(
    BuildContext context,
    VistaLayout layout,
    UserStore user,
  ) {
    final eps = _episodes;
    final g = layout.gutter;
    if (eps == null) return const [];
    if (eps.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 28, g, 0),
          sliver: const SliverToBoxAdapter(
            child: Text(
              'Nessun episodio disponibile.',
              style: TextStyle(color: VistaColors.textSecondary),
            ),
          ),
        ),
      ];
    }
    final visible = eps.where((e) => e.season == _season).toList();
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 30, 0, 6),
          child: SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: g),
              itemCount: _seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final n = _seasons[i];
                return FocusCard(
                  radius: 999,
                  focusScale: 1.0,
                  selected: n == _season,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  onTap: () => setState(() => _season = n),
                  child: Text(
                    'Stagione $n',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(g, 10, g, 0),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final e = visible[i];
            final p = user.progressOf(UserKey.episode(e.id));
            return _EpisodeRow(
              episode: e,
              fallbackImage: _backdrop.isNotEmpty ? _backdrop : _poster,
              compact: layout.compact,
              progress: p?.fraction,
              watched: p?.finished ?? false,
              onTap: () => Nav.playEpisodes(context, widget.series!, eps, e),
            );
          },
        ),
      ),
    ];
  }

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

class TitleBackdrop extends StatelessWidget {
  const TitleBackdrop({
    super.key,
    required this.backdrop,
    required this.poster,
    required this.title,
  });
  final String backdrop;
  final String poster;
  final String title;

  @override
  Widget build(BuildContext context) {
    final image = backdrop.isNotEmpty
        ? NetImage(
            backdrop,
            cacheWidth: 1280,
            placeholder: const SizedBox.shrink(),
          )
        : ImageFiltered(
            imageFilter: blurFilter(30),
            child: Transform.scale(
              scale: 1.3,
              child: NetImage(
                poster,
                cacheWidth: 300,
                placeholder: TitlePlaceholder(title, showText: false),
              ),
            ),
          );
    // L'immagine sfuma nella trasparenza (non verso un colore pieno): sotto
    // c'è lo sfondo con gli aloni e non si vede nessuno stacco.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [0, 0.55, 1],
      ).createShader(r),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: backdrop.isNotEmpty ? 0.7 : 0.5, child: image),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8807090D), Color(0x0007090D)],
                stops: [0, 0.3],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xE607090D), Color(0x0007090D)],
                stops: [0, 0.75],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.fallbackImage,
    required this.compact,
    required this.onTap,
    this.progress,
    this.watched = false,
  });

  final Episode episode;
  final String fallbackImage;
  final bool compact;
  final double? progress;
  final bool watched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = episode;
    final thumbW = compact ? 128.0 : 190.0;
    return FocusCard(
      radius: VistaRadius.card,
      focusScale: 1.0,
      fill: const Color(0x0AFFFFFF),
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: thumbW,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VistaRadius.poster - 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(
                      e.image.isNotEmpty ? e.image : fallbackImage,
                      cacheWidth: 400,
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 34,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                    if (progress != null && progress! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProgressStrip(progress!),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${e.number}. ${e.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (watched)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: VistaColors.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  metaLine([
                    e.code,
                    if (e.duration != null) formatDuration(e.duration!),
                  ]),
                  style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
                ),
                if (e.plot.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    e.plot,
                    maxLines: compact ? 2 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
