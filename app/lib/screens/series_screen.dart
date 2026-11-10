import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/channel_tile.dart';
import '../widgets/focus_card.dart';
import '../widgets/poster_card.dart';
import 'vod_player_screen.dart';

/// Scheda di una serie: locandina, trama, stagioni ed episodi.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.series,
    required this.source,
    required this.store,
  });

  final Series series;
  final VistaSource source;
  final SourceStore store;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  List<Episode>? _episodes;
  String? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final eps = await widget.store.episodes(widget.source, widget.series);
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _season = eps.isEmpty ? null : eps.first.season;
      });
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Episodi non disponibili: ${redactError(e)}');
    }
  }

  List<int> get _seasons => {for (final e in _episodes ?? <Episode>[]) e.season}.toList();

  List<Episode> get _visible =>
      (_episodes ?? const []).where((e) => e.season == _season).toList();

  void _play(Episode e) {
    final list = _visible;
    final s = widget.series;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VodPlayerScreen(
        initialIndex: list.indexOf(e),
        items: [
          for (final x in list)
            VodItem(title: s.title, subtitle: '${x.code} · ${x.title}', url: x.url),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final side = wide ? 48.0 : 16.0;
    final s = widget.series;
    final eps = _episodes;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, wide ? 32 : 16, side, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: wide ? 200 : 120,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ExcludeFocus(
                          child: PosterCard(title: s.title, image: s.poster, onTap: () {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title,
                              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (s.rating.isNotEmpty) Pill('★ ${s.rating}', filled: true),
                              Text(
                                [
                                  if (s.year != null) '${s.year}',
                                  s.group,
                                  if (eps != null)
                                    _seasons.length == 1 ? '1 stagione' : '${_seasons.length} stagioni',
                                ].join(' · '),
                                style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
                              ),
                            ],
                          ),
                          if (s.plot.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(s.plot,
                                maxLines: wide ? 5 : 4,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!, style: const TextStyle(color: Color(0xFFFF9C8A))),
                      const SizedBox(height: 12),
                      FilledButton(autofocus: true, onPressed: _load, child: const Text('Riprova')),
                    ],
                  ),
                ),
              )
            else if (eps == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (eps.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Nessun episodio disponibile.', textAlign: TextAlign.center),
                ),
              )
            else ...[
              if (_seasons.length > 1)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: side, vertical: 10),
                      children: [
                        for (final n in _seasons)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: FocusCard(
                              radius: 999,
                              selected: _season == n,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              onTap: () => setState(() => _season = n),
                              child: Text('Stagione $n',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 8, side, 40),
                sliver: SliverList.separated(
                  itemCount: _visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _EpisodeRow(
                    episode: _visible[i],
                    autofocus: i == 0,
                    onTap: () => _play(_visible[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap, this.autofocus = false});

  final Episode episode;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = episode;
    final minutes = e.duration?.inMinutes;
    return FocusCard(
      autofocus: autofocus,
      radius: VistaRadius.poster,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('${e.number}',
                style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: VistaColors.textTertiary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (e.plot.isNotEmpty)
                  Text(e.plot,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
              ],
            ),
          ),
          if (minutes != null && minutes > 0) ...[
            const SizedBox(width: 12),
            Text('$minutes min',
                style: t.bodySmall?.copyWith(color: VistaColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
