// Модели данных «Родквест». Все модели сериализуются в JSON,
// чтобы позже без переделок перейти на серверную синхронизацию.

import 'life.dart';

export 'life.dart';

enum GoalTier { legend, epic, quest, task, daily }

extension GoalTierInfo on GoalTier {
  String get label => switch (this) {
        GoalTier.legend => 'Легенда',
        GoalTier.epic => 'Эпик',
        GoalTier.quest => 'Квест',
        GoalTier.task => 'Задание',
        GoalTier.daily => 'Рутина',
      };

  String get emoji => switch (this) {
        GoalTier.legend => '👑',
        GoalTier.epic => '🏰',
        GoalTier.quest => '⚔️',
        GoalTier.task => '📜',
        GoalTier.daily => '🔁',
      };

  String get hint => switch (this) {
        GoalTier.legend => 'Главная мечта: «Купить дом»',
        GoalTier.epic => 'Большой этап: «Накопить взнос»',
        GoalTier.quest => 'Конкретная задача: «Открыть вклад»',
        GoalTier.task => 'Один шаг: «Сравнить 3 банка»',
        GoalTier.daily => 'По расписанию: «Зарядка», «Уборка по субботам»',
      };

  /// Базовый опыт за выполнение.
  int get xp => switch (this) {
        GoalTier.legend => 300,
        GoalTier.epic => 100,
        GoalTier.quest => 30,
        GoalTier.task => 10,
        GoalTier.daily => 5,
      };

  /// Монеты за выполнение — их можно потратить в лавке наград.
  int get coins => switch (this) {
        GoalTier.legend => 150,
        GoalTier.epic => 50,
        GoalTier.quest => 15,
        GoalTier.task => 5,
        GoalTier.daily => 2,
      };

  /// Чем меньше число, тем «главнее» цель.
  int get rank => index;

  /// Ранги, внутрь которых можно вложить цель этого ранга.
  List<GoalTier> get allowedParents => switch (this) {
        GoalTier.legend => const [],
        GoalTier.epic => const [GoalTier.legend],
        GoalTier.quest => const [GoalTier.legend, GoalTier.epic],
        GoalTier.task => const [GoalTier.legend, GoalTier.epic, GoalTier.quest],
        GoalTier.daily => const [
            GoalTier.legend,
            GoalTier.epic,
            GoalTier.quest,
          ],
      };
}

enum HeroStat { strength, intellect, charisma, mastery }

extension HeroStatInfo on HeroStat {
  String get label => switch (this) {
        HeroStat.strength => 'Сила',
        HeroStat.intellect => 'Интеллект',
        HeroStat.charisma => 'Харизма',
        HeroStat.mastery => 'Мастерство',
      };

  String get emoji => switch (this) {
        HeroStat.strength => '💪',
        HeroStat.intellect => '🧠',
        HeroStat.charisma => '💬',
        HeroStat.mastery => '🛠',
      };

  String get hint => switch (this) {
        HeroStat.strength => 'спорт и здоровье',
        HeroStat.intellect => 'учёба и работа',
        HeroStat.charisma => 'общение и семья',
        HeroStat.mastery => 'дом и хобби',
      };
}

/// Как часто повторяется рутина.
enum Repeat { daily, weekly, monthly }

extension RepeatInfo on Repeat {
  String get label => switch (this) {
        Repeat.daily => 'Каждый день',
        Repeat.weekly => 'Каждую неделю',
        Repeat.monthly => 'Каждый месяц',
      };

  String get emoji => switch (this) {
        Repeat.daily => '🔁',
        Repeat.weekly => '📆',
        Repeat.monthly => '🗓',
      };

  /// Единица серии: «🔥 3 нед.».
  String get unit => switch (this) {
        Repeat.daily => 'дн.',
        Repeat.weekly => 'нед.',
        Repeat.monthly => 'мес.',
      };

