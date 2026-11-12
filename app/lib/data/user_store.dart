import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Chiavi degli elementi salvati: un prefisso per tipo.
abstract final class UserKey {
  static String channel(String key) => 'ch:$key';
  static String movie(String id) => 'mv:$id';
  static String series(String id) => 'sr:$id';
  static String episode(String id) => 'ep:$id';
}

/// Punto di visione di un film o di un episodio.
///
/// Non contiene l'indirizzo del flusso (con Xtream ha la password): al
/// momento di riprendere si ricava di nuovo dal catalogo.
class WatchProgress {
  const WatchProgress({
    required this.key,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.seriesId,
  });

  /// `mv:<id>` o `ep:<id>`.
  final String key;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final String title;
  final String subtitle;
  final String image;

  /// Per gli episodi: la serie, per riaprirne la scheda.
  final String? seriesId;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  /// Oltre il 92% (titoli di coda) un contenuto conta come visto.
  bool get finished => fraction >= 0.92;

  /// Vale la pena riprendere: iniziato da almeno 30 s e non finito.
  bool get resumable => position >= const Duration(seconds: 30) && !finished;

  Map<String, dynamic> toJson() => {
    'k': key,
    'p': position.inMilliseconds,
    'd': duration.inMilliseconds,
    'u': updatedAt.millisecondsSinceEpoch,
    't': title,
    if (subtitle.isNotEmpty) 's': subtitle,
    if (image.isNotEmpty) 'i': image,
    if (seriesId != null) 'sr': seriesId,
  };

  static WatchProgress? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = j['k'];
    if (key is! String) return null;
    int ms(Object? v) => v is int ? v : 0;
    return WatchProgress(
      key: key,
      position: Duration(milliseconds: ms(j['p'])),
      duration: Duration(milliseconds: ms(j['d'])),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ms(j['u'])),
      title: j['t'] as String? ?? '',
      subtitle: j['s'] as String? ?? '',
      image: j['i'] as String? ?? '',
      seriesId: j['sr'] as String?,
    );
  }
}

/// Preferiti, "La mia lista", avanzamento e canali recenti.
///
/// Un file JSON nella cartella privata dell'app; nessun indirizzo né
/// credenziale. È la base per la sincronizzazione con l'account.
class UserStore extends ChangeNotifier {
  static const _fileName = 'user_data.json';
  static const _maxRecent = 24;
  static const _maxProgress = 300;

  final _favorites = <String>{};
  final _progress = <String, WatchProgress>{};
  final _recent = <String>[]; // chiavi dei canali, il più recente per primo
  final _services = <int>[]; // servizi di streaming scelti (id TMDB)
  final _saved = <String, SavedTitle>{}; // titoli TMDB in "La mia lista"
  PictureFormat _picture = PictureFormat.fit;
  AutoRefresh _autoRefresh = AutoRefresh.day;
  final _softwareDecode = <String>{}; // canali con decodifica software
  final _reminders = <Reminder>[];
  bool _startOnLastChannel = false;
  Timer? _saveTimer;

  /// Formato dell'immagine nei player (vale per tutti i canali e i titoli).
  PictureFormat get picture => _picture;

  void setPicture(PictureFormat p) {
    if (p == _picture) return;
    _picture = p;
    _changed();
  }

  /// Promemoria dei programmi, il più vicino per primo.
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  bool hasReminder(String channelKey, DateTime start) =>
      _reminders.any((r) => r.channelKey == channelKey && r.start == start);

  void addReminder(Reminder r) {
    if (hasReminder(r.channelKey, r.start)) return;
    _reminders
      ..add(r)
      ..sort((a, b) => a.start.compareTo(b.start));
    _changed();
  }

  void removeReminder(String channelKey, DateTime start) {
    _reminders.removeWhere(
      (r) => r.channelKey == channelKey && r.start == start,
    );
    _changed();
  }

  /// I promemoria dei programmi che iniziano entro [ahead]: li toglie
  /// dall'elenco e li restituisce (da mostrare).
  List<Reminder> takeDue({Duration ahead = const Duration(minutes: 1)}) {
    final limit = DateTime.now().add(ahead);
    final due = [
      for (final r in _reminders)
        if (!r.start.isAfter(limit)) r,
    ];
    if (due.isEmpty) return const [];
    _reminders.removeWhere(due.contains);
    _changed();
    return due;
  }

