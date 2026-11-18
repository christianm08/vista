import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/vista_cards.dart';
import 'package:vista/widgets/vista_focus.dart';
import 'package:vista/widgets/vista_grid.dart';

/// Griglia di [count] locandine col primo elemento a fuoco e, a sinistra,
/// un pulsante dove porta la freccia sinistra dalla prima colonna.
Widget _page(int count, {required VoidCallback onExitLeft}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) {
        final layout = VistaLayout.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: layout.contentLeft,
            top: layout.safe.top,
            bottom: layout.safe.bottom,
          ),
          child: VistaPosterGrid(
            header: const SizedBox(height: VistaSpace.s64),
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            onExitLeft: onExitLeft,
            itemCount: count,
            itemKey: (i) => ValueKey('p$i'),
            itemBuilder: (context, i, width) => VistaPosterCard(
              title: 'Titolo $i',
              image: '',
              restWidth: width,
              autofocus: i == 0,
              onTap: () {},
            ),
          ),
        );
      },
    ),
  ),
);

Future<void> _hold(WidgetTester tester, LogicalKeyboardKey key, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 33));
  }
}

List<VistaFocusEffectState> _effects(WidgetTester tester) => tester
    .stateList<VistaFocusEffectState>(find.byType(VistaFocusEffect))
    .toList();

/// Un solo elemento a fuoco; tutti gli altri a scala 1 e anello spento.
void _expectOneFocused(WidgetTester tester) {
  final effects = _effects(tester);
  expect(effects.where((e) => e.widget.active), hasLength(1));
  for (final e in effects.where((e) => !e.widget.active)) {
    expect(e.scale, 1.0);
    expect(e.ringOpacity, 0.0);
  }
}

/// L'anello dell'elemento a fuoco sta tutto dentro la vista della griglia.
void _expectRingInside(WidgetTester tester) {
  final state = _effects(tester).singleWhere((e) => e.widget.active);
  final box = state.context.findRenderObject()! as RenderBox;
  final rest = box.localToGlobal(Offset.zero) & box.size;
  final ring = Rect.fromCenter(
    center: rest.center,
    width: rest.width * state.scale,
    height: rest.height * state.scale,
  ).inflate(VistaFocus.ringGap + VistaFocus.ringWidth);
  final view = tester.renderObject<RenderBox>(find.byType(CustomScrollView));
  final bounds = view.localToGlobal(Offset.zero) & view.size;
  final where = 'anello $ring, vista $bounds';
  expect(bounds.contains(ring.topLeft), isTrue, reason: where);
  expect(bounds.contains(ring.bottomRight), isTrue, reason: where);
}

/// Posizione nella griglia dell'elemento a fuoco.
int _focused() {
  final ctx = FocusManager.instance.primaryFocus!.context!;
  final slot = ctx.findAncestorWidgetOfExactType<KeyedSubtree>()!;
  return int.parse((slot.key! as ValueKey<String>).value.substring(1));
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 720);
    view.devicePixelRatio = 1;
  });

  testWidgets('giù e su tenuti 5 s: tutto a riposo, anello intero', (
    tester,
  ) async {
    await tester.pumpWidget(_page(200, onExitLeft: () {}));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowDown, 150);
    await tester.pumpAndSettle();
    expect(_focused(), greaterThan(180), reason: 'arrivato in fondo');
    _expectOneFocused(tester);
    _expectRingInside(tester);

    await _hold(tester, LogicalKeyboardKey.arrowUp, 150);
    await tester.pumpAndSettle();
    expect(_focused(), 0);
    _expectOneFocused(tester);
    _expectRingInside(tester);
  });

  testWidgets('su TV l\'anello resta nell\'area sicura', (tester) async {
    Device.isTv = true;
    addTearDown(() => Device.isTv = false);
    await tester.pumpWidget(_page(200, onExitLeft: () {}));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowDown, 20);
    await _hold(tester, LogicalKeyboardKey.arrowRight, 20);
    await tester.pumpAndSettle();
    _expectOneFocused(tester);
    _expectRingInside(tester);
  });

  testWidgets('a sinistra dalla prima colonna si esce dalla griglia', (
    tester,
  ) async {
    var exits = 0;
    await tester.pumpWidget(_page(40, onExitLeft: () => exits++));
    await tester.pumpAndSettle();
    await _hold(tester, LogicalKeyboardKey.arrowRight, 1);
    await _hold(tester, LogicalKeyboardKey.arrowLeft, 1);
    expect(exits, 0, reason: 'dalla seconda colonna si resta nella griglia');
    await _hold(tester, LogicalKeyboardKey.arrowLeft, 1);
    expect(exits, 1);
  });
}
