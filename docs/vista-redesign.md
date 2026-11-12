# Vista — nuova direzione di prodotto (novembre 2026)

Dopo il primo prototipo funzionante (guida TV in stile TiviMate) la richiesta è: un'app
moderna e professionale come **Plex + TiviMate + JustWatch**, su Android TV, Android
mobile, Windows e, più avanti, Samsung TV.

## Cosa fanno gli altri (ricerca)

| App | Punti di forza da prendere | Limiti da evitare |
|---|---|---|
| **Plex** (redesign 2025) | Navigazione per sezioni (Home, Live TV, On Demand, Discover, Library); **Watchlist universale** in primo piano; artwork grande (titoli, sfondi); menu utente con cronologia | Interfaccia lenta per chi vuole solo la TV |
| **TiviMate** | Guida a griglia velocissima, gruppi e **preferiti**, catch-up, registrazione, **multiview**, più playlist, anteprima del canale | Solo Android/Fire TV; VOD povero; aspetto datato |
| **JustWatch** | "**I miei servizi**", timeline delle **novità**, watchlist sincronizzata con avviso "ora disponibile", filtri genere/anno/età, ricerca unica | Dati non sempre affidabili; watchlist senza filtri né raccolte |
| **Stremio 5** | **Continua a guardare** in testa alla home con badge "nuovi episodi"; una riga per catalogo; stessa UI su tutte le piattaforme | — |
| **Channels / UHF** | Esperienza "Apple TV": pulita, fluida, preferiti nella guida rapida, multiview fino a 4, pausa del live | Solo Apple |
| **IPTV Smarters / OTT Navigator** | Multipiattaforma, Xtream + M3U, OTT Navigator ha un buon VOD | Interfacce datate e lente (sono proprio le lamentele del nostro pubblico) |

Sintesi: nessuno unisce **una home da streaming moderno** (Plex/Stremio) con **una guida TV
seria** (TiviMate) e **un catalogo dei servizi legali** (JustWatch). È lo spazio di Vista.

## Principi di design

1. **Una sola struttura, tre forme.** Le stesse sezioni ovunque:
   - telefono: barra in basso;
   - PC, tablet e TV: barra laterale con le etichette. Su TV l'app si disegna su una
     tela larga 1280 punti, come una finestra del PC, e si scala sullo schermo: TV e
     Windows hanno la stessa impaginazione (aggiornato il 12/11/2026).
2. **I contenuti al centro.** Locandine e sfondi grandi, l'interfaccia passa in secondo
   piano: niente cornici superflue e un solo accento (pesca) per avanzamento e focus.
3. **Gerarchia chiara.** Titoli di riga piccoli in maiuscoletto, titoli dei contenuti in
   grassetto, metadati su una riga separati da "·".
4. **Il telecomando prima di tutto.** Focus sempre visibile, Indietro prevedibile (torna
   alla barra, poi alla Home, poi esce), nessun vicolo cieco.
5. **Veloce.** Nessun blur (né sullo sfondo né sulle superfici: gli aloni sono
   gradienti), immagini ridimensionate in decodifica e tenute anche su disco, liste
   virtualizzate, calcoli sulle liste grandi fatti una volta per catalogo.

## Sezioni

| Sezione | Contenuto |
|---|---|
| **Home** | Riquadro in evidenza; righe "Continua a guardare", "Canali preferiti", "Visti di recente", "In onda ora", "La mia lista", "Film aggiunti di recente", "Serie aggiunte di recente" |
| **TV** | Guida a griglia (già fatta) con le categorie "Preferiti" e "Recenti" in cima |
| **Film / Serie** | Categorie a lato (TV/PC) o in alto (telefono), ordinamento (recenti, A-Z, anno, voto), griglia di locandine |
| **Scheda titolo** | Sfondo, locandina, metadati, trama, cast; Riproduci / Riprendi / Ricomincia / La mia lista; per le serie stagioni ed episodi con avanzamento |
| **Cerca** | Una sola ricerca su canali, programmi in onda, film e serie |
| **Impostazioni** | Fonte (aggiorna, cambia), canali, guida TV, riproduzione, informazioni |

## Funzioni concrete — fase 1 (questa iterazione)

- Preferiti (canali, film, serie) e "La mia lista".
- Avanzamento: riprendi film ed episodi da dove eri, "visto" oltre il 92%.
- Canali visti di recente.
- Dettagli Xtream completi (`get_vod_info` / `get_series_info`): sfondo, genere, cast,
  regia, durata.
- Data di aggiunta (Xtream `added`) per le righe "aggiunti di recente".
- Ricerca globale.
- Tracce audio e sottotitoli nel player.
- Build Windows e layout PC/telefono.

## Fasi successive

1. **Account e sync** (Supabase): preferiti, avanzamento, lista, correzioni canali;
   URL e credenziali cifrati sul dispositivo; login TV con QR.
2. **Scopri (stile JustWatch)**: TMDB `discover` con `watch_region=IT`, "I miei servizi",
   novità e in scadenza, deep link. Attribuzione a JustWatch obbligatoria.
3. **TV avanzata**: catch-up/replay Xtream, promemoria, multiview 2×2, PIN parentale,
   controllo canali non funzionanti.
4. **Aspetto**: 12 accenti e 3 sfondi, temi per lista.
5. **Samsung TV**: Flutter for Tizen (SDK 2026, TV dal 2021); player nativo AVPlay
   al posto di media_kit.

## Fase 2 — servizi di streaming e TV avanzata (fatta, novembre 2026)

- **Scopri** (stile JustWatch/Plex): cataloghi dei servizi scelti in "I miei servizi"
  (TMDB `discover` con `watch_region=IT`); righe Popolari, Novità, I più votati, una per
  servizio e Di tendenza; elenco completo a pagine.
- **Un titolo, una scheda**: "Disponibile su:" elenca ogni servizio una volta sola (incluso,
  gratis, noleggio, acquisto), prima i servizi dell'utente; ogni voce apre l'app (su TV per
  nome del pacchetto) o la ricerca del servizio; "Tutte le opzioni" apre la pagina JustWatch.
  TMDB non dà link diretti ai contenuti.
- **Lista IPTV ↔ TMDB**: se il titolo c'è anche nella lista, compare "La tua lista IPTV" in
  cima (abbinamento per ID TMDB del pannello, altrimenti titolo + anno). Le schede della
  lista mostrano "Disponibile anche su", cast e i dati mancanti presi da TMDB.
- Dati completi da TMDB: generi, durata, stagioni ed episodi, cast, regia/ideatori,
  trailer YouTube, link IMDb. Chiave TMDB dell'utente nel portachiavi.
- Ricerca anche sui servizi; Home con "Popolari sui tuoi servizi"; La mia lista unica.
- **Player live**: menu interno (tasto Menu o pulsante nella barra) con flusso della lista,
  qualità video HLS, audio, sottotitoli, preferito e **Multiview** fino a 4 canali (audio
  sul riquadro col focus). Stesso menu nei film/episodi.
- Attribuzioni obbligatorie: TMDB (Impostazioni → I miei servizi) e JustWatch (schede e Scopri).
