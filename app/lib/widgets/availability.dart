import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/service_launcher.dart';
import '../theme.dart';
import 'vista_controls.dart';
import 'vista_detail.dart';
import 'vista_focus.dart';
import 'vista_row.dart';

/// Logo quadrato di un servizio di streaming.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo(this.provider, {super.key, this.size = VistaSize.icon});
  final WatchProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        size >= VistaSize.minTouch ? VistaRadius.card : VistaRadius.chip / 2,
      ),
      child: SizedBox.square(
        dimension: size,
        child: NetImage(
          provider.logo,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          placeholder: ColoredBox(
            color: VistaColors.surfaceSelected,
            child: Center(
              child: Text(
                provider.name.isEmpty ? '?' : provider.name[0],
                style: t.labelSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La voce "nella tua lista IPTV" in cima a "Disponibile su".
class IptvOffer {
  const IptvOffer({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

/// "Disponibile su" — i servizi su cui si guarda un titolo (ognuno una volta
/// sola, prima quelli dell'utente), più la lista IPTV se ce l'ha. Ogni chip
/// apre l'app o il sito del servizio. Dati JustWatch (attribuzione
/// obbligatoria).
class AvailabilitySection extends StatelessWidget {
  const AvailabilitySection({
    super.key,
    required this.title,
    required this.availability,
    this.iptv,
    this.heading = 'Disponibile su',
  });

  final String title;
  final Availability availability;
  final IptvOffer? iptv;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colors = DetailColors.of(context);
    final mine = AppScope.of(context).user.services.toSet();
    final offers = availability.distinct;
    // Prima i servizi dell'utente, poi gli altri nell'ordine di JustWatch.
    offers.sort((a, b) {
      final am = mine.contains(a.$1.id) ? 0 : 1;
      final bm = mine.contains(b.$1.id) ? 0 : 1;
      if (am != bm) return am - bm;
      return a.$2.index - b.$2.index;
    });
    final metaStyle = t.labelLarge?.copyWith(color: colors.meta);
    if (offers.isEmpty && iptv == null) {
      return Text(
        'Non risulta disponibile sui servizi di streaming in Italia.',
        style: metaStyle,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: VistaSpace.s12,
          runSpacing: VistaSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(heading, style: metaStyle),
            if (iptv case final i?)
              _OfferChip(
                leading: Icon(
                  Icons.playlist_play_rounded,
                  size: VistaSize.iconSmall,
                  color: colors.onTonal,
                ),
                name: 'Lista IPTV',
                detail: i.label,
                mine: true,
                onTap: i.onTap,
              ),
            for (final (p, kind) in offers)
              _OfferChip(
                leading: ProviderLogo(p, size: VistaSize.iconSmall),
                name: p.name,
                // L'abbonamento è il caso normale: si scrive solo il resto
                // (noleggio, acquisto, gratis).
                detail: kind == OfferKind.flatrate ? '' : kind.label,
                mine: mine.contains(p.id),
                onTap: () async {
                  final ok = await openService(
                    p,
                    title,
                    fallback: availability.link,
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Non riesco ad aprire ${p.name} su questo dispositivo.',
                        ),
                      ),
                    );
                  }
                },
              ),
            // In coda ai servizi: una riga in meno sotto le azioni.
            if (availability.link.isNotEmpty)
              VistaChip(
                label: 'Tutte le opzioni',
                icon: Icons.open_in_new_rounded,
                selected: false,
                onSelected: () => openLink(availability.link),
              ),
          ],
        ),
        const SizedBox(height: VistaSpace.s8),
        Text(
          offers.isEmpty
              ? 'Dati sulla disponibilità: JustWatch'
              : 'Si apre nell\'app del servizio · Dati: JustWatch',
          style: t.bodySmall?.copyWith(color: colors.meta),
        ),
      ],
    );
  }
}

class _OfferChip extends StatelessWidget {
  const _OfferChip({
    required this.leading,
    required this.name,
    required this.detail,
    required this.onTap,
    required this.mine,
  });

  final Widget leading;
  final String name;
  final String detail;
  final VoidCallback onTap;

  /// Servizio dell'utente (o la sua lista): fondo con la tinta. Gli altri
  /// restano sulla superficie neutra.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final layout = VistaLayout.of(context);
    final colors = DetailColors.of(context);
    final fg = mine ? colors.onTonal : VistaColors.text;
    return VistaFocusable(
      onTap: onTap,
      kind: VistaFocusKind.flat,
      radius: VistaRadius.chip,
      fill: mine ? colors.tonal : VistaColors.surface,
      activeFill: mine ? colors.tonal : VistaColors.surfaceHigh,
      semanticLabel: detail.isEmpty ? name : '$name, $detail',
      child: SizedBox(
        height: layout.chipHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VistaSpace.s12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: VistaSpace.s8),
              Text(name, style: t.labelLarge?.copyWith(color: fg)),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: VistaSpace.s8),
                Text(
                  detail,
                  style: t.bodySmall?.copyWith(
                    color: mine ? colors.meta : VistaColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Riga del cast: foto rotonda, nome e personaggio. Più piccola delle
/// locandine: sono facce, non titoli.
class CastRow extends StatelessWidget {
  const CastRow(this.cast, {super.key});
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final w = layout.compact ? VistaSize.castPhotoCompact : VistaSize.castPhoto;
    return VistaRow(
      title: 'Cast',
      itemCount: cast.length,
      itemKey: (i) => ValueKey('cast:$i:${cast[i].name}'),
      itemWidth: w,
      itemHeight: w + layout.cardTextHeight,
      itemBuilder: (context, i) => _CastCard(cast[i], size: w),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard(this.member, {required this.size});
  final CastMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final t = Theme.of(context).textTheme;
    final name = member.name.trim();
    final initials = [
      for (final p in name.split(RegExp(r'\s+')).take(2))
        if (p.isNotEmpty) p[0].toUpperCase(),
    ].join();
    return Column(
      children: [
        SizedBox.square(
          dimension: size,
          child: VistaFocusable(
            // Solo da guardare: col telecomando ci si arriva per scorrere.
            onTap: () {},
            radius: VistaRadius.full,
            semanticLabel: member.character.isEmpty
                ? name
                : '$name, ${member.character}',
            child: ClipOval(
              child: NetImage(
                member.photo,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fallback: ColoredBox(
                  color: VistaColors.surfaceSelected,
                  child: Center(
                    child: Text(
                      initials,
                      style: t.titleMedium?.copyWith(
                        color: VistaColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: layout.cardTextHeight,
          child: Padding(
            padding: EdgeInsets.only(top: layout.cardTextGap),
            child: Column(
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.titleSmall,
                ),
                if (member.character.isNotEmpty) ...[
                  const SizedBox(height: VistaSpace.s4),
                  Text(
                    member.character,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: t.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
