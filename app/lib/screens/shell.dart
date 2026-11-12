import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../data/window_mode.dart';
import '../theme.dart';
import '../widgets/vista_mark.dart';
import 'catalog_screen.dart';
import 'discover_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Le sezioni dell'app, uguali su ogni dispositivo.
enum Destination {
  search('Cerca', Icons.search_rounded),
  home('Home', Icons.home_rounded),
  discover('Scopri', Icons.explore_rounded),
  live('TV in diretta', Icons.live_tv_rounded),
  movies('Film', Icons.movie_rounded),
  series('Serie TV', Icons.video_library_rounded),
  settings('Impostazioni', Icons.settings_rounded);

  const Destination(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Etichetta corta per la barra del telefono.
  String get short => switch (this) {
    Destination.live => 'TV',
    Destination.series => 'Serie',
    _ => label,
  };
}

/// "Indietro" gestito da una schermata (es. chiudere un pannello). Restituisce
/// `true` se l'ha consumato.
typedef BackHandler = bool Function();

/// Comandi della shell per le schermate figlie.
class ShellController {
  ShellController._(this._state);
  final _AppShellState _state;

  void go(Destination d) => _state._go(d);

  /// Porta il focus sulla barra di navigazione (TV, PC).
  void focusNav() => _state._focusNav();

  void addBackHandler(BackHandler h) => _state._backHandlers.add(h);
  void removeBackHandler(BackHandler h) => _state._backHandlers.remove(h);

  static ShellController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ShellScope>()!.controller;

  static ShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ShellScope>()?.controller;
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({required this.controller, required super.child});
  final ShellController controller;
  @override
  bool updateShouldNotify(_ShellScope old) => false;
}

/// Struttura dell'app: barra laterale (TV, PC, tablet) o barra in basso
/// (telefono) e la sezione corrente.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.library});
  final Library library;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final _controller = ShellController._(this);
  final _backHandlers = <BackHandler>[];
  final _navScope = FocusScopeNode(debugLabel: 'barra di navigazione');
  final _contentScope = FocusScopeNode(debugLabel: 'contenuto');
  final _navNodes = <Destination, FocusNode>{
    for (final d in Destination.values)
      d: FocusNode(debugLabel: 'nav ${d.name}'),
  };

  Destination _current = Destination.home;
  bool _navFocused = false;
  bool _hover = false;
  DateTime? _lastBack;

  Catalog get _catalog => widget.library.catalog;

  List<Destination> get _destinations => [
    Destination.search,
    Destination.home,
    Destination.discover,
    if (_catalog.live.channels.isNotEmpty) Destination.live,
    if (_catalog.movies.isNotEmpty) Destination.movies,
    if (_catalog.series.isNotEmpty) Destination.series,
    Destination.settings,
  ];

  /// L'ultimo canale si riapre una volta sola, all'avvio dell'app.
  static bool _launched = false;

