// Token di design di Vista.
//
// È l'unico file dell'interfaccia in cui compaiono colori, raggi, spaziature e
// durate: componenti e schermate leggono solo da qui (vedi
// docs/vista-design-brief.md). I timer di logica (orologio, aggiornamento
// delle liste, promemoria) non sono token: restano nel loro codice.

import 'package:flutter/material.dart';

/// Colori. Fondo quasi nero, un solo accento, testo sempre ≥ 4,5:1.
abstract final class VistaColors {
  /// Sfondo di ogni schermata e di ogni pagina (opaco).
  static const background = Color(0xFF0C0D0C);

  /// Barre, celle della guida, pannelli, chip non selezionati.
  static const surface = Color(0xFF161816);

  /// Chip e celle "in onda", pulsanti tonali senza artwork.
  static const surfaceHigh = Color(0xFF1F221F);

  /// Voce di navigazione attiva, cella della guida a fuoco.
  static const surfaceSelected = Color(0xFF2A2F27);

  /// Separatori sottili, traccia delle barre su superficie.
  static const outline = Color(0xFF2E322D);

  /// Titoli e testo principale; fondo dei chip selezionati.
  static const text = Color(0xFFF2F3EE);

  /// Trame e descrizioni.
  static const textBody = Color(0xFFD4D7CF);

  /// Metadati, etichette, icone inattive.
  static const textSecondary = Color(0xFFA9ADA4);

  /// Riproduci, avanzamento, linea "adesso", punto "in onda", marchio.
  /// Due o tre presenze per schermata, non di più.
  static const accent = Color(0xFFC8F250);

  /// Testo e icone sopra l'accento.
  static const onAccent = Color(0xFF141A05);

  /// Anello di fuoco.
  static const focusRing = Color(0xFFFFFFFF);

  /// Solo testo e icone degli stati di errore.
  static const error = Color(0xFFFF8A7A);

  /// L'unica ombra: sotto l'elemento a fuoco.
  static const focusShadow = Color(0x99000000);

  /// Traccia della barra di avanzamento sopra un'immagine.
  static const trackOnImage = Color(0x47FFFFFF);

  /// Velo leggero sul tocco e sul passaggio del mouse (stato, non decoro).
  static const pressOverlay = Color(0x1FF2F3EE);
  static const hoverOverlay = Color(0x0FF2F3EE);

  static const transparent = Color(0x00000000);

  // --- Nomi dello stile "Vetro", tenuti finché le schermate non sono migrate
  // (fasi 3–6) e rimossi nella fase 7. Puntano ai nuovi token.
  static const teal = accent;
  static const peach = accent;
  static const violet = accent;
  static const onPrimary = onAccent;
  static const glass = surface;
  static const glassHigh = surfaceHigh;
  static const glassActive = surfaceSelected;
  static const glassBorder = outline;
  static const textTertiary = textSecondary;
}

/// Veli del backdrop: sfumano l'artwork nel fondo. Il testo sta solo dove il
/// velo copre almeno il 90%.
abstract final class VistaScrims {
  /// Da sinistra: pieno fino al 30%, 92% al 40%, trasparente dal 75%.
  /// Sotto la parte piena non c'è immagine (vedi [imageStart]).
  static const horizontalColors = [
    VistaColors.background,
    VistaColors.background,
    Color(0xEB0C0D0C),
    Color(0x000C0D0C),
  ];
  static const horizontalStops = [0.0, imageStart, 0.4, 0.75];

  /// Dove comincia l'immagine del backdrop (frazione della sua larghezza).
  /// Prima c'è solo il fondo: sotto un velo quasi opaco, su Windows, il
  /// motore di disegno lasciava passare una riga di 1 px dell'immagine.
  static const imageStart = 0.3;

  /// Dal basso: pieno sul bordo inferiore, trasparente in alto.
  static const bottomColors = [VistaColors.background, Color(0x000C0D0C)];

  /// Riquadro in evidenza del telefono: il testo sta nella metà bassa, che
  /// è coperta almeno al 92%.
  static const heroColors = [
    VistaColors.background,
    Color(0xEB0C0D0C),
    Color(0x000C0D0C),
  ];
  static const heroStops = [0.0, 0.5, 0.85];

  /// Dettaglio (wide): maschera che fa svanire il backdrop prima del fondo
  /// dell'intestazione, con una curva morbida (opaco = immagine visibile).
  /// Una maschera e non un velo: sotto un velo quasi pieno, su Windows,
  /// restava visibile la riga dove finisce l'immagine.
  static const detailFadeColors = [
    Color(0x00FFFFFF),
    Color(0x00FFFFFF),
    Color(0x40FFFFFF),
    Color(0xB3FFFFFF),
    Color(0xFFFFFFFF),
  ];
  static const detailFadeStops = [0.0, 0.06, 0.2, 0.36, 0.55];
}

/// Spaziature. Nessun altro valore.
abstract final class VistaSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s48 = 48.0;
  static const s64 = 64.0;
}

