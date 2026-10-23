import 'dart:math';

import '../models/models.dart';

/// Чистые функции игровой механики: их легко тестировать и переиспользовать
/// на сервере в будущем.
class GameRules {
  const GameRules._();

  /// Сколько опыта нужно, чтобы перейти с [level] на следующий уровень.
  static int xpToNext(int level) => 100 + 50 * (level - 1);

  /// Сколько всего опыта нужно, чтобы достичь [level].
  static int totalXpForLevel(int level) {
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += xpToNext(l);
    }
    return total;
  }

  /// Уровень, опыт внутри уровня и сколько нужно до следующего.
  static LevelInfo levelFor(int totalXp) {
    var level = 1;
    var rest = totalXp < 0 ? 0 : totalXp;
    while (rest >= xpToNext(level)) {
      rest -= xpToNext(level);
      level++;
    }
    return LevelInfo(level: level, xpInLevel: rest, xpNeeded: xpToNext(level));
  }

  /// Бонус за серию рутины: +1 XP за день серии, не больше +10.
  static int dailyXp(int streak) => GoalTier.daily.xp + (streak.clamp(1, 11) - 1);

  /// Опыт за рутину с учётом частоты и серии (бонус растёт до 10 периодов).
  static int repeatXp(Goal g, int streak) => g.repeat.baseXp + g.repeat.streakBonus * (streak.clamp(1, 11) - 1);

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---------- Расписание рутины ----------

  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  /// Запланированное число месяца: 31-е в ноябре превращается в 30-е.
  static int plannedMonthDay(Goal g, int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    return min(g.monthDay ?? 1, last);
  }

  /// Можно ли выполнять рутину в этот день. Ежедневную по дням недели —
  /// только в выбранные дни; недельную и месячную — в любой день периода.
  static bool isScheduledDay(Goal g, DateTime day) =>
      g.repeat != Repeat.daily || g.weekdays.isEmpty || g.weekdays.contains(day.weekday);

  /// Запланированный день («по плану») — за него растёт пунктуальность.
  static bool isPlannedDay(Goal g, DateTime day) => switch (g.repeat) {
        Repeat.daily => isScheduledDay(g, day),
        Repeat.weekly => g.weekdays.isNotEmpty && day.weekday == g.weekdays.first,
        Repeat.monthly => g.monthDay != null && day.day == plannedMonthDay(g, day.year, day.month),
      };

  /// Начало периода, к которому относится [day]: сам день, понедельник
  /// недели или 1-е число. Для ежедневной по дням недели — последний
  /// запланированный день не позже [day].
  static DateTime periodAnchor(Goal g, DateTime day) {
    final d = dayStart(day);
    switch (g.repeat) {
      case Repeat.daily:
        if (g.weekdays.isEmpty) return d;
        var cur = d;
        for (var i = 0; i < 7; i++) {
          if (g.weekdays.contains(cur.weekday)) return cur;
          cur = _addDays(cur, -1);
        }
        return d;
      case Repeat.weekly:
        return _addDays(d, -(d.weekday - 1));
      case Repeat.monthly:
        return DateTime(d.year, d.month, 1);
    }
  }

  /// Начало предыдущего периода (для серии).
  static DateTime previousAnchor(Goal g, DateTime anchor) => switch (g.repeat) {
        Repeat.daily => periodAnchor(g, _addDays(anchor, -1)),
        Repeat.weekly => _addDays(anchor, -7),
        Repeat.monthly => DateTime(anchor.year, anchor.month - 1, 1),
      };

  /// Можно ли отметить рутину прямо сейчас.
  static bool canDoNow(Goal g, DateTime now) => g.isDaily && isScheduledDay(g, now);

  /// Выполнена ли рутина в текущем периоде (сегодня / на этой неделе / в этом месяце).
  static bool isDoneToday(Goal g, DateTime now) => g.isDaily && g.lastDoneDay == dayKey(periodAnchor(g, now));

  /// Серия, которая получится, если выполнить рутину сейчас.
  static int nextStreak(Goal g, DateTime now) {
    final anchor = periodAnchor(g, now);
    if (g.lastDoneDay == dayKey(anchor)) return g.streak;
    return g.lastDoneDay == dayKey(previousAnchor(g, anchor)) ? g.streak + 1 : 1;
  }

  /// Актуальная серия (сгорает, если прошлый период пропущен).
  static int liveStreak(Goal g, DateTime now) {
    final anchor = periodAnchor(g, now);
    if (g.lastDoneDay == dayKey(anchor) || g.lastDoneDay == dayKey(previousAnchor(g, anchor))) return g.streak;
    return 0;
  }

  /// Опыт черт характера за выполнение рутины.
  static Map<HeroTrait, int> traitGain(Goal g, int streak, {required bool onTime}) {
    final k = switch (g.repeat) {
      Repeat.daily => 1,
      Repeat.weekly => 2,
      Repeat.monthly => 4,
    };
    final punctual = !onTime
        ? 0
        : switch (g.repeat) {
            Repeat.daily => g.weekdays.isEmpty ? 1 : 2,
            Repeat.weekly => 5,
            Repeat.monthly => 10,
          };
    return {
      HeroTrait.habit: 2 * k + (g.repeat == Repeat.monthly ? 2 : 0),
      if (punctual > 0) HeroTrait.punctuality: punctual,
      if (streak > 1) HeroTrait.endurance: k * (streak.clamp(1, 11) - 1),
    };
  }

  /// Уровень черты характера: порог растёт медленнее, чем у героя.
  static LevelInfo traitLevel(int xp) {
    int need(int l) => 30 + 20 * (l - 1);
    var level = 1;
    var rest = max(0, xp);
    while (rest >= need(level)) {
      rest -= need(level);
      level++;
    }
    return LevelInfo(level: level, xpInLevel: rest, xpNeeded: need(level));
  }

  static const _weekdayDative = ['понедельникам', 'вторникам', 'средам', 'четвергам', 'пятницам', 'субботам', 'воскресеньям'];

  /// «каждый день», «пн, ср, пт», «по будням», «по средам», «15-го числа».
  static String scheduleLabel(Goal g) {
    switch (g.repeat) {
      case Repeat.daily:
        final days = [...g.weekdays]..sort();
        if (days.isEmpty || days.length == 7) return 'каждый день';
        if (days.join() == '12345') return 'по будням';
        if (days.join() == '67') return 'по выходным';
        return days.map((d) => weekdayShort[d - 1].toLowerCase()).join(', ');
      case Repeat.weekly:
        return g.weekdays.isEmpty ? 'раз в неделю' : 'по ${_weekdayDative[g.weekdays.first - 1]}';
      case Repeat.monthly:
        return g.monthDay == null ? 'раз в месяц' : '${g.monthDay}-го числа';
    }
  }

  /// «сегодня» / «на этой неделе» / «в этом месяце».
  static String periodLabel(Repeat r) => switch (r) {
        Repeat.daily => 'сегодня',
        Repeat.weekly => 'на этой неделе',
        Repeat.monthly => 'в этом месяце',
      };

  // ---------- Сроки ----------

  /// Разница в календарных днях (без влияния часовых поясов и перевода часов).
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  static DueState dueState(Goal g, DateTime now) {
    final due = g.dueDate;
    if (due == null || g.done || g.isDaily) return DueState.none;
    final left = daysBetween(now, due);
    if (left < 0) return DueState.overdue;
    if (left == 0) return DueState.today;
    if (left <= 3) return DueState.soon;
    return DueState.later;
  }

  static String dueLabel(Goal g, DateTime now) {
    final due = g.dueDate;
    if (due == null) return '';
    final left = daysBetween(now, due);
    if (g.done || g.isDaily) return 'до ${shortDate(due)}';
    if (left < -1) return 'просрочено на ${-left} дн.';
    if (left == -1) return 'срок был вчера';
    if (left == 0) return 'срок сегодня';
    if (left == 1) return 'срок завтра';
    if (left <= 6) return 'через $left дн.';
    return 'до ${shortDate(due)}';
  }

  static String shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  /// Цели, о которых стоит напомнить: просроченные, на сегодня и ближайшие 3 дня.
  static List<Goal> reminders(List<Goal> goals, DateTime now, {String? heroId}) {
    final list = goals.where((g) {
      final s = dueState(g, now);
      if (s == DueState.none || s == DueState.later) return false;
      return heroId == null || g.ownerId == heroId || g.isFamily;
    }).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return list;
  }

  // ---------- Бюджет ----------

  static MonthSummary monthSummary(List<MoneyEntry> money, int year, int month) {
    var income = 0, expense = 0, saved = 0;
    final byCategory = <String, int>{};
    for (final m in money) {
      if (m.date.year != year || m.date.month != month) continue;
      switch (m.kind) {
        case MoneyKind.income:
          income += m.amount;
        case MoneyKind.expense:
          expense += m.amount;
        case MoneyKind.saving:
          saved += m.amount;
      }
      final cat = m.categoryId;
      if (cat != null) byCategory[cat] = (byCategory[cat] ?? 0) + m.amount;
    }
    return MonthSummary(income: income, expense: expense, saved: saved, byCategory: byCategory);
  }

  static int potSaved(String potId, List<MoneyEntry> money) => money
      .where((m) => m.kind == MoneyKind.saving && m.potId == potId)
      .fold<int>(0, (s, m) => s + m.amount);

  /// 125000 → «125 000 ₽».
  static String rub(int amount) {
    final neg = amount < 0;
    final digits = amount.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u00A0');
      buf.write(digits[i]);
    }
    return '${neg ? '−' : ''}$buf\u00A0₽';
  }

  static List<Goal> childrenOf(String id, List<Goal> goals) =>
      goals.where((g) => g.parentId == id).toList()
        ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));

  /// Прогресс цели от 0 до 1. Рутина в прогресс родителя не входит.
  static double progress(Goal goal, List<Goal> goals) {
    if (goal.done) return 1;
    if (goal.isDaily) return 0;
    final kids = childrenOf(goal.id, goals).where((g) => !g.isDaily).toList();
    if (kids.isEmpty) return goal.pendingApproval ? 0.5 : 0;
    var total = 0.0;
    var weight = 0.0;
    for (final k in kids) {
      final w = k.tier.xp.toDouble();
      total += progress(k, goals) * w;
      weight += w;
    }
    return weight == 0 ? 0 : total / weight;
  }

  /// Все ли (не рутинные) дочерние цели выполнены.
  static bool allChildrenDone(Goal goal, List<Goal> goals) {
    final kids = childrenOf(goal.id, goals).where((g) => !g.isDaily).toList();
    return kids.isNotEmpty && kids.every((k) => k.done);
  }

  /// Цепочка предков от корня до цели (без самой цели).
  static List<Goal> ancestors(Goal goal, List<Goal> goals) {
    final byId = {for (final g in goals) g.id: g};
    final result = <Goal>[];
    var cur = goal.parentId == null ? null : byId[goal.parentId];
    var guard = 0;
    while (cur != null && guard++ < 20) {
      result.insert(0, cur);
      cur = cur.parentId == null ? null : byId[cur.parentId];
    }
    return result;
  }

  /// Все потомки цели (для каскадного удаления).
  static Set<String> descendantIds(String id, List<Goal> goals) {
    final result = <String>{};
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final g in goals) {
        if (g.parentId == cur && result.add(g.id)) queue.add(g.id);
      }
    }
    return result;
  }

  // ---------- Статистика ----------

  /// Начало календарного дня.
  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Записи героя (или всей гильдии, если [heroId] == null) за [days] дней,
  /// начиная с [start] (включительно).
  static Iterable<XpRecord> recordsIn(List<XpRecord> records, DateTime start, int days, {String? heroId}) {
    final from = dayStart(start);
    return records.where((r) {
      if (heroId != null && r.heroId != heroId) return false;
      final d = daysBetween(from, r.at);
      return d >= 0 && d < days;
    });
  }

  /// Опыт по дням: список длиной [days], первый элемент — день [start].
  static List<int> xpPerDay(List<XpRecord> records, DateTime start, int days, {String? heroId}) {
    final result = List<int>.filled(days, 0);
    final from = dayStart(start);
    for (final r in recordsIn(records, from, days, heroId: heroId)) {
      result[daysBetween(from, r.at)] += r.xp;
    }
    return result;
  }

  static PeriodStats periodStats(List<XpRecord> records, DateTime start, int days, {String? heroId}) {
    var xp = 0, coins = 0, goals = 0, dailies = 0;
    final byTier = <GoalTier, int>{};
    final byStat = <HeroStat, int>{};
    final byHero = <String, int>{};
    final traits = <HeroTrait, int>{};
    var onTime = 0;
    final active = <String>{};
    final byArea = <LifeArea, int>{};
    final byKind = <XpKind, int>{};
    for (final r in recordsIn(records, start, days, heroId: heroId)) {
      xp += r.xp;
      coins += r.coins;
      byKind[r.kind] = (byKind[r.kind] ?? 0) + r.xp;
      final area = r.area;
      if (area != null) byArea[area] = (byArea[area] ?? 0) + r.xp;
      byStat[r.stat] = (byStat[r.stat] ?? 0) + r.xp;
      byHero[r.heroId] = (byHero[r.heroId] ?? 0) + r.xp;
      active.add(dayKey(r.at));
      for (final e in r.traits.entries) {
        traits[e.key] = (traits[e.key] ?? 0) + e.value;
      }
      // Таймеры, навыки и подъёмы — это опыт, но не «выполненные цели».
      if (!r.isGoal) continue;
      if (r.tier == GoalTier.daily) {
        dailies++;
      } else {
        goals++;
      }
      byTier[r.tier] = (byTier[r.tier] ?? 0) + 1;
      if (r.onTime) onTime++;
    }
    return PeriodStats(
      days: days,
      xp: xp,
      coins: coins,
      goals: goals,
      dailies: dailies,
      activeDays: active.length,
      byTier: byTier,
      byStat: byStat,
      byHero: byHero,
      traits: traits,
      onTime: onTime,
      byArea: byArea,
      byKind: byKind,
    );
  }

  /// Сколько дней подряд (по сегодня или по вчера) герой что-то выполнял.
  static int activityStreak(List<XpRecord> records, DateTime now, {String? heroId}) {
    final days = {
      for (final r in records)
        if (heroId == null || r.heroId == heroId) dayKey(r.at),
    };
    var cur = dayStart(now);
    if (!days.contains(dayKey(cur))) cur = cur.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(dayKey(cur))) {
      n++;
      cur = DateTime(cur.year, cur.month, cur.day - 1);
    }
    return n;
  }

  /// Самая длинная серия активных дней за всю историю.
  static int bestActivityRun(List<XpRecord> records, {String? heroId}) {
    final days = {
      for (final r in records)
        if (heroId == null || r.heroId == heroId) dayStart(r.at),
    }.toList()
      ..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      run = prev != null && daysBetween(prev, d) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  /// День недели (1 — понедельник … 7 — воскресенье), в который герой
  /// набирает больше всего опыта; null, если данных нет.
  static int? bestWeekday(List<XpRecord> records, {String? heroId}) {
    final sums = <int, int>{};
    for (final r in records) {
      if (heroId != null && r.heroId != heroId) continue;
      sums[r.at.weekday] = (sums[r.at.weekday] ?? 0) + r.xp;
    }
    if (sums.isEmpty) return null;
    return sums.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const weekdayLong = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];

  /// Изменение в процентах относительно прошлого периода; null — сравнивать не с чем.
  static int? deltaPercent(int current, int previous) {
    if (previous <= 0) return null;
    return ((current - previous) * 100 / previous).round();
  }

  // ---------- Достижения ----------

  /// Все достижения героя с текущим прогрессом. Ступень — максимум из
  /// вычисленной сейчас и уже сохранённой в профиле (полученное не теряется).
  static List<Achievement> achievements(
    HeroProfile hero,
    List<Goal> goals,
    DateTime now, {
    List<XpRecord> records = const [],
    List<HeroProfile> heroes = const [],
    List<MoneyEntry> money = const [],
    List<SavingsPot> pots = const [],
    List<RewardClaim> claims = const [],
    bool solo = false,
    List<FocusSession> sessions = const [],
    List<SkillEntry> skillEntries = const [],
  }) {
    final mine = goals.where((g) => g.completedById == hero.id && g.done).toList();
    int countTier(GoalTier t) => mine.where((g) => g.tier == t).length;
    final myRecords = records.where((r) => r.heroId == hero.id).toList();
    int best(Repeat r) => goals
        .where((g) => g.isDaily && g.repeat == r && g.ownerId == hero.id)
        .fold<int>(0, (m, g) => max(m, max(g.bestStreak, g.streak)));
    final bestStreak = best(Repeat.daily);
    final punctual = myRecords.where((r) => r.onTime).length;
    final familyLegend = goals.any((g) => g.tier == GoalTier.legend && g.isFamily && g.done);
    final level = levelFor(hero.xp).level;
    final early = myRecords.where((r) => r.isGoal && r.at.hour >= 4 && r.at.hour < 8).length;
    final mySessions = sessions.where((x) => x.heroId == hero.id);
    final focusMinutes = mySessions.fold<int>(0, (m, x) => m + x.actualSec) ~/ 60;
    final beat = mySessions.where((x) => x.beat).length;
    final pbs = skillEntries.where((e) => e.heroId == hero.id && e.pb).length;
    final wakeUps = myRecords.where((r) => r.kind == XpKind.wake).length;
    final areas = {
      for (final r in myRecords)
        if (r.isGoal && r.area != null) r.area!,
    }.length;
    final onTime = mine
        .where((g) => g.dueDate != null && g.completedAt != null && daysBetween(g.completedAt!, g.dueDate!) >= 0)
        .length;
    final allRound = HeroStat.values.map((s) => hero.statXp[s] ?? 0).reduce(min);
    final teamSteps = myRecords.where((r) => r.isGoal && r.family && r.tier != GoalTier.daily).length;
    final perDayDailies = <String, Set<String>>{};
    for (final r in myRecords.where((r) => r.isGoal && r.tier == GoalTier.daily)) {
      perDayDailies.putIfAbsent(dayKey(r.at), () => {}).add(r.goalId);
    }
    final maxDailiesInDay = perDayDailies.values.fold<int>(0, (m, s) => max(m, s.length));
    // Чемпион недели: больше всех опыта в гильдии за последние 7 дней.
    final week = periodStats(records, now.subtract(const Duration(days: 6)), 7);
    final myWeek = week.byHero[hero.id] ?? 0;
    final champion = heroes.length >= 2 &&
        myWeek > 0 &&
        heroes.where((h) => h.id != hero.id).every((h) => (week.byHero[h.id] ?? 0) < myWeek);
    final loot = claims.where((c) => c.heroId == hero.id && c.status == ClaimStatus.granted).length;

    Achievement a(String id, String emoji, String title, String Function(int n) describe, List<int> thresholds,
            int value) =>
        Achievement(
          id: id,
          emoji: emoji,
          title: title,
          describe: describe,
          thresholds: thresholds,
          value: value,
        ).merged(hero.badges[id] ?? 0);

    return [
      a('first_task', '🗡', 'Первый шаг', (_) => 'Выполнить первое задание', const [1], countTier(GoalTier.task)),
      a('worker', '📚', 'Трудяга', (n) => 'Выполнить $n заданий', const [10, 50, 200], countTier(GoalTier.task)),
      a('seeker', '⚔️', 'Искатель', (n) => n == 1 ? 'Пройти первый квест' : 'Пройти $n квестов', const [1, 10, 30],
          countTier(GoalTier.quest)),
      a('conqueror', '🏰', 'Покоритель', (n) => n == 1 ? 'Завершить эпик' : 'Завершить $n эпиков', const [1, 5, 15],
          countTier(GoalTier.epic)),
      a('fire', '🔥', 'Огненная серия', (n) => 'Серия рутины $n дней подряд', const [7, 30, 100], bestStreak),
      a('weekly', '📆', 'Неделя за неделей', (n) => 'Еженедельное дело $n недель подряд', const [4, 12, 52],
          best(Repeat.weekly)),
      a('monthly', '🗓', 'Месяц за месяцем', (n) => 'Ежемесячное дело $n месяцев подряд', const [3, 6, 12],
          best(Repeat.monthly)),
      a('punctual', '⏰', 'Пунктуальный', (n) => '$n раз сделать рутину в запланированный день', const [10, 50, 200],
          punctual),
      a('routine', '☀️', 'Режим дня', (n) => '$n разных рутин за один день', const [3, 5, 8], maxDailiesInDay),
      a('no_days_off', '📅', 'Без выходных', (n) => 'Выполнять хоть что-то $n дней подряд', const [3, 7, 30],
          bestActivityRun(records, heroId: hero.id)),
      a('early', '🌅', 'Ранняя пташка', (n) => n == 1 ? 'Выполнить цель до 8 утра' : '$n раз выполнить цель до 8 утра',
          const [1, 10, 30], early),
      a('on_time', '🎯', 'Точно в срок', (n) => n == 1 ? 'Успеть к сроку' : 'Успеть к сроку $n раз', const [1, 10, 30],
          onTime),
      a('all_round', '🧩', 'Мастер на все руки', (n) => 'Набрать $n XP в каждой характеристике', const [50, 200, 500],
          allRound),
      if (!solo) a('team', '🤝', 'Командный игрок', (n) => '$n шагов в семейных целях', const [5, 25, 100], teamSteps),
      if (!solo) a('champion', '🏆', 'Чемпион недели', (_) => 'Больше всех опыта в гильдии за 7 дней', const [1],
          champion ? 1 : 0),
      a('focus', '⏱', 'Сосредоточенность', (n) => 'Провести $n минут на таймере', const [60, 600, 3000],
          focusMinutes),
      a('speed', '⚡', 'Быстрее ветра', (n) => n == 1 ? 'Успеть за время на таймере' : 'Успеть за время $n раз',
          const [1, 10, 30], beat),
      a('record', '🏅', 'Рекордсмен', (n) => n == 1 ? 'Поставить личный рекорд' : 'Поставить $n личных рекордов',
          const [1, 10, 50], pbs),
      a('lark', '🌄', 'Жаворонок', (n) => 'Встать по будильнику вовремя $n раз', const [5, 20, 60], wakeUps),
      a('balance', '⚖️', 'Гармония', (n) => 'Выполнять цели в $n разных разделах жизни', const [3, 6, 10], areas),
      a('veteran', '⭐', 'Ветеран', (n) => 'Достичь $n уровня', const [5, 10, 20], level),
      a('saver', '🪙', 'Копилка героя', (n) => 'Скопить $n монет', const [100, 300, 1000], hero.coins),
      a('loot', '🎁', 'Охотник за лутом', (n) => n == 1 ? 'Получить награду из лавки' : 'Получить $n наград',
          const [1, 5, 20], loot),
      if (!solo) a('family_legend', '👑', 'Легенда семьи', (_) => 'Семья завершила легенду', const [1], familyLegend ? 1 : 0),
      if (hero.role.isAdult) ...[
        a('treasurer', '🧾', 'Казначей', (n) => 'Записать $n операций в бюджет', const [20, 100, 300],
            money.where((m) => m.heroId == hero.id).length),
        a('pot_full', '🐷', 'Копилка полна', (_) => 'Накопить всю сумму копилки', const [1],
            pots.where((p) => p.target > 0 && potSaved(p.id, money) >= p.target).length),
      ],
    ];
  }
}

