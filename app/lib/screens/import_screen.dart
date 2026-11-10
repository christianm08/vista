import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/playlist_store.dart';
import '../theme.dart';

/// Primo avvio: l'utente porta la propria lista M3U (URL o file).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.store, required this.onImported});

  final PlaylistStore store;
  final ValueChanged<StoredPlaylist> onImported;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<StoredPlaylist?> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await job();
      if (p != null) widget.onImported(p);
    } on PlaylistException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Errore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<StoredPlaylist?> _fromUrl() async {
    final url = _url.text.trim();
    final text = await widget.store.download(url);
    return widget.store.save(text, url);
  }

  Future<StoredPlaylist?> _fromFile() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Scegli una lista M3U');
    if (files.isEmpty) return null;
    final f = files.first;
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    return widget.store.save(text, f.name);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Glass(
                radius: VistaRadius.hero,
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Vista',
                        style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Aggiungi la tua lista',
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(
                      'Vista è un player: non include canali né liste. '
                      'Usa solo liste che hai il diritto di guardare, '
                      'come i canali in chiaro.',
                      style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _url,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'https://… indirizzo della lista M3U',
                      ),
                      onSubmitted: (_) => _run(_fromUrl),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(_fromUrl),
                      child: const Text('Carica da indirizzo'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _run(_fromFile),
                      child: const Text('Scegli un file .m3u'),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 20),
                      const Center(child: CircularProgressIndicator()),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Color(0xFFFF9C8A))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