/// Raggi.
abstract final class VistaRadius {
  /// Chip, celle della guida, etichette, riquadro del logo del canale.
  static const chip = 8.0;

  /// Card, poster, anteprima del canale.
  static const card = 12.0;

  /// Pannelli, dialoghi, fogli.
  static const panel = 20.0;

  /// Pulsanti, indicatori, barre: forma a pillola.
  static const full = 999.0;

  // Nomi dello stile "Vetro" (fase 7: da rimuovere).
  static const hero = panel;
  static const poster = card;
}

/// Misure dei componenti (dimensioni, non spaziature).
abstract final class VistaSize {
  /// Sotto questa larghezza (e non su TV): layout da telefono.
  static const compactMaxWidth = 700.0;

  /// Da questa larghezza le card crescono (finestre grandi su PC).
  static const largeMinWidth = 1600.0;

  /// Tela della TV: l'app si disegna larga così e si scala sullo schermo.
  static const tvCanvasWidth = 1280.0;

  /// Area sicura della TV: 5% per lato.
  static const tvSafeFraction = 0.05;

  // Card 16:9 e poster 2:3: larghezza a riposo per telefono, wide, grande.
  static const wideCardCompact = 220.0;
  static const wideCard = 256.0;
  static const wideCardLarge = 300.0;
  static const posterCompact = 112.0;
  static const poster = 148.0;
  static const posterLarge = 168.0;

  /// Barra di avanzamento.
  static const progress = 4.0;

  /// Icone.
  static const icon = 24.0;
  static const iconSmall = 20.0;

  /// Bersaglio minimo al tocco.
  static const minTouch = 48.0;

  /// Pulsanti.
  static const button = 56.0;
  static const buttonCompact = 48.0;

  /// Chip.
  static const chip = 36.0;
  static const chipCompact = 32.0;

  /// Barra laterale: voce, larghezza aperta.
  static const railItemWidth = 56.0;
  static const railItemHeight = 48.0;
  static const railExpanded = 248.0;

  /// Barra in basso del telefono e indicatore della voce attiva.
  static const navBar = 80.0;
  static const navIndicator = Size(64, 32);

  /// Guida: altezza della riga e colonna dei canali.
  static const guideRow = 48.0;
  static const guideChannelColumn = 200.0;

  /// Zona fissa dell'anteprima in Home (wide) e riquadro in evidenza (telefono).
  static const homePreview = 300.0;
  static const phoneHero = 430.0;

  /// Colonna di testo dell'anteprima: sta dove il velo del backdrop è pieno.
  static const previewText = 560.0;

  /// Backdrop dell'anteprima: frazione della larghezza e dell'altezza
  /// dell'area dei contenuti, ancorato in alto a destra.
  static const backdropWidth = 0.78;
  static const backdropHeight = 0.72;

  /// Marchio nella barra laterale.
  static const railMark = 40.0;

  /// Logo del canale dentro la card 16:9 e, grande, nell'anteprima (i
  /// canali non hanno un backdrop: al suo posto c'è il logo).
  static const channelLogoCard = 72.0;
  static const channelLogoPreview = 200.0;

  /// Dettaglio: colonna di testo e altezza minima dell'intestazione
  /// (frazione dell'altezza dello schermo: sotto si vede la prima riga).
  static const detailText = 620.0;
  static const detailHeader = 0.62;

  /// Larghezza a cui si riduce l'artwork per ricavarne la tinta.
  static const tintSample = 64;

  /// Foto rotonda del cast (larghezza della card): wide e telefono.
  static const castPhoto = 112.0;
  static const castPhotoCompact = 88.0;
}

/// Fuoco: scala, anello, ombra.
abstract final class VistaFocus {
  static const cardScale = 1.06;
  static const buttonScale = 1.04;

  /// Anello: spessore costante, distacco dal bordo dell'elemento.
  static const ringWidth = 3.0;
  static const ringGap = 3.0;

  /// Distacco per celle, chip e voci, dove i vicini sono a 4–8 px.
  static const ringGapTight = 2.0;

  static const shadow = BoxShadow(
    color: VistaColors.focusShadow,
    offset: Offset(0, 16),
    blurRadius: 32,
  );
}

