import 'package:flutter/material.dart';

import '../theme.dart';
import 'vista_focus.dart';

/// Barra di avanzamento: riempimento con l'accento.
///
/// Sopra un'immagine ([onImage]) ha la traccia chiara e gli estremi dritti
/// (la ritaglia il raggio della card); altrove è una pillola sul contorno.
class VistaProgressBar extends StatelessWidget {
  const VistaProgressBar(this.value, {super.key, this.onImage = false});
  final double value;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final radius = onImage
        ? BorderRadius.zero
        : BorderRadius.circular(VistaRadius.full);
    return SizedBox(
      height: VistaSize.progress,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: onImage ? VistaColors.trackOnImage : VistaColors.outline,
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: VistaColors.accent,
                  borderRadius: radius,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etichetta piccola sopra un'immagine: "IPTV", "IN ONDA" (con [dot]).
class VistaLabel extends StatelessWidget {
  const VistaLabel(this.text, {super.key, this.dot = false});
  final String text;

  /// Punto con l'accento davanti al testo ("in onda").
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VistaColors.background,
        borderRadius: BorderRadius.circular(VistaRadius.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VistaSpace.s8,
          vertical: VistaSpace.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              const SizedBox.square(
                dimension: VistaSpace.s8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: VistaColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: VistaSpace.s8),
            ],
            Text(text.toUpperCase(), style: t.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// Immagine mancante: superficie piena e il titolo in basso a sinistra.
class VistaArtFallback extends StatelessWidget {
  const VistaArtFallback(this.title, {super.key, this.showTitle = true});
  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ColoredBox(
      color: VistaColors.surface,
      child: showTitle
          ? Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(VistaSpace.s12),
                child: Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall,
                ),
              ),
            )
          : null,
    );
  }
}

