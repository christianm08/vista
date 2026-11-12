import 'models.dart';

/// Modifiche dell'utente a un canale: nome e logo.
class ChannelOverride {
  const ChannelOverride({this.name = '', this.logo = ''});

  factory ChannelOverride.fromJson(Map<String, dynamic> j) => ChannelOverride(
        name: j['name'] as String? ?? '',
        logo: j['logo'] as String? ?? '',
      );

  final String name;
  final String logo;

  bool get isEmpty => name.isEmpty && logo.isEmpty;

  Map<String, String> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (logo.isNotEmpty) 'logo': logo,
      };
}

/// Preferenze sui canali, legate alla chiave normalizzata ([Channel.key]) e
/// quindi valide anche se la lista cambia o si ricarica.
///
/// - [merges]: unioni manuali, chiave → chiave del canale di destinazione
///   (passate a `resolveChannels`);
/// - [overrides]: nome e logo scelti dall'utente;
/// - [hidden]: canali nascosti.
class ChannelPrefs {
  const ChannelPrefs({
    this.merges = const {},
    this.overrides = const {},
    this.hidden = const {},
  });

  factory ChannelPrefs.fromJson(Map<String, dynamic> j) => ChannelPrefs(
        merges: Map<String, String>.from(j['merges'] as Map? ?? const {}),
        overrides: {
          for (final MapEntry(:key, :value)
              in (j['overrides'] as Map? ?? const {}).entries)
            key as String:
                ChannelOverride.fromJson(Map<String, dynamic>.from(value as Map)),
        },
        hidden: {for (final k in j['hidden'] as List? ?? const []) k as String},
      );

  final Map<String, String> merges;
  final Map<String, ChannelOverride> overrides;
  final Set<String> hidden;

  Map<String, dynamic> toJson() => {
        'merges': merges,
        'overrides': {
          for (final MapEntry(:key, :value) in overrides.entries)
            if (!value.isEmpty) key: value.toJson(),
        },
        'hidden': (hidden.toList()..sort()),
      };

  ChannelPrefs setHidden(String key, bool hide) => ChannelPrefs(
        merges: merges,
        overrides: overrides,
        hidden: hide ? {...hidden, key} : ({...hidden}..remove(key)),
      );

  /// Nasconde o mostra più canali insieme (es. un'intera categoria).
  ChannelPrefs setHiddenAll(Iterable<String> keys, bool hide) => ChannelPrefs(
        merges: merges,
        overrides: overrides,
        hidden: hide ? {...hidden, ...keys} : hidden.difference(keys.toSet()),
      );

  ChannelPrefs rename(String key, String name) {
    final o = overrides[key] ?? const ChannelOverride();
    return _withOverride(key, ChannelOverride(name: name.trim(), logo: o.logo));
  }

  ChannelPrefs setLogo(String key, String logo) {
    final o = overrides[key] ?? const ChannelOverride();
    return _withOverride(key, ChannelOverride(name: o.name, logo: logo.trim()));
  }

  /// Unisce il canale [from] a [into]. Le modifiche di [from] spariscono:
  /// conta il canale di destinazione.
  ChannelPrefs merge(String from, String into) {
    if (from == into) return this;
    return ChannelPrefs(
      merges: {...merges, from: into},
      overrides: {...overrides}..remove(from),
      hidden: {...hidden}..remove(from),
    );
  }

  /// Annulla un'unione manuale.
  ChannelPrefs split(String from) => ChannelPrefs(
      merges: {...merges}..remove(from), overrides: overrides, hidden: hidden);

  /// Chiavi unite a mano dentro [key].
  List<String> mergedInto(String key) =>
      [for (final MapEntry(key: k, value: v) in merges.entries) if (v == key) k];

  ChannelPrefs _withOverride(String key, ChannelOverride o) => ChannelPrefs(
        merges: merges,
        overrides: {...overrides}..[key] = o,
        hidden: hidden,
      );

  /// Applica nomi, loghi e visibilità ai canali già risolti. I nascosti
  /// restano nell'elenco con [Channel.hidden]: l'interfaccia li filtra.
  List<Channel> apply(List<Channel> channels) => [
        for (final c in channels)
          switch ((overrides[c.key], hidden.contains(c.key))) {
            (null, false) => c,
            (null, true) => c.copyWith(hidden: true),
            (final o?, final h) => c.copyWith(
                name: o.name.isEmpty ? null : o.name,
                renamed: o.name.isNotEmpty,
                customLogo: o.logo,
                hidden: h,
              ),
          },
      ];
}
