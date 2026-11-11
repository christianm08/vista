import 'package:flutter/material.dart';
import 'package:vista_resolver/vista_resolver.dart';

import '../app_scope.dart';
import '../data/service_launcher.dart';
import '../theme.dart';
import 'focus_card.dart';
import 'poster_card.dart';

/// Logo quadrato di un servizio di streaming.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo(this.provider, {super.key, this.size = 36});
  final WatchProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: NetImage(
          provider.logo,
          cacheWidth: (size * 3).round(),
          placeholder: ColoredBox(
            color: toneFor(provider.name),
            child: Center(
              child: Text(
                provider.name.isEmpty ? '?' : provider.name[0],
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La voce "nella tua lista IPTV" in cima a "Disponibile su:".
class IptvOffer {
  const IptvOffer({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

/// "Disponibile su:" — un titolo, tutti i servizi su cui si guarda (ognuno
/// una volta sola), più la lista IPTV se ce l'ha. Ogni voce apre l'app o il
/// sito del servizio. Dati JustWatch (attribuzione obbligatoria).
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
    final mine = AppScope.of(context).user.services.toSet();
    final offers = availability.distinct;
    // Prima i servizi dell'utente, poi gli altri nell'ordine di JustWatch.
    offers.sort((a, b) {
      final am = mine.contains(a.$1.id) ? 0 : 1;
      final bm = mine.contains(b.$1.id) ? 0 : 1;
      if (am != bm) return am - bm;
      return a.$2.index - b.$2.index;
    });
    if (offers.isEmpty && iptv == null) {
      return Text(
        'Non risulta disponibile sui servizi di streaming in Italia.',
        style: t.bodyMedium?.copyWith(color: VistaColors.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$heading:',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (iptv != null)
              _OfferChip(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [VistaColors.accent, VistaColors.peach],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.playlist_play_rounded,
                    color: VistaColors.onPrimary,
                  ),
                ),
                name: 'La tua lista IPTV',
                detail: iptv!.label,
                highlight: true,
                onTap: iptv!.onTap,
              ),
            for (final (p, kind) in offers)
              _OfferChip(
                leading: ProviderLogo(p),
                name: p.name,
                detail: mine.contains(p.id)
                    ? '${kind.label} · il tuo servizio'
                    : kind.label,
                highlight: mine.contains(p.id),
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
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              'Dati sulla disponibilità: JustWatch',
              style: t.bodySmall?.copyWith(color: VistaColors.textTertiary),
            ),
            if (availability.link.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => openLink(availability.link),
                child: const Text('Tutte le opzioni'),
              ),
            ],
          ],
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
    this.highlight = false,
  });

  final Widget leading;
  final String name;
  final String detail;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FocusCard(
      radius: 14,
      focusScale: 1.04,
      fill: highlight ? const Color(0x1FF6C59A) : VistaColors.glass,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                detail,
                style: t.bodySmall?.copyWith(
                  color: highlight
                      ? VistaColors.accent
                      : VistaColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Riga del cast con foto, nome e personaggio.
class CastRow extends StatelessWidget {
  const CastRow(this.cast, {super.key});
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final g = VistaLayout.of(context).gutter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: const SectionTitle('Cast'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: g),
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final c = cast[i];
              return SizedBox(
                width: 92,
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: NetImage(
                          c.photo,
                          cacheWidth: 200,
                          placeholder: ColoredBox(
                            color: toneFor(c.name),
                            child: const Icon(Icons.person_rounded, size: 36),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      c.character,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(
                        color: VistaColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
