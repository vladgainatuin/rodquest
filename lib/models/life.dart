// Модели версии 0.5: разделы жизни, будильники и напоминания,
// таймеры «на время» и навыки с личными рекордами.

import 'models.dart';

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

T? _byNameOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

// ---------- Разделы жизни ----------

/// Раздел (сфера жизни), к которому относится цель, навык или таймер.
/// Помогает видеть баланс: здоровье, финансы, карьера, семья…
enum LifeArea {
  health,
  sport,
  mind,
  finance,
  career,
  study,
  home,
  family,
  social,
  hobby,
  travel,
  docs,
  car,
  charity,
}

extension LifeAreaInfo on LifeArea {
  String get label => switch (this) {
        LifeArea.health => 'Здоровье',
        LifeArea.sport => 'Спорт',
        LifeArea.mind => 'Психология и отдых',
        LifeArea.finance => 'Финансы',
        LifeArea.career => 'Работа и карьера',
        LifeArea.study => 'Учёба и навыки',
        LifeArea.home => 'Дом и быт',
        LifeArea.family => 'Семья и отношения',
        LifeArea.social => 'Друзья и общение',
        LifeArea.hobby => 'Хобби и творчество',
        LifeArea.travel => 'Путешествия',
        LifeArea.docs => 'Документы и дела',
        LifeArea.car => 'Авто и транспорт',
        LifeArea.charity => 'Помощь другим',
      };

  /// Короткое название — для плашек и фильтров.
  String get short => switch (this) {
        LifeArea.health => 'Здоровье',
        LifeArea.sport => 'Спорт',
        LifeArea.mind => 'Психология',
        LifeArea.finance => 'Финансы',
        LifeArea.career => 'Карьера',
        LifeArea.study => 'Учёба',
        LifeArea.home => 'Дом',
        LifeArea.family => 'Семья',
        LifeArea.social => 'Друзья',
        LifeArea.hobby => 'Хобби',
        LifeArea.travel => 'Путешествия',
        LifeArea.docs => 'Документы',
        LifeArea.car => 'Авто',
        LifeArea.charity => 'Помощь',
      };

  String get emoji => switch (this) {
        LifeArea.health => '🩺',
        LifeArea.sport => '🏃',
        LifeArea.mind => '🧘',
        LifeArea.finance => '💰',
        LifeArea.career => '💼',
        LifeArea.study => '📚',
        LifeArea.home => '🏠',
        LifeArea.family => '👨‍👩‍👧',
        LifeArea.social => '🤝',
        LifeArea.hobby => '🎨',
        LifeArea.travel => '✈️',
        LifeArea.docs => '📑',
        LifeArea.car => '🚗',
        LifeArea.charity => '💚',
      };

  String get hint => switch (this) {
        LifeArea.health => 'врачи, анализы, сон, питание',
        LifeArea.sport => 'тренировки, шаги, форма',
        LifeArea.mind => 'стресс, отдых, медитация',
        LifeArea.finance => 'накопления, долги, налоги, инвестиции',
        LifeArea.career => 'работа, повышение, своё дело',
        LifeArea.study => 'курсы, языки, школа',
        LifeArea.home => 'уборка, ремонт, покупки',
        LifeArea.family => 'дети, пара, родители',
        LifeArea.social => 'друзья, встречи, звонки',
        LifeArea.hobby => 'творчество, музыка, игры',
        LifeArea.travel => 'поездки, отпуск, маршруты',
        LifeArea.docs => 'паспорта, страховки, госуслуги',
        LifeArea.car => 'ТО, страховка, права',
        LifeArea.charity => 'волонтёрство, помощь близким',
      };

  /// Только для взрослых: юнгам эти разделы не предлагаются.
  bool get adultOnly => this == LifeArea.career || this == LifeArea.docs || this == LifeArea.car;

  /// Какую характеристику обычно прокачивает раздел.
  HeroStat get stat => switch (this) {
        LifeArea.health || LifeArea.sport || LifeArea.mind => HeroStat.strength,
        LifeArea.finance || LifeArea.career || LifeArea.study || LifeArea.docs => HeroStat.intellect,
        LifeArea.family || LifeArea.social || LifeArea.travel || LifeArea.charity => HeroStat.charisma,
        LifeArea.home || LifeArea.hobby || LifeArea.car => HeroStat.mastery,
      };

  static LifeArea? fromName(Object? name) => _byNameOrNull(LifeArea.values, name);
}

// ---------- Будильники и напоминания ----------

enum ReminderKind { alarm, reminder }

extension ReminderKindInfo on ReminderKind {
  String get label => switch (this) {
        ReminderKind.alarm => 'Будильник',
        ReminderKind.reminder => 'Напоминание',
      };

  String get emoji => switch (this) {
        ReminderKind.alarm => '⏰',
        ReminderKind.reminder => '🔔',
      };
}

/// Будильник или напоминание: время, дни недели (или одна дата),
/// можно связать с целью («Зарядка» в 7:30 по будням).
class Reminder {
  Reminder({
    required this.id,
    required this.heroId,
    required this.title,
    required this.kind,
    required this.hour,
    required this.minute,
    required this.createdAt,
    List<int>? weekdays,
    this.date,
    this.goalId,
    this.enabled = true,
    this.snoozedUntil,
    this.snoozeMinutes = 5,
    this.wakeUp = false,
  }) : weekdays = weekdays ?? [];

