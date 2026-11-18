import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart' show hhmm;
import '../widgets/list_titles.dart';
import '../widgets/tmdb_row.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_focus.dart';
import '../widgets/vista_row.dart';
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
///
/// Campo in alto e risultati nelle stesse righe della Home. Su TV, accanto
/// ai risultati, una tastiera a schermo da usare col telecomando.
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
      _debounce = Timer(VistaMotion.searchDebounce, () {
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
    final tv = layout.tv;
    final top = layout.compact
        ? MediaQuery.paddingOf(context).top + VistaSpace.s8
        : (layout.safe.top > VistaSpace.s32 ? layout.safe.top : VistaSpace.s32);

    final field = TvTextField(
      controller: _query,
      autofocus: !tv,
      editOnFocus: !tv,
      hint: 'Canali, programmi, film, serie…',
      prefixIcon: const Icon(Icons.search_rounded),
      textInputAction: TextInputAction.search,
    );
    final results = ListenableBuilder(
      listenable: Listenable.merge([
        app.store.library,
        app.user,
        app.epg.guide,
      ]),
      builder: (context, _) => _results(context, app, layout),
    );

    if (tv) {
      return Padding(
        padding: EdgeInsets.only(top: top, bottom: layout.safe.bottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: g),
              child: SizedBox(
                width: _Keyboard.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Cerca', style: t.headlineSmall),
                    const SizedBox(height: VistaSpace.s16),
                    field,
                    const SizedBox(height: VistaSpace.s16),
                    _Keyboard(controller: _query),
                  ],
                ),
              ),
            ),
            Expanded(child: results),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: Text('Cerca', style: t.headlineSmall),
          ),
          const SizedBox(height: VistaSpace.s16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: VistaSize.searchField,
                ),
                child: field,
              ),
            ),
          ),
          const SizedBox(height: VistaSpace.s8),
          Expanded(child: results),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, AppScope app, VistaLayout layout) {
    final lib = app.library;
    final tokens = _fold(_q).split(' ').where((s) => s.isNotEmpty).toList();
    if (lib == null || tokens.isEmpty || _q.length < 2) {
      return const EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Cosa vuoi guardare?',
        message:
            'Cerca tra i canali, i programmi della guida, i film e le serie.',
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
        ? TmdbVistaRow(
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
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato per "$_q"',
        message: 'Prova con un\'altra parola.',
        action: 'Cancella la ricerca',
        onAction: _query.clear,
      );
    }

    final pw = layout.posterWidth;
    final posterH = VistaPosterCard.heightFor(context, pw, true);
    final ww = layout.wideCardWidth;
    final wideH = VistaWideCard.heightFor(context, ww);
    final allChannels = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];
    final shown = programmes.take(40).toList();

    Widget logo(Channel ch) =>
        ChannelLogo(channel: ch, size: VistaSize.channelLogoCard, boxed: false);

    return VistaRowsPage(
      // Nuova ricerca, pagina nuova: si riparte dalla prima riga.
      key: ValueKey(_q),
      rows: [
        if (channels.isNotEmpty)
          VistaRow(
            key: const ValueKey('channels'),
            title: 'Canali  ·  ${channels.length}',
            itemCount: channels.length,
            itemKey: (i) => ValueKey('ch:${channels[i].key}'),
            itemWidth: ww,
            itemHeight: wideH,
            itemBuilder: (context, i) {
              final ch = channels[i];
              final p = guide.nowOn(ch, now: now);
              return VistaWideCard(
                title: ch.name,
                meta: p?.title ?? cleanGroupName(ch.group),
                restWidth: ww,
                center: logo(ch),
                progress: p?.progressAt(now),
                onTap: () => Nav.playChannel(context, allChannels, ch),
              );
            },
          ),
        if (shown.isNotEmpty)
          VistaRow(
            key: const ValueKey('guide'),
            title: 'Nella guida TV  ·  ${programmes.length}',
            itemCount: shown.length,
            itemKey: (i) =>
                ValueKey('pg:${shown[i].$1.key}|${shown[i].$2.start}'),
            itemWidth: ww,
            itemHeight: wideH,
            itemBuilder: (context, i) {
              final (ch, p) = shown[i];
              final live = p.isOnAt(now);
              return VistaWideCard(
                title: p.title,
                meta:
                    '${ch.name} · ${live ? 'ora' : _day(p.start, now)} '
                    '${hhmm(p.start)}',
                restWidth: ww,
                center: logo(ch),
                progress: live ? p.progressAt(now) : null,
                overlay: live ? const VistaLabel('IN ONDA', dot: true) : null,
                onTap: () => Nav.playChannel(context, allChannels, ch),
              );
            },
          ),
        if (movies.isNotEmpty)
          VistaRow(
            key: const ValueKey('movies'),
            title: 'Film  ·  ${movies.length}',
            itemCount: movies.length,
            itemKey: (i) => ValueKey(UserKey.movie(movies[i].id)),
            itemWidth: pw,
            itemHeight: posterH,
            itemBuilder: (context, i) {
              final m = movies[i];
              final key = UserKey.movie(m.id);
              final hero = 'search|$key';
              return VistaPosterCard(
                title: cleanListTitle(m.title),
                image: m.poster,
                restWidth: pw,
                heroTag: hero,
                meta: metaLine([
                  if ((m.year ?? yearInTitle(m.title)) case final y?) '$y',
                  cleanGroupName(m.group),
                ]),
                progress: user.progressOf(key)?.fraction,
                saved: user.isFavorite(key),
                onTap: () => Nav.openMovie(context, m, hero: hero),
                onLongPress: () =>
                    toggleMyList(context, key, cleanListTitle(m.title)),
              );
            },
          ),
        if (series.isNotEmpty)
          VistaRow(
            key: const ValueKey('series'),
            title: 'Serie TV  ·  ${series.length}',
            itemCount: series.length,
            itemKey: (i) => ValueKey(UserKey.series(series[i].id)),
            itemWidth: pw,
            itemHeight: posterH,
            itemBuilder: (context, i) {
              final s = series[i];
              final key = UserKey.series(s.id);
              final hero = 'search|$key';
              return VistaPosterCard(
                title: cleanListTitle(s.title),
                image: s.poster,
                restWidth: pw,
                heroTag: hero,
                meta: metaLine([
                  if ((s.year ?? yearInTitle(s.title)) case final y?) '$y',
                  cleanGroupName(s.group),
                ]),
                saved: user.isFavorite(key),
                onTap: () => Nav.openSeries(context, s, hero: hero),
                onLongPress: () =>
                    toggleMyList(context, key, cleanListTitle(s.title)),
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

/// Tastiera a schermo per il telecomando (TV): lettere, cifre, spazio,
/// cancella e svuota. Scrive nel campo della ricerca.
class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.controller});
  final TextEditingController controller;

  static const _columns = 6;
  static const _keys = 'abcdefghijklmnopqrstuvwxyz1234567890';
  static const width =
      _columns * VistaSize.minTouch + (_columns - 1) * VistaSpace.s8;

  void _set(String text) => controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget key(
      String semantic,
      Widget child,
      VoidCallback onTap, {
      int span = 1,
      bool autofocus = false,
    }) => SizedBox(
      width: span * VistaSize.minTouch + (span - 1) * VistaSpace.s8,
      height: VistaSize.minTouch,
      child: VistaFocusable(
        kind: VistaFocusKind.flat,
        radius: VistaRadius.chip,
        fill: VistaColors.surfaceHigh,
        activeFill: VistaColors.surfaceSelected,
        autofocus: autofocus,
        semanticLabel: semantic,
        onTap: onTap,
        child: Center(child: child),
      ),
    );

    return FocusTraversalGroup(
      child: Wrap(
        // Più dell'anello di fuoco: non copre i tasti vicini.
        spacing: VistaSpace.s8,
        runSpacing: VistaSpace.s8,
        children: [
          for (final (i, k) in _keys.split('').indexed)
            key(
              k,
              Text(k, style: t.titleMedium),
              () => _set(controller.text + k),
              autofocus: i == 0,
            ),
          key(
            'Spazio',
            const Icon(Icons.space_bar_rounded),
            () => _set('${controller.text} '),
            span: 2,
          ),
          key('Cancella', const Icon(Icons.backspace_outlined), () {
            final s = controller.text;
            if (s.isNotEmpty) _set(s.substring(0, s.length - 1));
          }, span: 2),
          key(
            'Svuota',
            const Icon(Icons.clear_rounded),
            () => _set(''),
            span: 2,
          ),
        ],
      ),
    );
  }
}
