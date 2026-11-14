import 'package:flutter/material.dart';

import '../data/image_cache.dart';
import '../theme.dart';
import 'vista_cards.dart';
import 'vista_controls.dart';
import 'vista_preview.dart';
import 'vista_row.dart';

// Componenti della scheda di un titolo (dettaglio IPTV e dettaglio TMDB):
// la tinta presa dall'artwork, il backdrop su cui atterra la locandina,
// l'intestazione con titolo, azioni e servizi.

/// I colori del dettaglio che seguono l'artwork. L'accento non c'è: resta
/// sempre lo stesso.
@immutable
class DetailColors {
  const DetailColors({
    required this.tonal,
    required this.onTonal,
    required this.meta,
    required this.body,
  });

  /// Fondo dei pulsanti tonali e dei chip.
  final Color tonal;

  /// Testo e icone sopra [tonal].
  final Color onTonal;

  /// Metadati e sopratitolo.
  final Color meta;

  /// Trama.
  final Color body;

  static const neutral = DetailColors(
    tonal: VistaColors.surfaceHigh,
    onTonal: VistaColors.text,
    meta: VistaColors.textSecondary,
    body: VistaColors.textBody,
  );

  /// Ruoli M3 dello schema scuro: toni 17 (fondo), 90 e 80 (testo), quindi
  /// il contrasto resta sopra 4,5:1 qualunque sia l'artwork.
  factory DetailColors.fromScheme(ColorScheme s) => DetailColors(
    tonal: s.surfaceContainerHigh,
    onTonal: s.onSurface,
    meta: s.onSurfaceVariant,
    body: s.onSurface,
  );

  static DetailColors lerp(DetailColors a, DetailColors b, double t) =>
      DetailColors(
        tonal: Color.lerp(a.tonal, b.tonal, t)!,
        onTonal: Color.lerp(a.onTonal, b.onTonal, t)!,
        meta: Color.lerp(a.meta, b.meta, t)!,
        body: Color.lerp(a.body, b.body, t)!,
      );

  static DetailColors of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DetailColorsScope>()
          ?.colors ??
      neutral;

  @override
  bool operator ==(Object other) =>
      other is DetailColors &&
      other.tonal == tonal &&
      other.onTonal == onTonal &&
      other.meta == meta &&
      other.body == body;

  @override
  int get hashCode => Object.hash(tonal, onTonal, meta, body);
}

class _DetailColorsScope extends InheritedWidget {
  const _DetailColorsScope({required this.colors, required super.child});
  final DetailColors colors;

  @override
  bool updateShouldNotify(_DetailColorsScope old) => old.colors != colors;
}

class _ColorsTween extends Tween<DetailColors> {
  _ColorsTween({super.begin, super.end});

  @override
  DetailColors lerp(double t) => DetailColors.lerp(begin!, end!, t);
}

/// Ricava la tinta da [image] e la passa ai componenti sotto
/// ([DetailColors.of]).
///
/// Si calcola solo a transizione finita (durante il volo della locandina
/// non si decodifica niente in più) e si tiene in cache per indirizzo.
/// Si passa dai neutri alla tinta con una dissolvenza.
class DetailTint extends StatefulWidget {
  const DetailTint({super.key, required this.image, required this.child});
  final String image;
  final Widget child;

  @override
  State<DetailTint> createState() => _DetailTintState();
}

class _DetailTintState extends State<DetailTint> {
  static final _cache = <String, DetailColors>{};

  DetailColors _colors = DetailColors.neutral;
  Animation<double>? _route;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (identical(a, _route)) return;
    _route?.removeStatusListener(_status);
    _route = a;
    if (a == null || a.status == AnimationStatus.completed) {
      _start();
    } else {
      a.addStatusListener(_status);
    }
  }

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed) _start();
  }

  void _start() {
    if (_ready) return;
    _ready = true;
    _route?.removeStatusListener(_status);
    _load();
  }

  @override
  void didUpdateWidget(DetailTint old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image && _ready) _load();
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_status);
    super.dispose();
  }

  Future<void> _load() async {
    final url = widget.image;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return;
    final hit = _cache[url];
    if (hit != null) {
      setState(() => _colors = hit);
      return;
    }
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(CachedNetImage(url), width: VistaSize.tintSample),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      );
      final c = DetailColors.fromScheme(scheme);
      _cache[url] = c;
      if (mounted && widget.image == url) setState(() => _colors = c);
    } catch (_) {
      // Immagine illeggibile: restano i neutri.
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<DetailColors>(
      tween: _ColorsTween(begin: DetailColors.neutral, end: _colors),
      duration: reduce ? VistaMotion.reducedFade : VistaMotion.tint,
      curve: VistaMotion.standard,
      builder: (context, colors, child) =>
          _DetailColorsScope(colors: colors, child: child!),
      child: widget.child,
    );
  }
}

