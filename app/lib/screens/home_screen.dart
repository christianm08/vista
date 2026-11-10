import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/epg_store.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/focus_card.dart';
import '../widgets/live_preview.dart';
import '../widgets/poster_card.dart';
import '../widgets/tv_drawer.dart';
import '../widgets/vod_browser.dart';
import 'channel_settings_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'vod_player_screen.dart';

enum Section {
  live('Live TV', Icons.live_tv_rounded),
  movies('Film', Icons.movie_outlined),
  series('Serie', Icons.video_library_outlined);

  const Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Home. Su TV e PC la guida TV occupa tutto lo schermo (dettagli del
/// programma e anteprima in alto, griglia sotto) e il menu con sezioni e
/// categorie si apre di lato; Film e Serie sono scaffali per categoria.
/// Su telefono la stessa struttura in forma compatta.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.library,
    required this.store,
    required this.epg,
  });

  final Library library;
  final SourceStore store;
  final EpgStore epg;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Section _section;
  final _groupBy = <Section, String?>{}; // null = tutte le categorie
  bool _refreshing = false;
  bool _drawerOpen = false;
  bool _previewOn = true;
  GuideSelection? _selection;
  DateTime? _lastBack;
  DateTime _now = DateTime.now();
  late final Timer _clock;

  final _gridFocus = FocusNode(debugLabel: 'guida');
  final _vodFocus = FocusNode(debugLabel: 'primo titolo');

  Catalog get _catalog => widget.library.catalog;

  /// I canali nascosti non compaiono (restano nelle impostazioni).
  List<Channel> get _channels =>
      [for (final c in _catalog.live.channels) if (!c.hidden) c];

  @override
  void initState() {
    super.initState();
    _section = _sections.first;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
  }

  @override
  void dispose() {
    _clock.cancel();
    _gridFocus.dispose();
    _vodFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.library != widget.library) {
      if (!_sections.contains(_section)) _section = _sections.first;
      for (final s in Section.values) {
        if (!_groups(s).contains(_groupBy[s])) _groupBy[s] = null;
      }
    }
  }

  List<Section> get _sections {
    final s = [
      if (_catalog.live.channels.isNotEmpty) Section.live,
      if (_catalog.movies.isNotEmpty) Section.movies,
      if (_catalog.series.isNotEmpty) Section.series,
    ];
    return s.isEmpty ? [Section.live] : s;
  }

  int _count(Section s, [String? group]) => switch (s) {
        Section.live => _channels.where((c) => group == null || c.group == group).length,
        Section.movies =>
          _catalog.movies.where((m) => group == null || m.group == group).length,
        Section.series =>
          _catalog.series.where((x) => group == null || x.group == group).length,
      };

  List<String> _groups(Section s) => {
        ...switch (s) {
          Section.live => _channels.map((c) => c.group),
          Section.movies => _catalog.movies.map((m) => m.group),
          Section.series => _catalog.series.map((x) => x.group),
        },
      }.toList();

  List<T> _filter<T>(List<T> items, String Function(T) group) {
    final g = _groupBy[_section];
    return g == null ? items : items.where((i) => group(i) == g).toList();
  }

  // --- navigazione -------------------------------------------------------------

  void _focusContent() {
    if (!mounted) return;
    final node = _section == Section.live ? _gridFocus : _vodFocus;
    if (node.context != null) node.requestFocus();
  }

  void _openDrawer() => setState(() => _drawerOpen = true);

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
  }

  void _switchSection(Section s) {
    setState(() {
      _section = s;
      _selection = null;
    });
    _closeDrawer();
  }

  void _pickGroup(String? g) {
    setState(() {
      _groupBy[_section] = g;
      _selection = null;
    });
    _closeDrawer();
  }

  /// Indietro: apre il menu; a menu aperto, una seconda pressione esce.
  void _onBack() {
    if (!_drawerOpen) {
      _openDrawer();
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    _toast('Premi di nuovo Indietro per uscire');
  }

  /// Apre una schermata spegnendo l'anteprima (un solo video alla volta).
  Future<void> _push(Widget screen) async {
    setState(() => _previewOn = false);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    setState(() => _previewOn = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
  }

  void _playChannel(List<Channel> list, Channel c) => _push(PlayerScreen(
        channels: list,
        initialIndex: list.indexOf(c),
        guide: widget.epg.guide.value,
      ));

  void _playMovie(Movie m) => _push(VodPlayerScreen(items: [
        VodItem(
          title: m.title,
          subtitle: [if (m.year != null) '${m.year}', m.group].join(' · '),
          url: m.url,
        ),
      ]));

  void _openSeries(Series s) => _push(
      SeriesScreen(series: s, source: widget.library.source, store: widget.store));

  void _openChannelSettings() => _push(ChannelSettingsScreen(store: widget.store));

  void _editChannel(Channel c) =>
      _push(ChannelEditScreen(store: widget.store, channelKey: c.key));

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.store.refresh(widget.library.source);
      unawaited(widget.epg.refresh());
      _toast('Contenuti aggiornati.');
    } on SourceException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Aggiornamento non riuscito: ${redactError(e)}');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _confirmChange() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12161D),
        title: const Text('Cambiare fonte?'),
        content: const Text(
            'La lista o l\'account attuale verranno rimossi da questo dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cambia')),
        ],
      ),
    );
    if (ok == true) await widget.store.clear();
  }

  bool get _canRefresh {
    final s = widget.library.source;
    return !(s is M3uSource && s.isFile);
  }

  // --- interfaccia -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ValueListenableBuilder<EpgGuide>(
      valueListenable: widget.epg.guide,
      builder: (context, guide, _) => wide ? _tv(guide) : _compact(guide),
    );
  }

  // ===== TV e PC ===============================================================

  Widget _tv(EpgGuide guide) {
    final groups = _groups(_section);
    final current = _groupBy[_section];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: switch (_section) {
                    Section.live => _liveTv(guide),
                    Section.movies => VodBrowser<Movie>(
                        items: _catalog.movies,
                        group: current,
                        firstFocus: _vodFocus,
                        onOpenMenu: _openDrawer,
                        onOpen: _playMovie,
                        info: (m) => VodInfo(
                            title: m.title,
                            poster: m.poster,
                            group: m.group,
                            year: m.year,
                            rating: m.rating,
                            plot: m.plot),
                      ),
                    Section.series => VodBrowser<Series>(
                        items: _catalog.series,
                        group: current,
                        firstFocus: _vodFocus,
                        onOpenMenu: _openDrawer,
                        onOpen: _openSeries,
                        info: (s) => VodInfo(
                            title: s.title,
                            poster: s.poster,
                            group: s.group,
                            year: s.year,
                            rating: s.rating,
                            plot: s.plot),
                      ),
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: TvDrawer(
                open: _drawerOpen,
                onClose: _closeDrawer,
                footer: widget.library.source.label,
                sections: [
                  for (final s in _sections)
                    DrawerEntry(
                      icon: s.icon,
                      label: s.label,
                      trailing: '${_count(s)}',
                      selected: s == _section,
                      onTap: () => _switchSection(s),
                    ),
                ],
                groups: [
                  if (groups.length > 1) ...[
                    DrawerEntry(
                      label: 'Tutte',
                      trailing: '${_count(_section)}',
                      selected: current == null,
                      onTap: () => _pickGroup(null),
                    ),
                    for (final g in groups)
                      DrawerEntry(
                        label: g,
                        trailing: '${_count(_section, g)}',
                        selected: current == g,
                        onTap: () => _pickGroup(g),
                      ),
                  ],
                ],
                actions: [
                  if (_catalog.live.channels.isNotEmpty)
                    DrawerEntry(
                        icon: Icons.tune_rounded,
                        label: 'Canali',
                        onTap: () {
                          _closeDrawer();
                          _openChannelSettings();
                        }),
                  if (_canRefresh)
                    DrawerEntry(
                        icon: Icons.refresh_rounded,
                        label: _refreshing ? 'Aggiorno…' : 'Aggiorna',
                        onTap: _refreshing ? () {} : _refresh),
                  DrawerEntry(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Cambia fonte',
                      onTap: _confirmChange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveTv(EpgGuide guide) {
    final channels = _filter(_channels, (c) => c.group);
    if (channels.isEmpty) {
      return _empty('Nessun canale in questa categoria.\nPremi Indietro per il menu.');
    }
    final height = MediaQuery.sizeOf(context).height;
    final selection = _selection != null && channels.contains(_selection!.channel)
        ? _selection
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: (height * 0.36).clamp(170.0, 300.0),
          child: ValueListenableBuilder<String>(
            valueListenable: widget.epg.status,
            builder: (context, status, _) => GuideHeader(
              selection: selection,
              now: _now,
              category: _groupBy[Section.live],
              status: status,
              preview: LivePreview(
                channel: selection?.channel ?? channels.first,
                enabled: _previewOn,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: EpgGrid(
            channels: channels,
            guide: guide,
            now: _now,
            focusNode: _gridFocus,
            onSelectionChanged: (s) => setState(() => _selection = s),
            onPlay: (c) => _playChannel(channels, c),
            onEdit: _editChannel,
            onOpenMenu: _openDrawer,
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VistaColors.textSecondary)),
      );

  // ===== Telefono ==============================================================

  Widget _moviePoster(Movie m) => PosterCard(
        title: m.title,
        image: m.poster,
        caption: [if (m.year != null) '${m.year}', if (m.rating.isNotEmpty) '★ ${m.rating}']
            .join(' · '),
        onTap: () => _playMovie(m),
      );

  Widget _seriesPoster(Series s) => PosterCard(
        title: s.title,
        image: s.poster,
        caption: [if (s.year != null) '${s.year}', if (s.rating.isNotEmpty) '★ ${s.rating}']
            .join(' · '),
        onTap: () => _openSeries(s),
      );

  Widget _compact(EpgGuide guide) {
    final t = Theme.of(context).textTheme;
    final sections = _sections;
    final groups = _groups(_section);
    return Scaffold(
      bottomNavigationBar: sections.length < 2
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xE610141B),
              indicatorColor: Colors.white,
              selectedIndex: sections.indexOf(_section),
              onDestinationSelected: (i) => setState(() => _section = sections[i]),
              destinations: [
                for (final s in sections)
                  NavigationDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.icon, color: VistaColors.onPrimary),
                    label: s.label,
                  ),
              ],
            ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_section.label,
                          style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    if (_section == Section.live)
                      IconButton(
                          tooltip: 'Canali',
                          onPressed: _openChannelSettings,
                          icon: const Icon(Icons.tune_rounded)),
                    if (_canRefresh)
                      IconButton(
                          tooltip: 'Aggiorna',
                          onPressed: _refreshing ? null : _refresh,
                          icon: const Icon(Icons.refresh_rounded)),
                    IconButton(
                        tooltip: 'Cambia fonte',
                        onPressed: _confirmChange,
                        icon: const Icon(Icons.swap_horiz_rounded)),
                  ],
                ),
              ),
            ),
            if (groups.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: groups.length + 1,
                    itemBuilder: (_, i) {
                      final g = i == 0 ? null : groups[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FocusCard(
                          radius: 999,
                          selected: _groupBy[_section] == g,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          onTap: () => setState(() => _groupBy[_section] = g),
                          child: Text(g ?? 'Tutte',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: switch (_section) {
                Section.live => _compactLive(guide),
                Section.movies =>
                  _compactPosters(_filter(_catalog.movies, (m) => m.group), _moviePoster),
                Section.series =>
                  _compactPosters(_filter(_catalog.series, (s) => s.group), _seriesPoster),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactLive(EpgGuide guide) {
    final channels = _filter(_channels, (c) => c.group);
    return SliverList.separated(
      itemCount: channels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = channels[i];
        final now = guide.nowOn(c, now: _now);
        final t = Theme.of(context).textTheme;
        return FocusCard(
          radius: 18,
          focusScale: 1.02,
          padding: const EdgeInsets.all(10),
          onTap: () => _playChannel(channels, c),
          onLongPress: () => _editChannel(c),
          child: Row(
            children: [
              ChannelLogo(channel: c, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c.number}  ${c.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(now == null ? 'Nessuna informazione' : '${hhmm(now.start)}  ${now.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: VistaColors.textSecondary)),
                    if (now != null) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: now.progressAt(_now),
                          minHeight: 3,
                          backgroundColor: VistaColors.glassActive,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _compactPosters<T>(List<T> items, Widget Function(T) poster) =>
      SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => poster(items[i]),
      );
}
