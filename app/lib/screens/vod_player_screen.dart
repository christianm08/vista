import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../data/user_store.dart';
import '../player/video.dart';
import '../theme.dart';

/// Un film o un episodio da riprodurre.
class VodItem {
  const VodItem({
    required this.title,
    required this.subtitle,
    required this.url,
    this.key,
    this.image = '',
    this.seriesId,
    this.startAt,
  });
  final String title;
  final String subtitle;
  final String url;

  /// Chiave per salvare l'avanzamento (`mv:` / `ep:`); senza, non si salva.
  final String? key;
  final String image;
  final String? seriesId;

  /// Da dove ripartire.
  final Duration? startAt;
}

/// Riproduzione on demand (film, episodi) con avanzamento.
///
/// Telecomando: OK pausa/riprendi, sinistra/destra −/+10 s (tenendo premuto
/// accelera), su/giù mostrano il pannello, canale +/− episodio successivo o
/// precedente. A fine episodio parte il successivo.
class VodPlayerScreen extends StatefulWidget {
  const VodPlayerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  final List<VodItem> items;
  final int initialIndex;

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  static const _overlayTimeout = Duration(seconds: 4);

  final _player = Player();
  late final _video = vistaVideoController(_player);
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

  UserStore? _user;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  Tracks _tracks = const Tracks();
  Track _track = const Track();