  /// Il canale va decodificato in software (se in hardware scatta).
  bool softwareDecode(String channelKey) =>
      _softwareDecode.contains(channelKey);

  void setSoftwareDecode(String channelKey, bool on) {
    on ? _softwareDecode.add(channelKey) : _softwareDecode.remove(channelKey);
    _changed();
  }

  /// Ogni quanto riscaricare le liste da sole.
  AutoRefresh get autoRefresh => _autoRefresh;

  void setAutoRefresh(AutoRefresh v) {
    if (v == _autoRefresh) return;
    _autoRefresh = v;
    _changed();
  }

  /// All'avvio dell'app si riapre l'ultimo canale guardato.
  bool get startOnLastChannel => _startOnLastChannel;

  void setStartOnLastChannel(bool on) {
    if (on == _startOnLastChannel) return;
    _startOnLastChannel = on;
    _changed();
  }

  /// I servizi di streaming dell'utente (id dei provider TMDB/JustWatch).
  List<int> get services => List.unmodifiable(_services);

  void setServices(Iterable<int> ids) {
    _services
      ..clear()
      ..addAll(ids);
    _changed();
  }

  /// Dati per mostrare un titolo TMDB salvato in "La mia lista".
  SavedTitle? savedTitle(String key) => _saved[key];

  /// Aggiunge o toglie un titolo TMDB da "La mia lista".
  void toggleSaved(SavedTitle t) {
    if (_favorites.remove(t.key)) {
      _saved.remove(t.key);
    } else {
      _favorites.add(t.key);
      _saved[t.key] = t;
    }
    _changed();
  }

  /// Canali, film e serie preferiti (per film e serie è "La mia lista").
  Set<String> get favorites => Set.unmodifiable(_favorites);

  /// Chiavi dei canali visti di recente.
  List<String> get recentChannels => List.unmodifiable(_recent);

  bool isFavorite(String key) => _favorites.contains(key);

  WatchProgress? progressOf(String key) => _progress[key];

