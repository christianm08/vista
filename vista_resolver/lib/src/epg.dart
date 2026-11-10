import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:xml/xml_events.dart';

import 'logos.dart' show logoKey;
import 'models.dart';
import 'normalize.dart';

/// Guida principale di Vista (XMLTV); in mancanza si usa quella della lista.
final defaultEpgUri = Uri.parse('https://epg.lat/files/it.xml.gz');

/// Un programma della guida.
class EpgProgramme {
  const EpgProgramme({
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.category = '',
  });

  final DateTime start;
  final DateTime stop;
  final String title;
  final String subtitle;
  final String description;
  final String category;

  Duration get duration => stop.difference(start);

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  /// Quanto è già andato in onda, da 0 a 1.
  double progressAt(DateTime t) {
    final total = duration.inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }
}

/// Contenuto di un file XMLTV: programmi per id del canale e nomi dei canali.
class EpgData {
  const EpgData({required this.programmes, required this.names});

  static const empty = EpgData(programmes: {}, names: {});

  /// id XMLTV → programmi ordinati per inizio.
  final Map<String, List<EpgProgramme>> programmes;

  /// id XMLTV → `display-name`.
  final Map<String, List<String>> names;

  int get programmeCount =>
      programmes.values.fold(0, (sum, list) => sum + list.length);

  /// Ultimo istante coperto dalla guida (per capire se è vecchia).
  DateTime? get lastStop {
    DateTime? last;
    for (final list in programmes.values) {
      if (list.isEmpty) continue;
      final s = list.last.stop;
      if (last == null || s.isAfter(last)) last = s;
    }
    return last;
  }
}

/// Chiave di abbinamento di un id XMLTV o di un `tvg-id`: senza paese, senza
/// numero del canale e senza qualità. `Rai.1.HD..101.it`, `Rai1.it@HD` e
/// `Rai1.it` → `rai1`.
String epgIdKey(String id) {
  var s = id.trim().toLowerCase();
  final at = s.indexOf('@');
  if (at >= 0) s = s.substring(0, at);
  s = s
      .replaceFirst(RegExp(r'\.[a-z]{2,3}$'), '')
      .replaceFirst(RegExp(r'\.{2,}\d+$'), '')
      .replaceAll('.', ' ');
  return logoKey(normalizeName(s).key);
}

/// Chiave di abbinamento di un nome (`display-name` o nome del canale).
String epgNameKey(String name) => logoKey(normalizeName(name).key);