  @override
  void initState() {
    super.initState();
    if (_launched) return;
    _launched = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLastChannel());
  }

  void _openLastChannel() {
    if (!mounted) return;
    final user = AppScope.of(context).user;
    if (!user.startOnLastChannel || user.recentChannels.isEmpty) return;
    final channels = [
      for (final c in _catalog.live.channels)
        if (!c.hidden) c,
    ];
    final last = user.recentChannels.first;
    final c = channels.where((c) => c.key == last).firstOrNull;
    if (c != null) Nav.playChannel(context, channels, c);
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (!_destinations.contains(_current)) _current = Destination.home;
  }

  @override
  void dispose() {
    _navScope.dispose();
    _contentScope.dispose();
    for (final n in _navNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // --- navigazione -------------------------------------------------------------

  void _go(Destination d, {bool focusContent = true}) {
    if (d != _current) setState(() => _current = d);
    if (focusContent) _focusContentSoon();
  }

  /// Dopo il cambio di sezione il focus entra nel contenuto: lo prende
  /// l'elemento con `autofocus`, altrimenti il primo elemento.
  void _focusContentSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _contentScope.hasFocus) return;
        final first = _contentScope.traversalDescendants
            .where(
              (n) =>
                  n.canRequestFocus && !n.skipTraversal && n is! FocusScopeNode,
            )
            .firstOrNull;
        first?.requestFocus();
      });
    });
  }

  void _focusNav() => _navNodes[_current]?.requestFocus();

  /// Dalla barra al contenuto: torna sull'ultimo elemento che aveva il
  /// focus, altrimenti sul primo.
  void _focusContent() {
    _contentScope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = FocusManager.instance.primaryFocus;
      if (!mounted ||
          (p != null && p is! FocusScopeNode && _contentScope.hasFocus)) {
        return;
      }
      _contentScope.traversalDescendants
          .where(
            (n) =>
                n.canRequestFocus && !n.skipTraversal && n is! FocusScopeNode,
          )
          .firstOrNull
          ?.requestFocus();
    });
  }

  /// Le frecce si muovono solo dentro un FocusScope: a sinistra, quando nel
  /// contenuto non c'è più niente, si passa alla barra.
  KeyEventResult _contentKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final p = FocusManager.instance.primaryFocus;
    if (p == null) return KeyEventResult.ignored;
    if (p.focusInDirection(TraversalDirection.left)) {
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent) _focusNav();
    return KeyEventResult.handled;
  }

  void _handleBack({bool allowExit = true}) {
    for (final h in _backHandlers.reversed.toList()) {
      if (h()) return;
    }
    final compact = VistaLayout.of(context).compact;
    if (!compact && !_navScope.hasFocus) {
      _focusNav();
      return;
    }
    if (_current != Destination.home) {
      _go(Destination.home, focusContent: compact);
      if (!compact) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusNav());
      }
      return;
    }
    if (!allowExit) return;
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Premi di nuovo Indietro per uscire'),
        ),
      );
  }

  // --- interfaccia -----------------------------------------------------------

  Widget _screen(Destination d) => switch (d) {
    Destination.home => const HomeScreen(),
    Destination.discover => const DiscoverScreen(),
    Destination.live => const LiveScreen(),
    Destination.movies => const CatalogScreen(kind: CatalogKind.movies),
    Destination.series => const CatalogScreen(kind: CatalogKind.series),
    Destination.search => const SearchScreen(),
    Destination.settings => const SettingsScreen(),
  };

  /// Ogni sezione ha il suo FocusScope nuovo: l'autofocus funziona a ogni
  /// cambio e il focus non resta su un elemento della sezione precedente.
  Widget get _content => FocusScope(
    node: _contentScope,
    child: FocusScope(
      key: ValueKey(_current),
      child: KeyedSubtree(
        key: ValueKey('s-$_current'),
        child: _screen(_current),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    return _ShellScope(
      controller: _controller,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: CallbackShortcuts(
          // Su PC Esc fa da "Indietro" (senza mai chiudere l'app).
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!WindowMode.leaveOnEscape()) _handleBack(allowExit: false);
            },
          },
          child: layout.compact ? _phone(layout) : _wide(layout),
        ),
      ),
    );
  }

  // ===== Telefono ===============================================================

  Widget _phone(VistaLayout layout) {
    final items = [
      for (final d in _destinations)
        if (d != Destination.settings) d,
    ];
    return Scaffold(
      extendBody: true,
      // Il contenuto scorre sotto la barra in basso ma non sotto quella di
      // stato (orologio, batteria): lì si sovrapporrebbe al testo.
      body: SafeArea(bottom: false, child: _content),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: _PillBar(
          items: items,
          current: _current,
          onSelect: (d) => _go(d, focusContent: false),
        ),
      ),
    );
  }

  // ===== TV, PC, tablet =========================================================

  Widget _wide(VistaLayout layout) {
    const collapsed = 76.0;
    const expandedWidth = 232.0;
    // Con lo spazio di una finestra larga (anche su TV, vedi TvCanvas) la
    // barra resta aperta; più stretta si apre col focus o col mouse.
    final pinned = layout.width >= 1280;
    final open = pinned || _navFocused || _hover;
    final contentLeft = pinned ? expandedWidth : collapsed;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            left: contentLeft,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _contentKey,
              // Tablet: niente contenuto sotto la barra di stato.
              child: SafeArea(bottom: false, left: false, child: _content),
            ),
          ),
          // Velo sul contenuto quando la barra si apre sopra.
          if (open && !pinned)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xF2050608),
                        Color(0xB3050608),
                        Color(0x00050608),
                      ],
                      stops: [0, 0.3, 0.6],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: open ? expandedWidth : collapsed,
                child: _SideNav(
                  scope: _navScope,
                  nodes: _navNodes,
                  items: _destinations,
                  current: _current,
                  expanded: open,
                  source: widget.library.source.label,
                  onFocusChange: (v) => setState(() => _navFocused = v),
                  onSelect: _go,
                  onRight: _focusContent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra laterale. All'ingresso del focus si posiziona sulla sezione
/// corrente, non sulla voce più vicina geometricamente.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.scope,
    required this.nodes,
    required this.items,
    required this.current,
    required this.expanded,
    required this.source,
    required this.onFocusChange,
    required this.onSelect,
    required this.onRight,
  });

  final VoidCallback onRight;
  final FocusScopeNode scope;
  final Map<Destination, FocusNode> nodes;
  final List<Destination> items;
  final Destination current;
  final bool expanded;
  final String source;
  final ValueChanged<bool> onFocusChange;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final main = [
      for (final d in items)
        if (d != Destination.settings) d,
    ];
    return FocusScope(
      node: scope,
      onFocusChange: (has) {
        onFocusChange(has);
        if (has) {
          // Entrando da destra si arriva sulla sezione corrente.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = nodes[current];
            final focused = FocusManager.instance.primaryFocus;
            if (target != null &&
                focused != null &&
                !nodes.values.contains(focused)) {
              target.requestFocus();
            }
          });
        }
      },
      onKeyEvent: (node, e) {
        // Destra dalla barra: torna al contenuto.
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.arrowRight) {
          onRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: expanded ? const Color(0xF20A0D12) : const Color(0x990A0D12),
          border: const Border(
            right: BorderSide(color: VistaColors.glassBorder),
          ),
        ),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(expanded: expanded),
                const SizedBox(height: 22),
                for (final d in main)
                  _NavItem(
                    destination: d,
                    focusNode: nodes[d]!,
                    selected: d == current,
                    expanded: expanded,
                    onTap: () => onSelect(d),
                  ),
                const Spacer(),
                if (items.contains(Destination.settings))
                  _NavItem(
                    destination: Destination.settings,
                    focusNode: nodes[Destination.settings]!,
                    selected: current == Destination.settings,
                    expanded: expanded,
                    onTap: () => onSelect(Destination.settings),
                  ),
                if (expanded && source.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
                    child: Text(
                      source,
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
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 6),
          // Lo stesso marchio delle icone dell'app.
          const VistaMark(size: 34),
          if (expanded) ...[
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Vista',
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.focusNode,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final Destination destination;
  final FocusNode focusNode;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fg = sel
        ? VistaColors.onPrimary
        : (_focused ? Colors.white : VistaColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: widget.destination.label,
        excludeFromSemantics: true,
        triggerMode: widget.expanded ? TooltipTriggerMode.manual : null,
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          mouseCursor: SystemMouseCursors.click,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: sel
                    ? Colors.white
                    : (_focused || _hovered
                          ? VistaColors.glassActive
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused
                      ? (sel ? VistaColors.accent : Colors.white)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(widget.destination.icon, size: 22, color: fg),
                  if (widget.expanded) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.destination.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          color: fg,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 15,
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
    );
  }
}

/// Barra a pillola fluttuante del telefono: la voce attiva è una pillola
/// bianca con l'etichetta.
class _PillBar extends StatelessWidget {
  const _PillBar({
    required this.items,
    required this.current,
    required this.onSelect,
  });
  final List<Destination> items;
  final Destination current;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 999,
      fill: const Color(0xCC10141B),
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            for (final d in items)
              Expanded(
                flex: d == current ? 2 : 1,
                child: Semantics(
                  button: true,
                  selected: d == current,
                  label: d.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelect(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: d == current ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            d.icon,
                            size: 22,
                            color: d == current
                                ? VistaColors.onPrimary
                                : VistaColors.textSecondary,
                          ),
                          if (d == current) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                d.short,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: VistaColors.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
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

/// Testo per le sezioni vuote.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: VistaColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: VistaColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Avvisi brevi in basso.
void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}

/// Per le schermate che vogliono la fonte corrente.
VistaSource? currentSource(BuildContext context) =>
    AppScope.of(context).library?.source;
