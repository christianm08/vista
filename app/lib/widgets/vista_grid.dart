import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'vista_cards.dart';
import 'vista_focus.dart';

/// Griglia di locandine 2:3 (Film, Serie, elenchi completi di Scopri).
///
/// - È l'unica responsabile dello scorrimento: quando un elemento prende il
///   fuoco, la pagina scorre il minimo perché la sua fila sia tutta in vista,
///   con lo spazio riservato sopra e sotto (ingrandimento e anello).
/// - Le colonne si ricavano dalla larghezza: locandine larghe circa quanto
///   quelle delle righe della Home.
/// - [header] scorre con la griglia; quando prende il fuoco la pagina torna
///   in cima.
/// - [itemKey] lega ogni elemento al suo contenuto: riordinando, il fuoco e
///   lo stato seguono il titolo, non la posizione.
class VistaPosterGrid extends StatefulWidget {
  const VistaPosterGrid({
    super.key,
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    this.header,
    this.footer,
    this.padding = EdgeInsets.zero,
    this.onNearEnd,
    this.onExitLeft,
  });

  final int itemCount;
  final Key Function(int index) itemKey;

  /// L'elemento [index], largo [width] a riposo.
  final Widget Function(BuildContext context, int index, double width)
  itemBuilder;
  final Widget? header;
  final Widget? footer;

  /// Margini della griglia (non dell'intestazione).
  final EdgeInsets padding;

  /// Mancano due file alla fine (per caricare la pagina successiva).
  final VoidCallback? onNearEnd;

  /// Freccia sinistra dalla prima colonna (es. verso le categorie).
  final VoidCallback? onExitLeft;

  @override
  State<VistaPosterGrid> createState() => _VistaPosterGridState();
}

class _VistaPosterGridState extends State<VistaPosterGrid> {
  final _scroll = ScrollController();
  int _cols = 1;
  int? _focused;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _to(double target) {
    final p = _scroll.position;
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

  /// Scorre il minimo perché [item] sia in vista con lo spazio riservato.
  void _reveal(BuildContext item) {
    final box = item.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final p = _scroll.position;
    if (viewport == null || !p.hasContentDimensions) return;
    final reserve = VistaLayout.of(context).rowReserve;
    // Posizioni della pagina con l'elemento in cima e in fondo alla vista.
    final top = viewport.getOffsetToReveal(box, 0).offset - reserve;
    final bottom = viewport.getOffsetToReveal(box, 1).offset + reserve;
    final target = (bottom > top ? top : p.pixels.clamp(bottom, top)).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    // Col tasto tenuto premuto il fuoco corre più dello scorrimento: se
    // l'elemento è del tutto fuori vista si recupera di scatto.
    final h = box.size.height;
    if (p.pixels > top + h + reserve || p.pixels < bottom - h - reserve) {
      p.jumpTo(target);
    } else {
      _to(target);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final exit = widget.onExitLeft;
    if (exit == null ||
        e is KeyUpEvent ||
        e.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final i = _focused;
    if (i == null || i % _cols != 0) return KeyEventResult.ignored;
    if (e is KeyDownEvent) exit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final gap = layout.rowSpacing;
    final reserve = layout.rowReserve;
    final pad = widget.padding;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - pad.horizontal;
        _cols = ((w + gap) / (layout.posterWidth + gap)).floor().clamp(2, 12);
        final itemW = (w - gap * (_cols - 1)) / _cols;
        final itemH = VistaPosterCard.heightFor(context, itemW, true);
        return FocusTraversalGroup(
          policy: VistaTraversalPolicy(),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (widget.header case final header?)
                  SliverToBoxAdapter(
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (has) {
                        if (has && _scroll.hasClients) {
                          _focused = null;
                          _to(_scroll.position.minScrollExtent);
                        }
                      },
                      child: header,
                    ),
                  ),
                SliverPadding(
                  // Sopra la prima fila, spazio per l'anello.
                  padding: pad.copyWith(top: pad.top + reserve),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                      mainAxisExtent: itemH,
                    ),
                    itemCount: widget.itemCount,
                    itemBuilder: (context, i) {
                      if (widget.onNearEnd != null &&
                          i >= widget.itemCount - _cols * 2) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) widget.onNearEnd?.call();
                        });
                      }
                      return KeyedSubtree(
                        key: widget.itemKey(i),
                        child: Builder(
                          builder: (context) => Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: (has) {
                              if (!has) return;
                              _focused = i;
                              _reveal(context);
                            },
                            child: widget.itemBuilder(context, i, itemW),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.footer case final footer?)
                  SliverToBoxAdapter(child: footer),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Griglia in caricamento: segnaposto a tinta piatta delle misure delle
/// locandine, quanti ne servono per riempire la vista.
class VistaPosterGridSkeleton extends StatelessWidget {
  const VistaPosterGridSkeleton({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final gap = layout.rowSpacing;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - padding.horizontal;
        final cols = ((w + gap) / (layout.posterWidth + gap)).floor().clamp(
          2,
          12,
        );
        final itemW = (w - gap * (cols - 1)) / cols;
        final itemH = VistaPosterCard.heightFor(context, itemW, true);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding.copyWith(top: padding.top + layout.rowReserve),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: itemH,
          ),
          itemCount: cols * 3,
          itemBuilder: (_, _) =>
              const VistaCardSkeleton(aspect: VistaPosterCard.aspect),
        );
      },
    );
  }
}
