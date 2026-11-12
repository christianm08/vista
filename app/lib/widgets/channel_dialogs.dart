import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_card.dart';
import 'tv_text_field.dart';

ShapeBorder get _shape => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(VistaRadius.card),
);

const _dialogFill = Color(0xF0121720);

/// Chiede un testo (nome di una categoria, numero…). `null` se annullato.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  String action = 'Salva',
  String message = '',
  bool numeric = false,
}) async {
  final ctl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      void done() => Navigator.pop(ctx, ctl.text.trim());
      return AlertDialog(
        backgroundColor: _dialogFill,
        shape: _shape,
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty) ...[
                Text(
                  message,
                  style: Theme.of(ctx).textTheme.bodySmall
                      ?.copyWith(color: VistaColors.textSecondary),
                ),
                const SizedBox(height: 12),
              ],
              TvTextField(
                controller: ctl,
                hint: hint,
                autofocus: true,
                keyboardType: numeric ? TextInputType.number : null,
                onSubmitted: (_) => done(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(onPressed: done, child: Text(action)),
        ],
      );
    },
  );
  ctl.dispose();
  return result;
}

/// Chiede un numero di canale (1–9999). `null` se annullato o non valido;
/// `0` se l'utente ha scelto di tornare al numero della lista.
Future<int?> askChannelNumber(
  BuildContext context, {
  required String channelName,
  required int current,
  required bool custom,
}) async {
  final text = await askText(
    context,
    title: 'Numero di $channelName',
    hint: 'Es. 101',
    initial: '$current',
    numeric: true,
    message: custom
        ? 'Lascia vuoto per tornare al numero della lista.'
        : 'I canali si ordinano per numero.',
  );
  if (text == null) return null;
  if (text.isEmpty) return 0;
  final n = int.tryParse(text);
  if (n == null || n < 1 || n > 9999) return null;
  return n;
}

/// Sceglie una categoria fra [groups] o ne crea una nuova. Con [canReset]
/// c'è anche "Torna alla categoria della lista". Restituisce il nome scelto,
/// `''` per tornare alla categoria della lista, `null` se annullato.
Future<String?> pickGroup(
  BuildContext context, {
  required List<String> groups,
  String current = '',
  bool canReset = false,
  String title = 'Sposta in categoria',
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: _dialogFill,
      shape: _shape,
      title: Text(title),
      children: [
        SizedBox(
          width: 380,
          height: 380,
          child: ListView(
            children: [
              _option(
                ctx,
                icon: Icons.add_rounded,
                label: 'Nuova categoria…',
                value: '\u0000nuova',
              ),
              if (canReset)
                _option(
                  ctx,
                  icon: Icons.undo_rounded,
                  label: 'Torna alla categoria della lista',
                  value: '',
                ),
              for (final g in groups)
                _option(
                  ctx,
                  label: g.isEmpty ? 'Senza categoria' : g,
                  value: g,
                  selected: g == current,
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice != '\u0000nuova') return choice;
  final name = await askText(
    context,
    title: 'Nuova categoria',
    hint: 'Nome della categoria',
    action: 'Crea',
  );
  return (name == null || name.isEmpty) ? null : name;
}

Widget _option(
  BuildContext ctx, {
  required String label,
  required String value,
  IconData? icon,
  bool selected = false,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
  child: FocusCard(
    autofocus: selected,
    selected: selected,
    radius: 12,
    focusScale: 1.0,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    onTap: () => Navigator.pop(ctx, value),
    child: Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  ),
);
