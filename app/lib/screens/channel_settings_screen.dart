import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/channel_logos.dart';
import '../data/image_cache.dart';
import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/channel_tile.dart';
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';

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

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  final _search = TextEditingController();
  final _channelScroll = ScrollController();
  String _category = _allChannels;
  bool _selecting = false;
  final _selected = <String>{};
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
    super.dispose();
  }

  /// Gruppi della lista nell'ordine in cui compaiono, con quanti canali hanno.
  List<(String, int)> _groups(List<Channel> all) {
    final counts = <String, int>{};
    for (final c in all) {
      counts[c.group] = (counts[c.group] ?? 0) + 1;
    }
    return [for (final e in counts.entries) (e.key, e.value)];
  }

  String _label(String category) => switch (category) {
    _allChannels => 'Tutti i canali',
    _hiddenChannels => 'Nascosti',
    '' => 'Senza categoria',
    final g => g,
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

  void _startSelecting([Channel? c]) => setState(() {
    _selecting = true;
    if (c != null) _selected.add(c.key);
  });

  void _stopSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
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
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
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
        body: SafeArea(
          child: ValueListenableBuilder(
            valueListenable: _store.library,
            builder: (context, _, _) {
              final all = _channelsOf(_store);
              final groups = _groups(all);
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
              final channels = _channelPane(inCategory, shown);
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
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    return FocusCard(
      autofocus: autofocus,
      selected: selected,
      radius: compact ? 999 : 12,
      focusScale: compact ? 1.04 : 1.02,
      outline: !compact || selected,
      fill: compact ? VistaColors.glass : Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 11),
      onTap: () => _pickCategory(id),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (id == _hiddenChannels) ...[
            Icon(
              Icons.visibility_off_outlined,
              size: 18,
              color: selected ? VistaColors.onPrimary : null,
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
    );
  }

  /// Destra: barra con le azioni della categoria o della selezione, poi i
  /// canali.
  Widget _channelPane(List<Channel> inCategory, List<Channel> shown) {
    final t = Theme.of(context).textTheme;
    final hiddenHere = inCategory.where((c) => c.hidden).length;
    final allSelected =
        shown.isNotEmpty && shown.every((c) => _selected.contains(c.key));
    final selectedChannels = [
      for (final c in inCategory)
        if (_selected.contains(c.key)) c,
    ];
    final canHide = selectedChannels.any((c) => !c.hidden);
    final canShow = selectedChannels.any((c) => c.hidden);
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
          OutlinedButton.icon(
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
          FilledButton.icon(
            onPressed: !_busy && canHide
                ? () => _setHidden(
                    selectedChannels.where((c) => !c.hidden).map((c) => c.key),
                    true,
                  )
                : null,
            icon: const Icon(Icons.visibility_off_outlined),
            label: const Text('Nascondi'),
          ),
          OutlinedButton.icon(
            onPressed: !_busy && canShow
                ? () => _setHidden(
                    selectedChannels.where((c) => c.hidden).map((c) => c.key),
                    false,
                  )
                : null,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Mostra'),
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
                  if (hiddenHere > 0 && _category != _hiddenChannels)
                    '$hiddenHere nascosti',
                ].join(' · '),
                style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: inCategory.isEmpty ? null : () => _startSelecting(),
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('Seleziona'),
          ),
          if (realGroup && hiddenHere < inCategory.length)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setHidden(
                      inCategory.where((c) => !c.hidden).map((c) => c.key),
                      true,
                    ),
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Nascondi la categoria'),
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
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = shown[i];
                    return _ChannelRow(
                      channel: c,
                      mergedCount: _store.prefs.mergedInto(c.key).length,
                      checked: _selecting ? _selected.contains(c.key) : null,
                      onTap: () => _selecting ? _toggle(c) : _openChannel(c),
                      onLongPress: () =>
                          _selecting ? _toggle(c) : _startSelecting(c),
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
      c.group,
    ];
    return FocusCard(
      autofocus: autofocus,
      radius: VistaRadius.poster,
      focusScale: 1.02,
      fill: checked == true ? VistaColors.glassActive : VistaColors.glass,
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
              color: checked! ? VistaColors.accent : VistaColors.textTertiary,
            ),
            const SizedBox(width: 12),
          ],
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
                  style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
                ),
              ],
            ),
          ),
          if (c.customLogo.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Pill('icona'),
            ),
          if (c.hidden)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Pill('nascosto', filled: true),
            ),
        ],
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
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
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
                    _section('Nome', _nameSection(c)),
                    _section('Icona', _logoSection(c)),
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
                  c.group,
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
      child: Glass(
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

  List<Widget> _visibilitySection(Channel c) => [
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
                c.hidden ? 'Canale di nuovo visibile.' : 'Canale nascosto.',
              ),
        child: Text(c.hidden ? 'Mostra il canale' : 'Nascondi il canale'),
      ),
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
        style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
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
                  radius: 20,
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

  List<Widget> _mergeSection(Channel c) {
    final t = Theme.of(context).textTheme;
    final merged = _store.prefs.mergedInto(c.key);
    return [
      Text(
        'Unisci qui i canali doppi: i loro flussi diventano alternative di '
        'questo canale, ordinate per qualità.',
        style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
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
