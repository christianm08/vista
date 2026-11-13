import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'vista_cards.dart';
import 'vista_focus.dart';

/// Ritaglia solo ai lati: sopra e sotto l'elemento a fuoco (ingrandimento,
/// anello, ombra) resta libero.
class _SidesClipper extends CustomClipper<Rect> {
  const _SidesClipper(this.left);

  /// Bordo sinistro: dove finisce la card precedente quando quella a fuoco è
  /// agganciata al margine. Di lei non si vede una striscia tagliata; la
  /// card a fuoco, ingrandita, ci sta ancora dentro.
  final double left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    left,
    -VistaSpace.s64,
    size.width,
    size.height + VistaSpace.s64,
  );

  @override
  bool shouldReclip(_SidesClipper old) => old.left != left;
}

/// Ritaglia solo in alto: il bordo della zona delle righe sotto l'anteprima.
class _TopClipper extends CustomClipper<Rect> {
  const _TopClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -VistaSpace.s64,
    0,
    size.width + VistaSpace.s64,
    size.height + VistaSpace.s64,
  );

  @override
  bool shouldReclip(_TopClipper old) => false;
}

/// Riga orizzontale con titolo (Home, Scopri, dettaglio).
///
/// - L'elemento a fuoco si aggancia al margine sinistro: scorre la riga, non
///   il fuoco. Lo scorrimento è animato, interrompibile, e riparte sempre
///   dalla posizione corrente.
/// - Ritaglia solo ai lati, al bordo dell'area dei contenuti; sopra e sotto
///   le card c'è uno spazio riservato più grande di quanto sporge la card a
///   fuoco.
/// - Ricorda l'ultimo elemento a fuoco: entrando dall'alto o dal basso si
///   torna lì.
/// - [itemKey] lega ogni elemento al suo contenuto (non alla posizione).
///
/// Va usata dentro una [VistaRowsPage], che toglie lo scorrimento automatico
/// di Flutter (vedi [VistaTraversalPolicy]).
class VistaRow extends StatefulWidget {
  const VistaRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required this.itemWidth,
    required this.itemHeight,
    this.trailing,
  });

  final String title;
  final int itemCount;
  final Key Function(int index) itemKey;
  final IndexedWidgetBuilder itemBuilder;

  /// Larghezza a riposo di un elemento.
  final double itemWidth;

  /// Altezza di un elemento (immagine più testo).
  final double itemHeight;
  final Widget? trailing;

  @override
  State<VistaRow> createState() => _VistaRowState();
}

class _VistaRowState extends State<VistaRow> {
  final _scroll = ScrollController();

  /// Un nodo "contenitore" per elemento, per ritrovarlo e ridargli il fuoco.
  final _slots = <Key, FocusNode>{};
  Key? _remembered;

  double get _extent => widget.itemWidth + VistaLayout.of(context).rowSpacing;

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _slots.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _itemFocused(int index, Key key) {
    _remembered = key;
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (!p.hasContentDimensions) return;
    final start = index * _extent;
    final target = start.clamp(p.minScrollExtent, p.maxScrollExtent);
    // Col tasto tenuto premuto il fuoco corre più dello scorrimento: se la
    // riga è rimasta indietro, recupera di scatto quanto basta perché
    // l'elemento a fuoco sia tutto in vista, poi anima il resto.
    final g = VistaLayout.of(context).gutter;
    final seen = p.pixels
        .clamp(
          start + widget.itemWidth + g * 2 - p.viewportDimension,
          start + g,
        )
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    if (seen != p.pixels) p.jumpTo(seen);
    _animate(p, target);
  }

