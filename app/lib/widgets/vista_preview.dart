import 'package:flutter/material.dart';

import '../theme.dart';

/// Cosa mostra l'anteprima del contenuto a fuoco (Home, e più avanti Live).
class VistaPreviewData {
  const VistaPreviewData({
    required this.id,
    required this.title,
    this.kicker = '',
    this.meta = '',
    this.plot = '',
    this.note = '',
    this.backdrop = '',
    this.poster = '',
    this.art,
  });

  /// Identifica il contenuto (per le dissolvenze: stesso id, niente cambio).
  final String id;
  final String title;

  /// Sopratitolo in maiuscolo: tipo e dove si apre ("Serie · IPTV").
  final String kicker;

  /// Anno, genere, durata…
  final String meta;

  /// Una frase di trama.
  final String plot;

  /// Riga forte in fondo: "23 min rimanenti".
  final String note;

  /// Immagine orizzontale; se manca si usa [poster], intera a destra.
  final String backdrop;
  final String poster;

  /// Al posto del backdrop quando non c'è un'immagine (il logo del canale):
  /// grande, a destra, sfuma nel fondo con gli stessi veli.
  final Widget? art;
}

/// La prima frase di una trama (l'anteprima ne mostra una sola).
String firstSentence(String plot) {
  final text = plot.trim();
  final m = RegExp(r'^.+?[.!?](?=\s|$)').firstMatch(text);
  return m?.group(0) ?? text;
}

/// Backdrop del contenuto a fuoco: riempie la zona in alto a destra e sfuma
/// nel fondo con due veli. Cambia con una dissolvenza incrociata (che si
/// interrompe e riparte dallo stato corrente se il fuoco cambia ancora).
class VistaBackdrop extends StatelessWidget {
  const VistaBackdrop({super.key, required this.data});
  final VistaPreviewData? data;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final d = data;
    final url = d == null
        ? ''
        : (d.backdrop.isNotEmpty ? d.backdrop : d.poster);
    return LayoutBuilder(
      builder: (context, c) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: c.maxWidth * VistaScrims.imageStart,
              top: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: reduce
                    ? VistaMotion.reducedFade
                    : VistaMotion.backdropFade,
                switchInCurve: VistaMotion.standard,
                switchOutCurve: VistaMotion.standard,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(d?.art != null ? 'art:${d!.id}' : url),
                  child: d?.art != null
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: VistaSpace.s64,
                            ),
                            child: d!.art,
                          ),
                        )
                      : d == null || url.isEmpty
                      ? const SizedBox.expand()
                      : d.backdrop.isNotEmpty
                      ? NetImage(
                          d.backdrop,
                          cacheWidth:
                              (c.maxWidth * (1 - VistaScrims.imageStart) * dpr)
                                  .round(),
                          placeholder: const SizedBox.expand(),
                          fallback: const SizedBox.expand(),
                        )
                      // Solo la locandina: intera, appoggiata a destra.
                      : Align(
                          alignment: Alignment.centerRight,
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            // Anche il bordo sinistro della locandina sfuma:
                            // niente spigolo netto nel mezzo dello schermo.
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                NetImage(
                                  d.poster,
                                  cacheWidth: (c.maxHeight * 2 / 3 * dpr)
                                      .round(),
                                  placeholder: const SizedBox.expand(),
                                  fallback: const SizedBox.expand(),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: VistaScrims.horizontalColors,
                                      stops: VistaScrims.horizontalStops,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: VistaScrims.horizontalColors,
                  stops: VistaScrims.horizontalStops,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: VistaScrims.bottomColors,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Testo dell'anteprima: sopratitolo, titolo, metadati, una frase di trama,
/// una riga forte. L'unico elemento forte è il titolo.
class VistaPreviewText extends StatelessWidget {
  const VistaPreviewText({super.key, required this.data});
  final VistaPreviewData? data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final d = data;
    return AnimatedSwitcher(
      duration: reduce ? VistaMotion.reducedFade : VistaMotion.textFade,
      switchInCurve: VistaMotion.standard,
      switchOutCurve: VistaMotion.standard,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: d == null
          ? const SizedBox.shrink()
          : ConstrainedBox(
              key: ValueKey(d.id),
              constraints: const BoxConstraints(
                maxWidth: VistaSize.previewText,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d.kicker.isNotEmpty) ...[
                    Text(
                      d.kicker.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                        letterSpacing: VistaType.capsTracking,
                      ),
                    ),
                    const SizedBox(height: VistaSpace.s12),
                  ],
                  Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.displayMedium,
                  ),
                  if (d.meta.isNotEmpty) ...[
                    const SizedBox(height: VistaSpace.s12),
                    Text(
                      d.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ],
                  if (d.plot.isNotEmpty) ...[
                    const SizedBox(height: VistaSpace.s12),
                    Text(
                      firstSentence(d.plot),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(color: VistaColors.textBody),
                    ),
                  ],
                  if (d.note.isNotEmpty) ...[
                    const SizedBox(height: VistaSpace.s12),
                    Text(
                      d.note,
                      style: t.labelLarge?.copyWith(
                        fontWeight: VistaType.strong,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
