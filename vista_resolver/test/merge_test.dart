import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

const principale = '''
#EXTM3U url-tvg="http://guida/a.xml"
#EXTINF:-1 group-title="Nazionali" tvg-logo="http://logo/rai1.png",Rai 1 HD
http://a/rai1
#EXTINF:-1 group-title="Nazionali",Rai 2
http://a/rai2
#EXTINF:-1 group-title="Film",Matrix (1999)
http://a/movie/matrix.mkv
''';

const riserva = '''
#EXTM3U url-tvg="http://guida/b.xml"
#EXTINF:-1 group-title="IT",IT: Rai 1 FHD
http://b/rai1
#EXTINF:-1 group-title="IT",Rai 1 HD
http://a/rai1
#EXTINF:-1 group-title="IT",La7
http://b/la7
#EXTINF:-1 group-title="Film",Matrix (1999)
http://b/movie/matrix.mkv
''';

void main() {
  test('stesso canale in due liste: un canale, flussi di entrambe', () {
    final a = buildM3uCatalog(parseM3u(principale));
    final b = buildM3uCatalog(parseM3u(riserva));
    final m = mergeCatalogs([('', a), ('b~', b)]);

    expect(m.live.channels.map((c) => (c.name, c.number, c.group)), [
      ('Rai 1', 1, 'Nazionali'),
      ('Rai 2', 2, 'Nazionali'),
      ('La7', 3, 'IT'),
    ]);
    final rai1 = m.live.channels.first;
    // FHD della riserva prima dell'HD; l'indirizzo doppio una volta sola.
    expect(rai1.streams.map((s) => s.url), ['http://b/rai1', 'http://a/rai1']);
    expect(rai1.logo, 'http://logo/rai1.png');
    expect(m.live.report.epgUrl, 'http://guida/a.xml,http://guida/b.xml');
    expect(m.live.report.merged, 1);

    // Film: entrambi, quello della seconda fonte con il prefisso.
    expect(m.movies.map((f) => f.title), ['Matrix', 'Matrix']);
    expect(m.movies.last.id, startsWith('b~'));
    expect(m.movies.first.id, isNot(startsWith('b~')));
  });

  test('una fonte senza prefisso resta identica', () {
    final a = buildM3uCatalog(parseM3u(principale));
    expect(identical(mergeCatalogs([('', a)]), a), isTrue);
    expect(mergeCatalogs([]).isEmpty, isTrue);
  });

  test('serie: prefisso anche sugli episodi', () {
    const s = Series(
      id: '7',
      title: 'Serie',
      episodes: [Episode(id: '70', title: 'Pilota', url: 'u', season: 1, number: 1)],
    );
    final p = s.withIdPrefix('x~');
    expect((p.id, p.episodes.single.id), ('x~7', 'x~70'));
    expect(identical(s.withIdPrefix(''), s), isTrue);
  });
}
