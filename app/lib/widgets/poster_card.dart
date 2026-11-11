import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_card.dart';

/// Colore di ripiego per i titoli senza immagine (fisso per titolo).
Color toneFor(String title) {
  const tones = [
    Color(0xFF1E5A61),
    Color(0xFF6E3F28),
    Color(0xFF3F3275),
    Color(0xFF2C5136),
    Color(0xFF5A2944),
    Color(0xFF2B4362),
  ];
  return tones[title.hashCode.abs() % tones.length];
}

/// Segnaposto: sfumatura col titolo, per locandine mancanti o rotte.
class TitlePlaceholder extends StatelessWidget {
  const TitlePlaceholder(this.title, {super.key, this.showText = true});
  final String title;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone, Color.lerp(tone, Colors.black, 0.6)!],
        ),
      ),
      child: showText
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.15,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// Barra di avanzamento sottile sul bordo inferiore di un'immagine.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip(this.value, {super.key});
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x66000000)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: const ColoredBox(color: VistaColors.accent),
          ),
        ],
      ),
    );
  }
}

/// Locandina 2:3 con titolo e didascalia sotto (stile Plex / Apple TV): col
/// focus si ingrandisce solo l'immagine.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.onLongPress,
    this.caption = '',
    this.badge = '',
    this.progress,
    this.favorite = false,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.showText = true,
  });

  final String title;
  final String image;
  final String caption;
  final String badge;

  /// Avanzamento 0–1, se iniziato.
  final double? progress;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final bool showText;

  /// Spazio sotto l'immagine per titolo e didascalia.
  static const textHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final art = FocusCard(
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      radius: VistaRadius.poster,
      focusScale: 1.06,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VistaRadius.poster - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, c) => NetImage(
                image,
                cacheWidth: (c.maxWidth * dpr).round().clamp(120, 480),
                placeholder: TitlePlaceholder(title),
              ),
            ),
            if (badge.isNotEmpty)
              Positioned(top: 6, left: 6, child: _Badge(badge)),
            if (favorite)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.bookmark_rounded,
                  size: 20,
                  color: VistaColors.accent,
                  shadows: [Shadow(blurRadius: 6)],
                ),
              ),
            if (progress != null && progress! > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ProgressStrip(progress!),
              ),
          ],
        ),
      ),
    );
    if (!showText) return AspectRatio(aspectRatio: 2 / 3, child: art);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(aspectRatio: 2 / 3, child: art),
          ),
        ),
        SizedBox(
          height: textHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (caption.isNotEmpty)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textTertiary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Scheda 16:9 con testo sotto: "Continua a guardare", canali, episodi.
class WideCard extends StatelessWidget {
  const WideCard({
    super.key,
    required this.title,
    required this.onTap,
    this.image = '',
    this.subtitle = '',
    this.progress,
    this.overlay,
    this.center,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  final String title;
  final String subtitle;
  final String image;
  final double? progress;

  /// Disegnato sopra l'immagine (es. etichetta "LIVE").
  final Widget? overlay;

  /// Al centro al posto dell'immagine (es. logo del canale).
  final Widget? center;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  static const textHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: FocusCard(
            autofocus: autofocus,
            focusNode: focusNode,
            onFocusChange: onFocusChange,
            radius: VistaRadius.poster,
            focusScale: 1.05,
            fill: const Color(0xFF141922),
            onTap: onTap,
            onLongPress: onLongPress,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VistaRadius.poster - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (center != null)
                    Center(child: center)
                  else
                    LayoutBuilder(
                      builder: (context, c) => NetImage(
                        image,
                        cacheWidth: (c.maxWidth * dpr).round().clamp(200, 640),
                        placeholder: TitlePlaceholder(title, showText: false),
                      ),
                    ),
                  if (center == null)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.55, 1],
                          colors: [Color(0x00000000), Color(0x99000000)],
                        ),
                      ),
                    ),
                  ?overlay,
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ProgressStrip(progress!),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: textHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: VistaColors.textTertiary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0B0D12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Etichetta rossa "LIVE".
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          'LIVE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
