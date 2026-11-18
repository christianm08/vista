import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/vista_cards.dart';
import 'package:vista/widgets/vista_focus.dart';
import 'package:vista/widgets/vista_row.dart';

/// Pagina di prova: [rows] righe di [count] poster, il primo a fuoco. Le
/// righe iniziano dove le mette la shell, accanto alla barra laterale chiusa.
Widget _page({int rows = 1, int count = 50, bool reduce = false}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final layout = VistaLayout.of(context);
          final w = layout.posterWidth;
          final h = VistaPosterCard.heightFor(context, w, true);
          return Padding(
            // Come le schermate: le righe partono sotto l'area sicura.
            padding: EdgeInsets.only(
              left: layout.contentLeft,
              top: layout.safe.top,
            ),
            child: VistaRowsPage(
              rows: [
                for (var r = 0; r < rows; r++)
                  VistaRow(
                    key: ValueKey('row-$r'),
                    title: 'Riga $r',
                    itemCount: count,
                    itemKey: (i) => ValueKey('r$r-i$i'),
                    itemWidth: w,
                    itemHeight: h,
                    itemBuilder: (context, i) => VistaPosterCard(
                      title: 'Titolo $r/$i',
                      image: '',
                      restWidth: w,
                      autofocus: r == 0 && i == 0,
                      onTap: () {},
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _hold(WidgetTester tester, LogicalKeyboardKey key, int n) async {
  // Ripetizione del telecomando: ~30 pressioni al secondo.
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 33));
  }
}

List<VistaFocusEffectState> _effects(WidgetTester tester) => tester
    .stateList<VistaFocusEffectState>(find.byType(VistaFocusEffect))
    .toList();

/// Esattamente un elemento a fuoco (scala e anello pieni), tutti gli altri
/// esattamente a riposo: scala 1, anello spento.
void _expectOneFocusedRestAtRest(WidgetTester tester) {
  final effects = _effects(tester);
  final focused = effects.where((e) => e.widget.active).toList();
  expect(focused, hasLength(1));
  expect(focused.single.scaleProgress, 1.0);
  expect(focused.single.ringOpacity, 1.0);
  for (final e in effects.where((e) => !e.widget.active)) {
    expect(e.scaleProgress, 0.0, reason: 'scala a riposo');
    expect(e.scale, 1.0);
    expect(e.ringOpacity, 0.0, reason: 'anello spento');
  }
}

String? _focusedKey() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final slot = ctx?.findAncestorWidgetOfExactType<KeyedSubtree>();
  return (slot?.key as ValueKey<String>?)?.value;
}

/// Rettangolo dell'anello dell'elemento a fuoco, sullo schermo.
Rect _ringRect(WidgetTester tester) {
  final state = _effects(tester).singleWhere((e) => e.widget.active);
  final box = state.context.findRenderObject()! as RenderBox;
  final rest = box.localToGlobal(Offset.zero) & box.size;
  final scaled = Rect.fromCenter(
    center: rest.center,
    width: rest.width * state.scale,
    height: rest.height * state.scale,
  );
  return scaled.inflate(VistaFocus.ringGap + VistaFocus.ringWidth);
}

/// L'anello sta dentro l'area sicura (5% per lato su TV) e, in orizzontale,
/// dentro il ritaglio della riga che contiene l'elemento a fuoco.
void _expectRingInside(WidgetTester tester, Rect ring) {
  final context = tester.element(find.byType(VistaRow).first);
  final layout = VistaLayout.of(context);
  final safe = layout.safe.deflateRect(
    Offset.zero & Size(layout.width, layout.height),
  );
  final where = 'anello $ring, area sicura $safe';
  expect(safe.contains(ring.topLeft), isTrue, reason: where);
  expect(safe.contains(ring.bottomRight), isTrue, reason: where);

  // Il primo ritaglio con un clipper sopra l'elemento è quello della riga.
  final focused = _effects(tester).singleWhere((e) => e.widget.active);
  RenderObject? node = focused.context.findRenderObject();
  while (node is! RenderClipRect || node.clipper == null) {
    node = node!.parent;
  }
  final row = node;
  final clip = row.clipper!
      .getClip(row.size)
      .shift(row.localToGlobal(Offset.zero));
  expect(
    ring.left,
    greaterThanOrEqualTo(clip.left),
    reason: 'tagliato a sinistra',
  );
  expect(
    ring.right,
    lessThanOrEqualTo(clip.right),
    reason: 'tagliato a destra',
  );
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 720);
    view.devicePixelRatio = 1;
  });

  testWidgets('D-pad tenuto premuto 5 s: a fine corsa tutto a riposo', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 150);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i49');
    _expectOneFocusedRestAtRest(tester);

    await _hold(tester, LogicalKeyboardKey.arrowLeft, 150);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i0');
    _expectOneFocusedRestAtRest(tester);
  });

  testWidgets('il fuoco si aggancia al margine, non viene tagliato e non '
      'tocca i vicini', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 10);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i10');

    final ring = _ringRect(tester);
    _expectRingInside(tester, ring);

    // L'immagine a riposo inizia esattamente al margine (aggancio).
    final layout = VistaLayout.of(tester.element(find.byType(VistaRow)));
    final focused = _effects(tester).singleWhere((e) => e.widget.active);
    final box = focused.context.findRenderObject()! as RenderBox;
    expect(
      box.localToGlobal(Offset.zero).dx,
      layout.contentLeft + layout.gutter,
    );

    // Le vicine non entrano nell'anello.
    for (final e in _effects(tester).where((e) => !e.widget.active)) {
      final b = e.context.findRenderObject()! as RenderBox;
      final r = b.localToGlobal(Offset.zero) & b.size;
      expect(r.overlaps(ring), isFalse, reason: 'vicina dentro l\'anello');
    }
  });

  testWidgets('su TV il fuoco resta nell\'area sicura, anche a fine riga', (
    tester,
  ) async {
    Device.isTv = true;
    addTearDown(() => Device.isTv = false);
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 10);
    await tester.pumpAndSettle();
    _expectRingInside(tester, _ringRect(tester));

    await _hold(tester, LogicalKeyboardKey.arrowRight, 150);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i49');
    _expectRingInside(tester, _ringRect(tester));
  });

  testWidgets('giù e su tenuti premuti 5 s: a fine corsa tutto a riposo', (
    tester,
  ) async {
    await tester.pumpWidget(_page(rows: 50, count: 10));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowDown, 150);
    await tester.pumpAndSettle();
    expect(_focusedKey(), startsWith('r49-'));
    _expectOneFocusedRestAtRest(tester);
    _expectRingInside(tester, _ringRect(tester));

    await _hold(tester, LogicalKeyboardKey.arrowUp, 150);
    await tester.pumpAndSettle();
    expect(_focusedKey(), startsWith('r0-'));
    _expectOneFocusedRestAtRest(tester);
    _expectRingInside(tester, _ringRect(tester));
  });

  testWidgets('su e giù tra le righe: nessun elemento resta ingrandito', (
    tester,
  ) async {
    await tester.pumpWidget(_page(rows: 6, count: 20));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await _hold(tester, LogicalKeyboardKey.arrowRight, 4);
      await _hold(tester, LogicalKeyboardKey.arrowDown, 5);
      await _hold(tester, LogicalKeyboardKey.arrowLeft, 2);
      await _hold(tester, LogicalKeyboardKey.arrowUp, 5);
    }
    await _hold(tester, LogicalKeyboardKey.arrowDown, 3);
    await tester.pumpAndSettle();
    _expectOneFocusedRestAtRest(tester);
    // La riga a fuoco è agganciata in alto: l'anello resta dentro lo schermo.
    expect(_ringRect(tester).top, greaterThanOrEqualTo(0));
  });

  testWidgets('tornando su una riga il fuoco torna dove era', (tester) async {
    await tester.pumpWidget(_page(rows: 2, count: 20));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 6);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i6');
    await _hold(tester, LogicalKeyboardKey.arrowDown, 1);
    await tester.pumpAndSettle();
    expect(_focusedKey(), startsWith('r1-'));
    await _hold(tester, LogicalKeyboardKey.arrowUp, 1);
    await tester.pumpAndSettle();
    expect(_focusedKey(), 'r0-i6');
  });

  testWidgets('animazioni ridotte: niente scala, solo l\'anello', (
    tester,
  ) async {
    await tester.pumpWidget(_page(reduce: true));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 3);
    await tester.pumpAndSettle();
    final focused = _effects(tester).singleWhere((e) => e.widget.active);
    expect(focused.scaleProgress, 0.0);
    expect(focused.ringOpacity, 1.0);
  });
}