  /// Базовый опыт за выполнение и прибавка за каждый период серии.
  int get baseXp => switch (this) {
        Repeat.daily => 5,
        Repeat.weekly => 20,
        Repeat.monthly => 50,
      };

  int get streakBonus => switch (this) {
        Repeat.daily => 1,
        Repeat.weekly => 2,
        Repeat.monthly => 5,
      };

  int get coins => switch (this) {
        Repeat.daily => 2,
        Repeat.weekly => 8,
        Repeat.monthly => 25,
      };
}

/// Черты характера — прокачиваются регулярными делами.
enum HeroTrait { punctuality, habit, endurance }

extension HeroTraitInfo on HeroTrait {
  String get label => switch (this) {
        HeroTrait.punctuality => 'Пунктуальность',
        HeroTrait.habit => 'Привычка',
        HeroTrait.endurance => 'Выдержка',
      };

  String get emoji => switch (this) {
        HeroTrait.punctuality => '⏰',
        HeroTrait.habit => '🔁',
        HeroTrait.endurance => '🧘',
      };

  String get hint => switch (this) {
        HeroTrait.punctuality => 'дела в запланированный день',
        HeroTrait.habit => 'каждое регулярное дело',
        HeroTrait.endurance => 'длинные серии без пропусков',
      };
}

enum HeroRole { leader, member, child }

extension HeroRoleInfo on HeroRole {
  String get label => switch (this) {
        HeroRole.leader => 'Глава гильдии',
        HeroRole.member => 'Герой',
        HeroRole.child => 'Юнга',
      };

  /// Может подтверждать задания юнг и управлять гильдией.
  bool get canApprove => this == HeroRole.leader;

  /// Взрослый: видит бюджет, создаёт награды.
  bool get isAdult => this != HeroRole.child;
}

/// Тема оформления. «Авто» — игровая для юнг, строгая для взрослых.
enum AppSkin { auto, fairy, lagoon, graphite, midnight, forest, bordeaux, espresso }

extension AppSkinInfo on AppSkin {
  String get label => switch (this) {
        AppSkin.auto => 'Авто',
        AppSkin.fairy => 'Сказка',
        AppSkin.lagoon => 'Лагуна',
        AppSkin.graphite => 'Графит',
        AppSkin.midnight => 'Полночь',
        AppSkin.forest => 'Хвоя',
        AppSkin.bordeaux => 'Бордо',
        AppSkin.espresso => 'Эспрессо',
      };

  String get emoji => switch (this) {
        AppSkin.auto => '✨',
        AppSkin.fairy => '🦄',
        AppSkin.lagoon => '🐬',
        AppSkin.graphite => '🖋',
        AppSkin.midnight => '🌙',
        AppSkin.forest => '🌲',
        AppSkin.bordeaux => '🍷',
        AppSkin.espresso => '☕',
      };

  String get hint => switch (this) {
        AppSkin.auto => 'Игровая для юнг, строгая для взрослых',
        AppSkin.fairy => 'Яркая игровая, фиолетовая',
        AppSkin.lagoon => 'Яркая игровая, бирюзовая',
        AppSkin.graphite => 'Строгая светлая',
        AppSkin.midnight => 'Строгая тёмная',
        AppSkin.forest => 'Строгая светлая, глубокий зелёный',
        AppSkin.bordeaux => 'Деловая светлая, винный акцент',
        AppSkin.espresso => 'Тёмная тёплая, для вечера',
      };

  /// Строгая тема для взрослых (не игровая).
  bool get adult => switch (this) {
        AppSkin.auto || AppSkin.fairy || AppSkin.lagoon => false,
        _ => true,
      };

  /// Конкретная тема для героя с учётом режима «Авто».
  AppSkin resolve(HeroRole role) {
    if (this != AppSkin.auto) return this;
    return role == HeroRole.child ? AppSkin.fairy : AppSkin.graphite;
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Профиль героя (члена семьи). Не путать с виджетом Flutter `Hero`.
class HeroProfile {
  HeroProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.role,
    this.xp = 0,
    this.coins = 0,
    this.skin = AppSkin.auto,
    Map<HeroStat, int>? statXp,
    Map<String, int>? badges,
    Map<HeroTrait, int>? traitXp,
  })  : statXp = statXp ?? {for (final s in HeroStat.values) s: 0},
        traitXp = traitXp ?? {for (final t in HeroTrait.values) t: 0},
        badges = badges ?? {};

