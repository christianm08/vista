import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/channel_logos.dart';
import '../theme.dart';

/// Logo del canale: quello scelto dall'utente, tv-logos (link raw di GitHub),
/// `tvg-logo` della lista, infine le iniziali generate. Se un'immagine non si
/// carica si passa alla successiva.
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
    // L'indice tv-logos arriva da GitHub dopo l'avvio: ridisegna quando c'è.
    return ValueListenableBuilder(
      valueListenable: ChannelLogos.notifier,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final mono = _Monogram(
      text: channel.monogram,
      color: _tones[channel.key.hashCode.abs() % _tones.length],
      size: size,
    );
    final r = BorderRadius.circular(size * 0.28);
    final urls = ChannelLogos.candidates(channel);
    if (urls.isEmpty) return ClipRRect(borderRadius: r, child: mono);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();

    Widget image(int i) => Image.network(
      urls[i],
      key: ValueKey(urls[i]),
      fit: BoxFit.contain,
      cacheWidth: px,
      errorBuilder: (_, _, _) => i + 1 < urls.length ? image(i + 1) : mono,
    );

    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: size,
        height: size,
        color: VistaColors.glassHigh,
        padding: EdgeInsets.all(size * 0.12),
        child: image(0),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.text,
    required this.color,
    required this.size,
  });
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
