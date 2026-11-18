import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import 'channel_logo.dart';
import 'vista_cards.dart';
import 'vista_focus.dart';

String hhmm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Inizio della mezz'ora che contiene [t].
DateTime floorHalfHour(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day, l.hour, l.minute < 30 ? 0 : 30);
}

/// "ancora 23 min", "tra 1 h 10 min".
String remaining(EpgProgramme p, DateTime now) {
  String fmt(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    return m % 60 == 0 ? '$h h' : '$h h ${m % 60} min';
  }

  if (p.isOnAt(now)) return 'ancora ${fmt(p.stop.difference(now))}';
  if (p.start.isAfter(now)) return 'tra ${fmt(p.start.difference(now))}';
  return 'terminato';
}

/// Programma in onda all'istante [t] in una lista ordinata.
EpgProgramme? programmeAt(List<EpgProgramme> list, DateTime t) {
  for (final p in list) {
    if (p.isOnAt(t)) return p;
    if (p.start.isAfter(t)) break;
  }
  return null;
}

/// Misure della guida. Cambia solo l'ampiezza della finestra oraria: due ore
/// e mezza sulla tela TV, tre ore su finestre larghe.
class GuideMetrics {
  const GuideMetrics._(this.minutes);

  factory GuideMetrics.of(double width) =>
      width < 1200 ? const GuideMetrics._(150) : const GuideMetrics._(180);

  final int minutes;

  static const channelWidth = VistaSize.guideChannelColumn;

  /// Una riga della lista: la cella più lo spazio sotto, che è più largo di
  /// quanto sporge l'anello della cella a fuoco.
  static const rowHeight = VistaSize.guideRow + gap;

  /// Spazio tra righe, tra celle e tra canale e programmi.
  static const gap = VistaSpace.s8;
}

/// Selezione corrente della guida: canale e programma sotto il cursore.
typedef GuideSelection = ({
  Channel channel,
  EpgProgramme? programme,
  DateTime cursor,
});

/// Guida TV a griglia, comandata col telecomando come nelle app per TV:
/// su/giù cambiano canale mantenendo l'orario, sinistra/destra scorrono i
/// programmi (la finestra oraria segue il cursore), OK guarda il canale,
/// Menu lo modifica. Su dalla prima riga e sinistra dal programma in onda
/// lasciano la guida (verso i filtri e la barra laterale).
class EpgGrid extends StatefulWidget {
  const EpgGrid({
    super.key,
    required this.channels,
    required this.guide,
    required this.now,
    required this.focusNode,
    required this.onSelectionChanged,
    required this.onPlay,
    required this.onEdit,
    this.onExitTop,
  });

  final List<Channel> channels;
  final EpgGuide guide;
  final DateTime now;
  final FocusNode focusNode;
  final ValueChanged<GuideSelection> onSelectionChanged;
  final ValueChanged<Channel> onPlay;
  final ValueChanged<Channel> onEdit;

  /// Su dalla prima riga: dove va il fuoco (es. il filtro scelto). Senza,
  /// decide la geometria.
  final VoidCallback? onExitTop;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  final _scroll = ScrollController();
  int _row = 0;
  late DateTime _cursor = widget.now;
  late DateTime _windowStart = floorHalfHour(widget.now);
  GuideMetrics _metrics = GuideMetrics.of(960);
  bool _focused = false;