// --- backdrop e volo della locandina ------------------------------------------

/// Quanto dell'immagine resta visibile sotto un velo del colore [scrim]:
/// serve alle maschere, che usano solo l'opacità.
Color _visible(Color scrim) => VistaColors.text.withValues(alpha: 1 - scrim.a);

/// L'immagine del dettaglio come appare sotto i suoi veli, ma trasparente
/// dove il velo è pieno: durante il volo sta sopra la pagina, e il testo
/// sotto deve vedersi.
Widget _underScrims(Widget image, {required bool compact}) {
  if (compact) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [for (final c in VistaScrims.heroColors) _visible(c)],
        stops: VistaScrims.heroStops,
      ).createShader(r),
      child: image,
    );
  }
  // L'immagine comincia a [imageStart]: le fermate del velo orizzontale,
  // riportate alla sua larghezza.
  const start = VistaScrims.imageStart;
  final stops = [
    for (final s in VistaScrims.horizontalStops.skip(1))
      (s - start) / (1 - start),
  ];
  return ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => LinearGradient(
      colors: [for (final c in VistaScrims.bottomColors) _visible(c)],
      begin: Alignment.bottomCenter,
      end: Alignment.center,
    ).createShader(r),
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          for (final c in VistaScrims.horizontalColors.skip(1)) _visible(c),
        ],
        stops: stops,
      ).createShader(r),
      child: image,
    ),
  );
}

/// Volo locandina → dettaglio: il riquadro passa da quello della locandina a
/// quello del backdrop, e intanto la locandina sfuma nel backdrop. Al
/// ritorno lo stesso all'indietro (l'animazione è quella della rotta).
HeroFlightShuttleBuilder detailShuttle({required bool compact}) =>
    (context, animation, direction, fromContext, toContext) {
      final from = (fromContext.widget as Hero).child;
      final to = (toContext.widget as Hero).child;
      final push = direction == HeroFlightDirection.push;
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: ReverseAnimation(animation),
            child: push ? from : to,
          ),
          FadeTransition(
            opacity: animation,
            child: _underScrims(push ? to : from, compact: compact),
          ),
        ],
      );
    };

/// Backdrop del dettaglio: riempie l'intestazione e sfuma nel fondo.
///
/// Wide: come l'anteprima della Home, a destra con i due veli. Telefono: in
/// alto, a tutta larghezza, col velo dal basso. [heroTag] è dove atterra la
/// locandina da cui si è aperta la scheda.
class DetailBackdrop extends StatelessWidget {
  const DetailBackdrop({
    super.key,
    required this.id,
    required this.title,
    required this.backdrop,
    required this.poster,
    this.heroTag,
  });

  final String id;
  final String title;
  final String backdrop;
  final String poster;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    if (!layout.compact) {
      return VistaBackdrop(
        data: VistaPreviewData(
          id: id,
          title: title,
          backdrop: backdrop,
          poster: poster,
        ),
        heroTag: heroTag,
        flightShuttleBuilder: detailShuttle(compact: false),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final url = backdrop.isNotEmpty ? backdrop : poster;
    Widget image = NetImage(
      url,
      alignment: Alignment.topCenter,
      cacheWidth: (layout.width * dpr).round(),
      placeholder: const SizedBox.expand(),
      fallback: const SizedBox.expand(),
    );
    if (heroTag != null) {
      image = Hero(
        tag: heroTag!,
        flightShuttleBuilder: detailShuttle(compact: true),
        child: image,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: VistaScrims.heroColors,
              stops: VistaScrims.heroStops,
            ),
          ),
        ),
      ],
    );
  }
}

// --- intestazione ---------------------------------------------------------------

