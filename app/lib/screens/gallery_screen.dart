import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/vista_cards.dart';
import '../widgets/vista_controls.dart';
import '../widgets/vista_focus.dart';
import '../widgets/vista_nav.dart';
import '../widgets/vista_row.dart';

/// Galleria dei componenti: per provarli da soli, con dati finti e senza
/// toccare liste, account o servizi.
///
/// Si apre solo così: `flutter run --dart-define=VISTA_GALLERY=true`.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

const _nav = [
  VistaNavItem('Cerca', Icons.search_rounded),
  VistaNavItem('Home', Icons.home_rounded),
  VistaNavItem('Scopri', Icons.explore_rounded),
  VistaNavItem('TV in diretta', Icons.live_tv_rounded),
  VistaNavItem('Film', Icons.movie_rounded),
  VistaNavItem('Serie TV', Icons.video_library_rounded),
];
const _settings = VistaNavItem('Impostazioni', Icons.settings_rounded);

const _titles = [
  'Maree d\'Inverno',
  'Atlante Minore',
  'Linea 9',
  'Quota 3000',
  'Faro Rosso',
  'Cenere Blu',
  'Stazione Nord',
  'Ultimo Giro',
  'Sale e Vento',
  'Le Ore Piccole',
  'Meridiano',
  'Controluce',
];

String _title(int i) =>
    '${_titles[i % _titles.length]} ${i ~/ _titles.length + 1}';

class _GalleryScreenState extends State<GalleryScreen> {
  int _section = 1;
  bool _reduce = false;
  String _category = 'Tutti';
  String _quality = 'Auto';
  final _saved = <int>{3, 7};

