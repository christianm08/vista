import 'dart:io';

import 'package:flutter/material.dart';

import '../data/recordings.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import 'shell.dart' show showToast;
import 'vod_player_screen.dart';

/// Registrazioni: programmate (da annullare), in corso e salvate (da
/// guardare o cancellare).
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final _service = RecordingService.instance;
  late Future<(String, List<File>)> _files = _load();
  late Future<(int, int?)> _space = _loadSpace();

  Future<(String, List<File>)> _load() async =>
      ((await _service.folder()).path, await _service.files());

  /// Spazio usato dalle registrazioni e libero sul disco.
  Future<(int, int?)> _loadSpace() async =>
      (await _service.usedSpace(), await _service.freeSpace());

  void _reload() => setState(() {
    _files = _load();
    _space = _loadSpace();
  });

  static String _gb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return gb < 1
        ? '${(bytes / (1024 * 1024)).round()} MB'
        : '${gb.toStringAsFixed(1)} GB';
  }

  Future<T?> _choose<T>(
    String title,
    List<T> values,
    T current,
    String Function(T) label, [
    String Function(T)? detail,
  ]) => showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: const Color(0xF0121720),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VistaRadius.card),
      ),
      title: Text(title),
      children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: FocusCard(
              autofocus: v == current,
              selected: v == current,
              radius: 12,
              focusScale: 1.0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onTap: () => Navigator.pop(ctx, v),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(v),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (detail != null)
                    Opacity(opacity: 0.7, child: Text(detail(v))),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _pickQuality() async {
    final q = await _choose<RecordQuality>(
      'Qualità delle registrazioni',
      RecordQuality.values,
      _service.quality,
      (q) => q.label,
      (q) => '${q.detail} · ${q.estimate(const Duration(hours: 2))} per 2 ore',
    );
    if (q != null) _service.setQuality(q);
  }

  Future<void> _pickLimit() async {
    final gb = await _choose<int>(
      'Spazio massimo per le registrazioni',
      const [5, 10, 20, 50, 100, 0],
      _service.limitGb,
      (v) => v == 0 ? 'Nessun limite (solo il disco)' : '$v GB',
    );
    if (gb != null) _service.setLimit(gb);
  }

  Future<void> _pickWhenFull() async {
    final w = await _choose<WhenFull>(
      'Quando lo spazio finisce',
      WhenFull.values,
      _service.whenFull,
      (w) => w.label,
      (w) => w == WhenFull.stop
          ? 'Quello registrato finora resta salvato'
          : 'Si fa posto togliendo le registrazioni più vecchie',
    );
    if (w != null) _service.setWhenFull(w);
  }

  String _when(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _play(File f) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VodPlayerScreen(
          items: [
            VodItem(
              title: RecordingService.label(f),
              subtitle: 'Registrazione',
              url: f.path,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF0121720),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VistaRadius.card),
        ),
        title: const Text('Cancellare la registrazione?'),
        content: Text(
          '${RecordingService.label(f)}\nIl file verrà eliminato e non si potrà recuperare.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await f.delete();
      if (mounted) showToast(context, 'Registrazione cancellata.');
    } on FileSystemException {
      if (mounted) showToast(context, 'File in uso: riprova tra poco.');
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) => FutureBuilder<(String, List<File>)>(
            future: _files,
            builder: (context, snap) {
              final (folder, files) = snap.data ?? ('', const <File>[]);
              final pending = [..._service.running, ..._service.scheduled];
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 48 : 16,
                  wide ? 32 : 16,
                  wide ? 48 : 16,
                  40,
                ),
                children: [
                  Text(
                    'Registrazioni',
                    style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Si registra dal menu del player (il canale che guardi) o '
                    'dalla guida (tasto Menu su un programma). Le registrazioni '
                    'programmate partono solo con Vista aperta e usano una '
                    'connessione in più verso il fornitore.',
                    style: t.bodyMedium?.copyWith(
                      color: VistaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FutureBuilder<(int, int?)>(
                    future: _space,
                    builder: (context, space) {
                      final (used, free) = space.data ?? (0, null);
                      return Text(
                        [
                          'Usati ${_gb(used)}'
                              '${_service.limitGb > 0 ? ' su ${_service.limitGb} GB' : ''}',
                          if (free != null) 'liberi sul disco ${_gb(free)}',
                        ].join(' · '),
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _Row(
                    autofocus: true,
                    icon: Icons.high_quality_outlined,
                    title: 'Qualità: ${_service.quality.label}',
                    subtitle:
                        '${_service.quality.estimate(const Duration(hours: 2))} '
                        'per 2 ore di programma. Senza ricodificare: si registra '
                        'la versione più leggera che il fornitore offre.',
                    action: 'Cambia',
                    onTap: _pickQuality,
                  ),
                  _Row(
                    icon: Icons.storage_rounded,
                    title: _service.limitGb == 0
                        ? 'Spazio massimo: nessun limite'
                        : 'Spazio massimo: ${_service.limitGb} GB',
                    subtitle:
                        'Sotto 1,5 GB liberi sul disco la registrazione si '
                        'ferma comunque, per non riempire la memoria.',
                    action: 'Cambia',
                    onTap: _pickLimit,
                  ),
                  _Row(
                    icon: Icons.auto_delete_outlined,
                    title: 'Al limite: ${_service.whenFull.label}',
                    subtitle: _service.whenFull == WhenFull.stop
                        ? 'Le registrazioni salvate non si toccano.'
                        : 'Le più vecchie si cancellano per fare posto.',
                    action: 'Cambia',
                    onTap: _pickWhenFull,
                  ),
                  if (folder.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Cartella: $folder',
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textTertiary,
                      ),
                    ),
                  ],
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'PROGRAMMATE',
                      style: t.labelMedium?.copyWith(
                        color: VistaColors.textTertiary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final s in pending)
                      _Row(
                        icon: _service.running.contains(s)
                            ? Icons.fiber_manual_record_rounded
                            : Icons.schedule_rounded,
                        iconColor: _service.running.contains(s)
                            ? const Color(0xFFFF5A5F)
                            : null,
                        title: s.title.isEmpty ? s.channelName : s.title,
                        subtitle:
                            '${s.channelName} · ${_when(s.start)}–'
                            '${_when(s.end).split(' ').last}'
                            '${_service.running.contains(s) ? ' · in corso' : ''}',
                        action: _service.running.contains(s)
                            ? 'Ferma'
                            : 'Annulla',
                        onTap: () => _service.cancel(s),
                      ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'SALVATE',
                    style: t.labelMedium?.copyWith(
                      color: VistaColors.textTertiary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (files.isEmpty)
                    Text(
                      'Ancora nessuna registrazione.',
                      style: t.bodyMedium?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    )
                  else
                    for (final f in files)
                      _Row(
                        icon: Icons.movie_outlined,
                        title: RecordingService.label(f),
                        subtitle:
                            '${(f.lengthSync() / (1024 * 1024)).toStringAsFixed(0)} MB',
                        action: 'Cancella',
                        onTap: () => _play(f),
                        onAction: () => _delete(f),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.onAction,
    this.iconColor,
    this.autofocus = false,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  /// Il pulsante a destra; senza, fa la stessa cosa del tocco sulla riga.
  final VoidCallback? onAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: FocusCard(
              autofocus: autofocus,
              radius: VistaRadius.card,
              focusScale: 1.0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              onTap: onTap,
              child: Row(
                children: [
                  Icon(icon, color: iconColor ?? VistaColors.textSecondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          subtitle,
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
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: onAction ?? onTap, child: Text(action)),
        ],
      ),
    );
  }
}
