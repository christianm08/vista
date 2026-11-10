import 'models.dart';

/// Parole chiave della qualità, in ordine di priorità. Solo parola intera:
/// "Rai 4" non è "Rai" in 4K.
final List<(Quality, RegExp)> _qualities = [
  (Quality.uhd4k, RegExp(r'\b(4k|uhd|2160p)\b', caseSensitive: false)),
  (Quality.fhd, RegExp(r'\b(fhd|1080p|1080i)\b', caseSensitive: false)),
  (Quality.hd, RegExp(r'\b(hd|720p)\b', caseSensitive: false)),
  (Quality.sd, RegExp(r'\b(sd|576p|576i|480p)\b', caseSensitive: false)),
];

/// `IT:`, `|IT|`, `[ITA]`, `(IT)`, `IT -`, `ITALIA:` all'inizio del nome.
final _countryPrefix = RegExp(
  r'^\s*[\[|(]?\s*(it|ita|italia)\s*[\]|):-]+\s*',
  caseSensitive: false,
);
final _backupParen = RegExp(r'\((backup|alt|bk|riserva)\)', caseSensitive: false);
final _noiseWords = RegExp(r'\b(backup|alt|h\.?265|hevc|50fps)\b', caseSensitive: false);
final _separators = RegExp(r'[|_]');
final _spaces = RegExp(r'\s+');
final _combiningMarks = RegExp('[̀-ͯ]');

/// Alias applicati al nome già in minuscolo e senza accenti.
final List<(RegExp, String)> aliases = [
  (RegExp(r'\brai uno\b'), 'rai 1'),
  (RegExp(r'\brai due\b'), 'rai 2'),
  (RegExp(r'\brai tre\b'), 'rai 3'),
  (RegExp(r'\bcanale\s*5\b'), 'canale 5'),
  (RegExp(r'\bitalia\s*1\b'), 'italia 1'),
  (RegExp(r'\brete\s*4\b'), 'rete 4'),
  (RegExp(r'\bla\s*7\b'), 'la7'),
  (RegExp(r'\btv\s*8\b'), 'tv8'),
  (RegExp(r'\brai\s*news\s*24\b'), 'rai news 24'),
  (RegExp(r'\bsky\s*tg\s*24\b'), 'sky tg24'),
];

/// Normalizza il nome di una voce: toglie il prefisso del paese, riconosce e
/// toglie la qualità, toglie `(backup)`/`alt`/`HEVC`/`H265`/`50fps`, passa a
/// minuscolo senza accenti e applica gli [aliases].
NormalizedName normalizeName(String name) {
  var n = name.replaceFirst(_countryPrefix, '');

  var q = Quality.auto;
  for (final (quality, re) in _qualities) {
    if (re.hasMatch(n)) {
      q = quality;
      break;
    }
  }
  for (final (_, re) in _qualities) {
    n = n.replaceAll(re, ' ');
  }

  n = n.replaceAll(_backupParen, ' ').replaceAll(_noiseWords, ' ');
  n = removeAccents(n)
      .toLowerCase()
      .replaceAll(_separators, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
  for (final (re, to) in aliases) {
    n = n.replaceAll(re, to);
  }
  n = n.replaceAll(_spaces, ' ').trim();
  return NormalizedName(n, q);
}

const _accentMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
  'ç': 'c', 'Ç': 'C', 'ñ': 'n', 'Ñ': 'N', 'ý': 'y', 'ÿ': 'y', 'Ý': 'Y',
};

/// Equivalente di `normalize('NFD').replace(/[̀-ͯ]/g, '')` per le
/// lettere latine comuni (Dart non ha la normalizzazione Unicode nel core).
String removeAccents(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_accentMap[ch] ?? ch);
  }
  return b.toString().replaceAll(_combiningMarks, '');
}

const _displayOverrides = {
  'la7': 'La7',
  'tv8': 'TV8',
  'sky tg24': 'Sky TG24',
  'dmax': 'DMAX',
  'cine34': 'Cine34',
  'rai 3 tgr lazio': 'Rai 3 TGR Lazio',
  'rai news 24': 'Rai News 24',
};
const _upperWords = {'tv', 'tg', 'tgr', 'hd', 'mtv'};

/// Nome da mostrare a partire dalla chiave normalizzata.
String displayName(String key) {
  final o = _displayOverrides[key];
  if (o != null) return o;
  return key
      .split(' ')
      .map((w) => _upperWords.contains(w)
          ? w.toUpperCase()
          : (w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)))
      .join(' ');
}

final _startsWithPlusOrDigit = RegExp(r'^[+\d]');
final _hasDigit = RegExp(r'\d');

/// Iniziali per il logo generato: `Rai 1` → `R1`, `Canale 5 +1` → `CA5+1`.
String monogram(String name) {
  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length <= 5 ? w : w.substring(0, 3)).toUpperCase();
  }
  final joined = words.map((w) {
    if (_startsWithPlusOrDigit.hasMatch(w)) return w;
    if (w.length > 3 && !_hasDigit.hasMatch(w)) return w.substring(0, 2);
    if (_hasDigit.hasMatch(w)) return w;
    return w[0];
  }).join().toUpperCase();
  return joined.length <= 5 ? joined : joined.substring(0, 5);
}
