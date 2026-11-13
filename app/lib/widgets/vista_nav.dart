import 'package:flutter/material.dart';

import '../theme.dart';
import 'vista_focus.dart';
import 'vista_mark.dart';

/// Una voce di navigazione.
class VistaNavItem {
  const VistaNavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Ritaglio che rivela la barra laterale da sinistra. Cambia solo il
/// disegno (e il tocco): il layout resta fermo.
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.width) : super(reclip: width);
  final Animation<double> width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width.value, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.width != width;
}

/// Barra laterale (TV, PC, tablet).
///
/// Chiusa mostra solo le icone; col fuoco o col mouse si apre sopra il
/// contenuto, piena e opaca, con le etichette. Va messa in uno spazio largo
/// [VistaSize.railExpanded]: la parte non rivelata non disegna e non riceve
/// tocchi, e il contenuto accanto inizia a [VistaLayout.contentLeft].
class VistaRail extends StatefulWidget {
  const VistaRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.footer,
    this.focusNodes,
    this.open,
    this.onOpenChanged,
    this.caption = '',
  });

  final List<VistaNavItem> items;

  /// Riga piccola sotto l'ultima voce, visibile a barra aperta (es. la lista).
  final String caption;

  /// Voce in fondo (Impostazioni); il suo indice è `items.length`.
  final VistaNavItem? footer;

  /// Voce attiva (indice in [items], o `items.length` per [footer]).
  final int selected;
  final ValueChanged<int> onSelect;

  /// Nodi di fuoco delle voci (stesso ordine, [footer] per ultimo).
  final List<FocusNode>? focusNodes;

  /// Forza l'apertura; se null si apre da sola con fuoco o mouse.
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<VistaRail> createState() => _VistaRailState();
}

class _VistaRailState extends State<VistaRail>
    with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    duration: VistaMotion.railReveal,
  );
  late final _curve = CurvedAnimation(
    parent: _reveal,
    curve: VistaMotion.enter,
    reverseCurve: VistaMotion.exit,
  );
  bool _focus = false;
  bool _hover = false;
  bool _lastOpen = false;

  bool get _open => widget.open ?? (_focus || _hover);

  @override
  void didUpdateWidget(VistaRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) _sync();
  }

  void _set(VoidCallback change) {
    setState(change);
    _sync();
  }

  @override
  void dispose() {
    _curve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _sync() {
    final open = _open;
    if (open == _lastOpen) return;
    _lastOpen = open;
    widget.onOpenChanged?.call(open);
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _reveal.value = open ? 1 : 0;
    } else if (open) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final collapsed = layout.railWidth;
    final inset = layout.railInset;
    final width = Tween<double>(
      begin: collapsed,
      end: VistaSize.railExpanded,
    ).animate(_curve);
    final all = [...widget.items, ?widget.footer];

    Widget item(int i) => _RailItem(
      item: all[i],
      selected: i == widget.selected,
      reveal: _curve,
      focusNode: widget.focusNodes?[i],
      onTap: () => widget.onSelect(i),
    );

    return MouseRegion(
      onEnter: (_) => _set(() => _hover = true),
      onExit: (_) => _set(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (v) => _set(() => _focus = v),
        child: ClipRect(
          clipper: _RevealClipper(width),
          child: AnimatedBuilder(
            animation: _curve,
            builder: (_, c) => ColoredBox(
              color: Color.lerp(
                VistaColors.background,
                VistaColors.surface,
                _curve.value,
              )!,
              child: c,
            ),
            child: SizedBox(
              width: VistaSize.railExpanded,
              child: SafeArea(
                right: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    inset,
                    VistaSpace.s32 + layout.safe.top,
                    VistaSpace.s16,
                    VistaSpace.s32 + layout.safe.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: VistaSize.railItemWidth,
                          child: Center(
                            child: VistaMark(size: VistaSize.railMark),
                          ),
                        ),
                      ),
                      const SizedBox(height: VistaSpace.s32),
                      for (var i = 0; i < widget.items.length; i++) ...[
                        if (i > 0) const SizedBox(height: VistaSpace.s8),
                        item(i),
                      ],
                      const Spacer(),
                      if (widget.footer != null) item(widget.items.length),
                      if (widget.caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: VistaSpace.s16,
                            top: VistaSpace.s8,
                          ),
                          child: FadeTransition(
                            opacity: _curve,
                            child: Text(
                              widget.caption,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.reveal,
    required this.onTap,
    this.focusNode,
  });

  final VistaNavItem item;
  final bool selected;
  final Animation<double> reveal;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = selected ? VistaColors.text : VistaColors.textSecondary;
    return SizedBox(
      height: VistaSize.railItemHeight,
      child: VistaFocusable(
        onTap: onTap,
        focusNode: focusNode,
        kind: VistaFocusKind.flat,
        radius: VistaRadius.full,
        activeFill: selected ? null : VistaColors.surfaceHigh,
        semanticLabel: item.label,
        child: AnimatedBuilder(
          animation: reveal,
          builder: (context, c) => CustomPaint(
            // Pillola della voce attiva: larga quanto l'icona da chiusa,
            // quanto la voce da aperta. Solo disegno, niente layout.
            painter: selected ? _PillPainter(reveal.value) : null,
            child: c,
          ),
          child: Row(
            children: [
              SizedBox(
                width: VistaSize.railItemWidth,
                child: Icon(item.icon, color: fg),
              ),
              Expanded(
                child: FadeTransition(
                  opacity: reveal,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: t.bodyLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? VistaType.strong : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w =
        VistaSize.railItemWidth + (size.width - VistaSize.railItemWidth) * t;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, size.height),
        Radius.circular(size.height / 2),
      ),
      Paint()..color = VistaColors.surfaceSelected,
    );
  }

  @override
  bool shouldRepaint(_PillPainter old) => old.t != t;
}

/// Barra in basso del telefono: [NavigationBar] M3 ritematizzata.
///
/// [selected] null: la sezione aperta non è nella barra (Cerca,
/// Impostazioni), quindi nessuna voce è evidenziata.
class VistaNavBar extends StatelessWidget {
  const VistaNavBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<VistaNavItem> items;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bar = NavigationBar(
      selectedIndex: selected ?? 0,
      onDestinationSelected: onSelect,
      destinations: [
        for (final i in items)
          NavigationDestination(icon: Icon(i.icon), label: i.label),
      ],
    );
    if (selected != null) return bar;
    final theme = NavigationBarTheme.of(context);
    final t = Theme.of(context).textTheme;
    return NavigationBarTheme(
      data: theme.copyWith(
        indicatorColor: VistaColors.transparent,
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(size: VistaSize.icon, color: VistaColors.textSecondary),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          t.labelSmall?.copyWith(color: VistaColors.textSecondary),
        ),
      ),
      child: bar,
    );
  }
}
