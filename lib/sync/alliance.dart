/// v0.9: гильдия — союз семей, кланов и одиночных героев.
///
/// Гильдия живёт на сервере (server/rodquest_server/alliance.py) одним
/// документом. Устройство получает его целиком и показывает; изменения —
/// отдельными операциями, права проверяет сервер. Ссылка на героя —
/// `id-семьи-на-сервере|id-героя`.
library;

/// Права, которые глава гильдии выдаёт участникам.
enum AllyPerm { settings, invite, members, goals, announce }

extension AllyPermInfo on AllyPerm {
  String get label => switch (this) {
        AllyPerm.settings => 'Название и герб',
        AllyPerm.invite => 'Приглашать',
        AllyPerm.members => 'Исключать участников',
        AllyPerm.goals => 'Цели гильдии',
        AllyPerm.announce => 'Объявления',
      };

  String get emoji => switch (this) {
        AllyPerm.settings => '🏷',
        AllyPerm.invite => '🎟',
        AllyPerm.members => '🚪',
        AllyPerm.goals => '🎯',
        AllyPerm.announce => '📣',
      };

  String get hint => switch (this) {
        AllyPerm.settings => 'менять название, герб и девиз гильдии',
        AllyPerm.invite => 'создавать коды для семей, кланов и одиночек',
        AllyPerm.members => 'исключать семьи, кланы и одиночек',
        AllyPerm.goals => 'ставить, менять и удалять общие цели',
        AllyPerm.announce => 'писать объявления в ленту гильдии',
      };

