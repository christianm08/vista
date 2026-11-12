import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/backup.dart';
import '../data/epg_store.dart';
import '../data/parental_store.dart';
import '../data/source_store.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_dialogs.dart';
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';
import 'channel_settings_screen.dart';
import 'import_screen.dart';
import 'recordings_screen.dart';
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
  bool _cleaning = false;

  /// Spazio delle cache, ricalcolato dopo una pulizia.
  late Future<int> _cacheSize = CacheCleaner.size();

  Future<void> _saveBackup() async {
    try {
      final where = await Backup.save(AppScope.of(context));
      if (where != null && mounted) {
        showToast(context, 'Backup salvato: $where');
      }
    } catch (e) {
      if (mounted) showToast(context, 'Backup non salvato: ${redactError(e)}');
    }
  }

  Future<void> _restoreBackup() async {
    final app = AppScope.of(context);
    Map<String, dynamic>? data;
    try {
      data = await Backup.pick();
    } on FormatException catch (e) {
      if (mounted) showToast(context, e.message);
      return;
    } catch (e) {
      if (mounted) showToast(context, 'File non letto: ${redactError(e)}');
      return;
    }
    if (data == null || !mounted) return;
    final ok = await _confirm(
      'Ripristinare il backup?',
      'Preferiti, avanzamento, canali e preferenze verranno sostituiti con '
          'quelli del backup. La fonte, la chiave TMDB e il PIN restano questi.',
      'Ripristina',
    );
    if (!ok || !mounted) return;
    await Backup.restore(app, data);
    if (mounted) showToast(context, 'Backup ripristinato.');
  }

  Future<void> _clearCache() async {
    final ok = await _confirm(
      'Svuotare la cache?',
      'Locandine, loghi e guide TV si riscaricheranno quando servono. '
          'Preferiti, canali e impostazioni non si toccano.',
      'Svuota',
    );
    if (!ok || !mounted) return;
    setState(() => _cleaning = true);
    try {
      await CacheCleaner.clear(AppScope.of(context));
    } finally {
      if (mounted) {
        setState(() {
          _cleaning = false;
          _cacheSize = CacheCleaner.size();
        });
        showToast(context, 'Cache svuotata.');
      }
    }
  }

  /// Aggiorna tutte le fonti; quelle che non rispondono non bloccano le
  /// altre.
  Future<void> _refreshAll() async {
    final app = AppScope.of(context);
    setState(() => _refreshing = true);
    try {
      final errors = await app.store.refreshAll();
      unawaited(app.epg.refresh());
      if (mounted) {
        showToast(
          context,
          errors.isEmpty ? 'Contenuti aggiornati.' : errors.join('\n'),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Aggiornamento non riuscito: ${redactError(e)}');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _addSource() async {
    final app = AppScope.of(context);
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ImportScreen(store: app.store, adding: true),
      ),
    );
    if (added == true && mounted) {
      unawaited(app.epg.refresh());
      showToast(context, 'Fonte aggiunta: i canali uguali ora sono uniti.');
    }
  }

  /// Azioni su una fonte: aggiorna, rinomina, user-agent, togli.
  Future<void> _sourceActions(VistaSource source) async {
    final app = AppScope.of(context);
    final last = app.store.sources.length <= 1;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: Text(source.displayName),
        children: [
          if (source.canRefresh)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'refresh'),
              child: const Text('Aggiorna adesso'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'rename'),
            child: const Text('Rinomina'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'agent'),
            child: Text(
              source.userAgent.isEmpty
                  ? 'Imposta uno user-agent'
                  : 'Cambia user-agent',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: Text(last ? 'Togli (e torna all\'inizio)' : 'Togli'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'refresh':
        setState(() => _refreshing = true);
        try {
          await app.store.refresh(source);
          unawaited(app.epg.refresh());
          if (mounted) showToast(context, '${source.displayName} aggiornata.');
        } on SourceException catch (e) {
          if (mounted) showToast(context, e.message);
        } catch (e) {
          if (mounted) {
            showToast(context, 'Aggiornamento non riuscito: ${redactError(e)}');
          }
        } finally {
          if (mounted) setState(() => _refreshing = false);
        }
      case 'rename':
        final name = await askText(
          context,
          title: 'Nome della fonte',
          hint: source.label,
          initial: source.name,
          message: 'Lascia vuoto per usare "${source.label}".',
        );
        if (name != null) await app.store.updateSource(source, name: name);
      case 'agent':
        final ua = await askText(
          context,
          title: 'User-agent',
          hint: 'Es. VLC/3.0.20 LibVLC/3.0.20',
          initial: source.userAgent,
          message:
              'Serve solo se il fornitore lo chiede. Vale per scaricare la '
              'lista e per guardarne i canali. Vuoto = predefinito.',
        );
        if (ua != null) await app.store.updateSource(source, userAgent: ua);
      case 'remove':
        final ok = await _confirm(
          'Togliere ${source.displayName}?',
          last
              ? 'È l\'unica fonte: Vista tornerà alla schermata iniziale. '
                    'Preferiti e avanzamento restano.'
              : 'I suoi canali, film e serie spariscono; quelli che sono anche '
                    'in un\'altra fonte restano.',
          'Togli',
        );
        if (ok && mounted) {
          await app.store.remove(source);
          if (mounted && !last) unawaited(app.epg.refresh());
        }
    }
  }

  Future<void> _pickAutoRefresh() async {
    final user = AppScope.of(context).user;
    final picked = await showDialog<AutoRefresh>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: const Text('Aggiornamento automatico'),
        children: [
          for (final a in AutoRefresh.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: FocusCard(
                autofocus: a == user.autoRefresh,
                selected: a == user.autoRefresh,
                radius: 12,
                focusScale: 1.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                onTap: () => Navigator.pop(ctx, a),
                child: Text(a.label),
              ),
            ),
        ],
      ),
    );
    if (picked != null) user.setAutoRefresh(picked);
  }

  Future<void> _refreshEpg() async {
    setState(() => _epgRefreshing = true);
    try {
      await AppScope.of(context).epg.refresh();
    } finally {
      if (mounted) setState(() => _epgRefreshing = false);
    }
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

  /// Imposta, cambia o toglie il PIN (cambiare e togliere chiedono quello
  /// attuale).
  Future<void> _editPin() async {
    final parental = AppScope.of(context).parental;
    if (parental.enabled) {
      if (!await parental.unlock(
        context,
        reason: 'Inserisci il PIN attuale.',
      )) {
        return;
      }
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: const Color(0xF0121720),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VistaRadius.card),
          ),
          title: const Text('PIN'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('Cambia PIN'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Togli il PIN e tutti i blocchi'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'remove') {
        await parental.setPin('');
        if (mounted) showToast(context, 'PIN tolto: niente è più protetto.');
        return;
      }
    }
    if (!mounted) return;
    var first = '';
    if (!await askPin(
      context,
      title: 'Nuovo PIN',
      reason: 'Servirà per i canali e le categorie protetti.',
      onEntered: (p) => first = p,
    )) {
      return;
    }
    if (!mounted) return;
    final same = await askPin(
      context,
      title: 'Conferma il PIN',
      check: (p) => p == first,
    );
    if (!mounted) return;
    if (!same) {
      showToast(context, 'I due PIN non coincidono: riprova.');
      return;
    }
    await parental.setPin(first);
    if (mounted) {
      showToast(
        context,
        'PIN impostato. Blocca canali e categorie da Gestisci canali.',
      );
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
    // Si ridisegna quando cambiano fonti e catalogo (aggiunte, aggiornamenti).
    return ValueListenableBuilder<Library?>(
      valueListenable: AppScope.of(context).store.library,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final lib = app.library;
    final c = lib?.catalog;
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
                const _Header('Fonti'),
                for (final (i, src) in (lib?.sources ?? const []).indexed)
                  _Tile(
                    icon: src is XtreamSource
                        ? Icons.dns_rounded
                        : Icons.playlist_play_rounded,
                    title: src.displayName,
                    subtitle: [
                      src is XtreamSource ? 'Account Xtream' : 'Lista M3U',
                      if (src.name.isNotEmpty) src.label,
                      if (src.userAgent.isNotEmpty) 'user-agent personalizzato',
                    ].join(' · '),
                    autofocus: i == 0,
                    onTap: () => _sourceActions(src),
                  ),
                _Tile(
                  icon: Icons.refresh_rounded,
                  title: _refreshing
                      ? 'Aggiornamento in corso…'
                      : 'Aggiorna tutte le fonti',
                  subtitle: c == null
                      ? ''
                      : '${c.live.channels.length} canali · ${c.movies.length} film · '
                            '${c.series.length} serie',
                  onTap: _refreshing ? null : _refreshAll,
                ),
                _Tile(
                  icon: Icons.add_rounded,
                  title: 'Aggiungi una lista o un account',
                  subtitle:
                      'I canali presenti in più fonti diventano uno solo: '
                      'una fa da riserva all\'altra.',
                  onTap: _addSource,
                ),
                ListenableBuilder(
                  listenable: app.user,
                  builder: (context, _) => _Tile(
                    icon: Icons.update_rounded,
                    title: 'Aggiornamento automatico',
                    subtitle: app.user.autoRefresh == AutoRefresh.off
                        ? 'Le liste si aggiornano solo a mano.'
                        : '${app.user.autoRefresh.label} (le liste da file '
                              'si aggiornano scegliendo di nuovo il file).',
                    onTap: _pickAutoRefresh,
                  ),
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
                  icon: Icons.fiber_manual_record_outlined,
                  title: 'Registrazioni',
                  subtitle: 'Programmate e salvate: guardale o cancellale.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecordingsScreen()),
                  ),
                ),
                _Tile(
                  icon: Icons.history_rounded,
                  title: 'Svuota canali recenti',
                  subtitle: 'Cancella l\'elenco "Visti di recente".',
                  onTap: _clearRecent,
                ),
                const _Header('Backup e manutenzione'),
                _Tile(
                  icon: Icons.save_alt_rounded,
                  title: 'Salva un backup',
                  subtitle:
                      'Preferiti, avanzamento, canali e preferenze in un file '
                      '(senza password né chiavi).',
                  onTap: _saveBackup,
                ),
                _Tile(
                  icon: Icons.settings_backup_restore_rounded,
                  title: 'Ripristina un backup',
                  subtitle:
                      'Da un file salvato con Vista, anche su un altro '
                      'dispositivo.',
                  onTap: _restoreBackup,
                ),
                FutureBuilder<int>(
                  future: _cacheSize,
                  builder: (context, size) => _Tile(
                    icon: Icons.cleaning_services_outlined,
                    title: _cleaning ? 'Pulizia in corso…' : 'Svuota cache',
                    subtitle: size.hasData
                        ? 'Locandine, loghi e guide TV: '
                              '${CacheCleaner.format(size.data!)}.'
                        : 'Locandine, loghi e guide TV salvati.',
                    onTap: _cleaning ? null : _clearCache,
                  ),
                ),
                const _Header('Controllo genitori'),
                ListenableBuilder(
                  listenable: app.parental,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Tile(
                        icon: Icons.lock_outline_rounded,
                        title: app.parental.enabled
                            ? 'Cambia o togli il PIN'
                            : 'Imposta un PIN',
                        subtitle: app.parental.enabled
                            ? '${app.parental.lockedChannels.length} canali e '
                                  '${app.parental.lockedGroups.length} categorie '
                                  'protetti.'
                            : 'Proteggi canali, categorie e impostazioni.',
                        onTap: _editPin,
                      ),
                      if (app.parental.enabled)
                        _Tile(
                          icon: Icons.settings_outlined,
                          title: 'Proteggi le impostazioni',
                          subtitle: app.parental.locksSettings
                              ? 'Per entrare nelle impostazioni serve il PIN.'
                              : 'Le impostazioni sono aperte a tutti.',
                          trailing: ExcludeFocus(
                            child: Switch(
                              value: app.parental.locksSettings,
                              onChanged: (v) =>
                                  app.parental.setSettingsLocked(v),
                            ),
                          ),
                          onTap: () => app.parental.setSettingsLocked(
                            !app.parental.locksSettings,
                          ),
                        ),
                    ],
                  ),
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