class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.xpInLevel,
    required this.xpNeeded,
  });

  final int level;
  final int xpInLevel;
  final int xpNeeded;

  double get fraction => xpNeeded == 0 ? 0 : xpInLevel / xpNeeded;

  /// Звание героя по уровню — для антуража.
  String get title {
    if (level >= 30) return 'Легендарный';
    if (level >= 20) return 'Мифический';
    if (level >= 12) return 'Чемпион';
    if (level >= 7) return 'Рыцарь';
    if (level >= 3) return 'Искатель';
    return 'Новичок';
  }
}

enum DueState { none, overdue, today, soon, later }

class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.expense,
    required this.saved,
    required this.byCategory,
  });

  final int income;
  final int expense;
  final int saved;
  final Map<String, int> byCategory;

  int get balance => income - expense - saved;
}

class PeriodStats {
  const PeriodStats({
    required this.days,
    required this.xp,
    required this.coins,
    required this.goals,
    required this.dailies,
    required this.activeDays,
    required this.byTier,
    required this.byStat,
    required this.byHero,
    this.traits = const {},
    this.onTime = 0,
    this.byArea = const {},
    this.byKind = const {},
  });

  final int days;
  final int xp;
  final int coins;

  /// Выполнено целей (без рутины).
  final int goals;

