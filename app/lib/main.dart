import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_scope.dart';
import 'data/channel_logos.dart';
import 'data/epg_store.dart';
import 'data/source_store.dart';
import 'data/user_store.dart';
import 'screens/import_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Future.wait([ChannelLogos.init(), Device.init()]);
  final user = UserStore();
  await user.load();
  runApp(VistaApp(user: user));
}

class VistaApp extends StatefulWidget {
  const VistaApp({super.key, required this.user});
  final UserStore user;

  @override
  State<VistaApp> createState() => _VistaAppState();
}

class _VistaAppState extends State<VistaApp> with WidgetsBindingObserver {
  final _store = SourceStore();
  late final _epg = EpgStore(_store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Su TV il focus si vede sempre, anche prima del primo tasto; su PC e
    // telefono solo usando la tastiera.
    FocusManager.instance.highlightStrategy = Device.isTv
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      child: MaterialApp(
        title: 'Vista',
        debugShowCheckedModeBanner: false,
        theme: buildVistaTheme(),
        scrollBehavior: const VistaScrollBehavior(),
        builder: (context, child) => VistaBackground(child: child!),
        home: _Root(store: _store),
      ),
    );
  }
}

/// Mostra l'importazione se non c'è una fonte, altrimenti l'app.
class _Root extends StatefulWidget {
  const _Root({required this.store});
  final SourceStore store;

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
