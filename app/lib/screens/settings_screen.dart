import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import 'channel_settings_screen.dart';
import 'shell.dart';

/// Impostazioni: fonte, canali, guida TV, dati personali, informazioni.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _refreshing = false;
  bool _epgRefreshing = false;

  Future<void> _refresh() async {
    final app = AppScope.of(context);
    final lib = app.library;
    if (lib == null) return;
    setState(() => _refreshing = true);
    try {
      await app.store.refresh(lib.source);
      unawaited(app.epg.refresh());
      if (mounted) showToast(context, 'Contenuti aggiornati.');
    } on SourceException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) {
        showToast(context, 'Aggiornamento non riuscito: ${redactError(e)}');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _refreshEpg() async {
    setState(() => _epgRefreshing = true);
    try {
      await AppScope.of(context).epg.refresh();
    } finally {
      if (mounted) setState(() => _epgRefreshing = false);
    }
  }

  Future<void> _changeSource() async {
    final ok = await _confirm(
      'Cambiare fonte?',
      'La lista o l\'account attuale verranno rimossi da questo dispositivo. '
          'Preferiti e avanzamento restano.',
      'Cambia',
    );
    if (ok && mounted) await AppScope.of(context).store.clear();
  }

  Future<void> _clearRecent() async {
    final ok = await _confirm('Svuotare i canali recenti?', '', 'Svuota');
    if (ok && mounted) {
      AppScope.of(context).user.clearRecent();
      showToast(context, 'Canali recenti svuotati.');
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: Text(title),
        content: body.isEmpty ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final lib = app.library;
    final source = lib?.source;
    final c = lib?.catalog;
    final canRefresh =
        source != null && !(source is M3uSource && source.isFile);
    final g = layout.gutter;

    return ListView(
      padding: EdgeInsets.fromLTRB(g, 0, g, layout.compact ? 110 : 32),
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(top: layout.compact ? 8 : 26, bottom: 18),
            child: Text(
              'Impostazioni',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header('Fonte'),
                if (source != null)
                  _Tile(
                    icon: source is XtreamSource
                        ? Icons.dns_rounded
                        : Icons.playlist_play_rounded,
                    title: source is XtreamSource
                        ? 'Account Xtream'
                        : 'Lista M3U',
                    subtitle: [
                      source.label,
                      if (c != null)
                        '${c.live.channels.length} canali · ${c.movies.length} film · ${c.series.length} serie',
                    ].join('\n'),
                    autofocus: true,
                  ),
                if (canRefresh)
                  _Tile(
                    icon: Icons.refresh_rounded,
                    title: _refreshing
                        ? 'Aggiornamento in corso…'
                        : 'Aggiorna contenuti',
                    subtitle:
                        'Scarica di nuovo canali, film e serie dalla fonte.',
                    onTap: _refreshing ? null : _refresh,
                  ),
                _Tile(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Cambia fonte',
                  subtitle: 'Aggiungi un\'altra lista M3U o un altro account.',
                  onTap: _changeSource,
                ),
                const _Header('TV in diretta'),
                _Tile(
                  icon: Icons.tune_rounded,
                  title: 'Gestisci canali',
                  subtitle:
                      'Rinomina, cambia logo, unisci o nascondi i canali.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChannelSettingsScreen(store: app.store),
                    ),
                  ),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: app.epg.status,
                  builder: (context, status, _) => _Tile(
                    icon: Icons.calendar_view_week_rounded,
                    title: _epgRefreshing
                        ? 'Aggiornamento guida…'
                        : 'Aggiorna guida TV',
                    subtitle: status.isEmpty
                        ? 'Guida dalla fonte e da epg.lat.'
                        : status,
                    onTap: _epgRefreshing ? null : _refreshEpg,
                  ),
                ),
                _Tile(
                  icon: Icons.history_rounded,
                  title: 'Svuota canali recenti',
                  subtitle: 'Cancella l\'elenco "Visti di recente".',
                  onTap: _clearRecent,
                ),
                const _Header('Informazioni'),
                const _Tile(
                  icon: Icons.info_outline_rounded,
                  title: 'Vista 0.2',
                  subtitle:
                      'Vista è un lettore: non fornisce né include canali, film o liste. '
                      'Usa solo contenuti che hai il diritto di guardare.',
                ),
                const _Tile(
                  icon: Icons.image_outlined,
                  title: 'Loghi dei canali',
                  subtitle:
                      'Dalla lista o da tv-logos (github.com/tv-logo/tv-logos), '
                      'licenza CC BY-NC-SA 4.0.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: VistaColors.textTertiary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusCard(
        autofocus: autofocus,
        radius: VistaRadius.card,
        focusScale: 1.0,
        fill: const Color(0x0DFFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap ?? () {},
        child: Row(
          children: [
            Icon(icon, size: 24, color: VistaColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: VistaColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}
