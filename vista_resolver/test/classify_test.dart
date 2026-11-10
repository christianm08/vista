import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

M3uEntry e(String name, String url, {String group = 'Altri', String type = ''}) =>
    M3uEntry(name: name, url: url, group: group, declaredType: type);

void main() {
  group('classifyEntry', () {
    test('un canale "Movie" nel gruppo Film resta live', () {
      expect(
        classifyEntry(e('Rai Movie HD', 'https://x.example/raimovie.m3u8', group: 'Film')),
        ContentKind.live,
      );
    });

    test('percorsi Xtream /live/, /movie/, /series/', () {
      expect(classifyEntry(e('Rai 1', 'http://p.example:8080/live/u/p/1.ts')),
          ContentKind.live);
      expect(classifyEntry(e('Nord', 'http://p.example:8080/movie/u/p/2.mkv')),
          ContentKind.movie);
      expect(classifyEntry(e('Marea S01 E01', 'http://p.example:8080/series/u/p/3.mkv')),
          ContentKind.series);
    });

    test('flusso Xtream senza /live/ e senza estensione è live', () {
      expect(classifyEntry(e('Canale 5', 'http://p.example:8080/u/p/44')),
          ContentKind.live);
    });

    test('estensione di file on demand', () {
      expect(classifyEntry(e('Vetro', 'https://cdn.example/vetro.mp4?t=1')),
          ContentKind.movie);
      expect(classifyEntry(e('Faro S02E03', 'https://cdn.example/faro-203.mkv')),
          ContentKind.series);
    });

    test('il tipo dichiarato vince sull\'URL', () {
      expect(classifyEntry(e('Doc', 'https://x.example/doc.m3u8', type: 'movie')),
          ContentKind.movie);
      expect(classifyEntry(e('Tg', 'https://x.example/tg.mp4', type: 'live')),
          ContentKind.live);
    });

    test('/series/ senza stagione ed episodio diventa un film', () {
      final cat = buildM3uCatalog(M3uPlaylist(entries: [
        e('Speciale', 'http://p.example/series/u/p/9.mp4'),
      ]));
      expect(cat.movies.single.title, 'Speciale');
      expect(cat.series, isEmpty);
    });
  });

  group('parseEpisodeMarker', () {
    test('formati comuni', () {
      final a = parseEpisodeMarker('Marea S01 E02 Il ritorno')!;
      expect((a.show, a.season, a.episode, a.rest), ('Marea', 1, 2, 'Il ritorno'));
      final b = parseEpisodeMarker('Il.Faro.S02E10.720p')!;
      expect((b.show, b.season, b.episode), ('Il.Faro', 2, 10));
      final c = parseEpisodeMarker('Segnale - 1x05')!;
      expect((c.show, c.season, c.episode, c.rest), ('Segnale', 1, 5, ''));
    });

    test('nessun falso positivo sui canali', () {
      expect(parseEpisodeMarker('Rai 1 HD'), isNull);
      expect(parseEpisodeMarker('Canale 5 +1'), isNull);
      expect(parseEpisodeMarker('Sky Sport 24'), isNull);
    });
  });

  test('voci separatore', () {
    for (final s in ['##### SPORT #####', '*** Italy / ***', '=== CINEMA ===', '----- NEWS']) {
      expect(isSeparatorEntry(s), isTrue, reason: s);
    }
    for (final s in ['Rai 1', 'Canale 5 +1', 'Sky Sport 24', 'Rai 3 TGR (Lazio) [HD-B]', 'IT: Rai 1 [4K-Q]']) {
      expect(isSeparatorEntry(s), isFalse, reason: s);
    }
    final cat = buildM3uCatalog(parseM3u(
        '#EXTM3U\n#EXTINF:-1,##### ITALIA #####\nhttp://s/sep\n#EXTINF:-1,Rai 1\nhttp://s/r1\n'));
    expect(cat.live.channels.map((c) => c.name), ['Rai 1']);
  });

  test('splitTitleYear', () {
    expect(splitTitleYear('IT: Nord (2025)'), (title: 'Nord', year: 2025));
    expect(splitTitleYear('|IT| Polvere - 2024'), (title: 'Polvere', year: 2024));
    expect(splitTitleYear('Orbita'), (title: 'Orbita', year: null));
  });

  test('buildM3uCatalog separa live, film e serie', () {
    final cat = buildM3uCatalog(parseM3u('''
#EXTM3U x-tvg-url="https://epg.example/it.xml"
#EXTINF:-1 tvg-id="Rai1.it" group-title="Nazionali",Rai 1 HD
https://live.example/rai1-hd.m3u8
#EXTINF:-1 tvg-id="Rai1.it" group-title="Nazionali",Rai 1 SD
https://live.example/rai1-sd.m3u8
#EXTINF:-1 group-title="Film",Rai Movie
https://live.example/raimovie.m3u8
#EXTINF:-1 tvg-logo="https://img.example/nord.jpg" group-title="VOD Film",IT: Nord (2025)
http://p.example/movie/u/p/10.mkv
#EXTINF:-1 group-title="VOD Film",Nord (2025)
http://p.example/movie/u/p/10.mkv
#EXTINF:-1 group-title="Serie",Marea S02 E01
http://p.example/series/u/p/22.mkv
#EXTINF:-1 tvg-logo="https://img.example/marea.jpg" group-title="Serie",Marea S01 E02 Secondo
http://p.example/series/u/p/21.mkv
#EXTINF:-1 group-title="Serie",Marea S01 E01 Primo
http://p.example/series/u/p/20.mkv
'''));

    expect(cat.live.channels.map((c) => c.name), ['Rai 1', 'Rai Movie']);
    expect(cat.live.report.entries, 3);
    expect(cat.live.report.epgUrl, 'https://epg.example/it.xml');

    final movie = cat.movies.single; // il doppione con lo stesso URL sparisce
    expect((movie.title, movie.year, movie.poster),
        ('Nord', 2025, 'https://img.example/nord.jpg'));

    final marea = cat.series.single;
    expect(marea.title, 'Marea');
    expect(marea.poster, 'https://img.example/marea.jpg');
    expect(marea.episodes.map((x) => x.code), ['S01E01', 'S01E02', 'S02E01']);
    expect(marea.episodes.map((x) => x.title), ['Primo', 'Secondo', 'Episodio 1']);
  });
}
