import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vista_resolver/vista_resolver.dart';

import 'app_scope.dart';
import 'data/channel_logos.dart';
import 'data/epg_store.dart';
import 'data/parental_store.dart';
import 'data/recordings.dart';
import 'data/source_store.dart';
import 'data/tmdb_store.dart';
import 'data/user_store.dart';
import 'data/window_mode.dart';
import 'player/platform_player.dart';
import 'screens/import_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PlayerPlatform.init();
  // Più locandine decodificate in memoria: tornando indietro o scorrendo le
  // righe non si ridecodificano (il default è 100 MB / 1000 immagini).
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 192 << 20
    ..maximumSize = 2000;
  await Future.wait([ChannelLogos.init(), Device.init()]);
  final user = UserStore();
  final tmdb = TmdbStore();
  final parental = ParentalStore();
  await Future.wait([
    user.load(),
    tmdb.init(),
    parental.load(),
    RecordingService.instance.load(),
  ]);
  runApp(VistaApp(user: user, tmdb: tmdb, parental: parental));
}

class VistaApp extends StatefulWidget {
  const VistaApp({
    super.key,
    required this.user,
    required this.tmdb,
    required this.parental,
  });
  final UserStore user;
  final TmdbStore tmdb;
  final ParentalStore parental;

  @override
  State<VistaApp> createState() => _VistaAppState();
}

class _VistaAppState extends State<VistaApp> with WidgetsBindingObserver {
  final _store = SourceStore();
  late final _epg = EpgStore(_store);
  final _nav = GlobalKey<NavigatorState>();
  Timer? _autoRefresh;
  Timer? _reminders;

  /// Avvia e ferma le registrazioni programmate.
  Future<void> _checkRecordings() async {
    final lib = _store.library.value;
    if (lib == null) return;
    final service = RecordingService.instance;
    await service.tick(lib.catalog.live.channels, (url) {
      final ua = _store.userAgentFor(url);
      return ua == null ? null : {'User-Agent': ua};
    });
    // Spazio finito, registrazione saltata…: lo si dice subito.
    final warning = service.takeWarning();
    final context = _nav.currentContext;
    if (warning != null && context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(warning), duration: const Duration(seconds: 8)),
      );
    }
  }

  /// Ogni 20 s: i programmi con promemoria che stanno per iniziare.
  void _checkReminders() {
    final due = widget.user.takeDue();
    final context = _nav.currentContext;
    if (due.isEmpty || context == null) return;
    for (final r in due) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xF0121720),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VistaRadius.card),
          ),
          title: Row(
            children: [
              const Icon(Icons.notifications_active_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.start.isAfter(DateTime.now())
                      ? 'Sta per iniziare'
                      : 'È iniziato',
                ),
              ),
            ],
          ),
          content: Text('${r.title}\nsu ${r.channelName}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () {
                Navigator.pop(ctx);
                final lib = _store.library.value;
                final channels = [
                  for (final c
                      in lib?.catalog.live.channels ?? const <Channel>[])
                    if (!c.hidden) c,
                ];
                final c = channels
                    .where((c) => c.key == r.channelKey)
                    .firstOrNull;
                final nav = _nav.currentContext;
                if (c != null && nav != null) {
                  Nav.playChannel(nav, channels, c);
                }
              },
              child: const Text('Guarda'),
            ),
          ],
        ),
      );
    }
  }

  /// Riscarica in silenzio le liste più vecchie di quanto scelto.
  Future<void> _refreshStale() async {
    final age = widget.user.autoRefresh.maxAge;
    if (age == null || _store.sources.isEmpty) return;
    await _store.refreshAll(olderThan: age);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Controllo ogni ora (per chi tiene l'app aperta a lungo, es. sulla TV).
    _reminders = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkReminders();
      _checkRecordings();
    });
    _autoRefresh = Timer.periodic(const Duration(hours: 1), (_) {
      if (widget.user.autoRefresh != AutoRefresh.start) _refreshStale();
    });
    // Su TV il focus si vede sempre, anche prima del primo tasto; su PC e
    // telefono solo usando la tastiera.
    FocusManager.instance.highlightStrategy = Device.isTv
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefresh?.cancel();
    _reminders?.cancel();
    _epg.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // L'avanzamento si scrive a intervalli: in pausa si salva subito.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.user.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: _store,
      epg: _epg,
      user: widget.user,
      tmdb: widget.tmdb,
      parental: widget.parental,
      child: MaterialApp(
        title: 'Vista',
        debugShowCheckedModeBanner: false,
        // Grafico dei tempi di disegno, solo per le prove: --dart-define=SHOW_PERF=true
        showPerformanceOverlay: const bool.fromEnvironment('SHOW_PERF'),
        theme: buildVistaTheme(),
        scrollBehavior: const VistaScrollBehavior(),
        navigatorKey: _nav,
        // Su PC Esc torna indietro in tutte le schermate (la shell e i
        // player lo gestiscono prima a modo loro); a schermo intero Esc ne
        // esce. F11 attiva e disattiva lo schermo intero ovunque.
        builder: (context, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              // Dalla finestra mini, Esc torna prima alla finestra normale.
              if (PlayerPlatform.pip.value) {
                PlayerPlatform.exitPip();
                return;
              }
              if (!WindowMode.leaveOnEscape()) _nav.currentState?.maybePop();
            },
            const SingleActivator(LogicalKeyboardKey.f11): WindowMode.toggle,
          },
          child: TvCanvas(child: VistaBackground(child: child!)),
        ),
        home: _Root(store: _store, onLoaded: _refreshStale),
      ),
    );
  }
}

/// Mostra l'importazione se non c'è una fonte, altrimenti l'app.
class _Root extends StatefulWidget {
  const _Root({required this.store, required this.onLoaded});
  final SourceStore store;

  /// Dopo la lettura delle fonti salvate (es. aggiornamento automatico).
  final Future<void> Function() onLoaded;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.load().then(
      (_) {
        if (mounted) setState(() => _loading = false);
        unawaited(widget.onLoaded());
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _loadError = e is SourceException
                ? e.message
                : 'Non riesco a leggere la fonte salvata: aggiungila di nuovo.';
            _loading = false;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ValueListenableBuilder<Library?>(
      valueListenable: widget.store.library,
      // Ogni schermata ha il suo FocusScope: al cambio (importazione → app e
      // viceversa) il focus del telecomando non resta sul vecchio pulsante.
      builder: (context, lib, _) => FocusScope(
        key: ValueKey(lib == null),
        autofocus: true,
        child: lib == null
            ? ImportScreen(store: widget.store, initialError: _loadError)
            : AppShell(library: lib),
      ),
    );
  }
}