/// Motion: molle, durate, curve.
abstract final class VistaMotion {
  /// Fuoco: si assesta in circa 190 ms, rimbalzo dello 0,6%.
  static final focusSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 600,
    ratio: 0.85,
  );

  /// Comparsa dell'anello (solo opacità).
  static const focusRingFade = Duration(milliseconds: 150);
  static const focusRingCurve = Easing.standard;

  /// Testo dell'anteprima che cambia col fuoco.
  static const textFade = Duration(milliseconds: 150);

  /// Backdrop: attesa dopo che il fuoco si è fermato, poi dissolvenza.
  static const backdropDelay = Duration(milliseconds: 150);
  static const backdropFade = Duration(milliseconds: 300);

  /// Cambio di pagina: dissolvenza con scorrimento breve.
  static const page = Duration(milliseconds: 250);
  static const pageSlide = 24.0;

  /// Parte della transizione in cui esce la pagina vecchia (dissolvenza
  /// "attraverso": le due pagine non si vedono mai insieme).
  static const pageExitFraction = 0.35;

  /// Poster → dettaglio.
  static const sharedElement = Duration(milliseconds: 350);

  /// Scorrimento delle righe verso la posizione agganciata e della pagina.
  static const rowScroll = Duration(milliseconds: 250);
  static const pageScroll = Duration(milliseconds: 300);

  /// Apertura della barra laterale (solo ritaglio e opacità).
  static const railReveal = Duration(milliseconds: 200);

  /// Arrivo della tinta presa dall'artwork.
  static const tint = Duration(milliseconds: 300);

  /// Animazioni ridotte: restano solo dissolvenze brevi.
  static const reducedFade = Duration(milliseconds: 150);

  /// Overlay del player e messaggi brevi.
  static const overlayAutoHide = Duration(seconds: 4);
  static const toast = Duration(seconds: 2);

  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;
  static const standard = Easing.standard;
}

/// Uno stile di testo, come numeri: font, corpo, interlinea in punti.
class VistaTextSpec {
  const VistaTextSpec(
    this.family,
    this.size,
    this.lineHeight,
    this.weight, {
    this.tracking = 0,
  });

  final String family;
  final double size;
  final double lineHeight;
  final FontWeight weight;
  final double tracking;
}

/// Scala tipografica per un formato (wide o telefono).
class VistaTypeScale {
  const VistaTypeScale({
    required this.hero,
    required this.feature,
    required this.page,
    required this.rowTitle,
    required this.button,
    required this.cardTitle,
    required this.body,
    required this.label,
    required this.meta,
    required this.minimum,
  });

  /// Titolo hero (displayMedium).
  final VistaTextSpec hero;

  /// In evidenza: programma nell'anteprima Live (headlineLarge).
  final VistaTextSpec feature;

  /// Titolo pagina (headlineSmall).
  final VistaTextSpec page;

  /// Titolo riga (titleLarge).
  final VistaTextSpec rowTitle;

  /// Testo dei pulsanti (titleMedium).
  final VistaTextSpec button;

  /// Titolo sotto poster ed episodi (titleSmall).
  final VistaTextSpec cardTitle;

  /// Corpo (bodyLarge, bodyMedium).
  final VistaTextSpec body;

  /// Etichetta: chip, voci di menu (labelLarge).
  final VistaTextSpec label;

  /// Metadati (bodySmall, labelMedium).
  final VistaTextSpec meta;

  /// Etichette della barra in basso e "IN ONDA" (labelSmall).
  final VistaTextSpec minimum;
}

abstract final class VistaType {
  static const display = 'Bricolage Grotesque';
  static const text = 'Instrument Sans';

  /// Tracking delle righe in maiuscolo (sopratitoli).
  static const capsTracking = 0.4;

  /// Misure riferite alla tela TV 1280×720; valgono anche per PC e tablet.
  static const wide = VistaTypeScale(
    hero: VistaTextSpec(display, 68, 68, FontWeight.w700, tracking: -1.5),
    feature: VistaTextSpec(display, 36, 40, FontWeight.w700, tracking: -0.6),
    page: VistaTextSpec(display, 28, 34, FontWeight.w600, tracking: -0.4),
    rowTitle: VistaTextSpec(text, 20, 28, FontWeight.w600),
    button: VistaTextSpec(text, 16, 24, FontWeight.w600),
    cardTitle: VistaTextSpec(text, 15, 20, FontWeight.w600),
    body: VistaTextSpec(text, 17, 26, FontWeight.w400),
    label: VistaTextSpec(text, 14, 20, FontWeight.w500),
    meta: VistaTextSpec(text, 13, 18, FontWeight.w500),
    minimum: VistaTextSpec(text, 12, 16, FontWeight.w600, tracking: 0.4),
  );

  static const compact = VistaTypeScale(
    hero: VistaTextSpec(display, 40, 42, FontWeight.w700, tracking: -1),
    feature: VistaTextSpec(display, 28, 34, FontWeight.w700, tracking: -0.6),
    page: VistaTextSpec(display, 28, 34, FontWeight.w600, tracking: -0.4),
    rowTitle: VistaTextSpec(text, 18, 26, FontWeight.w600),
    button: VistaTextSpec(text, 15, 22, FontWeight.w600),
    cardTitle: VistaTextSpec(text, 14, 20, FontWeight.w600),
    body: VistaTextSpec(text, 15, 22, FontWeight.w400),
    label: VistaTextSpec(text, 14, 20, FontWeight.w500),
    meta: VistaTextSpec(text, 13, 18, FontWeight.w500),
    minimum: VistaTextSpec(text, 12, 16, FontWeight.w600, tracking: 0.4),
  );

  /// Peso forte per i titoli delle celle della guida.
  static const strong = FontWeight.w600;
}