  /// Отметок рутины.
  final int dailies;
  final int activeDays;
  final Map<GoalTier, int> byTier;
  final Map<HeroStat, int> byStat;
  final Map<String, int> byHero;

  /// Опыт черт характера за период.
  final Map<HeroTrait, int> traits;

  /// Рутина, выполненная в запланированный день.
  final int onTime;

  /// v5: опыт по разделам жизни и по источникам (цели, таймер, навыки, подъём).
  final Map<LifeArea, int> byArea;
  final Map<XpKind, int> byKind;
}

/// Достижение со ступенями: бронза → серебро → золото.
/// Достижение с одной ступенью — просто «получено / нет».
class Achievement {
  const Achievement({
    required this.id,
    required this.emoji,
    required this.title,
    required this.describe,
    required this.thresholds,
    required this.value,
    this.level = 0,
  });

  final String id;
  final String emoji;
  final String title;
  final String Function(int target) describe;
  final List<int> thresholds;

  /// Текущее значение счётчика (сколько заданий, дней серии и т. п.).
  final int value;

  /// Достигнутая ступень: 0 — ещё нет.
  final int level;

  static int levelFor(List<int> thresholds, int value) => thresholds.where((t) => value >= t).length;

  /// Ступень с учётом уже полученной ранее.
  Achievement merged(int storedLevel) => Achievement(
        id: id,
        emoji: emoji,
        title: title,
        describe: describe,
        thresholds: thresholds,
        value: value,
        level: max(levelFor(thresholds, value), min(storedLevel, thresholds.length)),
      );

  int get maxLevel => thresholds.length;
  bool get tiered => thresholds.length > 1;
  bool get unlocked => level > 0;
  bool get maxed => level >= maxLevel;
  int? get nextTarget => maxed ? null : thresholds[level];

  /// Прогресс до следующей ступени (0..1).
  double get progress => maxed ? 1 : (value / nextTarget!).clamp(0.0, 1.0);

  /// Описание следующей цели (или последней, если всё получено).
  String get description => describe(nextTarget ?? thresholds.last);

  String get medal => tiered ? const ['', '🥉', '🥈', '🥇'][level.clamp(0, 3)] : '';

  static String levelName(int level) => const ['', 'бронза', 'серебро', 'золото'][level.clamp(0, 3)];
}
