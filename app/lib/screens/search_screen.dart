import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/content_row.dart';
import '../widgets/epg_guide.dart' show hhmm;
import '../widgets/poster_card.dart';
import '../widgets/tmdb_row.dart';
import '../widgets/tv_text_field.dart';
import 'home_screen.dart' show toggleMyList;
import 'shell.dart';

/// Testo per il confronto: minuscole, senza accenti né punteggiatura.
const _accented = 'àáâäãåèéêëìíîïòóôöõùúûüçñ';
const _plain = 'aaaaaaeeeeiiiiooooouuuucn';

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if ((r >= 0x61 && r <= 0x7a) || (r >= 0x30 && r <= 0x39)) {
      b.writeCharCode(r);
    } else {
      final i = r < 0xc0 ? -1 : _accented.indexOf(String.fromCharCode(r));
      b.write(i >= 0 ? _plain[i] : ' ');
    }
  }
  return b.toString();
}

bool _matches(String folded, List<String> tokens) =>
    tokens.every(folded.contains);

/// Ricerca unica: canali, programmi in onda o in arrivo, film e serie.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _q = '';

  // Titoli già normalizzati, ricalcolati solo al cambio di catalogo.
  Catalog? _memoFor;
  List<String> _channelText = const [];
  List<String> _movieText = const [];
  List<String> _seriesText = const [];

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
    _channelText = [for (final ch in c.live.channels) _fold(ch.name)];
    _movieText = [for (final m in c.movies) _fold(m.title)];
    _seriesText = [for (final s in c.series) _fold(s.title)];
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted && _query.text.trim() != _q) {
          setState(() => _q = _query.text.trim());
        }
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(g, layout.compact ? 8 : 26, g, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cerca',
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: TvTextField(
                      controller: _query,
                      autofocus: true,
                      editOnFocus: !Device.isTv,
                      hint: 'Canali, programmi, film, serie…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([
            app.store.library,
            app.user,
            app.epg.guide,
          ]),
          builder: (context, _) => _results(context, app, layout),
        ),
        SliverToBoxAdapter(child: SizedBox(height: layout.compact ? 110 : 32)),
      ],
    );
  }

  Widget _results(BuildContext context, AppScope app, VistaLayout layout) {
    final lib = app.library;
    final tokens = _fold(_q).split(' ').where((s) => s.isNotEmpty).toList();
    if (lib == null || tokens.isEmpty || _q.length < 2) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.manage_search_rounded,
          title: 'Cosa vuoi guardare?',
          message:
              'Cerca tra i canali, i programmi della guida, i film e le serie.',
        ),
      );
    }
    final c = lib.catalog;
    _memo(c);
    final user = app.user;
    final guide = app.epg.guide.value;
    final now = DateTime.now();

    final channels = [
      for (var i = 0; i < c.live.channels.length; i++)
        if (!c.live.channels[i].hidden && _matches(_channelText[i], tokens))
          c.live.channels[i],
    ].take(40).toList();

    // Programmi: in onda o nelle prossime 24 ore, il più vicino per primo.
    final programmes = <(Channel, EpgProgramme)>[];
    if (!guide.isEmpty) {
      final until = now.add(const Duration(hours: 24));
      for (final ch in c.live.channels) {
        if (ch.hidden) continue;
        for (final p in guide.forChannel(ch, now: now)) {
          if (p.stop.isBefore(now) || p.start.isAfter(until)) continue;
          if (_matches(_fold(p.title), tokens)) programmes.add((ch, p));
        }
      }
      programmes.sort((a, b) => a.$2.start.compareTo(b.$2.start));
    }
    final movies = [
      for (var i = 0; i < c.movies.length; i++)
        if (_matches(_movieText[i], tokens)) c.movies[i],
    ].take(60).toList();
    final series = [
      for (var i = 0; i < c.series.length; i++)
        if (_matches(_seriesText[i], tokens)) c.series[i],
    ].take(60).toList();

    final online = app.tmdb.ready
        ? TmdbRow(
            key: ValueKey('tmdb-search-$_q'),
            title: 'Sui servizi di streaming',
            load: () async => (await app.tmdb.search(_q)).results,
          )
        : null;
    if (channels.isEmpty &&
        programmes.isEmpty &&
        movies.isEmpty &&
        series.isEmpty &&
        online == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nessun risultato per "$_q"',
          message: 'Prova con un\'altra parola.',
        ),
      );
    }

    final pw = layout.posterWidth;
    final posterH = pw * 1.5 + PosterCard.textHeight;
    final ww = layout.wideCardWidth;
    final wideH = ww * 9 / 16 + WideCard.textHeight;
    final allChannels = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];

    return SliverList.list(
      children: [
        if (channels.isNotEmpty)
          ContentRow(
            title: 'Canali  ·  ${channels.length}',
            itemCount: channels.length,
            itemWidth: ww,
            itemHeight: wideH,
            itemBuilder: (context, i) {
              final ch = channels[i];
              final p = guide.nowOn(ch, now: now);
              return WideCard(
                title: ch.name,
                subtitle: p?.title ?? ch.group,
                center: ChannelLogo(channel: ch, size: 64),
                progress: p?.progressAt(now),
                overlay: const Positioned(top: 8, left: 8, child: LiveBadge()),
                onTap: () => Nav.playChannel(context, allChannels, ch),
              );
            },
          ),
        if (programmes.isNotEmpty)
          ContentRow(
            title: 'Nella guida TV  ·  ${programmes.length}',
            itemCount: programmes.length.clamp(0, 40),
            itemWidth: ww,
            itemHeight: wideH,
            itemBuilder: (context, i) {
              final (ch, p) = programmes[i];
              final live = p.isOnAt(now);
              return WideCard(
                title: p.title,
                subtitle:
                    '${ch.name} · ${live ? 'ora' : _day(p.start, now)} ${hhmm(p.start)}',
                center: ChannelLogo(channel: ch, size: 56),
                progress: live ? p.progressAt(now) : null,
                overlay: live
                    ? const Positioned(top: 8, left: 8, child: LiveBadge())
                    : null,
                onTap: () => Nav.playChannel(context, allChannels, ch),
              );
            },
          ),
        if (movies.isNotEmpty)
          ContentRow(
            title: 'Film  ·  ${movies.length}',
            itemCount: movies.length,
            itemWidth: pw,
            itemHeight: posterH,
            itemBuilder: (context, i) {
              final m = movies[i];
              final key = UserKey.movie(m.id);
              return PosterCard(
                title: m.title,
                image: m.poster,
                caption: metaLine([if (m.year != null) '${m.year}', m.group]),
                progress: user.progressOf(key)?.fraction,
                favorite: user.isFavorite(key),
                onTap: () => Nav.openMovie(context, m),
                onLongPress: () => toggleMyList(context, key, m.title),
              );
            },
          ),
        if (series.isNotEmpty)
          ContentRow(
            title: 'Serie TV  ·  ${series.length}',
            itemCount: series.length,
            itemWidth: pw,
            itemHeight: posterH,
            itemBuilder: (context, i) {
              final s = series[i];
              final key = UserKey.series(s.id);
              return PosterCard(
                title: s.title,
                image: s.poster,
                caption: metaLine([if (s.year != null) '${s.year}', s.group]),
                favorite: user.isFavorite(key),
                onTap: () => Nav.openSeries(context, s),
                onLongPress: () => toggleMyList(context, key, s.title),
              );
            },
          ),
        ?online,
      ],
    );
  }

  static String _day(DateTime t, DateTime now) {
    final l = t.toLocal();
    final n = now.toLocal();
    if (l.year == n.year && l.month == n.month && l.day == n.day) return 'oggi';
    final tomorrow = n.add(const Duration(days: 1));
    if (l.year == tomorrow.year &&
        l.month == tomorrow.month &&
        l.day == tomorrow.day) {
      return 'domani';
    }
    return '${l.day}/${l.month}';
  }
}
