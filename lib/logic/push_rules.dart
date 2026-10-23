import '../models/models.dart';
import 'time_rules.dart';

/// Что за системное уведомление.
enum PushKind { alarm, reminder, timer, deadline }

/// Как повторять уведомление, пока приложение закрыто.
enum PushRepeat {
  /// Один раз.
  none,

  /// Каждый день в это время.
  daily,

  /// Каждую неделю в этот день и время.
  weekly,
}

/// Системное уведомление, которое нужно запланировать: звонит, даже если
/// Родквест закрыт (версия 0.6).
class PlannedPush {
  const PlannedPush({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
    this.repeat = PushRepeat.none,
    this.payload = '',
  });

  /// Номер уведомления (32 бита, не меньше нуля) — один и тот же для того же звонка.
  final int id;

  /// Первый звонок (местное время).
  final DateTime at;
  final PushKind kind;
  final String title;
  final String body;
  final PushRepeat repeat;

  /// Что открыть по нажатию: id будильника, таймера или пусто.
  final String payload;

  @override
  String toString() => 'PlannedPush(${kind.name}, $at, ${repeat.name}, $title)';
}

/// Правила версии 0.6: какие системные уведомления запланировать, когда
/// приложение уходит в фон. Чистые функции — легко тестировать.
///
/// Пока приложение открыто, звонит оно само (окно будильника, плашки), а
/// запланированные уведомления снимаются — чтобы не звенело дважды.
class PushRules {
  const PushRules._();

  /// iOS хранит не больше 64 запланированных уведомлений — оставляем запас.
  static const limit = 60;

  /// Сроки целей — на сколько дней вперёд напоминать.
  static const deadlineDays = 14;

  /// Утреннее напоминание о сроках в этот час.
  static const deadlineHour = 9;

  /// Сколько звенит будильник в шторке, если его не трогать (как и окно в приложении).
  static const alarmRingFor = Duration(minutes: 3);

