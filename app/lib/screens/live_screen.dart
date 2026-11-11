import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/focus_card.dart';
import '../widgets/live_preview.dart';
import '../widgets/tv_drawer.dart';
import 'channel_settings_screen.dart';
import 'shell.dart';

/// Categorie speciali in cima all'elenco.
const _all = '\u0000tutti';
const _favorites = '\u0000preferiti';
const _recent = '\u0000recenti';

String _groupLabel(String g) => switch (g) {
  _all => 'Tutti i canali',
  _favorites => 'Preferiti',
  _recent => 'Visti di recente',
  _ => g,
};

/// TV in diretta. Su TV e PC: dettagli del programma e anteprima in alto,
/// guida a griglia sotto, categorie in un pannello laterale (sinistra
/// dall'ora attuale). Su telefono: categorie a scorrimento e lista canali.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  String _group = _all;
  bool _panel = false;
  bool _previewOn = true;
  GuideSelection? _selection;
  DateTime _now = DateTime.now();
  late final Timer _clock;
  final _gridFocus = FocusNode(debugLabel: 'guida');
  ShellController? _shell;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _shell = ShellController.maybeOf(context);
    _shell?.addBackHandler(_onBack);
    final user = AppScope.of(context).user;
    // Si parte dai preferiti, se ce ne sono.
    if (user.favorites.any((k) => k.startsWith('ch:'))) _group = _favorites;
  }

  @override
  void dispose() {
    _shell?.removeBackHandler(_onBack);
    _clock.cancel();
    _gridFocus.dispose();
    super.dispose();
  }

  bool _onBack() {
    if (_panel) {
      _closePanel();
      return true;
    }
    return false;
  }

  List<Channel> _visible(Catalog c, UserStore user) {
    final all = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];
    switch (_group) {
      case _all:
        return all;
      case _favorites:
        return [
          for (final ch in all)
            if (user.isFavorite(UserKey.channel(ch.key))) ch,
        ];
      case _recent:
        final byKey = {for (final ch in all) ch.key: ch};
        return [
          for (final k in user.recentChannels)
            if (byKey[k] != null) byKey[k]!,
        ];
      default:
        return [
          for (final ch in all)
            if (ch.group == _group) ch,
        ];
    }
  }

  List<(String, int)> _groups(Catalog c, UserStore user) {
    final all = [
      for (final ch in c.live.channels)
        if (!ch.hidden) ch,
    ];
    final counts = <String, int>{};
    for (final ch in all) {
      counts[ch.group] = (counts[ch.group] ?? 0) + 1;
    }
    final fav = all
        .where((ch) => user.isFavorite(UserKey.channel(ch.key)))
        .length;
    final rec = user.recentChannels
        .where((k) => all.any((ch) => ch.key == k))
        .length;
    return [
      (_all, all.length),
      if (fav > 0) (_favorites, fav),
      if (rec > 0) (_recent, rec),
      for (final e in counts.entries) (e.key, e.value),
    ];
  }

  void _pick(String g) {
    setState(() {
      _group = g;
      _selection = null;
    });
    _closePanel();
  }

  void _openPanel() => setState(() => _panel = true);

  void _closePanel() {
    setState(() => _panel = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _gridFocus.context != null) _gridFocus.requestFocus();
    });
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
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: Row(
          children: [
            ChannelLogo(channel: c, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'fav'),
            child: _ActionRow(
              fav ? Icons.star_rounded : Icons.star_outline_rounded,
              fav ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const _ActionRow(Icons.edit_outlined, 'Nome, logo e gruppo'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'fav') {
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
        final groups = _groups(lib.catalog, app.user);
        if (!groups.any((g) => g.$1 == _group)) _group = _all;
        final channels = _visible(lib.catalog, app.user);
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
    final height = MediaQuery.sizeOf(context).height;
    final selection =
        _selection != null && channels.contains(_selection!.channel)
        ? _selection
        : null;
    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: channels.isEmpty
                  ? Column(
                      children: [
                        _categoryButton(context, groups),
                        const Expanded(
                          child: EmptyState(
                            icon: Icons.live_tv_outlined,
                            title: 'Nessun canale qui',
                            message: 'Scegli un\'altra categoria.',
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: (height * 0.36).clamp(170.0, 300.0),
                          child: ValueListenableBuilder<String>(
                            valueListenable: app.epg.status,
                            builder: (context, status, _) => GuideHeader(
                              selection: selection,
                              now: _now,
                              category: _groupLabel(_group),
                              status: status,
                              preview: LivePreview(
                                channel: selection?.channel ?? channels.first,
                                enabled: _previewOn && !_panel,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: EpgGrid(
                            channels: channels,
                            guide: guide,
                            now: _now,
                            focusNode: _gridFocus,
                            onSelectionChanged: (s) =>
                                setState(() => _selection = s),
                            onPlay: (c) => _play(channels, c),
                            onEdit: _actions,
                            onOpenMenu: _openPanel,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        // L'autofocus della griglia: entrando nella sezione si è subito sui canali.
        if (channels.isNotEmpty) _AutofocusGrid(node: _gridFocus),
        Positioned.fill(
          // Se il focus esce dal pannello (es. verso la barra laterale) il
          // pannello si chiude senza riprendersi il focus.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (has) {
              if (!has && _panel) setState(() => _panel = false);
            },
            child: TvDrawer(
              open: _panel,
              title: 'Categorie',
              onClose: _closePanel,
              sections: const [],
              groups: [
                for (final (g, n) in groups)
                  DrawerEntry(
                    label: _groupLabel(g),
                    icon: switch (g) {
                      _favorites => Icons.star_rounded,
                      _recent => Icons.history_rounded,
                      _all => Icons.apps_rounded,
                      _ => null,
                    },
                    trailing: '$n',
                    selected: g == _group,
                    onTap: () => _pick(g),
                  ),
              ],
              actions: [
                DrawerEntry(
                  icon: Icons.tune_rounded,
                  label: 'Gestisci canali',
                  onTap: () async {
                    _closePanel();
                    setState(() => _previewOn = false);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelSettingsScreen(store: app.store),
                      ),
                    );
                    if (mounted) setState(() => _previewOn = true);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryButton(BuildContext context, List<(String, int)> groups) =>
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          autofocus: true,
          onPressed: _openPanel,
          icon: const Icon(Icons.list_rounded),
          label: Text(_groupLabel(_group)),
        ),
      );

  // ===== Telefono ==============================================================

  Widget _phone(
    BuildContext context,
    List<Channel> channels,
    List<(String, int)> groups,
    EpgGuide guide,
  ) {
    final t = Theme.of(context).textTheme;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'TV in diretta',
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Gestisci canali',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelSettingsScreen(
                          store: AppScope.of(context).store,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (g, n) = groups[i];
                return FocusCard(
                  radius: 999,
                  focusScale: 1.0,
                  selected: _group == g,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  onTap: () => setState(() => _group = g),
                  child: Text(
                    '${_groupLabel(g)}  $n',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
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
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 110),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(color: VistaColors.textTertiary),
              ),
            ),
            Container(
              width: 76,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF141922),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VistaColors.glassBorder),
              ),
              alignment: Alignment.center,
              child: ChannelLogo(channel: c, size: 40),
            ),
            const SizedBox(width: 12),
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
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (user.isFavorite(UserKey.channel(c.key))) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: VistaColors.accent,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    now == null ? c.group : '${hhmm(now.start)}  ${now.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                  if (now != null) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: now.progressAt(_now),
                        minHeight: 3,
                        backgroundColor: VistaColors.glassActive,
                      ),
                    ),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [Icon(icon, size: 22), const SizedBox(width: 14), Text(label)],
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
