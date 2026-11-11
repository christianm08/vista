import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../theme.dart';
import 'content_row.dart';
import 'focus_card.dart';
import 'poster_card.dart';

/// Locandina di un titolo TMDB, con l'etichetta "IPTV" se lo ha anche la
/// lista dell'utente. Tocco lungo: La mia lista.
class TmdbPoster extends StatelessWidget {
  const TmdbPoster(this.title, {super.key, this.autofocus = false});
  final TmdbTitle title;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = title;
    final lib = app.library;
    final inIptv =
        lib != null &&
        (t.type == MediaType.movie
            ? app.tmdb.localMovie(lib.catalog, t) != null
            : app.tmdb.localSeries(lib.catalog, t) != null);
    return PosterCard(
      autofocus: autofocus,
      title: t.title,
      image: t.poster,
      badge: inIptv ? 'IPTV' : '',
      favorite: app.user.isFavorite(t.key),
      caption: metaLine([
        if (t.year != null) '${t.year}',
        t.type == MediaType.tv ? 'Serie' : 'Film',
        if (t.rating > 0)
          '★ ${t.rating.toStringAsFixed(1).replaceAll('.', ',')}',
      ]),
      onTap: () => Nav.openTmdb(context, t),
      onLongPress: () => toggleSavedTitle(context, t),
    );
  }
}

void toggleSavedTitle(BuildContext context, TmdbTitle t) {
  final user = AppScope.of(context).user;
  user.toggleSaved(
    SavedTitle(key: t.key, title: t.title, poster: t.poster, year: t.year),
  );
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          user.isFavorite(t.key)
              ? '${t.title} aggiunto alla tua lista'
              : '${t.title} tolto dalla tua lista',
        ),
      ),
    );
}

/// Riga di titoli TMDB caricata in modo asincrono; sparisce se vuota o in
/// errore (le altre righe restano). L'ultima scheda apre l'elenco completo.
class TmdbRow extends StatefulWidget {
  const TmdbRow({
    super.key,
    required this.title,
    required this.load,
    this.onSeeAll,
  });

  final String title;
  final Future<List<TmdbTitle>> Function() load;
  final VoidCallback? onSeeAll;

  @override
  State<TmdbRow> createState() => _TmdbRowState();
}

class _TmdbRowState extends State<TmdbRow> {
  late Future<List<TmdbTitle>> _future = widget.load();

  @override
  void didUpdateWidget(TmdbRow old) {
    super.didUpdateWidget(old);
    if (old.key != widget.key) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final pw = layout.posterWidth;
    final h = pw * 1.5 + PosterCard.textHeight;
    return FutureBuilder<List<TmdbTitle>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Skeleton(title: widget.title, width: pw, height: h);
        }
        final items = snap.data ?? const <TmdbTitle>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final more = widget.onSeeAll != null;
        return ContentRow(
          title: widget.title,
          itemCount: items.length + (more ? 1 : 0),
          itemWidth: pw,
          itemHeight: h,
          itemBuilder: (context, i) {
            if (i == items.length) return _SeeAll(onTap: widget.onSeeAll!);
            return TmdbPoster(items[i]);
          },
        );
      },
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: FocusCard(
                radius: VistaRadius.poster,
                focusScale: 1.06,
                onTap: onTap,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 30),
                      SizedBox(height: 8),
                      Text(
                        'Vedi tutto',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: PosterCard.textHeight),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.title,
    required this.width,
    required this.height,
  });
  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = VistaLayout.of(context).gutter;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(g, 0, g, 10),
            child: SectionTitle(title),
          ),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: g),
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, _) => SizedBox(
                width: width,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: VistaColors.glass,
                          borderRadius: BorderRadius.circular(
                            VistaRadius.poster,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unisce film e serie in un'unica lista, alternandoli per popolarità.
List<TmdbTitle> mergeByPopularity(List<TmdbTitle> a, List<TmdbTitle> b) =>
    ([...a, ...b]..sort((x, y) => y.popularity.compareTo(x.popularity)));
