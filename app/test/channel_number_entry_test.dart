import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vista/player/channel_number_entry.dart';

KeyDownEvent _down(LogicalKeyboardKey k) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: k,
  timeStamp: Duration.zero,
);

void main() {
  late List<int> committed;
  late ChannelNumberEntry entry;

  setUp(() {
    committed = [];
    entry = ChannelNumberEntry(onChanged: () {}, onCommit: committed.add);
  });
  tearDown(() => entry.dispose());

  testWidgets('dopo la pausa va al numero digitato', (tester) async {
    entry.handleKey(_down(LogicalKeyboardKey.digit1));
    entry.handleKey(_down(LogicalKeyboardKey.numpad2));
    expect(entry.typed, '12');
    await tester.pump(ChannelNumberEntry.timeout);
    expect(committed, [12]);
    expect(entry.isEmpty, isTrue);
  });

  testWidgets('OK conferma subito, Backspace cancella una cifra', (
    tester,
  ) async {
    entry.handleKey(_down(LogicalKeyboardKey.digit4));
    entry.handleKey(_down(LogicalKeyboardKey.digit5));
    expect(
      entry.handleKey(_down(LogicalKeyboardKey.backspace)),
      KeyEventResult.handled,
    );
    expect(entry.typed, '4');
    entry.handleKey(_down(LogicalKeyboardKey.select));
    expect(committed, [4]);
    await tester.pump(ChannelNumberEntry.timeout);
    expect(committed, [4]);
  });

  test('senza cifre OK e Backspace non sono suoi', () {
    expect(entry.handleKey(_down(LogicalKeyboardKey.select)), isNull);
    expect(entry.handleKey(_down(LogicalKeyboardKey.backspace)), isNull);
  });

  testWidgets('oltre 4 cifre si ricomincia', (tester) async {
    for (final k in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit7,
    ]) {
      entry.handleKey(_down(k));
    }
    expect(entry.typed, '7');
    await tester.pump(ChannelNumberEntry.timeout);
  });
}
