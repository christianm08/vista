import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/image_cache.dart';

/// Colori dello stile "B · Vetro".
abstract final class VistaColors {
  static const background = Color(0xFF07090D);
  static const teal = Color(0xFF1E6B73);
  static const peach = Color(0xFFE08A55);
  static const violet = Color(0xFF4B3A8C);
  static const accent = Color(0xFFF6C59A);
  static const onPrimary = Color(0xFF0B0D12);

  static const glass = Color(0x0FFFFFFF); // .06
  static const glassHigh = Color(0x17FFFFFF); // .09
  static const glassActive = Color(0x26FFFFFF); // .15
  static const glassBorder = Color(0x24FFFFFF); // .14

  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xBDFFFFFF); // 74%
  static const textTertiary = Color(0x94FFFFFF); // 58%
}

/// Raggi: più contenuti del primo prototipo, per un aspetto più "da
/// prodotto" (stile Plex / Apple TV) e meno "da giocattolo".
abstract final class VistaRadius {
  static const hero = 22.0;
  static const card = 16.0;
  static const poster = 12.0;
}

/// Che dispositivo è: decide forma della navigazione e dimensioni.
abstract final class Device {
  static const _channel = MethodChannel('vista/device');

  /// Android TV / Google TV (telecomando, niente touch).
  static bool isTv = false;

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      isTv = false;
    } on MissingPluginException {
      isTv = false;
    }
  }
}

/// Misure che dipendono da dispositivo e larghezza della finestra.
class VistaLayout {
  VistaLayout._(this.width, this.height);

  factory VistaLayout.of(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return VistaLayout._(s.width, s.height);
  }

  final double width;
  final double height;

  /// Telefono (o finestra stretta): barra in basso, una colonna.
  bool get compact => width < 700 && !Device.isTv;

  /// Interfaccia da telecomando (Android TV). Le misure sono quelle del PC:
  /// su TV l'app si disegna su una tela larga come una finestra ([TvCanvas]).
  bool get tv => Device.isTv;

  /// Margine laterale del contenuto.
  double get gutter => compact ? 16 : 32;

  /// Larghezza delle locandine 2:3 nelle righe orizzontali.
  double get posterWidth {
    if (compact) return 112;
    return width >= 1600 ? 168 : 148;
  }

  /// Larghezza delle schede 16:9 (continua a guardare, canali).
  double get wideCardWidth {
    if (compact) return 220;
    return width >= 1600 ? 300 : 264;
  }
}

/// Su TV l'interfaccia si disegna su una tela larga [width] punti, come una
/// finestra del PC, e si scala sullo schermo: così TV e Windows hanno la
/// stessa impaginazione (barra laterale aperta, stesse righe e locandine).
/// Su PC e telefono non fa niente.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});

  static const width = 1280.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Device.isTv) return child;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    if (screen.width <= 0 || screen.height <= 0) return child;
    final scale = screen.width / width;
    final size = Size(width, screen.height / scale);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Scorrimento col trascinamento anche col mouse (righe orizzontali su PC).
class VistaScrollBehavior extends MaterialScrollBehavior {
  const VistaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

/// Titolo di una riga o sezione: piccolo e spaziato, il contenuto domina.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Metadati su una riga separati da "·" (anno · genere · durata).
String metaLine(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.trim().isNotEmpty).join('  ·  ');

/// Durata leggibile: "1 h 45 min", "45 min".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Immagine di rete con segnaposto e ridimensionamento in decodifica
/// (le locandine originali pesano anche 1-2 MB: sui box TV sono troppo).
///
/// Le immagini restano anche su disco ([CachedNetImage]): tornando su una
/// schermata non si riscaricano. [soft] le decodifica minuscole e le allarga:
/// un "blur" che non costa niente alla scheda grafica.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.opacity = 1,
    this.soft = false,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? placeholder;
  final double opacity;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const ColoredBox(color: Color(0xFF151A22));
    if (url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return ph;
    }
    return Image(
      image: ResizeImage.resizeIfNeeded(
        soft ? 24 : cacheWidth,
        null,
        CachedNetImage(url),
      ),
      fit: fit,
      gaplessPlayback: true,
      filterQuality: soft ? FilterQuality.medium : FilterQuality.low,
      opacity: opacity == 1 ? null : AlwaysStoppedAnimation(opacity),
      errorBuilder: (_, _, _) => ph,
      frameBuilder: (_, child, frame, sync) =>
          sync || frame != null ? child : ph,
    );
  }
}