  final String id;
  String heroId;
  String title;
  ReminderKind kind;
  int hour;
  int minute;

  /// Дни недели (1 = пн … 7 = вс). Пусто — каждый день.
  List<int> weekdays;

  /// Разовое напоминание: конкретная дата (время — [hour]:[minute]).
  /// Если задано, [weekdays] не используются.
  DateTime? date;

  /// Связанная цель — из звонка можно сразу её выполнить или запустить таймер.
  String? goalId;
  bool enabled;
  final DateTime createdAt;

  /// Будильник отложен до этого момента.
  DateTime? snoozedUntil;
  int snoozeMinutes;

  /// «Подъём»: выключить вовремя — растёт пунктуальность и «Жаворонок».
  bool wakeUp;

  bool get oneTime => date != null;

  String get timeLabel => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'heroId': heroId,
        'title': title,
        'kind': kind.name,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'date': date?.toIso8601String(),
        'goalId': goalId,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        'snoozedUntil': snoozedUntil?.toIso8601String(),
        'snoozeMinutes': snoozeMinutes,
        'wakeUp': wakeUp,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        heroId: j['heroId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        kind: _byName(ReminderKind.values, j['kind'], ReminderKind.reminder),
        hour: ((j['hour'] as num?)?.toInt() ?? 8).clamp(0, 23),
        minute: ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
        weekdays: [
          for (final d in (j['weekdays'] as List?) ?? const [])
            if (d is num && d >= 1 && d <= 7) d.toInt(),
        ],
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        goalId: j['goalId'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        snoozedUntil: DateTime.tryParse(j['snoozedUntil'] as String? ?? ''),
        snoozeMinutes: ((j['snoozeMinutes'] as num?)?.toInt() ?? 5).clamp(1, 60),
        wakeUp: j['wakeUp'] as bool? ?? false,
      );
}

// ---------- Таймеры «на время» ----------

enum TimerMode { countdown, stopwatch }

extension TimerModeInfo on TimerMode {
  String get label => switch (this) {
        TimerMode.countdown => 'Успеть за время',
        TimerMode.stopwatch => 'Секундомер',
      };

  String get emoji => switch (this) {
        TimerMode.countdown => '⏳',
        TimerMode.stopwatch => '⏱',
      };
}

/// Запущенный таймер героя. Хранится в состоянии, поэтому переживает
/// перезапуск приложения: время считается от [startedAt].
class ActiveTimer {
  ActiveTimer({
    required this.id,
    required this.heroId,
    required this.title,
    required this.mode,
    required this.startedAt,
    this.plannedSec = 0,
    this.pausedAt,
    this.pausedSec = 0,
    this.goalId,
    this.skillId,
    this.stat = HeroStat.mastery,
    this.area,
    this.rang = false,
  });

  final String id;
  final String heroId;
  String title;
  final TimerMode mode;

  /// Лимит для режима «Успеть за время».
  final int plannedSec;
  final DateTime startedAt;
  DateTime? pausedAt;

  /// Сколько секунд таймер простоял на паузе (всего).
  int pausedSec;
  final String? goalId;
  final String? skillId;
  final HeroStat stat;
  final LifeArea? area;

  /// Уже прозвенел по окончании времени.
  bool rang;

  bool get paused => pausedAt != null;

  int elapsedSec(DateTime now) {
    final end = pausedAt ?? now;
    final s = end.difference(startedAt).inSeconds - pausedSec;
    return s < 0 ? 0 : s;
  }

  /// Сколько осталось в режиме «Успеть за время» (может быть меньше нуля).
  int leftSec(DateTime now) => plannedSec - elapsedSec(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'heroId': heroId,
        'title': title,
        'mode': mode.name,
        'plannedSec': plannedSec,
        'startedAt': startedAt.toIso8601String(),
        'pausedAt': pausedAt?.toIso8601String(),
        'pausedSec': pausedSec,
        'goalId': goalId,
        'skillId': skillId,
        'stat': stat.name,
        'area': area?.name,
        'rang': rang,
      };

