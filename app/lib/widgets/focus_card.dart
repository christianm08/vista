import 'package:flutter/material.dart';

import '../theme.dart';

/// Elemento selezionabile con tocco, mouse e telecomando.
///
/// Con il focus (frecce/D-pad) mostra il contorno bianco e si ingrandisce di
/// circa 1,08×, come previsto per la TV. OK/Invio lo attivano.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = VistaRadius.card,
    this.fill = VistaColors.glass,
    this.selected = false,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final Color fill;
  final bool selected;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    final fill = widget.selected
        ? Colors.white
        : (_hovered ? VistaColors.glassHigh : widget.fill);
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: r,
              border: Border.all(
                color: _focused ? Colors.white : VistaColors.glassBorder,
                width: _focused ? 3 : 1,
              ),
              boxShadow: _focused
                  ? [const BoxShadow(color: Color(0x66000000), blurRadius: 24)]
                  : null,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: widget.selected ? VistaColors.onPrimary : Colors.white,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
