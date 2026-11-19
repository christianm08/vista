import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/vista_controls.dart';
import 'package:vista/widgets/vista_focus.dart';

void main() {
  testWidgets('nella finestra la scelta attuale ha il fuoco, e si vede', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVistaTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  children: [
                    for (final o in ['Uno', 'Due', 'Tre'])
                      VistaChoice(
                        selected: o == 'Due',
                        onTap: () => Navigator.pop(ctx, o),
                        child: Text(o),
                      ),
                  ],
                ),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    // Modalità tastiera: giù porta il fuoco da "Due" a "Tre".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final active = tester
        .stateList<VistaFocusEffectState>(find.byType(VistaFocusEffect))
        .where((e) => e.widget.active)
        .toList();
    expect(active, hasLength(1));
    expect(active.single.ringOpacity, 1.0);
    expect(
      find.descendant(
        of: find.byWidget(active.single.widget),
        matching: find.text('Tre'),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 'Tre');
  });

  testWidgets('un pulsante disattivato si costruisce senza errori', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVistaTheme(),
        home: const Scaffold(
          body: Center(
            child: VistaButton.primary(label: 'Salva', onPressed: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
