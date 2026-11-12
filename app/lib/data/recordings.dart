import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vista_resolver/vista_resolver.dart';

import 'stream_recorder.dart';

/// Una registrazione programmata dalla guida.
class ScheduledRecording {
  const ScheduledRecording({
    required this.channelKey,
    required this.channelName,
    required this.title,
    required this.start,
    required this.end,
  });

  final String channelKey;
  final String channelName;
  final String title;

  /// Inizio e fine del programma (la registrazione parte 1 minuto prima e
  /// finisce 3 minuti dopo, per i ritardi delle emittenti).
  final DateTime start;
  final DateTime end;

  DateTime get recordFrom => start.subtract(RecordingService.before);
  DateTime get recordTo => end.add(RecordingService.after);

  bool same(ScheduledRecording o) =>
      o.channelKey == channelKey && o.start == start;

  Map<String, dynamic> toJson() => {
    'c': channelKey,
    'n': channelName,
    't': title,
    's': start.millisecondsSinceEpoch,
    'e': end.millisecondsSinceEpoch,
  };

  static ScheduledRecording? fromJson(Object? j) {
    if (j is! Map || j['c'] is! String || j['s'] is! int || j['e'] is! int) {
      return null;
    }
    return ScheduledRecording(
      channelKey: j['c'] as String,
      channelName: j['n'] as String? ?? '',
      title: j['t'] as String? ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
      end: DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
    );
  }
}

/// Qualità delle registrazioni: si sceglie la versione del canale più
/// leggera che la rispetta (variante HLS o flusso 4K/FHD/HD/SD della
/// lista), senza ricodificare. Le stime di spazio sono indicative.
enum RecordQuality {
  best('Massima', 'La qualità migliore disponibile', null, null, 3.5),
  full('Alta · fino a 1080p', 'Come in TV, ma senza il 4K', 1080, 8000000, 2.7),
  medium(
    'Media · fino a 720p',
    'Buona su TV e PC, metà dello spazio',
    720,
    4000000,
    1.6,
  ),
  low(
    'Risparmio · fino a 480p',
    'Per tenerne tante o vederle sul telefono',
    480,
    2000000,
    0.9,
  );

  const RecordQuality(
    this.label,
    this.detail,
    this.maxHeight,
    this.maxBandwidth,
    this.gbPerHour,
  );
  final String label;
  final String detail;
  final int? maxHeight;
  final int? maxBandwidth;

  /// Spazio indicativo per un'ora (GB).
  final double gbPerHour;

  /// Qualità dei flussi della lista ammesse (le liste dicono 4K/FHD/HD/SD).
  int get maxRank => switch (this) {
    best => Quality.uhd4k.rank,
    full => Quality.fhd.rank,
    medium => Quality.hd.rank,
    low => Quality.sd.rank,
  };

  String estimate(Duration d) {
    final gb = gbPerHour * d.inMinutes / 60;
    return gb < 1
        ? 'circa ${(gb * 1024).round()} MB'
        : 'circa ${gb.toStringAsFixed(1)} GB';
  }
}

/// Cosa fare quando le registrazioni arrivano al limite di spazio.
enum WhenFull {
  stop('Ferma la registrazione'),
  deleteOldest('Cancella le più vecchie');

  const WhenFull(this.label);
  final String label;
}

/// Una registrazione programmata in corso.
class _Active {
  _Active(this.schedule, this.recorder);
  final ScheduledRecording schedule;
  final StreamRecorder recorder;
}

/// Registrazioni: istantanee (del canale che si guarda) e programmate dalla
/// guida. Il flusso si scarica così com'è, senza ricodificarlo
/// ([StreamRecorder]): `.ts` per i flussi MPEG-TS e HLS classici, `.mp4`
/// per gli HLS fMP4.
///
/// Partono solo con l'app aperta e usano una connessione in più verso il
/// fornitore (alcuni abbonamenti ne permettono una sola).
class RecordingService extends ChangeNotifier {
  RecordingService._();
  static final instance = RecordingService._();

