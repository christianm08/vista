import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Che aspetto prende un elemento col fuoco.
enum VistaFocusKind {
  /// Card e poster: scala 1,06, anello staccato, ombra.
  card,

  /// Pulsanti: scala 1,04, anello staccato, ombra.
  button,

  /// Celle della guida, chip, voci di menu: niente scala né ombra; anello
  /// vicino e superficie un gradino più chiara.
  flat,
}

extension on VistaFocusKind {
  double get scale => switch (this) {
    VistaFocusKind.card => VistaFocus.cardScale,
    VistaFocusKind.button => VistaFocus.buttonScale,
    VistaFocusKind.flat => 1.0,
  };

  double get gap => this == VistaFocusKind.flat
      ? VistaFocus.ringGapTight
      : VistaFocus.ringGap;

  bool get shadow => this != VistaFocusKind.flat;
}

/// Regola di navigazione col telecomando: sposta solo il fuoco.
///
/// Flutter, di suo, a ogni spostamento chiama `Scrollable.ensureVisible` su
/// tutti gli scrollable antenati, di scatto e a filo del bordo. Qui no: lo
/// scorrimento lo decidono la riga ([VistaRow], in orizzontale) e la pagina
/// ([VistaRowsPage], in verticale). Un solo responsabile per asse.
class VistaTraversalPolicy extends ReadingOrderTraversalPolicy {
  VistaTraversalPolicy() : super(requestFocusCallback: _focusOnly);

  static void _focusOnly(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) => node.requestFocus();
}

/// Molla che, ferma, vale esattamente il suo obiettivo: a riposo ogni
/// elemento è a scala 1 e spostamento 0, non "quasi".
SpringSimulation _spring(double from, double to, double velocity) =>
    SpringSimulation(
      VistaMotion.focusSpring,
      from,
      to,
      velocity,
      snapToEnd: true,
    );

/// Aspetto del fuoco: scala a molla, anello disegnato fuori dal box, ombra.
///
/// Dipende da un solo stato, [active]. Ogni cambio riparte dal valore e dalla
/// velocità correnti verso il nuovo obiettivo: niente sequenze né ritardi.
/// Anima solo trasformazioni e colori: il layout non si muove mai.
class VistaFocusEffect extends StatefulWidget {
  const VistaFocusEffect({
    super.key,
    required this.active,
    required this.child,
    this.kind = VistaFocusKind.card,
    this.radius = VistaRadius.card,
    this.elevated = true,
    this.fill,
    this.activeFill,
  });

  /// A fuoco (o sotto il mouse).
  final bool active;
  final VistaFocusKind kind;
  final double radius;

  /// Ombra (sì col fuoco, no col solo passaggio del mouse).
  final bool elevated;

  /// Riempimento a riposo e a fuoco (per [VistaFocusKind.flat]).
  final Color? fill;
  final Color? activeFill;
  final Widget child;

  @override
  State<VistaFocusEffect> createState() => VistaFocusEffectState();
}

