import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/image_cache.dart';
import 'tokens.dart';

export 'tokens.dart';

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
  bool get compact => width < VistaSize.compactMaxWidth && !Device.isTv;

  /// Interfaccia da telecomando (Android TV). Le misure sono quelle del PC:
  /// su TV l'app si disegna su una tela larga come una finestra ([TvCanvas]).
  bool get tv => Device.isTv;

  bool get _large => !compact && width >= VistaSize.largeMinWidth;

  /// Area sicura: 5% per lato su TV, niente altrove.
  EdgeInsets get safe => tv
      ? EdgeInsets.symmetric(
          horizontal: width * VistaSize.tvSafeFraction,
          vertical: height * VistaSize.tvSafeFraction,
        )
      : EdgeInsets.zero;

  /// Margine laterale del contenuto.
  double get gutter => compact ? VistaSpace.s16 : VistaSpace.s32;

  /// Spazio tra le card di una riga.
  double get rowSpacing => compact ? VistaSpace.s12 : VistaSpace.s16;

  /// Spazio riservato sopra e sotto le card di una riga: più grande di quanto
  /// la card a fuoco sporge (ingrandimento + anello).
  double get rowReserve => compact ? VistaSpace.s12 : VistaSpace.s16;

  /// Spazio tra una riga e la successiva.
  double get rowGap => compact ? VistaSpace.s24 : VistaSpace.s32;

  /// Larghezza delle locandine 2:3 nelle righe orizzontali.
  double get posterWidth => compact
      ? VistaSize.posterCompact
      : (_large ? VistaSize.posterLarge : VistaSize.poster);

  /// Larghezza delle schede 16:9 (continua a guardare, canali, episodi).
  double get wideCardWidth => compact
      ? VistaSize.wideCardCompact
      : (_large ? VistaSize.wideCardLarge : VistaSize.wideCard);

  /// Rientro delle voci della barra laterale: su TV le voci e il loro anello
  /// (che sporge di 5 px) restano dentro l'area sicura.
  double get railInset => tv ? safe.left + VistaSpace.s8 : VistaSpace.s16;

  /// Barra laterale chiusa.
  double get railWidth => railInset + VistaSize.railItemWidth + VistaSpace.s16;

  /// Dove inizia l'area dei contenuti accanto alla barra laterale chiusa
  /// (testo e card stanno più in là, di [gutter]).
  double get contentLeft => railWidth;

  double get buttonHeight =>
      compact ? VistaSize.buttonCompact : VistaSize.button;

  double get chipHeight => compact ? VistaSize.chipCompact : VistaSize.chip;

  /// Spazio fra immagine e testo nelle card.
  double get cardTextGap => compact ? VistaSpace.s8 : VistaSpace.s12;

  VistaTypeScale get type => compact ? VistaType.compact : VistaType.wide;

  /// Altezza del testo sotto una card: titolo e metadati.
  double get cardTextHeight =>
      cardTextGap +
      type.cardTitle.lineHeight +
      VistaSpace.s4 +
      type.meta.lineHeight;
}

/// Su TV l'interfaccia si disegna su una tela larga [width] punti, come una
/// finestra del PC, e si scala sullo schermo: così TV e Windows hanno la
/// stessa impaginazione. Su PC e telefono non fa niente.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});

  static const width = VistaSize.tvCanvasWidth;

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

/// Titolo di una riga o sezione.
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
            style: t.titleLarge,
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
/// schermata non si riscaricano. [placeholder] si vede durante il
/// caricamento; [fallback] (se c'è) quando l'immagine manca o non si carica.
/// [soft] le decodifica minuscole e le allarga: un "blur" che non costa niente
/// alla scheda grafica.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.placeholder,
    this.fallback,
    this.opacity = 1,
    this.soft = false,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget? fallback;
  final double opacity;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const ColoredBox(color: VistaColors.surface);
    final missing = fallback ?? ph;
    if (url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return missing;
    }
    return Image(
      image: ResizeImage.resizeIfNeeded(
        soft ? 24 : cacheWidth,
        null,
        CachedNetImage(url),
      ),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: soft ? FilterQuality.medium : FilterQuality.low,
      opacity: opacity == 1 ? null : AlwaysStoppedAnimation(opacity),
      errorBuilder: (_, _, _) => missing,
      frameBuilder: (_, child, frame, sync) =>
          sync || frame != null ? child : ph,
    );
  }
}

// ===== Tema ==================================================================

TextStyle _style(VistaTextSpec s, Color color) => GoogleFonts.getFont(
  s.family,
  fontSize: s.size,
  height: s.lineHeight / s.size,
  fontWeight: s.weight,
  letterSpacing: s.tracking,
  color: color,
);

