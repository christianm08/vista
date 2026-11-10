import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/source_store.dart';
import '../theme.dart';

/// Un film o un episodio da riprodurre.
class VodItem {
  const VodItem({required this.title, required this.subtitle, required this.url});
  final String title;
  final String subtitle;
  final String url;
}

/// Riproduzione on demand (film, episodi) con avanzamento.
///
/// Telecomando: OK pausa/riprendi, sinistra/destra −/+10 s (tenendo premuto
/// accelera), su/giù mostrano il pannello, canale +/− episodio successivo o
/// precedente. A fine episodio parte il successivo.
class VodPlayerScreen extends StatefulWidget {
  const VodPlayerScreen({super.key, required this.items, this.initialIndex = 0});

  final List<VodItem> items;
  final int initialIndex;

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  static const _overlayTimeout = Duration(seconds: 4);

  final _player = Player();
  late final _video = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  final _focus = FocusNode(debugLabel: 'vod');

  late int _index = widget.initialIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _overlay = true;
  String? _error;
  Timer? _overlayTimer;
  int _repeat = 0; // tasti tenuti premuti: il salto cresce

  VodItem get _item => widget.items[_index];
  bool get _hasNext => _index + 1 < widget.items.length;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }))
      ..add(_player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }))
      ..add(_player.stream.playing.listen((p) {
        if (!mounted) return;
        setState(() => _playing = p);
        p ? _scheduleHide() : _showOverlay(autoHide: false);
      }))
      ..add(_player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }))
      ..add(_player.stream.completed.listen((done) {
        if (done && _hasNext) _openAt(_index + 1);
      }))
      ..add(_player.stream.error.listen((e) {
        // Mai l'URL a schermo: con Xtream contiene le credenziali.
        if (mounted) {
          setState(() => _error =
              'Impossibile riprodurre questo contenuto.\n${redactError(e)}');
        }
      }));
    _openAt(_index);
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openAt(int i) {
    setState(() {
      _index = i;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffering = true;
    });
    _showOverlay();
    _player.open(Media(_item.url));
  }

  void _showOverlay({bool autoHide = true}) {
    setState(() => _overlay = true);
    if (autoHide) {
      _scheduleHide();
    } else {
      _overlayTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(_overlayTimeout, () {
      if (mounted && _playing && _error == null) setState(() => _overlay = false);
    });
  }

  void _togglePlay() {
    _player.playOrPause();
    _showOverlay();
  }

  void _seekBy(int seconds) {
    if (_duration == Duration.zero) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration - const Duration(seconds: 1);
    _player.seek(target);
    setState(() => _position = target);
    _showOverlay();
  }

  void _seekToFraction(double f) {
    if (_duration == Duration.zero) return;
    _player.seek(_duration * f.clamp(0.0, 1.0));
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) {
      _repeat = 0;
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (e is KeyRepeatEvent) _repeat++;
    final step = _repeat < 6 ? 10 : (_repeat < 20 ? 30 : 60);

    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-step);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(step);
    } else if (e is KeyRepeatEvent) {
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _togglePlay();
    } else if ((k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.mediaTrackNext) &&
        _hasNext) {
      _openAt(_index + 1);
    } else if ((k == LogicalKeyboardKey.channelDown ||
            k == LogicalKeyboardKey.mediaTrackPrevious) &&
        _index > 0) {
      _openAt(_index - 1);
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _showOverlay();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _overlay
              ? setState(() => _overlay = false)
              : _showOverlay(autoHide: _playing),
          onDoubleTapDown: (d) {
            final w = MediaQuery.sizeOf(context).width;
            _seekBy(d.localPosition.dx < w / 2 ? -10 : 10);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _video, controls: NoVideoControls),
              if (_buffering && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_error != null) _message(_error!),
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(ignoring: !_overlay, child: _controls()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Glass(
          padding: const EdgeInsets.all(24),
          fill: const Color(0x6B10161C),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(text, textAlign: TextAlign.center),
          ),
        ),
      );

  Widget _controls() {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final total = _duration.inMilliseconds;
    final progress = total == 0 ? 0.0 : _position.inMilliseconds / total;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(wide ? 40 : 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Glass(
            radius: VistaRadius.card,
            fill: const Color(0x6B10161C),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 40),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          if (_item.subtitle.isNotEmpty)
                            Text(_item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(color: VistaColors.textSecondary)),
                        ],
                      ),
                    ),
                    if (_hasNext)
                      GestureDetector(
                        onTap: () => _openAt(_index + 1),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Icon(Icons.skip_next_rounded, size: 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SeekBar(progress: progress, onSeek: _seekToFraction),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_fmt(_position), style: t.bodySmall),
                    const Spacer(),
                    if (wide)
                      Text('◀ ▶ 10 s · OK pausa',
                          style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
                    const Spacer(),
                    Text(_duration == Duration.zero ? '--:--' : _fmt(_duration),
                        style: t.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// Barra di avanzamento: si tocca o si trascina per saltare.
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.progress, required this.onSeek});
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void seek(double dx) => onSeek(dx / c.maxWidth);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => seek(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
        child: SizedBox(
          height: 20,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: VistaColors.glassActive),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: const ColoredBox(color: VistaColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
