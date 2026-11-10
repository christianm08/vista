import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/playlist_store.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/focus_card.dart';
import 'player_screen.dart';

/// Elenco dei canali risolti, con filtro per gruppo.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.playlist, required this.onChangeList});

  final StoredPlaylist playlist;
  final VoidCallback onChangeList;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  late ResolveResult _result;
  late List<String> _groups;
  String? _group; // null = tutti

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ChannelsScreen old) {
    super.didUpdateWidget(old);
    if (old.playlist != widget.playlist) _resolve();
  }

  void _resolve() {
    _result = widget.playlist.resolve();
    _groups = {for (final c in _result.channels) c.group}.toList();
    _group = null;
  }

  List<Channel> get _visible => _group == null
      ? _result.channels
      : _result.channels.where((c) => c.group == _group).toList();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6 || h >= 18) return 'Buonasera';
    if (h < 13) return 'Buongiorno';
    return 'Buon pomeriggio';
  }

  void _play(Channel c) {
    final list = _visible;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(channels: list, initialIndex: list.indexOf(c)),
    ));
  }

  Future<void> _confirmChange() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12161D),
        title: const Text('Cambiare lista?'),
        content: const Text('La lista attuale verrà rimossa da questo dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambia')),
        ],
      ),
    );
    if (ok == true) widget.onChangeList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900; // TV e PC: margini di sicurezza più ampi
    final side = wide ? 48.0 : 16.0;
    final r = _result.report;
    final channels = _visible;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, wide ? 32 : 16, side, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting(),
                              style: t.titleMedium?.copyWith(color: VistaColors.textSecondary)),
                          Text('Cosa guardiamo?',
                              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            '${r.entries} voci → ${r.channels} canali, ${r.merged} raggruppati',
                            style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    FocusCard(
                      radius: 999,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      onTap: _confirmChange,
                      child: const Text('Cambia lista',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: side, vertical: 10),
                  children: [
                    _chip('Tutti', null),
                    for (final g in _groups) _chip(g, g),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 8, side, 40),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: wide ? 300 : 420,
                  mainAxisExtent: wide ? 96 : 84,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: channels.length,
                itemBuilder: (_, i) => _ChannelTile(
                  channel: channels[i],
                  autofocus: i == 0,
                  onTap: () => _play(channels[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? group) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FocusCard(
        radius: 999,
        selected: _group == group,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onTap: () => setState(() => _group = group),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onTap, this.autofocus = false});

  final Channel channel;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final best = channel.bestQuality;
    return FocusCard(
      autofocus: autofocus,
      radius: VistaRadius.poster,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          ChannelLogo(channel: channel, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${channel.number}  ${channel.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  channel.streams.length > 1
                      ? '${channel.streams.length} flussi'
                      : '1 flusso',
                  style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
                ),
              ],
            ),
          ),
          if (best != Quality.auto) _QualityBadge(best.label),
        ],
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VistaColors.accent.withValues(alpha: 0.6)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: VistaColors.accent)),
    );
  }
}
