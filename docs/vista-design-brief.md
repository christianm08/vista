# Vista — design brief (Fase 1)

13 novembre 2026 · proposta da approvare. Traduce il documento di redesign e le bozze
(Home TV, Dettaglio TV, Live TV — Guida, Home telefono) in token, componenti e regole di
motion realizzabili con lo stack attuale: **Flutter 3.47.9, Material 3, nessuna nuova
dipendenza**.

Dove le bozze e i token del documento non coincidono, **vincono i token**: le bozze
indicano layout, gerarchia e stato di fuoco, non i valori esatti.

---

## 0. Scelte di partenza (da confermare)

Sono le risposte che do per difetto ai punti aperti della Fase 0. Se ne cambi una,
aggiorno il brief prima della Fase 2.

| # | Punto | Scelta proposta |
|---|---|---|
| 1 | Voci di navigazione | Restano le 7 attuali. **TV, Windows, tablet**: barra laterale a icone con tutte e 7. **Telefono**: barra in basso con 5 voci (Home, Scopri, TV in diretta, Film, Serie TV); Cerca e Impostazioni passano come icone nell'intestazione della Home, come nella bozza. Nessuna sezione «Libreria». |
| 2 | Logo del titolo (clearlogo) | Titolo in testo ovunque. Il componente accetta già un logo, così basta collegarlo se un giorno i dati lo forniranno. |
| 3 | Icone | `Icons.*_rounded` di Flutter (Material Icons Rounded): nessuna dipendenza. |
| 4 | Token contro bozze | Vincono i token. Si aggiungono due colori presi dalle bozze: *superficie selezionata* e *testo corpo*. |
| 5 | Hero della Home su TV | Anteprima passiva del contenuto a fuoco, senza carosello né pulsanti. Sul telefono resta un riquadro in evidenza con «Riprendi» e «Lista», come nella bozza. |
| 6 | «Riproduci» | Titoli dei servizi (TMDB): apre l'app del servizio. Film e serie IPTV: parte nel player di Vista, come oggi. |
| 7 | Font offline | Da decidere: oggi `google_fonts` scarica i font al primo avvio; offline si vede il font di sistema. Proposta: includere i due font come asset (non è una dipendenza). |

---

## 1. Lo stack, in breve

- **Material 3 di Flutter 3.47** non ha i componenti Expressive: il commento in
  `page_transitions_theme.dart` lo conferma. I principi Expressive (molle, forme,
  tipografia enfatizzata) si riproducono con `SpringSimulation` e con i token di questo
  brief.
- **Android TV** non ha componenti Flutter dedicati: si usano i componenti M3
  ritematizzati e un contenitore di fuoco nostro.
