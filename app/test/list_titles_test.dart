import 'package:flutter_test/flutter_test.dart';
import 'package:vista/widgets/list_titles.dart';
import 'package:vista_resolver/vista_resolver.dart';

void main() {
  test('i titoli della lista si leggono puliti', () {
    expect(cleanListTitle('IT - Gajab Raat (2026) [1080p]'), 'Gajab Raat');
    expect(cleanListTitle('|IT| Il Gladiatore II 4K'), 'Il Gladiatore II');
    expect(cleanListTitle('[ITA] Dune: Parte Due - HD'), 'Dune: Parte Due');
    expect(cleanListTitle('Matrix'), 'Matrix');
    expect(cleanListTitle('Up'), 'Up');
    expect(cleanListTitle('[4K]'), '[4K]');
  });

  test("l'anno si prende dal titolo se manca", () {
    expect(yearInTitle('Gajab Raat (2026) [1080p]'), 2026);
    expect(yearInTitle('Blade Runner 2049'), isNull);
  });

  test('le categorie diventano titoli di riga', () {
    expect(
      cleanGroupName('IT: PELLICOLA 2025/2026 [1080p]'),
      'Pellicola 2025/2026',
    );
    expect(cleanGroupName('Azione'), 'Azione');
    expect(cleanGroupName('IT: ITALY [4K-Q]/[4K-Q]'), 'Italy');
  });

  test('il titolo TMDB solo se si legge nella stessa scrittura', () {
    TmdbTitle t(String title) =>
        TmdbTitle(type: MediaType.movie, id: 1, title: title);
    expect(listTitle('IT - Gajab Raat (2026)', t('ग़ज़ब रात')), 'Gajab Raat');
    expect(
      listTitle('IT - Hellfire (2026) [1080p]', t('Hellfire')),
      'Hellfire',
    );
    expect(listTitle('IT - Il Gladiatore', null), 'Il Gladiatore');
  });
}
