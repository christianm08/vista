import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/recordings.dart';
import '../data/stream_recorder.dart';

/// Registrazione istantanea del canale che si guarda (menu del player).
/// Si chiude cambiando canale, aprendo il Multiview o uscendo dal player.
class LiveRecording {
  LiveRecording({required this.onChanged, required this.notify});

  /// Registrazione partita o finita (da ridisegnare).
  final VoidCallback onChanged;
  final ValueChanged<String> notify;

  StreamRecorder? _recorder;
  DateTime? _since;
  bool _disposed = false;

  bool get active => _recorder != null;
  DateTime? get since => _since;

  Future<void> toggle({
    required Channel channel,
    required String title,
    required String? Function(String url) userAgentFor,
  }) async {
    if (active) return stop();
    final service = RecordingService.instance;
    final f = await service.startInstant(
      streams: channel.streams,
      channelName: channel.name,
      title: title,
      headersFor: (url) {
        final ua = userAgentFor(url);
        return ua == null ? null : {'User-Agent': ua};
      },
    );
    // Player chiuso mentre partiva: la registrazione non resta aperta.
    if (_disposed) {
      await f?.stop();
      return;
    }
    _recorder = f;
    _since = f == null ? null : DateTime.now();
    onChanged();
    notify(
      f == null
          ? (service.takeWarning() ?? 'Registrazione non disponibile.')
          : 'Registrazione avviata (${service.quality.label}, '
                '${service.quality.estimate(const Duration(hours: 1))} '
                'all\'ora): la trovi in Impostazioni › Registrazioni.',
    );
    // Se si ferma da sola (spazio finito, flusso caduto) il bollino sparisce.
    f?.done.then((_) {
      if (!_disposed && identical(_recorder, f)) {
        _recorder = null;
        _since = null;
        onChanged();
        notify('Registrazione fermata e salvata.');
      }
    });
  }

  Future<void> stop({bool quiet = false}) async {
    final rec = _recorder;
    if (rec == null) return;
    // Prima si azzera, così l'avviso di "fermata da sola" non scatta.
    _recorder = null;
    _since = null;
    onChanged();
    await rec.stop();
    if (!_disposed && !quiet) notify('Registrazione salvata.');
  }

  /// Uscendo dal player la registrazione si chiude.
  void dispose() {
    _disposed = true;
    _recorder?.stop();
  }
}

/// "● REC" sopra il video durante la registrazione.
class RecBadge extends StatelessWidget {
  const RecBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xCC000000),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 12, color: Color(0xFFFF5A5F)),
        SizedBox(width: 8),
        Text('REC', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
