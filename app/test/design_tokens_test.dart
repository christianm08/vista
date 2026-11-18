import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// I file già migrati ai token. Cresce a ogni fase; nella fase 7 diventa
/// tutta l'interfaccia (lib/ tranne tokens.dart, data/ e player/).
const _migrated = [
  'lib/theme.dart',
  'lib/widgets/focus_card.dart',
  'lib/widgets/vista_focus.dart',
  'lib/widgets/vista_cards.dart',
  'lib/widgets/vista_row.dart',
  'lib/widgets/vista_controls.dart',
  'lib/widgets/vista_nav.dart',
  'lib/widgets/vista_preview.dart',
  'lib/screens/gallery_screen.dart',
  'lib/screens/home_screen.dart',
  'lib/widgets/list_titles.dart',
  'lib/widgets/vista_detail.dart',
  'lib/widgets/availability.dart',
  'lib/screens/title_screen.dart',
  'lib/screens/tmdb_title_screen.dart',
  // Fase 5: Live TV e player dal vivo (in lib/player/ solo l'interfaccia).
  'lib/screens/live_screen.dart',
  'lib/screens/player_screen.dart',
  'lib/widgets/epg_guide.dart',
  'lib/widgets/live_preview.dart',
  'lib/widgets/channel_logo.dart',
  'lib/player/live_banner.dart',
  'lib/player/live_channel_list.dart',
  'lib/player/options_panel.dart',
  'lib/player/channel_number_entry.dart',
];

/// Valori scritti a mano che devono stare solo in lib/tokens.dart.
final _rules = <String, RegExp>{
  'colore': RegExp(r'Color\(0x|\bColors\.'),
  'raggio': RegExp(r'circular\([1-9]'),
  'durata': RegExp(r'Duration\((milliseconds|seconds|minutes):'),
  'spaziatura': RegExp(
    r'EdgeInsets\.[a-zA-Z]+\([^)]*\b[1-9]|SizedBox\((width|height): [1-9]|'
    r'(spacing|runSpacing): [1-9]',
  ),
  'corpo del testo': RegExp(r'fontSize: [1-9]'),
};

/// Eccezioni motivate: timer di logica e calcoli sugli orari della guida,
/// non durate d'interfaccia.
const _allowed = [
  'Duration(seconds: 20)', // orologio
  'Duration(seconds: 30)', // orologio della guida
  'Duration(minutes: ', // orari dei programmi
  'Duration(seconds: 12)', // flusso bloccato
  'Duration(seconds: 2)', // il video avanza davvero
  'Duration(seconds: 2 * _attempt)', // nuovo tentativo
  'Duration(milliseconds: 350)', // fuoco dopo il ritorno da Multiview
  'Duration(milliseconds: 900)', // pausa prima dell'anteprima
  'Duration(seconds: 10)', // anteprima bloccata
  'Duration(milliseconds: 1600)', // conferma del numero digitato
];

void main() {
  test('nei file migrati non ci sono valori fuori dai token', () {
    final problems = <String>[];
    for (final path in _migrated) {
      final lines = File(path).readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        final code = line.split('//').first;
        if (_allowed.any(code.contains)) continue;
        for (final MapEntry(key: what, value: re) in _rules.entries) {
          if (re.hasMatch(code)) problems.add('$path:${i + 1} ($what): $line');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
