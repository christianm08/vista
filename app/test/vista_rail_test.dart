import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/vista_nav.dart';

// Barra laterale e mouse: si apre solo passando sulla striscia delle icone,
// non su tutta la larghezza che occupa da aperta (lì ci sono le prime card).

void main() {
  testWidgets('il mouse apre la barra solo sopra la striscia chiusa', (
    tester,
  ) async {
    final opened = <bool>[];
    var cardTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Una card sotto la parte della barra che da chiusa non si vede.
              Positioned(
                left: VistaSize.railExpanded - VistaSpace.s64,
                top: 200,
                width: VistaSpace.s48,
                height: VistaSpace.s48,
                child: GestureDetector(
                  onTap: () => cardTaps++,
                  child: const ColoredBox(color: VistaColors.surface),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: VistaSize.railExpanded,
                child: VistaRail(
                  items: const [
                    VistaNavItem('Home', Icons.home_rounded),
                    VistaNavItem('Live', Icons.live_tv_rounded),
                  ],
                  selected: 0,
                  onSelect: (_) {},
                  onOpenChanged: opened.add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final layout = VistaLayout.of(tester.element(find.byType(VistaRail)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 224));
    addTearDown(mouse.removePointer);

    // Oltre la striscia chiusa, sopra la card: la barra resta chiusa e la
    // card riceve il clic.
    await mouse.moveTo(
      const Offset(VistaSize.railExpanded - VistaSpace.s48, 224),
    );
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tapAt(
      const Offset(VistaSize.railExpanded - VistaSpace.s48, 224),
    );
    expect(cardTaps, 1);

    // Sulla striscia delle icone: si apre.
    await mouse.moveTo(Offset(layout.railWidth / 2, 224));
    await tester.pumpAndSettle();
    expect(opened, [true]);

    // Fuori dalla barra aperta: si richiude.
    await mouse.moveTo(const Offset(600, 224));
    await tester.pumpAndSettle();
    expect(opened, [true, false]);
  });
}
