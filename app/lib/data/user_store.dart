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
  Timer? _saveTimer;

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
      notifyListeners();
    } on FormatException {
      // File rovinato: si riparte da zero piuttosto che bloccare l'app.
    } on FileSystemException {
      // Idem.
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
    final data = jsonEncode({
      'v': 1,
      'fav': _favorites.toList(),
      'recent': _recent,
      'services': _services,
      'saved': [for (final t in _saved.values) t.toJson()],
      'progress': [for (final p in _progress.values) p.toJson()],
    });
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
