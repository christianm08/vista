import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/tmdb_store.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';
import '../widgets/tmdb_row.dart';
import 'services_screen.dart';
import 'shell.dart';

enum _Kind {
  all('Tutto'),
  movies('Film'),
  tv('Serie TV');

  const _Kind(this.label);
  final String label;
}

/// Carica una pagina di risultati (film e/o serie).
typedef PageLoader = Future<TmdbPage> Function(int page);

/// Scopri: i cataloghi dei servizi di streaming dell'utente, in stile
/// JustWatch/Plex. Ogni titolo compare una volta sola; la scheda dice dove
/// guardarlo.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  _Kind _kind = _Kind.all;
  int? _service; // null = tutti i miei servizi
  Future<List<WatchProvider>>? _providers;

  void _openServices() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ServicesScreen()));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.tmdb.client, app.user]),
      builder: (context, _) {
        if (!app.tmdb.ready) return _setup(context);
        _providers ??= app.tmdb.providers();
        return FutureBuilder<List<WatchProvider>>(
          future: _providers,
          builder: (context, snap) =>
              _content(context, app, snap.data ?? const []),
        );
      },
    );
  }

  Widget _setup(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyState(
            icon: Icons.explore_outlined,
            title: 'Tutti i tuoi servizi in un posto',
            message:
                'Scegli i servizi di streaming che hai (Netflix, Prime Video, Disney+, '
                'RaiPlay…) e Vista ti mostra cosa c\'è e dove guardarlo.\n'
                'Serve una chiave gratuita di TMDB, il database di film e serie.',
          ),
          FilledButton.icon(
            autofocus: true,
            onPressed: _openServices,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Configura'),
          ),
        ],
      ),
    ),
  );

  List<int> _ids(AppScope app) =>
      _service != null ? [_service!] : app.user.services;

  /// Film, serie o entrambi uniti per popolarità.
  Future<TmdbPage> _discover(
    TmdbStore tmdb, {
    required List<int> providers,
    String sortBy = 'popularity.desc',
    bool recent = false,
    int page = 1,
    _Kind? kind,
  }) async {
    final k = kind ?? _kind;
    Future<TmdbPage> one(MediaType t) => tmdb.discover(
      t,
      providers: providers,
      sortBy: sortBy,
      recent: recent,
      page: page,
    );
    if (k == _Kind.movies) return one(MediaType.movie);
    if (k == _Kind.tv) return one(MediaType.tv);
    final r = await Future.wait([one(MediaType.movie), one(MediaType.tv)]);
    return TmdbPage(
      mergeByPopularity(r[0].results, r[1].results),
      page: page,
      totalPages: r[0].totalPages > r[1].totalPages
          ? r[0].totalPages
          : r[1].totalPages,
    );
  }

  void _seeAll(String title, PageLoader loader) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TmdbGridScreen(title: title, loader: loader),
    ),
  );

  Widget _row(String title, String id, PageLoader loader) => TmdbRow(
    key: ValueKey(
      '$id|${_kind.name}|$_service|${AppScope.of(context).user.services.join(',')}',
    ),
    title: title,
    load: () async => (await loader(1)).results,
    onSeeAll: () => _seeAll(title, loader),
  );

  Widget _content(BuildContext context, AppScope app, List<WatchProvider> all) {
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    final tmdb = app.tmdb;
    final mine = [
      for (final id in app.user.services)
        ?all.where((p) => p.id == id).firstOrNull,
    ];
    if (_service != null && !mine.any((p) => p.id == _service)) _service = null;
    // I servizi scelti più le loro varianti (es. Prime Video con pubblicità).
    final ids = withVariants(_ids(app), all).toList();
    final serviceName = _service == null
        ? null
        : mine.firstWhere((p) => p.id == _service).name;
    final where = serviceName != null
        ? 'su $serviceName'
        : (ids.isEmpty ? 'in Italia' : 'sui tuoi servizi');

    final rows = <Widget>[
      _row(
        'Popolari $where',
        'pop',
        (p) => _discover(tmdb, providers: ids, page: p),
      ),
      _row(
        'Novità $where',
        'new',
        (p) => _discover(tmdb, providers: ids, recent: true, page: p),
      ),
      _row(
        'I più votati $where',
        'top',
        (p) => _discover(
          tmdb,
          providers: ids,
          sortBy: 'vote_average.desc',
          page: p,
        ),
      ),
      if (_service == null && mine.length > 1)
        for (final s in mine)
          _row(
            'Su ${s.name}',
            'svc${s.id}',
            (p) => _discover(
              tmdb,
              providers: withVariants([s.id], all).toList(),
              page: p,
            ),
          ),
      if (_service == null)
        TmdbRow(
          key: const ValueKey('trending'),
          title: 'Di tendenza questa settimana',
          load: () async => (await tmdb.trending()).results,
        ),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(g, layout.compact ? 8 : 24, g, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scopri',
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          mine.isEmpty
                              ? 'Scegli i tuoi servizi per vedere solo quello che puoi guardare'
                              : 'Film e serie dei tuoi ${mine.length} servizi',
                          style: t.bodyMedium?.copyWith(
                            color: VistaColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openServices,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(layout.compact ? 'Servizi' : 'I miei servizi'),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: g, vertical: 8),
              children: [
                for (final k in _Kind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FocusCard(
                      autofocus: k == _Kind.all && !layout.compact,
                      radius: 999,
                      focusScale: 1.0,
                      selected: _kind == k,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      onTap: () => setState(() => _kind = k),
                      child: Text(
                        k.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (mine.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FocusCard(
                      radius: 999,
                      focusScale: 1.0,
                      selected: _service == null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      onTap: () => setState(() => _service = null),
                      child: const Text(
                        'Tutti i miei',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  for (final p in mine)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FocusCard(
                        radius: 999,
                        focusScale: 1.0,
                        selected: _service == p.id,
                        padding: const EdgeInsets.fromLTRB(5, 4, 14, 4),
                        onTap: () => setState(() => _service = p.id),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProviderLogo(p, size: 30),
                            const SizedBox(width: 8),
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverList.list(children: rows),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(g, 4, g, layout.compact ? 110 : 32),
            child: Text(
              'Dati di film e serie: TMDB. Disponibilità sui servizi: JustWatch.',
              style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Elenco completo a griglia, con le pagine caricate scorrendo.
class TmdbGridScreen extends StatefulWidget {
  const TmdbGridScreen({super.key, required this.title, required this.loader});
  final String title;
  final PageLoader loader;

  @override
  State<TmdbGridScreen> createState() => _TmdbGridScreenState();
}

class _TmdbGridScreenState extends State<TmdbGridScreen> {
  final _items = <TmdbTitle>[];
  final _seen = <String>{};
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    try {
      final p = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        _page = p.page;
        _more = p.hasMore && _page < 50;
        for (final t in p.results) {
          if (_seen.add(t.key)) _items.add(t);
        }
        _error = null;
      });
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    const gap = 14.0;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 900) _next();
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(g - 8, 12, g, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Indietro',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: g),
              sliver: SliverLayoutBuilder(
                builder: (context, c) {
                  final w = c.crossAxisExtent;
                  final cols = ((w + gap) / (layout.posterWidth + gap))
                      .floor()
                      .clamp(2, 12);
                  final itemW = (w - gap * (cols - 1)) / cols;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: 10,
                      mainAxisExtent: itemW * 1.5 + PosterCard.textHeight,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      // Col telecomando la pagina successiva arriva prima del fondo.
                      if (i > _items.length - cols * 2 && _more && !_loading) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _next();
                        });
                      }
                      return TmdbPoster(_items[i], autofocus: i == 0);
                    },
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _error != null
                      ? Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFF9C8A)),
                        )
                      : (_loading
                            ? const CircularProgressIndicator()
                            : const SizedBox.shrink()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