  static const before = Duration(minutes: 1);
  static const after = Duration(minutes: 3);
  static const _file = 'recordings.json';

  static const _channel = MethodChannel('vista/device');
  static const _window = MethodChannel('vista/window');

  /// Sotto questo spazio libero sul disco non si registra.
  static const minFree = 1536 * 1024 * 1024;

  final _scheduled = <ScheduledRecording>[];
  final _active = <_Active>[];

  /// Registrazioni istantanee (dal player), controllate anche loro.
  final _instant = <StreamRecorder>[];

  RecordQuality _quality = RecordQuality.medium;
  int _limitGb = 20;
  WhenFull _whenFull = WhenFull.stop;

  /// Ultimo avviso da mostrare (spazio finito…), letto e azzerato da chi lo
  /// mostra.
  String? _warning;

  RecordQuality get quality => _quality;

  /// Spazio massimo per le registrazioni (GB); 0 = nessun limite.
  int get limitGb => _limitGb;
  WhenFull get whenFull => _whenFull;

  void setQuality(RecordQuality q) {
    _quality = q;
    unawaited(_save());
    notifyListeners();
  }

  void setLimit(int gb) {
    _limitGb = gb;
    unawaited(_save());
    notifyListeners();
  }

  void setWhenFull(WhenFull w) {
    _whenFull = w;
    unawaited(_save());
    notifyListeners();
  }

  String? takeWarning() {
    final w = _warning;
    _warning = null;
    return w;
  }