  final String id;
  String name;
  String avatar;
  HeroRole role;
  int xp;
  int coins;
  AppSkin skin;
  final Map<HeroStat, int> statXp;

  /// Полученные достижения: id → ступень (1 — бронза, 2 — серебро, 3 — золото).
  /// Однажды полученная ступень не теряется.
  final Map<String, int> badges;

  /// Опыт черт характера (пунктуальность, привычка, выдержка).
  final Map<HeroTrait, int> traitXp;

  AppSkin get resolvedSkin => skin.resolve(role);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'role': role.name,
        'xp': xp,
        'coins': coins,
        'skin': skin.name,
        'statXp': {for (final e in statXp.entries) e.key.name: e.value},
        'badges': badges,
        'traitXp': {for (final e in traitXp.entries) e.key.name: e.value},
      };

  factory HeroProfile.fromJson(Map<String, dynamic> j) {
    final rawStats = (j['statXp'] as Map?) ?? const {};
    final rawBadges = (j['badges'] as Map?) ?? const {};
    final rawTraits = (j['traitXp'] as Map?) ?? const {};
    return HeroProfile(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Герой',
      avatar: j['avatar'] as String? ?? '🧙',
      role: _enumByName(HeroRole.values, j['role'], HeroRole.member),
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      coins: (j['coins'] as num?)?.toInt() ?? 0,
      skin: _enumByName(AppSkin.values, j['skin'], AppSkin.auto),
      statXp: {
        for (final s in HeroStat.values)
          s: (rawStats[s.name] as num?)?.toInt() ?? 0,
      },
      traitXp: {
        for (final t in HeroTrait.values) t: (rawTraits[t.name] as num?)?.toInt() ?? 0,
      },
      badges: {
        for (final e in rawBadges.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      },
    );
  }
}