class VistaFocusEffectState extends State<VistaFocusEffect>
    with TickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: VistaMotion.focusRingFade,
    value: 0,
  );
  bool _reduce = false;

  /// Avanzamento della scala: 0 a riposo, 1 a fuoco (solo per i test).
  @visibleForTesting
  double get scaleProgress => _scale.value;

  /// Scala effettiva in questo momento.
  double get scale => 1 + (widget.kind.scale - 1) * _scale.value;

  /// Opacità dell'anello: 0 a riposo, 1 a fuoco.
  double get ringOpacity => _ring.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduce) {
      _reduce = reduce;
      _go();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _go();
      });
    }
  }

  @override
  void didUpdateWidget(VistaFocusEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _go();
  }

  void _go() {
    final target = widget.active ? 1.0 : 0.0;
    _ring.animateTo(
      target,
      duration: _reduce ? VistaMotion.reducedFade : VistaMotion.focusRingFade,
      curve: VistaMotion.focusRingCurve,
    );
    if (_reduce || widget.kind.scale == 1.0) {
      _scale.value = 0;
      return;
    }
    if (_scale.value == target && !_scale.isAnimating) return;
    _scale.animateWith(_spring(_scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    Widget content = RepaintBoundary(child: w.child);
    if (w.fill != null || w.activeFill != null) {
      final rest = w.fill ?? VistaColors.transparent;
      final on = w.activeFill ?? rest;
      content = AnimatedBuilder(
        animation: _ring,
        builder: (_, c) => DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(rest, on, _ring.value),
            borderRadius: BorderRadius.circular(w.radius),
          ),
          child: c,
        ),
        child: content,
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_scale, _ring]),
      builder: (context, c) {
        final s = scale;
        return Transform.scale(
          scale: s,
          child: CustomPaint(
            painter: w.kind.shadow && w.elevated
                ? _ShadowPainter(w.radius, _ring.value)
                : null,
            foregroundPainter: _RingPainter(
              radius: w.radius,
              gap: w.kind.gap,
              opacity: _ring.value,
              scale: s,
            ),
            child: c,
          ),
        );
      },
      child: content,
    );
  }
}

/// Anello di fuoco fuori dal box. Diviso per la scala corrente, così sullo
/// schermo resta sempre di 3 px e staccato sempre dello stesso spazio.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.radius,
    required this.gap,
    required this.opacity,
    required this.scale,
  });

  final double radius;
  final double gap;
  final double opacity;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final width = VistaFocus.ringWidth / scale;
    final offset = gap / scale + width / 2;
    final rect = (Offset.zero & size).inflate(offset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = VistaColors.focusRing.withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + offset)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.opacity != opacity ||
      old.scale != scale ||
      old.radius != radius ||
      old.gap != gap;
}

/// L'unica ombra dell'app, sotto l'elemento a fuoco.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.radius, this.opacity);
  final double radius;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    const s = VistaFocus.shadow;
    final paint = s.toPaint()
      ..color = s.color.withValues(alpha: s.color.a * opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).shift(s.offset),
        Radius.circular(radius),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.opacity != opacity || old.radius != radius;
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

/// Elemento selezionabile con tocco, mouse e telecomando: card, poster, voci.
///
/// Il fuoco si vede solo con tastiera e telecomando (col tocco no); il mouse
/// dà lo stesso aspetto, senza ombra. OK/Invio lo attivano, il tasto Menu (o
/// Shift+F10, o il tocco lungo) apre il menu.
///
/// Nelle liste dagli una chiave legata al contenuto (`ValueKey(id)`): lo stato
/// del fuoco segue il contenuto, non la posizione.
class VistaFocusable extends StatefulWidget {
  const VistaFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.kind = VistaFocusKind.card,
    this.radius = VistaRadius.card,
    this.fill,
    this.activeFill,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final VistaFocusKind kind;
  final double radius;
  final Color? fill;
  final Color? activeFill;
  final String? semanticLabel;

  @override
  State<VistaFocusable> createState() => _VistaFocusableState();
}

/// Quanti elementi mostrano ora il fuoco da tastiera o telecomando. Finché
/// ce n'è uno, il passaggio del mouse non disegna un secondo anello: vince
/// il fuoco.
var _keyboardFocusCount = 0;
final _keyboardFocusShown = ValueNotifier<bool>(false);

void _countKeyboardFocus(int delta) {
  _keyboardFocusCount += delta;
  // Notifica solo quando si passa da "nessuno" a "qualcuno" e viceversa:
  // spostando il fuoco non si ricostruiscono tutte le card.
  void notify() => _keyboardFocusShown.value = _keyboardFocusCount > 0;
  // Durante build e smontaggio (es. si lascia una pagina con una card a
  // fuoco) l'albero è bloccato: si notifica a fine frame.
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    SchedulerBinding.instance.addPostFrameCallback((_) => notify());
  } else {
    notify();
  }
}

class _VistaFocusableState extends State<VistaFocusable> {
  bool _focused = false;
  bool _hovered = false;