  /// Byte liberi sul disco delle registrazioni (`null` se non si sa).
  Future<int?> freeSpace() async {
    final path = (await folder()).path;
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<int>('freeSpace', {'path': path});
      }
      if (Platform.isWindows) {
        return await _window.invokeMethod<int>('freeSpace', path);
      }
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return null;
  }

  /// Byte occupati dalle registrazioni salvate.
  Future<int> usedSpace() async {
    var total = 0;
    for (final f in await files()) {
      try {
        total += await f.length();
      } on FileSystemException {
        // Sparito nel frattempo.
      }
    }
    return total;
  }

  /// Il flusso del canale da registrare: il migliore che rispetta la
  /// qualità scelta (se nessuno la rispetta, il più leggero).
  ChannelStream? pickStream(List<ChannelStream> streams) {
    if (streams.isEmpty) return null;
    final ok = streams
        .where(
          (s) =>
              s.quality == Quality.auto || s.quality.rank <= _quality.maxRank,
        )
        .toList();
    if (ok.isNotEmpty) return ok.first; // già ordinati dal migliore
    return streams.last;
  }

  List<ScheduledRecording> get scheduled => List.unmodifiable(_scheduled);

  /// Programmate in corso adesso.
  List<ScheduledRecording> get running => [for (final a in _active) a.schedule];

  bool isScheduled(String channelKey, DateTime start) =>
      _scheduled.any((s) => s.channelKey == channelKey && s.start == start) ||
      _active.any(
        (a) => a.schedule.channelKey == channelKey && a.schedule.start == start,
      );

  /// Cartella delle registrazioni: Documenti/Vista/Registrazioni su
  /// Windows, la cartella dell'app sulla memoria su Android.
  Future<Directory> folder() async {
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
        : Directory(
            '${(await getApplicationDocumentsDirectory()).path}'
            '${Platform.pathSeparator}Vista',
          );
    final d = Directory('${base.path}${Platform.pathSeparator}Registrazioni');
    await d.create(recursive: true);
    return d;
  }

  /// Registrazioni salvate, la più recente per prima.
  Future<List<File>> files() async {
    final d = await folder();
    final list = [
      await for (final e in d.list())
        if (e is File &&
            (e.path.endsWith('.ts') ||
                e.path.endsWith('.mp4') ||
                e.path.endsWith('.mkv')))
          e,
    ];
    final stats = {for (final f in list) f.path: await f.stat()};
    list.sort(
      (a, b) => stats[b.path]!.modified.compareTo(stats[a.path]!.modified),
    );
    return list;
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_file');
  }

  Future<void> load() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      // Formato vecchio: solo l'elenco delle programmate.
      final list = j is List ? j : (j as Map)['scheduled'] as List? ?? const [];
      if (j is Map) {
        _quality =
            RecordQuality.values
                .where((q) => q.name == j['quality'])
                .firstOrNull ??
            RecordQuality.medium;
        _limitGb = j['limitGb'] as int? ?? 20;
        _whenFull =
            WhenFull.values.where((w) => w.name == j['whenFull']).firstOrNull ??
            WhenFull.stop;
      }
      _scheduled
        ..clear()
        ..addAll([
          for (final x in list)
            if (ScheduledRecording.fromJson(x) case final s?)
              if (s.recordTo.isAfter(DateTime.now())) s,
        ]);
      notifyListeners();
    } catch (_) {
      // File rovinato: nessuna programmata.
    }
  }

  Future<void> _save() async {
    try {
      await (await _settingsFile()).writeAsString(
        jsonEncode({
          'scheduled': [for (final s in _scheduled) s.toJson()],
          'quality': _quality.name,
          'limitGb': _limitGb,
          'whenFull': _whenFull.name,
        }),
      );
    } catch (_) {
      // Disco o cartella non disponibili: riproverà al prossimo cambiamento.
    }
  }

  void schedule(ScheduledRecording s) {
    if (isScheduled(s.channelKey, s.start)) return;
    _scheduled
      ..add(s)
      ..sort((a, b) => a.start.compareTo(b.start));
    unawaited(_save());
    notifyListeners();
  }

  /// Annulla una programmata (o ferma quella in corso).
  Future<void> cancel(ScheduledRecording s) async {
    _scheduled.removeWhere(s.same);
    for (final a in [..._active]) {
      if (a.schedule.same(s)) await _stop(a);
    }
    unawaited(_save());
    notifyListeners();
  }

  /// Ogni 20 s: avvia le programmate che devono partire e ferma quelle
  /// finite. [channels] e [headersFor] servono a trovare il flusso.
  Future<void> tick(
    List<Channel> channels,
    Map<String, String>? Function(String url) headersFor,
  ) async {
    final now = DateTime.now();
    for (final a in [..._active]) {
      if (!now.isBefore(a.schedule.recordTo)) {
        await _stop(a);
      } else if (!a.recorder.isRunning) {
        // Il flusso si è fermato prima della fine: si tiene quello che c'è.
        _active.remove(a);
        _warning =
            'Registrazione di ${a.schedule.title} interrotta: il flusso si è '
            'fermato. Quello registrato è salvato.';
      }
    }
    _instant.removeWhere((r) => !r.isRunning);
    await _checkSpace();
    for (final s in [..._scheduled]) {
      if (now.isBefore(s.recordFrom)) continue;
      _scheduled.remove(s);
      if (!now.isBefore(s.recordTo)) continue; // già finito
      final c = channels.where((c) => c.key == s.channelKey).firstOrNull;
      final stream = c == null ? null : pickStream(c.streams);
      if (stream == null) continue;
      // Prima di partire: c'è spazio per tutto il programma?
      final need =
          (_quality.gbPerHour *
                  s.recordTo.difference(now).inMinutes /
                  60 *
                  1024 *
                  1024 *
                  1024)
              .round();
      final free = await freeSpace();
      if (free != null && free - need < minFree) {
        _warning =
            'Registrazione di ${s.title} saltata: sul disco non c\'è spazio '
            '(${s.recordTo.difference(now).inMinutes} minuti richiedono '
            '${_quality.estimate(s.recordTo.difference(now))}).';
        continue;
      }
      final url = stream.url;
      final rec = StreamRecorder(
        url,
        await _newBase(s.channelName, s.title),
        headers: headersFor(url),
        maxHeight: _quality.maxHeight,
        maxBandwidth: _quality.maxBandwidth,
      );
      try {
        await rec.start();
        _active.add(_Active(s, rec));
      } catch (_) {
        // Il flusso non risponde: la registrazione salta.
      }
    }
    unawaited(_save());
    notifyListeners();
  }

  Future<void> _stop(_Active a) async {
    _active.remove(a);
    await a.recorder.stop();
    notifyListeners();
  }

  /// Registra subito il canale che si sta guardando, nella qualità scelta.
  /// `null` se il flusso non risponde o se sul disco non c'è spazio (allora
  /// [takeWarning] dice perché).
  Future<StreamRecorder?> startInstant({
    required List<ChannelStream> streams,
    required String channelName,
    required String title,
    Map<String, String>? Function(String url)? headersFor,
  }) async {
    final stream = pickStream(streams);
    if (stream == null) return null;
    final free = await freeSpace();
    if (free != null && free < minFree * 2) {
      _warning =
          'Sul disco restano meno di 3 GB: libera spazio per registrare.';
      return null;
    }
    final rec = StreamRecorder(
      stream.url,
      await _newBase(channelName, title),
      headers: headersFor?.call(stream.url),
      maxHeight: _quality.maxHeight,
      maxBandwidth: _quality.maxBandwidth,
    );
    try {
      await rec.start();
      _instant.add(rec);
      return rec;
    } catch (_) {
      return null;
    }
  }

  /// Ogni 20 s durante le registrazioni: se il disco sta per finire si
  /// ferma tutto; oltre il limite scelto si ferma o si cancellano le più
  /// vecchie.
  Future<void> _checkSpace() async {
    final recording = _active.isNotEmpty || _instant.isNotEmpty;
    if (!recording) return;
    final free = await freeSpace();
    if (free != null && free < minFree) {
      await _stopAll();
      _warning =
          'Registrazione fermata: sul disco restano meno di 1,5 GB. '
          'Quello registrato finora è salvato.';
      return;
    }
    if (_limitGb <= 0) return;
    final limit = _limitGb * 1024 * 1024 * 1024;
    var used = await usedSpace();
    if (used <= limit) return;
    if (_whenFull == WhenFull.stop) {
      await _stopAll();
      _warning =
          'Registrazione fermata: le registrazioni hanno raggiunto il limite '
          'di $_limitGb GB (Impostazioni › Registrazioni).';
      return;
    }
    // Si cancellano le più vecchie, mai quelle in corso.
    final inUse = {
      for (final a in _active) a.recorder.file?.path,
      for (final r in _instant) r.file?.path,
    };
    final files = (await this.files()).reversed; // dalla più vecchia
    for (final f in files) {
      if (used <= limit) break;
      if (inUse.contains(f.path)) continue;
      try {
        final size = await f.length();
        await f.delete();
        used -= size;
      } on FileSystemException {
        // In uso: si passa alla successiva.
      }
    }
    if (used > limit) {
      await _stopAll();
      _warning =
          'Registrazione fermata: anche cancellando le vecchie non c\'è '
          'spazio entro il limite di $_limitGb GB.';
    }
  }

  Future<void> _stopAll() async {
    for (final a in [..._active]) {
      await _stop(a);
    }
    for (final r in [..._instant]) {
      await r.stop();
    }
    _instant.clear();
  }

  /// Percorso del nuovo file, senza estensione.
  Future<String> _newBase(String channel, String title) async {
    final d = await folder();
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
    final clean = [
      channel,
      if (title.isNotEmpty) title,
      stamp,
    ].join(' - ').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${d.path}${Platform.pathSeparator}$clean';
  }

  /// Nome leggibile di un file di registrazione.
  static String label(File f) {
    final name = f.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
