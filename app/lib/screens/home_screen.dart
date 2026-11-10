import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/epg_store.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';
import 'channel_settings_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'vod_player_screen.dart';

/// Quando il focus entra nel figlio da fuori, lo porta su [target] (la voce
/// selezionata) invece che sulla voce geometricamente più vicina.
class _EnterAt extends StatefulWidget {
  const _EnterAt({required this.target, required this.child});
  final FocusNode Function() target;
  final Widget child;

  @override
  State<_EnterAt> createState() => _EnterAtState();
}

class _EnterAtState extends State<_EnterAt> {
  bool _inside = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has && !_inside) {
          final t = widget.target();
          if (t.context != null && !t.hasFocus) t.requestFocus();
        }
        _inside = has;
      },
      child: widget.child,
    );
  }
}

enum Section {
  live('Live', Icons.live_tv_rounded),
  movies('Film', Icons.movie_outlined),
  series('Serie', Icons.video_library_outlined);

  const Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Home in stile "10-foot": su TV e PC menu a sinistra (Live, Film, Serie),
/// colonna delle categorie della lista e contenuto; i canali live sono una
/// guida TV con l'EPG. Su telefono la stessa struttura in forma compatta.
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
  Channel? _focusedChannel;
  bool _railFocused = false;
  DateTime _now = DateTime.now();
  late final Timer _clock;

  /// Primo elemento del contenuto: all'apertura il telecomando parte da qui.
  final _firstItem = FocusNode(debugLabel: 'primo elemento');

  /// Nodi del menu e delle categorie: entrando da fuori nella colonna il focus
  /// va sulla voce già selezionata, non su quella più vicina.
  final _navNodes = <Section, FocusNode>{};
  final _categoryNodes = <String, FocusNode>{};

  FocusNode _navNode(Section s) =>
      _navNodes.putIfAbsent(s, () => FocusNode(debugLabel: 'menu ${s.name}'));

  FocusNode _categoryNode(Section s, String? g) => _categoryNodes.putIfAbsent(
      '${s.name}|${g ?? ''}', () => FocusNode(debugLabel: 'categoria $g'));