  /// Da riprendere, il più recente per primo; per le serie solo l'ultimo
  /// episodio guardato.
  List<WatchProgress> get continueWatching {
    final items = _progress.values.where((p) => p.resumable).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final seenSeries = <String>{};
    return [
      for (final p in items)
        if (p.seriesId == null || seenSeries.add(p.seriesId!)) p,
    ];
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      _read(j);
      notifyListeners();
    } on FormatException {
      // File rovinato: si riparte da zero piuttosto che bloccare l'app.
    } on FileSystemException {
      // Idem.
    }
  }

  /// Tutti i dati dell'utente (per il file e per il backup).
  Map<String, dynamic> toJson() => {
    'v': 1,
    'fav': _favorites.toList(),
    'recent': _recent,
    'services': _services,
    'saved': [for (final t in _saved.values) t.toJson()],
    'progress': [for (final p in _progress.values) p.toJson()],
    'prefs': {
      'picture': _picture.name,
      'startLast': _startOnLastChannel,
      'autoRefresh': _autoRefresh.name,
      'swdec': _softwareDecode.toList(),
    },
    'reminders': [for (final r in _reminders) r.toJson()],
  };

  /// Sostituisce tutti i dati con quelli di un backup e li salva.
  Future<void> restore(Map<String, dynamic> j) async {
    _read(j);
    notifyListeners();
    await flush();
  }

  void _read(Map<dynamic, dynamic> j) {
    {
      _favorites
        ..clear()
        ..addAll([
          for (final x in (j['fav'] as List? ?? const []))
            if (x is String) x,
        ]);
      _recent
        ..clear()
        ..addAll([
          for (final x in (j['recent'] as List? ?? const []))
            if (x is String) x,
        ]);
      _services
        ..clear()
        ..addAll([
          for (final x in (j['services'] as List? ?? const []))
            if (x is int) x,
        ]);
      _saved.clear();
      for (final x in (j['saved'] as List? ?? const [])) {
        final t = SavedTitle.fromJson(x);
        if (t != null) _saved[t.key] = t;
      }
      _progress.clear();
      for (final x in (j['progress'] as List? ?? const [])) {
        final p = WatchProgress.fromJson(x);
        if (p != null) _progress[p.key] = p;
      }
      final prefs = j['prefs'];
      if (prefs is Map) {
        _picture =
            PictureFormat.values
                .where((p) => p.name == prefs['picture'])
                .firstOrNull ??
            PictureFormat.fit;
        _startOnLastChannel = prefs['startLast'] == true;
        _autoRefresh =
            AutoRefresh.values
                .where((a) => a.name == prefs['autoRefresh'])
                .firstOrNull ??
            AutoRefresh.day;
        _reminders
          ..clear()
          ..addAll([
            for (final x in j['reminders'] as List? ?? const [])
              if (Reminder.fromJson(x) case final r?)
                // Quelli già passati da più di 10 minuti non servono più.
                if (DateTime.now().difference(r.start) <
                    const Duration(minutes: 10))
                  r,
          ]);
        _softwareDecode
          ..clear()
          ..addAll([
            for (final k in prefs['swdec'] as List? ?? const [])
              if (k is String) k,
          ]);
      }
    }
  }

  void toggleFavorite(String key) {
    _favorites.contains(key) ? _favorites.remove(key) : _favorites.add(key);
    _changed();
  }

  void channelWatched(String channelKey) {
    _recent
      ..remove(channelKey)
      ..insert(0, channelKey);
    if (_recent.length > _maxRecent) {
      _recent.removeRange(_maxRecent, _recent.length);
    }
    _changed();
  }

  void saveProgress(WatchProgress p) {
    if (p.duration <= Duration.zero) return;
    _progress[p.key] = p;
    if (_progress.length > _maxProgress) {
      final oldest = _progress.values.toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final o in oldest.take(_progress.length - _maxProgress)) {
        _progress.remove(o.key);
      }
    }
    _changed();
  }

  void clearProgress(String key) {
    if (_progress.remove(key) != null) _changed();
  }

  void clearRecent() {
    _recent.clear();
    _changed();
  }

  void _changed() {
    notifyListeners();
    // Durante la visione l'avanzamento arriva spesso: si scrive al massimo
    // ogni 2 secondi.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final data = jsonEncode(toJson());
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
    } on FileSystemException catch (e) {
      debugPrint('Vista: salvataggio dati utente non riuscito: ${e.message}');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// Un promemoria: avvisa quando il programma sta per iniziare.
class Reminder {
  const Reminder({
    required this.channelKey,
    required this.channelName,
    required this.title,
    required this.start,
  });

  final String channelKey;
  final String channelName;
  final String title;
  final DateTime start;

  Map<String, dynamic> toJson() => {
    'c': channelKey,
    'n': channelName,
    't': title,
    's': start.millisecondsSinceEpoch,
  };

  static Reminder? fromJson(Object? j) {
    if (j is! Map || j['c'] is! String || j['s'] is! int) return null;
    return Reminder(
      channelKey: j['c'] as String,
      channelName: j['n'] as String? ?? '',
      title: j['t'] as String? ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
    );
  }
}

/// Ogni quanto riscaricare liste e account da soli.
enum AutoRefresh {
  off('Mai', null),
  start('A ogni avvio', Duration.zero),
  sixHours('Ogni 6 ore', Duration(hours: 6)),
  halfDay('Ogni 12 ore', Duration(hours: 12)),
  day('Ogni giorno', Duration(hours: 24));

  const AutoRefresh(this.label, this.maxAge);
  final String label;

  /// Età oltre la quale una lista si riscarica (`null` = mai).
  final Duration? maxAge;
}

/// Come riempire lo schermo con il video.
enum PictureFormat {
  fit('Adatta', 'Immagine intera, con bande nere se serve'),
  zoom('Zoom', 'Riempie lo schermo tagliando i bordi'),
  stretch('Allarga', 'Riempie lo schermo deformando l\'immagine'),
  wide('16:9', 'Forza il formato panoramico'),
  classic('4:3', 'Forza il formato tradizionale');

  const PictureFormat(this.label, this.detail);
  final String label;
  final String detail;
}

/// Un titolo TMDB salvato in "La mia lista" (quanto basta per mostrarlo).
class SavedTitle {
  const SavedTitle({
    required this.key,
    required this.title,
    this.poster = '',
    this.year,
  });

  /// `tm:movie:603` / `tm:tv:5920`.
  final String key;
  final String title;
  final String poster;
  final int? year;

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    if (poster.isNotEmpty) 'p': poster,
    if (year != null) 'y': year,
  };

  static SavedTitle? fromJson(Object? j) {
    if (j is! Map || j['k'] is! String) return null;
    return SavedTitle(
      key: j['k'] as String,
      title: j['t'] as String? ?? '',
      poster: j['p'] as String? ?? '',
      year: j['y'] as int?,
    );
  }
}
