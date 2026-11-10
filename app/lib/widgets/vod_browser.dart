import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'channel_tile.dart';
import 'poster_card.dart';

/// Come mostrare un titolo (film o serie) nel catalogo.
class VodInfo {
  const VodInfo({
    required this.title,
    required this.poster,
    required this.group,
    this.year,
    this.rating = '',
    this.plot = '',
  });

  final String title;
  final String poster;
  final String group;
  final int? year;
  final String rating;
  final String plot;
}

/// Catalogo film/serie per la TV: in alto i dettagli del titolo col focus, sotto
/// uno scaffale per categoria (o la griglia di una sola categoria). Sinistra
/// sul primo titolo di uno scaffale apre il menu laterale.
class VodBrowser<T> extends StatefulWidget {
  const VodBrowser({
    super.key,
    required this.items,
    required this.info,
    required this.onOpen,
    required this.onOpenMenu,
    required this.firstFocus,
    this.group,
    this.emptyText = 'Niente in questa categoria.',
  });

  final List<T> items;
  final VodInfo Function(T) info;
  final ValueChanged<T> onOpen;
  final VoidCallback onOpenMenu;
  final FocusNode firstFocus;

  /// Categoria scelta nel menu; null = tutte, a scaffali.
  final String? group;
  final String emptyText;

  @override
  State<VodBrowser<T>> createState() => _VodBrowserState<T>();
}

class _VodBrowserState<T> extends State<VodBrowser<T>> {
  T? _focused;
  late Map<String, List<T>> _shelves = _group(widget.items);

  static const _shelfLimit = 40;

  Map<String, List<T>> _group(List<T> items) {
    final m = <String, List<T>>{};
    for (final i in items) {
      m.putIfAbsent(widget.info(i).group, () => []).add(i);
    }
    return m;
  }

  @override
  void didUpdateWidget(VodBrowser<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.items, widget.items)) {
      _shelves = _group(widget.items);
      _focused = null;
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final moved =
          FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.left) ??
              false;
      if (!moved) widget.onOpenMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _poster(T item, {FocusNode? focusNode, double? width}) {
    final i = widget.info(item);
    final card = PosterCard(
      title: i.title,
      image: i.poster,
      focusNode: focusNode,
      caption: [if (i.year != null) '${i.year}', if (i.rating.isNotEmpty) '★ ${i.rating}']
          .join(' · '),
      onTap: () => widget.onOpen(item),
      onFocusChange: (f) {
        if (f && !identical(_focused, item)) setState(() => _focused = item);
      },
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.group == null
        ? widget.items
        : _shelves[widget.group] ?? <T>[];
    if (items.isEmpty) {
      return Center(
        child: Text(widget.emptyText,
            style: const TextStyle(color: VistaColors.textSecondary)),
      );
    }
    final focused = _focused ?? items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 150, child: _details(widget.info(focused))),
        const SizedBox(height: 8),
        Expanded(
          child: Focus(
            skipTraversal: true,
            canRequestFocus: false,
            onKeyEvent: _onKey,
            child: widget.group == null ? _shelfList() : _grid(items),
          ),
        ),
      ],
    );
  }

  Widget _details(VodInfo i) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(i.group.toUpperCase(),
                      style: t.labelMedium?.copyWith(
                          color: VistaColors.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  const Spacer(),
                  const VistaClock(),
                ],
              ),
              const SizedBox(height: 6),
              Text(i.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (i.rating.isNotEmpty) ...[
                    Pill('★ ${i.rating}', filled: true),
                    const SizedBox(width: 10),
                  ],
                  if (i.year != null)
                    Text('${i.year}',
                        style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 8),
              if (i.plot.isNotEmpty)
                Expanded(
                  child: Text(i.plot,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium
                          ?.copyWith(color: VistaColors.textSecondary, height: 1.35)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shelfList() {
    final t = Theme.of(context).textTheme;
    final names = _shelves.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: names.length,
      itemBuilder: (_, row) {
        final list = _shelves[names[row]]!;
        final shown = list.length > _shelfLimit ? list.sublist(0, _shelfLimit) : list;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
              child: Text('${names[row]}  ·  ${list.length}',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _poster(
                  shown[i],
                  width: 113,
                  focusNode: row == 0 && i == 0 ? widget.firstFocus : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(List<T> items) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            _poster(items[i], focusNode: i == 0 ? widget.firstFocus : null),
      );
}
