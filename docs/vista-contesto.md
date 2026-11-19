# Vista — contesto di progetto

Riassunto delle decisioni prese finora. "Vista" è un nome provvisorio.

## Obiettivo
Un'unica app che fa da centro di intrattenimento:
1. **Catalogo streaming unificato** (Netflix, Prime Video, Disney+, NOW, Apple TV, RaiPlay, Paramount+…). Mostra tutti i titoli disponibili in Italia; il tocco apre il titolo nell'app del servizio tramite **deep link**. Serve l'abbonamento a quel servizio. La riproduzione dentro Vista non è possibile (DRM, nessuna API) e non va tentata.
2. **Player IPTV** per liste **M3U** e login **Xtream**, con riproduzione interna. È un player "vuoto": **nessuna lista inclusa**, l'utente porta la sua. Uso previsto: canali in chiaro e liste legali. Non fornire liste e non aiutare a configurare liste pirata.

Pubblico iniziale: l'autore e i suoi amici, insoddisfatti di IPTV Smarters, OTT Navigator e TiviMate. Le loro lamentele:
- interfaccia datata e lenta;
- EPG che non funziona;
- loghi sbagliati;
- un'app diversa per ogni piattaforma;
- mancanza di sincronizzazione con un account.

## Piattaforme e stack
- **Flutter**, un unico codice per **Android → Android TV → Windows → Samsung TV (Tizen, ultima)**.
- Due layout:
  - touch/mouse (Android, Windows): barra a pillola in basso sul telefono, barra laterale su PC;
  - telecomando (Android TV, Samsung): navigazione con frecce/D-pad, focus molto visibile, margini di sicurezza dai bordi dello schermo, testi grandi.
- **Player:** `media_kit` o ExoPlayer/Media3 (HLS). Su Tizen il player nativo AVPlay. Picture-in-picture, Multiview fino a 4 canali.
- **Samsung:** Flutter for Tizen (progetto di Samsung Research), TV dal 2021 in su (Tizen 6.0+). Non tutti i plugin sono disponibili; il deep link a un titolo specifico in Netflix e simili non è garantito; senza store serve la modalità sviluppatore.
- **Windows:** i deep link aprono quasi sempre il sito web del servizio.
- **Mobile:** deep link all'app nativa (Intent su Android), con il sito come fallback.
- **Backend:** Supabase (login, Postgres con permessi per utente, realtime). Più un job notturno per catalogo ed EPG.
- **Locale:** SQLite (es. drift), funzionamento offline-first.

## Catalogo streaming
- **TMDB** (gratis): `discover` con `watch_region=IT` e `with_watch_providers` per i cataloghi, poi poster e metadati. Va **citato JustWatch** come fonte dei dati sui provider: è obbligatorio.
- **Deep link:** Streaming Availability API (100 richieste al giorno gratis, poi da 29 USD/mese; include la data di scadenza dal catalogo) oppure Watchmode. Si chiamano **solo all'apertura di un titolo**, con risultato in cache.
- Un titolo presente su più servizi appare una volta sola, con più opzioni: incluso, noleggio, acquisto.
- Funzioni:
  - filtro "solo i miei servizi";
  - righe "Novità sui tuoi servizi" e "In scadenza";
  - watchlist unificata;
  - ricerca unica su titoli, canali e programmi in onda.

