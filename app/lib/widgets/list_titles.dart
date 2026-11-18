import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/tmdb_store.dart';
import '../theme.dart';

/// Titolo di un film o di una serie della lista IPTV, ripulito per lo
/// schermo: senza prefisso di lingua ("IT - "), etichette tra parentesi
/// quadre ("[1080p]"), anno tra parentesi e qualità in coda ("4K", "HD").
/// I dati restano come sono: cambia solo quello che si legge.
String cleanListTitle(String raw) {
  var s = raw;
  s = s.replaceFirst(
    RegExp(
      r'^\s*(?:\|[A-Za-z]{2,3}\||\[[A-Za-z]{2,3}\]|[A-Z]{2,3}\s*[-:|])\s*',
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  s = s.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), ' ');
  final tail = RegExp(
    r'[\s\-–|:]*\b(?:4K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|2160p|1080p|720p|ITA|SUB ?ITA)\s*$',
    caseSensitive: false,
  );
  while (tail.hasMatch(s)) {
    s = s.replaceFirst(tail, '');
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'[\s\-–|:/]+$'), '').trim();
  return s.isEmpty ? raw.trim() : s;
}

/// L'anno scritto nel titolo ("Titolo (2024)"), se la lista non lo dà a parte.
int? yearInTitle(String raw) {
  final m = RegExp(r'\(((?:19|20)\d{2})\)').firstMatch(raw);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Abbinamenti con TMDB dei titoli della lista, per mostrare titolo, trama e
/// backdrop di TMDB quando la chiave è configurata.
///
/// Si chiede un titolo solo quando la sua card viene costruita (cioè quando
/// compare a schermo), al massimo [_parallel] richieste per volta e prima le
/// più recenti. Gli abbinamenti li conserva [TmdbStore] (anche su disco);
/// qui resta solo il risultato della sessione. Chi ascolta viene avvisato a
/// gruppi, non a ogni risposta.
class ListTitles extends ChangeNotifier {
  ListTitles._();
  static final instance = ListTitles._();

  static const _parallel = 4;

  final _done = <String, TmdbTitle?>{};
  final _queued = <String>{};
  final _queue = <(String, Future<TmdbTitle?> Function())>[];
  int _running = 0;
  Object? _client;
  Timer? _notify;

  /// Il titolo TMDB di un film, o `null` (ancora in arrivo, o non trovato).
  TmdbTitle? movie(TmdbStore tmdb, Movie m) => _get(
    tmdb,
    'mv:${m.id}',
    () => tmdb.matchMovie(
      Movie(
        id: m.id,
        title: cleanListTitle(m.title),
        url: m.url,
        year: m.year ?? yearInTitle(m.title),
        tmdbId: m.tmdbId,
      ),
    ),
  );

  TmdbTitle? series(TmdbStore tmdb, Series s) => _get(
    tmdb,
    'sr:${s.id}',
    () => tmdb.matchSeries(
      Series(
        id: s.id,
        title: cleanListTitle(s.title),
        year: s.year ?? yearInTitle(s.title),
        tmdbId: s.tmdbId,
      ),
    ),
  );

  TmdbTitle? _get(
    TmdbStore tmdb,
    String key,
    Future<TmdbTitle?> Function() load,
  ) {
    if (!tmdb.ready) return null;
    // Chiave cambiata: gli abbinamenti di prima non valgono più.
    final client = tmdb.client.value;
    if (!identical(client, _client)) {
      _client = client;
      _done.clear();
      _queued.clear();
      _queue.clear();
    }
    if (_done.containsKey(key)) return _done[key];
    if (_queued.add(key)) {
      _queue.add((key, load));
      _pump();
    }
    return null;
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final (key, load) = _queue.removeLast();
      final client = _client;
      _running++;
      () async {
        TmdbTitle? t;
        try {
          t = await load();
        } catch (_) {}
        _running--;
        if (identical(client, _client)) {
          _done[key] = t;
          if (t != null) _notifySoon();
        }
        _pump();
      }();
    }
  }

  void _notifySoon() {
    if (_notify?.isActive ?? false) return;
    _notify = Timer(VistaMotion.backdropFade, notifyListeners);
  }
}

/// Nome di una categoria della lista come titolo di riga: ripulito come i
/// titoli e, se è tutto maiuscolo, con la sola iniziale maiuscola
/// ("IT: PELLICOLA 2025 [1080p]" diventa "Pellicola 2025").
String cleanGroupName(String raw) {
  final s = cleanListTitle(raw);
  if (s != s.toUpperCase() || s.length < 2) return s;
  return s[0] + s.substring(1).toLowerCase();
}

/// Il titolo da mostrare per un elemento della lista: quello di TMDB [t] se
/// c'è l'abbinamento, altrimenti quello della lista ripulito.
///
/// Se TMDB non ha il titolo italiano dà l'originale, a volte in un'altra
/// scrittura (devanagari, cirillico…): allora si tiene quello della lista.
String listTitle(String raw, TmdbTitle? t) {
  final clean = cleanListTitle(raw);
  if (t == null || t.title.trim().isEmpty) return clean;
  final latin = RegExp('[A-Za-z]');
  if (!latin.hasMatch(t.title) && latin.hasMatch(clean)) return clean;
  return t.title;
}