ThemeData buildVistaTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      onPrimary: VistaColors.onPrimary,
      secondary: VistaColors.accent,
      surface: VistaColors.background,
      onSurface: VistaColors.text,
    ),
  );
  // Plus Jakarta Sans 400–800. Chiamare GoogleFonts per ogni peso ne avvia il
  // caricamento (poi resta in cache); il TextTheme usa solo la famiglia.
  final family = GoogleFonts.plusJakartaSans().fontFamily;
  for (final w in [
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ]) {
    GoogleFonts.plusJakartaSans(fontWeight: w);
  }
  final text = base.textTheme.apply(
    fontFamily: family,
    bodyColor: VistaColors.text,
    displayColor: VistaColors.text,
  );
  return base.copyWith(
    textTheme: text,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VistaColors.accent,
    ),
    // Col telecomando il focus deve vedersi sempre: bordo spesso e, sul
    // pulsante bianco, alone color pesca.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: VistaColors.onPrimary,
            disabledBackgroundColor: VistaColors.glassActive,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? const BorderSide(color: VistaColors.accent, width: 4)
                  : BorderSide.none,
            ),
            overlayColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? const Color(0x22E08A55)
                  : null,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? const BorderSide(color: Colors.white, width: 3)
                  : const BorderSide(color: VistaColors.glassBorder),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? VistaColors.glassActive
                  : null,
            ),
          ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VistaColors.glass,
      hintStyle: const TextStyle(color: VistaColors.textTertiary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: VistaColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: VistaColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF1A1F27),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

/// Sfondo con gli aloni sfumati (verde acqua, pesca, viola).
///
/// Gli aloni sono gradienti radiali, non cerchi sfocati: lo stesso effetto
/// senza un blur a tutto schermo, che sui box TV costava a ogni fotogramma.
class VistaBackground extends StatelessWidget {
  const VistaBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VistaColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Lo sfondo non cambia: non si ridisegna quando cambia il resto.
          const RepaintBoundary(
            child: Stack(
              // Aloni discreti: danno profondità senza competere con le
              // locandine.
              children: [
                _Halo(VistaColors.teal, Alignment(-1.1, -1.1), 0.32),
                _Halo(VistaColors.peach, Alignment(1.25, -0.6), 0.18),
                _Halo(VistaColors.violet, Alignment(-0.3, 1.3), 0.28),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo(this.color, this.alignment, this.opacity);
  final Color color;
  final Alignment alignment;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox.square(
        dimension: 760,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.55),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.35, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Superficie di vetro: riempimento traslucido e bordo.
///
/// Niente blur dello sfondo (BackdropFilter): su TV e telefoni rallentava
/// ogni scorrimento; sopra lo sfondo scuro il riempimento basta.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = VistaRadius.card,
    this.fill = VistaColors.glass,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final Color fill;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: VistaColors.glassBorder),
      ),
      child: child,
    );
  }
}

/// Orologio per l'intestazione delle schermate TV, aggiornato ogni 20 s.
class VistaClock extends StatefulWidget {
  const VistaClock({super.key, this.style});
  final TextStyle? style;

  @override
  State<VistaClock> createState() => _VistaClockState();
}

class _VistaClockState extends State<VistaClock> {
  late final _timer = Stream.periodic(const Duration(seconds: 20));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _timer,
      builder: (context, _) {
        final t = DateTime.now();
        return Text(
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          style:
              widget.style ??
              Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
        );
      },
    );
  }
}
