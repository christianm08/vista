import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../data/user_store.dart';
import '../widgets/epg_guide.dart' show hhmm;
import 'live_recording.dart';
import 'options_panel.dart';
import 'platform_player.dart';
import 'stream_picker.dart';

/// Voci del menu del player dal vivo: flusso, tracce, immagine e "Altro"
/// (registra, PiP, player esterno, decodifica, canale precedente, Multiview,
/// preferiti).
///
/// [onClose] chiude il menu; [onReopen] riapre il flusso da capo (dopo aver
/// cambiato flusso o decodifica).
List<PlayerOptionSection> liveOptionSections({
  required Player player,
  required StreamPicker picker,
  required Tracks tracks,
  required Track track,
  required UserStore user,
  required Channel channel,
  required LiveRecording recording,
  required bool canPip,
  required Channel? previous,
  required VoidCallback onClose,
  required VoidCallback onReopen,
  required VoidCallback onToggleRecording,
  required VoidCallback onOpenExternal,
  required VoidCallback onPrevious,
  required VoidCallback onMultiview,
  required VoidCallback onToggleFavorite,
}) {
  final favorite = user.isFavorite(UserKey.channel(channel.key));
  final software = user.softwareDecode(channel.key);
  return [
    if (picker.streams.length > 1)
      PlayerOptionSection('Flusso', [
        PlayerOption(
          label: 'Automatico',
          detail: 'Il migliore che funziona; se si blocca passa al successivo',
          selected: picker.auto,
          onTap: () {
            picker.reset();
            onReopen();
            onClose();
          },
        ),
        for (var i = 0; i < picker.streams.length; i++)
          PlayerOption(
            label: 'Flusso ${i + 1} · ${picker.streams[i].quality.label}',
            detail: picker.streams[i].sourceName,
            selected: !picker.auto && picker.index == i,
            onTap: () {
              picker.select(i);
              onReopen();
              onClose();
            },
          ),
      ]),
    ...trackSections(player, tracks, track, onPicked: onClose),
    pictureSection(user, onPicked: onClose),
    PlayerOptionSection('Altro', [
      PlayerOption(
        icon: recording.active
            ? Icons.stop_circle_outlined
            : Icons.fiber_manual_record_outlined,
        label: recording.active ? 'Ferma la registrazione' : 'Registra',
        detail: recording.active
            ? 'In corso dalle ${hhmm(recording.since!)}'
            : 'Salva il canale finché non la fermi o cambi canale',
        onTap: () {
          onClose();
          onToggleRecording();
        },
      ),
      if (canPip)
        PlayerOption(
          icon: Icons.picture_in_picture_alt_rounded,
          label: PlayerPlatform.pipLabel,
          detail: 'Il canale resta visibile mentre fai altro',
          onTap: () {
            onClose();
            PlayerPlatform.enterPip();
          },
        ),
      if (PlayerPlatform.hasExternalPlayer)
        PlayerOption(
          icon: Icons.open_in_new_rounded,
          label: 'Apri con un altro player',
          detail: Platform.isWindows ? 'VLC' : 'VLC, MX Player…',
          onTap: () {
            onClose();
            onOpenExternal();
          },
        ),
      PlayerOption(
        icon: Icons.memory_rounded,
        label: software
            ? 'Decodifica software (attiva)'
            : 'Decodifica software',
        detail: software
            ? 'Torna alla decodifica hardware per questo canale'
            : 'Per questo canale, se il video scatta o si vede male',
        onTap: () {
          user.setSoftwareDecode(channel.key, !software);
          onClose();
          onReopen();
        },
      ),
      if (previous != null)
        PlayerOption(
          icon: Icons.undo_rounded,
          label: 'Canale precedente',
          detail: '${previous.number} · ${previous.name}',
          onTap: () {
            onClose();
            onPrevious();
          },
        ),
      PlayerOption(
        icon: Icons.grid_view_rounded,
        label: 'Multiview',
        detail: 'Fino a 4 canali insieme',
        onTap: onMultiview,
      ),
      PlayerOption(
        icon: favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        label: favorite ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
        onTap: () {
          onToggleFavorite();
          onClose();
        },
      ),
    ]),
  ];
}
