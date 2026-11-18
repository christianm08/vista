import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/source_store.dart';
import '../data/window_mode.dart';
import '../theme.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_nav.dart';
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

  /// Quanto è aperta la barra laterale: su TV sposta il contenuto.
  final _railRevealed = ValueNotifier<double>(0);
  final _navNodes = <Destination, FocusNode>{
    for (final d in Destination.values)
      d: FocusNode(debugLabel: 'nav ${d.name}'),
  };

  Destination _current = Destination.home;
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
    _railRevealed.dispose();
    for (final n in _navNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // --- navigazione -------------------------------------------------------------

  void _go(Destination d, {bool focusContent = true}) {
    final parental = AppScope.of(context).parental;
    if (d == Destination.settings &&
        d != _current &&
        parental.locksSettings &&
        !parental.isUnlocked) {
      parental
          .unlock(context, reason: 'Le impostazioni sono protette dal PIN.')
          .then((ok) {
            if (ok && mounted) _go(d, focusContent: focusContent);
          });
      return;
    }
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
          duration: VistaMotion.toast,
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

  /// Voci della barra in basso: Cerca e Impostazioni stanno nell'intestazione
  /// della Home.
  List<Destination> get _phoneItems => [
    for (final d in _destinations)
      if (d != Destination.search && d != Destination.settings) d,
  ];

  Widget _phone(VistaLayout layout) {
    final items = _phoneItems;
    final index = items.indexOf(_current);
    return Scaffold(
      // La Home disegna il suo riquadro anche sotto la barra di stato;
      // le altre sezioni no, lì si sovrapporrebbe al testo.
      body: _current == Destination.home
          ? _content
          : SafeArea(bottom: false, child: _content),
      bottomNavigationBar: VistaNavBar(
        items: [for (final d in items) VistaNavItem(d.label, d.icon)],
        selected: index < 0 ? null : index,
        onSelect: (i) => _go(items[i], focusContent: false),
      ),
    );
  }

  // ===== TV, PC, tablet =========================================================

  Widget _wide(VistaLayout layout) {
    final all = _destinations;
    final main = [
      for (final d in all)
        if (d != Destination.settings) d,
    ];
    final footer = all.contains(Destination.settings)
        ? Destination.settings
        : null;
    final order = [...main, ?footer];
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            left: layout.contentLeft,
            // Su TV la barra aperta sposta il contenuto invece di coprirlo
            // (una traslazione: il layout non cambia). Su PC no: col mouse
            // la pagina si sposterebbe a ogni passaggio sulle icone.
            child: ValueListenableBuilder(
              valueListenable: _railRevealed,
              builder: (context, v, child) => Transform.translate(
                offset: Offset(
                  layout.tv
                      ? (VistaSize.railExpanded - layout.contentLeft) * v
                      : 0,
                  0,
                ),
                child: child,
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _contentKey,
                // Tablet: niente contenuto sotto la barra di stato.
                child: SafeArea(bottom: false, left: false, child: _content),
              ),
            ),
          ),
          // La barra si apre sopra il contenuto, piena e opaca: il contenuto
          // non si sposta e non passa mai sotto una superficie trasparente.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: VistaSize.railExpanded,
            child: FocusScope(
              node: _navScope,
              onFocusChange: (has) {
                if (!has) return;
                // Entrando da destra si arriva sulla sezione corrente.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final target = _navNodes[_current];
                  final focused = FocusManager.instance.primaryFocus;
                  if (target != null &&
                      focused != null &&
                      !_navNodes.values.contains(focused)) {
                    target.requestFocus();
                  }
                });
              },
              onKeyEvent: (node, e) {
                // Destra dalla barra: torna al contenuto.
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _focusContent();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: VistaRail(
                items: [for (final d in main) VistaNavItem(d.label, d.icon)],
                footer: footer == null
                    ? null
                    : VistaNavItem(footer.label, footer.icon),
                selected: order.indexOf(_current),
                focusNodes: [for (final d in order) _navNodes[d]!],
                onSelect: (i) => _go(order[i]),
                revealed: _railRevealed,
                caption: widget.library.sources.length > 1
                    ? '${widget.library.sources.length} fonti'
                    : widget.library.source.displayName,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stato vuoto o di errore di una sezione: una frase, una riga di
/// spiegazione e, se c'è, un'azione ("Riprova" per gli errori).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
    this.onAction,
    this.autofocus = false,
  }) : error = false;

  /// Qualcosa non ha funzionato: cosa è successo e "Riprova".
  const EmptyState.error({
    super.key,
    required this.title,
    this.message = '',
    this.onAction,
    this.autofocus = false,
  }) : icon = Icons.error_outline_rounded,
       action = 'Riprova',
       error = true;

  final IconData icon;
  final String title;
  final String message;

  /// Testo del pulsante; senza [onAction] il pulsante non c'è.
  final String? action;
  final VoidCallback? onAction;
  final bool autofocus;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VistaSpace.s32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: VistaSize.stateText),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: VistaSize.stateIcon,
                color: error ? VistaColors.error : VistaColors.textSecondary,
              ),
              const SizedBox(height: VistaSpace.s16),
              Text(title, textAlign: TextAlign.center, style: t.titleLarge),
              if (message.isNotEmpty) ...[
                const SizedBox(height: VistaSpace.s8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(
                    color: VistaColors.textSecondary,
                  ),
                ),
              ],
              if (action != null && onAction != null) ...[
                const SizedBox(height: VistaSpace.s24),
                VistaButton.tonal(
                  label: action!,
                  icon: error ? Icons.refresh_rounded : null,
                  autofocus: autofocus,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Avvisi brevi in basso.
void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: VistaMotion.toast));
}

/// Per le schermate che vogliono la fonte corrente.
VistaSource? currentSource(BuildContext context) =>
    AppScope.of(context).library?.source;
