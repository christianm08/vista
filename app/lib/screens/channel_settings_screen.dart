import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/channel_logos.dart';
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
  return EdgeInsets.fromLTRB(wide ? 48 : 16, wide ? 32 : 16, wide ? 48 : 16, 40);
}

Widget _title(BuildContext context, String text, [String? subtitle]) {
  final t = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle, style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary)),
      ],
    ],
  );
}

// =============================================================================
// Elenco
// =============================================================================

/// Impostazioni dei canali: elenco con ricerca, da cui si apre la modifica.
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({super.key, required this.store});
  final SourceStore store;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
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
    final store = widget.store;
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: store.library,
          builder: (context, _, _) {
            final all = _channelsOf(store);
            final shown = all.where((c) => _matches(c, _search.text.trim())).toList();
            final edited = store.prefs.overrides.length + store.prefs.merges.length;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: _pagePadding(context).copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _title(
                          context,
                          'Canali',
                          'Rinomina, cambia icona o unisci i canali doppi. '
                              '${all.length} canali'
                              '${edited > 0 ? ' · $edited modifiche' : ''}.',
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
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ChannelRow(
                      channel: shown[i],
                      mergedCount: store.prefs.mergedInto(shown[i].key).length,
                      autofocus: i == 0,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ChannelEditScreen(store: store, channelKey: shown[i].key),
                      )),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.onTap,
    this.mergedCount = 0,
    this.autofocus = false,
  });

  final Channel channel;
  final VoidCallback onTap;
  final int mergedCount;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = channel;
    final notes = [
      if (c.renamed) 'era "${displayName(c.key)}"',
      c.sourceNames.length == 1 ? '1 voce' : '${c.sourceNames.length} voci',
      if (mergedCount > 0) mergedCount == 1 ? '1 canale unito' : '$mergedCount canali uniti',
      c.group,
    ];
    return FocusCard(
      autofocus: autofocus,
      radius: VistaRadius.poster,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          ChannelLogo(channel: c, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(notes.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
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
  const ChannelEditScreen({super.key, required this.store, required this.channelKey});

  final SourceStore store;
  final String channelKey;

  @override
  State<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends State<ChannelEditScreen> {
  late final _name = TextEditingController(text: _channel?.name ?? '');
  late final _logoSearch = TextEditingController(text: displayName(widget.channelKey));
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

  Future<void> _save(ChannelPrefs Function(ChannelPrefs) change, String done) async {
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
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _rename() {
    final name = _name.text.trim();
    final original = displayName(widget.channelKey);
    _save((p) => p.rename(widget.channelKey, name == original ? '' : name),
        'Nome salvato.');
  }

  void _resetName() {
    _name.text = displayName(widget.channelKey);
    _save((p) => p.rename(widget.channelKey, ''), 'Nome originale ripristinato.');
  }

  void _setLogo(String url) =>
      _save((p) => p.setLogo(widget.channelKey, url),
          url.isEmpty ? 'Torna il logo automatico.' : 'Icona aggiornata.');

  void _useLogoUrl() {
    final uri = Uri.tryParse(_logoUrl.text.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _toast('Il link deve iniziare con http:// o https://');
      return;
    }
    _setLogo(uri.toString());
  }

  Future<void> _addChannel() async {
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => _ChannelPickerScreen(store: _store, exclude: widget.channelKey),
    ));
    if (picked == null) return;
    await _save((p) => p.merge(picked, widget.channelKey),
        '${displayName(picked)} unito a questo canale.');
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
                    const Text('Questo canale non c\'è più: forse è stato unito a un altro.'),
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
                  const Positioned(top: 16, right: 16, child: CircularProgressIndicator()),
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
              Text(c.name, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                [
                  if (c.renamed) 'nome originale "${displayName(c.key)}"',
                  c.streams.length == 1 ? '1 flusso' : '${c.streams.length} flussi',
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
            Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: VistaColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            autofocus: true,
            onPressed: _busy
                ? null
                : () => _save((p) => p.setHidden(widget.channelKey, !c.hidden),
                    c.hidden ? 'Canale di nuovo visibile.' : 'Canale nascosto.'),
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
            FilledButton(onPressed: _busy ? null : _rename, child: const Text('Salva nome')),
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
        Text('Elenco dei loghi non ancora scaricato da GitHub: riprova tra poco.',
            style: t.bodySmall?.copyWith(color: VistaColors.textSecondary))
      else if (results.isEmpty)
        Text('Nessun logo trovato per "$_query".',
            style: t.bodySmall?.copyWith(color: VistaColors.textSecondary))
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
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    cacheWidth: 192,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
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
      Text('Voci della lista: ${c.sourceNames.join(' · ')}',
          style: t.bodySmall?.copyWith(color: VistaColors.textSecondary)),
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
              child: Text('Unito a mano: ${displayName(k)}',
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _save((p) => p.split(k), '${displayName(k)} separato.'),
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
        .where((c) => c.key != widget.exclude && _matches(c, _search.text.trim()))
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
                    _title(context, 'Quale canale unire?',
                        'Diventerà parte di ${displayName(widget.exclude)}.'),
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
