import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// VideoController di Vista: uscita video standard di media_kit (`vo=gpu`).
///
/// Non usare `vo=mediacodec_embed` su Android: dal Flutter 3.29 il thread di
/// Dart e quello principale di Android sono unificati (non si può più
/// disattivare) e media_kit, impostando `vo` da Dart, aspetta mpv mentre mpv
/// aspetta il thread principale → blocco totale (ANR). Verificato il
/// 2026-11-10 con Flutter 3.47.9 e media_kit_video 2.0.1.
///
/// Gli emulatori Android 16 non creano il contesto OpenGL ES che serve a
/// `vo=gpu`: lì il video resta nero (sui dispositivi veri funziona). Per
/// vederlo in emulatore avviarlo con `-gpu swiftshader_indirect`.
VideoController vistaVideoController(Player player) => VideoController(player);
