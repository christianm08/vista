import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/content_row.dart';
import '../widgets/epg_guide.dart' show hhmm;
import '../widgets/poster_card.dart';
import '../widgets/tmdb_row.dart';
import 'shell.dart';

/// Un titolo in evidenza nel riquadro grande della Home.
class _Featured {
  _Featured({
    required this.title,
    required this.image,
    required this.backdrop,
    required this.meta,
    required this.plot,
    required this.onPlay,
    required this.onDetails,
    this.playLabel = 'Riproduci',
    this.progress,
    this.kicker = '',
  });
  final String title;
  final String image;
  final String backdrop;
  final String meta;
  final String plot;
  final String playLabel;
  final double? progress;
  final String kicker;
  final VoidCallback onPlay;
  final VoidCallback? onDetails;
}

/// Home in stile servizio di streaming: riquadro in evidenza e righe
/// (continua a guardare, canali, la mia lista, novità, categorie).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _now = DateTime.now();
  late final Timer _clock;
  Timer? _rotate;
  int _hero = 0;
  bool _heroFocused = false;

  // Calcoli costosi sulle liste grandi, rifatti solo al cambio di catalogo.
  Catalog? _memoFor;
  List<Movie> _recentMovies = const [];
  List<Series> _recentSeries = const [];
  List<(String, List<Movie>)> _movieGroups = const [];

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _rotate = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && !_heroFocused) setState(() => _hero++);
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _rotate?.cancel();
    super.dispose();
  }

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
    // "Aggiunti di recente": per data se la fonte la dà, altrimenti gli
    // ultimi della lista (i pannelli aggiungono in fondo).
    final movies = c.movies.any((m) => m.added != null)
        ? ([...c.movies]..sort(
            (a, b) =>
                (b.added ?? DateTime(0)).compareTo(a.added ?? DateTime(0)),
          ))
        : c.movies.reversed.toList();
    _recentMovies = movies.take(24).toList();
    final series = c.series.any((s) => s.added != null)
        ? ([...c.series]..sort(
            (a, b) =>
                (b.added ?? DateTime(0)).compareTo(a.added ?? DateTime(0)),
          ))
        : c.series.reversed.toList();
    _recentSeries = series.take(24).toList();
    final byGroup = <String, List<Movie>>{};
    for (final m in c.movies) {
      (byGroup[m.group] ??= []).add(m);
    }
    final groups = byGroup.entries.where((e) => e.value.length >= 6).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    _movieGroups = [
      for (final e in groups.take(4)) (e.key, e.value.take(24).toList()),
    ];
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 5) return 'Buonanotte';
    if (h < 13) return 'Buongiorno';
    if (h < 18) return 'Buon pomeriggio';
    return 'Buonasera';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.store.library,
        app.user,
        app.epg.guide,
      ]),
      builder: (context, _) {
        final lib = app.library;
        if (lib == null) return const SizedBox.shrink();
        _memo(lib.catalog);
        return _build(context, app, lib.catalog);
      },
    );
  }

  Widget _build(BuildContext context, AppScope app, Catalog catalog) {
    final layout = VistaLayout.of(context);
    final user = app.user;
    final guide = app.epg.guide.value;
    final channels = [
      for (final c in catalog.live.channels)
        if (!c.hidden) c,
    ];
    final byKey = {for (final c in channels) c.key: c};

    final favChannels = [
      for (final c in channels)
        if (user.isFavorite(UserKey.channel(c.key))) c,
    ];
    final recent = [
      for (final k in user.recentChannels)
        if (byKey[k] != null) byKey[k]!,
    ];
    final moviesById = {for (final m in catalog.movies) m.id: m};
    final seriesById = {for (final s in catalog.series) s.id: s};
    final myList = <Object>[
      for (final k in user.favorites)
        if (k.startsWith('mv:') && moviesById[k.substring(3)] != null)
          moviesById[k.substring(3)]!
        else if (k.startsWith('sr:') && seriesById[k.substring(3)] != null)
          seriesById[k.substring(3)]!
        else if (k.startsWith('tm:') && user.savedTitle(k) != null)
          user.savedTitle(k)!,
    ];
    final resume = user.continueWatching;
    // In onda ora: prima i preferiti e i recenti, poi gli altri con la guida.
    final onAir = <Channel>[];
    final seen = <String>{};
    for (final c in [...favChannels, ...recent, ...channels]) {
      if (onAir.length >= 20) break;
      if (!seen.add(c.key)) continue;
      if (guide.nowOn(c, now: _now) != null) onAir.add(c);
    }

    final featured = _featured(context, catalog, resume);
    final hero = featured.isEmpty ? null : featured[_hero % featured.length];

    final pw = layout.posterWidth;
    final posterH = pw * 1.5 + PosterCard.textHeight;
    final ww = layout.wideCardWidth;
    final wideH = ww * 9 / 16 + WideCard.textHeight;

    Widget channelRow(String title, List<Channel> list) => ContentRow(
      title: title,
      itemCount: list.length,
      itemWidth: ww,
      itemHeight: wideH,
      itemBuilder: (context, i) => _channelCard(context, list, list[i], guide),
    );

    final rows = <Widget>[
      if (resume.isNotEmpty)
        ContentRow(
          title: 'Continua a guardare',
          itemCount: resume.length,
          itemWidth: ww,
          itemHeight: wideH,
          itemBuilder: (context, i) {
            final p = resume[i];
            final left = p.duration - p.position;
            return WideCard(
              title: p.title,
              subtitle: [
                if (p.subtitle.isNotEmpty) p.subtitle,
                'mancano ${formatDuration(left)}',
              ].join(' · '),
              image: p.image,
              progress: p.fraction,
              onTap: () => Nav.resume(context, p),
              onLongPress: () {
                user.clearProgress(p.key);
                showToast(context, 'Tolto da Continua a guardare');
              },
            );
          },
        ),
      if (app.tmdb.ready && user.services.isNotEmpty)
        TmdbRow(
          key: ValueKey('home-svc-${user.services.join(',')}'),
          title: 'Popolari sui tuoi servizi',
          load: () async {
            final r = await Future.wait([
              app.tmdb.discover(MediaType.movie, providers: user.services),
              app.tmdb.discover(MediaType.tv, providers: user.services),
            ]);
            return mergeByPopularity(
              r[0].results,
              r[1].results,
            ).take(24).toList();
          },
          onSeeAll: () => ShellController.of(context).go(Destination.discover),
        ),
      if (favChannels.isNotEmpty) channelRow('Canali preferiti', favChannels),
      if (recent.isNotEmpty) channelRow('Visti di recente', recent),
      if (onAir.isNotEmpty) channelRow('In onda ora', onAir),
      if (myList.isNotEmpty)
        ContentRow(
          title: 'La mia lista',
          itemCount: myList.length,
          itemWidth: pw,
          itemHeight: posterH,
          itemBuilder: (context, i) => _poster(context, myList[i], user),
        ),
      if (_recentMovies.isNotEmpty)
        ContentRow(
          title: 'Film aggiunti di recente',
          itemCount: _recentMovies.length,
          itemWidth: pw,
          itemHeight: posterH,
          itemBuilder: (context, i) => _poster(context, _recentMovies[i], user),
        ),
      if (_recentSeries.isNotEmpty)
        ContentRow(
          title: 'Serie aggiornate di recente',
          itemCount: _recentSeries.length,
          itemWidth: pw,
          itemHeight: posterH,
          itemBuilder: (context, i) => _poster(context, _recentSeries[i], user),
        ),
      for (final (group, movies) in _movieGroups)
        ContentRow(
          title: group,
          itemCount: movies.length,
          itemWidth: pw,
          itemHeight: posterH,
          itemBuilder: (context, i) => _poster(context, movies[i], user),
        ),
      if (onAir.isEmpty && favChannels.isEmpty && channels.isNotEmpty)
        channelRow('Canali', channels.take(20).toList()),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _header(context, layout)),
        if (hero != null)
          SliverToBoxAdapter(
            child: _heroCard(context, layout, hero, featured.length),
          ),
        if (rows.isEmpty && hero == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Ancora niente da mostrare',
              message: 'Apri TV in diretta, Film o Serie per iniziare.',
            ),
          ),
        SliverList.list(children: rows),
        SliverToBoxAdapter(child: SizedBox(height: layout.compact ? 110 : 32)),
      ],
    );
  }

  Widget _header(BuildContext context, VistaLayout layout) {
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          g,
          layout.compact ? 8 : 22,
          layout.compact ? 6 : g,
          14,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting,
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    'Cosa guardiamo?',
                    style: t.bodyMedium?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (layout.compact)
              IconButton(
                tooltip: 'Impostazioni',
                onPressed: () =>
                    ShellController.of(context).go(Destination.settings),
                icon: const Icon(Icons.settings_outlined),
              )
            else
              VistaClock(
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VistaColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- riquadro in evidenza ------------------------------------------------------

  List<_Featured> _featured(
    BuildContext context,
    Catalog c,
    List<WatchProgress> resume,
  ) {
    final out = <_Featured>[];
    if (resume.isNotEmpty) {
      final p = resume.first;
      out.add(
        _Featured(
          kicker: 'CONTINUA A GUARDARE',
          title: p.title,
          image: p.image,
          backdrop: p.image,
          meta: [
            if (p.subtitle.isNotEmpty) p.subtitle,
            'mancano ${formatDuration(p.duration - p.position)}',
          ].join('  ·  '),
          plot: '',
          playLabel: 'Riprendi',
          progress: p.fraction,
          onPlay: () => Nav.resume(context, p),
          onDetails: null,
        ),
      );
    }
    for (final m in _recentMovies.where((m) => m.poster.isNotEmpty).take(3)) {
      out.add(
        _Featured(
          kicker: 'NOVITÀ',
          title: m.title,
          image: m.poster,
          backdrop: m.poster,
          meta: metaLine([
            if (m.year != null) '${m.year}',
            m.genre.isNotEmpty ? m.genre : m.group,
            if (m.rating.isNotEmpty) '★ ${m.rating}',
          ]),
          plot: m.plot,
          onPlay: () => Nav.playMovie(context, m),
          onDetails: () => Nav.openMovie(context, m),
        ),
      );
    }
    for (final s in _recentSeries.where((s) => s.poster.isNotEmpty).take(2)) {
      out.add(
        _Featured(
          kicker: 'SERIE TV',
          title: s.title,
          image: s.poster,
          backdrop: s.backdrop.isNotEmpty ? s.backdrop : s.poster,
          meta: metaLine([
            if (s.year != null) '${s.year}',
            s.genre.isNotEmpty ? s.genre : s.group,
            if (s.rating.isNotEmpty) '★ ${s.rating}',
          ]),
          plot: s.plot,
          playLabel: 'Episodi',
          onPlay: () => Nav.openSeries(context, s),
          onDetails: null,
        ),
      );
    }
    return out;
  }

  Widget _heroCard(
    BuildContext context,
    VistaLayout layout,
    _Featured f,
    int count,
  ) {
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    final height = layout.compact
        ? 230.0
        : (layout.height * 0.42).clamp(220.0, 420.0);
    final usesPoster = f.backdrop == f.image;
    return Padding(
      padding: EdgeInsets.fromLTRB(g, 0, g, 24),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (v) => setState(() => _heroFocused = v),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VistaRadius.hero),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Sfondo: immagine orizzontale, oppure la locandina sfocata.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: KeyedSubtree(
                    key: ValueKey(f.title),
                    child: usesPoster
                        ? ImageFiltered(
                            imageFilter: blurFilter(28),
                            child: Transform.scale(
                              scale: 1.2,
                              child: NetImage(
                                f.backdrop,
                                cacheWidth: 300,
                                placeholder: TitlePlaceholder(
                                  f.title,
                                  showText: false,
                                ),
                              ),
                            ),
                          )
                        : NetImage(
                            f.backdrop,
                            cacheWidth: 1280,
                            placeholder: TitlePlaceholder(
                              f.title,
                              showText: false,
                            ),
                          ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF0080A0E),
                        Color(0xB3080A0E),
                        Color(0x33080A0E),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(layout.compact ? 18 : 30),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (f.kicker.isNotEmpty)
                              Text(
                                f.kicker,
                                style: t.labelSmall?.copyWith(
                                  color: VistaColors.accent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              f.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (layout.compact
                                          ? t.headlineSmall
                                          : t.headlineMedium)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                            ),
                            if (f.meta.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                f.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(
                                  color: VistaColors.textSecondary,
                                ),
                              ),
                            ],
                            if (f.plot.isNotEmpty && !layout.compact) ...[
                              const SizedBox(height: 10),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 560,
                                ),
                                child: Text(
                                  f.plot,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodyMedium?.copyWith(
                                    color: VistaColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                            if (f.progress != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: ProgressStrip(f.progress!),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  autofocus: true,
                                  onPressed: f.onPlay,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text(f.playLabel),
                                ),
                                if (f.onDetails != null)
                                  OutlinedButton.icon(
                                    onPressed: f.onDetails,
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                    ),
                                    label: const Text('Dettagli'),
                                  ),
                                if (count > 1)
                                  OutlinedButton(
                                    onPressed: () => setState(() => _hero++),
                                    child: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (usesPoster &&
                          !layout.compact &&
                          f.image.isNotEmpty) ...[
                        const SizedBox(width: 24),
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              VistaRadius.poster,
                            ),
                            child: NetImage(
                              f.image,
                              cacheWidth: 400,
                              placeholder: TitlePlaceholder(f.title),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count > 1)
                  Positioned(
                    right: 18,
                    bottom: 14,
                    child: Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Container(
                            width: i == _hero % count ? 18 : 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 5),
                            decoration: BoxDecoration(
                              color: i == _hero % count
                                  ? Colors.white
                                  : VistaColors.glassActive,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- schede ----------------------------------------------------------------------

  Widget _channelCard(
    BuildContext context,
    List<Channel> list,
    Channel c,
    EpgGuide guide,
  ) {
    final user = AppScope.of(context).user;
    final now = guide.nowOn(c, now: _now);
    return WideCard(
      title: now?.title ?? c.name,
      subtitle: now == null
          ? '${c.number} · ${c.group}'
          : '${c.name} · ${hhmm(now.start)}–${hhmm(now.stop)}',
      center: ChannelLogo(channel: c, size: 64),
      progress: now?.progressAt(_now),
      overlay: Positioned(
        top: 8,
        left: 8,
        child: Row(
          children: [
            const LiveBadge(),
            if (user.isFavorite(UserKey.channel(c.key))) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: VistaColors.accent,
              ),
            ],
          ],
        ),
      ),
      onTap: () => Nav.playChannel(context, list, c),
      onLongPress: () {
        final key = UserKey.channel(c.key);
        user.toggleFavorite(key);
        showToast(
          context,
          user.isFavorite(key)
              ? '${c.name} aggiunto ai preferiti'
              : '${c.name} tolto dai preferiti',
        );
      },
    );
  }

  Widget _poster(BuildContext context, Object item, UserStore user) {
    switch (item) {
      case Movie m:
        final key = UserKey.movie(m.id);
        return PosterCard(
          title: m.title,
          image: m.poster,
          caption: metaLine([
            if (m.year != null) '${m.year}',
            if (m.rating.isNotEmpty) '★ ${m.rating}',
          ]),
          progress: user.progressOf(key)?.fraction,
          favorite: user.isFavorite(key),
          onTap: () => Nav.openMovie(context, m),
          onLongPress: () => toggleMyList(context, key, m.title),
        );
      case Series s:
        final key = UserKey.series(s.id);
        return PosterCard(
          title: s.title,
          image: s.poster,
          caption: metaLine([if (s.year != null) '${s.year}', 'Serie']),
          favorite: user.isFavorite(key),
          onTap: () => Nav.openSeries(context, s),
          onLongPress: () => toggleMyList(context, key, s.title),
        );
      case SavedTitle t:
        // Titolo dei servizi di streaming: `tm:movie:603`.
        final parts = t.key.split(':');
        final tmdb = TmdbTitle(
          type: parts[1] == 'tv' ? MediaType.tv : MediaType.movie,
          id: int.tryParse(parts[2]) ?? 0,
          title: t.title,
        );
        return PosterCard(
          title: t.title,
          image: t.poster,
          caption: metaLine([
            if (t.year != null) '${t.year}',
            parts[1] == 'tv' ? 'Serie' : 'Film',
          ]),
          favorite: true,
          onTap: () => Nav.openTmdb(context, tmdb),
          onLongPress: () => toggleSavedTitle(context, tmdb),
        );
    }
    return const SizedBox.shrink();
  }
}

/// Aggiunge o toglie un titolo da "La mia lista" con un avviso.
void toggleMyList(BuildContext context, String key, String title) {
  final user = AppScope.of(context).user;
  user.toggleFavorite(key);
  showToast(
    context,
    user.isFavorite(key)
        ? '$title aggiunto alla tua lista'
        : '$title tolto dalla tua lista',
  );
}
