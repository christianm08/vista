import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart' show redactError;
import '../data/user_store.dart';
import '../player/options_panel.dart';
import '../player/stream_picker.dart';
import '../player/video.dart';
import 'multiview_screen.dart';
import 'vod_player_screen.dart' show PlayerBackButton;
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart';
import '../widgets/focus_card.dart';

/// Riproduzione dal vivo a schermo intero con cambio flusso automatico.
///
/// Telecomando: su/giù o canale ± cambiano canale e mostrano la barra con il
/// programma; OK apre l'elenco dei canali sopra il video; destra/sinistra
/// mostrano la barra con la scelta del flusso; Indietro chiude o esce.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
    this.guide,
  });

  final List<Channel> channels;
  final int initialIndex;
  final EpgGuide? guide;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _stallTimeout = Duration(seconds: 12);
  static const _bannerTimeout = Duration(seconds: 5);
  static const _listRow = 64.0;

  final _player = Player(
    configuration: const PlayerConfiguration(
      logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
    ),
  );
  late final _video = vistaVideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  final _rootFocus = FocusNode(debugLabel: 'player');
  final _listFocus = FocusNode(debugLabel: 'canale corrente nell\'elenco');
  final _listScroll = ScrollController();

  late int _channelIndex = widget.initialIndex;
  late StreamPicker _picker;
  Timer? _watchdog;
  Timer? _bannerTimer;
  bool _banner = true;
  bool _list = false;
  bool _playing = false;
  String? _message;
  int? _height;
  DateTime _now = DateTime.now();

  Channel get _channel => widget.channels[_channelIndex];
  late final UserStore _user;

  bool get _favorite => _user.isFavorite(UserKey.channel(_channel.key));

  void _toggleFavorite() {
    _user.toggleFavorite(UserKey.channel(_channel.key));
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            _favorite
                ? '${_channel.name} aggiunto ai preferiti'
                : '${_channel.name} tolto dai preferiti',
          ),
        ),
      );
  }

  @override
  void initState() {
    super.initState();
    _user = AppScope.of(context).user;
    _subs
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
      // Il testo dell'errore contiene l'URL (con Xtream, anche le credenziali).
      ..add(
        _player.stream.error.listen((_) => _onFail('errore di riproduzione')),
      )
      // "playing" diventa vero appena parte il caricamento: il canale funziona
      // davvero solo quando arrivano i fotogrammi (o l'audio avanza).
      ..add(
        _player.stream.height.listen((h) {
          if (h != null && h > 0) _onFrames();
          if (mounted) setState(() => _height = h);
        }),
      )
      ..add(
        _player.stream.position.listen((p) {
          if (p > const Duration(seconds: 2)) _onFrames();
        }),
      )
      ..add(
        _player.stream.buffering.listen((b) {
          if (b && _playing) _armWatchdog();
          if (!b && _playing) _watchdog?.cancel();
        }),
      );
    if (kDebugMode) {
      _subs.add(
        _player.stream.log.listen(
          (l) => debugPrint(redactError('mpv ${l.prefix}: ${l.text}')),
        ),
      );
    }
    _tuneChannel(_channelIndex);
  }

  void _onFrames() {
    _watchdog?.cancel();
    if (mounted && !_playing) setState(() => _playing = true);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _bannerTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _rootFocus.dispose();
    _listFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _tuneChannel(int i) {
    _channelIndex = i;
    final key = _channel.key;
    // Dopo il frame: chi ascolta (la home) non si ridisegna durante il build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _user.channelWatched(key),
    );
    _picker = StreamPicker(_channel.streams);
    _showBanner();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Flusso non disponibile ($why): provo il successivo'),
        ),
      );
      _open();
    } else {
      _player.stop();
      setState(
        () => _message = _picker.auto
            ? 'Nessun flusso di ${_channel.name} funziona in questo momento.'
            : 'Questo flusso non funziona ($why). Prova "Auto" o un altro flusso.',
      );
    }
  }

  // --- pannelli ----------------------------------------------------------------

  void _showBanner() {
    setState(() {
      _banner = true;
      _now = DateTime.now();
    });
    _bannerTimer?.cancel();
    _bannerTimer = Timer(_bannerTimeout, () {
      if (mounted && _message == null) {
        setState(() => _banner = false);
        if (!_list) _focusRoot();
      }
    });
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    setState(() => _banner = false);
    _focusRoot();
  }

  void _openList() {
    _bannerTimer?.cancel();
    setState(() {
      _list = true;
      _banner = false;
      _now = DateTime.now();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listScroll.hasClients) {
        final target =
            _channelIndex * _listRow -
            _listScroll.position.viewportDimension / 2;
        _listScroll.jumpTo(
          target.clamp(0.0, _listScroll.position.maxScrollExtent),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _listFocus.context != null) _listFocus.requestFocus();
      });
    });
  }

  /// Il focus torna al player solo se è la schermata in primo piano: i timer
  /// (es. la barra che si nasconde) non devono rubarlo al Multiview.
  void _focusRoot() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) _rootFocus.requestFocus();
  }

  void _closeList() {
    setState(() => _list = false);
    _focusRoot();
  }

  // --- menu del player ---------------------------------------------------------

  bool _options = false;
  Tracks _tracks = const Tracks();
  Track _track = const Track();

  void _openOptions() {
    _bannerTimer?.cancel();
    setState(() {
      _options = true;
      _banner = false;
    });
  }

  void _closeOptions() {
    setState(() => _options = false);
    _focusRoot();
  }

  /// Multiview: il player a schermo intero si ferma (un decoder in meno) e
  /// riparte al ritorno, sul canale scelto se ne è stato scelto uno.
  Future<void> _openMultiview() async {
    _bannerTimer?.cancel();
    setState(() {
      _options = false;
      _list = false;
      _banner = false;
    });
    _watchdog?.cancel();
    await _player.stop();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<Channel>(
      MaterialPageRoute(
        builder: (_) => MultiviewScreen(
          channels: widget.channels,
          initial: [_channel],
          guide: widget.guide,
        ),
      ),
    );
    if (!mounted) return;
    final i = picked == null ? -1 : widget.channels.indexOf(picked);
    _tuneChannel(i >= 0 ? i : _channelIndex);
    // Dopo l'animazione di ritorno la route è di nuovo in primo piano.
    Future.delayed(const Duration(milliseconds: 350), _focusRoot);
  }

  List<PlayerOptionSection> _optionSections() {
    void done() => _closeOptions();
    return [
      if (_picker.streams.length > 1)
        PlayerOptionSection('Flusso', [
          PlayerOption(
            label: 'Automatico',
            detail:
                'Il migliore che funziona; se si blocca passa al successivo',
            selected: _picker.auto,
            onTap: () {
              _picker.reset();
              _open();
              done();
            },
          ),
          for (var i = 0; i < _picker.streams.length; i++)
            PlayerOption(
              label: 'Flusso ${i + 1} · ${_picker.streams[i].quality.label}',
              detail: _picker.streams[i].sourceName,
              selected: !_picker.auto && _picker.index == i,
              onTap: () {
                _picker.select(i);
                _open();
                done();
              },
            ),
        ]),
      ...trackSections(_player, _tracks, _track, onPicked: done),
      PlayerOptionSection('Altro', [
        PlayerOption(
          icon: Icons.grid_view_rounded,
          label: 'Multiview',
          detail: 'Fino a 4 canali insieme',
          onTap: _openMultiview,
        ),
        PlayerOption(
          icon: _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
          label: _favorite ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
          onTap: () {
            _toggleFavorite();
            done();
          },
        ),
      ]),
    ];
  }

  void _zap(int delta) {
    final n = widget.channels.length;
    _tuneChannel((_channelIndex + delta + n) % n);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || _list || _options) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // Tasto Menu: il menu del player (flusso, audio, sottotitoli, Multiview).
    if (k == LogicalKeyboardKey.contextMenu) {
      if (e is KeyDownEvent) _openOptions();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (e is KeyDownEvent) Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    // OK apre sempre l'elenco dei canali, anche con la barra visibile, a meno
    // che il focus sia su un pulsante del flusso.
    if (e is KeyDownEvent &&
        _rootFocus.hasPrimaryFocus &&
        (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter)) {
      _openList();
      return KeyEventResult.handled;
    }
    if (!_banner) {
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.channelUp) {
        _zap(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.channelDown) {
        _zap(1);
        return KeyEventResult.handled;
      }
      if (e is KeyDownEvent &&
          (k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter)) {
        _openList();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.info) {
        _showBanner();
        return KeyEventResult.handled;
      }
    } else {
      // Con la barra aperta i canale ± continuano a cambiare canale.
      if (k == LogicalKeyboardKey.channelUp) {
        _zap(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.channelDown) {
        _zap(1);
        return KeyEventResult.handled;
      }
      _showBanner(); // qualsiasi tasto tiene aperta la barra
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_list && !_options && (!_banner || _message != null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_options) {
          _closeOptions();
        } else if (_list) {
          _closeList();
        } else {
          _hideBanner();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_list) {
                _closeList();
              } else {
                _banner ? _hideBanner() : _showBanner();
              }
            },
            onDoubleTap: _openList,
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
                  opacity: _banner ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_banner,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildBanner(),
                        if (!Device.isTv)
                          const Align(
                            alignment: Alignment.topLeft,
                            child: PlayerBackButton(),
                          ),
                      ],
                    ),
                  ),
                ),
                _buildList(),
                PlayerOptionsPanel(
                  open: _options,
                  title: _channel.name,
                  sections: _options ? _optionSections() : const [],
                  onClose: _closeOptions,
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
        blur: false,
        padding: const EdgeInsets.all(24),
        fill: const Color(0xCC10161C),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  /// Barra in basso: canale, programma in onda e successivo, flussi.
  Widget _buildBanner() {
    final t = Theme.of(context).textTheme;
    final real = qualityFromHeight(_height);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final upcoming =
        widget.guide?.upcoming(_channel, now: _now, count: 2) ?? const [];
    final current = upcoming.where((p) => p.isOnAt(_now)).firstOrNull;
    final next = upcoming.where((p) => p.start.isAfter(_now)).firstOrNull;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          wide ? 40 : 16,
          48,
          wide ? 40 : 16,
          wide ? 28 : 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xE6000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${_channel.number}',
                    style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VistaColors.accent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ChannelLogo(channel: _channel, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            color: VistaColors.textSecondary,
                          ),
                        ),
                        Text(
                          current?.title ??
                              'Nessuna informazione sul programma',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const VistaClock(),
                        Text(
                          [
                            _picker.auto ? 'Auto' : 'Manuale',
                            if (_picker.streams.length > 1)
                              'flusso ${_picker.index + 1}/${_picker.streams.length}',
                            if (real.isNotEmpty) '$real · ${_height}p',
                          ].join(' · '),
                          style: t.bodySmall?.copyWith(
                            color: VistaColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      hhmm(current.start),
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: current.progressAt(_now),
                          minHeight: 5,
                          backgroundColor: VistaColors.glassActive,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hhmm(current.stop),
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              if (next != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Dopo · ${hhmm(next.start)}  ${next.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    color: VistaColors.textSecondary,
                  ),
                ),
              ],
              ...[
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _streamChip(
                        _favorite ? '★ Preferito' : '☆ Aggiungi ai preferiti',
                        false,
                        () {
                          _toggleFavorite();
                          _showBanner();
                        },
                      ),
                      _streamChip(
                        '⚙ Audio, sottotitoli e flussi',
                        false,
                        _openOptions,
                      ),
                      _streamChip('▦ Multiview', false, _openMultiview),
                      if (_picker.streams.length > 1)
                        _streamChip('Auto', _picker.auto, () {
                          _picker.reset();
                          _open();
                          _showBanner();
                        }),
                      if (_picker.streams.length > 1)
                        for (var i = 0; i < _picker.streams.length; i++)
                          _streamChip(
                            _picker.streams[i].quality.label,
                            !_picker.auto && _picker.index == i,
                            () {
                              _picker.select(i);
                              _open();
                              _showBanner();
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

  /// Elenco dei canali sopra il video (OK): si cambia canale senza uscire.
  Widget _buildList() {
    final t = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: !_list,
      child: ExcludeFocus(
        excluding: !_list,
        child: AnimatedOpacity(
          opacity: _list ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Row(
            children: [
              Container(
                width: 360,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xF2080A0E), Color(0xD9080A0E)],
                  ),
                ),
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                        child: Row(
                          children: [
                            Text(
                              'Canali',
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            const VistaClock(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _listScroll,
                          itemExtent: _listRow,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: widget.channels.length,
                          itemBuilder: (_, i) => _listItem(i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeList,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listItem(int i) {
    final t = Theme.of(context).textTheme;
    final c = widget.channels[i];
    final now = widget.guide?.nowOn(c, now: _now);
    final playing = i == _channelIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FocusCard(
        focusNode: playing ? _listFocus : null,
        radius: 12,
        focusScale: 1.02,
        fill: playing ? VistaColors.glassActive : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        onTap: () {
          _closeList();
          if (i != _channelIndex) _tuneChannel(i);
        },
        onLongPress: () {
          _user.toggleFavorite(UserKey.channel(c.key));
          setState(() {});
        },
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${c.number}',
                style: t.labelLarge?.copyWith(
                  color: playing
                      ? VistaColors.accent
                      : VistaColors.textTertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ChannelLogo(channel: c, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (now != null)
                    Text(
                      now.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (_user.isFavorite(UserKey.channel(c.key)))
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: VistaColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
