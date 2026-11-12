// Genera tutte le icone di Vista dal marchio in lib/widgets/vista_mark.dart.
//
//   cd app
//   flutter test tool/brand_icons_test.dart --dart-define=VISTA_FONT_DIR=<cartella>
//
// VISTA_FONT_DIR: cartella con i file Plus Jakarta Sans (licenza OFL) che
// google_fonts salva al primo avvio dell'app, es. %APPDATA%\Vista\Vista.
// Serve solo per la scritta del banner TV; senza, il banner resta senza
// scritta e il test lo segnala.
//
// Scrive:
//   ../brand/                         icone per README, store, siti
//   android/app/src/main/res/         icone del launcher, adattive, banner TV
//   windows/runner/resources/         app_icon.ico
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/widgets/vista_mark.dart';

const _fontDir = String.fromEnvironment('VISTA_FONT_DIR');

Future<Uint8List> _png(
  int w,
  int h,
  void Function(Canvas canvas, Size size) paint,
) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, Size(w.toDouble(), h.toDouble()));
  final image = await rec.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _icon(
  int size, {
  MarkShape shape = MarkShape.rounded,
  double markScale = 1,
  bool monochrome = false,
  bool drawMark = true,
}) => _png(
  size,
  size,
  (c, s) => paintVistaMark(
    c,
    Offset.zero & s,
    shape: shape,
    markScale: markScale,
    monochrome: monochrome,
    drawMark: drawMark,
  ),
);

/// File .ico con le immagini PNG dentro (va bene da Windows Vista in poi).
Uint8List _ico(List<(int, Uint8List)> images) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  u16(0);
  u16(1);
  u16(images.length);
  var offset = 6 + 16 * images.length;
  for (final (size, png) in images) {
    b.add([size >= 256 ? 0 : size, size >= 256 ? 0 : size, 0, 0]);
    u16(1);
    u16(32);
    u32(png.length);
    u32(offset);
    offset += png.length;
  }
  for (final (_, png) in images) {
    b.add(png);
  }
  return b.toBytes();
}

Future<void> _write(String path, List<int> bytes) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes);
}

Future<bool> _loadFont() async {
  if (_fontDir.isEmpty) return false;
  final files = Directory(_fontDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('PlusJakartaSans_'))
      .toList();
  if (files.isEmpty) return false;
  final loader = FontLoader('Jakarta');
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
  return true;
}

/// Banner di Android TV (16:9): sfondo dell'app, icona e scritta.
void _banner(Canvas canvas, Size size, {required bool text}) {
  final w = size.width;
  final h = size.height;
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF07090D));
  void halo(Color color, Offset at, double r, double a) => canvas.drawCircle(
    at,
    r,
    Paint()
      ..shader = ui.Gradient.radial(at, r, [
        color.withValues(alpha: a),
        color.withValues(alpha: 0),
      ]),
  );
  halo(const Color(0xFF1E6B73), Offset(w * 0.05, h * 0.05), h * 0.9, 0.55);
  halo(const Color(0xFF4B3A8C), Offset(w * 0.55, h * 1.1), h * 0.9, 0.5);
  halo(const Color(0xFFE08A55), Offset(w * 1.0, h * 0.2), h * 0.8, 0.3);

  final tile = h * 0.5;
  final left = text ? w * 0.13 : (w - tile) / 2;
  paintVistaMark(canvas, Rect.fromLTWH(left, (h - tile) / 2, tile, tile));
  if (!text) return;

  ui.Paragraph para(String s, double fontSize, FontWeight weight, Color color) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Jakarta'))
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: -fontSize * 0.02,
        ),
      )
      ..addText(s);
    return pb.build()..layout(ui.ParagraphConstraints(width: w));
  }

  final x = left + tile + w * 0.05;
  final title = para(
    'Vista',
    h * 0.3,
    FontWeight.w800,
    const Color(0xFFFFFFFF),
  );
  final sub = para(
    'TV · Film · Serie',
    h * 0.085,
    FontWeight.w500,
    const Color(0xBDFFFFFF),
  );
  final total = title.height + sub.height * 0.9;
  final y = (h - total) / 2;
  canvas.drawParagraph(title, Offset(x, y));
  canvas.drawParagraph(sub, Offset(x + h * 0.012, y + title.height * 0.92));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('icone di Vista', () async {
    final hasFont = await _loadFont();
    const brand = '../brand';

    // Icone generali.
    await _write(
      '$brand/icon-square.png',
      await _icon(1024, shape: MarkShape.square),
    );
    await _write('$brand/icon-rounded.png', await _icon(1024));
    await _write(
      '$brand/icon-round.png',
      await _icon(1024, shape: MarkShape.circle),
    );

    // Favicon e icone web.
    await _write(
      '$brand/favicon/favicon.ico',
      _ico([
        for (final s in [16, 32, 48]) (s, await _icon(s)),
      ]),
    );
    for (final s in [16, 32, 192, 512]) {
      await _write('$brand/favicon/icon-$s.png', await _icon(s));
    }
    // iOS arrotonda da solo: icona quadrata piena.
    await _write(
      '$brand/favicon/apple-touch-icon.png',
      await _icon(180, shape: MarkShape.square),
    );

    // Banner Android TV.
    await _write(
      '$brand/tv-banner.png',
      await _png(1280, 720, (c, s) => _banner(c, s, text: hasFont)),
    );
    const res = 'android/app/src/main/res';
    await _write(
      '$res/drawable-xhdpi/tv_banner.png',
      await _png(640, 360, (c, s) => _banner(c, s, text: hasFont)),
    );

    // Launcher Android: classiche (48 dp) e adattive (108 dp).
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final MapEntry(key: d, value: k) in densities.entries) {
      final legacy = (48 * k).round();
      final adaptive = (108 * k).round();
      await _write('$res/mipmap-$d/ic_launcher.png', await _icon(legacy));
      await _write(
        '$res/mipmap-$d/ic_launcher_round.png',
        await _icon(legacy, shape: MarkShape.circle),
      );
      // Nelle adattive la parte sempre visibile è il cerchio centrale di
      // 66 dp su 108: la V va rimpicciolita.
      await _write(
        '$res/mipmap-$d/ic_launcher_foreground.png',
        await _icon(adaptive, shape: MarkShape.none, markScale: 0.6),
      );
      await _write(
        '$res/mipmap-$d/ic_launcher_background.png',
        await _icon(adaptive, shape: MarkShape.square, drawMark: false),
      );
      await _write(
        '$res/mipmap-$d/ic_launcher_monochrome.png',
        await _icon(
          adaptive,
          shape: MarkShape.none,
          markScale: 0.6,
          monochrome: true,
        ),
      );
    }

    // Windows.
    await _write(
      'windows/runner/resources/app_icon.ico',
      _ico([
        for (final s in [16, 20, 24, 32, 40, 48, 64, 128, 256])
          (s, await _icon(s)),
      ]),
    );

    expect(
      hasFont,
      isTrue,
      reason: 'banner TV senza scritta: manca VISTA_FONT_DIR',
    );
  });
}
