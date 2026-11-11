import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../player/stream_picker.dart';
import '../player/video.dart';
import '../theme.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_guide.dart' show hhmm;
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';
import 'vod_player_screen.dart' show PlayerBackButton;

/// Un riquadro del Multiview: un canale col suo player.
class _Tile {
  _Tile(this.channel) : picker = StreamPicker(channel.streams) {
    video = vistaVideoController(player);
  }

  Channel channel;
  StreamPicker picker;
  final player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
  );
  late final VideoController video;
  final focus = FocusNode(debugLabel: 'riquadro multiview');
  final subs = <StreamSubscription<dynamic>>[];
  Timer? watchdog;
  bool playing = false;
  bool failed = false;

  void dispose() {
    watchdog?.cancel();
    for (final s in subs) {
      s.cancel();
    }
    player.dispose();
    focus.dispose();
  }
}

/// Multiview: fino a 4 canali insieme (2 affiancati, 3-4 in griglia 2×2).
/// L'audio è del riquadro col focus. OK su un riquadro: cambia canale,
/// schermo intero o rimuovi; OK su "Aggiungi": sceglie un canale.
/// Restituisce il canale da guardare a schermo intero, se scelto.
class MultiviewScreen extends StatefulWidget {
  const MultiviewScreen({
    super.key,
    required this.channels,
    required this.initial,
    this.guide,
  });

  final List<Channel> channels;
  final List<Channel> initial;
  final EpgGuide? guide;

  static const maxTiles = 4;

