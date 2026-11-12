import 'models.dart';

/// Modifiche dell'utente a un canale: nome, logo, numero e categoria.
class ChannelOverride {
  const ChannelOverride({
    this.name = '',
    this.logo = '',
    this.number,
    this.group = '',
  });

  factory ChannelOverride.fromJson(Map<String, dynamic> j) => ChannelOverride(
        name: j['name'] as String? ?? '',
        logo: j['logo'] as String? ?? '',
        number: j['number'] as int?,
        group: j['group'] as String? ?? '',
      );

  final String name;
  final String logo;

  /// Numero scelto dall'utente; `null` = quello della lista.
  final int? number;

  /// Categoria in cui l'utente ha spostato il canale; vuota = quella della
  /// lista. Una categoria nuova nasce spostandoci un canale.
  final String group;

  bool get isEmpty =>
      name.isEmpty && logo.isEmpty && number == null && group.isEmpty;

  ChannelOverride copyWith({
    String? name,
    String? logo,
    int? number,
    bool clearNumber = false,
    String? group,
  }) =>
      ChannelOverride(
        name: name ?? this.name,
        logo: logo ?? this.logo,
        number: clearNumber ? null : (number ?? this.number),
        group: group ?? this.group,
      );

  Map<String, Object> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (logo.isNotEmpty) 'logo': logo,
        if (number != null) 'number': number!,
        if (group.isNotEmpty) 'group': group,
      };
}

