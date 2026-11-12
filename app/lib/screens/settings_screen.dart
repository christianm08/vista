import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/epg_store.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';
import 'channel_settings_screen.dart';
import 'services_screen.dart';
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

  /// Link XMLTV personale: ha la precedenza su epg.lat e sulla guida della
  /// lista. Non si mostra mai per intero (può contenere una password).
  Future<void> _editGuideLink() async {
    final epg = AppScope.of(context).epg;
    final ctl = TextEditingController();
    String? error;
    final result = await showDialog<(bool, Uri?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void save() {
            final u = EpgStore.parseGuideUri(ctl.text);
            if (u == null) {
              setDialog(
                () => error = 'Serve un link che inizia con http:// o https://',
              );
              return;
            }
            Navigator.pop(ctx, (true, u));
          }

          return AlertDialog(
            backgroundColor: const Color(0xF0121720),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VistaRadius.card),
            ),
            title: const Text('Link della guida TV'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    epg.customUri.value == null
                        ? 'Un file XMLTV (.xml o .xml.gz). Avrà la precedenza sulle altre guide.'
                        : 'Attuale: ${epg.customUri.value!.host}. Scrivi un nuovo link per sostituirlo.',
                    style: Theme.of(ctx).textTheme.bodySmall
                        ?.copyWith(color: VistaColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TvTextField(
                    controller: ctl,
                    hint: 'https://… link della guida XMLTV',
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => save(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFFF8A80)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (epg.customUri.value != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, (true, null)),
                  child: const Text('Rimuovi link'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              FilledButton(onPressed: save, child: const Text('Salva')),
            ],
          );
        },
      ),
    );
    ctl.dispose();
    if (result == null || !result.$1 || !mounted) return;
    await epg.setCustomUri(result.$2);
    if (mounted) {
      showToast(
        context,
        result.$2 == null
            ? 'Link della guida rimosso.'
            : 'Link salvato: scarico la guida…',
      );
    }
  }

  /// Sposta gli orari della guida quando sono sbagliati di qualche ora.
  Future<void> _editGuideShift() async {
    final epg = AppScope.of(context).epg;
    final current = epg.shift.value.inHours;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: const Text('Sposta gli orari della guida'),
        children: [
          SizedBox(
            width: 320,
            height: 360,
            child: ListView(
              children: [
                for (var h = -12; h <= 12; h++)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, h),
                    child: FocusCard(
                      autofocus: h == current,
                      radius: 12,
                      focusScale: 1.0,
                      selected: h == current,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      onTap: () => Navigator.pop(ctx, h),
                      child: Text(shiftLabel(Duration(hours: h))),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await epg.setShift(Duration(hours: picked));
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
                const _Header('Servizi di streaming'),
                ListenableBuilder(
                  listenable: Listenable.merge([app.tmdb.client, app.user]),
                  builder: (context, _) => _Tile(
                    icon: Icons.subscriptions_rounded,
                    title: 'I miei servizi',
                    subtitle: !app.tmdb.ready
                        ? 'Collega TMDB e scegli Netflix, Prime Video, Disney+, RaiPlay…'
                        : (app.user.services.isEmpty
                              ? 'Nessun servizio scelto.'
                              : '${app.user.services.length} servizi scelti · TMDB collegato'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServicesScreen()),
                    ),
                  ),
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
                ListenableBuilder(
                  listenable: app.user,
                  builder: (context, _) => _Tile(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'All\'avvio apri l\'ultimo canale',
                    subtitle: app.user.startOnLastChannel
                        ? 'Vista riparte dal canale che stavi guardando.'
                        : 'Vista si apre sulla Home.',
                    trailing: ExcludeFocus(
                      child: Switch(
                        value: app.user.startOnLastChannel,
                        onChanged: app.user.setStartOnLastChannel,
                      ),
                    ),
                    onTap: () => app.user.setStartOnLastChannel(
                      !app.user.startOnLastChannel,
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
                ValueListenableBuilder<Uri?>(
                  valueListenable: app.epg.customUri,
                  builder: (context, uri, _) => _Tile(
                    icon: Icons.link_rounded,
                    title: 'Link della guida TV',
                    subtitle: uri == null
                        ? 'Aggiungi una tua guida XMLTV, oltre a epg.lat e a quella della lista.'
                        : 'La tua guida da ${uri.host} ha la precedenza.',
                    onTap: _editGuideLink,
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: app.epg.shift,
                  builder: (context, shift, _) => _Tile(
                    icon: Icons.schedule_rounded,
                    title: 'Orari della guida',
                    subtitle: shift == Duration.zero
                        ? 'Nessuna correzione. Usala se i programmi sono in anticipo o in ritardo.'
                        : 'Spostati di ${shiftLabel(shift)}.',
                    onTap: _editGuideShift,
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

/// `+1 h`, `−2 h`, `nessuna correzione`.
String shiftLabel(Duration d) {
  final h = d.inHours;
  if (h == 0) return 'nessuna correzione';
  return '${h > 0 ? '+' : '−'}${h.abs()} h';
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
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool autofocus;

  /// Al posto della freccia (es. un interruttore).
  final Widget? trailing;

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
            if (trailing != null)
              trailing!
            else if (onTap != null)
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