  void _animate(ScrollPosition p, double target) {
    if (target == p.pixels) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      p.jumpTo(target);
    } else {
      p.animateTo(
        target,
        duration: VistaMotion.rowScroll,
        curve: VistaMotion.enter,
      );
    }
  }

  /// Il fuoco entra nella riga da fuori: torna sull'ultimo elemento visto.
  void _rowFocusChanged(bool has) {
    if (!has) return;
    final slot = _remembered == null ? null : _slots[_remembered];
    final primary = FocusManager.instance.primaryFocus;
    if (slot == null || slot.context == null || primary == null) return;
    if (primary == slot || primary.ancestors.contains(slot)) return;
    final target = slot.descendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .firstOrNull;
    target?.requestFocus();
  }

  int? _indexOf(Key key) {
    for (var i = 0; i < widget.itemCount; i++) {
      if (widget.itemKey(i) == key) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    final reserve = layout.rowReserve;
    final spacing = layout.rowSpacing;
    // Elementi tolti dalla lista: via anche i loro nodi, dopo che i loro
    // widget sono usciti dall'albero.
    final live = {for (var i = 0; i < widget.itemCount; i++) widget.itemKey(i)};
    final gone = [
      for (final e in _slots.entries)
        if (!live.contains(e.key)) e,
    ];
    for (final e in gone) {
      _slots.remove(e.key);
      WidgetsBinding.instance.addPostFrameCallback((_) => e.value.dispose());
    }
    if (_remembered != null && !live.contains(_remembered)) _remembered = null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: SectionTitle(widget.title, trailing: widget.trailing),
        ),
        ClipRect(
          clipper: _SidesClipper(g - spacing),
          child: SizedBox(
            height: widget.itemHeight + reserve * 2,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: _rowFocusChanged,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: g, vertical: reserve),
                itemExtent: widget.itemWidth + spacing,
                itemCount: widget.itemCount,
                findChildIndexCallback: (key) => _indexOf(key),
                itemBuilder: (context, i) {
                  final key = widget.itemKey(i);
                  final slot = _slots.putIfAbsent(
                    key,
                    () => FocusNode(
                      canRequestFocus: false,
                      skipTraversal: true,
                      debugLabel: 'VistaRow slot $key',
                    ),
                  );
                  return KeyedSubtree(
                    key: key,
                    child: Focus(
                      focusNode: slot,
                      onFocusChange: (has) {
                        if (has) _itemFocused(i, key);
                      },
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: widget.itemWidth,
                          height: widget.itemHeight,
                          child: widget.itemBuilder(context, i),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Riga in caricamento: segnaposto a tinta piatta, delle stesse misure.
class VistaRowSkeleton extends StatelessWidget {
  const VistaRowSkeleton({
    super.key,
    required this.title,
    required this.itemWidth,
    required this.itemHeight,
    required this.aspect,
  });

  final String title;
  final double itemWidth;
  final double itemHeight;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    final reserve = layout.rowReserve;
    final spacing = layout.rowSpacing;
    final count = (layout.width / (itemWidth + spacing)).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: SectionTitle(title),
        ),
        ClipRect(
          child: SizedBox(
            height: itemHeight + reserve * 2,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              child: Padding(
                padding: EdgeInsets.fromLTRB(g, reserve, 0, reserve),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < count; i++)
                      Padding(
                        padding: EdgeInsets.only(right: spacing),
                        child: SizedBox(
                          width: itemWidth,
                          child: VistaCardSkeleton(aspect: aspect),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pagina fatta di righe, con una zona fissa in alto (l'anteprima) opzionale.
///
/// Scendendo, la riga a fuoco si aggancia in cima alla zona delle righe (con
/// lo spazio riservato sopra le card); le precedenti escono in alto. È
/// l'unico responsabile dello scorrimento verticale.
class VistaRowsPage extends StatefulWidget {
  const VistaRowsPage({
    super.key,
    required this.rows,
    this.header,
    this.headerHeight = 0,
  });

  /// Le righe: ognuna con una chiave stabile.
  final List<Widget> rows;

  /// Zona fissa in alto (es. anteprima del contenuto a fuoco).
  final Widget? header;
  final double headerHeight;

  @override
  State<VistaRowsPage> createState() => _VistaRowsPageState();
}

class _VistaRowsPageState extends State<VistaRowsPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rowFocused(BuildContext rowContext) {
    final box = rowContext.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final p = _scroll.position;
    if (viewport == null || !p.hasContentDimensions) return;
    double reveal(double alignment) => viewport
        .getOffsetToReveal(box, alignment)
        .offset
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    final target = reveal(0);
    // Come nelle righe: se la pagina è rimasta indietro, recupera di scatto
    // quanto basta perché la riga a fuoco sia tutta in vista.
    final low = reveal(1);
    final seen = p.pixels.clamp(
      low < target ? low : target,
      low < target ? target : low,
    );
    if (seen != p.pixels) p.jumpTo(seen);
    if (target == p.pixels) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      p.jumpTo(target);
    } else {
      p.animateTo(
        target,
        duration: VistaMotion.pageScroll,
        curve: VistaMotion.enter,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final between = layout.rowGap - layout.rowReserve;
    final rows = SingleChildScrollView(
      controller: _scroll,
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: layout.rowGap + layout.safe.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in widget.rows.indexed) ...[
            if (i > 0) SizedBox(height: between),
            _PageSlot(
              key: row.key ?? ValueKey(i),
              onFocused: _rowFocused,
              child: row,
            ),
          ],
        ],
      ),
    );
    return FocusTraversalGroup(
      policy: VistaTraversalPolicy(),
      child: widget.header == null
          ? ClipRect(clipper: const _TopClipper(), child: rows)
          : Stack(
              children: [
                Positioned.fill(
                  top: widget.headerHeight,
                  child: ClipRect(clipper: const _TopClipper(), child: rows),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: widget.headerHeight,
                  child: widget.header!,
                ),
              ],
            ),
    );
  }
}

class _PageSlot extends StatelessWidget {
  const _PageSlot({super.key, required this.onFocused, required this.child});
  final void Function(BuildContext) onFocused;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (has) {
      if (has) onFocused(context);
    },
    child: child,
  );
}