## IPTV "intelligente" (risolutore di canali)
1. **Parsing:** M3U (`#EXTINF`, `tvg-id`, `tvg-logo`, `group-title`, `x-tvg-url`/`url-tvg` nell'intestazione) e Xtream (`player_api.php`, EPG del provider).
2. **Normalizzazione del nome:**
   - togliere prefissi come `IT:`, `|IT|`, `[ITA]`;
   - riconoscere la qualità: `4K|UHD|2160p` → 4K, `FHD|1080p|1080i` → FHD, `HD|720p` → HD, `SD|576p|480p` → SD;
   - togliere `(backup)`, `alt`, `HEVC`, `H265`, `50fps`;
   - minuscole, senza accenti;
   - alias: rai uno → rai 1, canale5 → canale 5, la 7 → la7, rainews24 → rai news 24, ecc.
3. **Raggruppamento:**
   - prima per `tvg-id` (la parte prima di `@`), poi per nome normalizzato, poi confronto approssimato con `channels.json` di iptv-org (che include i nomi alternativi);
   - ogni canale contiene più flussi, ordinati 4K > FHD > HD > SD.
4. **Trappole da evitare:**
   - "Rai 4" non è "Rai" in 4K: le parole chiave della qualità vanno riconosciute solo come parola intera;
   - "+1" è un canale separato (differita);
   - le edizioni regionali sono canali separati (iptv-org le chiama `feeds`);
   - serve un'opzione manuale "unisci/separa" che l'app ricorda e sincronizza.
5. **Qualità vera:** si legge `RESOLUTION` dal manifest HLS invece di fidarsi del nome. "Auto" sceglie il flusso migliore e, se uno si blocca, passa al successivo.
6. **Loghi**, in quest'ordine:
   1. `tvg-logo` della lista;
   2. `logos.json` di iptv-org (già collegato all'ID del canale);
   3. **tv-logo/tv-logos** su GitHub: PNG 512 px per paese, pensati per sfondi scuri. **Licenza CC BY-NC-SA, vieta l'uso commerciale.** Verificare che la cartella italiana sia completa;
   4. iniziali generate.

   I loghi vanno messi in cache, non scaricati da GitHub a ogni avvio.
7. **EPG:**
   - fonti: XMLTV della lista, EPG del provider Xtream, **iptv-org/epg** (programma da far girare sul backend, anche con l'immagine Docker; licenza Unlicense; siti italiani elencati in `SITES.md`), `guides.json` di iptv-org per sapere quale fonte usare per ogni canale;
   - elaborazione sul backend; all'app vanno solo 2-3 giorni dei canali dell'utente, in JSON compatto;
   - abbinamento con lo stesso risolutore; correzione manuale "questo canale è…";
   - **correzioni condivise in forma anonima** (solo l'abbinamento canale → EPG/logo, **mai** gli URL delle liste).
8. **Privacy:** il risolutore gira **sul dispositivo**, scaricando il database di iptv-org (pochi MB). Liste e credenziali non passano dal backend in chiaro.
9. **Funzioni:**
   - gruppi e preferiti;
   - guida a griglia con "adesso / dopo" e linea dell'ora attuale;
   - **Replay** se il provider lo supporta;
   - promemoria;
   - Multiview 2×2 con scelta dell'audio;
   - controllo automatico dei canali non funzionanti;
   - controllo parentale con PIN.

## Account e sincronizzazione
- **Cosa si sincronizza:**
  - liste e fonti EPG;
  - preferiti e gruppi;
  - correzioni (unisci/separa, logo, EPG);
  - ultimi canali visti;
  - watchlist e abbonamenti;
  - tema;
  - profili.
- **Credenziali Xtream e URL delle liste cifrati sul dispositivo** prima dell'invio. Compromesso: se l'utente perde la password, deve reinserire le liste.
- **Login sulla TV con codice QR / codice dispositivo:** la TV mostra il codice, il telefono già loggato lo approva.
- Profili con PIN.
- Offline-first; in caso di modifiche contemporanee vince la più recente.

## Design — redesign di novembre 2026 (sostituisce lo stile "Vetro")
- **Fonte di verità:** i token in `app/lib/tokens.dart`; il tema Material in `app/lib/theme.dart`. Nessun colore, raggio o durata scritti a mano fuori dai token: lo controlla `app/test/design_tokens_test.dart`. Galleria dei componenti: `gallery_screen.dart`.
- **Font:** Bricolage Grotesque per titoli e numeri grandi, Instrument Sans per il testo.
- **Colori:** superfici piene e scure, senza vetro, blur né aloni.
  - Fondo `#0C0D0C`; superficie `#161816`, alta `#1F221F`, selezionata `#2A2F27`; contorno `#2E322D`.
  - Testo `#F2F3EE`, corpo `#D4D7CF`, secondario `#A9ADA4`.
  - Un solo accento, lime `#C8F250`, per avanzamento, "in onda" e pulsante principale; errore `#FF8A7A`.
  - Sugli artwork i veli (`VistaScrims`) sfumano nel fondo; il testo sta solo dove il velo copre almeno il 90%.
- **Spaziature:** scala 4, 8, 12, 16, 24, 32, 48, 64.
- **Raggi:** chip 8, card e locandine 12, pannelli e dialoghi 20, pulsanti a pillola.
- **Fuoco (telecomando):** anello bianco di 3 px staccato di 3 px dal bordo, disegnato fuori dall'elemento; ingrandimento 1,06× per le card e 1,04× per i pulsanti. Il fuoco non fa scorrere da solo: le righe e le griglie tengono l'elemento in vista. Il tocco non sposta il fuoco.
- **Navigazione:**
  - telefono: barra in basso;
  - PC e TV: barra laterale stretta con le icone, che si apre con le etichette; su TV, quando si apre, spinge il contenuto.
- **TV:** tela larga 1280 punti scalata sullo schermo, area sicura del 5%. Testare su un box Android TV economico per garantire i 60 fps.
- **Movimento:** durate e curve in `VistaMotion`; con "animazioni ridotte" restano solo dissolvenze brevi.
- **Non ancora ridisegnate** (colori e raggi sui token, spaziature ancora scritte a mano): Gestisci canali, Importazione, I miei servizi, Registrazioni, Multiview, player dei film.

## Materiale esistente
- **Prototipo funzionante** nel vecchio stile Vetro (superato dal redesign), solo frontend con dati finti: `prototipo-vista.html` (allegato). Link condiviso: https://claude.ai/artifact/QGNQDdKi49q6RnPLJDdMYD
  - Contiene in JS `parseM3U`, `normalize`, `resolve` (il raggruppamento), una guida TV generata e la lista di esempio `SAMPLE_M3U`.
  - Risultato provato: 30 voci → 20 canali, 8 raggruppati. Rai 1 raggruppa 4K, FHD, HD e la voce "IT: Rai Uno SD"; Rai 4, Canale 5 +1 e Rai 3 TGR Lazio restano canali separati.
  - Da portare in Dart come riferimento e test.
- **Canvas di mockup:** https://claude.ai/artifact/FR7GNK1QwVjwZcvhUxxte6 (privato). Contiene una prima versione per telefono e TV, più la pagina "Stili a confronto"; lo stile scelto allora era B, poi superato dal redesign di novembre 2026.

## Distribuzione
- **Android / Android TV:** APK installato a mano (sulla TV tramite l'app Downloader) con controllo aggiornamenti dentro l'app, oppure test chiuso su Google Play.
- **Windows:** installer.
- **Samsung:** per ultima.
- **Store:** sono severi con le app IPTV. Mai liste precaricate, e un disclaimer chiaro.

## Ordine di sviluppo
1. Player IPTV per Android e Android TV: import, risolutore, loghi, EPG, guida, preferiti, flussi con fallback.
2. Account e sincronizzazione (Supabase, cifratura, QR).
3. Catalogo streaming con deep link.
4. Windows.
5. Samsung Tizen.

## Decisioni ancora aperte
- Nome definitivo dell'app.
- Screenshot di KIPTV da analizzare.
- Uso commerciale sì o no (decide se si possono usare i loghi tv-logos).
- Dove ospitare il programma EPG di iptv-org.
- Streaming Availability o Watchmode per i deep link.
