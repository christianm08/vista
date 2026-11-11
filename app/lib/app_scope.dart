import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import 'data/epg_store.dart';
import 'data/source_store.dart';
import 'data/tmdb_store.dart';
import 'data/user_store.dart';
import 'screens/player_screen.dart';
import 'screens/title_screen.dart';
import 'screens/tmdb_title_screen.dart';
import 'screens/vod_player_screen.dart';

/// I servizi dell'app, raggiungibili da ogni schermata (anche dai player,
/// che stanno su altre route): fonte e catalogo, guida TV, dati dell'utente.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.epg,
    required this.user,
    required this.tmdb,
    required super.child,
  });

  final SourceStore store;
  final EpgStore epg;
  final UserStore user;
  final TmdbStore tmdb;

  static AppScope of(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope mancante');
    return s!;
  }

  /// Catalogo corrente (non nullo dopo l'importazione).
  Library? get library => store.library.value;

  @override
  bool updateShouldNotify(AppScope old) =>
      store != old.store ||
      epg != old.epg ||
      user != old.user ||
      tmdb != old.tmdb;
}

/// Azioni comuni: aprire una scheda, guardare un canale o un titolo.
abstract final class Nav {
  static Future<void> _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  static Future<void> openMovie(BuildContext context, Movie m) =>
      _push(context, TitleScreen.movie(m));

  static Future<void> openSeries(BuildContext context, Series s) =>
      _push(context, TitleScreen.series(s));

  /// Scheda di un titolo dal catalogo dei servizi di streaming.
  static Future<void> openTmdb(BuildContext context, TmdbTitle t) =>
      _push(context, TmdbTitleScreen(title: t));

  static Future<void> playChannel(
    BuildContext context,
    List<Channel> list,
    Channel c,
  ) {
    final app = AppScope.of(context);
    final i = list.indexOf(c);
    return _push(
      context,
      PlayerScreen(
        channels: list,
        initialIndex: i < 0 ? 0 : i,
        guide: app.epg.guide.value,
      ),
    );
  }

  static Future<void> playMovie(
    BuildContext context,
    Movie m, {
    bool fromStart = false,
  }) {
    final app = AppScope.of(context);
    final key = UserKey.movie(m.id);
    final saved = app.user.progressOf(key);
    return _push(
      context,
      VodPlayerScreen(
        items: [
          VodItem(
            key: key,
            title: m.title,
            subtitle: metaYearGroup(m.year, m.group),
            url: m.url,
            image: m.poster,
            startAt: !fromStart && saved != null && saved.resumable
                ? saved.position
                : null,
          ),
        ],
      ),
    );
  }

  /// Episodi in sequenza a partire da [start]; riprende dal punto salvato.
  static Future<void> playEpisodes(
    BuildContext context,
    Series s,
    List<Episode> episodes,
    Episode start, {
    bool fromStart = false,
  }) {
    final app = AppScope.of(context);
    final saved = app.user.progressOf(UserKey.episode(start.id));
    return _push(
      context,
      VodPlayerScreen(
        initialIndex: episodes.indexOf(start).clamp(0, episodes.length - 1),
        items: [
          for (final e in episodes)
            VodItem(
              key: UserKey.episode(e.id),
              title: s.title,
              subtitle: '${e.code} · ${e.title}',
              url: e.url,
              image: e.image.isNotEmpty
                  ? e.image
                  : (s.backdrop.isNotEmpty ? s.backdrop : s.poster),
              seriesId: s.id,
              startAt:
                  e == start && !fromStart && saved != null && saved.resumable
                  ? saved.position
                  : null,
            ),
        ],
      ),
    );
  }

  /// "Continua a guardare": riprende un film o riapre la serie all'episodio.
  static Future<void> resume(BuildContext context, WatchProgress p) async {
    final lib = AppScope.of(context).library;
    if (lib == null) return;
    if (p.key.startsWith('mv:')) {
      final id = p.key.substring(3);
      final m = lib.catalog.movies.where((x) => x.id == id).firstOrNull;
      if (m != null) return playMovie(context, m);
    } else if (p.seriesId != null) {
      final s = lib.catalog.series.where((x) => x.id == p.seriesId).firstOrNull;
      if (s != null) {
        return _push(
          context,
          TitleScreen.series(s, resumeEpisode: p.key.substring(3)),
        );
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questo titolo non è più nella fonte.')),
      );
    }
  }
}

String metaYearGroup(int? year, String group) =>
    [if (year != null) '$year', if (group.isNotEmpty) group].join(' · ');
