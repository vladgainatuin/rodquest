import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/time_rules.dart';
import '../models/models.dart';
import '../screens/goal_detail_screen.dart';
import '../screens/timer_screen.dart';
import '../services/notifier.dart';
import '../state/game_controller.dart';
import '../theme.dart';
import 'common.dart';

/// Звонок будильника: окно поверх приложения со звуком, пока не выключат.
/// Возвращается, когда окно закрыто.
Future<void> showAlarmRing(BuildContext context, TickEvent e) async {
  final r = e.reminder;
  if (r == null) return;
  final game = GameScope.read(context);
  final owner = game.heroById(r.heroId);
  Notifier.show('⏰ ${r.title}', '${r.timeLabel}${owner == null ? '' : ' · ${owner.name}'}');
  final action = await showGeneralDialog<_RingAction>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Будильник',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, _, _) => GameScope(controller: game, child: _RingCard(event: e)),
    transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case _RingAction.snooze:
      await game.snooze(r.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('💤 Отложено на ${r.snoozeMinutes} мин')));
      }
    case _RingAction.dismiss || _RingAction.openGoal || _RingAction.startTimer || null:
      final res = await game.dismissAlarm(r.id, e.at);
      if (!context.mounted) return;
      if (res.xp > 0) {
        showReward(context, res);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('🌄 Подъём вовремя! +⏰ пунктуальность')));
      }
      final goal = game.goalById(r.goalId);
      if (goal != null && action == _RingAction.openGoal) openGoal(context, goal);
      if (goal != null && action == _RingAction.startTimer) await openTimerStart(context, goal: goal);
  }
}

/// Напоминание: звук, уведомление браузера и плашка внизу.
void showReminderBanner(BuildContext context, TickEvent e) {
  final game = GameScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  switch (e.kind) {
    case TickKind.reminder:
      final r = e.reminder!;
      final goal = game.goalById(r.goalId);
      Notifier.beep();
      Notifier.show('🔔 ${r.title}', goal == null ? r.timeLabel : '${goal.tier.emoji} ${goal.title}');
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('🔔 ${r.timeLabel} · ${r.title}${_owner(game, r)}'),
        action: goal == null
            ? null
            : SnackBarAction(label: 'Открыть', onPressed: () => openGoal(context, goal)),
      ));
    case TickKind.missed:
      final r = e.reminder!;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('${r.kind == ReminderKind.alarm ? '⏰ Пропущен будильник' : '🔔 Пропущено напоминание'} '
            '${r.timeLabel} · ${r.title}${_owner(game, r)}'),
      ));
    case TickKind.timerDone:
      final t = e.timer!;
      Notifier.beep(alarm: true);
      Notifier.show('⏳ Время вышло', t.title);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('⏳ Время вышло: «${t.title}» (${TimeRules.minutesLabel(t.plannedSec)})'),
        action: t.heroId == game.activeHero?.id
            ? SnackBarAction(label: 'К таймеру', onPressed: () => openTimerScreen(context))
            : null,
      ));
    case TickKind.alarm:
      break;
  }
}

String _owner(GameController game, Reminder r) {
  if (game.heroes.length < 2) return '';
  final h = game.heroById(r.heroId);
  return h == null ? '' : ' (${h.avatar} ${h.name})';
}

enum _RingAction { dismiss, snooze, openGoal, startTimer }

class _RingCard extends StatefulWidget {
  const _RingCard({required this.event});

  final TickEvent event;

  @override
  State<_RingCard> createState() => _RingCardState();
}

class _RingCardState extends State<_RingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);
  Timer? _sound;
  int _rings = 0;

  @override
  void initState() {
    super.initState();
    Notifier.beep(alarm: true);
    // Звеним каждые 3 секунды, но не дольше 3 минут.
    _sound = Timer.periodic(const Duration(seconds: 3), (t) {
      if (++_rings > 60) {
        t.cancel();
        return;
      }
      Notifier.beep(alarm: true);
    });
  }

  @override
  void dispose() {
    _sound?.cancel();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final r = widget.event.reminder!;
    final owner = game.heroById(r.heroId);
    final goal = game.goalById(r.goalId);
    final p = RqColors.p;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(p.radius + 6),
            border: Border.all(color: p.playful ? p.gold : p.line, width: p.playful ? 3 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: Tween(begin: -0.03, end: 0.03).animate(_shake),
                child: const Text('⏰', style: TextStyle(fontSize: 64)),
              ),
              Text(
                r.timeLabel,
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, fontFamily: p.fontDisplay, color: p.ink),
              ),
              Text(r.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              if (owner != null && game.heroes.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${owner.avatar} ${owner.name}', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (r.wakeUp)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Выключите в течение 10 минут — засчитаем подъём вовремя',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 18),
              ChunkyButton(
                label: r.wakeUp ? 'Я встал(а)!' : 'Выключить',
                icon: r.wakeUp ? '🌄' : '✋',
                color: p.xp,
                onPressed: () => Navigator.pop(context, _RingAction.dismiss),
              ),
              const SizedBox(height: 10),
              ChunkyButton(
                label: 'Отложить на ${r.snoozeMinutes} мин',
                icon: '💤',
                color: p.inkSoft,
                onPressed: () => Navigator.pop(context, _RingAction.snooze),
              ),
              if (goal != null && !goal.done) ...[
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, _RingAction.startTimer),
                      child: Text('⏱ «${goal.title}» на время', overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _RingAction.openGoal),
                      child: const Text('Открыть цель'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
