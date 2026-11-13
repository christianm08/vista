import 'package:flutter/material.dart';

import '../theme.dart';
import 'vista_focus.dart';

/// Elemento selezionabile delle schermate non ancora migrate.
///
/// Dalla fase 2 è un involucro di [VistaFocusable]: stesso fuoco a molla,
/// anello fuori dal box e nessuna animazione di layout. Sparisce nella
/// fase 7, quando tutte le schermate usano i componenti nuovi.
class FocusCard extends StatelessWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.focusScale = VistaFocus.cardScale,
    this.focusNode,
    this.radius = VistaRadius.card,
    this.fill = VistaColors.surface,
    this.selected = false,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
    this.outline = true,
  });

  /// Non più usato: le card non hanno bordo (resta per compatibilità).
  final bool outline;

  final Widget child;
  final VoidCallback onTap;

  /// Tocco lungo, oppure tasto Menu del telecomando o della tastiera.
  final VoidCallback? onLongPress;

  /// Il focus arriva o se ne va (es. per aggiornare un pannello di dettaglio).
  final ValueChanged<bool>? onFocusChange;

  /// Ingrandimento col focus; 1 per gli elementi larghi come le righe.
  final double focusScale;

  final FocusNode? focusNode;
  final double radius;
  final Color fill;
  final bool selected;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final flat = focusScale <= 1.0;
    final fg = selected ? VistaColors.background : VistaColors.text;
    return VistaFocusable(
      onTap: onTap,
      onLongPress: onLongPress,
      onFocusChange: onFocusChange,
      focusNode: focusNode,
      autofocus: autofocus,
      kind: flat ? VistaFocusKind.flat : VistaFocusKind.card,
      radius: radius,
      fill: selected ? VistaColors.text : fill,
      activeFill: selected
          ? VistaColors.text
          : (flat ? VistaColors.surfaceSelected : fill),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding,
          child: IconTheme.merge(
            data: IconThemeData(color: fg),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
