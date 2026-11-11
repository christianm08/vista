import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';
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
  int order; // posizione nella fonte, per "aggiunti di recente" senza data
  final Movie? movie;
  final Series? series;

  double get ratingValue => double.tryParse(rating.replaceAll(',', '.')) ?? 0;
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

  bool get _movies => widget.kind == CatalogKind.movies;
  String get _title => _movies ? 'Film' : 'Serie TV';

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
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
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _Sort.year:
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case _Sort.rating:
        list.sort((a, b) => b.ratingValue.compareTo(a.ratingValue));
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

  String _label(String g) => switch (g) {
    _all => _movies ? 'Tutti i film' : 'Tutte le serie',
    _myList => 'La mia lista',
    _inProgress => 'In corso',
    _ => g,
  };

  IconData? _icon(String g) => switch (g) {
    _all => Icons.apps_rounded,
    _myList => Icons.bookmark_rounded,
    _inProgress => Icons.timelapse_rounded,
    _ => null,
  };

  void _open(_Item i) {
    if (i.movie != null) {
      Nav.openMovie(context, i.movie!);
    } else {
      Nav.openSeries(context, i.series!);
    }
  }

  Future<void> _pickSort() async {
    final s = await showDialog<_Sort>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: const Text('Ordina per'),
        children: [
          for (final o in _Sort.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      o == _sort
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: o == _sort
                          ? VistaColors.accent
                          : VistaColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                    Text(o.label),
                  ],
                ),
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
    final sideWidth = layout.width >= 1400 ? 260.0 : 210.0;
    return SafeArea(
      left: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sideWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 22, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 12),
                    child: Text(
                      _title,
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: groups.length,
                      itemExtent: 44,
                      itemBuilder: (_, i) {
                        final (g, n) = groups[i];
                        final sel = g == _group;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: FocusCard(
                            radius: 10,
                            focusScale: 1.0,
                            fill: Colors.transparent,
                            outline: false,
                            selected: sel,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            onTap: () => setState(() => _group = g),
                            child: Row(
                              children: [
                                if (_icon(g) != null) ...[
                                  Icon(
                                    _icon(g),
                                    size: 18,
                                    color: sel
                                        ? VistaColors.onPrimary
                                        : VistaColors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    _label(g),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: sel
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$n',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: sel
                                        ? VistaColors.onPrimary
                                        : VistaColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 26, 28, 14),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_label(_group)}  ·  ${items.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickSort,
                          icon: const Icon(Icons.sort_rounded, size: 18),
                          label: Text(_sort.label),
                        ),
                      ],
                    ),
                  ),
                ),
                _grid(
                  context,
                  layout,
                  items,
                  user,
                  const EdgeInsets.fromLTRB(18, 4, 28, 32),
                ),
              ],
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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ordina: ${_sort.label}',
                    onPressed: _pickSort,
                    icon: const Icon(Icons.sort_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (g, n) = groups[i];
                return FocusCard(
                  radius: 999,
                  focusScale: 1.0,
                  selected: _group == g,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  onTap: () => setState(() => _group = g),
                  child: Text(
                    '${_label(g)}  $n',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _grid(
          context,
          layout,
          items,
          user,
          const EdgeInsets.fromLTRB(16, 10, 16, 110),
        ),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    VistaLayout layout,
    List<_Item> items,
    UserStore user,
    EdgeInsets padding,
  ) {
    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: _group == _myList
              ? Icons.bookmark_outline_rounded
              : Icons.movie_outlined,
          title: _group == _myList ? 'La tua lista è vuota' : 'Niente qui',
          message: _group == _myList
              ? 'Tieni premuto su un titolo (o tasto Menu) per aggiungerlo.'
              : '',
        ),
      );
    }
    const gap = 14.0;
    return SliverPadding(
      padding: padding,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.crossAxisExtent;
          final target = layout.posterWidth;
          final cols = ((w + gap) / (target + gap)).floor().clamp(2, 12);
          final itemW = (w - gap * (cols - 1)) / cols;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: gap,
              mainAxisSpacing: 10,
              mainAxisExtent: itemW * 1.5 + PosterCard.textHeight,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              final p = user.progressOf(it.key);
              return PosterCard(
                autofocus: i == 0 && !layout.compact,
                title: it.title,
                image: it.poster,
                caption: metaLine([
                  if (it.year != null) '${it.year}',
                  if (it.rating.isNotEmpty) '★ ${it.rating}',
                ]),
                progress: p?.resumable ?? false ? p!.fraction : null,
                favorite: user.isFavorite(it.key),
                onTap: () => _open(it),
                onLongPress: () => toggleMyList(context, it.key, it.title),
              );
            },
          );
        },
      ),
    );
  }
}
