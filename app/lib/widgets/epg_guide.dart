import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import 'channel_logo.dart';
import 'focus_card.dart';

String hhmm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Finestra visibile della guida: dalla mezz'ora corrente per [minutes].
class GuideWindow {
  GuideWindow(DateTime now, {this.minutes = 180})
      : start = DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30);

  final DateTime start;
  final int minutes;

  DateTime get end => start.add(Duration(minutes: minutes));

  double offset(DateTime t, double pxPerMinute) =>
      t.difference(start).inSeconds / 60 * pxPerMinute;
}

/// Misure della guida in base allo spazio: una TV 1080p ha 960 punti logici
/// di larghezza, un PC molti di più.
class GuideMetrics {
  const GuideMetrics._(this.channelWidth, this.minutes, this.rowHeight, this.logo);

  factory GuideMetrics.of(double width) => width < 760
      ? const GuideMetrics._(200, 120, 64, 40)
      : const GuideMetrics._(280, 180, 76, 52);

  final double channelWidth;
  final int minutes;
  final double rowHeight;
  final double logo;
}

/// Righello orario sopra la guida, ogni mezz'ora (le etichette che non
/// ci stanno vengono saltate).
class GuideRuler extends StatelessWidget {
  const GuideRuler({
    super.key,
    required this.window,
    required this.now,
    required this.metrics,
  });
  final GuideWindow window;
  final DateTime now;
  final GuideMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox(
            width: metrics.channelWidth,
            child: Text('Oggi · ${hhmm(now)}',
                style: t.labelLarge?.copyWith(
                    color: VistaColors.accent, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final px = c.maxWidth / window.minutes;
              final step = 30 * px >= 56 ? 30 : 60;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var m = 0; m < window.minutes; m += step)
                    Positioned(
                      left: m * px,
                      top: 0,
                      child: Text(
                        hhmm(window.start.add(Duration(minutes: m))),
                        style: t.labelMedium?.copyWith(color: VistaColors.textTertiary),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Riga della guida: canale a sinistra, programmi in proporzione alla durata,
/// linea dell'ora attuale. Tutta la riga prende il focus; OK guarda il canale.
class GuideRow extends StatelessWidget {
  const GuideRow({
    super.key,
    required this.channel,
    required this.programmes,
    required this.window,
    required this.now,
    required this.metrics,
    required this.onTap,
    this.onLongPress,
    this.onFocused,
    this.focusNode,
    this.autofocus = false,
  });

  final Channel channel;
  final List<EpgProgramme> programmes;
  final GuideWindow window;
  final DateTime now;
  final GuideMetrics metrics;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocused;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final visible = [
      for (final p in programmes)
        if (p.stop.isAfter(window.start) && p.start.isBefore(window.end)) p,
    ];
    return FocusCard(
      autofocus: autofocus,
      focusNode: focusNode,
      focusScale: 1,
      radius: 18,
      fill: const Color(0x08FFFFFF),
      onTap: onTap,
      onLongPress: onLongPress,
      onFocusChange: (f) {
        if (f) onFocused?.call();
      },
      child: SizedBox(
        height: metrics.rowHeight,
        child: Row(
          children: [
            SizedBox(
              width: metrics.channelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text('${channel.number}',
                          style: t.titleSmall?.copyWith(
                              color: VistaColors.textTertiary, fontWeight: FontWeight.w700)),
                    ),
                    ChannelLogo(channel: channel, size: metrics.logo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: LayoutBuilder(builder: (context, c) {
                  final px = c.maxWidth / window.minutes;
                  if (visible.isEmpty) {
                    return _Block(
                      title: 'Nessuna informazione sulla guida',
                      time: '',
                      onAir: false,
                      muted: true,
                    );
                  }
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (final p in visible)
                        () {
                          final left = math.max(0.0, window.offset(p.start, px));
                          final right = math.min(c.maxWidth, window.offset(p.stop, px));
                          return Positioned(
                            left: left,
                            width: math.max(0.0, right - left - 4),
                            top: 0,
                            bottom: 0,
                            child: _Block(
                              title: p.title,
                              time: hhmm(p.start),
                              onAir: p.isOnAt(now),
                            ),
                          );
                        }(),
                      Positioned(
                        left: window.offset(now, px),
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const ColoredBox(color: VistaColors.accent),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    required this.time,
    required this.onAir,
    this.muted = false,
  });

  final String title;
  final String time;
  final bool onAir;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final titleStyle = t.bodyMedium?.copyWith(
      height: 1.15,
      fontWeight: onAir ? FontWeight.w800 : FontWeight.w600,
      color: muted ? VistaColors.textTertiary : Colors.white,
    );
    final timeStyle = t.bodySmall?.copyWith(height: 1.15, color: VistaColors.textTertiary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: onAir ? VistaColors.glassActive : VistaColors.glass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: onAir ? VistaColors.accent.withValues(alpha: 0.7) : VistaColors.glassBorder),
      ),
      // L'orario compare solo se c'è spazio per due righe.
      child: LayoutBuilder(builder: (context, c) {
        final twoLines = time.isNotEmpty && c.maxHeight >= 40;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
            if (twoLines)
              Text(time, maxLines: 1, overflow: TextOverflow.clip, style: timeStyle),
          ],
        );
      }),
    );
  }
}

/// Pannello in alto: il canale col focus e il programma in onda.
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({
    super.key,
    required this.channel,
    required this.upcoming,
    required this.now,
    this.status = '',
  });

  final Channel? channel;
  final List<EpgProgramme> upcoming;
  final DateTime now;
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = channel;
    final current = upcoming.where((p) => p.isOnAt(now)).firstOrNull;
    final next = upcoming.where((p) => !p.start.isBefore(now)).firstOrNull;
    final roomy = MediaQuery.sizeOf(context).width >= 1200;
    return Glass(
      radius: VistaRadius.card,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: roomy ? 140 : 118,
        child: c == null
            ? const SizedBox.shrink()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChannelLogo(channel: c, size: roomy ? 96 : 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.number}  ${c.name}',
                            style: t.labelLarge?.copyWith(color: VistaColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(current?.title ?? 'Nessuna informazione sul programma',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (roomy ? t.headlineSmall : t.titleLarge)
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (!roomy && next != null && next != current)
                          Text('Dopo · ${hhmm(next.start)}  ${next.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(color: VistaColors.accent)),
                        if (current != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('${hhmm(current.start)} – ${hhmm(current.stop)}',
                                  style: t.bodySmall?.copyWith(color: VistaColors.textSecondary)),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 160,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: current.progressAt(now),
                                    minHeight: 5,
                                    backgroundColor: VistaColors.glassActive,
                                  ),
                                ),
                              ),
                              if (current.category.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Text(current.category,
                                    style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Si accorcia (o sparisce) se lo spazio non basta.
                          Flexible(
                            child: Text(
                              current.subtitle.isNotEmpty && current.description.isEmpty
                                  ? current.subtitle
                                  : current.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
                            ),
                          ),
                        ] else if (status.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(status,
                              style: t.bodySmall?.copyWith(color: VistaColors.textTertiary)),
                        ],
                      ],
                    ),
                  ),
                  if (next != null && next != current && roomy)
                    SizedBox(
                      width: 240,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DOPO · ${hhmm(next.start)}',
                              style: t.labelSmall?.copyWith(
                                  color: VistaColors.accent, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(next.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
