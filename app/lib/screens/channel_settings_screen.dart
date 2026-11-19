import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/channel_logos.dart';
import '../app_scope.dart';
import '../data/image_cache.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/channel_dialogs.dart';
import '../widgets/channel_logo.dart';
import '../widgets/channel_tile.dart';
import '../widgets/focus_card.dart';
import '../widgets/list_titles.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/vista_focus.dart';

/// Canali della fonte corrente, letti da [SourceStore.library] così le
/// schermate restano aggiornate dopo ogni modifica.
List<Channel> _channelsOf(SourceStore store) =>
    store.library.value?.catalog.live.channels ?? const [];

bool _matches(Channel c, String q) {
  if (q.isEmpty) return true;
  final s = q.toLowerCase();
  return c.name.toLowerCase().contains(s) || c.key.contains(s);
}

EdgeInsets _pagePadding(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  return EdgeInsets.fromLTRB(
    wide ? 48 : 16,
    wide ? 32 : 16,
    wide ? 48 : 16,
    40,
  );
}

Widget _title(BuildContext context, String text, [String? subtitle]) {
  final t = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
        ),
      ],
    ],
  );
}

// =============================================================================
// Elenco: categorie della lista a sinistra, canali a destra
// =============================================================================

/// Categorie speciali (le altre sono i gruppi della lista).
const _allChannels = '\u0000tutti';
const _hiddenChannels = '\u0000nascosti';

/// Gestione dei canali: a sinistra le categorie della lista, a destra i loro
/// canali. Da un canale si apre la modifica; con "Seleziona" (o tenendo
/// premuto un canale, o col tasto Menu) se ne scelgono più d'uno per
/// nasconderli o mostrarli insieme.
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({super.key, required this.store});
  final SourceStore store;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