  Channel get _channel => widget.channels[_row];

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  @override
  void didUpdateWidget(EpgGrid old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (!identical(old.channels, widget.channels) &&
        (old.channels.length != widget.channels.length ||
            old.channels.isEmpty ||
            widget.channels.isEmpty ||
            old.channels.first.key != widget.channels.first.key)) {
      // Nuova categoria: si riparte dal primo canale e da adesso.
      _row = 0;
      _cursor = widget.now;
      _windowStart = floorHalfHour(widget.now);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    } else if (_row >= widget.channels.length) {
      _row = math.max(0, widget.channels.length - 1);
    }
    // L'EPG arriva dopo l'apertura: l'intestazione va aggiornata.
    if (!identical(old.guide, widget.guide)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    }
    // Il tempo passa: il cursore non resta nel passato.
    if (_cursor.isBefore(widget.now)) {
      _cursor = widget.now;
      // L'intestazione passa al programma ora in onda, non resta su
      // quello appena finito.
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    }
    final floor = floorHalfHour(widget.now);
    if (_windowStart.isBefore(floor)) _windowStart = floor;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  List<EpgProgramme> _programmes(Channel c) =>
      widget.guide.forChannel(c, now: widget.now);

  void _notify() {
    if (!mounted || widget.channels.isEmpty) return;
    widget.onSelectionChanged((
      channel: _channel,
      programme: programmeAt(_programmes(_channel), _cursor),
      cursor: _cursor,
    ));
  }

  // --- movimento -------------------------------------------------------------

  void _moveRow(int delta) {
    final next = (_row + delta).clamp(0, widget.channels.length - 1);
    if (next == _row) return;
    setState(() => _row = next);
    _ensureVisible();
    _notify();
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const h = GuideMetrics.rowHeight;
    final pos = _scroll.position;
    final top = _row * h;
    // Tiene una riga di margine sopra e sotto, come le guide TV.
    if (top - h < pos.pixels) {
      _scroll.jumpTo(math.max(0, top - h));
    } else if (top + 2 * h > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo(
        math.min(pos.maxScrollExtent, top + 2 * h - pos.viewportDimension),
      );
    }
  }

  /// Sposta il cursore al programma successivo o precedente. Restituisce
  /// false se a sinistra non c'è niente (siamo sul programma in onda).
  bool _moveTime(int dir) {
    final list = _programmes(_channel);
    final current = programmeAt(list, _cursor);
    final now = widget.now;
    if (dir > 0) {
      final from = current?.stop ?? _cursor;
      final next = list.where((p) => !p.start.isBefore(from)).firstOrNull;
      if (next == null) return true;
      _cursor = next.start;
    } else {
      if (current == null || !current.start.isAfter(now)) return false;
      final prev = list.where((p) => !p.stop.isAfter(current.start)).lastOrNull;
      _cursor = prev == null || prev.stop.isBefore(now)
          ? now
          : (prev.start.isBefore(now) ? now : prev.start);
    }
    final span = Duration(minutes: _metrics.minutes);
    while (!_cursor.isBefore(
      _windowStart.add(span - const Duration(minutes: 30)),
    )) {
      _windowStart = _windowStart.add(const Duration(minutes: 30));
    }
    while (_cursor.isBefore(_windowStart)) {
      _windowStart = _windowStart.subtract(const Duration(minutes: 30));
    }
    final floor = floorHalfHour(now);
    if (_windowStart.isBefore(floor)) _windowStart = floor;
    setState(() {});
    _notify();
    return true;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || widget.channels.isEmpty) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final page = math.max(1, (_visibleRows - 2));
    if (k == LogicalKeyboardKey.arrowDown) {
      _moveRow(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      // Dalla prima riga si sale ai filtri.
      if (_row == 0) {
        final exit = widget.onExitTop;
        if (exit == null) return KeyEventResult.ignored;
        if (e is KeyDownEvent) exit();
        return KeyEventResult.handled;
      }
      _moveRow(-1);
    } else if (k == LogicalKeyboardKey.channelDown ||
        k == LogicalKeyboardKey.pageDown) {
      _moveRow(page);
    } else if (k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.pageUp) {
      _moveRow(-page);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _moveTime(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      // Sul programma in onda si esce verso la barra laterale.
      if (!_moveTime(-1)) return KeyEventResult.ignored;
    } else if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.gameButtonA)) {
      widget.onPlay(_channel);
    } else if (e is KeyDownEvent && k == LogicalKeyboardKey.contextMenu) {
      widget.onEdit(_channel);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int _visibleRows = 6;

  void _tapRow(int row, DateTime? at) {
    widget.focusNode.requestFocus();
    if (row == _row &&
        (at == null ||
            programmeAt(_programmes(_channel), at) ==
                programmeAt(_programmes(_channel), _cursor))) {
      widget.onPlay(_channel);
      return;
    }
    setState(() {
      _row = row;
      if (at != null && !at.isBefore(widget.now)) _cursor = at;
    });
    _notify();
  }

  // --- interfaccia -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          _metrics = GuideMetrics.of(box.maxWidth);
          const left = GuideMetrics.channelWidth + GuideMetrics.gap;
          final timelineWidth = box.maxWidth - left;
          final px = timelineWidth / _metrics.minutes;
          final nowX = widget.now.difference(_windowStart).inSeconds / 60 * px;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Ruler(
                start: _windowStart,
                minutes: _metrics.minutes,
                nowX: nowX,
                pxPerMinute: px,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, rows) {
                    _visibleRows = (rows.maxHeight / GuideMetrics.rowHeight)
                        .floor();
                    return Stack(
                      children: [
                        // Linea "adesso": una sola, sotto le celle: si vede
                        // negli spazi tra le righe e non copre i testi.
                        if (nowX >= 0 && nowX <= timelineWidth)
                          Positioned(
                            left: left + nowX - VistaSize.guideNowLine / 2,
                            top: 0,
                            bottom: 0,
                            width: VistaSize.guideNowLine,
                            child: const IgnorePointer(
                              child: ColoredBox(color: VistaColors.accent),
                            ),
                          ),
                        ListView.builder(
                          controller: _scroll,
                          itemExtent: GuideMetrics.rowHeight,
                          itemCount: widget.channels.length,
                          // Sopra la prima riga, spazio per l'anello.
                          padding: const EdgeInsets.only(top: GuideMetrics.gap),
                          itemBuilder: (_, i) => _Row(
                            key: ValueKey(widget.channels[i].key),
                            channel: widget.channels[i],
                            programmes: _programmes(widget.channels[i]),
                            minutes: _metrics.minutes,
                            windowStart: _windowStart,
                            pxPerMinute: px,
                            now: widget.now,
                            selected: i == _row,
                            focused: _focused,
                            cursor: _cursor,
                            onTap: (at) => _tapRow(i, at),
                            onLongPress: () =>
                                widget.onEdit(widget.channels[i]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Asse orario: il giorno sopra la colonna dei canali, le mezz'ore e il
/// punto "adesso" da cui scende la linea.
class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.start,
    required this.minutes,
    required this.nowX,
    required this.pxPerMinute,
  });

  final DateTime start;
  final int minutes;
  final double nowX;
  final double pxPerMinute;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meta = t.bodySmall?.copyWith(
      color: VistaColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final today = DateUtils.isSameDay(start, DateTime.now());
    const days = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
    return SizedBox(
      height: VistaSize.guideRuler,
      child: Row(
        children: [
          SizedBox(
            width: GuideMetrics.channelWidth + GuideMetrics.gap,
            child: Text(
              today ? 'Oggi' : '${days[start.weekday - 1]} ${start.day}',
              style: meta,
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var m = 0; m < minutes; m += 30)
                  Positioned(
                    left: m * pxPerMinute,
                    top: 0,
                    child: Text(
                      hhmm(start.add(Duration(minutes: m))),
                      style: meta,
                    ),
                  ),
                if (nowX >= 0)
                  Positioned(
                    left: nowX - VistaSize.guideNowDot / 2,
                    bottom: 0,
                    width: VistaSize.guideNowDot,
                    height: VistaSize.guideNowDot,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: VistaColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.channel,
    required this.programmes,
    required this.minutes,
    required this.windowStart,
    required this.pxPerMinute,
    required this.now,
    required this.selected,
    required this.focused,
    required this.cursor,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final List<EpgProgramme> programmes;
  final int minutes;
  final DateTime windowStart;
  final double pxPerMinute;
  final DateTime now;
  final bool selected;
  final bool focused;
  final DateTime cursor;
  final ValueChanged<DateTime?> onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = selected && focused;
    final end = windowStart.add(Duration(minutes: minutes));
    final visible = [
      for (final p in programmes)
        if (p.stop.isAfter(windowStart) && p.start.isBefore(end)) p,
    ];
    final current = selected ? programmeAt(programmes, cursor) : null;
    double x(DateTime d) =>
        d.difference(windowStart).inSeconds / 60 * pxPerMinute;

    return Padding(
      padding: const EdgeInsets.only(bottom: GuideMetrics.gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Colonna del canale: numero, logo, nome.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(null),
            onLongPress: onLongPress,
            child: SizedBox(
              width: GuideMetrics.channelWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: VistaSize.guideNumber,
                    child: Text(
                      '${channel.number}',
                      maxLines: 1,
                      style: t.labelLarge?.copyWith(
                        color: active
                            ? VistaColors.text
                            : VistaColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  ChannelLogo(channel: channel, size: VistaSize.guideLogo),
                  const SizedBox(width: VistaSpace.s12),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: GuideMetrics.gap),
          // Programmi, larghi quanto durano. Nessun ritaglio: le celle
          // stanno già dentro la finestra e l'anello resta visibile.
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (visible.isEmpty) {
                  // Lo spazio a destra, come le altre celle: l'anello
                  // resta dentro la guida.
                  return Padding(
                    padding: const EdgeInsets.only(right: GuideMetrics.gap),
                    child: _Cell(
                      title: 'Nessuna informazione',
                      active: active,
                      onAir: false,
                      muted: true,
                      onTap: () => onTap(null),
                    ),
                  );
                }
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final p in visible)
                      () {
                        final left = math.max(0.0, x(p.start));
                        final right = math.min(c.maxWidth, x(p.stop));
                        return Positioned(
                          left: left,
                          width: math.max(0.0, right - left - GuideMetrics.gap),
                          top: 0,
                          bottom: 0,
                          child: _Cell(
                            title: p.title,
                            time: '${hhmm(p.start)} – ${hhmm(p.stop)}',
                            shortTime: hhmm(p.start),
                            active: active && identical(p, current),
                            highlighted:
                                selected && !focused && identical(p, current),
                            onAir: p.isOnAt(now),
                            onTap: () =>
                                onTap(p.start.isBefore(now) ? now : p.start),
                          ),
                        );
                      }(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Cella di un programma: superficie, un gradino più chiara se è in onda,
/// la più chiara con anello se è a fuoco. Niente scala.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.title,
    required this.active,
    required this.onAir,
    required this.onTap,
    this.time,
    this.shortTime,
    this.highlighted = false,
    this.muted = false,
  });

  final String title;
  final String? time;
  final String? shortTime;
  final bool active;
  final bool highlighted;
  final bool onAir;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Sul fondo della pagina le celle devono staccarsi: le future su
    // surfaceHigh, quella in onda un gradino sopra.
    final rest = highlighted || onAir
        ? VistaColors.surfaceSelected
        : VistaColors.surfaceHigh;
    return GestureDetector(
      onTap: onTap,
      child: VistaFocusEffect(
        active: active,
        kind: VistaFocusKind.flat,
        radius: VistaRadius.chip,
        fill: rest,
        activeFill: VistaColors.surfaceSelected,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VistaRadius.chip),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: t.labelLarge?.copyWith(
                        fontWeight: VistaType.strong,
                        color: muted
                            ? VistaColors.textSecondary
                            : VistaColors.text,
                      ),
                    ),
                    if (time != null)
                      LayoutBuilder(
                        builder: (context, box) {
                          final style = t.bodySmall?.copyWith(
                            color: active
                                ? VistaColors.textBody
                                : VistaColors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          );
                          // Nelle celle strette solo l'inizio: un orario
                          // tagliato a metà ("20:45 – 2") non si legge.
                          final full = TextPainter(
                            text: TextSpan(text: time, style: style),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout();
                          final fits = full.width <= box.maxWidth;
                          full.dispose();
                          return Text(
                            fits ? time! : shortTime ?? time!,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: style,
                          );
                        },
                      ),
                  ],
                ),
              ),
              // Riga scelta mentre il fuoco è altrove (sui chip): una tacca
              // accent la distingue dalle altre celle in onda.
              if (highlighted)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: VistaSize.guideNowLine,
                  child: ColoredBox(color: VistaColors.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Canale a fuoco nella guida (TV e PC): anteprima dal vivo a sinistra;
/// a destra canale, programma, orario con avanzamento, trama e qualità.
class LiveHeader extends StatelessWidget {
  const LiveHeader({
    super.key,
    required this.selection,
    required this.now,
    required this.preview,
    this.status = '',
  });

  final GuideSelection? selection;
  final DateTime now;
  final Widget preview;

  /// Stato dell'EPG (es. "Scarico la guida…") quando manca il programma.
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = selection;
    final p = s?.programme;
    final onAir = p != null && p.isOnAt(now);
    final meta = t.labelLarge?.copyWith(
      color: VistaColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final about = p == null
        ? ''
        : (p.description.isNotEmpty ? p.description : p.subtitle);
    return SizedBox(
      height: VistaSize.livePreview.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.fromSize(
            size: VistaSize.livePreview,
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (onAir)
                  const Positioned(
                    left: VistaSpace.s12,
                    top: VistaSpace.s12,
                    child: VistaLabel('IN ONDA', dot: true),
                  ),
              ],
            ),
          ),
          const SizedBox(width: VistaSpace.s32),
          if (s != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.channel.number} · ${s.channel.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                  const SizedBox(height: VistaSpace.s8),
                  Text(
                    p?.title ?? 'Nessuna informazione',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headlineLarge,
                  ),
                  const SizedBox(height: VistaSpace.s8),
                  if (p != null)
                    Row(
                      children: [
                        Text('${hhmm(p.start)} – ${hhmm(p.stop)}', style: meta),
                        if (onAir) ...[
                          const SizedBox(width: VistaSpace.s12),
                          SizedBox(
                            width: VistaSize.liveProgress,
                            child: VistaProgressBar(p.progressAt(now)),
                          ),
                        ],
                        const SizedBox(width: VistaSpace.s12),
                        Flexible(
                          child: Text(
                            [
                              remaining(p, now),
                              if (p.category.isNotEmpty) p.category,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                        ),
                      ],
                    )
                  else if (status.isNotEmpty)
                    Text(status, style: meta),
                  if (about.isNotEmpty) ...[
                    const SizedBox(height: VistaSpace.s8),
                    Text(
                      about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        color: VistaColors.textBody,
                      ),
                    ),
                  ],
                  const Spacer(),
                  _Qualities(s.channel),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Qualità disponibili del canale: "Auto" (parte dal flusso migliore) e le
/// altre. Solo informazione: la scelta si fa nel player.
class _Qualities extends StatelessWidget {
  const _Qualities(this.channel);
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // In ordine, dal migliore, una volta sola.
    final labels = <String>{
      for (final s in channel.streams)
        if (s.quality != Quality.auto) s.quality.label,
    }.toList();
    final best = labels.isEmpty ? null : labels.first;
    final n = channel.streams.length;
    return Row(
      children: [
        _Tag(
          best == null ? 'Auto' : 'Auto · $best',
          icon: Icons.check_rounded,
          strong: true,
        ),
        for (final l in labels.skip(1)) ...[
          const SizedBox(width: VistaSpace.s8),
          _Tag(l),
        ],
        if (n > 1) ...[
          const SizedBox(width: VistaSpace.s12),
          Flexible(
            child: Text(
              '$n flussi uniti in un canale',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: VistaColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// Etichetta a forma di chip, non selezionabile.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.icon, this.strong = false});
  final String text;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = strong ? VistaColors.text : VistaColors.textSecondary;
    return Container(
      height: VistaSize.chipCompact,
      padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s12),
      decoration: BoxDecoration(
        color: strong ? VistaColors.surfaceHigh : VistaColors.surface,
        borderRadius: BorderRadius.circular(VistaRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: VistaSize.iconSmall, color: fg),
            const SizedBox(width: VistaSpace.s8),
          ],
          Text(
            text,
            style: t.bodySmall?.copyWith(
              color: fg,
              fontWeight: VistaType.strong,
            ),
          ),
        ],
      ),
    );
  }
}