  /// Salva il punto di visione (ogni 10 s, al cambio e all'uscita).
  void _saveProgress({bool force = false}) {
    final key = _item.key;
    final user = _user;
    if (key == null || user == null || _duration <= Duration.zero) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSave) < const Duration(seconds: 10)) {
      return;
    }
    _lastSave = now;
    user.saveProgress(
      WatchProgress(
        key: key,
        position: _position,
        duration: _duration,
        updatedAt: now,
        title: _item.title,
        subtitle: _item.subtitle,
        image: _item.image,
        seriesId: _item.seriesId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _user = AppScope.of(context).user;
    _subs
      ..add(
        _player.stream.position.listen((p) {
          if (!mounted) return;
          setState(() => _position = p);
          if (_playing) _saveProgress();
        }),
      )
      ..add(
        _player.stream.tracks.listen((t) {
          if (mounted) setState(() => _tracks = t);
        }),
      )
      ..add(
        _player.stream.track.listen((t) {
          if (mounted) setState(() => _track = t);
        }),
      )
      ..add(
        _player.stream.duration.listen((d) {
          if (mounted) setState(() => _duration = d);
        }),
      )
      ..add(
        _player.stream.playing.listen((p) {
          if (!mounted) return;
          setState(() => _playing = p);
          p ? _scheduleHide() : _showOverlay(autoHide: false);
        }),
      )
      ..add(
        _player.stream.buffering.listen((b) {
          if (mounted) setState(() => _buffering = b);
        }),
      )
      ..add(
        _player.stream.completed.listen((done) {
          if (!done) return;
          if (_duration > Duration.zero) _position = _duration;
          _saveProgress(force: true);
          if (_hasNext) _openAt(_index + 1);
        }),
      )
      ..add(
        _player.stream.error.listen((e) {
          // Mai l'URL a schermo: con Xtream contiene le credenziali.
          if (mounted) {
            setState(
              () => _error =
                  'Impossibile riprodurre questo contenuto.\n${redactError(e)}',
            );
          }
        }),
      );
    _openAt(_index);
  }

  @override
  void dispose() {
    // Dopo lo smontaggio: chi ascolta (la home) può ridisegnarsi senza
    // toccare un albero bloccato.
    Future.microtask(() => _saveProgress(force: true));
    _overlayTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openAt(int i) {
    if (i != _index) _saveProgress(force: true);
    setState(() {
      _index = i;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffering = true;
    });
    _showOverlay();
    _player.open(Media(_item.url, start: _item.startAt));
  }

  /// Audio e sottotitoli: un pannello con le tracce del file.
  Future<void> _openTracks() async {
    _overlayTimer?.cancel();
    final audio = [
      for (final a in _tracks.audio)
        if (a.id != 'no') a,
    ];
    final subs = _tracks.subtitle;
    String label(String id, String? title, String? language, String fallback) {
      final parts = [
        if (language != null && language.isNotEmpty) language.toUpperCase(),
        if (title != null && title.isNotEmpty) title,
      ];
      if (id == 'auto') return 'Automatico';
      if (id == 'no') return 'Disattivati';
      return parts.isEmpty ? fallback : parts.join(' · ');
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
          child: ListView(
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children: [
              const _TrackHeader('Audio'),
              if (audio.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Una sola traccia',
                    style: TextStyle(color: VistaColors.textTertiary),
                  ),
                ),
              for (final (i, a) in audio.indexed)
                _TrackTile(
                  label: label(a.id, a.title, a.language, 'Traccia ${i + 1}'),
                  selected: _track.audio.id == a.id,
                  autofocus: _track.audio.id == a.id,
                  onTap: () {
                    _player.setAudioTrack(a);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 16),
              const _TrackHeader('Sottotitoli'),
              for (final (i, s) in subs.indexed)
                _TrackTile(
                  label: label(
                    s.id,
                    s.title,
                    s.language,
                    'Sottotitoli ${i + 1}',
                  ),
                  selected: _track.subtitle.id == s.id,
                  onTap: () {
                    _player.setSubtitleTrack(s);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _showOverlay(autoHide: _playing);
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
      if (mounted && _playing && _error == null) {
        setState(() => _overlay = false);
      }
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
    if (k == LogicalKeyboardKey.escape) {
      if (e is KeyDownEvent) Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) _repeat++;
    final step = _repeat < 6 ? 10 : (_repeat < 20 ? 30 : 60);

    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-step);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
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
    } else if ((k == LogicalKeyboardKey.channelUp ||
            k == LogicalKeyboardKey.mediaTrackNext) &&
        _hasNext) {
      _openAt(_index + 1);
    } else if ((k == LogicalKeyboardKey.channelDown ||
            k == LogicalKeyboardKey.mediaTrackPrevious) &&
        _index > 0) {
      _openAt(_index - 1);
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.contextMenu) {
      // Giù a pannello visibile (o Menu): audio e sottotitoli.
      _overlay || k == LogicalKeyboardKey.contextMenu
          ? _openTracks()
          : _showOverlay();
    } else if (k == LogicalKeyboardKey.arrowUp) {
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
        // Col mouse basta muoversi sul video per vedere i controlli.
        child: MouseRegion(
          onHover: (_) {
            if (!_overlay) _showOverlay(autoHide: _playing);
          },
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
                  child: IgnorePointer(
                    ignoring: !_overlay,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _controls(),
                        if (!Device.isTv)
                          const Align(
                            alignment: Alignment.topLeft,
                            child: PlayerBackButton(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_item.subtitle.isNotEmpty)
                            Text(
                              _item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: VistaColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _openTracks,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Icon(Icons.subtitles_outlined, size: 28),
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
                      Text(
                        '◀ ▶ 10 s · OK pausa · ▼ audio e sottotitoli',
                        style: t.bodySmall?.copyWith(
                          color: VistaColors.textTertiary,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _duration == Duration.zero ? '--:--' : _fmt(_duration),
                      style: t.bodySmall,
                    ),
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
    return LayoutBuilder(
      builder: (context, c) {
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
      },
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      autofocus: autofocus,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      focusColor: VistaColors.glassActive,
      hoverColor: VistaColors.glassHigh,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? VistaColors.accent : VistaColors.textTertiary,
      ),
      title: Text(label),
      onTap: onTap,
    ),
  );
}

/// Freccia "Indietro" per mouse e tocco (su TV c'è il tasto del telecomando).
class PlayerBackButton extends StatelessWidget {
  const PlayerBackButton({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: IconButton(
        tooltip: 'Indietro',
        style: IconButton.styleFrom(backgroundColor: const Color(0x80000000)),
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
  );
}
