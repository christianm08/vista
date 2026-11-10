import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/channel_logos.dart';
import 'data/epg_store.dart';
import 'data/source_store.dart';
import 'screens/home_screen.dart';
import 'screens/import_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ChannelLogos.init();
  runApp(const VistaApp());
}

class VistaApp extends StatelessWidget {
  const VistaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vista',
      debugShowCheckedModeBanner: false,
      theme: buildVistaTheme(),
      builder: (context, child) {
        // Su TV e PC il focus si vede sempre, anche prima del primo tasto;
        // sul telefono solo usando una tastiera.
        FocusManager.instance.highlightStrategy = MediaQuery.sizeOf(context).width >= 900
            ? FocusHighlightStrategy.alwaysTraditional
            : FocusHighlightStrategy.automatic;
        return VistaBackground(child: child!);
      },
      home: const _Root(),
    );
  }
}

/// Mostra l'importazione se non c'è una fonte, altrimenti la home.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final _store = SourceStore();
  late final _epg = EpgStore(_store);
  String? _loadError;
  bool _loading = true;

  @override
  void dispose() {
    _epg.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      if (mounted) setState(() => _loading = false);
    }, onError: (Object e) {
      if (mounted) {
        setState(() {
          _loadError = e is SourceException
              ? e.message
              : 'Non riesco a leggere la fonte salvata: aggiungila di nuovo.';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ValueListenableBuilder<Library?>(
      valueListenable: _store.library,
      // Ogni schermata ha il suo FocusScope: al cambio (importazione → home e
      // viceversa) il focus del telecomando non resta sul vecchio pulsante.
      builder: (context, lib, _) => FocusScope(
        key: ValueKey(lib == null),
        autofocus: true,
        child: lib == null
            ? ImportScreen(store: _store, initialError: _loadError)
            : HomeScreen(library: lib, store: _store, epg: _epg),
      ),
    );
  }
}
