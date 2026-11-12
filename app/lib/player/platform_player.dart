import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../data/window_mode.dart';

/// Funzioni del player legate al sistema: Picture-in-Picture su Android,
/// finestra mini sempre in primo piano su Windows, player esterno.
abstract final class PlayerPlatform {
  static const _device = MethodChannel('vista/device');
  static const _window = MethodChannel('vista/window');

  /// `true` mentre il video è nel riquadro PiP (Android) o nella finestra
  /// mini (Windows): il player nasconde barre e pannelli.
  static final pip = ValueNotifier<bool>(false);

  static bool _ready = false;
  static bool? _canPip;

  static bool get _android => !kIsWeb && Platform.isAndroid;
  static bool get _windows => !kIsWeb && Platform.isWindows;

  /// Da chiamare una volta all'avvio: Android avvisa quando si entra o si
  /// esce dal PiP.
  static void init() {
    if (_ready || !_android) return;
    _ready = true;
    _device.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') pip.value = call.arguments == true;
    });
  }

  /// Il dispositivo sa mettere il video in un riquadro.
  static Future<bool> canPip() async {
    if (_windows) return true;
    if (!_android) return false;
    try {
      return _canPip ??= await _device.invokeMethod<bool>('canPip') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static String get pipLabel =>
      _windows ? 'Finestra mini in primo piano' : 'Picture-in-Picture';

  static Future<void> enterPip() async {
    try {
      if (_android) {
        await _device.invokeMethod<bool>('enterPip');
      } else if (_windows) {
        if (WindowMode.fullScreen.value) await WindowMode.setFullScreen(false);
        pip.value = await _window.invokeMethod<bool>('setMini', true) ?? false;
      }
    } on PlatformException {
      // Non disponibile: si resta come si è.
    } on MissingPluginException {
      // Idem.
    }
  }

  /// Windows: torna alla finestra normale (su Android ci pensa il sistema).
  static Future<void> exitPip() async {
    if (!_windows || !pip.value) return;
    try {
      pip.value = await _window.invokeMethod<bool>('setMini', false) ?? false;
    } on PlatformException {
      pip.value = false;
    }
  }

  /// Android: col player aperto, il tasto Home manda il video nel riquadro.
  static Future<void> setAutoPip(bool on) async {
    if (!_android) return;
    try {
      await _device.invokeMethod<void>('setAutoPip', on);
    } on PlatformException {
      // Ignorato.
    } on MissingPluginException {
      // Ignorato.
    }
  }

  static bool get hasExternalPlayer => _android || _windows;

  /// Apre il flusso in un altro player: su Android si sceglie l'app, su
  /// Windows si usa VLC se c'è. `false` se non c'è nessun player.
  static Future<bool> openExternal(String url, String title) async {
    if (_android) {
      try {
        return await _device.invokeMethod<bool>('openVideo', {
              'url': url,
              'title': title,
            }) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    if (_windows) {
      final vlc = [
        r'C:\Program Files\VideoLAN\VLC\vlc.exe',
        r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
      ].where((p) => File(p).existsSync()).firstOrNull;
      if (vlc == null) return false;
      await Process.start(vlc, [
        '--meta-title=$title',
        url,
      ], mode: ProcessStartMode.detached);
      return true;
    }
    return false;
  }

  /// Decodifica software o hardware per il prossimo flusso. [defaultHwdec]
  /// è il valore che il player aveva all'inizio (si torna a quello).
  static Future<String?> applyDecoder(
    Player player, {
    required bool software,
    String? defaultHwdec,
  }) async {
    final p = player.platform;
    if (p is! NativePlayer) return defaultHwdec;
    try {
      final initial = defaultHwdec ?? await p.getProperty('hwdec');
      await p.setProperty('hwdec', software ? 'no' : initial);
      return initial;
    } catch (_) {
      return defaultHwdec;
    }
  }
}

/// Il video nel riquadro PiP (Android) o nella finestra mini (Windows).
/// Su Windows c'è sempre il pulsante per tornare alla finestra normale
/// (oltre a Esc e al doppio clic).
class PipView extends StatelessWidget {
  const PipView({super.key, required this.video});

  final Widget video;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: PlayerPlatform.exitPip,
        child: video,
      ),
      if (!kIsWeb && Platform.isWindows)
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              tooltip: 'Torna alla finestra normale (Esc)',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xB3000000),
              ),
              onPressed: PlayerPlatform.exitPip,
              icon: const Icon(Icons.open_in_full_rounded, size: 20),
            ),
          ),
        ),
    ],
  );
}
