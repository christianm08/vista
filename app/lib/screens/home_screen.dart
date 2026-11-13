import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/tmdb_store.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart' show hhmm;
import '../widgets/list_titles.dart';
import '../widgets/tmdb_row.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_mark.dart';
import '../widgets/vista_preview.dart';
import '../widgets/vista_row.dart';
import 'shell.dart';

/// Home in stile servizio di streaming.
///
/// TV, PC, tablet: in alto l'anteprima del contenuto a fuoco (backdrop,
/// titolo, metadati, una frase di trama), sotto le righe. Anteprima e
/// backdrop cambiano quando il fuoco si ferma.
///
/// Telefono: un riquadro in evidenza con Riproduci e Lista, poi le righe.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _now = DateTime.now();
  late final Timer _clock;

  /// Anteprima del contenuto dove il fuoco si è fermato. [_source] la
  /// ricalcola quando arrivano dati in ritardo (abbinamento TMDB, servizio).
  final _preview = ValueNotifier<VistaPreviewData?>(null);
  VistaPreviewData Function()? _source;
  Timer? _settle;

  late TmdbStore _tmdb;
  late UserStore _user;
  final _titles = ListTitles.instance;

  /// Su quale dei tuoi servizi si guarda un titolo TMDB ('' = non si sa).
  final _serviceOf = <String, String>{};

  // Calcoli costosi sulle liste grandi, rifatti solo al cambio di catalogo.
  Catalog? _memoFor;
  List<Movie> _recentMovies = const [];
  List<Series> _recentSeries = const [];
  List<(String, List<Movie>)> _movieGroups = const [];
  List<Channel> _channels = const [];
  Map<String, Channel> _channelsByKey = const {};
  Map<String, Movie> _moviesById = const {};
  Map<String, Series> _seriesById = const {};

  @override
  void initState() {
    super.initState();
    _titles.addListener(_refreshPreview);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _settle?.cancel();
    _titles.removeListener(_refreshPreview);
    _preview.dispose();
    super.dispose();
  }

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
    _channels = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];
    _channelsByKey = {for (final ch in _channels) ch.key: ch};
    _moviesById = {for (final m in c.movies) m.id: m};
    _seriesById = {for (final s in c.series) s.id: s};
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

  /// Il fuoco arriva su un contenuto: l'anteprima lo segue quando si ferma
  /// (e solo allora, con [onSettle], si chiedono i dati che mancano).
  void _focus(VistaPreviewData Function() d, {VoidCallback? onSettle}) {
    _settle?.cancel();
    _settle = Timer(VistaMotion.backdropDelay, () {
      if (!mounted) return;
      _source = d;
      _preview.value = d();
      onSettle?.call();
    });
  }

  ValueChanged<bool> _onFocus(VistaPreviewData Function() d) => (has) {
    if (has) _focus(d);
  };

  void _refreshPreview() {
    final f = _source;
    if (f != null && mounted) _preview.value = f();
  }

  /// Il primo dei tuoi servizi su cui c'è il titolo, per il sopratitolo.
  Future<void> _loadService(TmdbTitle t) async {
    if (_serviceOf.containsKey(t.key)) return;
    _serviceOf[t.key] = '';
    final tmdb = _tmdb;
    final services = _user.services;
    try {
      final ids = withVariants(services, await tmdb.providers()).toSet();
      final d = await tmdb.details(t.type, t.id);
      for (final (p, kind) in d.availability.distinct) {
        if (kind != OfferKind.flatrate &&
            kind != OfferKind.free &&
            kind != OfferKind.ads) {
          continue;
        }
        if (ids.contains(p.id)) {
          _serviceOf[t.key] = p.name;
          break;
        }
      }
    } catch (_) {}
    _refreshPreview();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.store.library,
        app.user,
        app.epg.guide,
        _titles,
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
    _tmdb = app.tmdb;
    _user = user;
    final guide = app.epg.guide.value;
    final channels = _channels;
    final byKey = _channelsByKey;
    final compact = layout.compact;

    final favChannels = [
      for (final c in channels)
        if (user.isFavorite(UserKey.channel(c.key))) c,
    ];
    final recent = [
      for (final k in user.recentChannels)
        if (byKey[k] != null) byKey[k]!,
    ];
    final moviesById = _moviesById;
    final seriesById = _seriesById;
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

    final pw = layout.posterWidth;
    // Su TV e PC il titolo lo dice già l'anteprima: locandine senza testo.
    final posterText = compact;
    final posterH = VistaPosterCard.heightFor(context, pw, posterText);
    final ww = layout.wideCardWidth;
    final wideH = VistaWideCard.heightFor(context, ww);

    // All'apertura ha il fuoco il primo elemento della prima riga.
    var first = !compact;
    bool takeFirst() {
      final f = first;
      first = false;
      return f;
    }

    Widget posterRow(String key, String title, List<Object> items) {
      final autofocus = takeFirst();
      return VistaRow(
        key: ValueKey(key),
        title: title,
        itemCount: items.length,
        itemKey: (i) => ValueKey(_keyOf(items[i])),
        itemWidth: pw,
        itemHeight: posterH,
        itemBuilder: (context, i) => _poster(
          context,
          items[i],
          user,
          width: pw,
          showText: posterText,
          autofocus: autofocus && i == 0,
        ),
      );
    }

    Widget channelRow(String key, String title, List<Channel> list) {
      final autofocus = takeFirst();
      return VistaRow(
        key: ValueKey(key),
        title: title,
        itemCount: list.length,
        itemKey: (i) => ValueKey('ch:${list[i].key}'),
        itemWidth: ww,
        itemHeight: wideH,
        itemBuilder: (context, i) => _channelCard(
          context,
          list,
          list[i],
          guide,
          width: ww,
          autofocus: autofocus && i == 0,
        ),
      );
    }

    Widget resumeRow() {
      final autofocus = takeFirst();
      return VistaRow(
        key: const ValueKey('resume'),
        title: 'Continua a guardare',
        itemCount: resume.length,
        itemKey: (i) => ValueKey('pr:${resume[i].key}'),
        itemWidth: ww,
        itemHeight: wideH,
        itemBuilder: (context, i) {
          final p = resume[i];
          return VistaWideCard(
            title: _resumePreview(p).title,
            meta: [
              if (p.subtitle.isNotEmpty) p.subtitle,
              'mancano ${formatDuration(p.duration - p.position)}',
            ].join(' · '),
            image: p.image,
            restWidth: ww,
            progress: p.fraction,
            autofocus: autofocus && i == 0,
            onFocusChange: _onFocus(() => _resumePreview(p)),
            onTap: () => Nav.resume(context, p),
            onLongPress: () {
              user.clearProgress(p.key);
              showToast(context, 'Tolto da Continua a guardare');
            },
          );
        },
      );
    }

    final rows = <Widget>[
      if (resume.isNotEmpty) resumeRow(),
      if (_recentMovies.isNotEmpty)
        posterRow('recent-movies', 'Film aggiunti di recente', _recentMovies),
      if (_recentSeries.isNotEmpty)
        posterRow(
          'recent-series',
          'Serie aggiornate di recente',
          _recentSeries,
        ),
      if (app.tmdb.ready && user.services.isNotEmpty)
        TmdbVistaRow(
          key: ValueKey('home-svc-${user.services.join(',')}'),
          title: 'Popolari sui tuoi servizi',
          showText: posterText,
          onFocusTitle: (t) =>
              _focus(() => _tmdbPreview(t), onSettle: () => _loadService(t)),
          load: () async {
            final ids = withVariants(
              user.services,
              await app.tmdb.providers(),
            ).toList();
            final r = await Future.wait([
              app.tmdb.discover(MediaType.movie, providers: ids),
              app.tmdb.discover(MediaType.tv, providers: ids),
            ]);
            return mergeByPopularity(
              r[0].results,
              r[1].results,
            ).take(24).toList();
          },
          onSeeAll: () => ShellController.of(context).go(Destination.discover),
        ),
      if (myList.isNotEmpty) posterRow('my-list', 'La mia lista', myList),
      if (favChannels.isNotEmpty)
        channelRow('fav-channels', 'Canali preferiti', favChannels),
      if (recent.isNotEmpty)
        channelRow('recent-channels', 'Visti di recente', recent),
      if (onAir.isNotEmpty) channelRow('on-air', 'In onda ora', onAir),
      for (final (group, movies) in _movieGroups)
        posterRow('group-$group', cleanGroupName(group), movies),
      if (onAir.isEmpty && favChannels.isEmpty && channels.isNotEmpty)
        channelRow('channels', 'Canali', channels.take(20).toList()),
    ];

    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Ancora niente da mostrare',
        message: 'Apri TV in diretta, Film o Serie per iniziare.',
      );
    }

    // Prima anteprima: il primo contenuto, finché il fuoco non si sposta.
    if (_source == null) {
      final p = resume.firstOrNull;
      final m = _recentMovies.firstOrNull;
      final sr = _recentSeries.firstOrNull;
      _source = p != null
          ? () => _resumePreview(p)
          : m != null
          ? () => _moviePreview(m)
          : sr != null
          ? () => _seriesPreview(sr)
          : null;
      _preview.value = _source?.call();
    }

    if (compact) {
      return VistaRowsPage(
        rows: [
          _PhoneHero(
            key: const ValueKey('hero'),
            feature: _phoneFeature(context, resume, user),
          ),
          ...rows,
        ],
      );
    }

    final headerTop = layout.safe.top > VistaSpace.s64
        ? layout.safe.top
        : VistaSpace.s64;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: c.maxWidth * VistaSize.backdropWidth,
            height: c.maxHeight * VistaSize.backdropHeight,
            child: ValueListenableBuilder(
              valueListenable: _preview,
              builder: (_, d, _) => VistaBackdrop(data: d),
            ),
          ),
          Positioned.fill(
            child: VistaRowsPage(
              headerHeight: headerTop + VistaSize.homePreview,
              header: Padding(
                padding: EdgeInsets.fromLTRB(layout.gutter, headerTop, 0, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder(
                    valueListenable: _preview,
                    builder: (_, d, _) => VistaPreviewText(data: d),
                  ),
                ),
              ),
              rows: rows,
            ),
          ),
        ],
      ),
    );
  }

  // --- anteprime -------------------------------------------------------------

  /// Titolo da mostrare: quello di TMDB se c'è l'abbinamento, altrimenti
  /// quello della lista ripulito.
  String _movieTitle(Movie m) => listTitle(m.title, _titles.movie(_tmdb, m));
  String _seriesTitle(Series s) => listTitle(s.title, _titles.series(_tmdb, s));

  static String _backdropOf(TmdbTitle? t) =>
      t == null || t.backdropPath.isEmpty ? '' : t.backdrop;

  static String _rating(String list, TmdbTitle? t) => list.isNotEmpty
      ? '$list/10'
      : (t != null && t.rating > 0
            ? '${t.rating.toStringAsFixed(1).replaceAll('.', ',')}/10'
            : '');

  VistaPreviewData _resumePreview(WatchProgress p) {
    final series = p.seriesId == null ? null : _seriesById[p.seriesId];
    final movie = p.key.startsWith('mv:')
        ? _moviesById[p.key.substring(3)]
        : null;
    final left = '${formatDuration(p.duration - p.position)} rimanenti';
    if (series == null && movie != null) {
      final m = _moviePreview(movie);
      return VistaPreviewData(
        id: 'pr:${p.key}',
        kicker: 'Film · Continua a guardare',
        title: m.title,
        meta: m.meta,
        plot: m.plot,
        note: left,
        backdrop: m.backdrop,
        poster: m.poster.isNotEmpty ? m.poster : p.image,
      );
    }
    final s = series == null ? null : _seriesPreview(series);
    return VistaPreviewData(
      id: 'pr:${p.key}',
      kicker: s != null ? 'Serie · Continua a guardare' : 'Continua a guardare',
      title: s?.title ?? cleanListTitle(p.title),
      meta: p.subtitle.isNotEmpty ? p.subtitle : (s?.meta ?? ''),
      plot: s?.plot ?? '',
      note: left,
      backdrop: s?.backdrop ?? '',
      poster: s != null && s.poster.isNotEmpty ? s.poster : p.image,
    );
  }

  VistaPreviewData _moviePreview(Movie m) {
    final t = _titles.movie(_tmdb, m);
    return VistaPreviewData(
      id: 'mv:${m.id}',
      kicker: 'Film · IPTV',
      title: listTitle(m.title, t),
      meta: metaLine([
        if ((m.year ?? t?.year ?? yearInTitle(m.title)) case final y?) '$y',
        // Il genere solo se la fonte lo dà: le categorie della lista
        // ("IT: PELLICOLA 2025") non lo sono.
        if (m.genre.isNotEmpty) m.genre,
        _rating(m.rating, t),
      ]),
      plot: m.plot.isNotEmpty ? m.plot : (t?.overview ?? ''),
      backdrop: _backdropOf(t),
      poster: m.poster.isNotEmpty ? m.poster : (t?.poster ?? ''),
    );
  }

  VistaPreviewData _seriesPreview(Series s) {
    final t = _titles.series(_tmdb, s);
    return VistaPreviewData(
      id: 'sr:${s.id}',
      kicker: 'Serie · IPTV',
      title: listTitle(s.title, t),
      meta: metaLine([
        if ((s.year ?? t?.year ?? yearInTitle(s.title)) case final y?) '$y',
        if (s.genre.isNotEmpty) s.genre,
        _rating(s.rating, t),
      ]),
      plot: s.plot.isNotEmpty ? s.plot : (t?.overview ?? ''),
      backdrop: s.backdrop.isNotEmpty ? s.backdrop : _backdropOf(t),
      poster: s.poster.isNotEmpty ? s.poster : (t?.poster ?? ''),
    );
  }

  VistaPreviewData _tmdbPreview(TmdbTitle t) => VistaPreviewData(
    id: t.key,
    kicker: [
      t.type == MediaType.tv ? 'Serie' : 'Film',
      (_serviceOf[t.key] ?? '').isNotEmpty
          ? _serviceOf[t.key]!
          : 'Sui tuoi servizi',
    ].join(' · '),
    title: t.title,
    meta: tmdbMeta(t),
    plot: t.overview,
    backdrop: t.backdrop,
    poster: t.poster,
  );

  VistaPreviewData _savedPreview(SavedTitle t) => VistaPreviewData(
    id: t.key,
    kicker: t.key.startsWith('tm:tv:')
        ? 'Serie · La mia lista'
        : 'Film · La mia lista',
    title: t.title,
    meta: t.year == null ? '' : '${t.year}',
    poster: t.poster,
  );

  VistaPreviewData _channelPreview(Channel c, EpgGuide guide) {
    final now = guide.nowOn(c, now: _now);
    return VistaPreviewData(
      id: 'ch:${c.key}',
      kicker: 'TV in diretta · ${c.number}',
      title: now?.title ?? c.name,
      meta: now == null
          ? 'Canale ${c.number}'
          : '${c.name} · ${hhmm(now.start)} – ${hhmm(now.stop)}',
      plot: now?.description ?? '',
      note: now == null
          ? 'Nessuna guida per questo canale'
          : '${formatDuration(now.stop.difference(_now))} rimanenti',
      // I canali non hanno un backdrop: al suo posto il logo, grande.
      art: ChannelLogo(
        channel: c,
        size: VistaSize.channelLogoPreview,
        boxed: false,
      ),
    );
  }

  // --- schede ------------------------------------------------------------------

  static String _keyOf(Object item) => switch (item) {
    Movie m => UserKey.movie(m.id),
    Series s => UserKey.series(s.id),
    SavedTitle t => t.key,
    _ => '$item',
  };

  Widget _channelCard(
    BuildContext context,
    List<Channel> list,
    Channel c,
    EpgGuide guide, {
    required double width,
    bool autofocus = false,
  }) {
    final user = AppScope.of(context).user;
    final now = guide.nowOn(c, now: _now);
    // Quanto del programma in onda è già passato: la barra dice "in onda"
    // e a che punto è, senza un'etichetta in più.
    final elapsed = now == null || now.duration.inSeconds <= 0
        ? null
        : _now.difference(now.start).inSeconds / now.duration.inSeconds;
    return VistaWideCard(
      title: now?.title ?? c.name,
      meta: now == null
          ? 'Canale ${c.number}'
          : '${c.name} · ${hhmm(now.start)} – ${hhmm(now.stop)}',
      restWidth: width,
      center: ChannelLogo(
        channel: c,
        size: VistaSize.channelLogoCard,
        boxed: false,
      ),
      progress: elapsed,
      autofocus: autofocus,
      onFocusChange: _onFocus(() => _channelPreview(c, guide)),
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

  Widget _poster(
    BuildContext context,
    Object item,
    UserStore user, {
    required double width,
    required bool showText,
    bool autofocus = false,
  }) {
    switch (item) {
      case Movie m:
        final key = UserKey.movie(m.id);
        final t = _titles.movie(_tmdb, m);
        return VistaPosterCard(
          title: listTitle(m.title, t),
          image: m.poster.isNotEmpty ? m.poster : (t?.poster ?? ''),
          restWidth: width,
          showText: showText,
          autofocus: autofocus,
          meta: metaLine([
            if ((m.year ?? t?.year ?? yearInTitle(m.title)) case final y?) '$y',
            _rating(m.rating, t),
          ]),
          progress: user.progressOf(key)?.fraction,
          saved: user.isFavorite(key),
          onFocusChange: _onFocus(() => _moviePreview(m)),
          onTap: () => Nav.openMovie(context, m),
          onLongPress: () => toggleMyList(context, key, _movieTitle(m)),
        );
      case Series s:
        final key = UserKey.series(s.id);
        final t = _titles.series(_tmdb, s);
        return VistaPosterCard(
          title: listTitle(s.title, t),
          image: s.poster.isNotEmpty ? s.poster : (t?.poster ?? ''),
          restWidth: width,
          showText: showText,
          autofocus: autofocus,
          meta: metaLine([
            if ((s.year ?? t?.year ?? yearInTitle(s.title)) case final y?) '$y',
            'Serie',
          ]),
          saved: user.isFavorite(key),
          onFocusChange: _onFocus(() => _seriesPreview(s)),
          onTap: () => Nav.openSeries(context, s),
          onLongPress: () => toggleMyList(context, key, _seriesTitle(s)),
        );
      case SavedTitle t:
        // Titolo dei servizi di streaming: `tm:movie:603`.
        final parts = t.key.split(':');
        final tmdb = TmdbTitle(
          type: parts[1] == 'tv' ? MediaType.tv : MediaType.movie,
          id: int.tryParse(parts[2]) ?? 0,
          title: t.title,
        );
        return VistaPosterCard(
          title: t.title,
          image: t.poster,
          restWidth: width,
          showText: showText,
          autofocus: autofocus,
          meta: metaLine([
            if (t.year != null) '${t.year}',
            parts[1] == 'tv' ? 'Serie' : 'Film',
          ]),
          saved: true,
          onFocusChange: _onFocus(() => _savedPreview(t)),
          onTap: () => Nav.openTmdb(context, tmdb),
          onLongPress: () => toggleSavedTitle(context, tmdb),
        );
    }
    return const SizedBox.shrink();
  }

  // --- telefono ------------------------------------------------------------------

  /// Il contenuto in evidenza sul telefono: da riprendere, o il più recente.
  _PhoneFeature? _phoneFeature(
    BuildContext context,
    List<WatchProgress> resume,
    UserStore user,
  ) {
    if (resume.isNotEmpty) {
      final p = resume.first;
      return _PhoneFeature(
        preview: _resumePreview(p),
        playLabel: 'Riprendi',
        onPlay: () => Nav.resume(context, p),
      );
    }
    final m = _recentMovies.where((m) => m.poster.isNotEmpty).firstOrNull;
    if (m != null) {
      final key = UserKey.movie(m.id);
      return _PhoneFeature(
        preview: _moviePreview(m),
        playLabel: 'Riproduci',
        onPlay: () => Nav.playMovie(context, m),
        saved: user.isFavorite(key),
        onList: () => toggleMyList(context, key, _movieTitle(m)),
      );
    }
    final s = _recentSeries.where((s) => s.poster.isNotEmpty).firstOrNull;
    if (s != null) {
      final key = UserKey.series(s.id);
      return _PhoneFeature(
        preview: _seriesPreview(s),
        playLabel: 'Episodi',
        onPlay: () => Nav.openSeries(context, s),
        saved: user.isFavorite(key),
        onList: () => toggleMyList(context, key, _seriesTitle(s)),
      );
    }
    return null;
  }
}

class _PhoneFeature {
  const _PhoneFeature({
    required this.preview,
    required this.playLabel,
    required this.onPlay,
    this.saved = false,
    this.onList,
  });

  final VistaPreviewData preview;
  final String playLabel;
  final VoidCallback onPlay;
  final bool saved;
  final VoidCallback? onList;
}

/// Riquadro in evidenza del telefono: artwork a tutta larghezza (anche sotto
/// la barra di stato), intestazione con Cerca e Impostazioni, titolo e azioni.
class _PhoneHero extends StatelessWidget {
  const _PhoneHero({super.key, required this.feature});
  final _PhoneFeature? feature;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top;
    final f = feature;
    final d = f?.preview;
    final art = d == null
        ? ''
        : (d.backdrop.isNotEmpty ? d.backdrop : d.poster);
    final shell = ShellController.of(context);
    final g = VistaLayout.of(context).gutter;
    final header = Row(
      children: [
        const VistaMark(size: VistaSize.railMark),
        const Spacer(),
        VistaIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Cerca',
          onPressed: () => shell.go(Destination.search),
        ),
        const SizedBox(width: VistaSpace.s8),
        VistaIconButton(
          icon: Icons.settings_rounded,
          tooltip: 'Impostazioni',
          onPressed: () => shell.go(Destination.settings),
        ),
      ],
    );
    if (f == null || d == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(g, top + VistaSpace.s8, g, 0),
        child: header,
      );
    }
    return SizedBox(
      height: VistaSize.phoneHero + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art.isNotEmpty)
            LayoutBuilder(
              builder: (context, c) => NetImage(
                art,
                alignment: Alignment.topCenter,
                cacheWidth:
                    (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                placeholder: const SizedBox.expand(),
                fallback: const SizedBox.expand(),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: VistaScrims.heroColors,
                stops: VistaScrims.heroStops,
              ),
            ),
          ),
          Positioned(
            left: g,
            right: g,
            top: top + VistaSpace.s8,
            child: header,
          ),
          Positioned(
            left: g,
            right: g,
            bottom: VistaSpace.s16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.kicker.isNotEmpty)
                  Text(
                    d.kicker.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      letterSpacing: VistaType.capsTracking,
                    ),
                  ),
                const SizedBox(height: VistaSpace.s8),
                Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.displayMedium,
                ),
                if (d.meta.isNotEmpty || d.note.isNotEmpty) ...[
                  const SizedBox(height: VistaSpace.s8),
                  Text(
                    metaLine([d.meta, d.note]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ],
                const SizedBox(height: VistaSpace.s16),
                Row(
                  children: [
                    Expanded(
                      child: VistaButton.primary(
                        label: f.playLabel,
                        icon: Icons.play_arrow_rounded,
                        onPressed: f.onPlay,
                      ),
                    ),
                    if (f.onList != null) ...[
                      const SizedBox(width: VistaSpace.s12),
                      VistaButton.tonal(
                        label: 'Lista',
                        icon: f.saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_rounded,
                        onPressed: f.onList,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
