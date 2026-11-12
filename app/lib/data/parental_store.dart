import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import '../widgets/tv_text_field.dart';

/// Controllo genitori: un PIN che protegge canali, categorie e impostazioni.
///
/// Tutto nel portachiavi del sistema (anche il PIN). Una volta inserito il
/// PIN giusto, resta sbloccato fino alla chiusura dell'app.
class ParentalStore extends ChangeNotifier {
  static const _key = 'vista.parental';
  final _secure = const FlutterSecureStorage();

  String _pin = '';
  Set<String> _channels = {};
  Set<String> _groups = {};
  bool _settings = false;
  bool _unlocked = false;

  bool get enabled => _pin.isNotEmpty;

  /// Nessun PIN, o PIN già inserito in questa sessione.
  bool get isUnlocked => !enabled || _unlocked;

  /// Le impostazioni chiedono il PIN.
  bool get locksSettings => enabled && _settings;

  Set<String> get lockedChannels => Set.unmodifiable(_channels);
  Set<String> get lockedGroups => Set.unmodifiable(_groups);

  bool isLocked(Channel c) =>
      enabled && (_channels.contains(c.key) || _groups.contains(c.group));

  Future<void> load() async {
    try {
      final raw = await _secure.read(key: _key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _pin = j['pin'] as String? ?? '';
      _channels = {for (final k in j['channels'] as List? ?? const []) '$k'};
      _groups = {for (final g in j['groups'] as List? ?? const []) '$g'};
      _settings = j['settings'] == true;
      notifyListeners();
    } catch (_) {
      // Dati illeggibili: nessun blocco piuttosto che app inutilizzabile.
    }
  }

  Future<void> _save() async {
    await _secure.write(
      key: _key,
      value: jsonEncode({
        'pin': _pin,
        'channels': _channels.toList(),
        'groups': _groups.toList(),
        'settings': _settings,
      }),
    );
    notifyListeners();
  }

  /// Imposta o cambia il PIN (4–8 cifre); vuoto lo toglie e sblocca tutto.
  Future<void> setPin(String pin) async {
    _pin = pin;
    if (pin.isEmpty) {
      _channels = {};
      _groups = {};
      _settings = false;
    }
    _unlocked = true;
    await _save();
  }

  Future<void> setSettingsLocked(bool on) async {
    _settings = on;
    await _save();
  }

  Future<void> setChannelLocked(String key, bool on) async {
    on ? _channels.add(key) : _channels.remove(key);
    await _save();
  }

  Future<void> setGroupLocked(String group, bool on) async {
    on ? _groups.add(group) : _groups.remove(group);
    await _save();
  }

  /// Dati per il backup (senza il PIN).
  Map<String, dynamic> toBackup() => {
    'channels': _channels.toList(),
    'groups': _groups.toList(),
    'settings': _settings,
  };

  Future<void> restore(Map<String, dynamic> j) async {
    _channels = {for (final k in j['channels'] as List? ?? const []) '$k'};
    _groups = {for (final g in j['groups'] as List? ?? const []) '$g'};
    _settings = j['settings'] == true;
    await _save();
  }

  /// `true` se si può proseguire: nessun PIN, già sbloccato, o PIN giusto.
  Future<bool> unlock(BuildContext context, {String reason = ''}) async {
    if (!enabled || _unlocked) return true;
    final ok = await askPin(context, reason: reason, check: (p) => p == _pin);
    if (ok) _unlocked = true;
    return ok;
  }
}

/// Chiede un PIN. Con [check] lo verifica (fino a 3 tentativi) e restituisce
/// se è giusto; senza, restituisce `true` e mette il PIN in [onEntered].
Future<bool> askPin(
  BuildContext context, {
  String title = 'PIN',
  String reason = '',
  bool Function(String pin)? check,
  ValueChanged<String>? onEntered,
}) async {
  final ctl = TextEditingController();
  var error = '';
  var tries = 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        void submit() {
          final pin = ctl.text.trim();
          if (pin.length < 4 || pin.length > 8 || int.tryParse(pin) == null) {
            setDialog(() => error = 'Il PIN è di 4–8 cifre.');
            return;
          }
          if (check == null) {
            onEntered?.call(pin);
            Navigator.pop(ctx, true);
            return;
          }
          if (check(pin)) {
            Navigator.pop(ctx, true);
            return;
          }
          tries++;
          ctl.clear();
          if (tries >= 3) {
            Navigator.pop(ctx, false);
            return;
          }
          setDialog(() => error = 'PIN sbagliato. Riprova.');
        }

        return AlertDialog(
          backgroundColor: const Color(0xF0121720),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VistaRadius.card),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_outline_rounded),
              const SizedBox(width: 10),
              Expanded(child: Text(title)),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reason.isNotEmpty) ...[
                  Text(
                    reason,
                    style: Theme.of(ctx).textTheme.bodySmall
                        ?.copyWith(color: VistaColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                ],
                TvTextField(
                  controller: ctl,
                  hint: 'PIN (4–8 cifre)',
                  obscure: true,
                  autofocus: true,
                  editOnFocus: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => submit(),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(error, style: const TextStyle(color: Color(0xFFFF8A80))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    ),
  );
  ctl.dispose();
  return ok == true;
}
