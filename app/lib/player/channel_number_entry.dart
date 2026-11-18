import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import '../widgets/channel_logo.dart';

/// OK sul telecomando o Invio sulla tastiera.
bool isOkKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter;

/// Numero del canale digitato col telecomando: si va al canale dopo una breve
/// pausa o con OK.
class ChannelNumberEntry {
  ChannelNumberEntry({required this.onChanged, required this.onCommit});

  static const timeout = Duration(milliseconds: 1600);

  static final _digits = {
    for (final (i, k) in [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ].indexed)
      k: i,
    for (final (i, k) in [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ].indexed)
      k: i,
  };

  /// Il numero è cambiato (da ridisegnare).
  final VoidCallback onChanged;

  /// Numero confermato.
  final ValueChanged<int> onCommit;

  String _typed = '';
  Timer? _timer;

  String get typed => _typed;
  bool get isEmpty => _typed.isEmpty;

  void type(int digit) {
    _timer?.cancel();
    _typed = _typed.length >= 4 ? '$digit' : '$_typed$digit';
    onChanged();
    _timer = Timer(timeout, commit);
  }

  void erase() {
    _timer?.cancel();
    _typed = _typed.substring(0, _typed.length - 1);
    onChanged();
    if (_typed.isNotEmpty) _timer = Timer(timeout, commit);
  }

  void commit() {
    _timer?.cancel();
    final n = int.tryParse(_typed);
    _typed = '';
    onChanged();
    if (n != null) onCommit(n);
  }

  /// I numeri e, mentre si digita, OK (conferma) e Backspace (cancella).
  /// `null` se il tasto non riguarda il numero.
  KeyEventResult? handleKey(KeyEvent e) {
    final k = e.logicalKey;
    if (_digits[k] case final d?) {
      if (e is KeyDownEvent) type(d);
      return KeyEventResult.handled;
    }
    if (_typed.isNotEmpty) {
      if (e is KeyDownEvent && isOkKey(k)) {
        commit();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace) {
        erase();
        return KeyEventResult.handled;
      }
    }
    return null;
  }

  void dispose() => _timer?.cancel();
}

/// Il numero che si sta digitando, con il canale che gli corrisponde.
class TypedChannelNumber extends StatelessWidget {
  const TypedChannelNumber({
    super.key,
    required this.typed,
    required this.match,
  });

  final String typed;
  final Channel? match;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final match = this.match;
    final layout = VistaLayout.of(context);
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            0,
            VistaSpace.s32 + layout.safe.top,
            VistaSpace.s32 + layout.safe.right,
            0,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VistaSpace.s24,
              vertical: VistaSpace.s12,
            ),
            decoration: BoxDecoration(
              color: VistaColors.surface,
              borderRadius: BorderRadius.circular(VistaRadius.panel),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  typed,
                  style: t.headlineLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: VistaSpace.s16),
                if (match != null) ...[
                  ChannelLogo(channel: match, size: VistaSize.guideLogo),
                  const SizedBox(width: VistaSpace.s12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: VistaSize.playerTypedName,
                    ),
                    child: Text(
                      match.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                  ),
                ] else
                  Text(
                    'Nessun canale',
                    style: t.titleMedium?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
