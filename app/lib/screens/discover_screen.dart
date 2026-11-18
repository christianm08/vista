import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/tmdb_store.dart';
import '../theme.dart';
import '../widgets/tmdb_row.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_grid.dart';
import '../widgets/vista_row.dart';
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

  Widget _setup(BuildContext context) => EmptyState(
    icon: Icons.explore_outlined,
    title: 'Tutti i tuoi servizi in un posto',
    message:
        'Scegli i servizi di streaming che hai (Netflix, Prime Video, '
        'Disney+, RaiPlay…) e Vista ti mostra cosa c\'è e dove guardarlo. '
        'Serve una chiave gratuita di TMDB, il database di film e serie.',
    action: 'Configura',
    onAction: _openServices,
    autofocus: true,
  );

  /// Sceglie il servizio da mostrare, o tutti i miei.
  Future<void> _pickService(List<WatchProvider> mine) async {
    Widget option(BuildContext ctx, int? id, String label) => VistaChoice(
      selected: id == _service,
      onTap: () => Navigator.pop(ctx, (id,)),
      child: Text(label),
    );
    final picked = await showDialog<(int?,)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Servizio'),
        children: [
          option(ctx, null, 'Tutti i miei servizi'),
          for (final p in mine) option(ctx, p.id, p.name),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _service = picked.$1);
  }

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

  Widget _row(String title, String id, PageLoader loader) => TmdbVistaRow(
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
    final top = layout.compact
        ? MediaQuery.paddingOf(context).top + VistaSpace.s8
        : (layout.safe.top > VistaSpace.s32 ? layout.safe.top : VistaSpace.s32);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        g,
        top,
        layout.compact ? VistaSpace.s8 : g + layout.safe.right,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scopri', style: t.headlineSmall),
                const SizedBox(height: VistaSpace.s4),
                Text(
                  mine.isEmpty
                      ? 'Scegli i tuoi servizi per vedere solo quello che '
                            'puoi guardare.'
                      : 'Film e serie dei tuoi ${mine.length} servizi.',
                  style: t.bodyMedium?.copyWith(
                    color: VistaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (layout.compact)
            VistaIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'I miei servizi',
              onPressed: _openServices,
            )
          else
            VistaButton.tonal(
              icon: Icons.tune_rounded,
              label: 'I miei servizi',
              onPressed: _openServices,
            ),
        ],
      ),
    );

    final chips = <Widget>[
      for (final k in _Kind.values)
        VistaChip(
          key: ValueKey(k),
          label: k.label,
          autofocus: k == _Kind.all && !layout.compact,
          selected: _kind == k,
          onSelected: () => setState(() => _kind = k),
        ),
      // I servizi in un solo chip che apre la scelta: una fila di nove
      // chip si confondeva con i tipi.
      if (mine.isNotEmpty) ...[
        const SizedBox(width: VistaSpace.s16),
        VistaChip(
          key: const ValueKey('service'),
          icon: Icons.subscriptions_rounded,
          label: serviceName ?? 'Tutti i miei servizi',
          selected: _service != null,
          onSelected: () => _pickService(mine),
        ),
      ],
    ];

    return VistaRowsPage(
      rows: [
        Column(
          key: const ValueKey('header'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            _ChipRow(chips: chips),
          ],
        ),
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
          TmdbVistaRow(
            key: const ValueKey('trending'),
            title: 'Di tendenza questa settimana',
            load: () async => (await tmdb.trending()).results,
          ),
        Padding(
          key: const ValueKey('credits'),
          padding: EdgeInsets.symmetric(horizontal: g),
          child: Text(
            'Dati di film e serie: TMDB. Disponibilità sui servizi: '
            'JustWatch.',
            style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Fila di chip che scorre col fuoco, con lo spazio per l'anello attorno.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final reserve = layout.rowReserve;
    return SizedBox(
      height: layout.chipHeight + reserve * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          reserve,
          layout.gutter + layout.safe.right,
          reserve,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: VistaSpace.s8),
        // Il fuoco non fa scorrere da solo (VistaTraversalPolicy): la fila
        // porta al centro il chip a fuoco.
        itemBuilder: (context, i) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (has) {
            if (!has) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : VistaMotion.rowScroll,
              curve: VistaMotion.enter,
            );
          },
          child: Center(child: chips[i]),
        ),
      ),
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
    final safe = layout.compact ? MediaQuery.paddingOf(context) : layout.safe;
    final top = layout.compact
        ? safe.top + VistaSpace.s8
        : (safe.top > VistaSpace.s32 ? safe.top : VistaSpace.s32);
    final padding = EdgeInsets.fromLTRB(
      g + safe.left,
      0,
      g + safe.right,
      VistaSpace.s32 + safe.bottom,
    );
    final Widget body;
    if (_items.isEmpty && _error != null) {
      body = EmptyState.error(
        title: 'Elenco non caricato',
        message: _error!,
        onAction: _next,
        autofocus: true,
      );
    } else if (_items.isEmpty) {
      body = _loading || _more
          ? VistaPosterGridSkeleton(padding: padding)
          : const EmptyState(
              icon: Icons.movie_outlined,
              title: 'Nessun titolo',
              message: 'Per ora qui non c\'è niente da guardare.',
            );
    } else {
      body = VistaPosterGrid(
        padding: padding,
        itemCount: _items.length,
        itemKey: (i) => ValueKey(_items[i].key),
        onNearEnd: _more && !_loading && _error == null ? _next : null,
        itemBuilder: (context, i, width) =>
            tmdbPosterCard(context, _items[i], width: width, autofocus: i == 0),
        footer: _error == null
            ? null
            : EmptyState.error(
                title: 'Altri titoli non caricati',
                message: _error!,
                onAction: _next,
              ),
      );
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              g + safe.left - VistaSpace.s8,
              top,
              g + safe.right,
              0,
            ),
            child: Row(
              children: [
                VistaIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Indietro',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: VistaSpace.s8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headlineSmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
