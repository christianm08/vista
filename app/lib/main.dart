import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/playlist_store.dart';
import 'screens/channels_screen.dart';
import 'screens/import_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
      builder: (context, child) => VistaBackground(child: child!),
      home: const _Root(),
    );
  }
}

/// Mostra l'importazione se non c'è una lista, altrimenti i canali.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final _store = PlaylistStore();
  StoredPlaylist? _playlist;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store.load().then((p) {
      if (mounted) {
        setState(() {
          _playlist = p;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _changeList() async {
    await _store.clear();
    if (mounted) setState(() => _playlist = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final p = _playlist;
    if (p == null) {
      return ImportScreen(
        store: _store,
        onImported: (p) => setState(() => _playlist = p),
      );
    }
    return ChannelsScreen(playlist: p, onChangeList: _changeList);
  }
}