  /// FNV-1a (32 бита): одинаковый номер для одного и того же звонка.
  static int idFor(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Все уведомления, которые нужно запланировать на момент [now].
  static List<PlannedPush> plan({
    required List<Reminder> reminders,
    required List<ActiveTimer> timers,
    required List<Goal> goals,
    required List<HeroProfile> heroes,
    required DateTime now,
  }) {
    final out = <PlannedPush>[];
    final family = heroes.length > 1;

    String ownerOf(String heroId) {
      if (!family) return '';
      for (final h in heroes) {
        if (h.id == heroId) return ' · ${h.avatar} ${h.name}';
      }
      return '';
    }

    Goal? goalOf(String? id) {
      if (id == null) return null;
      for (final g in goals) {
        if (g.id == id) return g;
      }
      return null;
    }

    // ---------- Будильники и напоминания ----------
    for (final r in reminders) {
      if (!r.enabled) continue;
      final alarm = r.kind == ReminderKind.alarm;
      final kind = alarm ? PushKind.alarm : PushKind.reminder;
      final goal = goalOf(r.goalId);
      // Название личной цели на общем устройстве не показываем.
      final goalText = goal == null ? '' : (goal.isPrivate ? ' · 🔒 личная цель' : ' · ${goal.tier.emoji} ${goal.title}');
      final title = '${r.kind.emoji} ${r.title}';
      final body = '${r.timeLabel}${ownerOf(r.heroId)}$goalText'
          '${alarm ? '\nНажмите, чтобы выключить или отложить' : ''}';

      final snooze = r.snoozedUntil;
      if (snooze != null && snooze.isAfter(now)) {
        out.add(PlannedPush(
          id: idFor('snooze|${r.id}|${snooze.toIso8601String()}'),
          at: snooze,
          kind: kind,
          title: title,
          body: '💤 ${r.snoozeMinutes} мин прошло${ownerOf(r.heroId)}$goalText',
          payload: r.id,
        ));
      }

      if (r.oneTime) {
        final t = TimeRules.nextOccurrence(r, now);
        if (t != null && t.isAfter(now)) {
          out.add(PlannedPush(
            id: idFor('once|${r.id}|${t.toIso8601String()}'),
            at: t,
            kind: kind,
            title: title,
            body: body,
            payload: r.id,
          ));
        }
        continue;
      }

      if (r.weekdays.isEmpty) {
        final t = _nextOn(r, now, null);
        out.add(PlannedPush(
          id: idFor('daily|${r.id}|${r.timeLabel}'),
          at: t,
          kind: kind,
          title: title,
          body: body,
          repeat: PushRepeat.daily,
          payload: r.id,
        ));
      } else {
        for (final d in r.weekdays) {
          final t = _nextOn(r, now, d);
          out.add(PlannedPush(
            id: idFor('weekly|${r.id}|$d|${r.timeLabel}'),
            at: t,
            kind: kind,
            title: title,
            body: body,
            repeat: PushRepeat.weekly,
            payload: r.id,
          ));
        }
      }
    }

    // ---------- Таймеры «Успеть за время» ----------
    for (final t in timers) {
      if (t.mode != TimerMode.countdown || t.paused || t.rang) continue;
      final end = t.startedAt.add(Duration(seconds: t.plannedSec + t.pausedSec));
      if (!end.isAfter(now)) continue;
      out.add(PlannedPush(
        id: idFor('timer|${t.id}'),
        at: end,
        kind: PushKind.timer,
        title: '⏳ Время вышло',
        body: '«${t.title}» · ${TimeRules.minutesLabel(t.plannedSec)}${ownerOf(t.heroId)}',
        payload: t.id,
      ));
    }

    // ---------- Сроки целей: утром в день срока ----------
    final byDay = <DateTime, List<Goal>>{};
    final today = DateTime(now.year, now.month, now.day);
    for (final g in goals) {
      final due = g.dueDate;
      if (g.done || g.isDaily || due == null) continue;
      final day = DateTime(due.year, due.month, due.day);
      if (day.isBefore(today) || day.difference(today).inDays >= deadlineDays) continue;
      byDay.putIfAbsent(day, () => []).add(g);
    }
    for (final e in byDay.entries) {
      final at = DateTime(e.key.year, e.key.month, e.key.day, deadlineHour);
      if (!at.isAfter(now)) continue;
      final open = e.value.where((g) => !g.isPrivate).map((g) => '«${g.title}»').toList();
      final hidden = e.value.length - open.length;
      final names = [
        ...open.take(3),
        if (open.length > 3) 'ещё ${open.length - 3}',
        if (hidden > 0) '🔒 личных: $hidden',
      ].join(', ');
      out.add(PlannedPush(
        id: idFor('due|${e.key.year}-${_two(e.key.month)}-${_two(e.key.day)}'),
        at: at,
        kind: PushKind.deadline,
        title: e.value.length == 1 ? '⏰ Срок сегодня' : '⏰ Сроки сегодня: ${e.value.length}',
        body: names,
      ));
    }

    // Самые важные — будильники, затем ближайшие по времени.
    int weight(PlannedPush p) => switch (p.kind) {
          PushKind.alarm => 0,
          PushKind.timer => 1,
          PushKind.reminder => 2,
          PushKind.deadline => 3,
        };
    out.sort((a, b) {
      final w = weight(a).compareTo(weight(b));
      return w != 0 ? w : a.at.compareTo(b.at);
    });
    final kept = out.take(limit).toList()..sort((a, b) => a.at.compareTo(b.at));
    return kept;
  }

  /// Ближайший звонок строго после [now] — в любой день или в день недели [weekday].
  static DateTime _nextOn(Reminder r, DateTime now, int? weekday) {
    for (var i = 0; i <= 8; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      if (weekday != null && day.weekday != weekday) continue;
      final t = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (t.isAfter(now)) return t;
    }
    // Сюда не попадаем: за 8 дней нужный день недели всегда найдётся.
    return DateTime(now.year, now.month, now.day + 7, r.hour, r.minute);
  }
}
