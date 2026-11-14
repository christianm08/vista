import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/theme.dart';
import 'package:vista/widgets/vista_cards.dart';
import 'package:vista/widgets/vista_detail.dart';

// Volo locandina → backdrop del dettaglio (fase 4): la locandina sfuma nel
// backdrop mentre il riquadro cambia, all'andata e al ritorno; con le
// animazioni ridotte non vola niente.

class _Route<T> extends MaterialPageRoute<T> {
  _Route({required super.builder});

  @override
  Duration get transitionDuration => VistaMotion.sharedElement;

  @override
  Duration get reverseTransitionDuration => VistaMotion.sharedElement;
}

const _tag = 'riga|titolo';

Widget _app({bool reduce = false}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: SizedBox(
          width: VistaSize.poster,
          child: VistaPosterCard(
            title: 'Titolo',
            image: '',
            restWidth: VistaSize.poster,
            heroTag: _tag,
            onTap: () => Navigator.of(context).push(
              _Route<void>(
                builder: (_) => const Scaffold(
                  body: SizedBox(
                    height: 400,
                    child: DetailBackdrop(
                      id: 'x',
                      title: 'Titolo',
                      backdrop: '',
                      poster: '',
                      heroTag: _tag,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Le due opacità del volo: locandina che se ne va, backdrop che arriva.
List<double> _flightOpacities(WidgetTester tester) {
  final shuttle = find.descendant(
    of: find.byType(Overlay),
    matching: find.byWidgetPredicate(
      (w) => w is Stack && w.children.length == 2 && w.fit == StackFit.expand,
    ),
  );
  final fades = tester
      .widgetList<FadeTransition>(
        find.descendant(
          of: shuttle.first,
          matching: find.byType(FadeTransition),
        ),
      )
      .take(2)
      .map((f) => f.opacity.value)
      .toList();
  return fades;
}

void main() {
  testWidgets('andata e ritorno: la locandina sfuma nel backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byType(Hero).first);
    await tester.pump(); // parte la rotta
    await tester.pump(const Duration(milliseconds: 175)); // a metà volo

    expect(find.byType(Hero), findsWidgets);
    final going = _flightOpacities(tester);
    expect(going, hasLength(2));
    expect(going[0] + going[1], moreOrLessEquals(1, epsilon: 1e-6));
    expect(going[1], inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DetailBackdrop), findsOneWidget);

    Navigator.of(tester.element(find.byType(DetailBackdrop))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    final back = _flightOpacities(tester);
    expect(back, hasLength(2));
    expect(back[0] + back[1], moreOrLessEquals(1, epsilon: 1e-6));

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DetailBackdrop), findsNothing);
  });

  testWidgets('la rotta dura 350 ms', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byType(Hero).first);
    await tester.pump();
    await tester.pump(
      VistaMotion.sharedElement - const Duration(milliseconds: 10),
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.byType(DetailBackdrop), findsOneWidget);
  });

  testWidgets('animazioni ridotte: la locandina non ha elemento condiviso', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduce: true));
    expect(
      find.descendant(
        of: find.byType(VistaPosterCard),
        matching: find.byType(Hero),
      ),
      findsNothing,
    );
  });
}
