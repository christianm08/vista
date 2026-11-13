import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/focus_card.dart';
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
    final real = qualityFromHeight(height);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final upcoming = guide?.upcoming(channel, now: now, count: 2) ?? const [];
    final current = upcoming.where((p) => p.isOnAt(now)).firstOrNull;
    final next = upcoming.where((p) => p.start.isAfter(now)).firstOrNull;
    final previous = this.previous;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          wide ? 40 : 16,
          48,
          wide ? 40 : 16,
          wide ? 28 : 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xE6000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${channel.number}',
                    style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VistaColors.accent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ChannelLogo(channel: channel, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            color: VistaColors.textSecondary,
                          ),
                        ),
                        Text(
                          current?.title ??
                              'Nessuna informazione sul programma',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const VistaClock(),
                        Text(
                          [
                            picker.auto ? 'Auto' : 'Manuale',
                            if (picker.streams.length > 1)
                              'flusso ${picker.index + 1}/${picker.streams.length}',
                            if (real.isNotEmpty) '$real · ${height}p',
                          ].join(' · '),
                          style: t.bodySmall?.copyWith(
                            color: VistaColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      hhmm(current.start),
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: current.progressAt(now),
                          minHeight: 5,
                          backgroundColor: VistaColors.glassActive,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hhmm(current.stop),
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              if (next != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Dopo · ${hhmm(next.start)}  ${next.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    color: VistaColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
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
                  child: Row(
                    children: [
                      _Chip(
                        favorite ? '★ Preferito' : '☆ Aggiungi ai preferiti',
                        onTap: onToggleFavorite,
                        focusNode: firstChip,
                      ),
                      _Chip('⚙ Audio, sottotitoli e flussi', onTap: onOptions),
                      _Chip('▦ Multiview', onTap: onMultiview),
                      if (previous != null)
                        _Chip('↩ ${previous.name}', onTap: onPrevious),
                      if (picker.streams.length > 1) ...[
                        _Chip(
                          'Auto',
                          selected: picker.auto,
                          onTap: onAutoStream,
                        ),
                        for (var i = 0; i < picker.streams.length; i++)
                          _Chip(
                            picker.streams[i].quality.label,
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
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
    this.label, {
    required this.onTap,
    this.selected = false,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: FocusCard(
      focusNode: focusNode,
      radius: 999,
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}