  void _open(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(duration: VistaMotion.toast, content: Text('Aperto: $what')),
      );
  }

  void _toggleSaved(int i) => setState(() {
    if (!_saved.remove(i)) _saved.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(disableAnimations: _reduce || mq.disableAnimations),
      child: Builder(builder: _scaffold),
    );
  }

  Widget _scaffold(BuildContext context) {
    final layout = VistaLayout.of(context);
    final page = VistaRowsPage(rows: _rows(context, layout));
    if (layout.compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: page),
        bottomNavigationBar: VistaNavBar(
          items: _nav.sublist(1),
          selected: (_section - 1).clamp(0, _nav.length - 2),
          onSelect: (i) => setState(() => _section = i + 1),
        ),
      );
    }
    return Scaffold(
      body: FocusTraversalGroup(
        policy: VistaTraversalPolicy(),
        child: Stack(
          children: [
            Positioned.fill(
              left: layout.contentLeft,
              child: SafeArea(left: false, bottom: false, child: page),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: VistaSize.railExpanded,
              child: VistaRail(
                items: _nav,
                footer: _settings,
                selected: _section,
                onSelect: (i) => setState(() => _section = i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context, VistaLayout layout) {
    final t = Theme.of(context).textTheme;
    final pw = layout.posterWidth;
    final ww = layout.wideCardWidth;
    final top = VistaSpace.s32 + layout.safe.top;
    return [
      _Section(
        key: const ValueKey('intro'),
        top: top,
        title: 'Galleria componenti',
        titleStyle: t.headlineSmall,
        child: Wrap(
          spacing: VistaSpace.s8,
          runSpacing: VistaSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VistaChip(
              label: 'Animazioni ridotte',
              icon: Icons.motion_photos_off_rounded,
              selected: _reduce,
              autofocus: true,
              onSelected: () => setState(() => _reduce = !_reduce),
            ),
            Text(
              layout.compact ? 'Formato telefono' : 'Formato wide',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
      _Section(
        key: const ValueKey('buttons'),
        title: 'Pulsanti',
        child: Wrap(
          spacing: VistaSpace.s16,
          runSpacing: VistaSpace.s16,
          children: [
            VistaButton.primary(
              label: 'Riproduci',
              icon: Icons.play_arrow_rounded,
              onPressed: () => _open('Riproduci'),
            ),
            VistaButton.tonal(
              label: 'La mia lista',
              icon: Icons.bookmark_add_rounded,
              onPressed: () => _open('La mia lista'),
            ),
            VistaButton.tonal(
              label: 'Trailer',
              onPressed: () => _open('Trailer'),
            ),
            VistaIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Altro',
              onPressed: () => _open('Altro'),
            ),
            const VistaButton.tonal(label: 'Non disponibile', onPressed: null),
          ],
        ),
      ),
      _Section(
        key: const ValueKey('chips'),
        title: 'Chip',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: VistaSpace.s8,
              runSpacing: VistaSpace.s8,
              children: [
                for (final c in const [
                  'Tutti',
                  'Preferiti',
                  'Notizie',
                  'Sport',
                  'Cinema',
                  'Ragazzi',
                ])
                  VistaChip(
                    label: c,
                    selected: c == _category,
                    onSelected: () => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: VistaSpace.s16),
            Wrap(
              spacing: VistaSpace.s8,
              runSpacing: VistaSpace.s8,
              children: [
                for (final q in const ['Auto', '4K', 'HD', 'SD'])
                  VistaChip(
                    label: q == 'Auto' ? 'Auto · 4K' : q,
                    icon: q == _quality ? Icons.check_rounded : null,
                    selected: q == _quality,
                    onSelected: () => setState(() => _quality = q),
                  ),
              ],
            ),
          ],
        ),
      ),
      VistaRow(
        key: const ValueKey('resume'),
        title: 'Continua a guardare',
        itemCount: 12,
        itemKey: (i) => ValueKey('resume-$i'),
        itemWidth: ww,
        itemHeight: VistaWideCard.heightFor(context, ww),
        itemBuilder: (context, i) => VistaWideCard(
          title: _title(i),
          meta: 'S1 · E${i + 1} · ${20 + i} min rimanenti',
          restWidth: ww,
          progress: ((i * 7) % 10 + 1) / 11,
          onTap: () => _open(_title(i)),
        ),
      ),
      VistaRow(
        key: const ValueKey('posters'),
        title: 'Poster con testo (50)',
        itemCount: 50,
        itemKey: (i) => ValueKey('poster-$i'),
        itemWidth: pw,
        itemHeight: VistaPosterCard.heightFor(context, pw, true),
        itemBuilder: (context, i) => VistaPosterCard(
          title: _title(i),
          image: '',
          restWidth: pw,
          meta: '${2000 + i % 25} · Film',
          label: i % 5 == 0 ? 'IPTV' : '',
          saved: _saved.contains(i),
          progress: i % 4 == 1 ? 0.4 : null,
          onTap: () => _open(_title(i)),
          onLongPress: () => _toggleSaved(i),
        ),
      ),
      VistaRow(
        key: const ValueKey('posters-bare'),
        title: 'Poster senza testo (Home TV)',
        itemCount: 30,
        itemKey: (i) => ValueKey('bare-$i'),
        itemWidth: pw,
        itemHeight: VistaPosterCard.heightFor(context, pw, false),
        itemBuilder: (context, i) => VistaPosterCard(
          title: _title(i + 3),
          image: '',
          restWidth: pw,
          showText: false,
          onTap: () => _open(_title(i + 3)),
        ),
      ),
      VistaRow(
        key: const ValueKey('channels'),
        title: 'Canali',
        itemCount: 20,
        itemKey: (i) => ValueKey('channel-$i'),
        itemWidth: ww,
        itemHeight: VistaWideCard.heightFor(context, ww),
        itemBuilder: (context, i) => VistaWideCard(
          title: 'Canale ${i + 1}',
          meta: 'Il giro lungo · 20:30 – 21:15',
          restWidth: ww,
          progress: 0.56,
          overlay: i.isEven ? const VistaLabel('In onda', dot: true) : null,
          center: Text('${i + 1}', style: t.headlineLarge),
          onTap: () => _open('Canale ${i + 1}'),
        ),
      ),
      VistaRowSkeleton(
        key: const ValueKey('loading'),
        title: 'In caricamento',
        itemWidth: pw,
        itemHeight: VistaPosterCard.heightFor(context, pw, true),
        aspect: VistaPosterCard.aspect,
      ),
      _Section(
        key: const ValueKey('type'),
        title: 'Tipografia',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maree d\'Inverno', style: t.displayMedium),
            Text('Il giro lungo', style: t.headlineLarge),
            Text('Titolo pagina', style: t.headlineSmall),
            Text('Titolo riga', style: t.titleLarge),
            Text('Pulsante', style: t.titleMedium),
            Text('Titolo card', style: t.titleSmall),
            Text(
              'Il guardiano di un faro ritrova le lettere che suo padre non '
              'ha mai spedito.',
              style: t.bodyLarge?.copyWith(color: VistaColors.textBody),
            ),
            Text('Etichetta', style: t.labelLarge),
            Text('2024 · Dramma · Stagione 1, episodio 4', style: t.bodySmall),
            Text('IN ONDA', style: t.labelSmall),
          ],
        ),
      ),
      const _Section(
        key: ValueKey('colors'),
        title: 'Colori',
        child: Wrap(
          spacing: VistaSpace.s16,
          runSpacing: VistaSpace.s16,
          children: [
            _Swatch('fondo', VistaColors.background),
            _Swatch('superficie', VistaColors.surface),
            _Swatch('superficie alta', VistaColors.surfaceHigh),
            _Swatch('selezionata', VistaColors.surfaceSelected),
            _Swatch('contorno', VistaColors.outline),
            _Swatch('testo', VistaColors.text),
            _Swatch('testo corpo', VistaColors.textBody),
            _Swatch('secondario', VistaColors.textSecondary),
            _Swatch('accento', VistaColors.accent),
            _Swatch('errore', VistaColors.error),
          ],
        ),
      ),
      if (!layout.compact)
        _Section(
          key: const ValueKey('navbar'),
          title: 'Barra in basso (telefono)',
          child: SizedBox(
            width: VistaSize.wideCardLarge + VistaSize.posterCompact,
            child: Theme(
              data: VistaThemeScope.compact,
              child: VistaNavBar(
                items: _nav.sublist(1),
                selected: 0,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.child,
    this.titleStyle,
    this.top = 0,
  });

  final String title;
  final TextStyle? titleStyle;
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    final layout = VistaLayout.of(context);
    final g = layout.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(g, top, g + layout.safe.right, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: titleStyle ?? Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: layout.rowReserve),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hex = color.toARGB32().toRadixString(16).substring(2).toUpperCase();
    return SizedBox(
      width: VistaSize.poster,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: VistaSpace.s64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(VistaRadius.chip),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: VistaSpace.s8),
          Text(name, style: t.labelLarge),
          Text('#$hex', style: t.bodySmall),
        ],
      ),
    );
  }
}