  static AllyPerm? fromName(Object? name) {
    for (final p in AllyPerm.values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Кто вступил: семья, клан или одиночный герой.
enum AllyKind { family, clan, solo }

extension AllyKindInfo on AllyKind {
  String get label => switch (this) {
        AllyKind.family => 'Семья',
        AllyKind.clan => 'Клан',
        AllyKind.solo => 'Одиночка',
      };

  String get emoji => switch (this) {
        AllyKind.family => '🏡',
        AllyKind.clan => '⚔️',
        AllyKind.solo => '🧭',
      };

  static AllyKind fromName(Object? name) => switch (name) {
        'clan' => AllyKind.clan,
        'solo' => AllyKind.solo,
        _ => AllyKind.family,
      };
}

class AllyHero {
  const AllyHero({required this.id, required this.name, required this.avatar, required this.kid});

  final String id;
  final String name;
  final String avatar;
  final bool kid;
}

class AllyMember {
  const AllyMember({
    required this.space,
    required this.kind,
    required this.name,
    required this.emoji,
    required this.heroes,
    required this.joinedAt,
  });

  /// Id семьи (клана, личного пути) на сервере.
  final String space;
  final AllyKind kind;
  final String name;
  final String emoji;
  final List<AllyHero> heroes;
  final DateTime joinedAt;

  String refOf(String heroId) => '$space|$heroId';
}

class AllyGoal {
  const AllyGoal({
    required this.id,
    required this.title,
    required this.emoji,
    required this.description,
    required this.unit,
    required this.target,
    required this.deadline,
    required this.createdBy,
    required this.createdAt,
    required this.done,
    required this.doneAt,
    required this.contrib,
  });

  final String id;
  final String title;
  final String emoji;
  final String description;
  final String unit;
  final int target;
  final DateTime? deadline;
  final String createdBy;
  final DateTime createdAt;
  final bool done;
  final DateTime? doneAt;

  /// Вклад: ссылка на героя → сколько.
  final Map<String, int> contrib;

  int get total => contrib.values.fold(0, (s, v) => s + v);
  double get progress => target <= 0 ? 0 : (total / target).clamp(0, 1).toDouble();
  int get left => (target - total).clamp(0, target);

  /// Вклад участника (всей семьи / клана) — сумма вкладов его героев.
  int byMember(String space) =>
      contrib.entries.where((e) => e.key.startsWith('$space|')).fold(0, (s, e) => s + e.value);
}

class AllyFeed {
  const AllyFeed({required this.id, required this.at, required this.who, required this.name, required this.emoji, required this.text});

  final String id;
  final DateTime at;
  final String who;

  /// Имя на момент события — если участник уже ушёл из гильдии.
  final String name;
  final String emoji;
  final String text;
}

class Alliance {
  const Alliance({
    required this.id,
    required this.name,
    required this.emblem,
    required this.motto,
    required this.leader,
    required this.members,
    required this.perms,
    required this.goals,
    required this.feed,
    required this.raw,
  });

  final String id;
  final String name;
  final String emblem;
  final String motto;

  /// Ссылка на героя-главу гильдии.
  final String leader;
  final List<AllyMember> members;

  /// Ссылка на героя → его права.
  final Map<String, Set<AllyPerm>> perms;
  final List<AllyGoal> goals;
  final List<AllyFeed> feed;

  /// Документ как пришёл с сервера — хранится на устройстве для показа без сети.
  final Map<String, dynamic> raw;

  AllyMember? member(String space) {
    for (final m in members) {
      if (m.space == space) return m;
    }
    return null;
  }

  /// Герой по ссылке «семья|герой».
  (AllyMember, AllyHero)? hero(String ref) {
    final i = ref.indexOf('|');
    if (i <= 0) return null;
    final m = member(ref.substring(0, i));
    if (m == null) return null;
    final id = ref.substring(i + 1);
    for (final h in m.heroes) {
      if (h.id == id) return (m, h);
    }
    return null;
  }

  String heroName(String ref) => hero(ref)?.$2.name ?? 'Герой';

  bool isLeader(String? ref) => ref != null && ref == leader;

  bool can(String? ref, AllyPerm p) => ref != null && (ref == leader || (perms[ref]?.contains(p) ?? false));

  /// Есть ли у героя хоть одно право управления (или он глава).
  bool isOfficer(String? ref) => ref != null && (ref == leader || (perms[ref]?.isNotEmpty ?? false));

  int get heroCount => members.fold(0, (s, m) => s + m.heroes.length);

  List<AllyGoal> get activeGoals => goals.where((g) => !g.done).toList();
  List<AllyGoal> get doneGoals => goals.where((g) => g.done).toList()
    ..sort((a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt));

  /// Вклад участников во все цели гильдии — для таблицы лидеров.
  Map<String, int> get totals {
    final out = <String, int>{};
    for (final g in goals) {
      for (final e in g.contrib.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    return out;
  }

  static DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num?)?.toInt() ?? 0);
  static DateTime? _msOrNull(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static Alliance? tryParse(Object? json) {
    if (json is! Map) return null;
    try {
      return Alliance.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  factory Alliance.fromJson(Map<String, dynamic> j) {
    final members = <AllyMember>[];
    for (final e in ((j['members'] as Map?) ?? const {}).entries) {
      final m = e.value as Map;
      members.add(AllyMember(
        space: e.key.toString(),
        kind: AllyKindInfo.fromName(m['kind']),
        name: m['name'] as String? ?? '',
        emoji: m['emoji'] as String? ?? '🏡',
        joinedAt: _ms(m['joinedAt']),
        heroes: [
          for (final h in ((m['heroes'] as Map?) ?? const {}).entries)
            AllyHero(
              id: h.key.toString(),
              name: (h.value as Map)['n'] as String? ?? 'Герой',
              avatar: (h.value as Map)['a'] as String? ?? '🧙',
              kid: (h.value as Map)['k'] == true,
            ),
        ],
      ));
    }
    members.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return Alliance(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Гильдия',
      emblem: j['emblem'] as String? ?? '🏰',
      motto: j['motto'] as String? ?? '',
      leader: j['leader'] as String? ?? '',
      members: members,
      perms: {
        for (final e in ((j['perms'] as Map?) ?? const {}).entries)
          e.key.toString(): {
            for (final p in (e.value as List? ?? const []))
              if (AllyPermInfo.fromName(p) case final AllyPerm perm) perm,
          },
      },
      goals: [
        for (final g in (j['goals'] as List? ?? const []))
          AllyGoal(
            id: (g as Map)['id'] as String,
            title: g['title'] as String? ?? '',
            emoji: g['emoji'] as String? ?? '🎯',
            description: g['description'] as String? ?? '',
            unit: g['unit'] as String? ?? 'раз',
            target: (g['target'] as num?)?.toInt() ?? 1,
            deadline: _msOrNull(g['deadline']),
            createdBy: g['createdBy'] as String? ?? '',
            createdAt: _ms(g['createdAt']),
            done: g['done'] == true,
            doneAt: _msOrNull(g['doneAt']),
            contrib: {
              for (final c in ((g['contrib'] as Map?) ?? const {}).entries)
                if (c.value is num) c.key.toString(): (c.value as num).toInt(),
            },
          ),
      ],
      feed: [
        for (final f in (j['feed'] as List? ?? const []))
          AllyFeed(
            id: (f as Map)['id'] as String? ?? '',
            at: _ms(f['at']),
            who: f['who'] as String? ?? '',
            name: f['n'] as String? ?? '',
            emoji: f['e'] as String? ?? '✨',
            text: f['t'] as String? ?? '',
          ),
      ],
      raw: j,
    );
  }
}
