import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';

/// Una voce del menu del player.
class PlayerOption {
  const PlayerOption({
    required this.label,
    required this.onTap,
    this.detail = '',
    this.selected = false,
    this.icon,
  });

  final String label;
  final String detail;
  final bool selected;

  /// Con un'icona la voce è un'azione (es. Multiview), senza è una scelta.
  final IconData? icon;
  final VoidCallback onTap;
}

class PlayerOptionSection {
  const PlayerOptionSection(this.title, this.options);
  final String title;
  final List<PlayerOption> options;
}

/// Menu interno del player: pannello a destra sopra il video, navigabile
/// col telecomando. All'apertura il focus va sulla prima voce selezionata.
class PlayerOptionsPanel extends StatelessWidget {
  const PlayerOptionsPanel({
    super.key,
    required this.open,
    required this.sections,
    required this.onClose,
    this.title = 'Opzioni',
  });

  final bool open;
  final List<PlayerOptionSection> sections;
  final VoidCallback onClose;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width < 600
        ? MediaQuery.sizeOf(context).width
        : 400.0;
    var focusGiven = false;
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeFocus(
        excluding: !open,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: GestureDetector(
                  onTap: onClose,
                  child: const ColoredBox(color: Color(0x66000000)),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              right: open ? 0 : -width - 20,
              top: 0,
              bottom: 0,
              width: width,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xF20B0E13),
                  border: Border(
                    left: BorderSide(color: VistaColors.glassBorder),
                  ),
                ),
                child: SafeArea(
                  left: false,
                  // Uno scope nuovo a ogni apertura: l'autofocus funziona
                  // anche se il player aveva già il focus.
                  child: FocusScope(
                    key: ValueKey(open),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: t.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Chiudi',
                              onPressed: onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        for (final s in sections)
                          if (s.options.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
                              child: Text(
                                s.title.toUpperCase(),
                                style: t.labelSmall?.copyWith(
                                  color: VistaColors.textTertiary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            for (final o in s.options)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: FocusCard(
                                  autofocus:
                                      open &&
                                          !focusGiven &&
                                          (o.selected || o.icon != null)
                                      ? (focusGiven = true)
                                      : false,
                                  radius: 12,
                                  focusScale: 1.0,
                                  outline: false,
                                  fill: o.selected
                                      ? VistaColors.glassActive
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  onTap: o.onTap,
                                  child: Row(
                                    children: [
                                      Icon(
                                        o.icon ??
                                            (o.selected
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off),
                                        size: 20,
                                        color: o.selected || o.icon != null
                                            ? VistaColors.accent
                                            : VistaColors.textTertiary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              o.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: o.selected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                            if (o.detail.isNotEmpty)
                                              Text(
                                                o.detail,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: t.bodySmall?.copyWith(
                                                  color:
                                                      VistaColors.textTertiary,
                                                ),
                                              ),
                                          ],
                                        ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _lang(String? l) {
  if (l == null || l.isEmpty) return '';
  const names = {
    'ita': 'Italiano',
    'it': 'Italiano',
    'eng': 'Inglese',
    'en': 'Inglese',
    'spa': 'Spagnolo',
    'es': 'Spagnolo',
    'fra': 'Francese',
    'fre': 'Francese',
    'fr': 'Francese',
    'deu': 'Tedesco',
    'ger': 'Tedesco',
    'de': 'Tedesco',
    'por': 'Portoghese',
    'pt': 'Portoghese',
    'jpn': 'Giapponese',
    'ja': 'Giapponese',
    'und': '',
  };
  return names[l.toLowerCase()] ?? l.toUpperCase();
}

/// Sezioni "Qualità video", "Audio" e "Sottotitoli" dalle tracce del flusso.
/// Le sezioni con una sola scelta reale non compaiono.
List<PlayerOptionSection> trackSections(
  Player player,
  Tracks tracks,
  Track current, {
  required VoidCallback onPicked,
}) {
  final video = [
    for (final v in tracks.video)
      if (v.id != 'no' && v.id != 'auto') v,
  ];
  // Dalla qualità più alta.
  video.sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
  final audio = [
    for (final a in tracks.audio)
      if (a.id != 'no' && a.id != 'auto') a,
  ];
  final subs = [
    for (final s in tracks.subtitle)
      if (s.id != 'no' && s.id != 'auto') s,
  ];
  void pick(void Function() f) {
    f();
    onPicked();
  }

  return [
    if (video.length > 1)
      PlayerOptionSection('Qualità video', [
        PlayerOption(
          label: 'Automatica',
          detail: 'Si adatta alla connessione',
          selected: current.video.id == 'auto',
          onTap: () => pick(() => player.setVideoTrack(VideoTrack.auto())),
        ),
        for (final (i, v) in video.indexed)
          PlayerOption(
            label: v.h != null && v.h! > 0
                ? '${v.h}p'
                : (v.title ?? 'Video ${i + 1}'),
            detail: [
              if (v.w != null && v.h != null) '${v.w}×${v.h}',
              if (v.bitrate != null && v.bitrate! > 0)
                '${(v.bitrate! / 1000000).toStringAsFixed(1)} Mbit/s',
              if (v.codec != null) v.codec!.toUpperCase(),
            ].join(' · '),
            selected: current.video.id == v.id,
            onTap: () => pick(() => player.setVideoTrack(v)),
          ),
      ]),
    if (audio.length > 1)
      PlayerOptionSection('Audio', [
        for (final (i, a) in audio.indexed)
          PlayerOption(
            label: [_lang(a.language), a.title ?? '']
                .where((s) => s.isNotEmpty)
                .join(' · ')
                .ifEmpty('Traccia ${i + 1}'),
            detail: [
              if (a.codec != null) a.codec!.toUpperCase(),
              if (a.channels != null) a.channels!,
            ].join(' · '),
            selected: current.audio.id == a.id,
            onTap: () => pick(() => player.setAudioTrack(a)),
          ),
      ]),
    PlayerOptionSection('Sottotitoli', [
      PlayerOption(
        label: 'Disattivati',
        selected: current.subtitle.id == 'no' || (subs.isEmpty),
        onTap: () => pick(() => player.setSubtitleTrack(SubtitleTrack.no())),
      ),
      for (final (i, s) in subs.indexed)
        PlayerOption(
          label: [_lang(s.language), s.title ?? '']
              .where((x) => x.isNotEmpty)
              .join(' · ')
              .ifEmpty('Sottotitoli ${i + 1}'),
          selected: current.subtitle.id == s.id,
          onTap: () => pick(() => player.setSubtitleTrack(s)),
        ),
    ]),
  ];
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Voci "Immagine": formato e zoom, salvati per tutti i player.
PlayerOptionSection pictureSection(
  UserStore user, {
  required VoidCallback onPicked,
}) => PlayerOptionSection('Immagine', [
  for (final p in PictureFormat.values)
    PlayerOption(
      label: p.label,
      detail: p.detail,
      selected: user.picture == p,
      onTap: () {
        user.setPicture(p);
        onPicked();
      },
    ),
]);

/// Il video nel formato scelto.
Widget formattedVideo(VideoController controller, PictureFormat format) =>
    Video(
      controller: controller,
      controls: NoVideoControls,
      fit: switch (format) {
        PictureFormat.zoom => BoxFit.cover,
        PictureFormat.stretch => BoxFit.fill,
        _ => BoxFit.contain,
      },
      aspectRatio: switch (format) {
        PictureFormat.wide => 16 / 9,
        PictureFormat.classic => 4 / 3,
        _ => null,
      },
    );
