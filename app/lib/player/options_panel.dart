import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/user_store.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/vista_controls.dart';

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
    final layout = VistaLayout.of(context);
    final width = layout.compact
        ? layout.width
        : VistaSize.playerOptions + layout.safe.right;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : VistaMotion.overlayFade;
    var focusGiven = false;
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeFocus(
        excluding: !open,
        child: Stack(
          children: [
            // Tocco fuori dal pannello: chiude. Nessun velo sul video.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
              ),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: VistaMotion.enter,
              right: open ? 0 : -width,
              top: 0,
              bottom: 0,
              width: width,
              child: ColoredBox(
                color: VistaColors.surface,
                child: SafeArea(
                  left: false,
                  // Uno scope nuovo a ogni apertura: l'autofocus funziona
                  // anche se il player aveva già il focus.
                  child: FocusScope(
                    key: ValueKey(open),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        VistaSpace.s16,
                        VistaSpace.s24 + layout.safe.top,
                        VistaSpace.s16 + layout.safe.right,
                        VistaSpace.s24 + layout.safe.bottom,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: VistaSpace.s8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.headlineSmall,
                                ),
                              ),
                              VistaIconButton(
                                icon: Icons.close_rounded,
                                tooltip: 'Chiudi',
                                onPressed: onClose,
                              ),
                            ],
                          ),
                        ),
                        for (final s in sections)
                          if (s.options.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                VistaSpace.s8,
                                VistaSpace.s24,
                                VistaSpace.s8,
                                VistaSpace.s8,
                              ),
                              child: Text(
                                s.title.toUpperCase(),
                                style: t.labelSmall?.copyWith(
                                  color: VistaColors.textSecondary,
                                ),
                              ),
                            ),
                            for (final o in s.options)
                              Padding(
                                // Più largo di quanto sporge l'anello.
                                padding: const EdgeInsets.only(
                                  bottom: VistaSpace.s8,
                                ),
                                child: FocusCard(
                                  autofocus:
                                      open &&
                                          !focusGiven &&
                                          (o.selected || o.icon != null)
                                      ? (focusGiven = true)
                                      : false,
                                  radius: VistaRadius.chip,
                                  focusScale: 1.0,
                                  fill: o.selected
                                      ? VistaColors.surfaceHigh
                                      : VistaColors.surface,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: VistaSpace.s12,
                                    vertical: VistaSpace.s8,
                                  ),
                                  onTap: o.onTap,
                                  child: _OptionRow(o),
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

/// Voce del menu: icona (azione) o spunta (scelta), nome e dettaglio.
class _OptionRow extends StatelessWidget {
  const _OptionRow(this.o);
  final PlayerOption o;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final icon = o.icon ?? (o.selected ? Icons.check_rounded : null);
    return Row(
      children: [
        // Le scelte non selezionate tengono lo stesso rientro.
        SizedBox(
          width: VistaSize.icon,
          child: icon == null
              ? null
              : Icon(icon, size: VistaSize.iconSmall, color: VistaColors.text),
        ),
        const SizedBox(width: VistaSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(
                  color: VistaColors.text,
                  fontWeight: o.selected ? VistaType.strong : null,
                ),
              ),
              if (o.detail.isNotEmpty)
                Text(
                  o.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    color: VistaColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
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
