import 'package:flutter_test/flutter_test.dart';
import 'package:vista/data/recordings.dart';
import 'package:vista/data/stream_recorder.dart';
import 'package:vista_resolver/vista_resolver.dart';

const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6500000,RESOLUTION=1920x1080
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
480/index.m3u8
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('varianti HLS: banda e altezza', () {
    final v = parseHlsVariants(master);
    expect(v.map((x) => (x.uri, x.bandwidth, x.height)), [
      ('1080/index.m3u8', 6500000, 1080),
      ('720/index.m3u8', 3200000, 720),
      ('480/index.m3u8', 1400000, 480),
    ]);
  });

  test('flussi della lista: il migliore entro la qualità scelta', () {
    const streams = [
      ChannelStream(quality: Quality.uhd4k, url: '4k', sourceName: ''),
      ChannelStream(quality: Quality.fhd, url: 'fhd', sourceName: ''),
      ChannelStream(quality: Quality.hd, url: 'hd', sourceName: ''),
    ];
    final s = RecordingService.instance;
    s.setQuality(RecordQuality.best);
    expect(s.pickStream(streams)?.url, '4k');
    s.setQuality(RecordQuality.medium);
    expect(s.pickStream(streams)?.url, 'hd');
    // Nessuno abbastanza leggero: il più leggero che c'è.
    s.setQuality(RecordQuality.low);
    expect(s.pickStream(streams)?.url, 'hd');
    expect(
      RecordQuality.medium.estimate(const Duration(hours: 2)),
      'circa 3.2 GB',
    );
  });

  test('due registrazioni nello stesso minuto non si sovrascrivono', () {
    final taken = {'Rete 4 - 1932', 'Rete 4 - 1932 (2)'};
    expect(
      RecordingService.uniqueBase('Rai 1 - 1932', taken.contains),
      'Rai 1 - 1932',
    );
    expect(
      RecordingService.uniqueBase('Rete 4 - 1932', taken.contains),
      'Rete 4 - 1932 (3)',
    );
  });
}