/// Preferenze sui canali, legate alla chiave normalizzata ([Channel.key]) e
/// quindi valide anche se la lista cambia o si ricarica.
///
/// - [merges]: unioni manuali, chiave → chiave del canale di destinazione
///   (passate a `resolveChannels`);
/// - [overrides]: nome, logo, numero e categoria scelti dall'utente;
/// - [hidden]: canali nascosti;
/// - [groupNames]: categorie della lista rinominate (originale → nuovo nome);
/// - [hiddenGroups]: categorie nascoste (per nome mostrato): vale anche per i
///   canali che la lista ci aggiungerà;
/// - [groupOrder]: ordine delle categorie scelto dall'utente.
class ChannelPrefs {
  const ChannelPrefs({
    this.merges = const {},
    this.overrides = const {},
    this.hidden = const {},
    this.groupNames = const {},
    this.hiddenGroups = const {},
    this.groupOrder = const [],
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
        groupNames: Map<String, String>.from(j['groupNames'] as Map? ?? const {}),
        hiddenGroups: {
          for (final g in j['hiddenGroups'] as List? ?? const []) g as String,
        },
        groupOrder: [
          for (final g in j['groupOrder'] as List? ?? const []) g as String,
        ],
      );

  final Map<String, String> merges;
  final Map<String, ChannelOverride> overrides;
  final Set<String> hidden;
  final Map<String, String> groupNames;
  final Set<String> hiddenGroups;
  final List<String> groupOrder;

  Map<String, dynamic> toJson() => {
        'merges': merges,
        'overrides': {
          for (final MapEntry(:key, :value) in overrides.entries)
            if (!value.isEmpty) key: value.toJson(),
        },
        'hidden': (hidden.toList()..sort()),
        if (groupNames.isNotEmpty) 'groupNames': groupNames,
        if (hiddenGroups.isNotEmpty)
          'hiddenGroups': (hiddenGroups.toList()..sort()),
        if (groupOrder.isNotEmpty) 'groupOrder': groupOrder,
      };

  ChannelPrefs _copy({
    Map<String, String>? merges,
    Map<String, ChannelOverride>? overrides,
    Set<String>? hidden,
    Map<String, String>? groupNames,
    Set<String>? hiddenGroups,
    List<String>? groupOrder,
  }) =>
      ChannelPrefs(
        merges: merges ?? this.merges,
        overrides: overrides ?? this.overrides,
        hidden: hidden ?? this.hidden,
        groupNames: groupNames ?? this.groupNames,
        hiddenGroups: hiddenGroups ?? this.hiddenGroups,
        groupOrder: groupOrder ?? this.groupOrder,
      );

  // --- canali ---------------------------------------------------------------

  ChannelPrefs setHidden(String key, bool hide) =>
      _copy(hidden: hide ? {...hidden, key} : ({...hidden}..remove(key)));

  /// Nasconde o mostra più canali insieme.
  ChannelPrefs setHiddenAll(Iterable<String> keys, bool hide) => _copy(
        hidden: hide ? {...hidden, ...keys} : hidden.difference(keys.toSet()),
      );

  ChannelPrefs rename(String key, String name) =>
      _override(key, (o) => o.copyWith(name: name.trim()));

  ChannelPrefs setLogo(String key, String logo) =>
      _override(key, (o) => o.copyWith(logo: logo.trim()));

  /// Numero del canale; `null` torna a quello della lista. I canali si
  /// ordinano per numero.
  ChannelPrefs setNumber(String key, int? number) => _override(
        key,
        (o) => number == null
            ? o.copyWith(clearNumber: true)
            : o.copyWith(number: number),
      );

  /// Sposta il canale in un'altra categoria (anche nuova); vuota = torna in
  /// quella della lista.
  ChannelPrefs moveToGroup(String key, String group) =>
      _override(key, (o) => o.copyWith(group: group.trim()));

  /// Unisce il canale [from] a [into]. Le modifiche di [from] spariscono:
  /// conta il canale di destinazione.
  ChannelPrefs merge(String from, String into) {
    if (from == into) return this;
    return _copy(
      merges: {...merges, from: into},
      overrides: {...overrides}..remove(from),
      hidden: {...hidden}..remove(from),
    );
  }

  /// Annulla un'unione manuale.
  ChannelPrefs split(String from) => _copy(merges: {...merges}..remove(from));

  /// Chiavi unite a mano dentro [key].
  List<String> mergedInto(String key) =>
      [for (final MapEntry(key: k, value: v) in merges.entries) if (v == key) k];

  ChannelPrefs _override(
    String key,
    ChannelOverride Function(ChannelOverride) change,
  ) {
    final next = change(overrides[key] ?? const ChannelOverride());
    return _copy(
      overrides: next.isEmpty
          ? ({...overrides}..remove(key))
          : ({...overrides}..[key] = next),
    );
  }

  // --- categorie ------------------------------------------------------------

  /// Nome mostrato della categoria [listGroup] della lista.
  String groupName(String listGroup) => groupNames[listGroup] ?? listGroup;

  /// Rinomina la categoria mostrata [from] in [to]. Se [to] esiste già, le
  /// due categorie diventano una sola.
  ChannelPrefs renameGroup(String from, String to) {
    final name = to.trim();
    if (name.isEmpty || name == from) return this;
    final names = {
      for (final MapEntry(:key, :value) in groupNames.entries)
        key: value == from ? name : value,
    };
    // [from] è una categoria della lista mai rinominata (o una creata
    // spostandoci canali): la si rinomina direttamente.
    if (!groupNames.containsKey(from) && !groupNames.containsValue(from)) {
      names[from] = name;
    }
    names.removeWhere((k, v) => k == v);
    String swap(String g) => g == from ? name : g;
    final order = <String>[];
    for (final g in groupOrder.map(swap)) {
      if (!order.contains(g)) order.add(g);
    }
    return _copy(
      groupNames: names,
      overrides: {
        for (final MapEntry(:key, :value) in overrides.entries)
          key: value.group == from ? value.copyWith(group: name) : value,
      },
      hiddenGroups: hiddenGroups.map(swap).toSet(),
      groupOrder: order,
    );
  }

  ChannelPrefs setGroupHidden(String group, bool hide) => _copy(
        hiddenGroups:
            hide ? {...hiddenGroups, group} : ({...hiddenGroups}..remove(group)),
      );

  /// Sposta [group] di [delta] posti nell'ordine [current] (le categorie
  /// come sono mostrate ora) e lo ricorda.
  ChannelPrefs moveGroup(List<String> current, String group, int delta) {
    final list = [...current];
    final i = list.indexOf(group);
    if (i < 0) return this;
    final j = (i + delta).clamp(0, list.length - 1);
    if (i == j) return this;
    list
      ..removeAt(i)
      ..insert(j, group);
    return _copy(groupOrder: list);
  }

  /// Le categorie [groups] (in ordine di lista) nell'ordine dell'utente:
  /// prima quelle che ha ordinato, poi le altre come vengono.
  List<String> orderGroups(Iterable<String> groups) {
    final rank = {for (var i = 0; i < groupOrder.length; i++) groupOrder[i]: i};
    final list = groups.toList();
    final indexed = [for (var i = 0; i < list.length; i++) (list[i], i)];
    indexed.sort((a, b) {
      final ra = rank[a.$1] ?? groupOrder.length;
      final rb = rank[b.$1] ?? groupOrder.length;
      return ra != rb ? ra.compareTo(rb) : a.$2.compareTo(b.$2);
    });
    return [for (final (g, _) in indexed) g];
  }

  // --- applicazione ---------------------------------------------------------

  /// Applica nomi, loghi, numeri, categorie e visibilità ai canali risolti. I
  /// nascosti restano nell'elenco con [Channel.hidden]: l'interfaccia li
  /// filtra. Con numeri personalizzati i canali si riordinano per numero (a
  /// parità vince quello scelto dall'utente).
  List<Channel> apply(List<Channel> channels) {
    final out = <Channel>[];
    var renumbered = false;
    for (final c in channels) {
      final o = overrides[c.key];
      final group =
          (o != null && o.group.isNotEmpty) ? o.group : groupName(c.group);
      final groupHidden = hiddenGroups.contains(group);
      final hide = hidden.contains(c.key) || groupHidden;
      if (o == null && group == c.group && !hide) {
        out.add(c);
        continue;
      }
      if (o?.number != null) renumbered = true;
      out.add(c.copyWith(
        name: (o == null || o.name.isEmpty) ? null : o.name,
        renamed: o != null && o.name.isNotEmpty,
        customLogo: o?.logo ?? '',
        number: o?.number,
        renumbered: o?.number != null,
        group: group,
        hidden: hide,
        groupHidden: groupHidden,
      ));
    }
    if (!renumbered) return out;
    final indexed = [for (var i = 0; i < out.length; i++) (out[i], i)];
    indexed.sort((a, b) {
      final n = a.$1.number.compareTo(b.$1.number);
      if (n != 0) return n;
      if (a.$1.renumbered != b.$1.renumbered) return a.$1.renumbered ? -1 : 1;
      return a.$2.compareTo(b.$2);
    });
    return [for (final (c, _) in indexed) c];
  }
}
