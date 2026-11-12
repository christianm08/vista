import 'dart:convert';
import 'dart:io' show gzip;

import 'package:test/test.dart';
import 'package:vista_resolver/vista_resolver.dart';

const xmltv = '''\u{FEFF}<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="none">
  <channel id="Rai.1.HD..101.it"><display-name lang="it">Rai 1 HD</display-name></channel>
  <channel id="Canale.5.it"><display-name lang="it">Canale 5</display-name></channel>
  <channel id="Sky.Uno.it"><display-name lang="it">Sky Uno</display-name></channel>
  <channel id="Vuoto.it"/>
  <programme start="20261110180000 +0100" stop="20261110200000 +0100" channel="Rai.1.HD..101.it">
    <title lang="it">L'Eredità</title>
    <desc lang="it">Quiz &amp; giochi</desc>
    <category lang="it">Intrattenimento</category>
  </programme>
  <programme start="20261110200000 +0100" stop="20261110203000 +0100" channel="Rai.1.HD..101.it">
    <title lang="it">Tg1</title>
    <sub-title lang="it">Edizione delle 20</sub-title>
  </programme>
  <programme start="20261101200000 +0100" stop="20261101210000 +0100" channel="Rai.1.HD..101.it">
    <title>Vecchio</title>
  </programme>
  <programme start="20261110180000 +0000" stop="20261110210000 +0000" channel="Canale.5.it">
    <title><![CDATA[Striscia la notizia]]></title>
  </programme>
  <programme start="20261110190000 +0100" stop="20261110200000 +0100" channel="Sky.Uno.it">
    <title></title>
  </programme>
</tv>
''';

final now = DateTime.utc(2026, 11, 10, 18, 15); // 19:15 in Italia

Stream<List<int>> chunks(List<int> bytes, [int size = 37]) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

Channel channel(String name, {String tvgId = ''}) =>
    resolveChannels(M3uPlaylist(entries: [
      M3uEntry(name: name, url: 'http://s/$name', tvgId: tvgId),
    ])).channels.single;

void main() {
  test('parseXmltvTime con fuso orario', () {
    expect(parseXmltvTime('20261110200000 +0100'), DateTime.utc(2026, 11, 10, 19));
    expect(parseXmltvTime('20261110200000 -0230'), DateTime.utc(2026, 11, 10, 22, 30));
    expect(parseXmltvTime('202611102000'), DateTime.utc(2026, 11, 10, 20));
    expect(parseXmltvTime('ieri'), isNull);
  });

  test('epgIdKey semplifica gli id di epg.lat, iptv-org e tvg-id', () {
    expect(epgIdKey('Rai.1.HD..101.it'), 'rai1');
    expect(epgIdKey('Rai1.it'), 'rai1');
    expect(epgIdKey('Rai1.it@HD'), 'rai1');
    expect(epgIdKey('RAI.Sport...227.it'), 'raisport');
    expect(epgIdKey('LA7.HD.it'), 'la7');
    expect(epgIdKey('Canale.5.it'), 'canale5');
  });

  for (final gz in [false, true]) {
    test('lettura a flusso ${gz ? 'gzip' : 'testo'}, finestra temporale', () async {
      final raw = utf8.encode(xmltv);
      final data = await parseXmltv(
        chunks(gz ? gzip.encode(raw) : raw),
        from: now.subtract(const Duration(hours: 6)),
        to: now.add(const Duration(hours: 24)),
      );
      final rai = data.programmes['Rai.1.HD..101.it']!;
      expect(rai.map((p) => p.title), ["L'Eredità", 'Tg1']); // "Vecchio" fuori finestra
      expect(rai.first.description, 'Quiz & giochi');
      expect(rai.first.category, 'Intrattenimento');
      expect(rai.last.subtitle, 'Edizione delle 20');
      expect(data.programmes['Canale.5.it']!.single.title, 'Striscia la notizia');
      expect(data.programmes, isNot(contains('Sky.Uno.it'))); // senza titolo
      expect(data.names['Canale.5.it'], ['Canale 5']);
      expect(data.lastStop, DateTime.utc(2026, 11, 10, 21));
    });
  }

  test('EpgGuide abbina per tvg-id, id semplificato e nome', () async {
    final data = await parseXmltv(chunks(utf8.encode(xmltv)));
    final guide = EpgGuide([data]);

    // tvg-id in stile iptv-org → id di epg.lat
    final rai1 = channel('IT: Rai 1 [4K-Q]', tvgId: 'Rai1.it@HD');
    expect(guide.nowOn(rai1, now: now)!.title, "L'Eredità");
    expect(guide.upcoming(rai1, now: now).map((p) => p.title), ["L'Eredità", 'Tg1']);
    expect(guide.nowOn(rai1, now: now)!.progressAt(now), closeTo(0.625, 0.001));

    // senza tvg-id: per nome
    final c5 = channel('Canale 5 FHD');
    expect(guide.nowOn(c5, now: now)!.title, 'Striscia la notizia');

    expect(guide.forChannel(channel('Sconosciuto TV')), isEmpty);
  });

  test('la prima guida con programmi attuali vince sulla seguente', () async {
    final vecchia = await parseXmltv(chunks(utf8.encode(
        '<tv><programme start="20260919200000 +0000" stop="20260919210000 +0000" '
        'channel="Rai1.it"><title>Settembre</title></programme></tv>')));
    final lista = await parseXmltv(chunks(utf8.encode(
        '<tv><programme start="20261110180000 +0000" stop="20261110190000 +0000" '
        'channel="rai1"><title>Oggi</title></programme></tv>')));
    final rai1 = channel('Rai 1', tvgId: 'Rai1.it');
    expect(EpgGuide([vecchia, lista]).nowOn(rai1, now: now)!.title, 'Oggi');
    // Solo la guida vecchia: si mostra comunque, ma niente "in onda".
    final soloVecchia = EpgGuide([vecchia]);
    expect(soloVecchia.forChannel(rai1, now: now).single.title, 'Settembre');
    expect(soloVecchia.nowOn(rai1, now: now), isNull);
  });

  test('orari spostati: anche la finestra temporale usa quelli corretti', () async {
    const one = '<tv><programme start="20261110180000 +0000" stop="20261110190000 +0000" '
        'channel="rai1"><title>Tg</title></programme></tv>';
    final avanti = await parseXmltv(chunks(utf8.encode(one)), shift: const Duration(hours: 1));
    final p = avanti.programmes['rai1']!.single;
    expect((p.start, p.stop), (DateTime.utc(2026, 11, 10, 19), DateTime.utc(2026, 11, 10, 20)));
    // Finito alle 19 secondo il file, ma alle 20 dopo lo spostamento.
    final dentro = await parseXmltv(chunks(utf8.encode(one)),
        from: DateTime.utc(2026, 11, 10, 19, 30), shift: const Duration(hours: 1));
    expect(dentro.programmes['rai1'], hasLength(1));
    final indietro = await parseXmltv(chunks(utf8.encode(one)),
        from: DateTime.utc(2026, 11, 10, 18, 30), shift: const Duration(hours: -1));
    expect(indietro.programmes, isEmpty);
  });

  test('file vuoto o senza programmi', () async {
    expect((await parseXmltv(const Stream.empty())).programmes, isEmpty);
    expect(EpgGuide([EpgData.empty]).isEmpty, isTrue);
  });
}
