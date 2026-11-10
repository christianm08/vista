# vista_resolver

Risolutore di canali IPTV di Vista, in Dart puro (senza Flutter), portato da
`parseM3U`, `normalize` e `resolve` del prototipo HTML.

```dart
import 'package:vista_resolver/vista_resolver.dart';

final result = resolveChannels(parseM3u(testoDellaLista));
for (final c in result.channels) {
  print('${c.number} ${c.name}: ${c.streams.map((s) => s.quality).join(' > ')}');
}
```

## API
- `parseM3u(String)` → `M3uPlaylist` (`epgUrl`, voci con `tvg-id`, `tvg-logo`, `group-title`).
- `normalizeName(String)` → chiave normalizzata + `Quality`.
- `resolveChannels(playlist, {matcher, merges})` → canali con flussi ordinati 4K > FHD > HD > SD > Auto, più un report.
- `displayName`, `monogram`, `tvgIdKey`, `removeAccents`.

## Differenze dal prototipo
- **Feed nel `tvg-id`:** `Rai1.it@HD` si unisce a `Rai1.it`. Un suffisso che non indica la qualità (`Rai3.it@Lazio`) viene trattato come feed regionale e resta un canale separato.
- **Ordinamento stabile** dei flussi: a parità di qualità resta l'ordine della lista. In Dart `List.sort` non è stabile.
- **Accenti:** Dart non ha la normalizzazione NFD, quindi c'è una tabella per le lettere latine comuni.
- **Escluso** tutto ciò che il prototipo simulava: colori, categorie, elenco `KNOWN`, origine finta di logo ed EPG, guida generata.

## Agganci ancora da implementare
- `matcher`: confronto approssimato con `channels.json` di iptv-org (nomi alternativi).
- `merges`: unioni manuali dell'utente (chiave → chiave). La "separa" manuale non è ancora prevista.
- Qualità `Auto`: va letta da `RESOLUTION` nel manifest HLS.
- Loghi: oggi solo `tvg-logo` della lista. Poi `logos.json`, tv-logos, iniziali (`monogram`).

## Test
```
dart pub get
dart test
```
La lista di esempio del prototipo è in `test/fixtures/sample_it.m3u`. Risultato atteso: 30 voci → 20 canali, 8 raggruppati.