class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.tier,
    required this.ownerId,
    required this.createdAt,
    this.description = '',
    this.parentId,
    this.isFamily = false,
    this.stat = HeroStat.mastery,
    this.done = false,
    this.pendingApproval = false,
    this.completedAt,
    this.completedById,
    this.lastDoneDay,
    this.streak = 0,
    int? bestStreak,
    this.dueDate,
    this.repeat = Repeat.daily,
    List<int>? weekdays,
    this.monthDay,
    this.isPrivate = false,
    this.area,
  })  : bestStreak = bestStreak ?? streak,
        weekdays = weekdays ?? [];

  final String id;
  String title;
  String description;
  GoalTier tier;
  String? parentId;
  String ownerId;
  bool isFamily;
  HeroStat stat;
  final DateTime createdAt;

  // Для обычных целей.
  bool done;
  bool pendingApproval;
  DateTime? completedAt;
  String? completedById;

  // Для рутины: начало периода (день / понедельник недели / 1-е число месяца)
  // последнего выполнения в формате yyyy-mm-dd и серия периодов подряд.
  String? lastDoneDay;
  int streak;

  /// Рекорд серии — не сгорает при пропуске (для достижений).
  int bestStreak;

  /// Срок (только дата, без времени). У рутины не используется.
  DateTime? dueDate;

  // ---------- Расписание рутины ----------

  /// Как часто повторяется.
  Repeat repeat;

  /// Для ежедневной — дни недели (1 = пн … 7 = вс), пусто — каждый день.
  /// Для еженедельной — один день «по плану» (пусто — любой день недели).
  List<int> weekdays;

  /// Для ежемесячной — число «по плану» (null — любой день месяца).
  /// Если в месяце меньше дней — последний день месяца.
  int? monthDay;

  /// Личная цель: видна только владельцу.
  bool isPrivate;

  /// v5: раздел жизни (здоровье, финансы, карьера…). null — без раздела.
  LifeArea? area;

  bool get isDaily => tier == GoalTier.daily;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'tier': tier.name,
        'parentId': parentId,
        'ownerId': ownerId,
        'isFamily': isFamily,
        'stat': stat.name,
        'createdAt': createdAt.toIso8601String(),
        'done': done,
        'pendingApproval': pendingApproval,
        'completedAt': completedAt?.toIso8601String(),
        'completedById': completedById,
        'lastDoneDay': lastDoneDay,
        'streak': streak,
        'bestStreak': bestStreak,
        'dueDate': dueDate?.toIso8601String(),
        'repeat': repeat.name,
        'weekdays': weekdays,
        'monthDay': monthDay,
        'isPrivate': isPrivate,
        'area': area?.name,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        tier: _enumByName(GoalTier.values, j['tier'], GoalTier.task),
        parentId: j['parentId'] as String?,
        ownerId: j['ownerId'] as String? ?? '',
        isFamily: j['isFamily'] as bool? ?? false,
        stat: _enumByName(HeroStat.values, j['stat'], HeroStat.mastery),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        done: j['done'] as bool? ?? false,
        pendingApproval: j['pendingApproval'] as bool? ?? false,
        completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
        completedById: j['completedById'] as String?,
        lastDoneDay: j['lastDoneDay'] as String?,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        bestStreak: (j['bestStreak'] as num?)?.toInt(),
        dueDate: DateTime.tryParse(j['dueDate'] as String? ?? ''),
        repeat: _enumByName(Repeat.values, j['repeat'], Repeat.daily),
        weekdays: [
          for (final d in (j['weekdays'] as List?) ?? const [])
            if (d is num && d >= 1 && d <= 7) d.toInt(),
        ],
        monthDay: (j['monthDay'] as num?)?.toInt(),
        isPrivate: j['isPrivate'] as bool? ?? false,
        area: LifeAreaInfo.fromName(j['area']),
      );
}

// ---------- Лут: награды за монеты ----------

class Reward {
  Reward({
    required this.id,
    required this.title,
    required this.emoji,
    required this.cost,
    this.archived = false,
  });

  final String id;
  String title;
  String emoji;
  int cost;
  bool archived;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'cost': cost,
        'archived': archived,
      };

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🎁',
        cost: (j['cost'] as num?)?.toInt() ?? 0,
        archived: j['archived'] as bool? ?? false,
      );
}

enum ClaimStatus { pending, granted, rejected }

/// Покупка награды героем. Монеты списываются сразу; при отказе — возвращаются.
class RewardClaim {
  RewardClaim({
    required this.id,
    required this.rewardId,
    required this.heroId,
    required this.title,
    required this.emoji,
    required this.cost,
    required this.at,
    this.status = ClaimStatus.pending,
  });

  final String id;
  final String rewardId;
  final String heroId;
  // Копия названия — чтобы история не ломалась, если награду изменят.
  final String title;
  final String emoji;
  final int cost;
  final DateTime at;
  ClaimStatus status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'rewardId': rewardId,
        'heroId': heroId,
        'title': title,
        'emoji': emoji,
        'cost': cost,
        'at': at.toIso8601String(),
        'status': status.name,
      };

  factory RewardClaim.fromJson(Map<String, dynamic> j) => RewardClaim(
        id: j['id'] as String,
        rewardId: j['rewardId'] as String? ?? '',
        heroId: j['heroId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🎁',
        cost: (j['cost'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        status: _enumByName(ClaimStatus.values, j['status'], ClaimStatus.pending),
      );
}

// ---------- Семейный бюджет (только для взрослых) ----------

enum MoneyKind { expense, income, saving }

extension MoneyKindInfo on MoneyKind {
  String get label => switch (this) {
        MoneyKind.expense => 'Расход',
        MoneyKind.income => 'Доход',
        MoneyKind.saving => 'В копилку',
      };
}

class BudgetCategory {
  BudgetCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.kind,
    this.limit,
  });

  final String id;
  String name;
  String emoji;
  final MoneyKind kind;

  /// Месячный лимит в рублях (только для расходов).
  int? limit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'kind': kind.name,
        'limit': limit,
      };

  factory BudgetCategory.fromJson(Map<String, dynamic> j) => BudgetCategory(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '📦',
        kind: _enumByName(MoneyKind.values, j['kind'], MoneyKind.expense),
        limit: (j['limit'] as num?)?.toInt(),
      );
}

