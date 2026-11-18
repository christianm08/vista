import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/epg_guide.dart';
import 'package:vista/widgets/vista_focus.dart';
import 'package:vista_resolver/vista_resolver.dart';

final _channels = [
  for (var i = 1; i <= 50; i++)
    Channel(
      key: 'canale $i',
      number: i,
      name: 'Canale $i',
      monogram: 'C$i',
      group: 'Prova',
      streams: const [],
      sourceNames: const [],
    ),
];

/// Un pulsante sopra la guida (al posto dei filtri) e la guida sotto.
Widget _page(FocusNode grid, FocusNode above) => MaterialApp(
  theme: buildVistaTheme(),
  home: Scaffold(
    body: Column(
      children: [
        TextButton(focusNode: above, onPressed: () {}, child: const Text('Su')),
        Expanded(
          child: EpgGrid(
            channels: _channels,
            guide: EpgGuide.empty,
            now: DateTime(2026, 11, 18, 20, 10),
            focusNode: grid,
            onSelectionChanged: (_) {},
            onPlay: (_) {},
            onEdit: (_) {},
          ),
        ),
      ],
    ),
  ),
);

Future<void> _hold(WidgetTester tester, LogicalKeyboardKey key, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 33));
  }
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 720);
    view.devicePixelRatio = 1;
  });

  testWidgets('guida: giù tenuto 5 s, una sola cella a fuoco e anello intero', (
    tester,
  ) async {
    final grid = FocusNode();
    final above = FocusNode();
    addTearDown(grid.dispose);
    addTearDown(above.dispose);
    await tester.pumpWidget(_page(grid, above));
    grid.requestFocus();
    await tester.pumpAndSettle();

    await _hold(tester, LogicalKeyboardKey.arrowDown, 150);
    await tester.pumpAndSettle();

    final effects = tester
        .stateList<VistaFocusEffectState>(find.byType(VistaFocusEffect))
        .toList();
    final active = effects.where((e) => e.widget.active).toList();
    expect(active, hasLength(1));
    for (final e in effects.where((e) => !e.widget.active)) {
      expect(e.ringOpacity, 0.0, reason: 'anello spento');
      expect(e.scale, 1.0);
    }

    // L'anello della cella a fuoco (l'ultima riga) sta dentro la lista.
    final box = active.single.context.findRenderObject()! as RenderBox;
    final ring = (box.localToGlobal(Offset.zero) & box.size).inflate(
      VistaFocus.ringGapTight + VistaFocus.ringWidth,
    );
    final list = tester.getRect(find.byType(ListView));
    expect(list.contains(ring.topLeft), isTrue, reason: '$ring in $list');
    expect(list.contains(ring.bottomRight), isTrue, reason: '$ring in $list');
  });

  testWidgets('guida: su dalla prima riga si esce verso i filtri', (
    tester,
  ) async {
    final grid = FocusNode();
    final above = FocusNode();
    addTearDown(grid.dispose);
    addTearDown(above.dispose);
    await tester.pumpWidget(_page(grid, above));
    grid.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(grid.hasFocus, isTrue, reason: 'dalla seconda riga si resta');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(above.hasFocus, isTrue);
  });
}
