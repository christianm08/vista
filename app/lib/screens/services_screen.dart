import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/service_launcher.dart';
import '../theme.dart';
import '../widgets/availability.dart';
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';

/// I miei servizi: chiave TMDB e scelta dei servizi di streaming che
/// l'utente ha (filtrano Scopri e mettono in evidenza "Disponibile su:").
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _key = TextEditingController();
  late final TextEditingController _filterCtl = TextEditingController()
    ..addListener(() => setState(() => _filter = _filterCtl.text.trim()));
  bool _checking = false;
  String? _keyError;
  Future<List<WatchProvider>>? _providers;
  String _filter = '';

  @override
  void dispose() {
    _key.dispose();
    _filterCtl.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final k = _key.text.trim();
    if (k.isEmpty) return;
    setState(() {
      _checking = true;
      _keyError = null;
    });
    try {
      await AppScope.of(context).tmdb.setKey(k);
      _key.clear();
      _providers = null;
    } on TmdbException catch (e) {
      _keyError = e.message;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final g = layout.gutter;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([app.tmdb.client, app.user]),
        builder: (context, _) {
          final ready = app.tmdb.ready;
          if (ready) _providers ??= app.tmdb.providers();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(g - 8, 12, g, 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Indietro',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'I miei servizi',
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: g),
                sliver: SliverToBoxAdapter(child: _keyCard(context, ready)),
              ),
              if (ready)
                SliverToBoxAdapter(
                  child: FutureBuilder<List<WatchProvider>>(
                    future: _providers,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Padding(
                          padding: EdgeInsets.all(g),
                          child: Text(
                            '${snap.error}',
                            style: const TextStyle(color: Color(0xFFFF9C8A)),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return _grid(context, layout, snap.data!);
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(g, 24, g, 40),
                  child: Text(
                    'Questo prodotto usa l\'API di TMDB ma non è approvato né certificato da TMDB. '
                    'I dati sulla disponibilità nei servizi sono forniti da JustWatch.',
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _keyCard(BuildContext context, bool ready) {
    final t = Theme.of(context).textTheme;
    final tmdb = AppScope.of(context).tmdb;
    return Glass(
      blur: false,
      radius: VistaRadius.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle_rounded : Icons.key_rounded,
                color: ready ? VistaColors.accent : VistaColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'TMDB collegato' : 'Collega TMDB',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (ready && tmdb.userKey)
                TextButton(
                  onPressed: () async {
                    await tmdb.removeKey();
                    setState(() => _providers = null);
                  },
                  child: const Text('Rimuovi chiave'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ready
                ? 'Film, serie, locandine, cast e disponibilità arrivano da TMDB. '
                      'Puoi sostituire la chiave quando vuoi.'
                : 'TMDB è il database gratuito di film e serie usato da Plex e da molte app. '
                      'Crea un account su themoviedb.org, poi in Impostazioni → API copia la '
                      '"Chiave API" o il "Token di accesso in lettura" e incollalo qui.',
            style: t.bodySmall?.copyWith(
              color: VistaColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TvTextField(
                  controller: _key,
                  hint: ready
                      ? 'Nuova chiave TMDB (facoltativa)'
                      : 'Chiave API o token TMDB',
                  obscure: true,
                  autofocus: !ready,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveKey(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _checking ? null : _saveKey,
                child: Text(_checking ? 'Verifico…' : 'Salva'),
              ),
            ],
          ),
          if (_keyError != null) ...[
            const SizedBox(height: 8),
            Text(_keyError!, style: const TextStyle(color: Color(0xFFFF9C8A))),
          ],
          if (!ready) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () =>
                  openLink('https://www.themoviedb.org/settings/api'),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Apri themoviedb.org'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    VistaLayout layout,
    List<WatchProvider> all,
  ) {
    final t = Theme.of(context).textTheme;
    final user = AppScope.of(context).user;
    final mine = user.services.toSet();
    final g = layout.gutter;
    final f = _filter.toLowerCase();
    final list = [
      for (final p in all)
        if (f.isEmpty || p.name.toLowerCase().contains(f)) p,
    ];
    final tileW = layout.compact ? 104.0 : 124.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(g, 22, g, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mine.isEmpty
                      ? 'Quali servizi hai?'
                      : 'Hai scelto ${mine.length} servizi',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                width: layout.compact ? 150 : 260,
                child: TvTextField(
                  controller: _filterCtl,
                  hint: 'Filtra',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Scopri mostrerà i loro cataloghi e "Disponibile su" li metterà per primi.',
            style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in list)
                SizedBox(
                  width: tileW,
                  child: FocusCard(
                    radius: 14,
                    focusScale: 1.05,
                    fill: mine.contains(p.id)
                        ? const Color(0x26F6C59A)
                        : VistaColors.glass,
                    padding: const EdgeInsets.all(10),
                    onTap: () {
                      final next = [...user.services];
                      next.contains(p.id) ? next.remove(p.id) : next.add(p.id);
                      user.setServices(next);
                    },
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProviderLogo(p, size: 56),
                            if (mine.contains(p.id))
                              const Positioned(
                                right: -6,
                                top: -6,
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: VistaColors.accent,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(
                            fontWeight: mine.contains(p.id)
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