/// Операция: доход, расход или пополнение копилки. Суммы — в рублях.
class MoneyEntry {
  MoneyEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.heroId,
    this.categoryId,
    this.potId,
    this.note = '',
  });

  final String id;
  MoneyKind kind;
  int amount;
  DateTime date;
  final String heroId;
  String? categoryId;
  String? potId;
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'date': date.toIso8601String(),
        'heroId': heroId,
        'categoryId': categoryId,
        'potId': potId,
        'note': note,
      };

  factory MoneyEntry.fromJson(Map<String, dynamic> j) => MoneyEntry(
        id: j['id'] as String,
        kind: _enumByName(MoneyKind.values, j['kind'], MoneyKind.expense),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        heroId: j['heroId'] as String? ?? '',
        categoryId: j['categoryId'] as String?,
        potId: j['potId'] as String?,
        note: j['note'] as String? ?? '',
      );
}

/// Копилка — накопление на что-то, можно связать с целью («Отпуск на море»).
class SavingsPot {
  SavingsPot({
    required this.id,
    required this.name,
    required this.emoji,
    required this.target,
    this.goalId,
  });

  final String id;
  String name;
  String emoji;
  int target;
  String? goalId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'target': target,
        'goalId': goalId,
      };

  factory SavingsPot.fromJson(Map<String, dynamic> j) => SavingsPot(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🐷',
        target: (j['target'] as num?)?.toInt() ?? 0,
        goalId: j['goalId'] as String?,
      );
}

// ---------- Журнал опыта (для статистики и достижений) ----------

/// За что начислен опыт: цель/рутина, таймер, замер навыка, подъём по будильнику.
enum XpKind { goal, focus, skill, wake }

/// Одна запись «герой получил опыт за цель». Хранится компактно:
/// по ней строятся графики и считаются достижения вроде «Ранней пташки».
class XpRecord {
  XpRecord({
    required this.heroId,
    required this.goalId,
    required this.tier,
    required this.stat,
    required this.xp,
    required this.coins,
    required this.at,
    this.family = false,
    this.onTime = false,
    Map<HeroTrait, int>? traits,
    this.kind = XpKind.goal,
    this.area,
  }) : traits = traits ?? const {};

  final String heroId;
  final String goalId;
  final GoalTier tier;
  final HeroStat stat;
  final int xp;
  final int coins;
  final DateTime at;

  /// Шаг семейной цели — для достижения «Командный игрок».
  final bool family;

  /// Рутина выполнена в запланированный день (для пунктуальности).
  final bool onTime;

  /// Сколько опыта черт характера дала запись (чтобы вернуть при отмене).
  final Map<HeroTrait, int> traits;

  /// v5: источник опыта. Для таймера и навыка [goalId] — id сессии или замера.
  final XpKind kind;

  /// v5: раздел жизни.
  final LifeArea? area;

  bool get isGoal => kind == XpKind.goal;

  Map<String, dynamic> toJson() => {
        'h': heroId,
        'g': goalId,
        't': tier.name,
        's': stat.name,
        'x': xp,
        'c': coins,
        'a': at.toIso8601String(),
        if (family) 'f': true,
        if (onTime) 'o': true,
        if (traits.isNotEmpty) 'tr': {for (final e in traits.entries) e.key.name: e.value},
        if (kind != XpKind.goal) 'k': kind.name,
        if (area != null) 'ar': area!.name,
      };

