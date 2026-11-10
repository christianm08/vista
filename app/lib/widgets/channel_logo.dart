import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';

/// Logo del canale: `tvg-logo` della lista, altrimenti le iniziali generate.
/// (iptv-org `logos.json` e tv-logos verranno inseriti qui in mezzo.)
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.channel, this.size = 56});

  final Channel channel;
  final double size;

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
    final mono = _Monogram(
      text: channel.monogram,
      color: _tones[channel.key.hashCode.abs() % _tones.length],
      size: size,
    );
    final r = BorderRadius.circular(size * 0.28);
    if (channel.logo.isEmpty) return ClipRRect(borderRadius: r, child: mono);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: size,
        height: size,
        color: VistaColors.glassHigh,
        padding: EdgeInsets.all(size * 0.12),
        child: Image.network(
          channel.logo,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => mono,
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.text, required this.color, required this.size});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: color,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: size * (text.length > 3 ? 0.24 : 0.32),
          color: Colors.white,
        ),
      ),
    );
  }
}
