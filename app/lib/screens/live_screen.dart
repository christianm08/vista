import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/recordings.dart';
import '../data/source_store.dart' show redactError;
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_dialogs.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/list_titles.dart';
import '../widgets/live_preview.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import 'channel_settings_screen.dart';
import 'shell.dart';

/// Categorie speciali in cima all'elenco.
const _all = '\u0000tutti';
const _favorites = '\u0000preferiti';
const _recent = '\u0000recenti';

const _specialLabels = {
  _all: 'Tutti i canali',
  _favorites: 'Preferiti',
  _recent: 'Visti di recente',
};

/// TV in diretta. Su TV e PC: anteprima del canale a fuoco in alto, filtri
/// per categoria, guida a griglia sotto. Su telefono: filtri a scorrimento e
/// lista dei canali.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  String _group = _all;
  bool _previewOn = true;

  /// Canale e programma sotto il cursore della guida. Cambia a ogni freccia:
  /// aggiorna solo l'intestazione, non tutta la schermata.
  final _selection = ValueNotifier<GuideSelection?>(null);

  // Elenchi calcolati una volta per catalogo (le liste vere hanno migliaia
  // di canali: rifarli a ogni tasto rallentava la guida sul box TV).
  Catalog? _memoFor;
  List<Channel> _allChannels = const [];
  Map<String, Channel> _byKey = const {};
  Map<String, List<Channel>> _byGroup = const {};
  DateTime _now = DateTime.now();
  late final Timer _clock;
  final _gridFocus = FocusNode(debugLabel: 'guida');

  /// Un nodo per chip: Su dalla guida torna sul filtro scelto.
  final _chipFocus = <String, FocusNode>{};

  FocusNode _chipNode(String g) =>
      _chipFocus.putIfAbsent(g, () => FocusNode(debugLabel: 'filtro $g'));

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    final user = AppScope.of(context).user;
    // Si parte dai preferiti, se ce ne sono.
    if (user.favorites.any((k) => k.startsWith('ch:'))) _group = _favorites;
  }

  @override
  void dispose() {
    _clock.cancel();
    _gridFocus.dispose();
    for (final n in _chipFocus.values) {
      n.dispose();
    }
    _selection.dispose();
    super.dispose();
  }

  void _memo(Catalog c) {
    if (identical(_memoFor, c)) return;
    _memoFor = c;
    _allChannels = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];
    _byKey = {for (final ch in _allChannels) ch.key: ch};
    final byGroup = <String, List<Channel>>{};
    for (final ch in _allChannels) {
      (byGroup[ch.group] ??= []).add(ch);
    }
    _byGroup = byGroup;
  }

  List<Channel> _visible(UserStore user) {
    switch (_group) {
      case _all:
        return _allChannels;
      case _favorites:
        return [
          for (final ch in _allChannels)
            if (user.isFavorite(UserKey.channel(ch.key))) ch,
        ];
      case _recent:
        return [for (final k in user.recentChannels) ?_byKey[k]];
      default:
        return _byGroup[_group] ?? const [];
    }
  }

  List<(String, int)> _groups(UserStore user) {
    // Preferiti e recenti si contano dall'elenco dell'utente (pochi), non
    // scorrendo tutti i canali.
    final fav = user.favorites
        .where((k) => k.startsWith('ch:') && _byKey.containsKey(k.substring(3)))
        .length;
    final rec = user.recentChannels.where(_byKey.containsKey).length;
    return [
      (_all, _allChannels.length),
      if (fav > 0) (_favorites, fav),
      if (rec > 0) (_recent, rec),
      for (final g in AppScope.of(
        context,
      ).store.prefs.orderGroups(_byGroup.keys))
        (g, _byGroup[g]!.length),
    ];
  }

  void _pick(String g) {
    if (g == _group) return;
    setState(() {
      _group = g;
      _selection.value = null;
    });
  }

  Future<void> _manageChannels() async {
    final store = AppScope.of(context).store;
    setState(() => _previewOn = false);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChannelSettingsScreen(store: store)),
    );
    if (mounted) setState(() => _previewOn = true);
  }

  Future<void> _play(List<Channel> list, Channel c) async {
    setState(() => _previewOn = false);
    await Nav.playChannel(context, list, c);
    if (!mounted) return;
    setState(() => _previewOn = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _gridFocus.context != null) _gridFocus.requestFocus();
    });
  }

  /// Menu del canale (tasto Menu, tocco lungo): preferito, modifica.
  Future<void> _actions(Channel c) async {
    final app = AppScope.of(context);
    final key = UserKey.channel(c.key);
    final fav = app.user.isFavorite(key);
    // Programma sotto il cursore della guida, se deve ancora iniziare.
    final sel = _selection.value;
    final upcoming =
        sel != null &&
            sel.channel.key == c.key &&
            sel.programme != null &&
            sel.programme!.start.isAfter(DateTime.now())
        ? sel.programme
        : null;
    final reminded =
        upcoming != null &&
        app.user.hasReminder(c.key, upcoming.start.toLocal());
    // Programma sotto il cursore non ancora finito: si può registrare.
    final recordable =
        sel != null &&
            sel.channel.key == c.key &&
            sel.programme != null &&
            sel.programme!.stop.isAfter(DateTime.now())
        ? sel.programme
        : null;
    final recording =
        recordable != null &&
        RecordingService.instance.isScheduled(
          c.key,
          recordable.start.toLocal(),
        );
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Row(
          children: [
            ChannelLogo(channel: c, size: VistaSize.guideLogo),
            const SizedBox(width: VistaSpace.s12),
            Expanded(
              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        children: [
          if (recordable != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'record'),
              child: _ActionRow(
                recording
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record_outlined,
                recording
                    ? 'Annulla la registrazione'
                    : 'Registra: ${recordable.title}',
              ),
            ),
          if (upcoming != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'remind'),
              child: _ActionRow(
                reminded
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                reminded
                    ? 'Togli il promemoria'
                    : 'Ricordamelo: ${upcoming.title} '
                          '(${hhmm(upcoming.start)})',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'fav'),
            child: _ActionRow(
              fav ? Icons.star_rounded : Icons.star_outline_rounded,
              fav ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
            ),
          ),
          if (app.parental.enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'lock'),
              child: _ActionRow(
                app.parental.lockedChannels.contains(c.key)
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                app.parental.lockedChannels.contains(c.key)
                    ? 'Togli il PIN'
                    : 'Proteggi col PIN',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'hide'),
            child: const _ActionRow(
              Icons.visibility_off_outlined,
              'Nascondi canale',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'move'),
            child: const _ActionRow(
              Icons.drive_file_move_outline,
              'Sposta in categoria',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'number'),
            child: _ActionRow(Icons.pin_outlined, 'Numero (${c.number})'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const _ActionRow(Icons.edit_outlined, 'Modifica canale'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Future<void> save(
      ChannelPrefs Function(ChannelPrefs) change,
      String done,
    ) async {
      try {
        await app.store.updatePrefs(change(app.store.prefs));
        if (mounted) showToast(context, done);
      } catch (e) {
        if (mounted) {
          showToast(context, 'Modifica non salvata: ${redactError(e)}');
        }
      }
    }

    if (choice == 'record' && recordable != null) {
      final s = ScheduledRecording(
        channelKey: c.key,
        channelName: c.name,
        title: recordable.title,
        start: recordable.start.toLocal(),
        end: recordable.stop.toLocal(),
      );
      if (recording) {
        await RecordingService.instance.cancel(s);
        if (mounted) showToast(context, 'Registrazione annullata.');
      } else {
        final service = RecordingService.instance;
        service.schedule(s);
        // Se il programma è già iniziato si registra da adesso.
        final from = s.recordFrom.isAfter(DateTime.now())
            ? s.recordFrom
            : DateTime.now();
        final size = service.quality.estimate(s.recordTo.difference(from));
        showToast(
          context,
          recordable.start.isAfter(DateTime.now())
              ? 'Registrerò ${recordable.title} (${hhmm(recordable.start)}), '
                    '$size in qualità ${service.quality.label}.'
              : 'Registrazione di ${recordable.title} avviata ($size).',
        );
      }
    } else if (choice == 'remind' && upcoming != null) {
      final start = upcoming.start.toLocal();
      if (reminded) {
        app.user.removeReminder(c.key, start);
        showToast(context, 'Promemoria tolto.');
      } else {
        app.user.addReminder(
          Reminder(
            channelKey: c.key,
            channelName: c.name,
            title: upcoming.title,
            start: start,
          ),
        );
        showToast(
          context,
          'Ti avviso quando inizia ${upcoming.title} (${hhmm(upcoming.start)}).',
        );
      }
    } else if (choice == 'lock') {
      final locked = app.parental.lockedChannels.contains(c.key);
      if (locked &&
          !await app.parental.unlock(
            context,
            reason: 'Serve il PIN per sbloccare.',
          )) {
        return;
      }
      await app.parental.setChannelLocked(c.key, !locked);
      if (mounted) {
        showToast(
          context,
          locked
              ? '${c.name} non più protetto.'
              : '${c.name} protetto dal PIN.',
        );
      }
    } else if (choice == 'hide') {
      await save(
        (p) => p.setHidden(c.key, true),
        '${c.name} nascosto. Lo ritrovi in Gestisci canali.',
      );
    } else if (choice == 'move') {
      final to = await pickGroup(
        context,
        groups: app.store.prefs.orderGroups({
          for (final ch in _allChannels) ch.group,
        }),
        current: c.group,
        canReset: (app.store.prefs.overrides[c.key]?.group ?? '').isNotEmpty,
      );
      if (to != null && to != c.group && mounted) {
        await save(
          (p) => p.moveToGroup(c.key, to),
          to.isEmpty
              ? '${c.name} tornato nella categoria della lista.'
              : '${c.name} spostato in "$to".',
        );
      }
    } else if (choice == 'number') {
      final n = await askChannelNumber(
        context,
        channelName: c.name,
        current: c.number,
        custom: c.renumbered,
      );
      if (n != null && mounted) {
        await save(
          (p) => p.setNumber(c.key, n == 0 ? null : n),
          n == 0
              ? 'Torna il numero della lista.'
              : '${c.name} ora è il canale $n.',
        );
      }
    } else if (choice == 'fav') {
      app.user.toggleFavorite(key);
      showToast(
        context,
        fav
            ? '${c.name} tolto dai preferiti'
            : '${c.name} aggiunto ai preferiti',
      );
    } else if (choice == 'edit') {
      setState(() => _previewOn = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChannelEditScreen(store: app.store, channelKey: c.key),
        ),
      );
      if (mounted) setState(() => _previewOn = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.store.library,
        app.user,
        app.epg.guide,
      ]),
      builder: (context, _) {
        final lib = app.library;
        if (lib == null) return const SizedBox.shrink();
        _memo(lib.catalog);
        final groups = _groups(app.user);
        if (!groups.any((g) => g.$1 == _group)) _group = _all;
        final channels = _visible(app.user);
        final guide = app.epg.guide.value;
        return VistaLayout.of(context).compact
            ? _phone(context, channels, groups, guide)
            : _wide(context, channels, groups, guide);
      },
    );
  }

  // ===== TV e PC ===============================================================

  Widget _wide(
    BuildContext context,
    List<Channel> channels,
    List<(String, int)> groups,
    EpgGuide guide,
  ) {
    final app = AppScope.of(context);
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    final top = layout.safe.top > VistaSpace.s32
        ? layout.safe.top
        : VistaSpace.s32;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        g,
        top,
        g + layout.safe.right,
        layout.safe.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context),
          const SizedBox(height: VistaSpace.s16),
          if (channels.isNotEmpty)
            ListenableBuilder(
              listenable: Listenable.merge([app.epg.status, _selection]),
              builder: (context, _) {
                final channel = _selection.value?.channel ?? channels.first;
                return LiveHeader(
                  selection: _selection.value,
                  now: _now,
                  status: app.epg.status.value,
                  preview: LivePreview(
                    channel: channel,
                    enabled:
                        _previewOn &&
                        (!app.parental.isLocked(channel) ||
                            app.parental.isUnlocked),
                  ),
                );
              },
            ),
          _filters(context, groups),
          Expanded(
            child: channels.isEmpty
                ? const EmptyState(
                    icon: Icons.live_tv_outlined,
                    title: 'Nessun canale qui',
                    message: 'Scegli un\'altra categoria.',
                  )
                : Stack(
                    children: [
                      EpgGrid(
                        channels: channels,
                        guide: guide,
                        now: _now,
                        focusNode: _gridFocus,
                        onSelectionChanged: (s) => _selection.value = s,
                        onPlay: (c) => _play(channels, c),
                        onEdit: _actions,
                        onExitTop: () {
                          // Il chip scelto, se la fila lo ha costruito;
                          // altrimenti il primo.
                          final n = _chipNode(_group);
                          (n.context != null ? n : _chipNode(_all))
                              .requestFocus();
                        },
                      ),
                      // Entrando nella sezione si è subito sui canali.
                      _AutofocusGrid(node: _gridFocus),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Titolo della pagina, data e ora, gestione dei canali.
  Widget _title(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final compact = VistaLayout.of(context).compact;
    const days = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu', //
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    final meta = t.labelLarge?.copyWith(
      color: VistaColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            'TV in diretta',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.headlineSmall,
          ),
        ),
        if (!compact) ...[
          Text(
            '${days[_now.weekday - 1]} ${_now.day} ${months[_now.month - 1]} · ',
            style: meta,
          ),
          VistaClock(style: meta),
          const SizedBox(width: VistaSpace.s16),
        ],
        VistaIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Gestisci canali',
          onPressed: _manageChannels,
        ),
      ],
    );
  }

  /// Filtri per categoria: una fila di chip che scorre col fuoco.
  Widget _filters(BuildContext context, List<(String, int)> groups) {
    final names = groupLabels([
      for (final (g, _) in groups) g,
    ], fixed: _specialLabels);
    final layout = VistaLayout.of(context);
    // Sopra e sotto, spazio per l'anello del chip a fuoco.
    const reserve = VistaSpace.s8;
    return SizedBox(
      height: layout.chipHeight + reserve * 2 + (layout.compact ? 0 : reserve),
      child: ClipRect(
        clipper: const _SidesOnly(reserve),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(
            layout.compact ? layout.gutter : 0,
            layout.compact ? reserve : reserve * 2,
            layout.gutter,
            reserve,
          ),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: VistaSpace.s8),
          itemBuilder: (context, i) {
            final (g, n) = groups[i];
            // Il fuoco non fa scorrere da solo (VistaTraversalPolicy): la
            // fila porta in vista il chip a fuoco.
            return Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (has) {
                if (has) {
                  Scrollable.ensureVisible(
                    context,
                    alignment: 0.5,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : VistaMotion.rowScroll,
                    curve: VistaMotion.enter,
                  );
                }
              },
              child: VistaChip(
                focusNode: _chipNode(g),
                label: layout.compact ? '${names[g]}  $n' : names[g]!,
                selected: g == _group,
                onSelected: () => _pick(g),
              ),
            );
          },
        ),
      ),
    );
  }

  // ===== Telefono ==============================================================

  Widget _phone(
    BuildContext context,
    List<Channel> channels,
    List<(String, int)> groups,
    EpgGuide guide,
  ) {
    final layout = VistaLayout.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                VistaSpace.s8,
                VistaSpace.s8,
                0,
              ),
              child: _title(context),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _filters(context, groups)),
        if (channels.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Nessun canale qui',
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              layout.gutter,
              0,
              layout.gutter,
              VistaSpace.s32,
            ),
            sliver: SliverList.builder(
              itemCount: channels.length,
              itemBuilder: (_, i) =>
                  _phoneRow(context, channels, channels[i], guide),
            ),
          ),
      ],
    );
  }

  Widget _phoneRow(
    BuildContext context,
    List<Channel> list,
    Channel c,
    EpgGuide guide,
  ) {
    final t = Theme.of(context).textTheme;
    final user = AppScope.of(context).user;
    final now = guide.nowOn(c, now: _now);
    return InkWell(
      borderRadius: BorderRadius.circular(VistaRadius.card),
      onTap: () => _play(list, c),
      onLongPress: () => _actions(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VistaSpace.s8),
        child: Row(
          children: [
            SizedBox(
              width: VistaSize.guideNumber,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(
                  color: VistaColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            ChannelLogo(channel: c, size: VistaSize.minTouch),
            const SizedBox(width: VistaSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall,
                        ),
                      ),
                      if (user.isFavorite(UserKey.channel(c.key))) ...[
                        const SizedBox(width: VistaSpace.s4),
                        const Icon(
                          Icons.star_rounded,
                          size: VistaSize.iconSmall,
                          color: VistaColors.textSecondary,
                          semanticLabel: 'Preferito',
                        ),
                      ],
                    ],
                  ),
                  Text(
                    now == null
                        ? 'Nessuna informazione'
                        : '${hhmm(now.start)}  ${now.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                  if (now != null) ...[
                    const SizedBox(height: VistaSpace.s4),
                    VistaProgressBar(now.progressAt(_now)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ritaglia solo ai lati, lasciando [overhang] per l'anello a sinistra; sopra
/// e sotto non taglia.
class _SidesOnly extends CustomClipper<Rect> {
  const _SidesOnly(this.overhang);
  final double overhang;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -overhang,
    -VistaSpace.s64,
    size.width,
    size.height + VistaSpace.s64,
  );

  @override
  bool shouldReclip(_SidesOnly old) => old.overhang != overhang;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: VistaSpace.s8),
    child: Row(
      children: [
        Icon(icon, size: VistaSize.icon),
        const SizedBox(width: VistaSpace.s16),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

/// Dà il focus alla griglia quando la sezione si apre (l'EpgGrid usa un
/// FocusNode esterno, senza autofocus proprio).
class _AutofocusGrid extends StatefulWidget {
  const _AutofocusGrid({required this.node});
  final FocusNode node;

  @override
  State<_AutofocusGrid> createState() => _AutofocusGridState();
}

class _AutofocusGridState extends State<_AutofocusGrid> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.node.context == null) return;
      final primary = FocusManager.instance.primaryFocus;
      // Solo se il focus non è già altrove nel contenuto.
      if (primary == null ||
          primary.context == null ||
          !_insideContent(primary)) {
        widget.node.requestFocus();
      }
    });
  }

  bool _insideContent(FocusNode n) =>
      FocusScope.of(context).traversalDescendants.contains(n);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
