import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Marchio di Vista: una "V" geometrica scura su un fondo pesca.
///
/// Un solo disegno per tutto: il logo nella barra laterale e le icone
/// dell'app (generate da `tool/brand_icons_test.dart`), così restano
/// identici.
abstract final class VistaMarkStyle {
  static const ink = Color(0xFF0B0D12);
  static const light = Color(0xFFF8D6B4);
  static const mid = Color(0xFFF6C59A);
  static const deep = Color(0xFFE08A55);
}

/// Forma del fondo dell'icona.
enum MarkShape { square, rounded, circle, none }

/// Disegna il marchio in [rect]. [markScale] è la grandezza della V
/// rispetto al lato (le icone adattive Android la vogliono più piccola).
/// Con [monochrome] la V è disegnata in nero pieno senza fondo (icone a tema);
/// con [drawMark] falso si disegna solo il fondo (livello di sfondo Android).
void paintVistaMark(
  Canvas canvas,
  Rect rect, {
  MarkShape shape = MarkShape.rounded,
  double markScale = 1,
  bool monochrome = false,
  bool drawMark = true,
}) {
  final s = rect.shortestSide;
  final o = rect.center - Offset(s / 2, s / 2);

  if (shape != MarkShape.none && !monochrome) {
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        o,
        o + Offset(s, s),
        const [VistaMarkStyle.light, VistaMarkStyle.mid, VistaMarkStyle.deep],
        const [0, 0.42, 1],
      );
    final area = Rect.fromLTWH(o.dx, o.dy, s, s);
    final clip = switch (shape) {
      MarkShape.square => Path()..addRect(area),
      MarkShape.rounded =>
        Path()
          ..addRRect(RRect.fromRectAndRadius(area, Radius.circular(s * 0.225))),
      MarkShape.circle => Path()..addOval(area),
      MarkShape.none => Path(),
    };
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawRect(area, bg);
    // Luce morbida in alto a sinistra.
    canvas.drawRect(
      area,
      Paint()
        ..shader = ui.Gradient.radial(
          o + Offset(s * 0.22, s * 0.18),
          s * 0.75,
          const [Color(0x40FFFFFF), Color(0x00FFFFFF)],
        ),
    );
    canvas.restore();
  }

  if (!drawMark) return;

  // La V: due tratti con le estremità arrotondate, il destro più chiaro.
  final c = rect.center;
  Offset p(double x, double y) =>
      c + Offset((x - 0.5) * s * markScale, (y - 0.5) * s * markScale);
  final top = 0.285;
  final left = p(0.285, top);
  final bottom = p(0.5, 0.735);
  final right = p(0.715, top);
  final stroke = s * markScale * 0.135;
  Paint arm(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final ink = monochrome ? const Color(0xFF000000) : VistaMarkStyle.ink;
  canvas.drawLine(
    bottom,
    right,
    arm(monochrome ? ink : ink.withValues(alpha: 0.62)),
  );
  canvas.drawLine(left, bottom, arm(ink));
}

/// Il marchio come widget (barra laterale, schermate).
class VistaMark extends StatelessWidget {
  const VistaMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      paintVistaMark(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
