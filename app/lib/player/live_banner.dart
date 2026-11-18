import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import 'stream_picker.dart';

/// Barra in basso del player dal vivo: canale, programma in onda e
/// successivo, pulsanti (preferiti, menu, Multiview, canale precedente,
/// flussi).
///
/// I focus restano del player: [firstChip] è il primo pulsante, a cui il
/// player porta il focus con Giù; Su dai pulsanti chiama [onLeaveChips].
class LiveBanner extends StatelessWidget {
  const LiveBanner({
    super.key,
    required this.channel,
    required this.guide,
    required this.now,
    required this.picker,
    required this.height,
    required this.favorite,
    required this.previous,
    required this.firstChip,
    required this.onChipsFocused,
    required this.onLeaveChips,
    required this.onToggleFavorite,
    required this.onOptions,
    required this.onMultiview,
    required this.onPrevious,
    required this.onAutoStream,
    required this.onPickStream,
  });

  final Channel channel;
  final EpgGuide? guide;
  final DateTime now;
  final StreamPicker picker;

  /// Altezza reale del video, se è già nota.
  final int? height;
  final bool favorite;
  final Channel? previous;
  final FocusNode firstChip;
  final ValueChanged<bool> onChipsFocused;
  final VoidCallback onLeaveChips;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOptions;
  final VoidCallback onMultiview;
  final VoidCallback onPrevious;
  final VoidCallback onAutoStream;
  final ValueChanged<int> onPickStream;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final layout = VistaLayout.of(context);
    final real = qualityFromHeight(height);
    final upcoming = guide?.upcoming(channel, now: now, count: 2) ?? const [];
    final current = upcoming.where((p) => p.isOnAt(now)).firstOrNull;
    final next = upcoming.where((p) => p.start.isAfter(now)).firstOrNull;
    final previous = this.previous;
    final meta = t.labelLarge?.copyWith(
      color: VistaColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: VistaScrims.playerBottomColors,
            stops: VistaScrims.playerBottomStops,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.gutter + layout.safe.left,
            VistaSpace.s64,
            layout.gutter + layout.safe.right,
            (layout.compact ? VistaSpace.s16 : VistaSpace.s24) +
                layout.safe.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChannelLogo(channel: channel, size: VistaSize.playerLogo),
                    const SizedBox(width: VistaSpace.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${channel.number} · ${channel.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                          Text(
                            current?.title ?? 'Nessuna informazione',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    if (!layout.compact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          VistaClock(style: t.titleLarge),
                          Text(
                            [
                              picker.auto ? 'Auto' : 'Manuale',
                              if (picker.streams.length > 1)
                                'flusso ${picker.index + 1}/${picker.streams.length}',
                              if (real.isNotEmpty) '$real · ${height}p',
                            ].join(' · '),
                            style: meta,
                          ),
                        ],
                      ),
                  ],
                ),
                if (current != null) ...[
                  const SizedBox(height: VistaSpace.s12),
                  Row(
                    children: [
                      Text(hhmm(current.start), style: meta),
                      const SizedBox(width: VistaSpace.s12),
                      Expanded(
                        child: VistaProgressBar(current.progressAt(now)),
                      ),
                      const SizedBox(width: VistaSpace.s12),
                      Text(hhmm(current.stop), style: meta),
                    ],
                  ),
                ],
                if (next != null) ...[
                  const SizedBox(height: VistaSpace.s8),
                  Text(
                    'Dopo · ${hhmm(next.start)}  ${next.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: VistaSpace.s8),
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: onChipsFocused,
                  onKeyEvent: (_, e) {
                    if (e is KeyUpEvent) return KeyEventResult.ignored;
                    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                      onLeaveChips();
                      return KeyEventResult.handled;
                    }
                    // Sotto i pulsanti non c'è altro.
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Spazio e nessun ritaglio in alto e in basso: l'anello
                    // del pulsante a fuoco resta intero.
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(
                      vertical: VistaSpace.s8,
                    ),
                    child: Row(
                      children: [
                        _Chip(
                          favorite ? 'Preferito' : 'Aggiungi ai preferiti',
                          icon: favorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          onTap: onToggleFavorite,
                          focusNode: firstChip,
                        ),
                        _Chip(
                          'Audio, sottotitoli e flussi',
                          icon: Icons.tune_rounded,
                          onTap: onOptions,
                        ),
                        _Chip(
                          'Multiview',
                          icon: Icons.grid_view_rounded,
                          onTap: onMultiview,
                        ),
                        if (previous != null)
                          _Chip(
                            previous.name,
                            icon: Icons.undo_rounded,
                            onTap: onPrevious,
                          ),
                        if (picker.streams.length > 1) ...[
                          _Chip(
                            'Auto',
                            selected: picker.auto,
                            onTap: onAutoStream,
                          ),
                          for (var i = 0; i < picker.streams.length; i++)
                            _Chip(
                              _streamLabel(picker.streams, i),
                              selected: !picker.auto && picker.index == i,
                              onTap: () => onPickStream(i),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
    this.label, {
    required this.onTap,
    this.icon,
    this.selected = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: VistaSpace.s8),
    child: VistaChip(
      label: label,
      icon: icon,
      selected: selected,
      onSelected: onTap,
      focusNode: focusNode,
    ),
  );
}

/// Etichetta del flusso [i]: la qualità, numerata quando più flussi hanno la
/// stessa ("4K · 1", "4K · 2").
String _streamLabel(List<ChannelStream> streams, int i) {
  final label = streams[i].quality.label;
  final same = [
    for (var j = 0; j < streams.length; j++)
      if (streams[j].quality.label == label) j,
  ];
  return same.length > 1 ? '$label · ${same.indexOf(i) + 1}' : label;
}
