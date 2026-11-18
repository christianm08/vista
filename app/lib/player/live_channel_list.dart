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
  static const rowHeight = VistaSize.playerChannelRow;

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
    final layout = VistaLayout.of(context);
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeFocus(
        excluding: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? VistaMotion.reducedFade
              : VistaMotion.overlayFade,
          child: Row(
            children: [
              // Pannello opaco: niente video che passa sotto il testo.
              Container(
                width: VistaSize.playerChannelList + layout.safe.left,
                color: VistaColors.surface,
                padding: EdgeInsets.only(
                  left: layout.safe.left,
                  top: layout.safe.top,
                  bottom: layout.safe.bottom,
                ),
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          VistaSpace.s24,
                          VistaSpace.s24,
                          VistaSpace.s24,
                          VistaSpace.s12,
                        ),
                        child: Row(
                          children: [
                            Text('Canali', style: t.headlineSmall),
                            const Spacer(),
                            VistaClock(
                              style: t.labelLarge?.copyWith(
                                color: VistaColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scroll,
                          itemExtent: rowHeight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: VistaSpace.s16,
                            vertical: VistaSpace.s8,
                          ),
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
      // Lo spazio sotto è più largo di quanto sporge l'anello.
      padding: const EdgeInsets.only(bottom: VistaSpace.s8),
      child: FocusCard(
        focusNode: playing ? currentFocus : null,
        radius: VistaRadius.chip,
        focusScale: 1.0,
        // Il canale in onda: un gradino più chiaro, come nella guida.
        fill: playing ? VistaColors.surfaceHigh : VistaColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s8),
        onTap: () => onPick(i),
        onLongPress: () => onToggleFavorite(c),
        child: Row(
          children: [
            SizedBox(
              width: VistaSize.guideNumber,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(
                  color: playing ? VistaColors.text : VistaColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            ChannelLogo(channel: c, size: VistaSize.playerChannelLogo),
            const SizedBox(width: VistaSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall,
                  ),
                  if (onNow != null)
                    Text(
                      onNow.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (isFavorite(c))
              const Icon(
                Icons.star_rounded,
                size: VistaSize.iconSmall,
                color: VistaColors.textSecondary,
                semanticLabel: 'Preferito',
              ),
          ],
        ),
      ),
    );
  }
}
