import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Schermo intero della finestra su Windows (canale `vista/window` del
/// runner). Su Android e TV l'app è già a schermo intero: non fa niente.
abstract final class WindowMode {
  static const _channel = MethodChannel('vista/window');

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// `true` mentre la finestra è a schermo intero.
  static final fullScreen = ValueNotifier<bool>(false);

  static Future<void> setFullScreen(bool on) async {
    if (!supported) return;
    try {
      final r = await _channel.invokeMethod<bool>('setFullScreen', on);
      fullScreen.value = r ?? on;
    } on PlatformException {
      // Finestra non ancora pronta: resta com'è.
    } on MissingPluginException {
      // Runner senza il canale (build vecchia).
    }
  }

  static Future<void> toggle() => setFullScreen(!fullScreen.value);

  /// Esc: se la finestra è a schermo intero, prima si esce da lì.
  /// Restituisce `true` se l'ha fatto (e allora Esc non torna indietro).
  static bool leaveOnEscape() {
    if (!fullScreen.value) return false;
    setFullScreen(false);
    return true;
  }
}

/// Pulsante schermo intero dei player (solo su Windows).
class FullScreenButton extends StatelessWidget {
  const FullScreenButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WindowMode.supported) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: WindowMode.fullScreen,
      builder: (context, on, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IconButton(
            tooltip: on
                ? 'Esci dallo schermo intero (F11 o Esc)'
                : 'Schermo intero (F11)',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x80000000),
            ),
            onPressed: WindowMode.toggle,
            icon: Icon(
              on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            ),
          ),
        ),
      ),
    );
  }
}
