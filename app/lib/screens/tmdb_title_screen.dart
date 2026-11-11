import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/service_launcher.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';
import '../widgets/tmdb_row.dart';
import 'title_screen.dart' show TitleBackdrop;

/// Scheda di un film o di una serie dal catalogo dei servizi (TMDB): dati
/// completi, "Disponibile su:" con i servizi (e la lista IPTV, se lo ha),
/// trailer, IMDb, cast e, per le serie, stagioni ed episodi.
class TmdbTitleScreen extends StatefulWidget {
  const TmdbTitleScreen({super.key, required this.title});
  final TmdbTitle title;

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
      body: ListenableBuilder(
        listenable: app.user,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    final heroHeight = layout.compact
        ? 240.0
        : (layout.height * 0.62).clamp(300.0, 560.0);
    final d = _details;
    final iptv = _iptv(context);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: TitleBackdrop(
            backdrop: _t.backdrop,
            poster: _t.poster,
            title: _t.title,
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    g,
                    layout.compact ? 4 : 18,
                    g,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Indietro',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  g,
                  layout.compact ? 60 : heroHeight * 0.16,
                  g,
                  0,
                ),
                child: _head(context, layout, iptv),
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, 18, g, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFF9C8A)),
                        ),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                ),
              ),
            if (d != null) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, 26, g, 0),
                sliver: SliverToBoxAdapter(
                  child: AvailabilitySection(
                    title: _t.title,
                    availability: d.availability,
                    iptv: iptv,
                  ),
                ),
              ),
              if (d.cast.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 26),
                  sliver: SliverToBoxAdapter(child: CastRow(d.cast)),
                ),
              if (d.seasons.isNotEmpty) ..._seasonSlivers(context, layout, d),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ],
    );
  }

  Widget _head(BuildContext context, VistaLayout layout, IptvOffer? iptv) {
    final t = Theme.of(context).textTheme;
    final d = _details;
    final user = AppScope.of(context).user;
    final saved = user.isFavorite(_t.key);
    final meta = metaLine([
      if (_t.year != null) '${_t.year}',
      _t.type == MediaType.tv ? 'Serie TV' : 'Film',
      if (d != null && d.genres.isNotEmpty) d.genres.take(3).join(', '),
      if (d?.runtime != null)
        _t.type == MediaType.tv
            ? '${formatDuration(d!.runtime!)} a episodio'
            : formatDuration(d!.runtime!),
      if (d != null && d.seasons.isNotEmpty)
        d.seasons.length == 1 ? '1 stagione' : '${d.seasons.length} stagioni',
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

    final posterW = layout.compact ? 110.0 : (layout.tv ? 170.0 : 210.0);
    final poster = SizedBox(
      width: posterW,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VistaRadius.poster),
          child: NetImage(
            _t.poster,
            cacheWidth: 420,
            placeholder: TitlePlaceholder(_t.title),
          ),
        ),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (layout.compact ? t.headlineSmall : t.headlineMedium)
              ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
        ),
        if (_t.originalTitle.isNotEmpty && _t.originalTitle != _t.title)
          Text(
            _t.originalTitle,
            style: t.bodyMedium?.copyWith(color: VistaColors.textTertiary),
          ),
        const SizedBox(height: 8),
        Text(
          meta,
          style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (iptv != null)
              FilledButton.icon(
                autofocus: true,
                onPressed: iptv.onTap,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Guarda dalla lista IPTV'),
              )
            else if (best != null)
              FilledButton.icon(
                autofocus: true,
                onPressed: () => openService(
                  best.$1,
                  _t.title,
                  fallback: d!.availability.link,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  '${best.$2 == OfferKind.flatrate ? 'Guarda' : best.$2.label} su ${best.$1.name}',
                ),
              ),
            if (d != null && d.trailerKey.isNotEmpty)
              OutlinedButton.icon(
                autofocus: iptv == null && best == null,
                onPressed: () =>
                    openLink('https://www.youtube.com/watch?v=${d.trailerKey}'),
                icon: const Icon(Icons.smart_display_outlined, size: 20),
                label: const Text('Trailer'),
              ),
            OutlinedButton.icon(
              autofocus:
                  iptv == null &&
                  best == null &&
                  (d?.trailerKey.isEmpty ?? true),
              onPressed: () => toggleSavedTitle(context, _t),
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                size: 20,
              ),
              label: Text(saved ? 'Nella tua lista' : 'La mia lista'),
            ),
            if (d != null && d.imdbUrl.isNotEmpty)
              OutlinedButton(
                onPressed: () => openLink(d.imdbUrl),
                child: const Text('IMDb'),
              ),
          ],
        ),
        if (d != null && d.tagline.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '“${d.tagline}”',
            style: t.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: VistaColors.textSecondary,
            ),
          ),
        ],
        if (_t.overview.isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              _t.overview,
              maxLines: layout.compact ? 8 : 5,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(
                color: VistaColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
        if (d != null && d.directors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _t.type == MediaType.movie ? 'Regia  ' : 'Ideata da  ',
                  style: const TextStyle(color: VistaColors.textTertiary),
                ),
                TextSpan(text: d.directors.join(', ')),
              ],
            ),
            style: t.bodySmall,
          ),
        ],
        if (d == null && _error == null) ...[
          const SizedBox(height: 14),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
    if (layout.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [poster, const SizedBox(height: 14), info],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        poster,
        const SizedBox(width: 28),
        Expanded(child: info),
      ],
    );
  }

  List<Widget> _seasonSlivers(
    BuildContext context,
    VistaLayout layout,
    TmdbDetails d,
  ) {
    final g = layout.gutter;
    final t = Theme.of(context).textTheme;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 26, 0, 6),
          child: SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: g),
              itemCount: d.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = d.seasons[i];
                return FocusCard(
                  radius: 999,
                  focusScale: 1.0,
                  selected: s.number == _season,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  onTap: () => setState(() => _pickSeason(s.number)),
                  child: Text(
                    s.name.isEmpty ? 'Stagione ${s.number}' : s.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: FutureBuilder<List<TmdbEpisode>>(
          key: ValueKey(_season),
          future: _episodes,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final eps = snap.data ?? const <TmdbEpisode>[];
            return Padding(
              padding: EdgeInsets.fromLTRB(g, 8, g, 0),
              child: Column(
                children: [
                  for (final e in eps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FocusCard(
                        radius: VistaRadius.card,
                        focusScale: 1.0,
                        fill: const Color(0x0AFFFFFF),
                        padding: const EdgeInsets.all(10),
                        // Si guarda dal servizio o dalla lista: qui solo i dati.
                        onTap: () {},
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: layout.compact ? 128 : 190,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    VistaRadius.poster - 2,
                                  ),
                                  child: NetImage(e.still, cacheWidth: 400),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${e.number}. ${e.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    metaLine([
                                      if (e.runtime != null)
                                        formatDuration(e.runtime!),
                                      if (e.airDate.isNotEmpty)
                                        _date(e.airDate),
                                    ]),
                                    style: t.bodySmall?.copyWith(
                                      color: VistaColors.textTertiary,
                                    ),
                                  ),
                                  if (e.overview.isNotEmpty)
                                    Text(
                                      e.overview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall?.copyWith(
                                        color: VistaColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3
        ? '${int.tryParse(p[2]) ?? p[2]}/${int.tryParse(p[1]) ?? p[1]}/${p[0]}'
        : iso;
  }
}
