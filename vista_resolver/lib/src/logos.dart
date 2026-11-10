import 'dart:convert';

import 'models.dart';
import 'normalize.dart';

/// Elenco dei file del repository tv-logos, letto all'avvio dall'app.
final tvLogoTreeUri = Uri.parse(
    'https://api.github.com/repos/tv-logo/tv-logos/git/trees/main?recursive=1');

/// Percorsi dei file dalla risposta di `git/trees?recursive=1` di GitHub.
List<String> pathsFromGithubTree(String json) {
  final j = jsonDecode(json);
  if (j is! Map || j['tree'] is! List) {
    throw const FormatException('Risposta di GitHub inattesa');
  }
  return [
    for (final e in j['tree'] as List)
      if (e is Map && e['type'] == 'blob' && e['path'] is String)
        e['path'] as String,
  ];
}

/// Chiave compatta per abbinare canali e file di logo: senza spazi né
/// punteggiatura, `+` scritto per esteso. `canale 5 +1` → `canale5plus1`,
/// `rai news 24` e `rainews24` → `rainews24`.
String logoKey(String normalizedKey) => normalizedKey
    .toLowerCase()
    .replaceAll('+', 'plus')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Cartelle di tv-logos usate per l'indice, in ordine di priorità.
const tvLogoCountries = [
  'italy',
  'international',
  'world-europe',
  'united-kingdom',
  'united-states',
];

final _countryCode = RegExp(r'-[a-z]{2,4}$');
final _variantWords = {'hz', 'white', 'dark', 'light', 'color', 'colour', 'alt'};

/// Ricava chiave e priorità (più bassa = migliore) da un percorso del
/// repository tv-logos, es. `countries/italy/hd/rai-1-hd-it.png`.
/// Le versioni quadrate e colorate vincono su quelle orizzontali (`-hz`) o
/// bianche, la cartella principale su `hd/`.
({String key, int rank})? tvLogoEntry(
  String path, {
  List<String> countries = tvLogoCountries,
}) {
  final parts = path.split('/');
  if (parts.length < 3 || parts.first != 'countries') return null;
  final country = countries.indexOf(parts[1]);
  if (country < 0 || !parts.last.toLowerCase().endsWith('.png')) return null;

  var slug = parts.last.substring(0, parts.last.length - 4).toLowerCase();
  slug = slug.replaceFirst(_countryCode, '');
  var rank = country * 100 + (parts.length > 3 ? 10 : 0);
  final words = <String>[];
  for (final w in slug.split('-')) {
    if (w == 'hz') {
      rank += 2;
    } else if (_variantWords.contains(w)) {
      rank += 4;
    } else if (w.isNotEmpty) {
      words.add(w);
    }
  }
  if (words.isEmpty) return null;
  final key = logoKey(normalizeName(words.join(' ')).key);
  return key.isEmpty ? null : (key: key, rank: rank);
}

/// Indice chiave → percorso, tenendo per ogni chiave il file migliore.
Map<String, String> buildTvLogoIndex(
  Iterable<String> paths, {
  List<String> countries = tvLogoCountries,
}) {
  final best = <String, ({String path, int rank})>{};
  for (final p in paths) {
    final e = tvLogoEntry(p, countries: countries);
    if (e == null) continue;
    final cur = best[e.key];
    if (cur == null || e.rank < cur.rank) best[e.key] = (path: p, rank: e.rank);
  }
  final keys = best.keys.toList()..sort();
  return {for (final k in keys) k: best[k]!.path};
}

/// Loghi del repository github.com/tv-logo/tv-logos (pensati per sfondi
/// scuri), cercati per nome del canale e, in mancanza, per `tvg-id`.
class TvLogos {
  const TvLogos(this.index);

  static const baseUrl = 'https://raw.githubusercontent.com/tv-logo/tv-logos/main/';
  static const empty = TvLogos({});

  /// Chiave ([logoKey]) → percorso nel repository.
  final Map<String, String> index;

  String? pathFor(Channel c) {
    final byName = index[logoKey(c.key)];
    if (byName != null) return byName;
    if (c.tvgId.isEmpty) return null;
    // `Rai1.it@HD` → `rai1`
    final id = c.tvgId.split(RegExp(r'[.@]')).first;
    return index[logoKey(normalizeName(id).key)];
  }

  String? urlFor(Channel c) {
    final p = pathFor(c);
    return p == null ? null : '$baseUrl$p';
  }

  static String urlOf(String path) => '$baseUrl$path';

  /// Loghi il cui nome contiene la ricerca, i più corti (più simili) prima.
  List<String> search(String query, {int limit = 48}) {
    final q = logoKey(normalizeName(query).key);
    if (q.isEmpty) return const [];
    final hits = [for (final k in index.keys) if (k.contains(q)) k]
      ..sort((a, b) {
        final c = a.length.compareTo(b.length);
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final k in hits.take(limit)) urlOf(index[k]!)];
  }
}