/// Titolo e metadati sotto una card, in uno spazio di altezza fissa.
class _CardText extends StatelessWidget {
  const _CardText({
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final String title;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: layout.cardTextHeight,
        child: Padding(
          padding: EdgeInsets.only(top: layout.cardTextGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleSmall,
                // Righe alte uguali anche con caratteri non latini
                // (es. devanagari): il riquadro ha un'altezza fissa.
                strutStyle: StrutStyle.fromTextStyle(
                  t.titleSmall!,
                  forceStrutHeight: true,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: VistaSpace.s4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                  // Righe alte uguali anche con caratteri non latini
                  // (es. devanagari): il riquadro ha un'altezza fissa.
                  strutStyle: StrutStyle.fromTextStyle(
                    t.bodySmall!,
                    forceStrutHeight: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

int _cacheWidth(BuildContext context, double restWidth) =>
    (restWidth * MediaQuery.devicePixelRatioOf(context)).round();

/// Locandina 2:3. Col fuoco si ingrandisce solo l'immagine; titolo e
/// metadati restano fermi sotto (se [showText]).
///
/// [restWidth] è la larghezza a riposo: decide la risoluzione di decodifica,
/// che così non cambia durante l'animazione del fuoco.
class VistaPosterCard extends StatelessWidget {
  const VistaPosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.restWidth,
    required this.onTap,
    this.meta = '',
    this.label = '',
    this.progress,
    this.saved = false,
    this.showText = true,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.heroTag,
  });

  final String title;
  final String image;
  final double restWidth;
  final String meta;

  /// Elemento condiviso: la locandina vola nel backdrop del dettaglio che
  /// apre (vedi Nav). Unico nella pagina: lo forma chi costruisce la riga.
  final Object? heroTag;

  /// Etichetta in alto a sinistra (es. "IPTV").
  final String label;
  final double? progress;

  /// Nella mia lista: segnalibro in alto a destra.
  final bool saved;
  final bool showText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;

  static const aspect = 2 / 3;

  /// Altezza totale della card (immagine più testo, se c'è).
  static double heightFor(BuildContext context, double width, bool showText) =>
      width / aspect + (showText ? VistaLayout.of(context).cardTextHeight : 0);

  @override
  Widget build(BuildContext context) {
    final art = AspectRatio(
      aspectRatio: aspect,
      child: VistaFocusable(
        onTap: onTap,
        onLongPress: onLongPress,
        onFocusChange: onFocusChange,
        focusNode: focusNode,
        autofocus: autofocus,
        semanticLabel: title,
        child: _withHero(
          context,
          ClipRRect(
            borderRadius: BorderRadius.circular(VistaRadius.card),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(
                  image,
                  cacheWidth: _cacheWidth(context, restWidth),
                  // Il titolo nel riquadro solo se non è già scritto sotto.
                  fallback: VistaArtFallback(title, showTitle: !showText),
                ),
                if (label.isNotEmpty)
                  Positioned(
                    top: VistaSpace.s8,
                    left: VistaSpace.s8,
                    child: VistaLabel(label),
                  ),
                if (saved)
                  const Positioned(
                    top: VistaSpace.s8,
                    right: VistaSpace.s8,
                    child: Icon(
                      Icons.bookmark_rounded,
                      size: VistaSize.iconSmall,
                      color: VistaColors.text,
                    ),
                  ),
                if (progress != null && progress! > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VistaProgressBar(progress!, onImage: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!showText) return art;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        art,
        _CardText(title: title, meta: meta, onTap: onTap),
      ],
    );
  }
}

extension on VistaPosterCard {
  // Con le animazioni ridotte niente elemento condiviso.
  Widget _withHero(BuildContext context, Widget child) =>
      heroTag == null || MediaQuery.disableAnimationsOf(context)
      ? child
      : Hero(tag: heroTag!, child: child);
}

/// Card 16:9 con testo sotto: "Continua a guardare", canali, episodi.
class VistaWideCard extends StatelessWidget {
  const VistaWideCard({
    super.key,
    required this.title,
    required this.restWidth,
    required this.onTap,
    this.image = '',
    this.meta = '',
    this.progress,
    this.overlay,
    this.center,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
  });

  final String title;
  final String meta;
  final String image;
  final double restWidth;
  final double? progress;

  /// Sopra l'immagine, in alto a sinistra (es. [VistaLabel] "In onda").
  final Widget? overlay;

  /// Al centro al posto dell'immagine (es. logo o numero del canale).
  final Widget? center;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;

  static const aspect = 16 / 9;

  static double heightFor(BuildContext context, double width) =>
      width / aspect + VistaLayout.of(context).cardTextHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: VistaFocusable(
            onTap: onTap,
            onLongPress: onLongPress,
            onFocusChange: onFocusChange,
            focusNode: focusNode,
            autofocus: autofocus,
            semanticLabel: title,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VistaRadius.card),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (center != null)
                    ColoredBox(
                      color: VistaColors.surface,
                      child: Center(child: center),
                    )
                  else
                    NetImage(
                      image,
                      cacheWidth: _cacheWidth(context, restWidth),
                      fallback: VistaArtFallback(title, showTitle: false),
                    ),
                  if (overlay != null)
                    Positioned(
                      top: VistaSpace.s8,
                      left: VistaSpace.s8,
                      child: overlay!,
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VistaProgressBar(progress!, onImage: true),
                    ),
                ],
              ),
            ),
          ),
        ),
        _CardText(title: title, meta: meta, onTap: onTap),
      ],
    );
  }
}

/// Segnaposto di caricamento: tinta piatta, grande quanto la card.
class VistaCardSkeleton extends StatelessWidget {
  const VistaCardSkeleton({super.key, required this.aspect, this.text = true});
  final double aspect;
  final bool text;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: VistaColors.surface,
              borderRadius: BorderRadius.circular(VistaRadius.card),
            ),
          ),
        ),
        if (text) SizedBox(height: layout.cardTextHeight),
      ],
    );
  }
}