  factory ActiveTimer.fromJson(Map<String, dynamic> j) => ActiveTimer(
        id: j['id'] as String,
        heroId: j['heroId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        mode: _byName(TimerMode.values, j['mode'], TimerMode.stopwatch),
        plannedSec: (j['plannedSec'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
        pausedAt: DateTime.tryParse(j['pausedAt'] as String? ?? ''),
        pausedSec: (j['pausedSec'] as num?)?.toInt() ?? 0,
        goalId: j['goalId'] as String?,
        skillId: j['skillId'] as String?,
        stat: _byName(HeroStat.values, j['stat'], HeroStat.mastery),
        area: LifeAreaInfo.fromName(j['area']),
        rang: j['rang'] as bool? ?? false,
      );
}

/// Завершённая сессия таймера — для истории, статистики и рекордов скорости.
class FocusSession {
  FocusSession({
    required this.id,
    required this.heroId,
    required this.title,
    required this.mode,
    required this.actualSec,
    required this.at,
    this.plannedSec = 0,
    this.goalId,
    this.skillId,
    this.beat = false,
    this.xp = 0,
    this.coins = 0,
    this.stat = HeroStat.mastery,
    this.area,
  });

  final String id;
  final String heroId;
  final String title;
  final TimerMode mode;
  final int plannedSec;
  final int actualSec;

  /// Когда закончена.
  final DateTime at;
  final String? goalId;
  final String? skillId;

  /// Успел до конца лимита («Успеть за время»).
  final bool beat;
  final int xp;
  final int coins;
  final HeroStat stat;
  final LifeArea? area;

  Map<String, dynamic> toJson() => {
        'id': id,
        'h': heroId,
        't': title,
        'm': mode.name,
        'p': plannedSec,
        's': actualSec,
        'a': at.toIso8601String(),
        if (goalId != null) 'g': goalId,
        if (skillId != null) 'k': skillId,
        if (beat) 'b': true,
        'x': xp,
        'c': coins,
        'st': stat.name,
        if (area != null) 'ar': area!.name,
      };

  factory FocusSession.fromJson(Map<String, dynamic> j) => FocusSession(
        id: j['id'] as String,
        heroId: j['h'] as String? ?? '',
        title: j['t'] as String? ?? '',
        mode: _byName(TimerMode.values, j['m'], TimerMode.stopwatch),
        plannedSec: (j['p'] as num?)?.toInt() ?? 0,
        actualSec: (j['s'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['a'] as String? ?? '') ?? DateTime.now(),
        goalId: j['g'] as String?,
        skillId: j['k'] as String?,
        beat: j['b'] as bool? ?? false,
        xp: (j['x'] as num?)?.toInt() ?? 0,
        coins: (j['c'] as num?)?.toInt() ?? 0,
        stat: _byName(HeroStat.values, j['st'], HeroStat.mastery),
        area: LifeAreaInfo.fromName(j['ar']),
      );
}

// ---------- Навыки и личные рекорды ----------

enum SkillBetter { higher, lower }

/// Навык, который герой развивает и измеряет: «Отжимания» (раз, больше — лучше),
/// «Бег 1 км» (время, меньше — лучше), «Скорость печати» (зн/мин).
class Skill {
  Skill({
    required this.id,
    required this.heroId,
    required this.name,
    required this.emoji,
    required this.unit,
    required this.createdAt,
    this.better = SkillBetter.higher,
    this.timed = false,
    this.target,
    this.stat = HeroStat.mastery,
    this.area,
    this.archived = false,
  });

  final String id;
  final String heroId;
  String name;
  String emoji;

  /// Единица измерения: «раз», «кг», «зн/мин». Для [timed] — время (мм:сс).
  String unit;
  SkillBetter better;

  /// Значение — время в секундах (замер секундомером).
  bool timed;

  /// Цель навыка: «50 отжиманий», «1 км за 5:00».
  double? target;
  HeroStat stat;
  LifeArea? area;
  bool archived;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'heroId': heroId,
        'name': name,
        'emoji': emoji,
        'unit': unit,
        'better': better.name,
        'timed': timed,
        'target': target,
        'stat': stat.name,
        'area': area?.name,
        'archived': archived,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        id: j['id'] as String,
        heroId: j['heroId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🏅',
        unit: j['unit'] as String? ?? '',
        better: _byName(SkillBetter.values, j['better'], SkillBetter.higher),
        timed: j['timed'] as bool? ?? false,
        target: (j['target'] as num?)?.toDouble(),
        stat: _byName(HeroStat.values, j['stat'], HeroStat.mastery),
        area: LifeAreaInfo.fromName(j['area']),
        archived: j['archived'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Один замер навыка. [pb] — это был новый личный рекорд.
class SkillEntry {
  SkillEntry({
    required this.id,
    required this.skillId,
    required this.heroId,
    required this.value,
    required this.at,
    this.note = '',
    this.pb = false,
    this.xp = 0,
    this.coins = 0,
  });

  final String id;
  final String skillId;
  final String heroId;
  final double value;
  final DateTime at;
  final String note;
  final bool pb;
  final int xp;
  final int coins;

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': skillId,
        'h': heroId,
        'v': value,
        'a': at.toIso8601String(),
        if (note.isNotEmpty) 'n': note,
        if (pb) 'pb': true,
        'x': xp,
        'c': coins,
      };

  factory SkillEntry.fromJson(Map<String, dynamic> j) => SkillEntry(
        id: j['id'] as String,
        skillId: j['k'] as String? ?? '',
        heroId: j['h'] as String? ?? '',
        value: (j['v'] as num?)?.toDouble() ?? 0,
        at: DateTime.tryParse(j['a'] as String? ?? '') ?? DateTime.now(),
        note: j['n'] as String? ?? '',
        pb: j['pb'] as bool? ?? false,
        xp: (j['x'] as num?)?.toInt() ?? 0,
        coins: (j['c'] as num?)?.toInt() ?? 0,
      );
}
