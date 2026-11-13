import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/focus_card.dart';

/// Elenco dei canali sopra il video (OK nel player): si cambia canale senza
/// uscire.
///
/// Scorrimento e focus restano del player: [scroll] porta il canale in onda
/// al centro, [currentFocus] è la sua riga, così all'apertura il focus ci va.
class LiveChannelList extends StatelessWidget {
  const LiveChannelList({
    super.key,
    required this.open,
    required this.channels,
    required this.currentIndex,
    required this.guide,
    required this.now,
    required this.isFavorite,
    required this.scroll,
    required this.currentFocus,
    required this.onPick,
    required this.onToggleFavorite,
    required this.onClose,
  });

  /// Altezza di una riga, per centrare il canale in onda.
  static const rowHeight = 64.0;

  final bool open;
  final List<Channel> channels;
  final int currentIndex;
  final EpgGuide? guide;
  final DateTime now;
  final bool Function(Channel) isFavorite;
  final ScrollController scroll;
  final FocusNode currentFocus;
  final ValueChanged<int> onPick;
  final ValueChanged<Channel> onToggleFavorite;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeFocus(
        excluding: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Row(
            children: [
              Container(
                width: 360,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xF2080A0E), Color(0xD9080A0E)],
                  ),
                ),
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                        child: Row(
                          children: [
                            Text(
                              'Canali',
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            const VistaClock(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scroll,
                          itemExtent: rowHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: channels.length,
                          itemBuilder: (context, i) => _item(t, i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(TextTheme t, int i) {
    final c = channels[i];
    final onNow = guide?.nowOn(c, now: now);
    final playing = i == currentIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FocusCard(
        focusNode: playing ? currentFocus : null,
        radius: 12,
        focusScale: 1.02,
        fill: playing ? VistaColors.glassActive : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        onTap: () => onPick(i),
        onLongPress: () => onToggleFavorite(c),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(
                  color: playing
                      ? VistaColors.accent
                      : VistaColors.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ChannelLogo(channel: c, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (onNow != null)
                    Text(
                      onNow.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (isFavorite(c))
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: VistaColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