/// Spazio attorno agli elenchi: l'anello del fuoco sta fuori dalla voce.
const _ring = VistaFocus.ringGap + VistaFocus.ringWidth;

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  /// Nomi delle categorie come si leggono (vedi [groupLabels]).
  var _names = <String, String>{};
  final _search = TextEditingController();
  final _channelScroll = ScrollController();
  String _category = _allChannels;
  bool _selecting = false;
  final _selected = <String>{};

  /// "Seleziona" e "Seleziona tutti": quando la barra cambia, il fuoco del
  /// telecomando passa dall'uno all'altro invece di perdersi. Due nodi
  /// distinti, così il pulsante nuovo riceve il fuoco e mostra l'anello.
  final _selectFocus = FocusNode();
  final _selectAllFocus = FocusNode();
  bool _busy = false;

  SourceStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _channelScroll.dispose();
    _selectFocus.dispose();
    _selectAllFocus.dispose();
    super.dispose();
  }

  /// Categorie nell'ordine scelto dall'utente (le altre come nella lista),
  /// con quanti canali hanno.
  List<(String, int)> _groups(List<Channel> all) {
    final counts = <String, int>{};
    for (final c in all) {
      counts[c.group] = (counts[c.group] ?? 0) + 1;
    }
    return [
      for (final g in _store.prefs.orderGroups(counts.keys)) (g, counts[g]!),
    ];
  }

  /// Salva una modifica alle preferenze dei canali e mostra [done].
  Future<bool> _save(
    ChannelPrefs Function(ChannelPrefs) change,
    String done,
  ) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await _store.updatePrefs(change(_store.prefs));
      _toast(done);
      return true;
    } catch (e) {
      _toast('Modifica non salvata: ${redactError(e)}');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameGroup() async {
    final from = _category;
    final name = await askText(
      context,
      title: 'Rinomina categoria',
      hint: 'Nome della categoria',
      initial: from,
      message: 'Se scegli il nome di un\'altra categoria, le due si uniscono.',
    );
    if (name == null || name.isEmpty || name == from || !mounted) return;
    final ok = await _save(
      (p) => p.renameGroup(from, name),
      'Categoria rinominata in "$name".',
    );
    if (ok && mounted) setState(() => _category = name);
  }

  Future<void> _setGroupHidden(String group, bool hide) => _save(
    (p) => p.setGroupHidden(group, hide),
    hide
        ? 'Categoria "${_label(group)}" nascosta, anche per i canali che '
              'arriveranno.'
        : 'Categoria "${_label(group)}" di nuovo visibile.',
  );

  /// Protegge col PIN (o libera) la categoria scelta. Togliere un blocco
  /// chiede il PIN.
  Future<void> _toggleGroupLock(String group) async {
    final parental = AppScope.of(context).parental;
    final locked = parental.lockedGroups.contains(group);
    if (locked &&
        !await parental.unlock(
          context,
          reason: 'Serve il PIN per sbloccare.',
        )) {
      return;
    }
    await parental.setGroupLocked(group, !locked);
    if (mounted) setState(() {});
    _toast(
      locked
          ? 'Categoria "${_label(group)}" non più protetta.'
          : 'Categoria "${_label(group)}" protetta dal PIN.',
    );
  }

  Future<void> _moveGroup(List<String> order, int delta) => _save(
    (p) => p.moveGroup(order, _category, delta),
    delta < 0 ? 'Categoria spostata più su.' : 'Categoria spostata più giù.',
  );

  Future<void> _moveSelected(List<String> groups) async {
    final keys = _selected.toList();
    if (keys.isEmpty) return;
    final to = await pickGroup(context, groups: groups, canReset: true);
    if (to == null || !mounted) return;
    final ok = await _save(
      (p) {
        var next = p;
        for (final k in keys) {
          next = next.moveToGroup(k, to);
        }
        return next;
      },
      to.isEmpty
          ? 'Canali tornati nella categoria della lista.'
          : (keys.length == 1
                ? '1 canale spostato in "$to".'
                : '${keys.length} canali spostati in "$to".'),
    );
    if (ok && mounted) _stopSelecting();
  }

  String _label(String category) => switch (category) {
    _allChannels => 'Tutti i canali',
    _hiddenChannels => 'Nascosti',
    '' => 'Senza categoria',
    final g => _names[g] ?? cleanGroupName(g),
  };

  /// Canali della categoria scelta (non filtrati dalla ricerca).
  List<Channel> _inCategory(List<Channel> all) => switch (_category) {
    _allChannels => all,
    _hiddenChannels => [
      for (final c in all)
        if (c.hidden) c,
    ],
    final g => [
      for (final c in all)
        if (c.group == g) c,
    ],
  };

  void _pickCategory(String id) {
    if (id == _category) return;
    setState(() {
      _category = id;
      _selected.clear();
    });
    if (_channelScroll.hasClients) _channelScroll.jumpTo(0);
  }

  void _toggle(Channel c) => setState(() {
    if (!_selected.remove(c.key)) _selected.add(c.key);
  });

  void _startSelecting([Channel? c]) {
    if (_selectFocus.hasFocus) _focusLater(_selectAllFocus);
    setState(() {
      _selecting = true;
      if (c != null) _selected.add(c.key);
    });
  }

  void _stopSelecting() {
    // Dalla barra (Annulla, un'azione) si torna su "Seleziona".
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<_ChannelRow>() ==
        null) {
      _focusLater(_selectFocus);
    }
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// Il pulsante a fuoco sparisce: il fuoco va a [node] nella nuova barra.
  void _focusLater(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });

  Future<void> _setHidden(Iterable<String> keys, bool hide) async {
    final list = keys.toList();
    if (list.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _store.updatePrefs(_store.prefs.setHiddenAll(list, hide));
      final n = list.length;
      _toast(
        hide
            ? (n == 1 ? '1 canale nascosto.' : '$n canali nascosti.')
            : (n == 1
                  ? '1 canale di nuovo visibile.'
                  : '$n canali di nuovo visibili.'),
      );
      if (mounted) _stopSelecting();
    } catch (e) {
      _toast('Modifica non salvata: ${redactError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: VistaMotion.toast),
      );
  }

  void _openChannel(Channel c) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChannelEditScreen(store: _store, channelKey: c.key),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = Device.isTv || MediaQuery.sizeOf(context).width >= 700;
    return PopScope(
      // Indietro prima esce dalla selezione, poi dalla pagina.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: Scaffold(
        // Il fuoco non fa scorrere da solo: gli elenchi centrano la voce.
        body: FocusTraversalGroup(
          policy: VistaTraversalPolicy(),
          child: SafeArea(
            child: ValueListenableBuilder(
              valueListenable: _store.library,
              builder: (context, _, _) {
                final all = _channelsOf(_store);
                final groups = _groups(all);
                _names = groupLabels([for (final (g, _) in groups) g]);
                final hiddenCount = all.where((c) => c.hidden).length;
                // La categoria scelta può sparire (lista aggiornata, nessun
                // canale più nascosto): si torna a "Tutti".
                if (_category != _allChannels &&
                    !(_category == _hiddenChannels && hiddenCount > 0) &&
                    !groups.any((g) => g.$1 == _category)) {
                  _category = _allChannels;
                }
                final inCategory = _inCategory(all);
                final q = _search.text.trim();
                final shown = [
                  for (final c in inCategory)
                    if (_matches(c, q)) c,
                ];
                final categories = [
                  (_allChannels, all.length),
                  if (hiddenCount > 0) (_hiddenChannels, hiddenCount),
                  ...groups,
                ];
                final edited =
                    _store.prefs.overrides.length + _store.prefs.merges.length;
                final header = _title(
                  context,
                  'Canali',
                  '${all.length} canali in ${groups.length} categorie'
                      '${hiddenCount > 0 ? ' · $hiddenCount nascosti' : ''}'
                      '${edited > 0 ? ' · $edited modifiche' : ''}.',
                );
                final search = TvTextField(
                  controller: _search,
                  hint: 'Cerca un canale',
                  prefixIcon: const Icon(Icons.search_rounded),
                );
                final channels = _channelPane(inCategory, shown, [
                  for (final (g, _) in groups) g,
                ]);
                final pad = _pagePadding(context).copyWith(bottom: 16);
                if (!wide) {
                  return Padding(
                    padding: pad,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: 14),
                        search,
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 44 + 2 * _ring,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.all(_ring),
                            itemCount: categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) =>
                                _categoryChip(categories[i], compact: true),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: channels),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 18),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 300,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  search,
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.all(_ring),
                                      itemCount: categories.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 6),
                                      itemBuilder: (_, i) => _categoryChip(
                                        categories[i],
                                        autofocus: i == 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: channels),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(
    (String, int) category, {
    bool compact = false,
    bool autofocus = false,
  }) {
    final (id, count) = category;
    final t = Theme.of(context).textTheme;
    final selected = id == _category;
    return VistaCenterOnFocus(
      child: FocusCard(
        autofocus: autofocus,
        selected: selected,
        radius: compact ? VistaRadius.full : VistaRadius.card,
        focusScale: 1.0,
        outline: !compact || selected,
        fill: compact ? VistaColors.surface : VistaColors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 8 : 11,
        ),
        onTap: () => _pickCategory(id),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (id == _hiddenChannels ||
                _store.prefs.hiddenGroups.contains(id)) ...[
              Icon(
                Icons.visibility_off_outlined,
                size: 18,
                color: selected ? VistaColors.onAccent : null,
              ),
              const SizedBox(width: 8),
            ],
            if (compact)
              Text(
                _label(id),
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              Expanded(
                child: Text(
                  _label(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: 10),
            Opacity(opacity: 0.65, child: Text('$count', style: t.labelMedium)),
          ],
        ),
      ),
    );
  }

  /// Destra: barra con le azioni della categoria o della selezione, poi i
  /// canali.
  Widget _channelPane(
    List<Channel> inCategory,
    List<Channel> shown,
    List<String> groupOrder,
  ) {
    final t = Theme.of(context).textTheme;
    // Nascosti uno per uno (quelli della categoria nascosta si mostrano
    // mostrando la categoria).
    final hiddenHere = inCategory
        .where((c) => c.hidden && !c.groupHidden)
        .length;
    final groupHidden = _store.prefs.hiddenGroups.contains(_category);
    final groupIndex = groupOrder.indexOf(_category);
    final allSelected =
        shown.isNotEmpty && shown.every((c) => _selected.contains(c.key));
    final selectedChannels = [
      for (final c in inCategory)
        if (_selected.contains(c.key)) c,
    ];
    final canHide = selectedChannels.any((c) => !c.hidden);
    final canShow = selectedChannels.any((c) => c.hidden && !c.groupHidden);
    final realGroup = _category != _allChannels && _category != _hiddenChannels;

    final Widget bar;
    if (_selecting) {
      bar = Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _selected.isEmpty
                ? 'Scegli i canali'
                : (_selected.length == 1
                      ? '1 selezionato'
                      : '${_selected.length} selezionati'),
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (Device.isTv)
            Text(
              'Menu: vai alle azioni',
              style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
            ),
          OutlinedButton.icon(
            focusNode: _selectAllFocus,
            onPressed: shown.isEmpty
                ? null
                : () => setState(() {
                    if (allSelected) {
                      _selected.removeAll(shown.map((c) => c.key));
                    } else {
                      _selected.addAll(shown.map((c) => c.key));
                    }
                  }),
            icon: Icon(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            ),
            label: Text(allSelected ? 'Deseleziona tutti' : 'Seleziona tutti'),
          ),
          // Solo le azioni che fanno qualcosa sui canali scelti.
          if (canHide)
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setHidden(
                      selectedChannels
                          .where((c) => !c.hidden)
                          .map((c) => c.key),
                      true,
                    ),
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Nascondi'),
            ),
          if (canShow)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setHidden(
                      selectedChannels
                          .where((c) => c.hidden && !c.groupHidden)
                          .map((c) => c.key),
                      false,
                    ),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Mostra'),
            ),
          if (_selected.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _moveSelected(groupOrder),
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('Sposta in…'),
            ),
          TextButton(onPressed: _stopSelecting, child: const Text('Annulla')),
        ],
      );
    } else {
      bar = Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label(_category),
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                [
                  inCategory.length == 1
                      ? '1 canale'
                      : '${inCategory.length} canali',
                  if (groupHidden) 'categoria nascosta',
                  if (Device.isTv && inCategory.isNotEmpty)
                    "Menu su un canale: scegline più d'uno",
                  if (hiddenHere > 0 && _category != _hiddenChannels)
                    '$hiddenHere nascosti',
                ].join(' · '),
                style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(width: 6),
          if (inCategory.isNotEmpty)
            OutlinedButton.icon(
              focusNode: _selectFocus,
              onPressed: () => _startSelecting(),
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('Seleziona'),
            ),
          if (realGroup)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setGroupHidden(_category, !groupHidden),
              icon: Icon(
                groupHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              label: Text(
                groupHidden ? 'Mostra la categoria' : 'Nascondi la categoria',
              ),
            ),
          if (realGroup && AppScope.of(context).parental.enabled)
            OutlinedButton.icon(
              onPressed: () => _toggleGroupLock(_category),
              icon: Icon(
                AppScope.of(context).parental.lockedGroups.contains(_category)
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              label: Text(
                AppScope.of(context).parental.lockedGroups.contains(_category)
                    ? 'Togli il PIN'
                    : 'Proteggi col PIN',
              ),
            ),
          if (realGroup)
            OutlinedButton.icon(
              onPressed: _busy ? null : _renameGroup,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rinomina'),
            ),
          if (realGroup && groupIndex > 0)
            IconButton.outlined(
              tooltip: 'Sposta la categoria più su',
              onPressed: _busy ? null : () => _moveGroup(groupOrder, -1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          if (realGroup &&
              groupIndex >= 0 &&
              groupIndex < groupOrder.length - 1)
            IconButton.outlined(
              tooltip: 'Sposta la categoria più giù',
              onPressed: _busy ? null : () => _moveGroup(groupOrder, 1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          if ((realGroup || _category == _hiddenChannels) && hiddenHere > 0)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setHidden(
                      inCategory.where((c) => c.hidden).map((c) => c.key),
                      false,
                    ),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(
                _category == _hiddenChannels
                    ? 'Mostra tutti'
                    : 'Mostra i nascosti',
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        const SizedBox(height: 14),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    _search.text.trim().isEmpty
                        ? 'Nessun canale in questa categoria.'
                        : 'Nessun canale trovato per "${_search.text.trim()}".',
                    style: t.bodyMedium?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  controller: _channelScroll,
                  padding: const EdgeInsets.all(_ring),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = shown[i];
                    return _ChannelRow(
                      channel: c,
                      mergedCount: _store.prefs.mergedInto(c.key).length,
                      checked: _selecting ? _selected.contains(c.key) : null,
                      onTap: () => _selecting ? _toggle(c) : _openChannel(c),
                      // Menu: entra nella selezione; già dentro, porta
                      // alle azioni senza risalire tutto l'elenco.
                      onLongPress: () => _selecting
                          ? _selectAllFocus.requestFocus()
                          : _startSelecting(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    this.mergedCount = 0,
    this.autofocus = false,
    this.checked,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int mergedCount;
  final bool autofocus;

  /// In modalità selezione: se il canale è selezionato; `null` altrimenti.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = channel;
    final notes = [
      if (c.renamed) 'era "${displayName(c.key)}"',
      c.sourceNames.length == 1 ? '1 voce' : '${c.sourceNames.length} voci',
      if (mergedCount > 0)
        mergedCount == 1 ? '1 canale unito' : '$mergedCount canali uniti',
      cleanGroupName(c.group),
    ];
    return VistaCenterOnFocus(
      child: FocusCard(
        autofocus: autofocus,
        radius: VistaRadius.card,
        focusScale: 1.0,
        fill: checked == true
            ? VistaColors.surfaceSelected
            : VistaColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            if (checked != null) ...[
              Icon(
                checked!
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: checked!
                    ? VistaColors.accent
                    : VistaColors.textSecondary,
              ),
              const SizedBox(width: 12),
            ],
            SizedBox(
              width: 40,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.renumbered
                      ? VistaColors.accent
                      : VistaColors.textSecondary,
                ),
              ),
            ),
            Opacity(
              opacity: c.hidden ? 0.45 : 1,
              child: ChannelLogo(channel: c, size: 48),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.hidden ? VistaColors.textSecondary : null,
                    ),
                  ),
                  Text(
                    notes.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (AppScope.of(context).parental.isLocked(c))
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: VistaColors.accent,
                ),
              ),
            if (c.customLogo.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Pill('icona'),
              ),
            if (c.hidden)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Pill(
                  c.groupHidden ? 'categoria nascosta' : 'nascosto',
                  filled: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Modifica di un canale
// =============================================================================

/// Nome, icona e raggruppamento di un canale.
class ChannelEditScreen extends StatefulWidget {
  const ChannelEditScreen({
    super.key,
    required this.store,
    required this.channelKey,
  });

  final SourceStore store;
  final String channelKey;

  @override
  State<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends State<ChannelEditScreen> {
  late final _name = TextEditingController(text: _channel?.name ?? '');
  late final _logoSearch = TextEditingController(
    text: displayName(widget.channelKey),
  );
  final _logoUrl = TextEditingController();
  late String _query = _logoSearch.text;
  bool _busy = false;

  SourceStore get _store => widget.store;

  Channel? get _channel {
    for (final c in _channelsOf(_store)) {
      if (c.key == widget.channelKey) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _logoSearch.dispose();
    _logoUrl.dispose();
    super.dispose();
  }

  Future<void> _save(
    ChannelPrefs Function(ChannelPrefs) change,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await _store.updatePrefs(change(_store.prefs));
      _toast(done);
    } catch (e) {
      _toast('Modifica non salvata: ${redactError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: VistaMotion.toast),
      );
  }

  void _rename() {
    final name = _name.text.trim();
    final original = displayName(widget.channelKey);
    _save(
      (p) => p.rename(widget.channelKey, name == original ? '' : name),
      'Nome salvato.',
    );
  }

  void _resetName() {
    _name.text = displayName(widget.channelKey);
    _save(
      (p) => p.rename(widget.channelKey, ''),
      'Nome originale ripristinato.',
    );
  }

  void _setLogo(String url) => _save(
    (p) => p.setLogo(widget.channelKey, url),
    url.isEmpty ? 'Torna il logo automatico.' : 'Icona aggiornata.',
  );

  void _useLogoUrl() {
    final uri = Uri.tryParse(_logoUrl.text.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _toast('Il link deve iniziare con http:// o https://');
      return;
    }
    _setLogo(uri.toString());
  }

  void _setEpg(String id) => _save(
    (p) => p.setEpg(widget.channelKey, id),
    id.isEmpty ? "Torna l'abbinamento automatico." : 'Guida aggiornata.',
  );

  Future<void> _pickEpg(EpgGuide guide, String current) async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _EpgPickerScreen(guide: guide, current: current),
      ),
    );
    if (picked != null) _setEpg(picked);
  }

  Future<void> _addChannel() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            _ChannelPickerScreen(store: _store, exclude: widget.channelKey),
      ),
    );
    if (picked == null) return;
    await _save(
      (p) => p.merge(picked, widget.channelKey),
      '${displayName(picked)} unito a questo canale.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: _store.library,
          builder: (context, _, _) {
            final c = _channel;
            if (c == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Questo canale non c\'è più: forse è stato unito a un altro.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Indietro'),
                    ),
                  ],
                ),
              );
            }
            return Stack(
              children: [
                ListView(
                  padding: _pagePadding(context),
                  children: [
                    _header(c),
                    _section('Visibilità', _visibilitySection(c)),
                    if (AppScope.of(context).parental.enabled)
                      _section('PIN', _lockSection(c)),
                    _section('Numero e categoria', _placeSection(c)),
                    _section('Nome', _nameSection(c)),
                    _section('Icona', _logoSection(c)),
                    _section('Guida TV', _epgSection(c)),
                    _section('Raggruppa', _mergeSection(c)),
                  ],
                ),
                if (_busy)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: CircularProgressIndicator(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Channel c) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        ChannelLogo(channel: c, size: 88),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.name,
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                [
                  if (c.renamed) 'nome originale "${displayName(c.key)}"',
                  c.streams.length == 1
                      ? '1 flusso'
                      : '${c.streams.length} flussi',
                  cleanGroupName(c.group),
                ].join(' · '),
                style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: VistaPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _visibilitySection(Channel c) => c.groupHidden
      ? [
          Text(
            'Nascosto perché è nascosta la categoria '
            '"${cleanGroupName(c.group)}".',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: VistaColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              autofocus: true,
              onPressed: _busy
                  ? null
                  : () => _save(
                      (p) => p.setGroupHidden(c.group, false),
                      'Categoria "${cleanGroupName(c.group)}" di nuovo visibile.',
                    ),
              child: const Text('Mostra la categoria'),
            ),
          ),
        ]
      : [
          Text(
            c.hidden
                ? 'Nascosto: non compare in Live né nella guida.'
                : 'Visibile in Live e nella guida.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: VistaColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              autofocus: true,
              onPressed: _busy
                  ? null
                  : () => _save(
                      (p) => p.setHidden(widget.channelKey, !c.hidden),
                      c.hidden
                          ? 'Canale di nuovo visibile.'
                          : 'Canale nascosto.',
                    ),
              child: Text(c.hidden ? 'Mostra il canale' : 'Nascondi il canale'),
            ),
          ),
        ];

  Future<void> _toggleLock(Channel c) async {
    final parental = AppScope.of(context).parental;
    final locked = parental.lockedChannels.contains(c.key);
    if (locked &&
        !await parental.unlock(
          context,
          reason: 'Serve il PIN per sbloccare.',
        )) {
      return;
    }
    await parental.setChannelLocked(c.key, !locked);
    if (mounted) setState(() {});
    _toast(locked ? 'Canale non più protetto.' : 'Canale protetto dal PIN.');
  }

  Future<void> _changeNumber(Channel c) async {
    final n = await askChannelNumber(
      context,
      channelName: c.name,
      current: c.number,
      custom: c.renumbered,
    );
    if (n == null || !mounted) return;
    await _save(
      (p) => p.setNumber(widget.channelKey, n == 0 ? null : n),
      n == 0 ? 'Torna il numero della lista.' : 'Ora è il canale $n.',
    );
  }

  Future<void> _changeGroup(Channel c) async {
    final groups = <String>{for (final ch in _channelsOf(_store)) ch.group};
    final moved =
        (_store.prefs.overrides[widget.channelKey]?.group ?? '').isNotEmpty;
    final to = await pickGroup(
      context,
      groups: _store.prefs.orderGroups(groups),
      current: c.group,
      canReset: moved,
    );
    if (to == null || to == c.group || !mounted) return;
    await _save(
      (p) => p.moveToGroup(widget.channelKey, to),
      to.isEmpty
          ? 'Tornato nella categoria della lista.'
          : 'Spostato in "$to".',
    );
  }

  List<Widget> _lockSection(Channel c) {
    final parental = AppScope.of(context).parental;
    final own = parental.lockedChannels.contains(c.key);
    final byGroup = parental.lockedGroups.contains(c.group);
    return [
      Text(
        byGroup
            ? 'Protetto perché è protetta la categoria '
                  '"${cleanGroupName(c.group)}".'
            : (own ? 'Per guardarlo serve il PIN.' : 'Chiunque può guardarlo.'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: VistaColors.textSecondary),
      ),
      if (!byGroup) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _toggleLock(c),
            icon: Icon(
              own ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            ),
            label: Text(own ? 'Togli il PIN' : 'Proteggi col PIN'),
          ),
        ),
      ],
    ];
  }

  List<Widget> _placeSection(Channel c) => [
    Text(
      'Canale ${c.number}${c.renumbered ? ' (numero scelto da te)' : ''} · '
      'categoria "${c.group.isEmpty ? 'Senza categoria' : cleanGroupName(c.group)}"',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: VistaColors.textSecondary),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _changeNumber(c),
          icon: const Icon(Icons.pin_outlined),
          label: const Text('Cambia numero'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _changeGroup(c),
          icon: const Icon(Icons.drive_file_move_outline),
          label: const Text('Sposta in categoria'),
        ),
      ],
    ),
  ];

  List<Widget> _nameSection(Channel c) => [
    TvTextField(
      controller: _name,
      enabled: !_busy,
      hint: 'Nome del canale',
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _rename(),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton(
          onPressed: _busy ? null : _rename,
          child: const Text('Salva nome'),
        ),
        if (c.renamed)
          OutlinedButton(
            onPressed: _busy ? null : _resetName,
            child: const Text('Ripristina il nome originale'),
          ),
      ],
    ),
  ];

  List<Widget> _logoSection(Channel c) {
    final t = Theme.of(context).textTheme;
    final results = ChannelLogos.tvLogos.search(_query, limit: 30);
    return [
      Text(
        'Loghi di tv-logos (GitHub) che corrispondono alla ricerca, '
        'oppure un link a un\'immagine.',
        style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
      ),
      const SizedBox(height: 12),
      TvTextField(
        controller: _logoSearch,
        hint: 'Cerca fra i loghi, es. Rai 1',
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => setState(() => _query = _logoSearch.text),
          child: const Text('Cerca'),
        ),
      ),
      const SizedBox(height: 14),
      if (ChannelLogos.tvLogos.index.isEmpty)
        Text(
          'Elenco dei loghi non ancora scaricato da GitHub: riprova tra poco.',
          style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
        )
      else if (results.isEmpty)
        Text(
          'Nessun logo trovato per "$_query".',
          style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
        )
      else
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final url in results)
              SizedBox(
                width: 96,
                height: 96,
                child: FocusCard(
                  radius: VistaRadius.panel,
                  selected: c.customLogo == url,
                  padding: const EdgeInsets.all(12),
                  onTap: () => _setLogo(url),
                  child: Image(
                    image: ResizeImage(CachedNetImage(url), width: 192),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
          ],
        ),
      const SizedBox(height: 18),
      TvTextField(
        controller: _logoUrl,
        hint: 'https://… link a un\'immagine',
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _useLogoUrl(),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _useLogoUrl,
            child: const Text('Usa questo link'),
          ),
          if (c.customLogo.isNotEmpty)
            OutlinedButton(
              onPressed: _busy ? null : () => _setLogo(''),
              child: const Text('Logo automatico'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _epgSection(Channel c) {
    final t = Theme.of(context).textTheme;
    final guide = AppScope.of(context).epg.guide.value;
    final id = guide.matchedId(c);
    final on = guide.nowOn(c);
    final how = c.epgId.isEmpty ? 'automatico' : 'scelto da te';
    return [
      Text(
        guide.isEmpty
            ? 'Nessuna guida caricata.'
            : id.isEmpty
            ? 'Nessun canale della guida abbinato ($how).'
            : metaLine([
                'Abbinato a ${guide.channels[id] ?? id} ($how)',
                if (on != null) 'ora: ${on.title}',
              ]),
        style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton(
            onPressed: _busy || guide.isEmpty
                ? null
                : () => _pickEpg(guide, id),
            child: const Text('Scegli il canale della guida'),
          ),
          if (c.epgId.isNotEmpty)
            OutlinedButton(
              onPressed: _busy ? null : () => _setEpg(''),
              child: const Text('Abbinamento automatico'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _mergeSection(Channel c) {
    final t = Theme.of(context).textTheme;
    final merged = _store.prefs.mergedInto(c.key);
    return [
      Text(
        'Unisci qui i canali doppi: i loro flussi diventano alternative di '
        'questo canale, ordinate per qualità.',
        style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
      ),
      const SizedBox(height: 10),
      Text(
        'Voci della lista: ${c.sourceNames.join(' · ')}',
        style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _busy ? null : _addChannel,
          child: const Text('Unisci un altro canale a questo'),
        ),
      ),
      for (final k in merged) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Unito a mano: ${displayName(k)}',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () =>
                        _save((p) => p.split(k), '${displayName(k)} separato.'),
              child: const Text('Separa'),
            ),
          ],
        ),
      ],
    ];
  }
}

// =============================================================================
// Scelta del canale da unire
// =============================================================================

class _ChannelPickerScreen extends StatefulWidget {
  const _ChannelPickerScreen({required this.store, required this.exclude});
  final SourceStore store;
  final String exclude;

  @override
  State<_ChannelPickerScreen> createState() => _ChannelPickerScreenState();
}

class _ChannelPickerScreenState extends State<_ChannelPickerScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channelsOf(widget.store)
        .where(
          (c) => c.key != widget.exclude && _matches(c, _search.text.trim()),
        )
        .toList();
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: _pagePadding(context).copyWith(bottom: 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title(
                      context,
                      'Quale canale unire?',
                      'Diventerà parte di ${displayName(widget.exclude)}.',
                    ),
                    const SizedBox(height: 16),
                    TvTextField(controller: _search, hint: 'Cerca un canale'),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: _pagePadding(context).copyWith(top: 0),
              sliver: SliverList.separated(
                itemCount: channels.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ChannelRow(
                  channel: channels[i],
                  autofocus: i == 0,
                  onTap: () => Navigator.of(context).pop(channels[i].key),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sceglie un canale fra quelli delle guide caricate; restituisce l'id XMLTV.
class _EpgPickerScreen extends StatefulWidget {
  const _EpgPickerScreen({required this.guide, required this.current});
  final EpgGuide guide;
  final String current;

  @override
  State<_EpgPickerScreen> createState() => _EpgPickerScreenState();
}

class _EpgPickerScreenState extends State<_EpgPickerScreen> {
  final _search = TextEditingController();
  // L'abbinamento attuale in cima, poi tutti per nome.
  late final _all = widget.guide.channels.entries.toList()
    ..sort((a, b) {
      final current =
          (b.key == widget.current ? 1 : 0) - (a.key == widget.current ? 1 : 0);
      if (current != 0) return current;
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Titolo in onda su un canale della guida, per riconoscerlo.
  String _onAir(String id, DateTime now) {
    for (final s in widget.guide.sources) {
      for (final p in s.programmes[id] ?? const <EpgProgramme>[]) {
        if (p.isOnAt(now)) return p.title;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in _all)
        if (q.isEmpty ||
            e.value.toLowerCase().contains(q) ||
            e.key.toLowerCase().contains(q))
          e,
    ];
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: VistaTraversalPolicy(),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: _pagePadding(context).copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _title(
                        context,
                        'Quale canale della guida?',
                        '${_all.length} canali nelle guide caricate.',
                      ),
                      const SizedBox(height: 16),
                      TvTextField(
                        controller: _search,
                        hint: 'Cerca per nome o id',
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: _pagePadding(context).copyWith(top: 0),
                sliver: SliverList.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: VistaSpace.s8),
                  itemBuilder: (_, i) {
                    final MapEntry(key: id, value: name) = shown[i];
                    return VistaCenterOnFocus(
                      child: FocusCard(
                        autofocus: i == 0,
                        radius: VistaRadius.card,
                        focusScale: 1.0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: VistaSpace.s16,
                          vertical: VistaSpace.s12,
                        ),
                        onTap: () => Navigator.of(context).pop(id),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall,
                            ),
                            Text(
                              metaLine([
                                if (id == widget.current) 'attuale',
                                id,
                                _onAir(id, now),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: VistaColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
