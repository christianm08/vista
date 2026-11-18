import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/list_titles.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_focus.dart';
import '../widgets/vista_grid.dart';
import 'home_screen.dart' show toggleMyList;
import 'shell.dart';

enum CatalogKind { movies, series }

enum _Sort {
  recent('Aggiunti di recente'),
  title('Titolo A-Z'),
  year('Anno'),
  rating('Voto');

  const _Sort(this.label);
  final String label;
}

const _all = '\u0000tutti';
const _myList = '\u0000lista';
const _inProgress = '\u0000incorso';

/// Elemento comune di film e serie per la griglia.
class _Item {
  _Item.movie(Movie m)
    : key = UserKey.movie(m.id),
      title = m.title,
      poster = m.poster,
      group = m.group,
      year = m.year,
      rating = m.rating,
      added = m.added,
      order = 0,
      movie = m,
      series = null;
  _Item.series(Series s)
    : key = UserKey.series(s.id),
      title = s.title,
      poster = s.poster,
      group = s.group,
      year = s.year,
      rating = s.rating,
      added = s.added,
      order = 0,
      movie = null,
      series = s;

  final String key;
  final String title;
  final String poster;
  final String group;
  final int? year;
  final String rating;
  final DateTime? added;

  /// Titolo in minuscolo per l'ordine alfabetico, calcolato una volta sola.
  late final String sortTitle = title.toLowerCase();
  int order; // posizione nella fonte, per "aggiunti di recente" senza data
  final Movie? movie;
  final Series? series;

  late final double ratingValue =
      double.tryParse(rating.replaceAll(',', '.')) ?? 0;
}