  factory XpRecord.fromJson(Map<String, dynamic> j) => XpRecord(
        heroId: j['h'] as String? ?? '',
        goalId: j['g'] as String? ?? '',
        tier: _enumByName(GoalTier.values, j['t'], GoalTier.task),
        stat: _enumByName(HeroStat.values, j['s'], HeroStat.mastery),
        xp: (j['x'] as num?)?.toInt() ?? 0,
        coins: (j['c'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['a'] as String? ?? '') ?? DateTime.now(),
        family: j['f'] as bool? ?? false,
        onTime: j['o'] as bool? ?? false,
        traits: {
          for (final t in HeroTrait.values)
            if ((j['tr'] as Map?)?[t.name] case final num v) t: v.toInt(),
        },
        kind: _enumByName(XpKind.values, j['k'], XpKind.goal),
        area: LifeAreaInfo.fromName(j['ar']),
      );
}

class FeedEvent {
  FeedEvent({
    required this.id,
    required this.heroId,
    required this.text,
    required this.emoji,
    required this.at,
    this.xp = 0,
  });

  final String id;
  final String heroId;
  final String text;
  final String emoji;
  final DateTime at;
  final int xp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'heroId': heroId,
        'text': text,
        'emoji': emoji,
        'at': at.toIso8601String(),
        'xp': xp,
      };

  factory FeedEvent.fromJson(Map<String, dynamic> j) => FeedEvent(
        id: j['id'] as String,
        heroId: j['heroId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '✨',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        xp: (j['xp'] as num?)?.toInt() ?? 0,
      );
}

/// Всё состояние приложения — то, что сохраняется на устройстве.
class AppState {
  AppState({
    required this.guildName,
    required this.heroes,
    required this.goals,
    required this.feed,
    required this.activeHeroId,
    List<Reward>? rewards,
    List<RewardClaim>? claims,
    List<BudgetCategory>? categories,
    List<MoneyEntry>? money,
    List<SavingsPot>? pots,
    List<XpRecord>? records,
    this.parentPinHash,
    this.parentPinSalt,
    this.solo = false,
    List<Reminder>? reminders,
    List<ActiveTimer>? timers,
    List<FocusSession>? sessions,
    List<Skill>? skills,
    List<SkillEntry>? skillEntries,
    this.remindersCheckedAt,
  })  : records = records ?? [],
        reminders = reminders ?? [],
        timers = timers ?? [],
        sessions = sessions ?? [],
        skills = skills ?? [],
        skillEntries = skillEntries ?? [],
        rewards = rewards ?? [],
        claims = claims ?? [],
        categories = categories ?? [],
        money = money ?? [],
        pots = pots ?? [];

  factory AppState.empty() => AppState(
        guildName: '',
        heroes: [],
        goals: [],
        feed: [],
        activeHeroId: null,
      );

  String guildName;
  final List<HeroProfile> heroes;
  final List<Goal> goals;
  final List<FeedEvent> feed;
  String? activeHeroId;
  final List<Reward> rewards;
  final List<RewardClaim> claims;
  final List<BudgetCategory> categories;
  final List<MoneyEntry> money;
  final List<SavingsPot> pots;

  /// v3: журнал опыта для статистики.
  final List<XpRecord> records;

  /// v3: PIN родителя (хранится только хэш с солью).
  String? parentPinHash;
  String? parentPinSalt;

  /// v4: личный режим «Только я» — без гильдии, юнг и семейных целей.
  bool solo;

  /// v5: будильники и напоминания всех героев устройства.
  final List<Reminder> reminders;

  /// v5: запущенные таймеры (не больше одного на героя).
  final List<ActiveTimer> timers;

  /// v5: история таймеров.
  final List<FocusSession> sessions;

  /// v5: навыки и их замеры (личные рекорды).
  final List<Skill> skills;
  final List<SkillEntry> skillEntries;

