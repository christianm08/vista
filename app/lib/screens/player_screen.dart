import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart' show redactError;
import '../data/user_store.dart';
import '../data/window_mode.dart';
import '../player/channel_number_entry.dart';
import '../player/live_banner.dart';
import '../player/live_channel_list.dart';
import '../player/live_options.dart';
import '../player/live_recording.dart';
import '../player/options_panel.dart';
import '../player/platform_player.dart';
import '../player/stream_picker.dart';
import '../player/video.dart';
import 'multiview_screen.dart';
import 'vod_player_screen.dart' show PlayerBackButton;
import '../theme.dart';

/// Riproduzione dal vivo a schermo intero con cambio flusso automatico.
///
/// Telecomando: su/giù o canale ± cambiano canale e mostrano la barra con il
/// programma; OK apre l'elenco dei canali sopra il video; destra/sinistra
/// mostrano la barra con la scelta del flusso; Indietro chiude o esce.
/// I numeri portano al canale con quel numero; il tasto "canale precedente"
/// (o Backspace sul PC) torna al canale di prima.
///
/// Qui restano la riproduzione (flussi, nuovi tentativi), lo zapping, i tasti
/// e i focus; barra, elenco, menu, numero digitato e registrazione sono in
/// `lib/player/`.
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

  /// Nuovi tentativi sullo stesso flusso prima di passare al successivo.
  static const _maxRetries = 2;

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

  /// Primo pulsante della barra (preferiti): Giù col telecomando ci arriva.
  final _firstChip = FocusNode(debugLabel: 'primo pulsante della barra');
  bool _chipsFocused = false;

  /// Canali fra cui si fa zapping: quelli da cui si è partiti, oppure tutti
  /// se si digita il numero di un canale che non è fra questi.
  late List<Channel> _channels = widget.channels;
  late int _channelIndex = widget.initialIndex;
  late StreamPicker _picker;
  Channel? _tuned;
  Channel? _previous;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _watchdog;
  Timer? _bannerTimer;
  bool _banner = true;
  bool _list = false;
  bool _playing = false;
  String? _message;
  int? _height;
  DateTime _now = DateTime.now();

  late final _number = ChannelNumberEntry(
    onChanged: _redraw,
    onCommit: _goToNumber,
  );
  late final _recording = LiveRecording(
    onChanged: _redraw,
    notify: (text) {
      if (mounted) _notify(text);
    },
  );

  Channel get _channel => _channels[_channelIndex];
  late final UserStore _user;

  /// Tutti i canali visibili della fonte.
  List<Channel> get _allChannels => [
    for (final c
        in AppScope.of(context).library?.catalog.live.channels ??
            const <Channel>[])
      if (!c.hidden) c,
  ];

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(duration: const Duration(seconds: 2), content: Text(text)),
      );
  }

  bool _isFavorite(Channel c) => _user.isFavorite(UserKey.channel(c.key));
  bool get _favorite => _isFavorite(_channel);

  void _toggleFavorite() {
    _user.toggleFavorite(UserKey.channel(_channel.key));
    setState(() {});
    _notify(
      _favorite
          ? '${_channel.name} aggiunto ai preferiti'
          : '${_channel.name} tolto dai preferiti',
    );
  }

  @override
  void initState() {
    super.initState();
    _user = AppScope.of(context).user;
    _user.addListener(_onUserChanged);
    PlayerPlatform.setAutoPip(true);
    PlayerPlatform.pip.addListener(_onPip);
    PlayerPlatform.canPip().then((v) {
      if (mounted) setState(() => _canPip = v);
    });
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
    _attempt = 0; // se si blocca di nuovo, si riprova da capo
    if (mounted && !_playing) setState(() => _playing = true);
  }

  /// Formato dell'immagine cambiato (anche da un altro player).
  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _recording.dispose();
    PlayerPlatform.pip.removeListener(_onPip);
    PlayerPlatform.setAutoPip(false);
    PlayerPlatform.exitPip();
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _number.dispose();
    _bannerTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _rootFocus.dispose();
    _listFocus.dispose();
    _firstChip.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  // --- canali ------------------------------------------------------------------

  void _tuneChannel(int i) {
    // Canale protetto dal PIN: prima lo si sblocca (poi si riprova).
    final parental = AppScope.of(context).parental;
    if (_tuned != null &&
        parental.isLocked(_channels[i]) &&
        !parental.isUnlocked) {
      parental
          .unlock(context, reason: '${_channels[i].name} è protetto dal PIN.')
          .then((ok) {
            if (ok && mounted) _tuneChannel(i);
          });
      return;
    }
    final old = _tuned;
    // Cambiando canale la registrazione istantanea si chiude.
    if (_recording.active && old != null && old.key != _channels[i].key) {
      _recording.stop();
    }
    _channelIndex = i;
    final key = _channel.key;
    if (old != null && old.key != key) _previous = old;
    _tuned = _channel;
    // Dopo il frame: chi ascolta (la home) non si ridisegna durante il build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _user.channelWatched(key),
    );
    _picker = StreamPicker(_channel.streams);
    _showBanner();
    _openFresh();
  }

  /// Porta su un canale anche se non è fra quelli dello zapping corrente
  /// (allora lo zapping passa a tutti i canali).
  void _tuneTo(Channel c) {
    var i = _channels.indexWhere((x) => x.key == c.key);
    if (i < 0) {
      final all = _allChannels;
      i = all.indexWhere((x) => x.key == c.key);
      if (i < 0) return;
      _channels = all;
    }
    if (i == _channelIndex && _channels[i].key == _tuned?.key) {
      _showBanner();
    } else {
      _tuneChannel(i);
    }
  }

  void _goPrevious() {
    final p = _previous;
    if (p == null) {
      _notify('Nessun canale precedente');
      return;
    }
    _tuneTo(p);
  }

  void _zap(int delta) {
    final n = _channels.length;
    _tuneChannel((_channelIndex + delta + n) % n);
  }

  /// Il canale con un certo numero: prima fra quelli dello zapping, poi fra
  /// tutti.
  Channel? _byNumber(int n) =>
      _channels.where((c) => c.number == n).firstOrNull ??
      _allChannels.where((c) => c.number == n).firstOrNull;

  void _goToNumber(int n) {
    if (!mounted) return;
    final c = _byNumber(n);
    if (c == null) {
      _notify('Nessun canale con il numero $n');
    } else {
      _tuneTo(c);
    }
  }

  // --- riproduzione ------------------------------------------------------------

  /// Decodifica predefinita del player (per tornarci dopo quella software).
  String? _hwdec;
  bool _canPip = false;

  /// Apre il flusso scelto ripartendo dal primo tentativo.
  void _openFresh() {
    _attempt = 0;
    _open();
  }

  void _open() {
    _retryTimer?.cancel();
    setState(() {
      _message = null;
      _height = null;
      _playing = false;
    });
    _armWatchdog();
    final url = _picker.current.url;
    PlayerPlatform.applyDecoder(
      _player,
      software: _user.softwareDecode(_channel.key),
      defaultHwdec: _hwdec,
    ).then((h) {
      _hwdec = h;
      // Nel frattempo si può essere passati a un altro flusso.
      if (mounted && _picker.current.url == url) {
        _player.open(streamMedia(context, url));
      }
    });
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_stallTimeout, () => _onFail('nessuna immagine'));
  }

  void _onFail(String why) {
    if (!mounted) return;
    // mpv può segnalare lo stesso errore più volte: un tentativo alla volta.
    if (_retryTimer?.isActive ?? false) return;
    _watchdog?.cancel();
    // Prima si riprova lo stesso flusso (cadute di rete, server lento)…
    if (_attempt < _maxRetries) {
      _attempt++;
      _notify(
        'Riconnessione a ${_channel.name}… '
        '(tentativo ${_attempt + 1} di ${_maxRetries + 1})',
      );
      setState(() {
        _playing = false;
        _message = null;
      });
      _retryTimer = Timer(Duration(seconds: 2 * _attempt), () {
        if (mounted) _open();
      });
      return;
    }
    // …poi si passa al flusso successivo, se c'è.
    _attempt = 0;
    if (_picker.fail()) {
      _notify('Flusso non disponibile ($why): provo il successivo');
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

  void _toggleRecording() => _recording.toggle(
    channel: _channel,
    title: widget.guide?.nowOn(_channel, now: _now)?.title ?? '',
    userAgentFor: AppScope.of(context).store.userAgentFor,
  );

  /// Entrando nel PiP o nella finestra mini i pannelli spariscono: il focus
  /// torna al player, così Esc e i tasti continuano a funzionare.
  void _onPip() {
    if (!mounted) return;
    setState(() {
      _options = false;
      _list = false;
      _banner = false;
    });
    _rootFocus.requestFocus();
  }

  Future<void> _openExternal() async {
    final ok = await PlayerPlatform.openExternal(
      _picker.current.url,
      _channel.name,
    );
    if (!ok && mounted) {
      _notify(
        Platform.isWindows
            ? 'Installa VLC per aprire i canali con un altro player.'
            : 'Nessun altro player installato.',
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
      // Mentre si sceglie un pulsante della barra, la barra resta aperta.
      if (mounted && _chipsFocused) {
        _showBanner();
        return;
      }
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
            _channelIndex * LiveChannelList.rowHeight -
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
    // Il focus passa prima al player: se restasse sul pulsante della barra
    // (fuori dal menu), l'autofocus del menu non lo prenderebbe e col
    // telecomando le frecce si muoverebbero dietro al menu.
    _rootFocus.requestFocus();
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
    _retryTimer?.cancel();
    // Il Multiview usa altri player: la registrazione di questo si chiude.
    await _recording.stop();
    await _player.stop();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<Channel>(
      MaterialPageRoute(
        builder: (_) => MultiviewScreen(
          channels: _channels,
          initial: [_channel],
          guide: widget.guide,
        ),
      ),
    );
    if (!mounted) return;
    final i = picked == null ? -1 : _channels.indexOf(picked);
    _tuneChannel(i >= 0 ? i : _channelIndex);
    // Dopo l'animazione di ritorno la route è di nuovo in primo piano.
    Future.delayed(const Duration(milliseconds: 350), _focusRoot);
  }

  List<PlayerOptionSection> _optionSections() => liveOptionSections(
    player: _player,
    picker: _picker,
    tracks: _tracks,
    track: _track,
    user: _user,
    channel: _channel,
    recording: _recording,
    canPip: _canPip,
    previous: _previous,
    onClose: _closeOptions,
    onReopen: _openFresh,
    onToggleRecording: _toggleRecording,
    onOpenExternal: _openExternal,
    onPrevious: _goPrevious,
    onMultiview: _openMultiview,
    onToggleFavorite: _toggleFavorite,
  );

  // --- tasti -------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || _list || _options) return KeyEventResult.ignored;
    // Numero del canale: si digita, e dopo una breve pausa (o con OK) si va.
    if (_number.handleKey(e) case final r?) return r;
    final k = e.logicalKey;
    // Canale precedente: tasto apposito del telecomando, Backspace sul PC.
    if (k == LogicalKeyboardKey.mediaLast ||
        k == LogicalKeyboardKey.backspace) {
      if (e is KeyDownEvent) _goPrevious();
      return KeyEventResult.handled;
    }
    // Tasto Menu: il menu del player (flusso, audio, sottotitoli, Multiview).
    if (k == LogicalKeyboardKey.contextMenu) {
      if (e is KeyDownEvent) _openOptions();
      return KeyEventResult.handled;
    }
    // Windows: dalla finestra mini, Esc torna alla finestra normale.
    if (k == LogicalKeyboardKey.escape && PlayerPlatform.pip.value) {
      if (e is KeyDownEvent) PlayerPlatform.exitPip();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      // A schermo intero Esc prima ne esce, poi torna indietro.
      if (e is KeyDownEvent && !WindowMode.leaveOnEscape()) {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    // OK apre sempre l'elenco dei canali, anche con la barra visibile, a meno
    // che il focus sia su un pulsante del flusso.
    if (e is KeyDownEvent && _rootFocus.hasPrimaryFocus && isOkKey(k)) {
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
      if (e is KeyDownEvent && isOkKey(k)) {
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
      // Telecomando: Giù porta sui pulsanti della barra (preferiti, menu,
      // Multiview, canale precedente, flussi); Su li lascia.
      if (k == LogicalKeyboardKey.arrowDown && _rootFocus.hasPrimaryFocus) {
        _showBanner();
        _firstChip.requestFocus();
        return KeyEventResult.handled;
      }
      _showBanner(); // qualsiasi tasto tiene aperta la barra
    }
    return KeyEventResult.ignored;
  }

  // --- interfaccia -------------------------------------------------------------

  /// Cambio di flusso dalla barra: la barra resta aperta.
  void _pickStream(void Function() change) {
    change();
    _openFresh();
    _showBanner();
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
            // Doppio clic: schermo intero sul PC, elenco canali al tocco.
            onDoubleTap: WindowMode.supported ? WindowMode.toggle : _openList,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 300) _zap(v < 0 ? 1 : -1);
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: PlayerPlatform.pip,
              // Nel riquadro PiP o nella finestra mini: solo il video (un
              // doppio clic sulla finestra mini torna alla finestra normale).
              builder: (context, pip, stack) => pip
                  ? PipView(video: formattedVideo(_video, _user.picture))
                  : stack!,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  formattedVideo(_video, _user.picture),
                  if (!_playing && _message == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_message != null) _buildMessage(),
                  if (!_number.isEmpty)
                    TypedChannelNumber(
                      typed: _number.typed,
                      match: _byNumber(int.parse(_number.typed)),
                    ),
                  if (_recording.active)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: RecBadge(),
                        ),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _banner ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_banner,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LiveBanner(
                            channel: _channel,
                            guide: widget.guide,
                            now: _now,
                            picker: _picker,
                            height: _height,
                            favorite: _favorite,
                            previous: _previous,
                            firstChip: _firstChip,
                            onChipsFocused: (v) => _chipsFocused = v,
                            onLeaveChips: () {
                              _rootFocus.requestFocus();
                              _showBanner();
                            },
                            onToggleFavorite: () {
                              _toggleFavorite();
                              _showBanner();
                            },
                            onOptions: _openOptions,
                            onMultiview: _openMultiview,
                            onPrevious: _goPrevious,
                            onAutoStream: () => _pickStream(_picker.reset),
                            onPickStream: (i) =>
                                _pickStream(() => _picker.select(i)),
                          ),
                          if (!Device.isTv)
                            const Align(
                              alignment: Alignment.topLeft,
                              child: PlayerBackButton(),
                            ),
                          const Align(
                            alignment: Alignment.topRight,
                            child: FullScreenButton(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  LiveChannelList(
                    open: _list,
                    channels: _channels,
                    currentIndex: _channelIndex,
                    guide: widget.guide,
                    now: _now,
                    isFavorite: _isFavorite,
                    scroll: _listScroll,
                    currentFocus: _listFocus,
                    onPick: (i) {
                      _closeList();
                      if (i != _channelIndex) _tuneChannel(i);
                    },
                    onToggleFavorite: (c) {
                      _user.toggleFavorite(UserKey.channel(c.key));
                      setState(() {});
                    },
                    onClose: _closeList,
                  ),
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
      ),
    );
  }

  Widget _buildMessage() {
    return Center(
      child: Glass(
        padding: const EdgeInsets.all(24),
        fill: const Color(0xCC10161C),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
