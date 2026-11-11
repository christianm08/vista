import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'focus_card.dart';

/// Voce del menu laterale.
class DrawerEntry {
  const DrawerEntry({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing = '',
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String trailing;
  final bool selected;
}

/// Menu laterale a scomparsa, come nelle app TV: sezioni (Live, Film, Serie),
/// categorie della lista e impostazioni. Si apre sopra il contenuto; destra
/// o Indietro lo chiudono. All'apertura il focus va sulla voce selezionata.
class TvDrawer extends StatefulWidget {
  const TvDrawer({
    super.key,
    required this.open,
    required this.sections,
    required this.groups,
    required this.actions,
    required this.onClose,
    this.footer = '',
    this.title = 'Vista',
  });

  final bool open;
  final List<DrawerEntry> sections;
  final List<DrawerEntry> groups;
  final List<DrawerEntry> actions;
  final VoidCallback onClose;
  final String footer;
  final String title;

  @override
  State<TvDrawer> createState() => _TvDrawerState();
}

class _TvDrawerState extends State<TvDrawer> {
  final _target = FocusNode(debugLabel: 'voce selezionata del menu');
  final _scroll = ScrollController();

  static const _groupHeight = 46.0;

  @override
  void didUpdateWidget(TvDrawer old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final i = widget.groups.indexWhere((g) => g.selected);
        if (i > 0 && _scroll.hasClients) {
          _scroll.jumpTo(
            (i * _groupHeight - 120).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _target.context != null) _target.requestFocus();
        });
      });
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final targetIsGroup = widget.groups.any((g) => g.selected);
    return IgnorePointer(
      ignoring: !widget.open,
      child: ExcludeFocus(
        excluding: !widget.open,
        child: Stack(
          children: [
            // Velo sul contenuto: un tocco chiude il menu.
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: widget.open ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: const ColoredBox(color: Color(0x99000000)),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: widget.open ? 0 : -320,
              top: 0,
              bottom: 0,
              width: 300,
              child: Focus(
                skipTraversal: true,
                canRequestFocus: false,
                onKeyEvent: _onKey,
                child: FocusTraversalGroup(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xF00B0E13),
                      border: Border(
                        right: BorderSide(color: VistaColors.glassBorder),
                      ),
                    ),
                    child: SafeArea(
                      right: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    widget.title,
                                    style: t.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                VistaClock(
                                  style: t.titleMedium?.copyWith(
                                    color: VistaColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            for (final s in widget.sections)
                              _entry(
                                s,
                                focusNode: !targetIsGroup && s.selected
                                    ? _target
                                    : null,
                              ),
                            if (widget.groups.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                                child: Text(
                                  'CATEGORIE',
                                  style: t.labelSmall?.copyWith(
                                    color: VistaColors.textTertiary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _scroll,
                                  itemExtent: _groupHeight,
                                  itemCount: widget.groups.length,
                                  itemBuilder: (_, i) => _entry(
                                    widget.groups[i],
                                    focusNode: widget.groups[i].selected
                                        ? _target
                                        : null,
                                    dense: true,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            if (widget.actions.isNotEmpty) ...[
                              const Divider(
                                color: VistaColors.glassBorder,
                                height: 16,
                              ),
                              Row(
                                children: [
                                  for (final a in widget.actions)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: _action(a),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (widget.footer.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                                child: Text(
                                  widget.footer,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall?.copyWith(
                                    color: VistaColors.textTertiary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
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

  /// Azione compatta (icona + etichetta piccola), tre per riga.
  Widget _action(DrawerEntry e) {
    return FocusCard(
      radius: 12,
      focusScale: 1.04,
      fill: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      onTap: e.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(e.icon, size: 20, color: VistaColors.textSecondary),
          const SizedBox(height: 4),
          Text(
            e.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: VistaColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(DrawerEntry e, {FocusNode? focusNode, bool dense = false}) {
    final color = e.selected ? VistaColors.onPrimary : Colors.white;
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 4 : 6),
      child: FocusCard(
        focusNode: focusNode,
        radius: 12,
        focusScale: 1.02,
        selected: e.selected,
        fill: Colors.transparent,
        outline: false,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 9 : 10),
        onTap: e.onTap,
        child: Row(
          children: [
            if (e.icon != null) ...[
              Icon(e.icon, size: dense ? 20 : 22, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: dense ? FontWeight.w600 : FontWeight.w800,
                  fontSize: dense ? 14 : 16,
                ),
              ),
            ),
            if (e.trailing.isNotEmpty)
              Text(
                e.trailing,
                style: TextStyle(
                  fontSize: 12,
                  color: e.selected
                      ? VistaColors.onPrimary
                      : VistaColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