  /// v5: когда последний раз проверяли будильники — чтобы после перезапуска
  /// сообщить о пропущенных и не звонить дважды.
  DateTime? remindersCheckedAt;

  /// v5: разделы жизни, будильники и напоминания, таймеры, навыки и рекорды.
  /// v4: расписание рутины (неделя/месяц), черты характера, личные цели, режим «Только я».
  /// v3: журнал опыта, ступени достижений, рекорд серии, PIN родителя.
  /// v2: монеты, лут, сроки, бюджет, темы. Старые данные v1 читаются как есть —
  /// новые поля получают значения по умолчанию.
  static const schemaVersion = 5;

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'guildName': guildName,
        'activeHeroId': activeHeroId,
        'heroes': [for (final h in heroes) h.toJson()],
        'goals': [for (final g in goals) g.toJson()],
        'feed': [for (final f in feed) f.toJson()],
        'rewards': [for (final r in rewards) r.toJson()],
        'claims': [for (final c in claims) c.toJson()],
        'categories': [for (final c in categories) c.toJson()],
        'money': [for (final m in money) m.toJson()],
        'pots': [for (final p in pots) p.toJson()],
        'records': [for (final r in records) r.toJson()],
        'parentPinHash': parentPinHash,
        'parentPinSalt': parentPinSalt,
        'solo': solo,
        'reminders': [for (final r in reminders) r.toJson()],
        'timers': [for (final t in timers) t.toJson()],
        'sessions': [for (final s in sessions) s.toJson()],
        'skills': [for (final s in skills) s.toJson()],
        'skillEntries': [for (final e in skillEntries) e.toJson()],
        'remindersCheckedAt': remindersCheckedAt?.toIso8601String(),
      };

  factory AppState.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String key) => [
          for (final e in (j[key] as List?) ?? const [])
            Map<String, dynamic>.from(e as Map),
        ];
    final goals = list('goals').map(Goal.fromJson).toList();
    final records = j['records'] == null
        ? _recordsFromGoals(goals)
        : list('records').map(XpRecord.fromJson).toList();
    return AppState(
      guildName: j['guildName'] as String? ?? '',
      activeHeroId: j['activeHeroId'] as String?,
      heroes: list('heroes').map(HeroProfile.fromJson).toList(),
      goals: goals,
      feed: list('feed').map(FeedEvent.fromJson).toList(),
      rewards: list('rewards').map(Reward.fromJson).toList(),
      claims: list('claims').map(RewardClaim.fromJson).toList(),
      categories: list('categories').map(BudgetCategory.fromJson).toList(),
      money: list('money').map(MoneyEntry.fromJson).toList(),
      pots: list('pots').map(SavingsPot.fromJson).toList(),
      records: records,
      parentPinHash: j['parentPinHash'] as String?,
      parentPinSalt: j['parentPinSalt'] as String?,
      solo: j['solo'] as bool? ?? false,
      reminders: list('reminders').map(Reminder.fromJson).toList(),
      timers: list('timers').map(ActiveTimer.fromJson).toList(),
      sessions: list('sessions').map(FocusSession.fromJson).toList(),
      skills: list('skills').map(Skill.fromJson).toList(),
      skillEntries: list('skillEntries').map(SkillEntry.fromJson).toList(),
      remindersCheckedAt: DateTime.tryParse(j['remindersCheckedAt'] as String? ?? ''),
    );
  }

  /// Миграция с v1/v2: журнала ещё нет — восстанавливаем его по выполненным целям.
  /// История рутины до v3 не сохранялась, поэтому она в журнал не попадает.
  static List<XpRecord> _recordsFromGoals(List<Goal> goals) => [
        for (final g in goals)
          if (g.done && !g.isDaily && g.completedById != null && g.completedAt != null)
            XpRecord(
              heroId: g.completedById!,
              goalId: g.id,
              tier: g.tier,
              stat: g.stat,
              xp: g.tier.xp,
              coins: g.tier.coins,
              at: g.completedAt!,
              family: g.isFamily,
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));
}
