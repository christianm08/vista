import 'dart:convert';

import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

const list = '''
#EXTM3U
#EXTINF:-1,Rai 1 HD
http://s/rai1
#EXTINF:-1,Canale Primo
http://s/primo
#EXTINF:-1,Rete 4
http://s/rete4
''';

void main() {
  test('rinomina e logo personalizzato', () {
    final prefs = const ChannelPrefs()
        .rename('rai 1', 'Rai Uno ')
        .setLogo('rai 1', 'https://img.example/r1.png')
        .rename('rete 4', 'Rete Quattro')
        .rename('rete 4', ''); // ripristino
    final channels = prefs.apply(resolveChannels(parseM3u(list)).channels);
    final rai1 = channels.first;
    expect((rai1.name, rai1.monogram, rai1.renamed, rai1.customLogo),
        ('Rai Uno', 'RU', true, 'https://img.example/r1.png'));
    expect((channels[2].name, channels[2].renamed), ('Rete 4', false));
  });

  test('unione manuale e separazione', () {
    var prefs = const ChannelPrefs()
        .rename('canale primo', 'Da perdere')
        .merge('canale primo', 'rai 1');
    expect(prefs.overrides, isNot(contains('canale primo')));
    expect(prefs.mergedInto('rai 1'), ['canale primo']);

    var r = resolveChannels(parseM3u(list), merges: prefs.merges);
    expect(r.channels.map((c) => c.name), ['Rai 1', 'Rete 4']);
    expect(r.channels.first.streams.map((s) => s.url), ['http://s/rai1', 'http://s/primo']);

    prefs = prefs.split('canale primo');
    r = resolveChannels(parseM3u(list), merges: prefs.merges);
    expect(r.channels, hasLength(3));
  });

  test('canali nascosti', () {
    var prefs = const ChannelPrefs().setHidden('rete 4', true).rename('rete 4', 'R4');
    var channels = prefs.apply(resolveChannels(parseM3u(list)).channels);
    expect(channels.map((c) => (c.name, c.hidden)),
        [('Rai 1', false), ('Canale Primo', false), ('R4', true)]);
    prefs = prefs.setHidden('rete 4', false);
    expect(prefs.hidden, isEmpty);
    // Unendo un canale nascosto, la sua impostazione sparisce.
    prefs = prefs.setHidden('canale primo', true).merge('canale primo', 'rai 1');
    expect(prefs.hidden, isEmpty);
    final back = ChannelPrefs.fromJson(
        jsonDecode(jsonEncode(const ChannelPrefs().setHidden('rai 1', true).toJson()))
            as Map<String, dynamic>);
    expect(back.hidden, {'rai 1'});
  });

  test('nascondi e mostra più canali insieme', () {
    var prefs = const ChannelPrefs()
        .rename('rai 1', 'Uno')
        .setHiddenAll(['rai 1', 'rete 4'], true);
    expect(prefs.hidden, {'rai 1', 'rete 4'});
    expect(prefs.overrides['rai 1']!.name, 'Uno'); // il resto non cambia
    prefs = prefs.setHiddenAll(['rete 4', 'canale primo'], true);
    expect(prefs.hidden, {'rai 1', 'rete 4', 'canale primo'});
    prefs = prefs.setHiddenAll(['rai 1', 'rete 4', 'sconosciuto'], false);
    expect(prefs.hidden, {'canale primo'});
  });

  test('JSON andata e ritorno, senza voci vuote', () {
    final prefs = const ChannelPrefs()
        .merge('canale primo', 'rai 1')
        .rename('rete 4', 'R4')
        .setLogo('rai 1', 'https://img.example/r1.png')
        .rename('la7', '');
    final json = jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>;
    expect(json['overrides'], isNot(contains('la7')));
    final back = ChannelPrefs.fromJson(json);
    expect(back.merges, {'canale primo': 'rai 1'});
    expect(back.overrides['rete 4']!.name, 'R4');
    expect(back.overrides['rai 1']!.logo, 'https://img.example/r1.png');
  });

  test('ricerca fra i loghi tv-logos e albero di GitHub', () {
    final paths = pathsFromGithubTree(jsonEncode({
      'tree': [
        {'path': 'countries/italy', 'type': 'tree'},
        {'path': 'countries/italy/rai-1-it.png', 'type': 'blob'},
        {'path': 'countries/italy/rai-movie-it.png', 'type': 'blob'},
        {'path': 'countries/italy/rai-news-24-it.png', 'type': 'blob'},
        {'path': 'countries/italy/la7-it.png', 'type': 'blob'},
      ],
    }));
    expect(paths, hasLength(4));
    final logos = TvLogos(buildTvLogoIndex(paths));
    expect(logos.search('Rai').first, endsWith('/rai-1-it.png'));
    expect(logos.search('rai'), hasLength(3));
    expect(logos.search('  '), isEmpty);
    expect(() => pathsFromGithubTree('{"message":"rate limit"}'), throwsFormatException);
  });
}
