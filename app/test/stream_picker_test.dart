import 'package:flutter_test/flutter_test.dart';
import 'package:vista/player/stream_picker.dart';
import 'package:vista_resolver/vista_resolver.dart';

List<ChannelStream> streams(List<Quality> qs) => [
      for (var i = 0; i < qs.length; i++)
        ChannelStream(quality: qs[i], url: 'http://s/$i', sourceName: 'S$i'),
    ];

void main() {
  test('Auto parte dal migliore e scala ai successivi', () {
    final p = StreamPicker(streams([Quality.uhd4k, Quality.fhd, Quality.hd]));
    expect(p.current.quality, Quality.uhd4k);
    expect(p.fail(), isTrue);
    expect(p.current.quality, Quality.fhd);
    expect(p.fail(), isTrue);
    expect(p.current.quality, Quality.hd);
    expect(p.fail(), isFalse);
    expect(p.exhausted, isTrue);
  });

  test('scelta manuale: niente salto automatico', () {
    final p = StreamPicker(streams([Quality.fhd, Quality.sd]))..select(1);
    expect(p.current.quality, Quality.sd);
    expect(p.fail(), isFalse);
    expect(p.current.quality, Quality.sd);
  });

  test('reset torna ad Auto dal primo flusso', () {
    final p = StreamPicker(streams([Quality.fhd, Quality.sd]))
      ..fail()
      ..reset();
    expect(p.auto, isTrue);
    expect(p.index, 0);
    expect(p.exhausted, isFalse);
  });

  test('qualità reale dall\'altezza', () {
    expect(qualityFromHeight(2160), '4K');
    expect(qualityFromHeight(1080), 'FHD');
    expect(qualityFromHeight(720), 'HD');
    expect(qualityFromHeight(576), 'SD');
    expect(qualityFromHeight(null), '');
  });
}
