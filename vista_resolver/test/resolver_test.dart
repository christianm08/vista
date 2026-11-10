import 'dart:io';

import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

String m3u(List<String> lines) => ['#EXTM3U', ...lines].join('\n');

void main() {
  final sample = File('test/fixtures/sample_it.m3u').readAsStringSync();

  group('parseM3u', () {
    test('lista di esempio: 30 voci e URL EPG', () {
      final p = parseM3u(sample);
      expect(p.entries, hasLength(30));
      expect(p.epgUrl, 'https://epg.example/guida-it.xml.gz');
      final first = p.entries.first;
      expect(first.name, 'Rai 1 FHD');
      expect(first.tvgId, 'Rai1.it');
      expect(first.group, 'Nazionali');
      expect(first.url, 'https://demo.example/rai1/fhd.m3u8');
    });

    test('url-tvg, BOM, CRLF, tvg-logo, righe # ignorate', () {
      final p = parseM3u('﻿#EXTM3U url-tvg="http://e/x.xml"\r\n'
          '#EXTINF:-1 tvg-logo="http://l/a.png" group-title="A, B",Canale, con virgola\r\n'
          '#EXTVLCOPT:http-user-agent=x\r\n'
          'http://s/1.m3u8\r\n'
          'http://orfano.m3u8\r\n');
      expect(p.epgUrl, 'http://e/x.xml');
      expect(p.entries, hasLength(1));
      expect(p.entries.single.logo, 'http://l/a.png');
      expect(p.entries.single.group, 'A, B');
      expect(p.entries.single.name, 'con virgola');
      expect(p.entries.single.url, 'http://s/1.m3u8');
    });

    test('senza group-title → "Altri"', () {
      final p = parseM3u(m3u(['#EXTINF:-1,Rai 1', 'http://a']));
      expect(p.entries.single.group, 'Altri');
    });
  });

  group('normalizeName', () {
    final cases = <String, (String, Quality)>{
      'Rai 1 FHD': ('rai 1', Quality.fhd),
      'RAI 1 HD': ('rai 1', Quality.hd),
      'IT: Rai Uno SD': ('rai 1', Quality.sd),
      'Rai 1 UHD': ('rai 1', Quality.uhd4k),
      'Rai 1 2160p': ('rai 1', Quality.uhd4k),
      '|IT| Canale5 HD': ('canale 5', Quality.hd),
      '[ITA] LA 7 1080p': ('la7', Quality.fhd),
      'IT - Rai Due 720p': ('rai 2', Quality.hd),
      'Italia 1 HD': ('italia 1', Quality.hd), // "Italia" non è un prefisso qui
      'Italia1 SD': ('italia 1', Quality.sd),
      'Rai 4 HD': ('rai 4', Quality.hd), // "4" non è 4K
      'Rai 4': ('rai 4', Quality.auto),
      'Canale 5 +1': ('canale 5 +1', Quality.auto),
      'Rai 3 TGR Lazio': ('rai 3 tgr lazio', Quality.auto),
      'RaiNews24 (backup)': ('rai news 24', Quality.auto),
      'Rai 2 HEVC 50fps': ('rai 2', Quality.auto),
      'Rai 1 FHD H.265': ('rai 1', Quality.fhd),
      'Sky TG 24 HD': ('sky tg24', Quality.hd),
      'Canale Città HD': ('canale citta', Quality.hd),
      'Rai_Storia': ('rai storia', Quality.auto),
      // etichette fra parentesi e varianti della qualità
      'Rai 1 [4K-Q]': ('rai 1', Quality.uhd4k),
      'IT: Rai 1 [FHD-Q]': ('rai 1', Quality.fhd),
      'Rai 1 (HD)': ('rai 1', Quality.hd),
      'Rai 1 4K-Q': ('rai 1', Quality.uhd4k),
      'Rai 1 FHD_HQ': ('rai 1', Quality.fhd),
      'Canale 5 [HEVC] [FHD]': ('canale 5', Quality.fhd),
      'Rai 1 [4K HDR]': ('rai 1', Quality.uhd4k),
      'Rai 2 - FHD': ('rai 2', Quality.fhd),
      'Rai 3 TGR (Lazio) [HD-B]': ('rai 3 tgr (lazio)', Quality.hd),
      'Canale 5 (+1) [SD]': ('canale 5 (+1)', Quality.sd),
      'Rai 4 [Q]': ('rai 4 [q]', Quality.auto),
    };
    cases.forEach((input, expected) {
      test('"$input" → ${expected.$1} / ${expected.$2.label}', () {
        expect(normalizeName(input), NormalizedName(expected.$1, expected.$2));
      });
    });
  });

  test('le varianti [4K-Q], [FHD-Q], HD si raggruppano in un canale', () {
    final r = resolveChannels(parseM3u(m3u([
      '#EXTINF:-1,IT: Rai 1 [4K-Q]',
      'http://s/4kq.m3u8',
      '#EXTINF:-1,IT: Rai 1 [FHD-Q]',
      'http://s/fhdq.m3u8',
      '#EXTINF:-1,IT: Rai 1 HD',
      'http://s/hd.m3u8',
      '#EXTINF:-1,IT: Rai 4 [FHD-Q]',
      'http://s/rai4.m3u8',
    ])));
    expect(r.channels.map((c) => c.name), ['Rai 1', 'Rai 4']);
    expect(r.channels.first.streams.map((s) => s.quality),
        [Quality.uhd4k, Quality.fhd, Quality.hd]);
  });

  group('tvgIdKey', () {
    test('qualità dopo @ = stesso canale', () {
      expect(tvgIdKey('Rai1.it@HD'), 'rai1.it');
      expect(tvgIdKey('Rai1.it'), 'rai1.it');
    });
    test('feed regionale dopo @ = canale separato', () {
      expect(tvgIdKey('Rai3.it@Lazio'), 'rai3.it@lazio');
    });
  });

  group('resolveChannels sulla lista di esempio', () {
    final result = resolveChannels(parseM3u(sample));
    Channel ch(String key) => result.channels.firstWhere((c) => c.key == key);

    test('30 voci → 20 canali, 8 raggruppati', () {
      expect(result.report.entries, 30);
      expect(result.report.channels, 20);
      expect(result.report.merged, 8);
      expect(result.report.epgUrl, 'https://epg.example/guida-it.xml.gz');
    });

    test('elenco e ordine dei canali', () {
      expect(result.channels.map((c) => c.key), [
        'rai 1', 'rai 2', 'rai 3', 'rai 3 tgr lazio', 'rete 4', 'canale 5',
        'canale 5 +1', 'italia 1', 'la7', 'tv8', 'nove', 'rai 4',
        'rai news 24', 'sky tg24', 'rai sport', 'rai movie', 'cine34',
        'rai storia', 'focus', 'dmax',
      ]);
      expect(result.channels.map((c) => c.number),
          List.generate(20, (i) => i + 1));
    });

    test('raggruppati: quali sono', () {
      expect(result.channels.where((c) => c.isMerged).map((c) => c.key), [
        'rai 1', 'rai 2', 'canale 5', 'italia 1', 'la7', 'rai 4',
        'rai news 24', 'rai sport',
      ]);
    });

    test('Rai 1: 4K, FHD, HD, SD incluso "IT: Rai Uno SD"', () {
      final rai1 = ch('rai 1');
      expect(rai1.name, 'Rai 1');
      expect(rai1.streams.map((s) => s.quality),
          [Quality.uhd4k, Quality.fhd, Quality.hd, Quality.sd]);
      expect(rai1.sourceNames, contains('IT: Rai Uno SD'));
      expect(rai1.tvgId, 'Rai1.it');
      expect(rai1.bestQuality, Quality.uhd4k);
    });

    test('trappole: Rai 4, Canale 5 +1, Rai 3 TGR Lazio separati', () {
      expect(ch('rai 4').streams.map((s) => s.quality),
          [Quality.hd, Quality.sd]);
      expect(ch('canale 5 +1').streams, hasLength(1));
      expect(ch('canale 5').streams, hasLength(2));
      expect(ch('rai 3 tgr lazio').streams, hasLength(1));
      expect(ch('rai 3').streams, hasLength(1));
    });

    test('Rai News 24: il backup va dopo l\'HD', () {
      final s = ch('rai news 24').streams;
      expect(s.map((x) => x.quality), [Quality.hd, Quality.auto]);
      expect(s.last.sourceName, 'RaiNews24 (backup)');
    });

    test('nomi da mostrare e iniziali', () {
      expect(ch('la7').name, 'La7');
      expect(ch('sky tg24').name, 'Sky TG24');
      expect(ch('rai 3 tgr lazio').name, 'Rai 3 TGR Lazio');
      expect(ch('canale 5 +1').name, 'Canale 5 +1');
      expect(ch('rai 1').monogram, 'R1');
      expect(ch('canale 5 +1').monogram, 'CA5+1');
      expect(ch('rai news 24').monogram, 'RNE24');
      expect(ch('dmax').monogram, 'DMAX');
      expect(ch('cine34').monogram, 'CIN');
    });
  });

  group('resolveChannels: regole', () {
    test('stesso tvg-id con nomi diversi → un canale', () {
      final r = resolveChannels(parseM3u(m3u([
        '#EXTINF:-1 tvg-id="Rai1.it",Rai 1 HD',
        'http://a',
        '#EXTINF:-1 tvg-id="Rai1.it@SD",RaiUno',
        'http://b',
      ])));
      expect(r.channels, hasLength(1));
      expect(r.channels.single.key, 'rai 1');
      expect(r.channels.single.streams.map((s) => s.url), ['http://a', 'http://b']);
    });

    test('feed regionale nel tvg-id → canale separato', () {
      final r = resolveChannels(parseM3u(m3u([
        '#EXTINF:-1 tvg-id="Rai3.it",Rai 3 HD',
        'http://a',
        '#EXTINF:-1 tvg-id="Rai3.it@Lazio",Rai 3 Lazio',
        'http://b',
      ])));
      expect(r.channels, hasLength(2));
    });

    test('URL doppi contati una volta sola', () {
      final r = resolveChannels(parseM3u(m3u([
        '#EXTINF:-1,Rai 2 HD', 'http://same',
        '#EXTINF:-1,RAI 2 HD', 'http://same',
      ])));
      expect(r.channels.single.streams, hasLength(1));
      expect(r.channels.single.sourceNames, hasLength(2));
    });

    test('a parità di qualità resta l\'ordine della lista', () {
      final r = resolveChannels(parseM3u(m3u([
        '#EXTINF:-1,Nove', 'http://1',
        '#EXTINF:-1,Nove HD', 'http://2',
        '#EXTINF:-1,Nove alt', 'http://3',
        '#EXTINF:-1,Nove (backup)', 'http://4',
      ])));
      expect(r.channels.single.streams.map((s) => s.url),
          ['http://2', 'http://1', 'http://3', 'http://4']);
    });

    test('primo tvg-logo trovato', () {
      final r = resolveChannels(parseM3u(m3u([
        '#EXTINF:-1,Focus HD', 'http://1',
        '#EXTINF:-1 tvg-logo="http://logo/focus.png",Focus SD', 'http://2',
      ])));
      expect(r.channels.single.logo, 'http://logo/focus.png');
    });

    final split = m3u([
      '#EXTINF:-1,Rai 1 HD', 'http://a',
      '#EXTINF:-1,RAI1 Italia', 'http://b',
    ]);

    test('senza aiuti, nomi troppo diversi restano separati', () {
      expect(resolveChannels(parseM3u(split)).channels, hasLength(2));
    });

    test('unione manuale (merges)', () {
      final r = resolveChannels(parseM3u(split),
          merges: {'rai1 italia': 'rai 1'});
      expect(r.channels, hasLength(1));
      expect(r.channels.single.key, 'rai 1');
    });

    test('aggancio matcher (iptv-org)', () {
      final r = resolveChannels(parseM3u(split),
          matcher: (k) => k == 'rai1 italia' ? 'rai 1' : null);
      expect(r.channels, hasLength(1));
      expect(r.channels.single.key, 'rai 1');
    });
  });
}
