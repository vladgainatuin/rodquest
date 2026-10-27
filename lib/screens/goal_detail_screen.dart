import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/goal_widgets.dart';
import 'alarms_screen.dart';
import 'timer_screen.dart';

void openGoal(BuildContext context, Goal goal) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: goal.id)),
  );
}

class GoalDetailScreen extends StatelessWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final goal = game.goalById(goalId);
    if (goal == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Цель удалена')));
    }
    final color = RqColors.tier(goal.tier);
    final kids = GameRules.childrenOf(goal.id, game.goals);
    final steps = kids.where((k) => !k.isDaily).toList();
    final path = GameRules.ancestors(goal, game.goals);
    final progress = GameRules.progress(goal, game.goals);
    final owner = game.heroById(goal.ownerId);
    final canEdit = game.canEdit(goal);
    final nextTier = goal.tier == GoalTier.task || goal.isDaily
        ? null
        : GoalTier.values[goal.tier.index + 1];

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.tier.label),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Изменить',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => openGoalEditor(context, goal: goal),
            ),
          if (canEdit)
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Удалить цель?'),
                    content: Text(kids.isEmpty
                        ? '«${goal.title}» будет удалена.'
                        : '«${goal.title}» и все вложенные цели (${GameRules.descendantIds(goal.id, game.goals).length}) будут удалены.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Удалить', style: TextStyle(color: RqColors.danger)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.pop(context);
                  await game.deleteGoal(goal.id);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (path.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in path)
                  ActionChip(
                    label: Text('${p.tier.emoji} ${p.title}'),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: p.id)),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          RqCard(
            borderColor: RqColors.tint(color, 0.6),
            color: Color.alphaBlend(RqColors.tint(color, 0.08), RqColors.surface),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(goal.tier.emoji, style: const TextStyle(fontSize: 40)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(goal.title, style: Theme.of(context).textTheme.headlineSmall),
                    ),
                  ],
                ),
                if (goal.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(goal.description),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TierBadge(goal.tier),
                    Chip(label: Text('${goal.stat.emoji} ${goal.stat.label}')),
                    if (goal.area != null) Chip(label: Text('${goal.area!.emoji} ${goal.area!.label}')),
                    if (owner != null) Chip(label: Text('${owner.avatar} ${owner.name}')),
                    if (goal.isFamily) Chip(label: Text('${Words.emoji} ${Words.sharedGoal}')),
                    if (goal.isPrivate) const Chip(label: Text('🔒 Личная')),
                    if (goal.isDaily) ...[
                      Chip(label: Text('${goal.repeat.emoji} ${GameRules.scheduleLabel(goal)}')),
                      Chip(
                          label: Text('🔥 серия ${GameRules.liveStreak(goal, game.now)} ${goal.repeat.unit}'
                              ' · рекорд ${goal.bestStreak}')),
                    ],
                    if (goal.dueDate != null)
                      Chip(
                        label: Text('📅 ${GameRules.dueLabel(goal, game.now)}'),
                        labelStyle: GameRules.dueState(goal, game.now) == DueState.overdue
                            ? TextStyle(color: RqColors.danger, fontWeight: FontWeight.w900)
                            : null,
                      ),
                  ],
                ),
                if ((game.canSeeBudget ? game.potForGoal(goal.id) : null) case final pot?) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _PotProgress(pot: pot, inherited: pot.goalId != goal.id),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Text('💰'),
                        label: const Text('Отложить'),
                        onPressed: () => openDeposit(context, goal),
                      ),
                      if (pot.goalId == goal.id)
                        ActionChip(
                          avatar: const Text('✏️'),
                          label: const Text('Изменить сумму'),
                          onPressed: () => openSavingTarget(context, goal),
                        ),
                    ],
                  ),
                ] else if (game.canSeeBudget && !goal.isDaily && !goal.done && canEdit) ...[
                  const SizedBox(height: 10),
                  ActionChip(
                    avatar: const Text('💰'),
                    label: const Text('Накопить сумму на цель'),
                    onPressed: () => openSavingTarget(context, goal),
                  ),
                ],
                if (!goal.isDaily) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: RqBar(value: progress, color: color, height: 16)),
                      const SizedBox(width: 10),
                      Text('${(progress * 100).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                if (goal.isDaily && goal.isMulti) ...[
                  // v6: многоразовая рутина — «Ещё раз» и «Отменить последнее».
                  Text(
                    '${GameRules.perPeriodLabel(goal)} · ${GameRules.periodLabel(goal.repeat)}: '
                    '${GameRules.timesLabel(goal, game.now)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ChunkyButton(
                    label: !GameRules.canDoNow(goal, game.now)
                        ? 'Сегодня не по расписанию'
                        : GameRules.canRepeat(goal, game.now)
                            ? (GameRules.timesDone(goal, game.now) == 0
                                ? 'Выполнить ${GameRules.periodLabel(goal.repeat)}'
                                : 'Ещё раз  +${GameRules.repeatAgainXp(goal)} XP')
                            : 'Всё выполнено ${GameRules.periodLabel(goal.repeat)} ✓',
                    icon: goal.repeat.emoji,
                    color: color,
                    onPressed: GameRules.canRepeat(goal, game.now)
                        ? () async {
                            final r = await game.toggleDaily(goal.id);
                            if (context.mounted) showReward(context, r);
                          }
                        : null,
                  ),
                  if (GameRules.timesDone(goal, game.now) > 0)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => game.undoDaily(goal.id),
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Отменить последнюю отметку'),
                      ),
                    ),
                ] else if (goal.isDaily) ...[
                  ChunkyButton(
                    label: GameRules.isDoneToday(goal, game.now)
                        ? 'Выполнено ${GameRules.periodLabel(goal.repeat)} ✓'
                        : GameRules.canDoNow(goal, game.now)
                            ? 'Выполнить ${GameRules.periodLabel(goal.repeat)}'
                            : 'Сегодня не по расписанию',
                    icon: goal.repeat.emoji,
                    color: color,
                    onPressed: GameRules.isDoneToday(goal, game.now) || GameRules.canDoNow(goal, game.now)
                        ? () async {
                            final r = await game.toggleDaily(goal.id);
                            if (context.mounted) showReward(context, r);
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    goal.repeat == Repeat.daily
                        ? '⏰ Пунктуальность, 🔁 привычка и 🧘 выдержка растут с каждым выполнением по расписанию.'
                        : GameRules.isPlannedDay(goal, game.now)
                            ? '⏰ Сегодня день по плану — выполните сейчас, чтобы прокачать пунктуальность.'
                            : '🔁 Привычка и 🧘 выдержка растут за выполнение в любой день периода, '
                                '⏰ пунктуальность — только в день по плану.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]
                else if (goal.done)
                  ChunkyButton(
                    label: 'Вернуть в работу',
                    icon: '↩️',
                    color: RqColors.inkSoft,
                    onPressed: canEdit ? () => game.uncompleteGoal(goal.id) : null,
                  )
                else if (goal.pendingApproval)
                  Text('⏳ Ждёт подтверждения: ${Words.leader.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w800))
                else
                  ChunkyButton(
                    label: 'Выполнить  +${goal.tier.xp} XP · ${goal.tier.coins} 🪙',
                    icon: '✅',
                    color: RqColors.xp,
                    onPressed: () async {
                      final r = await game.completeGoal(goal.id);
                      if (context.mounted) showReward(context, r);
                    },
                  ),
                if (!goal.done && !goal.pendingApproval) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!goal.isDaily || GameRules.canDoNow(goal, game.now))
                        ActionChip(
                          avatar: const Text('⏱'),
                          label: Text(game.activeTimer?.goalId == goal.id ? 'Таймер идёт' : 'Сделать на время'),
                          onPressed: () => openTimerStart(context, goal: goal),
                        ),
                      ActionChip(
                        avatar: const Text('🔔'),
                        label: Text(game.reminders.any((r) => r.goalId == goal.id) ? 'Ещё напоминание' : 'Напомнить'),
                        onPressed: () => openReminderEditor(context, goal: goal),
                      ),
                    ],
                  ),
                ],
                if (TimeRules.bestTimeFor(goal.id, game.sessions) case final best?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('🏁 Рекорд скорости: ${TimeRules.clock(best)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                for (final r in game.reminders.where((r) => r.goalId == goal.id))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${r.kind.emoji} ${r.timeLabel} · ${TimeRules.repeatLabel(r)}${r.enabled ? '' : ' (выключено)'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (!goal.isDaily) ...[
            SectionTitle(
              steps.isEmpty ? 'Шаги к цели' : 'Шаги к цели (${steps.where((k) => k.done).length}/${steps.length})',
            ),
            if (kids.isEmpty)
              const EmptyHint(
                emoji: '🧭',
                text: 'Разбейте цель на шаги — каждый выполненный шаг двигает прогресс, '
                    'а когда все шаги готовы, цель выполнится сама.',
              ),
            for (final k in kids) GoalTile(goal: k, onOpen: () => openGoal(context, k)),
            if (nextTier != null && canEdit && !goal.done)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ChunkyButton(
                  label: 'Добавить шаг',
                  icon: '➕',
                  color: RqColors.tier(nextTier),
                  onPressed: () => openGoalEditor(context, tier: nextTier, parentId: goal.id),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Прогресс копилки, связанной с целью.
class _PotProgress extends StatelessWidget {
  const _PotProgress({required this.pot, this.inherited = false});

  final SavingsPot pot;

  /// Копилка родительской цели (шаг пополняет её).
  final bool inherited;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final saved = GameRules.potSaved(pot.id, game.money);
    final frac = pot.target == 0 ? 0.0 : saved / pot.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${pot.emoji} ${inherited ? 'Пополняет копилку' : 'Копилка'} «${pot.name}»: '
            '${GameRules.rub(saved)} из ${GameRules.rub(pot.target)}',
            style: Theme.of(context).textTheme.bodySmall),
        if (pot.target > saved)
          Text('Осталось накопить: ${GameRules.rub(pot.target - saved)}',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        RqBar(value: frac, color: RqColors.coin, height: 10),
      ],
    );
  }
}