/// Prima "riga" della scheda: backdrop, sopratitolo, titolo, metadati,
/// trama, azioni, stato (caricamento o errore) e dove si guarda.
///
/// Sta dentro la [VistaRowsPage] come le altre righe: con il fuoco sulle
/// azioni la pagina è in cima; scendendo agli episodi esce in alto.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.id,
    required this.title,
    required this.backdrop,
    required this.poster,
    required this.actions,
    this.kicker = '',
    this.subtitle = '',
    this.meta = '',
    this.plot = '',
    this.notes = const [],
    this.status,
    this.availability,
    this.heroTag,
  });

  final String id;
  final String title;
  final String backdrop;
  final String poster;
  final List<Widget> actions;
  final String kicker;

  /// Sotto il titolo (il titolo originale).
  final String subtitle;
  final String meta;
  final String plot;

  /// Righe piccole sotto la trama: regia, cast, frase di lancio.
  final List<String> notes;

  /// Caricamento o errore.
  final Widget? status;

  /// "Disponibile su".
  final Widget? availability;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final colors = DetailColors.of(context);
    final t = Theme.of(context).textTheme;
    final compact = layout.compact;
    final top = MediaQuery.paddingOf(context).top + layout.safe.top;
    // Stesso margine delle righe sotto (stagioni, episodi, cast): un solo
    // bordo sinistro per tutta la pagina.
    final left = layout.gutter;
    final right = layout.gutter;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker.isNotEmpty) ...[
          Text(
            kicker.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(
              color: colors.meta,
              letterSpacing: VistaType.capsTracking,
            ),
          ),
          const SizedBox(height: VistaSpace.s12),
        ],
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.displayMedium,
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: VistaSpace.s4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: colors.meta),
          ),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: VistaSpace.s12),
          Text(meta, style: t.labelLarge?.copyWith(color: colors.meta)),
        ],
        if (plot.isNotEmpty) ...[
          const SizedBox(height: VistaSpace.s12),
          Text(
            plot,
            maxLines: compact ? 6 : 3,
            overflow: TextOverflow.ellipsis,
            style: t.bodyLarge?.copyWith(color: colors.body),
          ),
        ],
        for (final n in notes) ...[
          const SizedBox(height: VistaSpace.s8),
          Text(
            n,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: colors.meta),
          ),
        ],
      ],
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        left,
        compact
            ? top + VistaSize.phoneHero * VistaScrims.heroStops[1]
            : top + (layout.tv ? VistaSpace.s24 : VistaSpace.s64),
        right,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: VistaSize.detailText),
            child: text,
          ),
          const SizedBox(height: VistaSpace.s32),
          Wrap(
            spacing: VistaSpace.s16,
            runSpacing: VistaSpace.s12,
            children: actions,
          ),
          if (status != null) ...[
            const SizedBox(height: VistaSpace.s16),
            status!,
          ],
          if (availability != null) ...[
            const SizedBox(height: VistaSpace.s24),
            availability!,
          ],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: compact ? 0 : layout.height * VistaSize.detailHeader,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: compact ? null : 0,
            height: compact ? top + VistaSize.phoneHero : null,
            child: DetailBackdrop(
              id: id,
              title: title,
              backdrop: backdrop,
              poster: poster,
              heroTag: heroTag,
            ),
          ),
          content,
          // Su TV si torna indietro col telecomando; altrove serve il tasto.
          if (!layout.tv)
            Positioned(
              left: left,
              top: top + VistaSpace.s8,
              child: VistaIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Indietro',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Caricamento o errore sotto le azioni.
class DetailStatus extends StatelessWidget {
  const DetailStatus.loading({super.key}) : error = null, onRetry = null;
  const DetailStatus.error(String this.error, {super.key, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = error;
    if (e == null) {
      return const SizedBox.square(
        dimension: VistaSize.iconSmall,
        child: CircularProgressIndicator(),
      );
    }
    final colors = DetailColors.of(context);
    return Wrap(
      spacing: VistaSpace.s16,
      runSpacing: VistaSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(e, style: t.bodyMedium?.copyWith(color: VistaColors.error)),
        if (onRetry != null)
          VistaButton.tonal(
            label: 'Riprova',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
            tint: colors.tonal,
            onTint: colors.onTonal,
          ),
      ],
    );
  }
}

/// Pulsante tonale del dettaglio, con la tinta dell'artwork.
class DetailButton extends StatelessWidget {
  const DetailButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = DetailColors.of(context);
    return VistaButton.tonal(
      label: label,
      icon: icon,
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      tint: colors.tonal,
      onTint: colors.onTonal,
    );
  }
}

/// Riga di testo al posto di una riga di card ("Nessun episodio").
class DetailNote extends StatelessWidget {
  const DetailNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final g = VistaLayout.of(context).gutter;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: g),
      child: Text(
        text,
        style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
      ),
    );
  }
}

/// Le stagioni come chip, sopra la riga degli episodi.
class SeasonChips extends StatelessWidget {
  const SeasonChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final g = VistaLayout.of(context).gutter;
    // A capo, non a scorrimento: col telecomando ogni chip resta raggiungibile
    // senza che la fila debba scorrere.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: g),
      child: Wrap(
        spacing: VistaSpace.s8,
        runSpacing: VistaSpace.s8,
        children: [
          for (final (i, l) in labels.indexed)
            VistaChip(
              key: ValueKey('season:$l'),
              label: l,
              selected: i == selected,
              onSelected: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

/// Riga degli episodi in caricamento.
class EpisodesSkeleton extends StatelessWidget {
  const EpisodesSkeleton({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    return VistaRowSkeleton(
      title: title,
      itemWidth: layout.wideCardWidth,
      itemHeight: VistaWideCard.heightFor(context, layout.wideCardWidth),
      aspect: VistaWideCard.aspect,
    );
  }
}