  /// Seleziona solo se il focus resta sulla voce (non se è solo di passaggio
  /// o se viene subito spostato sulla voce selezionata).
  void _selectWhenSettled(FocusNode node, VoidCallback select) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.hasFocus) select();
    });
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstItem.context != null) _firstItem.requestFocus();
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _firstItem.dispose();
    for (final n in [..._navNodes.values, ..._categoryNodes.values]) {
      n.dispose();
    }
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

  void _select(Section s) {
    if (_section != s) setState(() => _section = s);
  }

  void _selectGroup(String? g) {
    if (_groupBy[_section] != g) setState(() => _groupBy[_section] = g);
  }

  // --- azioni ----------------------------------------------------------------

  void _playChannel(List<Channel> list, Channel c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(channels: list, initialIndex: list.indexOf(c)),
    ));
  }

  void _playMovie(Movie m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VodPlayerScreen(items: [
        VodItem(
          title: m.title,
          subtitle: [if (m.year != null) '${m.year}', m.group].join(' · '),
          url: m.url,
        ),
      ]),
    ));
  }

  void _openSeries(Series s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesScreen(series: s, source: widget.library.source, store: widget.store),
    ));
  }

  void _openChannelSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelSettingsScreen(store: widget.store),
    ));
  }

  void _editChannel(Channel c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChannelEditScreen(store: widget.store, channelKey: c.key),
    ));
  }

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      builder: (context, guide, _) => wide ? _tenFoot(guide) : _compact(guide),
    );
  }

  // ===== TV e PC ===============================================================

  /// Su una TV 1080p ci sono 960 punti logici: il menu resta a sole icone e
  /// si allarga con le etichette quando ha il focus. Sui PC grandi resta aperto.
  Widget _tenFoot(EpgGuide guide) {
    final width = MediaQuery.sizeOf(context).width;
    final roomy = width >= 1400;
    final railOpen = roomy || _railFocused;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(roomy ? 32 : 20, roomy ? 24 : 16, roomy ? 32 : 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (f) => setState(() => _railFocused = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: railOpen ? 210 : 76,
                  child: _EnterAt(
                    target: () => _navNode(_section),
                    child: FocusTraversalGroup(child: _sidebar(railOpen)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: roomy ? 280 : 210,
                child: _EnterAt(
                  target: () => _categoryNode(_section, _groupBy[_section]),
                  child: FocusTraversalGroup(child: _categoryColumn()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FocusTraversalGroup(
                  child: switch (_section) {
                    Section.live => _liveGuide(guide),
                    Section.movies =>
                      _posterGrid(_filter(_catalog.movies, (m) => m.group), _moviePoster),
                    Section.series =>
                      _posterGrid(_filter(_catalog.series, (s) => s.group), _seriesPoster),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar(bool open) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Glass(
        radius: VistaRadius.card,
        padding: EdgeInsets.fromLTRB(open ? 12 : 8, 18, open ? 12 : 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: open ? 8 : 0, bottom: 18),
              child: Text(open ? 'Vista' : 'V',
                  textAlign: open ? TextAlign.start : TextAlign.center,
                  maxLines: 1,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final s in _sections) ...[
              _navItem(s, open),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            if (_catalog.live.channels.isNotEmpty)
              _smallAction(Icons.tune_rounded, 'Canali', _openChannelSettings, open),
            if (_canRefresh)
              _smallAction(Icons.refresh_rounded, _refreshing ? 'Aggiorno…' : 'Aggiorna',
                  _refreshing ? null : _refresh, open),
            _smallAction(Icons.swap_horiz_rounded, 'Cambia fonte', _confirmChange, open),
            if (open) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(widget.library.source.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _navItem(Section s, bool open) {
    final selected = _section == s;
    final iconColor = selected ? VistaColors.onPrimary : Colors.white;
    final node = _navNode(s);
    return FocusCard(
      radius: 999,
      focusScale: 1.04,
      focusNode: node,
      selected: selected,
      fill: Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: open ? 14 : 0, vertical: 12),
      onTap: () => _select(s),
      onFocusChange: (f) {
        if (f) _selectWhenSettled(node, () => _select(s));
      },
      child: open
          ? Row(
              children: [
                Icon(s.icon, size: 22, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.label.toUpperCase(),
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ),
                Text('${_count(s)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? VistaColors.onPrimary : VistaColors.textTertiary)),
              ],
            )
          : Center(child: Icon(s.icon, size: 24, color: iconColor)),
    );
  }

  Widget _smallAction(IconData icon, String label, VoidCallback? onTap, bool open) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: FocusCard(
        radius: 999,
        focusScale: 1.04,
        fill: Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: open ? 12 : 0, vertical: 9),
        onTap: onTap ?? () {},
        child: open
            ? Row(
                children: [
                  Icon(icon, size: 20, color: VistaColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: VistaColors.textSecondary)),
                  ),
                ],
              )
            : Center(child: Icon(icon, size: 20, color: VistaColors.textSecondary)),
      ),
    );
  }

  Widget _categoryColumn() {
    final t = Theme.of(context).textTheme;
    final groups = _groups(_section);
    final current = _groupBy[_section];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_section.label.toUpperCase(),
                  style: t.labelMedium?.copyWith(
                      color: VistaColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1)),
              Text('Categorie', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 24),
            itemCount: groups.length + 1,
            itemBuilder: (_, i) {
              final g = i == 0 ? null : groups[i - 1];
              final selected = current == g;
              final node = _categoryNode(_section, g);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FocusCard(
                  radius: 16,
                  focusScale: 1.03,
                  focusNode: node,
                  selected: selected,
                  fill: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onTap: () => _selectGroup(g),
                  onFocusChange: (f) {
                    if (f) _selectWhenSettled(node, () => _selectGroup(g));
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(g ?? 'Tutte',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text('${_count(_section, g)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? VistaColors.onPrimary
                                  : VistaColors.textTertiary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _liveGuide(EpgGuide guide) {
    final channels = _filter(_channels, (c) => c.group);
    if (channels.isEmpty) return _empty('Nessun canale in questa categoria.');
    final focused =
        channels.contains(_focusedChannel) ? _focusedChannel! : channels.first;
    return LayoutBuilder(builder: (context, box) {
      final metrics = GuideMetrics.of(box.maxWidth);
      final window = GuideWindow(_now, minutes: metrics.minutes);
      return _guideColumn(guide, channels, focused, metrics, window);
    });
  }

  Widget _guideColumn(EpgGuide guide, List<Channel> channels, Channel focused,
      GuideMetrics metrics, GuideWindow window) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: widget.epg.status,
          builder: (context, status, _) => NowPlayingPanel(
            channel: focused,
            upcoming: guide.upcoming(focused, now: _now),
            now: _now,
            status: status,
          ),
        ),
        const SizedBox(height: 14),
        GuideRuler(window: window, now: _now, metrics: metrics),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 32, right: 4),
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = channels[i];
              return GuideRow(
                channel: c,
                programmes: guide.forChannel(c, now: _now),
                window: window,
                now: _now,
                metrics: metrics,
                focusNode: i == 0 ? _firstItem : null,
                onFocused: () {
                  if (_focusedChannel != c) setState(() => _focusedChannel = c);
                },
                onTap: () => _playChannel(channels, c),
                onLongPress: () => _editChannel(c),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _posterGrid<T>(List<T> items, Widget Function(T, {FocusNode? focusNode}) poster) {
    if (items.isEmpty) return _empty('Niente in questa categoria.');
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => poster(items[i], focusNode: i == 0 ? _firstItem : null),
    );
  }

  Widget _moviePoster(Movie m, {FocusNode? focusNode}) => PosterCard(
        title: m.title,
        image: m.poster,
        focusNode: focusNode,
        caption: [if (m.year != null) '${m.year}', if (m.rating.isNotEmpty) '★ ${m.rating}']
            .join(' · '),
        onTap: () => _playMovie(m),
      );

  Widget _seriesPoster(Series s, {FocusNode? focusNode}) => PosterCard(
        title: s.title,
        image: s.poster,
        focusNode: focusNode,
        caption: [if (s.year != null) '${s.year}', if (s.rating.isNotEmpty) '★ ${s.rating}']
            .join(' · '),
        onTap: () => _openSeries(s),
      );

  Widget _empty(String text) => Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VistaColors.textSecondary)),
      );

  // ===== Telefono ==============================================================

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
              onDestinationSelected: (i) => _select(sections[i]),
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
                          onTap: () => _selectGroup(g),
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
                Section.movies => _compactPosters(
                    _filter(_catalog.movies, (m) => m.group), _moviePoster),
                Section.series => _compactPosters(
                    _filter(_catalog.series, (s) => s.group), _seriesPoster),
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

  Widget _compactPosters<T>(
          List<T> items, Widget Function(T, {FocusNode? focusNode}) poster) =>
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
