import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/source_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/tv_text_field.dart';

enum _Mode { m3u, xtream }

/// Primo avvio: l'utente porta la propria fonte, una lista M3U (indirizzo o
/// file) oppure un account Xtream. La fonte caricata arriva alla home da
/// [SourceStore.library].
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.store, this.initialError});

  final SourceStore store;
  final String? initialError;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _url = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  _Mode _mode = _Mode.m3u;
  String? _busy; // testo dell'operazione in corso
  late String? _error = widget.initialError;

  @override
  void dispose() {
    for (final c in [_url, _server, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String busy, Future<Library?> Function() job) async {
    setState(() {
      _busy = busy;
      _error = null;
    });
    try {
      await job(); // la nuova fonte arriva da store.library
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Errore imprevisto: ${redactError(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _fromUrl() {
    final url = _url.text.trim();
    final busy = xtreamFromM3uUrl(url) != null
        ? 'Link Xtream riconosciuto: accedo e scarico canali, film e serie…'
        : 'Scarico la lista…';
    _run(busy, () => widget.store.importM3uUrl(url));
  }

  void _fromFile() {
    _run('Leggo il file…', () async {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Scegli una lista M3U',
      );
      if (files.isEmpty) return null;
      final f = files.first;
      return widget.store.importM3uFile(f.name, await f.readAsBytes());
    });
  }

  void _login() {
    _run(
      'Accedo e scarico canali, film e serie…',
      () => widget.store.loginXtream(
        XtreamCredentials(
          server: _server.text,
          username: _user.text,
          password: _pass.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = _busy != null;
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
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Vista',
                        style: t.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Aggiungi la tua fonte',
                        style: t.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Vista è un player: non include canali né liste. '
                        'Usa solo fonti che hai il diritto di guardare, '
                        'come i canali in chiaro.',
                        style: t.bodyMedium?.copyWith(
                          color: VistaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          _modeChip('Lista M3U', _Mode.m3u, autofocus: true),
                          const SizedBox(width: 10),
                          _modeChip('Xtream', _Mode.xtream),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_mode == _Mode.m3u)
                        ..._m3uForm(busy)
                      else
                        ..._xtreamForm(busy),
                      if (busy) ...[
                        const SizedBox(height: 20),
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 10),
                        Text(
                          _busy!,
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(
                            color: VistaColors.textSecondary,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFF9C8A)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String label, _Mode mode, {bool autofocus = false}) {
    return FocusCard(
      radius: 999,
      autofocus: autofocus,
      selected: _mode == mode,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      onTap: () => setState(() {
        _mode = mode;
        _error = null;
      }),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  List<Widget> _m3uForm(bool busy) => [
    TvTextField(
      controller: _url,
      enabled: !busy,
      hint: 'https://… indirizzo della lista M3U',
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) => _fromUrl(),
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: busy ? null : _fromUrl,
      child: const Text('Carica da indirizzo'),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: busy ? null : _fromFile,
      child: const Text('Scegli un file .m3u'),
    ),
  ];

  List<Widget> _xtreamForm(bool busy) => [
    TvTextField(
      controller: _server,
      enabled: !busy,
      hint: 'Server, es. http://server:8080',
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    TvTextField(
      controller: _user,
      enabled: !busy,
      hint: 'Nome utente',
      autofillHints: const [AutofillHints.username],
      textInputAction: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    TvTextField(
      controller: _pass,
      enabled: !busy,
      hint: 'Password',
      obscure: true,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.go,
      onSubmitted: (_) => _login(),
    ),
    const SizedBox(height: 8),
    Text(
      'Le credenziali restano su questo dispositivo, nel portachiavi del sistema.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: VistaColors.textTertiary),
    ),
    const SizedBox(height: 14),
    FilledButton(onPressed: busy ? null : _login, child: const Text('Accedi')),
  ];
}
