import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import 'channel_logo.dart';
import 'focus_card.dart';

/// Scheda di un canale live: logo, numero, nome, flussi e qualità migliore.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
  });

  final Channel channel;
  final VoidCallback onTap;

  /// Tocco lungo o tasto Menu del telecomando: impostazioni del canale.
  final VoidCallback? onLongPress;
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
      onLongPress: onLongPress,
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
          if (best != Quality.auto) Pill(best.label),
        ],
      ),
    );
  }
}

/// Etichetta a pillola color pesca (qualità, voto…).
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.filled = false});
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? VistaColors.accent : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VistaColors.accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: filled ? VistaColors.onPrimary : VistaColors.accent,
        ),
      ),
    );
  }
}