  void _setFocused(bool v) {
    if (v == _focused) return;
    _countKeyboardFocus(v ? 1 : -1);
    setState(() => _focused = v);
  }

  @override
  void dispose() {
    if (_focused) _countKeyboardFocus(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: w.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: w.autofocus,
        focusNode: w.focusNode,
        onFocusChange: w.onFocusChange,
        onShowFocusHighlight: _setFocused,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        shortcuts: w.onLongPress == null
            ? null
            : const {
                SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
                SingleActivator(LogicalKeyboardKey.f10, shift: true):
                    _MenuIntent(),
              },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              w.onTap?.call();
              return null;
            },
          ),
          if (w.onLongPress != null)
            _MenuIntent: CallbackAction<_MenuIntent>(
              onInvoke: (_) {
                w.onLongPress!();
                return null;
              },
            ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.onTap,
          onLongPress: w.onLongPress,
          onSecondaryTap: w.onLongPress,
          child: ValueListenableBuilder<bool>(
            valueListenable: _keyboardFocusShown,
            builder: (_, shown, child) => VistaFocusEffect(
              active: _focused || (_hovered && !shown),
              elevated: _focused,
              kind: w.kind,
              radius: w.radius,
              fill: w.fill,
              activeFill: w.activeFill,
              child: child!,
            ),
            child: w.child,
          ),
        ),
      ),
    );
  }
}

/// Mostra il fuoco di un controllo Material ([FilledButton], …) con lo
/// stesso aspetto di [VistaFocusable], leggendo gli stati del controllo.
class VistaStatesFocusEffect extends StatefulWidget {
  const VistaStatesFocusEffect({
    super.key,
    required this.states,
    required this.child,
    this.kind = VistaFocusKind.button,
    this.radius = VistaRadius.full,
  });

  final WidgetStatesController states;
  final VistaFocusKind kind;
  final double radius;
  final Widget child;

  @override
  State<VistaStatesFocusEffect> createState() => _VistaStatesFocusEffectState();
}

class _VistaStatesFocusEffectState extends State<VistaStatesFocusEffect> {
  /// Questo controllo mostra il fuoco da tastiera o telecomando (conta per
  /// [_keyboardFocusShown], come le card).
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.states.addListener(_changed);
    FocusManager.instance.addHighlightModeListener(_mode);
  }

  @override
  void didUpdateWidget(VistaStatesFocusEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.states != widget.states) {
      oldWidget.states.removeListener(_changed);
      widget.states.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.states.removeListener(_changed);
    FocusManager.instance.removeHighlightModeListener(_mode);
    if (_shown) _countKeyboardFocus(-1);
    super.dispose();
  }

  void _changed() {
    // Il pulsante (figlio) imposta i suoi stati in initState, mentre si
    // costruisce: si ridisegna dopo il frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changed();
      });
      return;
    }
    setState(() {});
    _sync();
  }

  void _mode(FocusHighlightMode _) {
    setState(() {});
    _sync();
  }

  bool get _focused =>
      widget.states.value.contains(WidgetState.focused) &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _sync() {
    final v = _focused;
    if (v == _shown) return;
    _shown = v;
    void apply() => _countKeyboardFocus(v ? 1 : -1);
    // Gli stati possono cambiare mentre si costruisce: si conta dopo.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final hovered = widget.states.value.contains(WidgetState.hovered);
    // Come per le card: se qualcosa ha il fuoco, il mouse non disegna un
    // secondo anello.
    return ValueListenableBuilder<bool>(
      valueListenable: _keyboardFocusShown,
      builder: (_, shown, child) => VistaFocusEffect(
        active: focused || (hovered && !shown),
        elevated: focused,
        kind: widget.kind,
        radius: widget.radius,
        child: child!,
      ),
      child: widget.child,
    );
  }
}

/// Il fuoco non fa scorrere da solo (VistaTraversalPolicy): l'elenco porta
/// al centro la voce a fuoco, con l'anello sempre in vista.
class VistaCenterOnFocus extends StatelessWidget {
  const VistaCenterOnFocus({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
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
    child: child,
  );
}
