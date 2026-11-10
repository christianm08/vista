import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

void main() {
  test('logoKey', () {
    expect(logoKey('canale 5 +1'), 'canale5plus1');
    expect(logoKey('rai news 24'), 'rainews24');
    expect(logoKey('sky tg24'), 'skytg24');
  });

  test('tvLogoEntry legge nome, paese e varianti', () {
    expect(tvLogoEntry('countries/italy/rai-1-it.png'), (key: 'rai1', rank: 0));
    expect(tvLogoEntry('countries/italy/hd/rai-1-hd-it.png'), (key: 'rai1', rank: 10));
    expect(tvLogoEntry('countries/italy/sky-cinema-uno-hz-it.png'),
        (key: 'skycinemauno', rank: 2));
    expect(tvLogoEntry('countries/italy/rete4-it.png')!.key, 'rete4');
    expect(tvLogoEntry('countries/italy/canale5-it.png')!.key, 'canale5');
    expect(tvLogoEntry('countries/international/animal-planet-int.png'),
        (key: 'animalplanet', rank: 100));
    expect(tvLogoEntry('countries/italy/0_all_logos_mosaic.md'), isNull);
    expect(tvLogoEntry('countries/brazil/globo-br.png'), isNull);
    expect(tvLogoEntry('misc/vista.png'), isNull);
  });

  test('l\'indice tiene il file migliore per ogni canale', () {
    final index = buildTvLogoIndex([
      'countries/italy/hd/rai-1-hd-it.png',
      'countries/italy/rai-1-it.png',
      'countries/italy/sky-cinema-uno-hz-it.png',
      'countries/italy/sky-cinema-uno-it.png',
      'countries/italy/paramount-network-white-it.png',
      'countries/italy/paramount-network-hz-it.png',
      'countries/united-kingdom/discovery-uk.png',
      'countries/italy/discovery-channel-it.png',
      'countries/international/discovery-int.png',
    ]);
    expect(index['rai1'], 'countries/italy/rai-1-it.png');
    expect(index['skycinemauno'], 'countries/italy/sky-cinema-uno-it.png');
    expect(index['paramountnetwork'], 'countries/italy/paramount-network-hz-it.png');
    expect(index['discovery'], 'countries/international/discovery-int.png');
  });

  test('TvLogos cerca per nome normalizzato e poi per tvg-id', () {
    final logos = TvLogos(buildTvLogoIndex([
      'countries/italy/rai-1-it.png',
      'countries/italy/rete4-it.png',
      'countries/italy/rai-news-24-it.png',
      'countries/italy/la7-it.png',
    ]));
    final r = resolveChannels(parseM3u('''
#EXTM3U
#EXTINF:-1,IT: Rai 1 [4K-Q]
http://s/1
#EXTINF:-1,Rete 4 HD
http://s/2
#EXTINF:-1,RaiNews24
http://s/3
#EXTINF:-1 tvg-id="La7.it@HD",Canale sette
http://s/4
#EXTINF:-1,Sconosciuto TV
http://s/5
'''));
    expect([for (final c in r.channels) logos.pathFor(c)], [
      'countries/italy/rai-1-it.png',
      'countries/italy/rete4-it.png',
      'countries/italy/rai-news-24-it.png',
      'countries/italy/la7-it.png',
      null,
    ]);
    expect(logos.urlFor(r.channels.first),
        'https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/italy/rai-1-it.png');
  });
}