- **Già disponibili, senza pacchetti:**
  - `SpringDescription.withDampingRatio` (molle)
  - `Easing.*` (curve M3)
  - `ColorScheme.fromImageProvider` (tinta dall'artwork)
  - `Hero` (elemento condiviso)
  - `FocusTraversalPolicy(requestFocusCallback:)` (scorrimento sotto il nostro controllo)
  - `MediaQuery.disableAnimationsOf` (animazioni ridotte)
- **Bricolage Grotesque e Instrument Sans** sono già in `google_fonts` 9.0.0.

---

## 2. Token

Tutti in un solo file, `app/lib/tokens.dart`. È l'unico posto dell'app in cui compaiono
colori, raggi, spaziature e durate. `theme.dart` costruisce il `ThemeData` leggendo solo
da lì. Nomi Dart in inglese, come nel resto del codice; commenti in italiano.

### 2.1 Colore — `VistaColors`

| Token | Dart | Valore | Uso |
|---|---|---|---|
| fondo | `background` | `#0C0D0C` | sfondo di ogni schermata e di ogni pagina (opaco) |
| superficie | `surface` | `#161816` | barre, celle della guida, pannelli, chip non selezionati |
| superficie alta | `surfaceHigh` | `#1F221F` | chip e celle «in onda», pulsanti tonali senza artwork |
| superficie selezionata *(nuovo, dalle bozze)* | `surfaceSelected` | `#2A2F27` | voce di navigazione attiva, cella della guida a fuoco |
| contorno | `outline` | `#2E322D` | separatori sottili, traccia delle barre su superficie |
| testo | `text` | `#F2F3EE` | titoli e testo principale; fondo dei chip selezionati |
| testo corpo *(nuovo, dalle bozze)* | `textBody` | `#D4D7CF` | trame, descrizioni |
| testo secondario | `textSecondary` | `#A9ADA4` | metadati, etichette, icone inattive |
| accento | `accent` | `#C8F250` | Riproduci, riempimento delle barre di avanzamento, linea «adesso» e punto «in onda», marchio |
| su accento | `onAccent` | `#141A05` | testo e icone sopra l'accento |
| fuoco | `focusRing` | `#FFFFFF` | anello di fuoco |
| errore *(nuovo)* | `error` | `#FF8A7A` | solo testo e icone degli stati di errore |
| ombra | `focusShadow` | `#99000000` | unica ombra, sotto l'elemento a fuoco |
| traccia su immagine | `trackOnImage` | `#47FFFFFF` | traccia della barra di avanzamento sopra un'immagine (funzionale, non decorativa) |

**Contrasti calcolati (WCAG):**

| Testo | Su | Rapporto |
|---|---|---|
| testo secondario | fondo · superficie · superficie alta · superficie selezionata | 8,5 · 7,8 · 7,0 · 6,0 : 1 |
| testo corpo | fondo | 13,4 : 1 |
| su accento | accento | 13,8 : 1 |
| fondo | testo (chip selezionato) | 17,5 : 1 |
| errore | fondo | 8,5 : 1 |

Tutti i testi superano 4,5:1.

**Regole:**

- **Accento**: Riproduci, avanzamento, «adesso» e «in onda», marchio. **Mai** su
  indicatori di navigazione, avatar, fuoco, chip selezionati o icone. Così resta a 2–3
  presenze per schermata, contando le barre di avanzamento come una sola presenza.
- **Il contorno non delimita i chip** (1,5:1 sul fondo): un chip non selezionato ha un
  riempimento *superficie*, non un bordo.
- **Testo sopra un backdrop** solo dove il velo è almeno al 90%. Il gradiente
  orizzontale va da fondo 100% a 0–40% della larghezza, 92% al 40%, 0% al 75%.
  La colonna di testo dell'anteprima non supera il 40%.
- **Tinta dinamica** (solo nel dettaglio):
  `ColorScheme.fromImageProvider(ResizeImage(backdrop, width: 64), brightness: dark, dynamicSchemeVariant: tonalSpot)`.
  - Ruoli usati: `surfaceContainerHigh` per pulsanti tonali e chip, `onSurfaceVariant`
    per i metadati, `onSurface` per il testo. I toni M3 (90 e 80 contro 17) garantiscono
    il contrasto.
  - Si calcola dopo la fine della transizione e si tiene in cache per URL. Si passa dai
    colori neutri alla tinta con una dissolvenza di 300 ms.
  - L'accento non cambia mai.

### 2.2 Tipografia — `VistaType`

Ogni ruolo occupa uno slot del `TextTheme` M3, così le chiamate esistenti
(`t.titleLarge`…) ereditano i nuovi stili. Anche gli slot non elencati vengono mappati
al ruolo più vicino: nessuno stile Material predefinito resta visibile.

| Ruolo | Slot M3 | Font | Wide (TV e PC) | Telefono | Peso | Spaziatura lettere |
|---|---|---|---|---|---|---|
| Titolo hero | `displayMedium` | Bricolage Grotesque | 68/68 | 40/42 | 700 | −1,5 / −1 |
| In evidenza *(nuovo, dalla bozza Live)* | `headlineLarge` | Bricolage Grotesque | 36/40 | 28/34 | 700 | −0,6 |
| Titolo pagina | `headlineSmall` | Bricolage Grotesque | 28/34 | 28/34 | 600 | −0,4 |
| Titolo riga | `titleLarge` | Instrument Sans | 20/28 | 18/26 | 600 | 0 |
| Pulsante *(nuovo)* | `titleMedium` | Instrument Sans | 16/24 | 15/22 | 600 | 0 |
| Titolo card *(nuovo, dalle bozze)* | `titleSmall` | Instrument Sans | 15/20 | 14/20 | 600 | 0 |
| Corpo | `bodyLarge` | Instrument Sans | 17/26 | 15/22 | 400 | 0 |
| Etichetta | `labelLarge` | Instrument Sans | 14/20 | 14/20 | 500 | 0 |
| Metadati | `bodySmall`, `labelMedium` | Instrument Sans | 13/18 | 13/18 | 500 | 0 (+0,4 in maiuscolo) |
| Minima *(nuovo)* | `labelSmall` | Instrument Sans | 12/16 | 12/16 | 600 | +0,4 |

- **Dove si usano i ruoli nuovi:**
  - *In evidenza*: il programma in onda nell'anteprima Live.
  - *Titolo card*: il titolo sotto poster ed episodi.
  - *Pulsante*: il testo dei pulsanti (le bozze lo hanno a 16–17).
  - *Minima*: solo le etichette della barra del telefono e le etichette «IN ONDA».
- **Varianti di peso** come token: `VistaType.labelStrong` (Etichetta a 600) per i titoli
  delle celle della guida.
- **Orari, durate e numeri di canale** usano cifre tabellari (`tnum`), se il font le
  supporta.
- **Il marchio Vista** (`vista_mark.dart`) resta in Plus Jakarta Sans e non si tocca.

### 2.3 Spazio — `VistaSpace`

`s4 s8 s12 s16 s24 s32 s48 s64`. Nessun altro valore.

| Uso | Wide | Telefono |
|---|---|---|
| Spazio tra card in una riga | 16 | 12 |
| Spazio riservato sopra e sotto le card della riga | 16 | 12 |
| Spazio tra le righe | 32 | 24 |
| Gutter del contenuto | 32 | 16 |
| Spazio tra titolo e metadati dentro una card | 4 | 4 |
| Spazio tra immagine e testo dentro una card | 12 | 8 |

Arrotondamenti delle bozze: 10 → 8 o 12, 14 → 12 o 16, 20 → 16 o 24, 28 → 24 o 32,
40 → 32, 56 → 48. Fanno eccezione le **misure dei componenti** (card, rail, celle):
sono dimensioni, non spaziature, e vivono come token propri in `VistaSize`.

### 2.4 Forme — `VistaRadius`

| Token | Valore | Dove |
|---|---|---|
| `chip` | 8 | chip, celle della guida, etichette («IN ONDA», «IPTV»), riquadro del logo del canale |
| `card` | 12 | card, poster, anteprima del canale |
| `panel` | 20 | pannelli, dialoghi, fogli |
| `full` | `StadiumBorder` | pulsanti, indicatori di navigazione, barre di avanzamento fuori dalle immagini |

Sopra le immagini la barra di avanzamento ha estremi dritti: la ritaglia il raggio della
card.

### 2.5 Profondità e fuoco — `VistaFocus`

| Elemento | Scala | Anello | Distacco | Ombra | Fondo a fuoco |
|---|---|---|---|---|---|
| Card e poster | 1,06 | 3 px bianco | 3 px | sì | — |
| Pulsanti | 1,04 | 3 px bianco | 3 px | sì | — |
| Celle della guida, chip, voci di menu e di navigazione | 1,0 | 3 px bianco | 2 px | no | un gradino più chiaro (superficie → superficie alta → superficie selezionata) |

- **Ombra unica**: `BoxShadow(focusShadow, offset: (0, 16), blur: 32)`, come nella bozza.
  Compare solo con il fuoco e segue l'animazione.
- **Anello**: disegnato *fuori* dal box (painter in primo piano) con raggio pari al
  raggio dell'elemento più il distacco. Spessore costante: si anima solo l'opacità del
  colore. Non cambia il layout.
- **Hover del mouse** (Windows): stesso aspetto del fuoco, senza ombra. Se ci sono
  entrambi, vince il fuoco.
- **Tocco**: niente anello, niente scala. Come oggi, il fuoco si mostra solo con la
  modalità tastiera o telecomando.

### 2.6 Misure — `VistaSize` e `VistaLayout`

Tela TV 1280×720 (come oggi). Su Windows e tablet valgono le stesse misure *wide*.

| Misura | Wide | Telefono | Note |
|---|---|---|---|
| Area sicura TV | 5% della tela: 64 orizzontale, 36 verticale | — | calcolata, non è una spaziatura. Sulle altre piattaforme vale 0 |
| Card 16:9 | 256×144 | 220×124 | 300×169 su finestre ≥1600, come oggi. Gli episodi del dettaglio usano la stessa misura (la bozza dice 232: unificato) |
| Poster 2:3 | 148×222 | 112×168 | 168×252 su finestre ≥1600 |
| Elemento della barra laterale | 56×48 | — | la bozza dice 44; 48 per il tocco su tablet |
| Barra laterale chiusa | rientro + 56 + 16 (88 su PC e tablet, 144 su TV) | — | su TV il rientro è area sicura + 8, così anche l'anello (che sporge di 5) resta dentro |
| Barra laterale aperta | 248, sopra il contenuto | — | il contenuto non si sposta |
| Inizio del contenuto | barra + 32 | gutter 16 | la bozza dice 128 su PC: diventa 120 |
| Barra in basso | — | 80 + area di sistema | |
| Riga della guida | 48 di altezza, 8 di spazio | — | |
| Colonna dei canali della guida | 200 | — | |
| Pulsante | altezza 56 | altezza 48 | bersaglio sempre ≥48 |
| Chip | altezza 36 | altezza 32 | bersaglio 48 sul telefono |
| Anteprima della Home | 64 dal bordo + 300 | riquadro di 430 che scorre | |

### 2.7 Motion — `VistaMotion`

| Token | Valore | Note |
|---|---|---|
| `focusSpring` | `SpringDescription.withDampingRatio(mass: 1, stiffness: 600, ratio: 0.85)` | si assesta in circa 190 ms, sovraelongazione dello 0,6% («appena accennato») |
| `focusRingFade` | 150 ms, `Easing.standard` | solo l'opacità dell'anello |
| `backdropDelay` | 150 ms | attesa dopo che il fuoco si è fermato |
| `backdropFade` | 300 ms, `Easing.standard` | dissolvenza incrociata |
| `page` | 250 ms: dissolvenza e scorrimento di 24 px, `Easing.emphasizedDecelerate` in entrata e `Easing.emphasizedAccelerate` in uscita | |
| `sharedElement` | 350 ms | poster → dettaglio. La rotta che parte da un poster dura 350 ms, perché il volo del `Hero` dura quanto la rotta |
| `rowScroll` | 250 ms, `Easing.emphasizedDecelerate` | interrompibile, riparte dalla posizione corrente |
| `pageScroll` | 300 ms, `Easing.emphasizedDecelerate` | scorrimento verticale tra le righe |
| `tint` | 300 ms | arrivo della tinta dinamica |
| `overlayAutoHide` | 4 s | overlay del player |
| `toast` | 2 s | snackbar |

Nel file dei token vanno le durate di **interfaccia** (animazioni, overlay, messaggi). I
timer di logica (orologio, aggiornamento delle liste, promemoria) restano dove sono:
fanno parte del comportamento, che non si cambia.

**Animazioni ridotte** (`MediaQuery.disableAnimationsOf`, che su Android TV corrisponde
a «Rimuovi animazioni»):

- niente scala: il fuoco usa solo l'anello, che appare con una dissolvenza di 150 ms;
- righe e pagine scorrono di scatto;
- cambio di pagina e backdrop con dissolvenza di 150 ms, senza attesa;
- niente elemento condiviso.

Su Windows vale dove l'engine espone l'impostazione.

---

## 3. Fuoco e scorrimento: come spariscono i difetti

Questo è il cuore della Fase 2. Ogni riga della tabella risponde a una causa della Fase 0.

| Difetto | Causa (Fase 0) | Soluzione |
|---|---|---|
| Scatto e poi scivolata in verticale | 4 | Una `FocusTraversalPolicy` di app con `requestFocusCallback` che **chiede solo il fuoco, senza `ensureVisible`**. Lo scorrimento lo decidono solo la riga (orizzontale) e la pagina (verticale). |
| Card a filo del bordo e tagliata | 2 | La riga aggancia la card a fuoco a una posizione fissa: offset = indice × (larghezza + spazio). Il bordo sinistro della card cade sul gutter, mai sul bordo del viewport. In fondo alla riga si ferma all'estensione massima. |
| Card sotto la barra o il titolo, o tagliata in alto e in basso | 1, 2 | La riga ritaglia **solo in orizzontale**, al bordo dell'area dei contenuti (`ClipRect` con un clipper aperto in verticale). Sopra e sotto c'è uno spazio riservato di 16, più grande dello sforamento: card 16:9 a fuoco 4,3 + 6 = 10,3. La barra laterale è opaca. |
| Compenetrazione con i vicini | 6 | Lo spazio tra le card (16) supera lo sforamento laterale (16:9: 7,7 + 6 = 13,7; poster: 4,4 + 6 = 10,4), quindi la card a fuoco non tocca mai la vicina. Il primo piano resta garantito anche senza z-index. Dove serve una sovrapposizione vera (per esempio la cella della guida in una griglia `Stack`), l'elemento a fuoco si disegna per ultimo. |
| Contenuto che si sposta di 2 px e immagini ridecodificate | 3 | L'anello è un painter fuori dal box, non un bordo; la scala è `Transform`, che non tocca il layout. `cacheWidth` = larghezza a riposo × dpr, passata dalla riga e non letta da un `LayoutBuilder`. |
| Righe che ereditano lo scorrimento di un'altra | 7 | Ogni riga ha una chiave stabile (`ValueKey(id della riga)`) e ogni card la chiave dell'ID del contenuto. Lo stato di animazione e di fuoco segue il contenuto. |
| Elementi che restano ingranditi | 8 | Molla guidata da un solo stato (a fuoco sì o no). Riparte da valore e velocità correnti e, a molla ferma, imposta il valore **esattamente** a 1. Nessuna sequenza, nessun ritardo. |
| Pagine che si vedono una attraverso l'altra | 5 | `pageTransitionsTheme` proprio per tutte le piattaforme. Ogni pagina ha il fondo opaco: `Scaffold` con `background`. Gli aloni spariscono. |

**Pagina a righe (Home, Scopri, dettaglio).** La zona dell'anteprima è fissa in alto; le
righe scorrono sotto. Scendendo, la riga a fuoco si aggancia alla prima posizione sotto
l'anteprima, con 16 di margine, e la precedente esce in alto. La zona delle righe ritaglia
al proprio bordo superiore. È l'unico ritaglio verticale, ed è il «bordo dello schermo»
di quella zona: l'elemento a fuoco non lo raggiunge mai.

**Memoria del fuoco.** Ogni riga ricorda l'ultimo elemento a fuoco. Entrando dall'alto o
dal basso si torna lì, cioè sulla card agganciata, non sulla più vicina in geometria.
Tornando da un'altra pagina il fuoco torna dov'era: lo fa già il `Navigator`, e le chiavi
stabili lo rendono affidabile.

**Mouse e tocco.** Le righe scorrono libere, senza aggancio. L'aggancio vale solo per il
fuoco da tastiera e telecomando.

---

## 4. Componenti della Fase 2

Convivono con quelli vecchi finché ogni schermata non viene migrata (Fasi 3–6); la
Fase 7 elimina i vecchi. Il nuovo `ThemeData` (fondo opaco, transizioni, font, colori)
entra subito per tutta l'app: dalla Fase 2 il difetto 5 sparisce ovunque e le schermate
non ancora migrate prendono già la nuova base.

### 4.1 `VistaFocusable` — contenitore di fuoco

Sostituisce `FocusCard`.

- **Parametri:** `kind` (`card`, `button`, `flat`), `radius`, `onTap`, `onLongPress`,
  `focusNode`, `autofocus`, `onFocusChange`.
- **Base:** `FocusableActionDetector`, come oggi. Restano Invio/OK, Menu e Shift+F10.
- **Animazione:** un `AnimationController.unbounded` per elemento, guidato da
  `SpringSimulation`. La scala usa `Transform.scale`; l'ombra e l'anello usano painter
  che leggono lo stesso valore, il tutto in un `RepaintBoundary`.
- **A riposo:** nessun riempimento e nessun bordo. Per `flat` il riempimento è un token
  di superficie.

### 4.2 `PosterCard` (2:3) e `WideCard` (16:9)

- **Immagine:** `NetImage` con `cacheWidth` a riposo.
- **Segnaposto durante il caricamento:** tinta piatta *superficie*.
- **Immagine mancante:** *superficie* con il titolo in Titolo card, allineato in basso a
  sinistra. Spariscono il gradiente e il testo centrato.
- **Testo sotto:** Titolo card e Metadati. Nelle righe della Home su TV il testo dei
  poster è nascosto (lo dice già l'anteprima, come nella bozza); nelle griglie e sul
  telefono si vede.
- **Etichette** («IPTV», «IN ONDA»): riquadro *fondo*, raggio 8, testo Minima.
  «IN ONDA» ha il punto accento; il rosso «LIVE» sparisce.
- **Preferito:** icona `bookmark_rounded` in *testo*, non in accento.
- **Avanzamento:** 4 px, traccia `trackOnImage`, riempimento accento.
- **`WideCard`:** perde il gradiente scuro (il testo è sotto, non serve). Per i canali:
  logo centrato su *superficie*; senza logo, il numero del canale in Bricolage.

### 4.3 `VistaRow` — riga orizzontale

- **Struttura:** intestazione (Titolo riga e `trailing`) e lista orizzontale con
  `ScrollController` proprio.
- **Parametri obbligatori:** `itemKey(i)` e `restWidth`.
- **Comportamento:** aggancio del fuoco, ritaglio solo orizzontale, spazio riservato,
  memoria del fuoco, `FocusTraversalGroup`.
- **Caricamento:** ha anche lo stato «caricamento», con segnaposto a tinta piatta delle
  stesse misure.

### 4.4 `VistaRowsPage` — pagina a righe

- **Struttura:** zona fissa in alto (opzionale) e righe agganciate sotto, con
  `pageScroll`.
- **Pagine:** è la base di Home, Scopri e della parte bassa del dettaglio.
- **Griglie:** Film, Serie e Scopri usano la stessa regola in verticale: la fila a fuoco
  resta dentro, con il margine riservato.

### 4.5 Pulsanti — `VistaButton`

- **Varianti:**
  - `.primary`: `FilledButton`, sfondo accento, testo su accento.
  - `.tonal`: `FilledButton.tonal`, sfondo *superficie alta* o la tinta dinamica.
  - `.icon`: `IconButton.filledTonal`, 48×48.
- **Forma:** pillola, altezza 56 (wide) o 48 (telefono), padding orizzontale 24, icona a
  24 con 8 di spazio.
- **Fuoco:** l'aspetto di fuoco lo disegna `VistaFocusable(kind: button)` attorno al
  pulsante, con lo stesso `FocusNode`. L'overlay di fuoco di Material è spento.

### 4.6 Chip — `VistaChip`

- **Base:** `ChoiceChip` e `FilterChip` ritematizzati via `ChipThemeData`.
- **Forma:** raggio 8, nessun bordo.
- **Stati:**
  - non selezionato: *superficie* con *testo*;
  - selezionato: *testo* con *fondo*, come «Tutti» nella bozza;
  - a fuoco: anello senza scala; se il chip non è selezionato sale anche a *superficie
    alta*.
- **Dove:** serve sia per i filtri di categoria sia per il selettore di qualità
  (Auto, 4K, HD, SD).

### 4.7 Barra laterale — `VistaRail` (TV, Windows, tablet)

- **Base:** costruita su misura e non su `NavigationRail`, per tenere la logica di
  fuoco di oggi: rientro sulla sezione corrente, Destra torna al contenuto, Indietro
  prevedibile.
- **Chiusa:** marchio in alto, 6 voci, Impostazioni in fondo. Voce attiva su pillola
  *superficie selezionata* con icona *testo*; le altre in *testo secondario*.
- **Aperta** (fuoco o hover): pannello opaco *superficie* da 248 sopra il contenuto,
  rivelato da un clipper animato con le etichette in dissolvenza. Nessun cambio di
  larghezza nel layout e nessun velo sfumato.

### 4.8 Barra in basso — `NavigationBar` M3 ritematizzata (telefono)

- **Aspetto:** altezza 80, fondo *superficie*, indicatore *superficie selezionata*
  64×32 a pillola, icona attiva in *testo* (non in accento, a differenza della bozza),
  etichette Minima.
- **Voci:** le 5 del punto 0.1.

### 4.9 Galleria componenti

- **Accesso:** `screens/gallery_screen.dart`, avviabile con
  `flutter run --dart-define=VISTA_GALLERY=true`. Non compare nella navigazione dell'app.
- **Contenuto:** campioni dei token, scala tipografica, card in tutti gli stati (riposo,
  fuoco, avanzamento, caricamento, immagine mancante), una riga di 50 elementi finti,
  pulsanti, chip, barra laterale e barra in basso.
- **Interruttore** per simulare le animazioni ridotte.
- **Dati:** finti, locali alla galleria. Nessun accesso a `data/`.

---

## 5. Verifica automatica

Test nuovi in `app/test/`, eseguiti a ogni fase con `flutter test`:

1. **D-pad tenuto premuto.**
   - Su una `VistaRow` di 50 elementi: 150 pressioni di Destra a 33 ms l'una (5 s),
     poi a fine corsa.
   - Verifica: tutti gli elementi tranne quello a fuoco hanno scala **esattamente** 1 e
     spostamento 0.
   - Lo stesso test va ripetuto verso Sinistra e in verticale su una `VistaRowsPage`.
2. **Nessun taglio.** Il rettangolo dell'anello a fuoco sta dentro il ritaglio della riga
   e dentro l'area sicura.
3. **Nessuna sovrapposizione.** Il rettangolo dell'anello a fuoco non interseca i
   rettangoli delle vicine.
4. **Animazioni ridotte.** Con `disableAnimations` la scala resta 1.
5. **Token.**
   - Un test cerca in `lib/` (esclusi `tokens.dart`, `data/`, `player/`) i pattern
     `Color(0x`, `Colors.`, `circular(<numero>)`, `Duration(milliseconds`.
   - In Fase 2 vale per i file nuovi; in Fase 7 per tutta la UI.

---

## 6. Cosa non cambia

`data/`, `player/`, `vista_resolver/`, modelli, chiamate API, rotte e comportamento
delle funzioni. Le uniche differenze di comportamento sono quelle elencate nei punti
0.1 e 0.5, e diventano effettive solo con la tua conferma.