/// TextTheme M3 dalla scala di Vista: ogni slot ha un ruolo, così nessuno
/// stile Material predefinito resta visibile.
TextTheme vistaTextTheme(VistaTypeScale s) {
  const fg = VistaColors.text;
  const muted = VistaColors.textSecondary;
  return TextTheme(
    displayLarge: _style(s.hero, fg),
    displayMedium: _style(s.hero, fg),
    displaySmall: _style(s.feature, fg),
    headlineLarge: _style(s.feature, fg),
    headlineMedium: _style(s.page, fg),
    headlineSmall: _style(s.page, fg),
    titleLarge: _style(s.rowTitle, fg),
    titleMedium: _style(s.button, fg),
    titleSmall: _style(s.cardTitle, fg),
    bodyLarge: _style(s.body, fg),
    bodyMedium: _style(s.body, fg),
    bodySmall: _style(s.meta, muted),
    labelLarge: _style(s.label, fg),
    labelMedium: _style(s.meta, muted),
    labelSmall: _style(s.minimum, fg),
  );
}

/// Tema per il formato wide (TV, PC, tablet) o telefono ([compact]).
ThemeData buildVistaTheme({bool compact = false}) {
  final scale = compact ? VistaType.compact : VistaType.wide;
  final text = vistaTextTheme(scale);
  final buttonHeight = compact ? VistaSize.buttonCompact : VistaSize.button;
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: VistaColors.accent,
    onPrimary: VistaColors.onAccent,
    primaryContainer: VistaColors.surfaceSelected,
    onPrimaryContainer: VistaColors.text,
    secondary: VistaColors.text,
    onSecondary: VistaColors.background,
    secondaryContainer: VistaColors.surfaceHigh,
    onSecondaryContainer: VistaColors.text,
    tertiary: VistaColors.text,
    onTertiary: VistaColors.background,
    error: VistaColors.error,
    onError: VistaColors.background,
    surface: VistaColors.background,
    onSurface: VistaColors.text,
    onSurfaceVariant: VistaColors.textSecondary,
    surfaceContainerLowest: VistaColors.background,
    surfaceContainerLow: VistaColors.surface,
    surfaceContainer: VistaColors.surface,
    surfaceContainerHigh: VistaColors.surfaceHigh,
    surfaceContainerHighest: VistaColors.surfaceSelected,
    outline: VistaColors.outline,
    outlineVariant: VistaColors.outline,
    inverseSurface: VistaColors.text,
    onInverseSurface: VistaColors.background,
    inversePrimary: VistaColors.onAccent,
    shadow: VistaColors.focusShadow,
    scrim: VistaColors.background,
  );

  // Per i pulsanti Material usati ancora "nudi" dalle schermate non migrate:
  // anello bianco col fuoco, senza cambiare le misure. VistaButton lo spegne
  // e disegna il suo.
  WidgetStateProperty<BorderSide?> focusSide([
    BorderSide rest = BorderSide.none,
  ]) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused)
        ? const BorderSide(
            color: VistaColors.focusRing,
            width: VistaFocus.ringWidth,
          )
        : rest,
  );
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? VistaColors.pressOverlay
        : s.contains(WidgetState.hovered)
        ? VistaColors.hoverOverlay
        : VistaColors.transparent,
  );
  const stadium = StadiumBorder();
  const buttonPadding = EdgeInsets.symmetric(horizontal: VistaSpace.s24);
  final buttonSize = Size(VistaSize.minTouch, buttonHeight);
  final chipRadius = BorderRadius.circular(VistaRadius.chip);

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: VistaColors.background,
    canvasColor: VistaColors.background,
    textTheme: text,
    iconTheme: const IconThemeData(
      color: VistaColors.text,
      size: VistaSize.icon,
    ),
    splashFactory: InkRipple.splashFactory,
    splashColor: VistaColors.pressOverlay,
    highlightColor: VistaColors.transparent,
    hoverColor: VistaColors.hoverOverlay,
    focusColor: VistaColors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: VistaPageTransitionsBuilder(),
        TargetPlatform.windows: VistaPageTransitionsBuilder(),
        TargetPlatform.linux: VistaPageTransitionsBuilder(),
        TargetPlatform.macOS: VistaPageTransitionsBuilder(),
        TargetPlatform.iOS: VistaPageTransitionsBuilder(),
        TargetPlatform.fuchsia: VistaPageTransitionsBuilder(),
      },
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VistaColors.accent,
      linearTrackColor: VistaColors.outline,
      circularTrackColor: VistaColors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? VistaColors.surfaceHigh
              : VistaColors.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? VistaColors.textSecondary
              : VistaColors.onAccent,
        ),
        overlayColor: overlay,
        minimumSize: WidgetStatePropertyAll(buttonSize),
        padding: WidgetStatePropertyAll(buttonPadding),
        shape: const WidgetStatePropertyAll(stadium),
        side: focusSide(),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(text.titleMedium),
        iconSize: const WidgetStatePropertyAll(VistaSize.icon),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(VistaColors.text),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? VistaColors.surfaceHigh
              : VistaColors.surface,
        ),
        overlayColor: overlay,
        minimumSize: WidgetStatePropertyAll(buttonSize),
        padding: WidgetStatePropertyAll(buttonPadding),
        shape: const WidgetStatePropertyAll(stadium),
        side: focusSide(),
        textStyle: WidgetStatePropertyAll(text.titleMedium),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(VistaColors.text),
        overlayColor: overlay,
        minimumSize: const WidgetStatePropertyAll(
          Size(VistaSize.minTouch, VistaSize.minTouch),
        ),
        shape: const WidgetStatePropertyAll(stadium),
        side: focusSide(),
        textStyle: WidgetStatePropertyAll(text.titleMedium),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(VistaColors.text),
        overlayColor: overlay,
        side: focusSide(),
        minimumSize: const WidgetStatePropertyAll(
          Size(VistaSize.minTouch, VistaSize.minTouch),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: VistaColors.surface,
      selectedColor: VistaColors.text,
      disabledColor: VistaColors.surface,
      labelStyle: text.labelLarge,
      secondaryLabelStyle: text.labelLarge?.copyWith(
        color: VistaColors.background,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s8),
      iconTheme: const IconThemeData(
        color: VistaColors.text,
        size: VistaSize.iconSmall,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: VistaSize.navBar,
      backgroundColor: VistaColors.surface,
      surfaceTintColor: VistaColors.transparent,
      elevation: 0,
      indicatorColor: VistaColors.surfaceSelected,
      indicatorShape: stadium,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: VistaSize.icon,
          color: s.contains(WidgetState.selected)
              ? VistaColors.text
              : VistaColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          color: s.contains(WidgetState.selected)
              ? VistaColors.text
              : VistaColors.textSecondary,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VistaColors.surface,
      hintStyle: text.bodyLarge?.copyWith(color: VistaColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VistaRadius.card),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VistaRadius.card),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VistaRadius.card),
        borderSide: const BorderSide(
          color: VistaColors.focusRing,
          width: VistaFocus.ringWidth,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: VistaColors.text,
      iconColor: VistaColors.textSecondary,
      selectedColor: VistaColors.text,
      selectedTileColor: VistaColors.surfaceSelected,
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? VistaColors.background
            : VistaColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? VistaColors.text
            : VistaColors.surfaceHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(VistaColors.outline),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: VistaColors.accent,
      inactiveTrackColor: VistaColors.outline,
      thumbColor: VistaColors.text,
    ),
    dividerTheme: const DividerThemeData(
      color: VistaColors.outline,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VistaColors.surfaceHigh,
      barrierColor: VistaScrims.dialogBarrier,
      surfaceTintColor: VistaColors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VistaRadius.panel),
      ),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyLarge?.copyWith(color: VistaColors.textBody),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VistaColors.surface,
      surfaceTintColor: VistaColors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: VistaColors.surfaceHigh,
      surfaceTintColor: VistaColors.transparent,
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
      textStyle: text.labelLarge,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: VistaColors.surfaceHigh,
        borderRadius: chipRadius,
      ),
      textStyle: text.labelLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VistaColors.surfaceHigh,
      contentTextStyle: text.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(VistaColors.outline),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: VistaColors.text,
      selectionColor: VistaColors.surfaceSelected,
      selectionHandleColor: VistaColors.text,
    ),
  );
}

