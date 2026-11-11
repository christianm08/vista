import 'package:flutter/material.dart';

import '../theme.dart';

/// Riga orizzontale con titolo (stile Plex / Netflix). Il focus del
/// telecomando la fa scorrere da sola.
class ContentRow extends StatelessWidget {
  const ContentRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemWidth,
    required this.itemHeight,
    required this.itemBuilder,
    this.trailing,
    this.spacing = 14,
  });

  final String title;
  final int itemCount;
  final double itemWidth;
  final double itemHeight;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? trailing;
  final double spacing;

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
            child: SectionTitle(title, trailing: trailing),
          ),
          SizedBox(
            height: itemHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: g),
              // L'ingrandimento col focus può uscire dai bordi della riga.
              clipBehavior: Clip.none,
              itemCount: itemCount,
              separatorBuilder: (_, _) => SizedBox(width: spacing),
              itemBuilder: (itemContext, i) => Focus(
                canRequestFocus: false,
                skipTraversal: true,
                // Col telecomando la riga attiva sale per intero nello schermo
                // (il Flutter di base la mostra appena, tagliata in basso).
                onFocusChange: (has) {
                  if (has) {
                    Scrollable.ensureVisible(
                      context,
                      alignment: 0.25,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: SizedBox(
                  width: itemWidth,
                  child: itemBuilder(itemContext, i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
