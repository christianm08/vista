import 'package:flutter/material.dart';

import '../theme.dart';
import 'vista_focus.dart';

/// Pulsante: [VistaButton.primary] (accento, l'azione principale della
/// schermata) o [VistaButton.tonal] (azioni secondarie).
///
/// È un [FilledButton] ritematizzato; il fuoco (scala 1,04, anello bianco,
/// ombra) lo disegna [VistaStatesFocusEffect] attorno al pulsante.
class VistaButton extends StatefulWidget {
  const VistaButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
  }) : primary = true,
       tint = null,
       onTint = null;

  const VistaButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.tint,
    this.onTint,
  }) : primary = false;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool primary;

  /// Fondo e testo presi dall'artwork (dettaglio); altrimenti i neutri.
  final Color? tint;
  final Color? onTint;

  @override
  State<VistaButton> createState() => _VistaButtonState();
}

class _VistaButtonState extends State<VistaButton> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final layout = VistaLayout.of(context);
    final bg = w.primary
        ? VistaColors.accent
        : (w.tint ?? VistaColors.surfaceHigh);
    final fg = w.primary
        ? VistaColors.onAccent
        : (w.onTint ?? VistaColors.text);
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? VistaColors.surface : bg,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.disabled) ? VistaColors.textSecondary : fg,
      ),
      minimumSize: WidgetStatePropertyAll(
        Size(VistaSize.minTouch, layout.buttonHeight),
      ),
      // L'anello lo disegna VistaStatesFocusEffect, fuori dal pulsante.
      side: const WidgetStatePropertyAll(BorderSide.none),
    );
    final child = w.icon == null
        ? FilledButton(
            onPressed: w.onPressed,
            autofocus: w.autofocus,
            focusNode: w.focusNode,
            statesController: _states,
            style: style,
            child: Text(w.label),
          )
        : FilledButton.icon(
            onPressed: w.onPressed,
            autofocus: w.autofocus,
            focusNode: w.focusNode,
            statesController: _states,
            style: style,
            icon: Icon(w.icon),
            label: Text(w.label),
          );
    return VistaStatesFocusEffect(states: _states, child: child);
  }
}

/// Pulsante tondo con sola icona (48×48), tonale.
class VistaIconButton extends StatefulWidget {
  const VistaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<VistaIconButton> createState() => _VistaIconButtonState();
}

class _VistaIconButtonState extends State<VistaIconButton> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = Size.square(VistaSize.minTouch);
    return Tooltip(
      message: widget.tooltip,
      child: VistaStatesFocusEffect(
        states: _states,
        child: FilledButton(
          onPressed: widget.onPressed,
          autofocus: widget.autofocus,
          focusNode: widget.focusNode,
          statesController: _states,
          style: const ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(VistaColors.surfaceHigh),
            foregroundColor: WidgetStatePropertyAll(VistaColors.text),
            minimumSize: WidgetStatePropertyAll(size),
            fixedSize: WidgetStatePropertyAll(size),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            shape: WidgetStatePropertyAll(CircleBorder()),
            side: WidgetStatePropertyAll(BorderSide.none),
          ),
          child: Icon(widget.icon),
        ),
      ),
    );
  }
}

/// Chip per filtri e scelte (categorie, qualità).
///
/// Non selezionato: superficie piena; selezionato: testo chiaro su fondo
/// scuro invertito. Col fuoco: anello vicino, senza scala, e (se non è
/// selezionato) superficie un gradino più chiara.
class VistaChip extends StatelessWidget {
  const VistaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final fg = selected ? VistaColors.background : VistaColors.text;
    final chip = VistaFocusable(
      onTap: onSelected,
      autofocus: autofocus,
      focusNode: focusNode,
      kind: VistaFocusKind.flat,
      radius: VistaRadius.chip,
      fill: selected ? VistaColors.text : VistaColors.surface,
      activeFill: selected ? VistaColors.text : VistaColors.surfaceHigh,
      semanticLabel: label,
      child: SizedBox(
        height: layout.chipHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: VistaSize.iconSmall, color: fg),
                const SizedBox(width: VistaSpace.s8),
              ],
              Text(
                label,
                style: t.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? VistaType.strong : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final result = Semantics(selected: selected, child: chip);
    if (!layout.compact) return result;
    // Sul telefono il bersaglio al tocco è alto almeno 48.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onSelected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VistaSize.minTouch),
        child: Center(widthFactor: 1, child: result),
      ),
    );
  }
}

/// Voce di una finestra di dialogo o di un menu: a fuoco superficie più
/// chiara e anello, senza scala (le voci Material non mostrano il fuoco: il
/// tema lo spegne). Con [selected] non nullo c'è la colonna della spunta,
/// piena sulla scelta attuale, che ha anche il fuoco all'apertura.
class VistaChoice extends StatelessWidget {
  const VistaChoice({
    super.key,
    required this.child,
    required this.onTap,
    this.selected,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool? selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: VistaSpace.s16,
      vertical: VistaSpace.s4,
    ),
    // Il fuoco non fa scorrere da solo (VistaTraversalPolicy): un elenco
    // lungo porta al centro la voce a fuoco.
    child: Focus(
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
      child: VistaFocusable(
        autofocus: autofocus || (selected ?? false),
        kind: VistaFocusKind.flat,
        radius: VistaRadius.chip,
        fill: VistaColors.transparent,
        activeFill: VistaColors.surfaceSelected,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VistaSize.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VistaSpace.s12,
              vertical: VistaSpace.s8,
            ),
            child: Row(
              children: [
                if (selected case final s?)
                  SizedBox(
                    width: VistaSize.icon + VistaSpace.s12,
                    child: s
                        ? const Icon(Icons.check_rounded)
                        : const SizedBox.shrink(),
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
