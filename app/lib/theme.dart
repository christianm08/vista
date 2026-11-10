import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

abstract final class VistaRadius {
  static const hero = 34.0;
  static const card = 28.0;
  static const poster = 20.0;
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
  for (final w in [FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
    GoogleFonts.plusJakartaSans(fontWeight: w);
  }
  final text = base.textTheme.apply(
    fontFamily: family,
    bodyColor: VistaColors.text,
    displayColor: VistaColors.text,
  );
  return base.copyWith(
    textTheme: text,
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: VistaColors.accent),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: VistaColors.onPrimary,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: VistaColors.glassBorder),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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

/// Sfondo con gli aloni sfocati (verde acqua, pesca, viola).
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
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
            child: const Stack(
              children: [
                _Halo(VistaColors.teal, Alignment(-1.1, -1.0), 0.55),
                _Halo(VistaColors.peach, Alignment(1.2, -0.3), 0.40),
                _Halo(VistaColors.violet, Alignment(-0.4, 1.2), 0.50),
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
      child: Container(
        width: 360,
        height: 360,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}

/// Superficie di vetro: riempimento traslucido, bordo e blur dello sfondo.
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
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: r,
            border: Border.all(color: VistaColors.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}
