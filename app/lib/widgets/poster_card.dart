import 'package:flutter/material.dart';

import '../theme.dart';
import 'channel_tile.dart';
import 'focus_card.dart';

/// Locandina 2:3 di un film o di una serie, come nel prototipo: immagine,
/// sfumatura in basso e titolo. Senza immagine usa un fondo a tinta unita.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.caption = '',
    this.badge = '',
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  final String title;
  final String image;
  final String caption;
  final String badge;
  final VoidCallback onTap;
  final bool autofocus;

  static const _tones = [
    Color(0xFF1E6B73),
    Color(0xFF8A4B2E),
    Color(0xFF4B3A8C),
    Color(0xFF2F5D3A),
    Color(0xFF6B2E4F),
    Color(0xFF2E4A6B),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tone = _tones[title.hashCode.abs() % _tones.length];
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone, Color.lerp(tone, Colors.black, 0.55)!],
        ),
      ),
    );
    return FocusCard(
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      radius: VistaRadius.poster,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VistaRadius.poster - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isEmpty)
              placeholder
            else
              Image.network(
                image,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (_, child, frame, sync) =>
                    sync || frame != null ? child : placeholder,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Color(0x00000000), Color(0xB3000000)],
                ),
              ),
            ),
            if (badge.isNotEmpty)
              Positioned(top: 8, right: 8, child: Pill(badge, filled: true)),
            Positioned(
              left: 11,
              right: 11,
              bottom: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      shadows: const [Shadow(blurRadius: 8)],
                    ),
                  ),
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
