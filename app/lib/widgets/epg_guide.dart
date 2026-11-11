import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../theme.dart';
import 'channel_logo.dart';

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

/// Misure della guida: una TV 1080p ha 960 punti logici di larghezza.
class GuideMetrics {
  const GuideMetrics._(
    this.channelWidth,
    this.minutes,
    this.rowHeight,
    this.logo,
  );

  factory GuideMetrics.of(double width) => width < 1200
      ? const GuideMetrics._(210, 120, 54, 34)
      : const GuideMetrics._(280, 180, 64, 42);

  final double channelWidth;
  final int minutes;
  final double rowHeight;
  final double logo;
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
/// Menu lo modifica. Sinistra sul programma in onda apre il menu laterale.
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
    required this.onOpenMenu,
  });

  final List<Channel> channels;
  final EpgGuide guide;
  final DateTime now;
  final FocusNode focusNode;
  final ValueChanged<GuideSelection> onSelectionChanged;
  final ValueChanged<Channel> onPlay;
  final ValueChanged<Channel> onEdit;
  final VoidCallback onOpenMenu;

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
    if (_cursor.isBefore(widget.now)) _cursor = widget.now;
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
    final h = _metrics.rowHeight;
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
      if (!_moveTime(-1) && e is KeyDownEvent) widget.onOpenMenu();
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
          final timelineWidth = box.maxWidth - _metrics.channelWidth;
          final px = timelineWidth / _metrics.minutes;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Ruler(
                start: _windowStart,
                minutes: _metrics.minutes,
                now: widget.now,
                channelWidth: _metrics.channelWidth,
                pxPerMinute: px,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, rows) {
                    _visibleRows = (rows.maxHeight / _metrics.rowHeight)
                        .floor();
                    return ListView.builder(
                      controller: _scroll,
                      itemExtent: _metrics.rowHeight,
                      itemCount: widget.channels.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (_, i) => _Row(
                        channel: widget.channels[i],
                        programmes: _programmes(widget.channels[i]),
                        metrics: _metrics,
                        windowStart: _windowStart,
                        pxPerMinute: px,
                        now: widget.now,
                        selected: i == _row,
                        focused: _focused,
                        cursor: _cursor,
                        onTap: (at) => _tapRow(i, at),
                        onLongPress: () => widget.onEdit(widget.channels[i]),
                      ),
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

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.start,
    required this.minutes,
    required this.now,
    required this.channelWidth,
    required this.pxPerMinute,
  });

  final DateTime start;
  final int minutes;
  final DateTime now;
  final double channelWidth;
  final double pxPerMinute;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final today = DateUtils.isSameDay(start, DateTime.now());
    const days = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
    final nowX = now.difference(start).inSeconds / 60 * pxPerMinute;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: channelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                today ? 'Oggi' : '${days[start.weekday - 1]} ${start.day}',
                style: t.labelLarge?.copyWith(
                  color: VistaColors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var m = 0; m < minutes; m += 30)
                  Positioned(
                    left: m * pxPerMinute,
                    top: 4,
                    child: Row(
                      children: [
                        Container(
                          width: 1,
                          height: 14,
                          color: VistaColors.glassBorder,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hhmm(start.add(Duration(minutes: m))),
                          style: t.labelMedium?.copyWith(
                            color: VistaColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (nowX >= 0)
                  Positioned(
                    left: math.max(0, nowX - 22),
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: VistaColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        hhmm(now),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: VistaColors.onPrimary,
                        ),
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
    required this.channel,
    required this.programmes,
    required this.metrics,
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
  final GuideMetrics metrics;
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
    final end = windowStart.add(Duration(minutes: metrics.minutes));
    final visible = [
      for (final p in programmes)
        if (p.stop.isAfter(windowStart) && p.start.isBefore(end)) p,
    ];
    final current = selected ? programmeAt(programmes, cursor) : null;
    double x(DateTime d) =>
        d.difference(windowStart).inSeconds / 60 * pxPerMinute;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          // Colonna del canale
          GestureDetector(
            onTap: () => onTap(null),
            onLongPress: onLongPress,
            child: Container(
              width: metrics.channelWidth,
              margin: const EdgeInsets.only(right: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? VistaColors.glassActive
                    : (selected
                          ? VistaColors.glassHigh
                          : const Color(0x0DFFFFFF)),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: active ? VistaColors.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${channel.number}',
                      style: t.labelLarge?.copyWith(
                        color: active ? Colors.white : VistaColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ChannelLogo(channel: channel, size: metrics.logo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Programmi
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (visible.isEmpty) {
                  return _Cell(
                    title: 'Nessuna informazione',
                    selected: active,
                    onAir: false,
                    progress: 0,
                    muted: true,
                    onTap: () => onTap(null),
                  );
                }
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final p in visible)
                      () {
                        final left = math.max(0.0, x(p.start));
                        final right = math.min(c.maxWidth, x(p.stop));
                        return Positioned(
                          left: left,
                          width: math.max(0.0, right - left - 3),
                          top: 0,
                          bottom: 0,
                          child: _Cell(
                            title: p.title,
                            selected: active && identical(p, current),
                            highlighted:
                                selected && !focused && identical(p, current),
                            onAir: p.isOnAt(now),
                            progress: p.progressAt(now),
                            onTap: () =>
                                onTap(p.start.isBefore(now) ? now : p.start),
                          ),
                        );
                      }(),
                    Positioned(
                      left: x(now),
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: const ColoredBox(color: VistaColors.accent),
                    ),
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.title,
    required this.selected,
    required this.onAir,
    required this.progress,
    required this.onTap,
    this.highlighted = false,
    this.muted = false,
  });

  final String title;
  final bool selected;
  final bool highlighted;
  final bool onAir;
  final double progress;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fill = selected
        ? Colors.white
        : highlighted
        ? VistaColors.glassActive
        : (onAir ? const Color(0x1FFFFFFF) : const Color(0x0DFFFFFF));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Parte già andata in onda, appena più scura.
            if (onAir && !selected)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: const ColoredBox(color: Color(0x0FFFFFFF)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: selected || onAir
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: selected
                        ? VistaColors.onPrimary
                        : (muted ? VistaColors.textTertiary : Colors.white),
                  ),
                ),
              ),
            ),
            if (onAir)
              Positioned(
                left: 0,
                bottom: 0,
                height: 3,
                width: null,
                right: 0,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: const ColoredBox(color: VistaColors.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Intestazione della guida: dettagli del programma selezionato e, a destra,
/// l'anteprima del canale.
class GuideHeader extends StatelessWidget {
  const GuideHeader({
    super.key,
    required this.selection,
    required this.now,
    required this.preview,
    this.category,
    this.status = '',
  });

  final GuideSelection? selection;
  final DateTime now;
  final Widget preview;
  final String? category;
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = selection;
    final p = s?.programme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 24, 8),
            child: s == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (category ?? 'Tutti i canali').toUpperCase(),
                        style: t.labelMedium?.copyWith(
                          color: VistaColors.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ChannelLogo(channel: s.channel, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${s.channel.number}  ${s.channel.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(
                                color: VistaColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p?.title ?? 'Nessuna informazione sul programma',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (p != null)
                        Row(
                          children: [
                            Text(
                              '${hhmm(p.start)} – ${hhmm(p.stop)}',
                              style: t.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (p.isOnAt(now)) ...[
                              SizedBox(
                                width: 110,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: p.progressAt(now),
                                    minHeight: 4,
                                    backgroundColor: VistaColors.glassActive,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                [
                                  remaining(p, now),
                                  if (p.category.isNotEmpty) p.category,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(
                                  color: VistaColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (status.isNotEmpty)
                        Text(
                          status,
                          style: t.bodySmall?.copyWith(
                            color: VistaColors.textTertiary,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (p != null)
                        Expanded(
                          child: Text(
                            p.description.isNotEmpty
                                ? p.description
                                : p.subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(
                              color: VistaColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              // Orologio in alto a destra, sopra l'anteprima.
              Positioned(
                top: 8,
                right: 12,
                child: VistaClock(
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