  @override
  State<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _MultiviewScreenState extends State<MultiviewScreen> {
  static const _stall = Duration(seconds: 15);

  final _tiles = <_Tile>[];
  final _addFocus = FocusNode(debugLabel: 'aggiungi canale');
  int _audio = 0;
  DateTime _now = DateTime.now();
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    for (final c in widget.initial.take(MultiviewScreen.maxTiles)) {
      _add(c);
    }
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // Si parte su "Aggiungi": il motivo per aprire il Multiview. Di nuovo
    // a fine animazione, quando la route ha davvero il focus.
    void focusStart() {
      if (!mounted) return;
      final inside = _tiles.any((t) => t.focus.hasFocus) || _addFocus.hasFocus;
      if (!inside) {
        (_tiles.length < MultiviewScreen.maxTiles ? _addFocus : _tiles.first.focus).requestFocus();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => focusStart());
    Future.delayed(const Duration(milliseconds: 400), focusStart);
  }

  @override
  void dispose() {
    _clock.cancel();
    for (final t in _tiles) {
      t.dispose();
    }
    _addFocus.dispose();
    super.dispose();
  }

  void _add(Channel c) {
    final t = _Tile(c);
    t.subs
      ..add(t.player.stream.error.listen((_) => _fail(t)))
      ..add(
        t.player.stream.height.listen((h) {
          if (h != null && h > 0) _ok(t);
        }),
      )
      ..add(
        t.player.stream.position.listen((p) {
          if (p > const Duration(seconds: 2)) _ok(t);
        }),
      );
    t.focus.addListener(() {
      if (t.focus.hasFocus) _setAudio(_tiles.indexOf(t));
    });
    setState(() => _tiles.add(t));
    _open(t);
    _applyVolumes();
  }

  void _open(_Tile t) {
    t.playing = false;
    t.failed = false;
    t.watchdog?.cancel();
    t.watchdog = Timer(_stall, () => _fail(t));
    t.player.open(Media(t.picker.current.url));
  }

  void _ok(_Tile t) {
    t.watchdog?.cancel();
    if (mounted && !t.playing) setState(() => t.playing = true);
  }

  void _fail(_Tile t) {
    if (!mounted || !_tiles.contains(t)) return;
    t.watchdog?.cancel();
    if (t.picker.fail()) {
      _open(t);
    } else {
      t.player.stop();
      setState(() => t.failed = true);
    }
  }

  void _setAudio(int i) {
    if (i < 0 || i == _audio) return;
    setState(() => _audio = i);
    _applyVolumes();
  }

  void _applyVolumes() {
    for (var i = 0; i < _tiles.length; i++) {
      _tiles[i].player.setVolume(i == _audio ? 100 : 0);
    }
  }

  Future<void> _replace(_Tile t) async {
    final c = await pickChannel(
      context,
      widget.channels,
      widget.guide,
      exclude: {for (final x in _tiles) x.channel.key},
    );
    if (c == null || !mounted) return;
    setState(() {
      t.channel = c;
      t.picker = StreamPicker(c.streams);
    });
    _open(t);
    t.focus.requestFocus();
  }

  Future<void> _addNew() async {
    final c = await pickChannel(
      context,
      widget.channels,
      widget.guide,
      exclude: {for (final x in _tiles) x.channel.key},
    );
    if (c == null || !mounted) return;
    _add(c);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tiles.last.focus.requestFocus();
    });
  }

  void _remove(_Tile t) {
    final i = _tiles.indexOf(t);
    setState(() => _tiles.removeAt(i));
    t.dispose();
    if (_audio >= _tiles.length) _audio = 0;
    _applyVolumes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_tiles.isEmpty ? _addFocus : _tiles[_audio].focus).requestFocus();
    });
  }

  Future<void> _tileMenu(_Tile t) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: Row(
          children: [
            ChannelLogo(channel: t.channel, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: [
          _menuItem(
            ctx,
            'full',
            Icons.fullscreen_rounded,
            'Guarda a schermo intero',
          ),
          _menuItem(ctx, 'swap', Icons.swap_horiz_rounded, 'Cambia canale'),
          if (t.picker.streams.length > 1)
            _menuItem(
              ctx,
              'stream',
              Icons.sync_alt_rounded,
              'Flusso successivo',
            ),
          _menuItem(ctx, 'remove', Icons.close_rounded, 'Togli dal Multiview'),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'full':
        Navigator.of(context).pop(t.channel);
      case 'swap':
        await _replace(t);
      case 'stream':
        t.picker.select((t.picker.index + 1) % t.picker.streams.length);
        _open(t);
      case 'remove':
        _remove(t);
    }
  }

  Widget _menuItem(
    BuildContext ctx,
    String value,
    IconData icon,
    String label,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.pop(ctx, value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 14),
          Text(label),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (var i = 0; i < _tiles.length; i++) _tileView(i),
      if (_tiles.length < MultiviewScreen.maxTiles) _addView(),
    ];
    // 1 → intero, 2 → affiancati, 3-4 → griglia 2×2.
    final n = cells.length;
    final Widget grid;
    if (n == 1) {
      grid = cells.first;
    } else if (n == 2) {
      grid = Row(children: [for (final c in cells) Expanded(child: c)]);
    } else {
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: cells[0]),
                Expanded(child: cells[1]),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: cells[2]),
                Expanded(child: n > 3 ? cells[3] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(padding: const EdgeInsets.all(4), child: grid),
            ),
            if (!Device.isTv)
              const Align(
                alignment: Alignment.topLeft,
                child: PlayerBackButton(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tileView(int i) {
    final t = _tiles[i];
    final now = widget.guide?.nowOn(t.channel, now: _now);
    final tx = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: FocusCard(
        focusNode: t.focus,
        radius: 10,
        focusScale: 1.0,
        fill: Colors.black,
        onTap: () {
          if (t.focus.hasFocus || Device.isTv) {
            _tileMenu(t);
          } else {
            t.focus.requestFocus();
            _setAudio(i);
          }
        },
        onLongPress: () => _tileMenu(t),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: t.video, controls: NoVideoControls),
              if (!t.playing)
                ColoredBox(
                  color: const Color(0xFF0B0E13),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChannelLogo(channel: t.channel, size: 48),
                        const SizedBox(height: 10),
                        if (t.failed)
                          Text(
                            'Non disponibile',
                            style: tx.bodySmall?.copyWith(
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                    child: Row(
                      children: [
                        Icon(
                          i == _audio
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 18,
                          color: i == _audio
                              ? VistaColors.accent
                              : VistaColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            now == null
                                ? t.channel.name
                                : '${t.channel.name} · ${now.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addView() => Padding(
    padding: const EdgeInsets.all(4),
    child: FocusCard(
      focusNode: _addFocus,
      radius: 10,
      focusScale: 1.0,
      fill: const Color(0xFF0B0E13),
      onTap: _addNew,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 40),
            SizedBox(height: 8),
            Text(
              'Aggiungi canale',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'fino a 4 canali insieme',
              style: TextStyle(color: VistaColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Elenco dei canali con filtro: restituisce quello scelto.
Future<Channel?> pickChannel(
  BuildContext context,
  List<Channel> channels,
  EpgGuide? guide, {
  Set<String> exclude = const {},
}) {
  return Navigator.of(context).push<Channel>(
    MaterialPageRoute(
      builder: (_) =>
          _ChannelPicker(channels: channels, guide: guide, exclude: exclude),
    ),
  );
}

class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({
    required this.channels,
    required this.guide,
    required this.exclude,
  });
  final List<Channel> channels;
  final EpgGuide? guide;
  final Set<String> exclude;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  late final TextEditingController _q = TextEditingController()
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = _q.text.trim().toLowerCase();
    final list = [
      for (final c in widget.channels)
        if (!widget.exclude.contains(c.key) &&
            (f.isEmpty || c.name.toLowerCase().contains(f)))
          c,
    ];
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Indietro',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scegli un canale',
                        style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TvTextField(
                    controller: _q,
                    hint: 'Cerca canale',
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemExtent: 66,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final p = widget.guide?.nowOn(c, now: now);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: FocusCard(
                          autofocus: i == 0,
                          radius: 12,
                          focusScale: 1.0,
                          outline: false,
                          fill: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          onTap: () => Navigator.of(context).pop(c),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${c.number}',
                                  style: t.labelLarge?.copyWith(
                                    color: VistaColors.textTertiary,
                                  ),
                                ),
                              ),
                              ChannelLogo(channel: c, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      p == null
                                          ? c.group
                                          : '${hhmm(p.start)}  ${p.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall?.copyWith(
                                        color: VistaColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
