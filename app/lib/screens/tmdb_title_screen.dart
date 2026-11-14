import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/service_launcher.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/tmdb_row.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_detail.dart';
import '../widgets/vista_row.dart';

/// Scheda di un film o di una serie dal catalogo dei servizi (TMDB): dati
/// completi, "Disponibile su" con i servizi (e la lista IPTV, se lo ha),
/// trailer, IMDb, cast e, per le serie, stagioni ed episodi.
class TmdbTitleScreen extends StatefulWidget {
  const TmdbTitleScreen({super.key, required this.title, this.heroTag});
  final TmdbTitle title;

  /// La locandina da cui si è aperta: atterra nel backdrop.
  final Object? heroTag;

  @override
  State<TmdbTitleScreen> createState() => _TmdbTitleScreenState();
}

class _TmdbTitleScreenState extends State<TmdbTitleScreen> {
  TmdbDetails? _details;
  String? _error;
  int? _season;
  Future<List<TmdbEpisode>>? _episodes;

  TmdbTitle get _t => _details?.title ?? widget.title;

  @override
  void initState() {
    super.initState();
    _load();
  }

  final _primaryFocus = FocusNode(debugLabel: 'azione principale');
  final _listFocus = FocusNode(debugLabel: 'la mia lista');

  @override
  void dispose() {
    _primaryFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await AppScope.of(context).tmdb
          .details(widget.title.type, widget.title.id);
      if (!mounted) return;
      setState(() {
        _details = d;
        if (d.seasons.isNotEmpty) _pickSeason(d.seasons.first.number);
      });
      // Durante il caricamento il focus era su "La mia lista" (l'unico
      // pulsante): ora passa all'azione principale, se c'è.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _listFocus.hasFocus && _primaryFocus.context != null) {
          _primaryFocus.requestFocus();
        }
      });
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Dettagli non disponibili.');
    }
  }

  void _pickSeason(int n) {
    _season = n;
    _episodes = AppScope.of(context).tmdb.season(_t.id, n);
  }

  /// Il titolo nella lista IPTV dell'utente, se c'è.
  IptvOffer? _iptv(BuildContext context) {
    final app = AppScope.of(context);
    final lib = app.library;
    if (lib == null) return null;
    if (_t.type == MediaType.movie) {
      final m = app.tmdb.localMovie(lib.catalog, _t);
      if (m == null) return null;
      return IptvOffer(
        label: 'Guarda ora · ${m.group}',
        onTap: () => Nav.playMovie(context, m),
      );
    }
    final s = app.tmdb.localSeries(lib.catalog, _t);
    if (s == null) return null;
    return IptvOffer(
      label: 'Episodi · ${s.group}',
      onTap: () => Nav.openSeries(context, s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: DetailTint(
        image: _t.backdrop.isNotEmpty ? _t.backdrop : _t.poster,
        child: ListenableBuilder(
          listenable: app.user,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final d = _details;
    final iptv = _iptv(context);
    final user = AppScope.of(context).user;
    final isTv = _t.type == MediaType.tv;
    final meta = metaLine([
      if (_t.year != null) '${_t.year}',
      if (d != null && d.seasons.isNotEmpty)
        d.seasons.length == 1 ? '1 stagione' : '${d.seasons.length} stagioni',
      if (d != null && d.genres.isNotEmpty) d.genres.take(3).join(', '),
      if (d?.runtime != null)
        isTv
            ? '${formatDuration(d!.runtime!)} a episodio'
            : formatDuration(d!.runtime!),
      if (_t.rating > 0)
        '★ ${_t.rating.toStringAsFixed(1).replaceAll('.', ',')} TMDB',
    ]);
    // Azione principale: la lista IPTV, altrimenti il primo dei servizi
    // dell'utente su cui è incluso, altrimenti il primo disponibile.
    final mine = user.services.toSet();
    final offers =
        d?.availability.distinct ?? const <(WatchProvider, OfferKind)>[];
    final best =
        offers.where((o) => mine.contains(o.$1.id)).firstOrNull ??
        offers.firstOrNull;
    final kind = isTv ? 'Serie' : 'Film';

    return VistaRowsPage(
      rows: [
        DetailHeader(
          key: const ValueKey('head'),
          id: '${_t.type.name}:${_t.id}',
          kicker: iptv != null
              ? '$kind · Lista IPTV'
              : (best != null ? '$kind · ${best.$1.name}' : kind),
          title: _t.title,
          subtitle: _t.originalTitle.isNotEmpty && _t.originalTitle != _t.title
              ? _t.originalTitle
              : '',
          meta: meta,
          plot: _t.overview,
          notes: [
            if (d != null && d.tagline.isNotEmpty) '“${d.tagline}”',
            if (d != null && d.directors.isNotEmpty)
              '${isTv ? 'Ideata da' : 'Regia'}  ${d.directors.join(', ')}',
          ],
          backdrop: _t.backdrop,
          poster: _t.poster,
          heroTag: widget.heroTag,
          actions: _actions(context, d, iptv, best),
          status: _error != null
              ? DetailStatus.error(_error!, onRetry: _load)
              : (d == null ? const DetailStatus.loading() : null),
          availability: d == null
              ? null
              : AvailabilitySection(
                  title: _t.title,
                  availability: d.availability,
                  iptv: iptv,
                ),
        ),
        if (d != null && d.seasons.isNotEmpty) _seasonsRow(context, d),
        if (d != null && d.cast.isNotEmpty)
          CastRow(key: const ValueKey('cast'), d.cast),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    TmdbDetails? d,
    IptvOffer? iptv,
    (WatchProvider, OfferKind)? best,
  ) {
    final saved = AppScope.of(context).user.isFavorite(_t.key);
    return [
      if (iptv != null)
        VistaButton.primary(
          key: const ValueKey('iptv'),
          focusNode: _primaryFocus,
          autofocus: true,
          icon: Icons.play_arrow_rounded,
          label: 'Guarda dalla lista IPTV',
          onPressed: iptv.onTap,
        )
      else if (best != null)
        VistaButton.primary(
          key: const ValueKey('service'),
          focusNode: _primaryFocus,
          autofocus: true,
          icon: Icons.open_in_new_rounded,
          label:
              '${best.$2 == OfferKind.flatrate ? 'Guarda' : best.$2.label} su ${best.$1.name}',
          onPressed: () =>
              openService(best.$1, _t.title, fallback: d!.availability.link),
        ),
      if (d != null && d.trailerKey.isNotEmpty)
        DetailButton(
          key: const ValueKey('trailer'),
          autofocus: iptv == null && best == null,
          icon: Icons.smart_display_rounded,
          label: 'Trailer',
          onPressed: () =>
              openLink('https://www.youtube.com/watch?v=${d.trailerKey}'),
        ),
      DetailButton(
        key: const ValueKey('list'),
        focusNode: _listFocus,
        autofocus:
            iptv == null && best == null && (d?.trailerKey.isEmpty ?? true),
        icon: saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
        label: saved ? 'Nella tua lista' : 'La mia lista',
        onPressed: () => toggleSavedTitle(context, _t),
      ),
      if (d != null && d.imdbUrl.isNotEmpty)
        DetailButton(
          key: const ValueKey('imdb'),
          label: 'IMDb',
          onPressed: () => openLink(d.imdbUrl),
        ),
    ];
  }

  Widget _seasonsRow(BuildContext context, TmdbDetails d) {
    final layout = VistaLayout.of(context);
    final w = layout.wideCardWidth;
    final seasons = d.seasons;
    String name(TmdbSeason s) =>
        s.name.isEmpty ? 'Stagione ${s.number}' : s.name;
    final current = seasons.where((s) => s.number == _season).firstOrNull;
    return Column(
      key: const ValueKey('episodes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seasons.length > 1) ...[
          SeasonChips(
            labels: [for (final s in seasons) name(s)],
            selected: current == null ? 0 : seasons.indexOf(current),
            onSelected: (i) => setState(() => _pickSeason(seasons[i].number)),
          ),
          const SizedBox(height: VistaSpace.s16),
        ],
        FutureBuilder<List<TmdbEpisode>>(
          key: ValueKey('season:$_season'),
          future: _episodes,
          builder: (context, snap) {
            final title = seasons.length > 1 || current == null
                ? 'Episodi'
                : name(current);
            if (snap.connectionState != ConnectionState.done) {
              return EpisodesSkeleton(title: title);
            }
            final eps = snap.data ?? const <TmdbEpisode>[];
            if (eps.isEmpty) {
              return const DetailNote('Nessun episodio disponibile.');
            }
            return VistaRow(
              title: title,
              itemCount: eps.length,
              itemKey: (i) => ValueKey('ep:${eps[i].number}'),
              itemWidth: w,
              itemHeight: VistaWideCard.heightFor(context, w),
              itemBuilder: (context, i) {
                final e = eps[i];
                return VistaWideCard(
                  title: '${e.number}. ${e.name}',
                  meta: metaLine([
                    if (e.runtime != null) formatDuration(e.runtime!),
                    if (e.airDate.isNotEmpty) _date(e.airDate),
                  ]),
                  image: e.still,
                  restWidth: w,
                  // Si guarda dal servizio o dalla lista: qui solo i dati.
                  onTap: () {},
                );
              },
            );
          },
        ),
      ],
    );
  }

  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3
        ? '${int.tryParse(p[2]) ?? p[2]}/${int.tryParse(p[1]) ?? p[1]}/${p[0]}'
        : iso;
  }
}
