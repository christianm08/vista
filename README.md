<p align="center">
  <img src="brand/icon-rounded.png" width="112" alt="Icona di Vista">
</p>

<h1 align="center">Vista</h1>

<p align="center">
  Player IPTV e aggregatore di servizi di streaming per <b>Android TV</b>, <b>Android</b> (telefono e tablet) e <b>Windows</b>.<br>
  Guida TV in stile TiviMate, home e schede in stile Plex, catalogo dei servizi in stile JustWatch.
</p>

> **Vista è solo un lettore.** Non fornisce né include canali, film, serie o liste.
> Si usa con fonti che si ha il diritto di guardare (liste dei canali in chiaro,
> abbonamenti propri). Le credenziali restano sul dispositivo, nel portachiavi del sistema.

---

## Scaricare

Ultima versione: **1.0.0**, nella pagina [Releases](https://github.com/christianm08/vista/releases).

- **Windows**: scaricare `Vista-1.0.0-windows-x64.zip`, estrarlo in una cartella e avviare `vista.exe`.
  L'app non è firmata: Windows SmartScreen può chiedere conferma al primo avvio.
- **Android, Android TV e Google TV**: scaricare `Vista-1.0.0-android.apk` e installarlo
  (bisogna consentire l'installazione da origini sconosciute).

Le versioni pubblicate non contengono la chiave TMDB: per la sezione Scopri e la disponibilità
sui servizi si inserisce la propria in Impostazioni › I miei servizi.

---

## Cosa fa

### Fonti
- Liste **M3U** da indirizzo o da file, account **Xtream Codes**.
- **Più fonti insieme**: lo stesso canale presente in più liste diventa uno solo con tutti i flussi, così una fa da riserva all'altra; film e serie restano separati, ognuno con la sua fonte.
- **Aggiornamento automatico** (all'avvio, ogni 6, 12 o 24 ore), **user-agent** per fonte, nome personalizzato.
- Canali doppi della lista **uniti in automatico** (stesso canale in 4K, FHD, HD…): il player sceglie il flusso migliore e, se si blocca, passa al successivo.
- Nomi ripuliti da prefissi e suffissi (`IT |`, `[FHD]`, `(backup)`…), loghi presi dalla lista o da [tv-logos](https://github.com/tv-logo/tv-logos).

### TV in diretta
- **Guida a griglia** con anteprima del canale, barra di avanzamento e categorie della lista.
- Guida da [epg.lat](https://epg.lat), da quella della fonte e da un **link XMLTV personale**; **spostamento degli orari** se la guida è in anticipo o in ritardo.
- Player con barra del programma, elenco canali sopra il video, **numero del canale** da telecomando, **canale precedente**, nuovi tentativi automatici se lo stream cade.
- Menu del player: flusso, qualità video, tracce audio, sottotitoli, **formato dell'immagine** (adatta, zoom, allarga, 16:9, 4:3), **Multiview** fino a 4 canali, **decodifica software** per i canali che scattano, **Picture-in-Picture** su Android e **finestra mini sempre in primo piano** su Windows, **apri con un altro player** (VLC, MX Player…).
- Opzione per **riaprire l'ultimo canale** all'avvio.
- **Promemoria**: dalla guida, sul programma che deve iniziare (tasto Menu), Vista avvisa quando parte.
- **Registrazione**: del canale che si guarda (menu del player) o programmata dalla guida, salvata così com'è senza ricodificare. Si sceglie la **qualità** (massima, fino a 1080p, 720p o 480p: si registra la versione più leggera che il fornitore offre, per esempio circa 3 GB per 2 ore a 720p), lo **spazio massimo** e se, arrivati al limite, fermarsi o cancellare le registrazioni più vecchie. Sotto 1,5 GB liberi sul disco si ferma comunque.
- **Gestione canali**: categorie a sinistra e canali a destra, rinomina, logo personalizzato, unione dei doppioni, **numeri personalizzati** (che danno anche l'ordine), **sposta in un'altra categoria** (anche nuova), **nascondi e mostra più canali insieme**.
- **Categorie**: rinomina, riordina, nascondi (anche per i canali che arriveranno).
- **Controllo genitori**: PIN su canali, categorie e impostazioni.

### Impostazioni
- **Backup e ripristino** in un file (preferiti, avanzamento, canali, preferenze; senza password né chiavi).
- **Svuota cache** (locandine, loghi e guide salvati).

### Film e serie
- Cataloghi con categorie e ordinamenti, schede con trama, cast e trailer, stagioni ed episodi.
- **Continua a guardare** e **La mia lista**.

### Servizi di streaming
- Con una chiave [TMDB](https://www.themoviedb.org/) si scelgono **i propri servizi** (Netflix, Prime Video, Disney+, RaiPlay, …) e la sezione **Scopri** mostra cosa c'è su ognuno.
- Ogni titolo compare una volta sola con **"Disponibile su"**: i servizi sono cliccabili e aprono l'app o il sito; se il titolo è anche nella lista IPTV, c'è anche quella.
- Ricerca unica su canali, programmi, film, serie e servizi.

### Piattaforme
| | Navigazione | Note |
|---|---|---|
| **Android TV / Google TV** | Telecomando (D-pad, OK, Indietro, Menu, numeri, canale precedente) | Stessa impaginazione della versione Windows, scalata sullo schermo |
| **Windows** | Mouse e tastiera | Schermo intero con il pulsante nei player, **F11** o doppio clic; **Esc** esce |
| **Android telefono** | Tocco | Barra di navigazione in basso |
| **Android tablet** | Tocco | Barra laterale (aperta in orizzontale, a icone in verticale) |

---

## Telecomando e tastiera

| Tasto | Guida TV | Player |
|---|---|---|
| Frecce | Canali e programmi | Su/Giù: canale precedente/successivo · con la barra aperta, Giù porta ai pulsanti |
| OK / Invio | Guarda il canale | Elenco dei canali |
| Menu | Canale: preferito, PIN, nascondi, sposta, numero, promemoria, registra | Audio, sottotitoli, flussi, immagine, Multiview, registra, PiP |
| 0–9 | — | Vai al canale con quel numero |
| Canale precedente (o Backspace) | — | Torna al canale di prima |
| Indietro / Esc | Categorie, poi barra laterale | Chiude pannelli e barra, poi esce (dalla finestra mini torna alla finestra normale) |
| F11 (Windows) | Schermo intero | Schermo intero |

---

## Struttura del progetto

```
app/              App Flutter (Android, Android TV, Windows)
  lib/data/       Fonti, guida TV, dati utente, TMDB, PIN, backup, registrazioni, cache
  lib/screens/    Schermate (Home, TV in diretta, Film/Serie, Scopri, Player, Impostazioni…)
  lib/player/     Pezzi del player: barra, elenco canali, menu, scelta del flusso,
                  numero del canale, registrazione, PiP e player esterno
  lib/widgets/    Componenti (guida a griglia, schede, marchio…)
  tool/           Generatore delle icone
vista_resolver/   Pacchetto Dart puro: M3U, Xtream, XMLTV, TMDB, unione dei canali
brand/            Icone (quadrata, arrotondata, circolare), favicon, banner Android TV
docs/             Ricerca e direzione di prodotto
```

## Compilare

Requisiti: **Flutter 3.47** (Dart 3.13), Android SDK con NDK; per Windows Visual Studio
Build Tools con il carico di lavoro C++ e il componente **ATL** (serve a `flutter_secure_storage`).

```bash
cd app
flutter pub get
```

Windows:

```bash
flutter build windows --release
```

Android (APK unico per telefono, tablet e TV):

```bash
flutter build apk --release
```

### Chiave TMDB

La sezione Scopri e la disponibilità sui servizi usano l'API di TMDB. La chiave si può
inserire **dall'app** (Impostazioni › I miei servizi) oppure passare in compilazione:

```bash
flutter build windows --release --dart-define=TMDB_KEY=<la-tua-chiave>
```

La chiave **non va mai** scritta nel codice né salvata nel repository.

### Test

```bash
cd vista_resolver
dart test
```

```bash
cd app
flutter analyze
flutter test
```

### Icone

Tutte le icone (Android, Android TV, Windows, favicon, `brand/`) nascono da un unico
disegno, `app/lib/widgets/vista_mark.dart`. Per rigenerarle:

```bash
cd app
flutter test tool/brand_icons_test.dart --dart-define=VISTA_FONT_DIR=<cartella con i file Plus Jakarta Sans>
```

### Problemi noti

- **Gradle: "Unable to establish loopback connection"** (JDK 25 su Windows): compilare con
  `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\cartella-inesistente`, così Gradle usa TCP.
- Le **registrazioni** usano una connessione in più verso il fornitore: con gli abbonamenti
  che ne permettono una sola, guardare e registrare insieme non funziona.
- Negli **emulatori Android 16** il video resta nero (manca il contesto OpenGL ES che serve
  al player): sui dispositivi veri funziona. Avviare l'emulatore con `-gpu swiftshader_indirect`.

---

## Prossimi passi

- Catch-up e "ricomincia dall'inizio" (Xtream `tv_archive`, M3U `catchup`).
- Promemoria e registrazioni anche ad app chiusa (oggi servono Vista aperta).
- Samsung TV (Tizen).

## Crediti

- Dati di film e serie: [TMDB](https://www.themoviedb.org/). Vista usa l'API di TMDB ma non è approvata né certificata da TMDB.
- Disponibilità sui servizi di streaming: [JustWatch](https://www.justwatch.com/) (tramite TMDB).
- Loghi dei canali: [tv-logos](https://github.com/tv-logo/tv-logos), licenza CC BY-NC-SA 4.0.
- Guida TV: [epg.lat](https://epg.lat) e le guide XMLTV delle fonti.
- Player: [media_kit](https://github.com/media-kit/media-kit) (libmpv).
- Carattere: Plus Jakarta Sans (SIL Open Font License).
