import 'dart:math';

import '../models/models.dart';

/// Правила версии 0.5: расписание будильников, опыт за таймер,
/// личные рекорды навыков. Чистые функции — легко тестировать.
class TimeRules {
  const TimeRules._();

  // ---------- Будильники и напоминания ----------

  /// Будильник, который опоздал больше чем на это время (приложение было
  /// закрыто), не звонит, а показывается как пропущенный.
  static const alarmGrace = Duration(minutes: 30);

  /// Пропущенные напоминания старше этого срока не показываем.
  static const missedWindow = Duration(hours: 12);

  /// Выключить будильник «Подъём» не позже этого — засчитывается подъём вовремя.
  static const wakeWindow = Duration(minutes: 10);

  static DateTime _at(DateTime day, Reminder r) => DateTime(day.year, day.month, day.day, r.hour, r.minute);

  static bool _dayFits(Reminder r, DateTime day) => r.weekdays.isEmpty || r.weekdays.contains(day.weekday);

  /// Ближайший звонок не раньше [from] (без учёта отложенного); null — больше не будет.
  static DateTime? nextOccurrence(Reminder r, DateTime from) {
    if (!r.enabled) return null;
    final date = r.date;
    if (date != null) {
      final t = _at(date, r);
      return t.isBefore(from) ? null : t;
    }
    for (var i = 0; i <= 7; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      if (!_dayFits(r, day)) continue;
      final t = _at(day, r);
      if (!t.isBefore(from)) return t;
    }
    return null;
  }

  /// Ближайший звонок с учётом «Отложить».
  static DateTime? nextRing(Reminder r, DateTime from) {
    final next = nextOccurrence(r, from);
    final snooze = r.snoozedUntil;
    if (r.enabled && snooze != null && !snooze.isBefore(from) && (next == null || snooze.isBefore(next))) {
      return snooze;
    }
    return next;
  }

