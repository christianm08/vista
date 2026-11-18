import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/channel_logos.dart';
import '../data/image_cache.dart';
import '../theme.dart';

/// Logo del canale: quello scelto dall'utente, tv-logos (link raw di GitHub),
/// `tvg-logo` della lista, infine le iniziali generate. Se un'immagine non si
/// carica si passa alla successiva.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 56,
    this.boxed = true,
  });

  final Channel channel;
  final double size;

  /// Con un fondo suo; senza, il logo sta direttamente sulla superficie
  /// (card dei canali, anteprima).
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    // L'indice tv-logos arriva da GitHub dopo l'avvio: ridisegna quando c'è.
    return ValueListenableBuilder(
      valueListenable: ChannelLogos.notifier,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final mono = _Monogram(text: channel.monogram, size: size);
    final r = BorderRadius.circular(VistaRadius.chip);
    final urls = ChannelLogos.candidates(channel);
    if (urls.isEmpty) return ClipRRect(borderRadius: r, child: mono);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();

    Widget image(int i) => Image(
      image: ResizeImage.resizeIfNeeded(px, null, CachedNetImage(urls[i])),
      key: ValueKey(urls[i]),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => i + 1 < urls.length ? image(i + 1) : mono,
    );

    if (!boxed) {
      return SizedBox.square(dimension: size, child: image(0));
    }
    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: size,
        height: size,
        color: VistaColors.surfaceHigh,
        padding: EdgeInsets.all(size * _inset),
        child: image(0),
      ),
    );
  }

  /// Margine del logo dentro il riquadro, in frazione del lato.
  static const _inset = 0.12;
}

/// Iniziali del canale su superficie neutra: niente colori decorativi.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: VistaColors.surfaceHigh,
      child: Text(
        text,
        maxLines: 1,
        // Il corpo segue il riquadro, che va da 36 a 200 punti.
        style: t.titleSmall?.copyWith(
          fontFamily: VistaType.display,
          fontSize: size * (text.length > 3 ? 0.24 : 0.32),
          color: VistaColors.textSecondary,
        ),
      ),
    );
  }
}