/// Legge un file XMLTV a flusso (anche compresso con gzip, riconosciuto dai
/// primi byte) tenendo solo i programmi fra [from] e [to]: le guide complete
/// pesano decine di MB.
Future<EpgData> parseXmltv(
  Stream<List<int>> bytes, {
  DateTime? from,
  DateTime? to,
}) async {
  final events = (await _decompressed(bytes))
      .transform(utf8.decoder)
      .toXmlEvents()
      .normalizeEvents()
      .flatten();

  final names = <String, List<String>>{};
  final programmes = <String, List<EpgProgramme>>{};

  String? channelId;
  _Programme? cur;
  String? capture; // elemento di cui si sta leggendo il testo
  final text = StringBuffer();

  await for (final e in events) {
    if (e is XmlStartElementEvent) {
      switch (e.name) {
        case 'channel':
          channelId = e.isSelfClosing ? null : _attr(e, 'id');
        case 'display-name' when channelId != null && !e.isSelfClosing:
          capture = 'display-name';
          text.clear();
        case 'programme':
          cur = null;
          if (e.isSelfClosing) break;
          final start = parseXmltvTime(_attr(e, 'start'));
          final stop = parseXmltvTime(_attr(e, 'stop'));
          final channel = _attr(e, 'channel');
          if (start == null || channel.isEmpty) break;
          final end = stop ?? start.add(const Duration(minutes: 30));
          if ((from != null && !end.isAfter(from)) ||
              (to != null && !start.isBefore(to))) {
            break;
          }
          cur = _Programme(channel, start, end);
        case 'title' || 'sub-title' || 'desc' || 'category'
            when cur != null && !e.isSelfClosing:
          capture = e.name;
          text.clear();
      }
    } else if (capture != null && e is XmlTextEvent) {
      text.write(e.value);
    } else if (capture != null && e is XmlCDATAEvent) {
      text.write(e.value);
    } else if (e is XmlEndElementEvent) {
      final value = text.toString().trim();
      switch (e.name) {
        case 'display-name' when capture == 'display-name':
          if (value.isNotEmpty) {
            names.putIfAbsent(channelId!, () => []).add(value);
          }
        case 'title' when capture == 'title':
          cur!.title ??= value;
        case 'sub-title' when capture == 'sub-title':
          cur!.subtitle ??= value;
        case 'desc' when capture == 'desc':
          cur!.description ??= value;
        case 'category' when capture == 'category':
          cur!.category ??= value;
        case 'programme':
          final p = cur;
          if (p != null && (p.title ?? '').isNotEmpty) {
            programmes.putIfAbsent(p.channel, () => []).add(EpgProgramme(
                  start: p.start,
                  stop: p.stop,
                  title: p.title!,
                  subtitle: p.subtitle ?? '',
                  description: p.description ?? '',
                  category: p.category ?? '',
                ));
          }
          cur = null;
        case 'channel':
          channelId = null;
      }
      capture = null;
    }
  }

  for (final list in programmes.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return EpgData(programmes: programmes, names: names);
}

/// `20261110203000 +0100` → istante UTC.
DateTime? parseXmltvTime(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  var t = DateTime.utc(g(1), g(2), g(3), g(4), g(5), m.group(6) == null ? 0 : g(6));
  final tz = m.group(7);
  if (tz != null) {
    final sign = tz.startsWith('-') ? -1 : 1;
    final offset = Duration(
        hours: int.parse(tz.substring(1, 3)), minutes: int.parse(tz.substring(3)));
    t = sign > 0 ? t.subtract(offset) : t.add(offset);
  }
  return t;
}

/// Una o più guide in ordine di priorità, con l'abbinamento ai canali.
class EpgGuide {
  EpgGuide(this.sources) {
    for (final s in sources) {
      final index = <String, List<String>>{};
      void add(String key, String id) {
        if (key.isEmpty) return;
        final ids = index.putIfAbsent(key, () => []);
        if (!ids.contains(id)) ids.add(id);
      }

      for (final id in {...s.programmes.keys, ...s.names.keys}) {
        index.putIfAbsent('#${id.toLowerCase()}', () => [id]);
        add(epgIdKey(id), id);
        for (final n in s.names[id] ?? const <String>[]) {
          add(epgNameKey(n), id);
        }
      }
      _indexes.add(index);
    }
  }

  static final empty = EpgGuide(const []);

  final List<EpgData> sources;
  final _indexes = <Map<String, List<String>>>[];
  final _cache = <String, List<EpgProgramme>>{};

  bool get isEmpty => sources.every((s) => s.programmes.isEmpty);

  /// Programmi di un canale: prima per `tvg-id` esatto, poi per `tvg-id`
  /// semplificato, infine per nome. Fra più candidati vince la prima guida
  /// che ha programmi in onda o futuri rispetto a [now].
  List<EpgProgramme> forChannel(Channel c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return _cache.putIfAbsent(c.key, () => _lookup(c, t));
  }

  List<EpgProgramme> _lookup(Channel c, DateTime now) {
    final keys = [
      if (c.tvgId.isNotEmpty) '#${c.tvgId.toLowerCase()}',
      if (c.tvgId.isNotEmpty) epgIdKey(c.tvgId),
      epgNameKey(c.key),
      if (c.renamed) epgNameKey(c.name),
    ];
    List<EpgProgramme>? stale;
    for (var i = 0; i < sources.length; i++) {
      for (final k in keys) {
        for (final id in _indexes[i][k] ?? const <String>[]) {
          final list = sources[i].programmes[id];
          if (list == null || list.isEmpty) continue;
          if (list.last.stop.isAfter(now)) return list;
          stale ??= list;
        }
      }
    }
    return stale ?? const [];
  }

  /// Programma in onda e i successivi (al massimo [count] in tutto).
  List<EpgProgramme> upcoming(Channel c, {DateTime? now, int count = 3}) {
    final t = now ?? DateTime.now();
    final list = forChannel(c, now: t);
    final i = list.indexWhere((p) => p.stop.isAfter(t));
    if (i < 0) return const [];
    return list.sublist(i, (i + count).clamp(0, list.length));
  }

  EpgProgramme? nowOn(Channel c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    for (final p in upcoming(c, now: t, count: 1)) {
      if (p.isOnAt(t)) return p;
    }
    return null;
  }
}

String _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return '';
}

Future<Stream<List<int>>> _decompressed(Stream<List<int>> input) async {
  final it = StreamIterator(input);
  if (!await it.moveNext()) return const Stream.empty();
  final head = it.current;
  Stream<List<int>> all() async* {
    yield head;
    while (await it.moveNext()) {
      yield it.current;
    }
  }

  final gz = head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b;
  return gz ? all().transform(gzip.decoder) : all();
}

class _Programme {
  _Programme(this.channel, this.start, this.stop);
  final String channel;
  final DateTime start;
  final DateTime stop;
  String? title;
  String? subtitle;
  String? description;
  String? category;
}
