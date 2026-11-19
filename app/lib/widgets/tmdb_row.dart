import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import 'vista_cards.dart';
import 'vista_focus.dart';
import 'vista_row.dart';

void toggleSavedTitle(BuildContext context, TmdbTitle t) {
  final user = AppScope.of(context).user;
  user.toggleSaved(
    SavedTitle(key: t.key, title: t.title, poster: t.poster, year: t.year),
  );
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: VistaMotion.toast,
        content: Text(
          user.isFavorite(t.key)
              ? '${t.title} aggiunto alla tua lista'
              : '${t.title} tolto dalla tua lista',
        ),
      ),
    );
}

/// Locandina di un titolo TMDB con i componenti nuovi: etichetta "IPTV" se
/// lo ha anche la lista dell'utente, segnalibro se è nella sua lista.
/// Tocco lungo: La mia lista.
Widget tmdbPosterCard(
  BuildContext context,
  TmdbTitle t, {
  required double width,
  bool showText = true,
  bool autofocus = false,
  ValueChanged<bool>? onFocusChange,
}) {
  final app = AppScope.of(context);
  final lib = app.library;
  final inIptv =
      lib != null &&
      (t.type == MediaType.movie
          ? app.tmdb.localMovie(lib.catalog, t) != null
          : app.tmdb.localSeries(lib.catalog, t) != null);
  return VistaPosterCard(
    title: t.title,
    image: t.poster,
    restWidth: width,
    showText: showText,
    autofocus: autofocus,
    label: inIptv ? 'IPTV' : '',
    saved: app.user.isFavorite(t.key),
    meta: tmdbMeta(t),
    onTap: () => Nav.openTmdb(context, t),
    onLongPress: () => toggleSavedTitle(context, t),
    onFocusChange: onFocusChange,
  );
}

/// Anno · tipo · voto di un titolo TMDB.
String tmdbMeta(TmdbTitle t) => metaLine([
  if (t.year != null) '${t.year}',
  t.type == MediaType.tv ? 'Serie' : 'Film',
  if (t.rating > 0) '${t.rating.toStringAsFixed(1).replaceAll('.', ',')}/10',
]);

/// Riga di titoli TMDB caricata in modo asincrono, coi componenti nuovi
/// ([VistaRow]): segnaposto mentre carica, sparisce se vuota o in errore.
/// L'ultima scheda apre l'elenco completo.
class TmdbVistaRow extends StatefulWidget {
  const TmdbVistaRow({
    super.key,
    required this.title,
    required this.load,
    this.onSeeAll,
    this.showText = true,
    this.onFocusTitle,
  });

  final String title;
  final Future<List<TmdbTitle>> Function() load;
  final VoidCallback? onSeeAll;
  final bool showText;

  /// Un titolo prende il fuoco (per l'anteprima).
  final ValueChanged<TmdbTitle>? onFocusTitle;

  @override
  State<TmdbVistaRow> createState() => _TmdbVistaRowState();
}

class _TmdbVistaRowState extends State<TmdbVistaRow> {
  late Future<List<TmdbTitle>> _future = widget.load();

  @override
  void didUpdateWidget(TmdbVistaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    final pw = VistaLayout.of(context).posterWidth;
    final h = VistaPosterCard.heightFor(context, pw, widget.showText);
    return FutureBuilder<List<TmdbTitle>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return VistaRowSkeleton(
            title: widget.title,
            itemWidth: pw,
            itemHeight: h,
            aspect: VistaPosterCard.aspect,
          );
        }
        final items = snap.data ?? const <TmdbTitle>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final more = widget.onSeeAll != null;
        return VistaRow(
          title: widget.title,
          itemCount: items.length + (more ? 1 : 0),
          itemKey: (i) =>
              ValueKey(i == items.length ? 'tm-more' : items[i].key),
          itemWidth: pw,
          itemHeight: h,
          itemBuilder: (context, i) {
            if (i == items.length) return _VistaSeeAll(onTap: widget.onSeeAll!);
            final t = items[i];
            return tmdbPosterCard(
              context,
              t,
              width: pw,
              showText: widget.showText,
              onFocusChange: (has) {
                if (has) widget.onFocusTitle?.call(t);
              },
            );
          },
        );
      },
    );
  }
}

/// Ultima scheda di una riga: "Vedi tutto".
class _VistaSeeAll extends StatelessWidget {
  const _VistaSeeAll({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.topLeft,
      child: AspectRatio(
        aspectRatio: VistaPosterCard.aspect,
        child: VistaFocusable(
          onTap: onTap,
          fill: VistaColors.surface,
          semanticLabel: 'Vedi tutto',
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_forward_rounded),
                const SizedBox(height: VistaSpace.s8),
                Text('Vedi tutto', style: t.titleSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unisce film e serie in un'unica lista, alternandoli per popolarità.
List<TmdbTitle> mergeByPopularity(List<TmdbTitle> a, List<TmdbTitle> b) =>
    ([...a, ...b]..sort((x, y) => y.popularity.compareTo(x.popularity)));
