import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class _MenuIntent extends Intent {
  const _MenuIntent();
}

/// Elemento selezionabile con tocco, mouse e telecomando.
///
/// Con il focus (frecce/D-pad) mostra il contorno bianco e si ingrandisce di
/// circa 1,08×, come previsto per la TV. OK/Invio lo attivano.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.focusScale = 1.08,
    this.focusNode,
    this.radius = VistaRadius.card,
    this.fill = VistaColors.glass,
    this.selected = false,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
    this.outline = true,
  });

  /// Bordo sottile anche senza focus (no per le voci di elenchi e menu).
  final bool outline;

  final Widget child;
  final VoidCallback onTap;

  /// Tocco lungo, oppure tasto Menu del telecomando o della tastiera.
  final VoidCallback? onLongPress;

  /// Il focus arriva o se ne va (es. per aggiornare un pannello di dettaglio).
  final ValueChanged<bool>? onFocusChange;

  /// Ingrandimento col focus; 1 per gli elementi larghi come le righe.
  final double focusScale;

  /// Per spostare il focus qui da codice (es. all'apertura della home).
  final FocusNode? focusNode;
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
      focusNode: widget.focusNode,
      onFocusChange: widget.onFocusChange,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      shortcuts: widget.onLongPress == null
          ? null
          : const {
              SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
              SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  _MenuIntent(),
            },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
        if (widget.onLongPress != null)
          _MenuIntent: CallbackAction<_MenuIntent>(
            onInvoke: (_) {
              widget.onLongPress!();
              return null;
            },
          ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        child: AnimatedScale(
          scale: _focused ? widget.focusScale : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: r,
              // Col focus: contorno bianco; se la scheda è già selezionata
              // (fondo bianco) il contorno è arancio, sennò non si vedrebbe.
              border: Border.all(
                color: _focused
                    ? (widget.selected ? VistaColors.accent : Colors.white)
                    : (widget.outline
                          ? VistaColors.glassBorder
                          : Colors.transparent),
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