  /// Последний звонок в промежутке (since, now] — или null.
  /// Если звонков было несколько (приложение долго было закрыто), берётся последний.
  static DateTime? firedBetween(Reminder r, DateTime since, DateTime now) {
    if (!r.enabled || !now.isAfter(since)) return null;
    DateTime? last;
    bool inWindow(DateTime t) => t.isAfter(since) && !t.isAfter(now);
    final date = r.date;
    if (date != null) {
      final t = _at(date, r);
      if (inWindow(t)) last = t;
    } else {
      // Больше 8 дней назад не смотрим: всё равно покажем только последний звонок.
      final from = since.isBefore(now.subtract(const Duration(days: 8))) ? now.subtract(const Duration(days: 8)) : since;
      var day = DateTime(from.year, from.month, from.day);
      final lastDay = DateTime(now.year, now.month, now.day);
      while (!day.isAfter(lastDay)) {
        if (_dayFits(r, day)) {
          final t = _at(day, r);
          if (inWindow(t)) last = t;
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    final snooze = r.snoozedUntil;
    if (snooze != null && inWindow(snooze) && (last == null || snooze.isAfter(last))) last = snooze;
    return last;
  }

  static const _weekdayShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

  /// «каждый день», «по будням», «пн, ср, пт», «24.10».
  static String repeatLabel(Reminder r) {
    final date = r.date;
    if (date != null) {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
    final days = [...r.weekdays]..sort();
    if (days.isEmpty || days.length == 7) return 'каждый день';
    if (days.join() == '12345') return 'по будням';
    if (days.join() == '67') return 'по выходным';
    return days.map((d) => _weekdayShort[d - 1]).join(', ');
  }

  /// «через 2 ч 15 мин», «через 5 мин», «завтра в 07:30», «в пт в 07:30».
  static String untilLabel(DateTime next, DateTime now) {
    final diff = next.difference(now);
    if (diff.inMinutes < 1) return 'меньше минуты';
    if (diff.inHours < 12) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return 'через ${h > 0 ? '$h ч ' : ''}${m > 0 || h == 0 ? '$m мин' : ''}'.trim();
    }
    final time = '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    final days = DateTime.utc(next.year, next.month, next.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    if (days == 0) return 'сегодня в $time';
    if (days == 1) return 'завтра в $time';
    if (days < 7) return 'в ${_weekdayShort[next.weekday - 1]} в $time';
    return '${next.day.toString().padLeft(2, '0')}.${next.month.toString().padLeft(2, '0')} в $time';
  }

  // ---------- Таймеры ----------

  /// Короче этого сессия не засчитывается (случайное нажатие).
  static const minSessionSec = 60;

  /// Опыт за фокус: 1 XP за каждые 5 минут, не больше 24 за сессию (2 часа).
  static int focusXp(int seconds) => seconds < minSessionSec ? 0 : min(24, max(1, seconds ~/ 300));

  /// Бонус «Успел за время».
  static const beatBonusXp = 5;
  static const beatBonusCoins = 3;

  /// Опыт за таймеры в день не больше — чтобы таймер не превращался в «ферму».
  static const focusXpPerDay = 40;

  /// 75 → «1:15», 3725 → «1:02:05».
  static String clock(int seconds) {
    final neg = seconds < 0;
    final s = seconds.abs();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final body = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '$m:${sec.toString().padLeft(2, '0')}';
    return neg ? '−$body' : body;
  }

  /// 1500 → «25 мин», 5400 → «1 ч 30 мин».
  static String minutesLabel(int seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m мин';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h ч' : '$h ч $rest мин';
  }

  /// Лучшее (самое быстрое) время, за которое выполнили цель на таймере.
  static int? bestTimeFor(String goalId, List<FocusSession> sessions) {
    int? best;
    for (final s in sessions) {
      if (s.goalId != goalId || s.actualSec < minSessionSec ~/ 6) continue;
      if (s.mode == TimerMode.countdown && !s.beat) continue;
      if (best == null || s.actualSec < best) best = s.actualSec;
    }
    return best;
  }

  // ---------- Навыки и рекорды ----------

  /// Опыт за замер (тренировку) — только первый замер навыка за день.
  static const practiceXp = 3;
  static const practiceCoins = 1;

  /// Новый личный рекорд — не чаще раза в день на навык.
  static const pbXp = 15;
  static const pbCoins = 5;

  static bool isBetter(Skill s, double value, double than) =>
      s.better == SkillBetter.higher ? value > than : value < than;

  /// Лучший результат навыка (личный рекорд) или null, если замеров нет.
  static double? personalBest(Skill s, List<SkillEntry> entries) {
    double? best;
    for (final e in entries) {
      if (e.skillId != s.id) continue;
      if (best == null || isBetter(s, e.value, best)) best = e.value;
    }
    return best;
  }

  static List<SkillEntry> entriesOf(String skillId, List<SkillEntry> entries) =>
      entries.where((e) => e.skillId == skillId).toList()..sort((a, b) => a.at.compareTo(b.at));

  /// Прогресс к цели навыка (0..1) — от первого замера к цели.
  static double? targetProgress(Skill s, List<SkillEntry> entries) {
    final target = s.target;
    final list = entriesOf(s.id, entries);
    if (target == null || list.isEmpty) return null;
    final start = list.first.value;
    final best = personalBest(s, entries)!;
    if (!isBetter(s, target, start)) return isBetter(s, best, target) || best == target ? 1 : 0;
    return ((best - start) / (target - start)).clamp(0.0, 1.0);
  }

  /// Число без лишних нулей или время: 12.0 → «12», 12.5 → «12,5», 95 сек → «1:35».
  static String formatValue(Skill s, double v) {
    if (s.timed) return clock(v.round());
    final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() < 10 ? 2 : 1);
    final trimmed = text.contains('.') ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : text;
    return trimmed.replaceAll('.', ',');
  }

  static String formatWithUnit(Skill s, double v) =>
      s.timed || s.unit.isEmpty ? formatValue(s, v) : '${formatValue(s, v)} ${s.unit}';

  /// «1:35», «95», «1:02:05», «12,5» → число (для времени — секунды).
  static double? parseValue(String text, {required bool timed}) {
    final t = text.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (t.isEmpty) return null;
    if (timed && t.contains(':')) {
      final parts = t.split(':').map(int.tryParse).toList();
      if (parts.any((p) => p == null || p < 0) || parts.length > 3) return null;
      var sec = 0;
      for (final p in parts) {
        sec = sec * 60 + p!;
      }
      return sec.toDouble();
    }
    final v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
    return v;
  }
}
