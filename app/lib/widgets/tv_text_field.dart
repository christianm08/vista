import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Campo di testo che funziona anche col telecomando.
///
/// - Su/giù spostano il focus al campo o al pulsante vicino (in un campo
///   normale muoverebbero solo il cursore, intrappolando il focus).
/// - La tastiera si apre con OK o con un tocco, non al semplice passaggio del
///   focus: su Android TV comparirebbe a schermo intero a ogni spostamento.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  /// Il campo precedente è stato lasciato col tasto "avanti" della tastiera:
  /// quello che riceve il focus continua a scrivere.
  static bool _carryEditing = false;

  late final FocusNode _node = FocusNode(onKeyEvent: _onKey);
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus && _carryEditing) {
        _carryEditing = false;
        setState(() => _editing = true);
      } else if (!_node.hasFocus && _editing) {
        setState(() => _editing = false);
      }
    });
  }

  void _next() {
    _carryEditing = true;
    if (!FocusScope.of(context).nextFocus()) _carryEditing = false;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (!_editing &&
        (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.gameButtonA)) {
      _startEditing();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      setState(() => _editing = false);
      node.focusInDirection(k == LogicalKeyboardKey.arrowDown
          ? TraversalDirection.down
          : TraversalDirection.up);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _startEditing() {
    if (!_editing) setState(() => _editing = true);
    _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      enabled: widget.enabled,
      // In sola lettura Flutter non apre la connessione con la tastiera;
      // quando torna modificabile con il focus la apre da solo.
      readOnly: !_editing,
      showCursor: _editing,
      obscureText: widget.obscure,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onTap: _startEditing,
      onEditingComplete:
          widget.textInputAction == TextInputAction.next ? _next : null,
      onSubmitted: (v) {
        setState(() => _editing = false);
        widget.onSubmitted?.call(v);
      },
      decoration: InputDecoration(
        hintText: widget.hint,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: _editing ? VistaColors.accent : Colors.white,
            width: 3,
          ),
        ),
      ),
    );
  }
}