/// Cambio di pagina "attraverso": la pagina vecchia svanisce nel primo terzo,
/// la nuova entra con dissolvenza e uno scorrimento breve. Ogni pagina ha il
/// fondo opaco, quindi le due non si vedono mai una attraverso l'altra.
class VistaPageTransitionsBuilder extends PageTransitionsBuilder {
  const VistaPageTransitionsBuilder();

  @override
  Duration get transitionDuration => VistaMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => VistaPageTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

class VistaPageTransition extends StatelessWidget {
  const VistaPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    const split = VistaMotion.pageExitFraction;
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(split, 1, curve: VistaMotion.enter),
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, split, curve: VistaMotion.exit),
    );
    return FadeTransition(
      opacity: ReverseAnimation(exit),
      child: FadeTransition(
        opacity: enter,
        child: reduce
            ? child
            : AnimatedBuilder(
                animation: enter,
                builder: (_, c) => Transform.translate(
                  offset: Offset(0, (1 - enter.value) * VistaMotion.pageSlide),
                  child: c,
                ),
                child: child,
              ),
      ),
    );
  }
}

/// Sfondo dell'app: il fondo pieno, dietro alle pagine durante i cambi.
class VistaBackground extends StatelessWidget {
  const VistaBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: VistaColors.background, child: child);
}

/// Sceglie il tema del formato (telefono o wide) dalla larghezza attuale.
class VistaThemeScope extends StatelessWidget {
  const VistaThemeScope({super.key, required this.child});
  final Widget child;

  static final wide = buildVistaTheme();
  static final compact = buildVistaTheme(compact: true);

  @override
  Widget build(BuildContext context) => Theme(
    data: VistaLayout.of(context).compact ? compact : wide,
    child: child,
  );
}

/// Superficie di un pannello (stile "Vetro" da rimuovere nella fase 7):
/// ora è una superficie piena, senza bordo.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = VistaRadius.card,
    this.fill = VistaColors.surface,
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
          style: widget.style ?? Theme.of(context).textTheme.titleLarge,
        );
      },
    );
  }
}