/// Film o serie: categorie (a lato su TV/PC, in alto su telefono),
/// ordinamento e griglia di locandine.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.kind});
  final CatalogKind kind;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _group = _all;
  _Sort _sort = _Sort.recent;

  Catalog? _memoFor;
  List<_Item> _items = const [];
  List<(String, int)> _groups = const [];

  // Elenco mostrato per (categoria, ordine): riordinare decine di migliaia di
  // titoli a ogni ridisegno (es. ogni volta che si salva l'avanzamento di un
  // film) bloccava l'interfaccia.
  (String, _Sort)? _shownFor;
  List<_Item> _shown = const [];

  bool get _movies => widget.kind == CatalogKind.movies;
  String get _title => _movies ? 'Film' : 'Serie TV';

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
    _shownFor = null;
    _items = _movies
        ? [for (final m in c.movies) _Item.movie(m)]
        : [for (final s in c.series) _Item.series(s)];
    for (var i = 0; i < _items.length; i++) {
      _items[i].order = i;
    }
    final counts = <String, int>{};
    for (final it in _items) {
      counts[it.group] = (counts[it.group] ?? 0) + 1;
    }
    _groups = [for (final e in counts.entries) (e.key, e.value)];
  }

  List<_Item> _visible(UserStore user) {
    // "La mia lista" e "In corso" dipendono dai dati dell'utente: sempre
    // ricalcolate (sono poche). Le altre si ricalcolano solo se cambiano
    // catalogo, categoria o ordine.
    final userBased = _group == _myList || _group == _inProgress;
    if (!userBased && _shownFor == (_group, _sort)) return _shown;
    final list = switch (_group) {
      _all => [..._items],
      _myList => [
        for (final i in _items)
          if (user.isFavorite(i.key)) i,
      ],
      _inProgress => [
        for (final i in _items)
          if (user.progressOf(i.key)?.resumable ?? false) i,
      ],
      _ => [
        for (final i in _items)
          if (i.group == _group) i,
      ],
    };
    switch (_sort) {
      case _Sort.recent:
        list.sort((a, b) {
          final c = (b.added ?? DateTime(0)).compareTo(a.added ?? DateTime(0));
          return c != 0 ? c : b.order.compareTo(a.order);
        });
      case _Sort.title:
        list.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
      case _Sort.year:
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case _Sort.rating:
        list.sort((a, b) => b.ratingValue.compareTo(a.ratingValue));
    }
    if (!userBased) {
      _shownFor = (_group, _sort);
      _shown = list;
    }
    return list;
  }

  List<(String, int)> _allGroups(UserStore user) {
    final fav = _items.where((i) => user.isFavorite(i.key)).length;
    final prog = _movies
        ? _items.where((i) => user.progressOf(i.key)?.resumable ?? false).length
        : 0;
    return [
      (_all, _items.length),
      if (fav > 0) (_myList, fav),
      if (prog > 0) (_inProgress, prog),
      ..._groups,
    ];
  }

  static const _special = {_myList: 'La mia lista', _inProgress: 'In corso'};

  /// Nomi delle categorie da mostrare: ripuliti (vedi [groupLabels]).
  Map<String, String> _names = const {};

  String _label(String g) => g == _all
      ? (_movies ? 'Tutti i film' : 'Tutte le serie')
      : _names[g] ?? _special[g] ?? cleanGroupName(g);

  IconData? _icon(String g) => switch (g) {
    _all => Icons.apps_rounded,
    _myList => Icons.bookmark_rounded,
    _inProgress => Icons.timelapse_rounded,
    _ => null,
  };

  /// Un nodo per categoria: dalla griglia, a sinistra si torna su quella
  /// scelta, non sulla più vicina.
  final _categoryNodes = <String, FocusNode>{};
  FocusNode _categoryNode(String g) => _categoryNodes.putIfAbsent(
    g,
    () => FocusNode(debugLabel: 'categoria $g'),
  );

  @override
  void dispose() {
    for (final n in _categoryNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _pick(String g) {
    if (g != _group) setState(() => _group = g);
  }

  void _open(_Item i, Object hero) {
    if (i.movie != null) {
      Nav.openMovie(context, i.movie!, hero: hero);
    } else {
      Nav.openSeries(context, i.series!, hero: hero);
    }
  }

  Future<void> _pickSort() async {
    final s = await showDialog<_Sort>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ordina per'),
        children: [
          for (final o in _Sort.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Row(
                children: [
                  SizedBox(
                    width: VistaSize.icon + VistaSpace.s12,
                    child: o == _sort
                        ? const Icon(Icons.check_rounded)
                        : const SizedBox.shrink(),
                  ),
                  Text(o.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (s != null && mounted) setState(() => _sort = s);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.store.library, app.user]),
      builder: (context, _) {
        final lib = app.library;
        if (lib == null) return const SizedBox.shrink();
        _memo(lib.catalog);
        final groups = _allGroups(app.user);
        if (!groups.any((g) => g.$1 == _group)) _group = _all;
        _names = groupLabels([
          for (final (g, _) in groups)
            if (g != _all) g,
        ], fixed: _special);
        final items = _visible(app.user);
        final layout = VistaLayout.of(context);
        return layout.compact
            ? _phone(context, layout, groups, items, app.user)
            : _wide(context, layout, groups, items, app.user);
      },
    );
  }

  // ===== TV e PC ===============================================================

  Widget _wide(
    BuildContext context,
    VistaLayout layout,
    List<(String, int)> groups,
    List<_Item> items,
    UserStore user,
  ) {
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    final top = layout.safe.top > VistaSpace.s32
        ? layout.safe.top
        : VistaSpace.s32;
    // Attorno alle voci, spazio per l'anello di fuoco.
    const ring = VistaFocus.ringGap + VistaFocus.ringWidth;
    return FocusTraversalGroup(
      policy: VistaTraversalPolicy(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: VistaSize.catalogSide + g,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                g - ring,
                top,
                0,
                layout.safe.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: ring),
                    child: Text(_title, style: t.headlineSmall),
                  ),
                  const SizedBox(height: VistaSpace.s16),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(ring),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: VistaSpace.s4),
                      itemBuilder: (_, i) {
                        final (gr, n) = groups[i];
                        return _Category(
                          key: ValueKey(gr),
                          focusNode: _categoryNode(gr),
                          icon: _icon(gr),
                          label: _label(gr),
                          count: n,
                          selected: gr == _group,
                          onTap: () => _pick(gr),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _grid(
              context,
              layout,
              items,
              user,
              header: Padding(
                padding: EdgeInsets.fromLTRB(g, top, g + layout.safe.right, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_label(_group)}  ·  ${items.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleLarge,
                      ),
                    ),
                    const SizedBox(width: VistaSpace.s16),
                    VistaButton.tonal(
                      icon: Icons.sort_rounded,
                      label: _sort.label,
                      onPressed: _pickSort,
                    ),
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                g,
                0,
                g + layout.safe.right,
                VistaSpace.s32 + layout.safe.bottom,
              ),
              onExitLeft: () => _categoryNode(_group).requestFocus(),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Telefono ==============================================================

  Widget _phone(
    BuildContext context,
    VistaLayout layout,
    List<(String, int)> groups,
    List<_Item> items,
    UserStore user,
  ) {
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    final reserve = layout.rowReserve;
    return SafeArea(
      bottom: false,
      child: _grid(
        context,
        layout,
        items,
        user,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(g, VistaSpace.s8, VistaSpace.s8, 0),
              child: Row(
                children: [
                  Expanded(child: Text(_title, style: t.headlineSmall)),
                  VistaIconButton(
                    icon: Icons.sort_rounded,
                    tooltip: 'Ordina: ${_sort.label}',
                    onPressed: _pickSort,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: layout.chipHeight + reserve * 2,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: g, vertical: reserve),
                itemCount: groups.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: VistaSpace.s8),
                itemBuilder: (_, i) {
                  final (gr, n) = groups[i];
                  return VistaChip(
                    key: ValueKey(gr),
                    label: '${_label(gr)}  $n',
                    selected: _group == gr,
                    onSelected: () => _pick(gr),
                  );
                },
              ),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(g, 0, g, VistaSpace.s32),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    VistaLayout layout,
    List<_Item> items,
    UserStore user, {
    required Widget header,
    required EdgeInsets padding,
    VoidCallback? onExitLeft,
  }) {
    if (items.isEmpty) {
      final mine = _group == _myList;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: EmptyState(
              icon: mine
                  ? Icons.bookmark_outline_rounded
                  : Icons.movie_outlined,
              title: mine
                  ? 'La tua lista è vuota'
                  : 'Niente in questa categoria',
              message: mine
                  ? 'Tieni premuto su un titolo (o il tasto Menu) per '
                        'aggiungerlo.'
                  : '',
              action: _movies ? 'Vedi tutti i film' : 'Vedi tutte le serie',
              onAction: () => _pick(_all),
            ),
          ),
        ],
      );
    }
    return VistaPosterGrid(
      // Una griglia per categoria e ordine: si riparte dall'inizio.
      key: ValueKey((_group, _sort)),
      header: header,
      padding: padding,
      onExitLeft: onExitLeft,
      itemCount: items.length,
      itemKey: (i) => ValueKey(items[i].key),
      itemBuilder: (context, i, width) {
        final it = items[i];
        final p = user.progressOf(it.key);
        final hero = 'catalog|${it.key}';
        return VistaPosterCard(
          autofocus: i == 0 && !layout.compact,
          title: cleanListTitle(it.title),
          image: it.poster,
          restWidth: width,
          heroTag: hero,
          meta: metaLine([
            if ((it.year ?? yearInTitle(it.title)) case final y?) '$y',
            if (it.rating.isNotEmpty) '${it.rating}/10',
          ]),
          progress: p?.resumable ?? false ? p!.fraction : null,
          saved: user.isFavorite(it.key),
          onTap: () => _open(it, hero),
          onLongPress: () =>
              toggleMyList(context, it.key, cleanListTitle(it.title)),
        );
      },
    );
  }
}

/// Voce dell'elenco delle categorie: a fuoco superficie più chiara e
/// anello, senza scala; la scelta ha il fondo e il testo forte.
class _Category extends StatelessWidget {
  const _Category({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final FocusNode focusNode;
  final IconData? icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = selected ? VistaColors.text : VistaColors.textSecondary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // Il fuoco non fa scorrere da solo (VistaTraversalPolicy): l'elenco
      // porta al centro la voce a fuoco.
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
      child: Semantics(
        selected: selected,
        child: VistaFocusable(
          focusNode: focusNode,
          kind: VistaFocusKind.flat,
          radius: VistaRadius.chip,
          fill: selected ? VistaColors.surfaceHigh : VistaColors.transparent,
          activeFill: VistaColors.surfaceSelected,
          onTap: onTap,
          child: SizedBox(
            height: VistaSize.minTouch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: VistaSize.iconSmall, color: fg),
                    const SizedBox(width: VistaSpace.s12),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: selected ? VistaType.strong : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: VistaSpace.s8),
                  Text(
                    '$count',
                    style: t.labelMedium?.copyWith(
                      color: VistaColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
