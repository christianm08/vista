import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../player/stream_picker.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/focus_card.dart';

/// Riproduzione a schermo intero con cambio flusso automatico.
///
/// Telecomando: su/giù cambia canale, OK mostra il pannello con la scelta
/// del flusso, Indietro chiude il pannello o esce.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channels, required this.initialIndex});

  final List<Channel> channels;
  final int initialIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _stallTimeout = Duration(seconds: 12);
  static const _overlayTimeout = Duration(seconds: 5);

  final _player = Player();
  late final _video = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  final _rootFocus = FocusNode(debugLabel: 'player');

  late int _channelIndex = widget.initialIndex;
  late StreamPicker _picker;
  Timer? _watchdog;
  Timer? _overlayTimer;
  bool _overlay = true;
  bool _playing = false;
  String? _message;
  int? _height;

  Channel get _channel => widget.channels[_channelIndex];

  @override
  void initState() {
    super.initState();
    _subs
      // Il testo dell'errore contiene l'URL (con Xtream, anche le credenziali).
      ..add(_player.stream.error.listen((_) => _onFail('errore di riproduzione')))
      ..add(_player.stream.playing.listen((p) {
        if (p) _watchdog?.cancel();
        if (mounted) setState(() => _playing = p);
      }))
      ..add(_player.stream.buffering.listen((b) {
        if (b) {
          _armWatchdog();
        } else if (_playing) {
          _watchdog?.cancel();
        }
      }))
      ..add(_player.stream.height.listen((h) {
        if (mounted) setState(() => _height = h);
      }));
    _tuneChannel(_channelIndex);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _overlayTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _tuneChannel(int i) {
    _channelIndex = i;
    _picker = StreamPicker(_channel.streams);
    _showOverlay();
    _open();
  }

  void _open() {
    setState(() {
      _message = null;
      _height = null;
      _playing = false;
    });
    _armWatchdog();
    _player.open(Media(_picker.current.url));
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_stallTimeout, () => _onFail('nessuna immagine'));
  }

  void _onFail(String why) {
    if (!mounted) return;
    _watchdog?.cancel();
    if (_picker.fail()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Flusso non disponibile ($why): provo il successivo'),
      ));
      _open();
    } else {
      _player.stop();
      setState(() => _message = _picker.auto
          ? 'Nessun flusso di ${_channel.name} funziona in questo momento.'
          : 'Questo flusso non funziona ($why). Prova "Auto" o un altro flusso.');
    }
  }

  void _showOverlay() {
    setState(() => _overlay = true);
    _overlayTimer?.cancel();
    _overlayTimer = Timer(_overlayTimeout, () {
      if (mounted && _message == null) {
        setState(() => _overlay = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _hideOverlay() {
    _overlayTimer?.cancel();
    setState(() => _overlay = false);
    _rootFocus.requestFocus();
  }

  void _zap(int delta) {
    final n = widget.channels.length;
    _tuneChannel((_channelIndex + delta + n) % n);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (!_overlay) {
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
        _zap(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
        _zap(1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        _showOverlay();
        return KeyEventResult.handled;
      }
    } else {
      _showOverlay(); // qualsiasi tasto tiene aperto il pannello
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_overlay || _message != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hideOverlay();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _overlay ? _hideOverlay() : _showOverlay(),
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 300) _zap(v < 0 ? 1 : -1);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(controller: _video, controls: NoVideoControls),
                if (!_playing && _message == null)
                  const Center(child: CircularProgressIndicator()),
                if (_message != null) _buildMessage(),
                AnimatedOpacity(
                  opacity: _overlay ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(ignoring: !_overlay, child: _buildOverlay()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage() {
    return Center(
      child: Glass(
        padding: const EdgeInsets.all(24),
        fill: const Color(0x6B10161C),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final t = Theme.of(context).textTheme;
    final real = qualityFromHeight(_height);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(wide ? 40 : 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Glass(
            radius: VistaRadius.card,
            fill: const Color(0x6B10161C),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChannelLogo(channel: _channel, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_channel.number}  ${_channel.name}',
                              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            [
                              _picker.auto ? 'Auto' : 'Manuale',
                              'flusso ${_picker.index + 1}/${_picker.streams.length}',
                              if (real.isNotEmpty) 'reale $real ($_height p)',
                            ].join(' · '),
                            style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_picker.streams.length > 1) ...[
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _streamChip('Auto', _picker.auto, () {
                          _picker.reset();
                          _open();
                          _showOverlay();
                        }),
                        for (var i = 0; i < _picker.streams.length; i++)
                          _streamChip(
                            _picker.streams[i].quality.label,
                            !_picker.auto && _picker.index == i,
                            () {
                              _picker.select(i);
                              _open();
                              _showOverlay();
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _streamChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FocusCard(
        radius: 999,
        selected: selected,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
