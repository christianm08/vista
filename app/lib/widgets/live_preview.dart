import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../player/video.dart';
import '../theme.dart';
import 'channel_logo.dart';

/// Anteprima dal vivo del canale selezionato nella guida.
///
/// Parte dopo una breve pausa sul canale (scorrendo la guida non apre ogni
/// flusso), prova i flussi alternativi se uno non va e si spegne quando
/// [enabled] è false (es. mentre è aperto il player a schermo intero).
class LivePreview extends StatefulWidget {
  const LivePreview({super.key, required this.channel, this.enabled = true});

  final Channel? channel;
  final bool enabled;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  static const _settle = Duration(milliseconds: 900);
  static const _stall = Duration(seconds: 10);

  Player? _player;
  VideoController? _video;
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _debounce;
  Timer? _watchdog;
  String? _key;
  int _stream = 0;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(LivePreview old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      _stop();
    } else if (widget.channel?.key != _key || !old.enabled) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    final c = widget.channel;
    if (!widget.enabled || c == null) return;
    if (c.key != _key) {
      setState(() {
        _playing = false;
        _failed = false;
      });
      _player?.stop();
    }
    _debounce = Timer(_settle, () => _open(c, 0));
  }

  void _ensurePlayer() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _video = vistaVideoController(p);
    // Pronto solo quando arrivano i fotogrammi, non appena parte il caricamento.
    void ready() {
      _watchdog?.cancel();
      if (mounted && !_playing) setState(() => _playing = true);
    }

    _subs
      ..add(
        p.stream.height.listen((h) {
          if (h != null && h > 0) ready();
        }),
      )
      ..add(
        p.stream.position.listen((d) {
          if (d > const Duration(seconds: 2)) ready();
        }),
      )
      ..add(p.stream.error.listen((_) => _next()));
  }

  void _open(Channel c, int stream) {
    if (!mounted || !widget.enabled || c.streams.isEmpty) return;
    _ensurePlayer();
    _key = c.key;
    _stream = stream;
    setState(() {
      _playing = false;
      _failed = false;
    });
    _watchdog?.cancel();
    _watchdog = Timer(_stall, _next);
    _player!.open(Media(c.streams[stream].url));
  }

  void _next() {
    final c = widget.channel;
    if (!mounted || c == null || c.key != _key) return;
    if (_stream + 1 < c.streams.length) {
      _open(c, _stream + 1);
    } else {
      _watchdog?.cancel();
      _player?.stop();
      setState(() => _failed = true);
    }
  }

  void _stop() {
    _debounce?.cancel();
    _watchdog?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player?.dispose();
    _player = null;
    _video = null;
    _key = null;
    _playing = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: VistaColors.glassBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_video != null && widget.enabled)
              Video(controller: _video!, controls: NoVideoControls),
            if (!_playing && c != null)
              ColoredBox(
                color: const Color(0xFF0B0E13),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChannelLogo(channel: c, size: 56),
                      const SizedBox(height: 10),
                      if (_failed)
                        Text(
                          'Anteprima non disponibile',
                          style: t.bodySmall?.copyWith(
                            color: VistaColors.textTertiary,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
