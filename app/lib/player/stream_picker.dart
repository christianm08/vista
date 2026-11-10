import 'package:vista_resolver/vista_resolver.dart';

/// Sceglie quale flusso di un canale riprodurre.
///
/// In "Auto" parte dal migliore (i flussi sono già ordinati 4K > … > SD) e,
/// se uno si blocca o va in errore, passa al successivo non ancora fallito.
class StreamPicker {
  StreamPicker(this.streams) : assert(streams.isNotEmpty);

  final List<ChannelStream> streams;
  final Set<int> _failed = {};
  int _index = 0;

  /// `true` finché l'utente non sceglie un flusso a mano.
  bool auto = true;

  int get index => _index;
  ChannelStream get current => streams[_index];
  bool get exhausted => _failed.length >= streams.length;

  /// Segna il flusso corrente come fallito e passa al prossimo disponibile.
  /// Restituisce `false` se non ce ne sono altri (o se la scelta è manuale).
  bool fail() {
    _failed.add(_index);
    if (!auto) return false;
    for (var step = 1; step <= streams.length; step++) {
      final j = (_index + step) % streams.length;
      if (!_failed.contains(j)) {
        _index = j;
        return true;
      }
    }
    return false;
  }

  /// Scelta manuale di un flusso.
  void select(int i) {
    auto = false;
    _index = i;
    _failed.remove(i);
  }

  /// Torna ad "Auto" ripartendo dal flusso migliore.
  void reset() {
    auto = true;
    _failed.clear();
    _index = 0;
  }
}

/// Qualità reale dall'altezza del video decodificato.
String qualityFromHeight(int? height) {
  if (height == null || height <= 0) return '';
  if (height >= 2160) return '4K';
  if (height >= 1080) return 'FHD';
  if (height >= 720) return 'HD';
  return 'SD';
}
