import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/recordings.dart';
import '../data/stream_recorder.dart';
import '../data/source_store.dart' show redactError;
import '../data/user_store.dart';
import '../data/window_mode.dart';
import '../player/options_panel.dart';
import '../player/platform_player.dart';
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
/// I numeri portano al canale con quel numero; il tasto "canale precedente"
/// (o Backspace sul PC) torna al canale di prima.
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

  /// Nuovi tentativi sullo stesso flusso prima di passare al successivo.
  static const _maxRetries = 2;
  static const _typingTimeout = Duration(milliseconds: 1600);

  static final _digits = {
    for (final (i, k) in [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ].indexed)
      k: i,
    for (final (i, k) in [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ].indexed)
      k: i,
  };

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
  String _typed = '';
  Timer? _typingTimer;
  Timer? _retryTimer;
  Timer? _watchdog;
  Timer? _bannerTimer;
  bool _banner = true;
  bool _list = false;
  bool _playing = false;
  String? _message;
  int? _height;
  DateTime _now = DateTime.now();

  Channel get _channel => _channels[_channelIndex];
  late final UserStore _user;

  /// Tutti i canali visibili della fonte.
  List<Channel> get _allChannels => [
    for (final c
        in AppScope.of(context).library?.catalog.live.channels ??
            const <Channel>[])
      if (!c.hidden) c,
  ];

  void _notify(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(duration: const Duration(seconds: 2), content: Text(text)),
      );
  }

  bool get _favorite => _user.isFavorite(UserKey.channel(_channel.key));

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
    // Uscendo dal player la registrazione istantanea si chiude.
    _recording?.stop();
    PlayerPlatform.pip.removeListener(_onPip);
    PlayerPlatform.setAutoPip(false);
    PlayerPlatform.exitPip();
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _typingTimer?.cancel();
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
    if (_recording != null && old != null && old.key != _channels[i].key) {
      _stopRecording();
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

  /// Apre il flusso scelto ripartendo dal primo tentativo.
  void _openFresh() {
    _attempt = 0;
    _open();
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

  // --- numero del canale ---------------------------------------------------

  /// Il canale con un certo numero: prima fra quelli dello zapping, poi fra
  /// tutti.
  Channel? _byNumber(int n) =>
      _channels.where((c) => c.number == n).firstOrNull ??
      _allChannels.where((c) => c.number == n).firstOrNull;

  void _typeDigit(int d) {
    _typingTimer?.cancel();
    setState(() => _typed = _typed.length >= 4 ? '$d' : '$_typed$d');
    _typingTimer = Timer(_typingTimeout, _commitTyped);
  }

  void _eraseDigit() {
    _typingTimer?.cancel();
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
    if (_typed.isNotEmpty) {
      _typingTimer = Timer(_typingTimeout, _commitTyped);
    }
  }

  void _commitTyped() {
    _typingTimer?.cancel();
    final n = int.tryParse(_typed);
    if (!mounted) return;
    setState(() => _typed = '');
    if (n == null) return;
    final c = _byNumber(n);
    if (c == null) {
      _notify('Nessun canale con il numero $n');
    } else {
      _tuneTo(c);
    }
  }

  /// Decodifica predefinita del player (per tornarci dopo quella software).
  String? _hwdec;
  bool _canPip = false;

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

  /// Registrazione istantanea in corso.
  StreamRecorder? _recording;
  DateTime? _recordingSince;

  Future<void> _toggleRecording() async {
    if (_recording != null) {
      await _stopRecording();
      return;
    }
    final now = _now;
    final title = widget.guide?.nowOn(_channel, now: now)?.title ?? '';
    final store = AppScope.of(context).store;
    final service = RecordingService.instance;
    final f = await service.startInstant(
      streams: _channel.streams,
      channelName: _channel.name,
      title: title,
      headersFor: (url) {
        final ua = store.userAgentFor(url);
        return ua == null ? null : {'User-Agent': ua};
      },
    );
    if (!mounted) return;
    setState(() {
      _recording = f;
      _recordingSince = DateTime.now();
    });
    _notify(
      f == null
          ? (service.takeWarning() ?? 'Registrazione non disponibile.')
          : 'Registrazione avviata (${service.quality.label}, '
                '${service.quality.estimate(const Duration(hours: 1))} '
                'all\'ora): la trovi in Impostazioni › Registrazioni.',
    );
    // Se si ferma da sola (spazio finito, flusso caduto) il bollino sparisce.
    f?.done.then((_) {
      if (mounted && identical(_recording, f)) {
        setState(() {
          _recording = null;
          _recordingSince = null;
        });
        _notify('Registrazione fermata e salvata.');
      }
    });
  }

  Future<void> _stopRecording({bool quiet = false}) async {
    final rec = _recording;
    if (rec == null) return;
    // Prima si azzera, così l'avviso di "fermata da sola" non scatta.
    setState(() {
      _recording = null;
      _recordingSince = null;
    });
    await rec.stop();
    if (mounted && !quiet) _notify('Registrazione salvata.');
  }

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
    await _stopRecording();
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
              _openFresh();
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
                _openFresh();
                done();
              },
            ),
        ]),
      ...trackSections(_player, _tracks, _track, onPicked: done),
      pictureSection(_user, onPicked: done),
      PlayerOptionSection('Altro', [
        PlayerOption(
          icon: _recording == null
              ? Icons.fiber_manual_record_outlined
              : Icons.stop_circle_outlined,
          label: _recording == null ? 'Registra' : 'Ferma la registrazione',
          detail: _recording == null
              ? 'Salva il canale finché non la fermi o cambi canale'
              : 'In corso dalle ${hhmm(_recordingSince!)}',
          onTap: () {
            done();
            _toggleRecording();
          },
        ),
        if (_canPip)
          PlayerOption(
            icon: Icons.picture_in_picture_alt_rounded,
            label: PlayerPlatform.pipLabel,
            detail: 'Il canale resta visibile mentre fai altro',
            onTap: () {
              done();
              PlayerPlatform.enterPip();
            },
          ),
        if (PlayerPlatform.hasExternalPlayer)
          PlayerOption(
            icon: Icons.open_in_new_rounded,
            label: 'Apri con un altro player',
            detail: Platform.isWindows ? 'VLC' : 'VLC, MX Player…',
            onTap: () {
              done();
              _openExternal();
            },
          ),
        PlayerOption(
          icon: Icons.memory_rounded,
          label: _user.softwareDecode(_channel.key)
              ? 'Decodifica software (attiva)'
              : 'Decodifica software',
          detail: _user.softwareDecode(_channel.key)
              ? 'Torna alla decodifica hardware per questo canale'
              : 'Per questo canale, se il video scatta o si vede male',
          onTap: () {
            _user.setSoftwareDecode(
              _channel.key,
              !_user.softwareDecode(_channel.key),
            );
            done();
            _openFresh();
          },
        ),
        if (_previous case final p?)
          PlayerOption(
            icon: Icons.undo_rounded,
            label: 'Canale precedente',
            detail: '${p.number} · ${p.name}',
            onTap: () {
              done();
              _goPrevious();
            },
          ),
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
    final n = _channels.length;
    _tuneChannel((_channelIndex + delta + n) % n);
  }

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || _list || _options) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // Numero del canale: si digita, e dopo una breve pausa (o con OK) si va.
    if (_digits[k] case final d?) {
      if (e is KeyDownEvent) _typeDigit(d);
      return KeyEventResult.handled;
    }
    if (_typed.isNotEmpty) {
      if (e is KeyDownEvent && _isOk(k)) {
        _commitTyped();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace) {
        _eraseDigit();
        return KeyEventResult.handled;
      }
    }
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
                  if (_typed.isNotEmpty) _buildTyped(),
                  if (_recording != null)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: _RecBadge(),
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
                          _buildBanner(),
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
      ),
    );
  }

  /// Il numero che si sta digitando, con il canale che gli corrisponde.
  Widget _buildTyped() {
    final t = Theme.of(context).textTheme;
    final match = _byNumber(int.parse(_typed));
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Glass(
            fill: const Color(0xE610161C),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _typed,
                  style: t.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: VistaColors.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 16),
                if (match != null) ...[
                  ChannelLogo(channel: match, size: 44),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      match.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Nessun canale',
                    style: t.titleMedium?.copyWith(
                      color: VistaColors.textTertiary,
                    ),
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
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (v) => _chipsFocused = v,
                  onKeyEvent: (_, e) {
                    if (e is KeyUpEvent) return KeyEventResult.ignored;
                    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _rootFocus.requestFocus();
                      _showBanner();
                      return KeyEventResult.handled;
                    }
                    // Sotto i pulsanti non c'è altro.
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: SingleChildScrollView(
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
                          focusNode: _firstChip,
                        ),
                        _streamChip(
                          '⚙ Audio, sottotitoli e flussi',
                          false,
                          _openOptions,
                        ),
                        _streamChip('▦ Multiview', false, _openMultiview),
                        if (_previous case final p?)
                          _streamChip('↩ ${p.name}', false, _goPrevious),
                        if (_picker.streams.length > 1)
                          _streamChip('Auto', _picker.auto, () {
                            _picker.reset();
                            _openFresh();
                            _showBanner();
                          }),
                        if (_picker.streams.length > 1)
                          for (var i = 0; i < _picker.streams.length; i++)
                            _streamChip(
                              _picker.streams[i].quality.label,
                              !_picker.auto && _picker.index == i,
                              () {
                                _picker.select(i);
                                _openFresh();
                                _showBanner();
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _streamChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FocusCard(
        focusNode: focusNode,
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
                          itemCount: _channels.length,
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
    final c = _channels[i];
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

/// "● REC" sopra il video durante la registrazione.
class _RecBadge extends StatelessWidget {
  const _RecBadge();

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
