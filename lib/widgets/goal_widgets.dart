import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../theme.dart';
import 'common.dart';
import 'effects.dart';

/// Круглая «галочка» выполнения.
class CheckBubble extends StatelessWidget {
  const CheckBubble({
    super.key,
    required this.done,
    required this.color,
    this.pending = false,
    this.onTap,
    this.onLongPress,
    this.count,
  });

  final bool done;
  final bool pending;
  final Color color;
  final VoidCallback? onTap;

  /// v6: снять последнюю отметку многоразовой рутины.
  final VoidCallback? onLongPress;

  /// v6: счётчик многоразовой рутины («1/3», «×2») — пока она не выполнена полностью.
  final String? count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Выполнено' : 'Отметить выполненным',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? color : RqColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: done ? RqColors.shade(color) : RqColors.tint(color, 0.6), width: 3),
          ),
          child: count != null
              ? Text(count!,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w900, color: done ? RqColors.onAccent : RqColors.strong(color)))
              : done
                  ? Icon(Icons.check_rounded, color: RqColors.onAccent, size: 22)
                  : pending
                      ? const Text('⏳', style: TextStyle(fontSize: 15))
                      : null,
        ),
      ),
    );
  }
}

/// Строка цели: галочка, название, ранг, прогресс, владелец.
class GoalTile extends StatelessWidget {
  const GoalTile({super.key, required this.goal, this.showPath = false, this.onOpen});

  final Goal goal;
  final bool showPath;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final color = RqColors.tier(goal.tier);
    final owner = game.heroById(goal.ownerId);
    final now = game.now;
    final doneToday = GameRules.isDoneToday(goal, now);
    final done = goal.isDaily ? doneToday : goal.done;
    final kids = GameRules.childrenOf(goal.id, game.goals).where((g) => !g.isDaily).toList();
    final progress = GameRules.progress(goal, game.goals);
    final path = showPath ? GameRules.ancestors(goal, game.goals) : const <Goal>[];
    final streak = goal.isDaily ? GameRules.liveStreak(goal, now) : 0;
    final due = GameRules.dueState(goal, now);
    final dueColor = switch (due) {
      DueState.overdue => RqColors.danger,
      DueState.today || DueState.soon => RqColors.gold,
      _ => RqColors.inkSoft,
    };

    final canDo = !goal.isDaily || done || GameRules.canDoNow(goal, now);
    // v6: многоразовая рутина — счётчик в галочке, нажатие отмечает ещё раз.
    final times = goal.isMulti ? GameRules.timesDone(goal, now) : 0;
    // Можно отметить ещё раз (у «без ограничения» — и после «выполнено»).
    final again = goal.isMulti && GameRules.canRepeat(goal, now);
    // Взрослым — сколько накоплено в копилке цели (из «Бюджета»).
    final pot = game.canSeeBudget ? game.ownPotOf(goal.id) : null;
    final savingPot = game.canSeeBudget ? game.potForGoal(goal.id) : null;
    final planned = goal.isDaily && GameRules.isPlannedDay(goal, now) && goal.repeat != Repeat.daily;

    Future<void> toggle() async {
      final CompletionResult r;
      if (!canDo) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📆 Это дело по расписанию: ${GameRules.scheduleLabel(goal)}')));
        return;
      }
      if (goal.isDaily) {
        // Многоразовая: каждое нажатие — ещё раз, пока не наберётся заданное число.
        r = await game.toggleDaily(goal.id);
        if (goal.isMulti && r.xp > 0 && context.mounted) {
          showReward(context, r);
          final left = goal.perPeriod == 0 ? null : goal.perPeriod - GameRules.timesDone(goal, game.now);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(left == null
                ? '✅ Отмечено: ${GameRules.timesLabel(goal, game.now)} ${GameRules.periodLabel(goal.repeat)}'
                : left > 0
                    ? '✅ ${GameRules.timesLabel(goal, game.now)} — ещё $left'
                    : '🎉 «${goal.title}» — ${GameRules.periodLabel(goal.repeat)} всё выполнено!'),
            action: SnackBarAction(label: 'Отменить', onPressed: () => game.undoDaily(goal.id)),
          ));
          return;
        }
        // Рутина накоплений («Отложить 10%») — предложить вписать сумму.
        if (savingPot != null && r.xp > 0 && context.mounted) {
          showReward(context, r);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 8),
            content: Text('${savingPot.emoji} Сколько отложили в «${savingPot.name}»?'),
            action: SnackBarAction(
              label: 'Вписать сумму',
              onPressed: () => openDeposit(context, goal, markRoutine: false),
            ),
          ));
          return;
        }
      } else if (goal.done || goal.pendingApproval) {
        await game.uncompleteGoal(goal.id);
        return;
      } else {
        r = await game.completeGoal(goal.id);
      }
      if (context.mounted) showReward(context, r);
    }

    final xpLabel = !goal.isDaily
        ? '+${goal.tier.xp}'
        : times > 0
            ? '+${GameRules.repeatAgainXp(goal)}'
            : '+${GameRules.repeatXp(goal, GameRules.nextStreak(goal, now))}';

    return RqCard(
      onTap: onOpen,
      borderColor: done ? RqColors.tint(color, 0.55) : RqColors.line,
      color: done ? RqColors.doneSurface : RqColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Opacity(
            opacity: canDo ? 1 : 0.4,
            child: CheckBubble(
              done: done,
              pending: goal.pendingApproval,
              color: color,
              onTap: toggle,
              onLongPress: times > 0 ? () => game.undoDaily(goal.id) : null,
              count: goal.isMulti && times > 0 ? GameRules.timesLabel(goal, now) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (path.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      path.map((g) => '${g.tier.emoji} ${g.title}').join('  ›  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(
                  goal.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: done ? RqColors.inkSoft : RqColors.ink,
                    decoration: done && !goal.isDaily ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TierBadge(goal.tier),
                    MiniPill(goal.stat.emoji, RqColors.stat(goal.stat)),
                    if (goal.area != null) MiniPill('${goal.area!.emoji} ${goal.area!.short}', RqColors.inkSoft),
                    if (pot != null)
                      MiniPill(
                          '${pot.emoji} ${GameRules.rub(GameRules.potSaved(pot.id, game.money))} из ${GameRules.rub(pot.target)}',
                          RqColors.coin),
                    if (goal.isFamily) MiniPill('${Words.emoji} ${Words.sharedPill}', RqColors.primary),
                    if (goal.isPrivate) MiniPill('🔒 личная', RqColors.inkSoft),
                    if (goal.isDaily)
                      MiniPill('${goal.repeat.emoji} ${GameRules.scheduleLabel(goal)}${planned && !done ? ' · сегодня!' : ''}',
                          planned && !done ? RqColors.gold : RqColors.tier(GoalTier.daily)),
                    if (goal.isDaily && streak > 0) StreakFlame(streak: streak, unit: goal.repeat.unit),
                    if (due != DueState.none) MiniPill('📅 ${GameRules.dueLabel(goal, now)}', dueColor),
                    if (goal.isMulti) MiniPill('✖️ ${GameRules.perPeriodLabel(goal)}', RqColors.tier(GoalTier.daily)),
                    if ((!done || again) && canDo) MiniPill('$xpLabel XP', RqColors.xp),
                  ],
                ),
                // v0.7: у легенд и эпиков в игровой теме — пешка на дорожке к короне.
                if (kids.isNotEmpty && RqColors.playful && (goal.tier == GoalTier.legend || goal.tier == GoalTier.epic)) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: PawnTrack(progress: progress, color: color)),
                      const SizedBox(width: 10),
                      Text('${(progress * 100).round()}%',
                          style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.strong(color))),
                    ],
                  ),
                ] else if (kids.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: RqBar(value: progress, color: color, height: 10)),
                      const SizedBox(width: 8),
                      Text('${(progress * 100).round()}%',
                          style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.strong(color))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (owner != null) ...[
            const SizedBox(width: 8),
            Tooltip(message: owner.name, child: AvatarBubble(owner.avatar, size: 34)),
          ],
        ],
      ),
    );
  }
}

/// Открыть редактор цели. Если [goal] передан — редактирование.
Future<void> openGoalEditor(
  BuildContext context, {
  Goal? goal,
  GoalTier? tier,
  String? parentId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(
      controller: GameScope.read(context),
      child: GoalEditorSheet(goal: goal, initialTier: tier, initialParentId: parentId),
    ),
  );
}

class GoalEditorSheet extends StatefulWidget {
  const GoalEditorSheet({super.key, this.goal, this.initialTier, this.initialParentId});

  final Goal? goal;
  final GoalTier? initialTier;
  final String? initialParentId;

  @override
  State<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<GoalEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late GoalTier _tier;
  String? _parentId;
  String? _ownerId;
  bool _family = false;
  HeroStat _stat = HeroStat.mastery;
  DateTime? _due;
  bool _private = false;
  Repeat _repeat = Repeat.daily;
  Set<int> _weekdays = {};
  int? _monthDay;
  LifeArea? _area;
  int _perPeriod = 1;
  bool _statTouched = false;
  final _saving = TextEditingController();
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _title = TextEditingController(text: g?.title ?? '');
    _desc = TextEditingController(text: g?.description ?? '');
    _tier = g?.tier ?? widget.initialTier ?? GoalTier.task;
    _parentId = g?.parentId ?? widget.initialParentId;
    _family = g?.isFamily ?? false;
    _stat = g?.stat ?? HeroStat.mastery;
    _ownerId = g?.ownerId;
    _due = g?.dueDate;
    _private = g?.isPrivate ?? false;
    _repeat = g?.repeat ?? Repeat.daily;
    _weekdays = {...?g?.weekdays};
    _monthDay = g?.monthDay;
    _area = g?.area;
    _perPeriod = g?.perPeriod ?? 1;
    _statTouched = g != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final game = GameScope.read(context);
    _ownerId ??= game.activeHero?.id;
    final ownPot = game.ownPotOf(widget.goal?.id);
    if (ownPot != null) _saving.text = '${ownPot.target}';
    final parent = game.goalById(_parentId);
    if (parent != null && widget.goal == null) {
      _family = parent.isFamily;
      _private = parent.isPrivate;
      _stat = parent.stat;
      _area = parent.area;
      if (!_tier.allowedParents.contains(parent.tier)) {
        // Подбираем ранг на ступень ниже родителя.
        _tier = GoalTier.values[(parent.tier.index + 1).clamp(0, GoalTier.task.index)];
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _saving.dispose();
    super.dispose();
  }

  List<Goal> _parentOptions(GameController game) {
    final banned = widget.goal == null
        ? <String>{}
        : (GameRules.descendantIds(widget.goal!.id, game.goals)..add(widget.goal!.id));
    final me = game.activeHero?.id;
    return game.goals
        .where((g) => !g.done && !g.isDaily && _tier.allowedParents.contains(g.tier) && !banned.contains(g.id))
        // Личную цель можно вложить только в свою личную, обычную — только в обычную.
        .where((g) => g.isPrivate == _private && (!g.isPrivate || g.ownerId == me))
        .toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));
  }

  Future<void> _save() async {
    final game = GameScope.read(context);
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final options = _parentOptions(game);
    final parentId = options.any((g) => g.id == _parentId) ? _parentId : null;
    final saving = parseAmount(_saving.text);
    if (widget.goal == null) {
      final created = await game.addGoal(
        title: title,
        description: _desc.text,
        tier: _tier,
        parentId: parentId,
        ownerId: _private ? game.activeHero?.id : _ownerId,
        isFamily: _family,
        isPrivate: _private,
        stat: _stat,
        dueDate: _due,
        repeat: _repeat,
        weekdays: _weekdays.toList(),
        monthDay: _monthDay,
        area: _area,
        perPeriod: _perPeriod,
      );
      if (_showSaving(game) && saving != null && saving > 0) await game.setGoalSavingTarget(created.id, saving);
    } else {
      await game.updateGoal(
        widget.goal!,
        title: title,
        description: _desc.text,
        tier: _tier,
        parentId: parentId,
        ownerId: _private ? widget.goal!.ownerId : (_ownerId ?? widget.goal!.ownerId),
        isFamily: _family,
        isPrivate: _private,
        stat: _stat,
        dueDate: _due,
        repeat: _repeat,
        weekdays: _weekdays.toList(),
        monthDay: _monthDay,
        area: _area,
        perPeriod: _perPeriod,
      );
      if (_showSaving(game)) await game.setGoalSavingTarget(widget.goal!.id, saving);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Поле «Сколько накопить» — взрослым, для финансовых целей или если копилка уже есть.
  bool _showSaving(GameController game) =>
      game.canSeeBudget &&
      _tier != GoalTier.daily &&
      (_area == LifeArea.finance || game.ownPotOf(widget.goal?.id) != null);

  Future<void> _pickDue() async {
    final now = GameScope.read(context).now;
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today.add(const Duration(days: 7)),
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365 * 10)),
      helpText: 'Срок цели',
    );
    if (picked != null) setState(() => _due = picked);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final theme = Theme.of(context);
    final parents = _parentOptions(game);
    final isEdit = widget.goal != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Изменить цель' : 'Новая цель', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: !isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _tier.hint),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Описание (необязательно)'),
              ),
              const _Label('Ранг'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in GoalTier.values)
                    ChoiceChip(
                      label: Text('${t.emoji} ${t.label}'),
                      selected: _tier == t,
                      selectedColor: RqColors.tint(RqColors.tier(t), 0.25),
                      onSelected: (_) => setState(() => _tier = t),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    _tier == GoalTier.daily
                        ? '+${_repeat.baseXp} XP и ${_repeat.coins} 🪙 за раз, бонус за серию; '
                            'прокачивает ⏰ пунктуальность, 🔁 привычку и 🧘 выдержку'
                        : '+${_tier.xp} XP и ${_tier.coins} 🪙 за выполнение · ${_tier.hint}',
                    style: theme.textTheme.bodySmall),
              ),
              if (_tier == GoalTier.daily) ...[
                const _Label('Повторять'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in Repeat.values)
                      ChoiceChip(
                        label: Text('${r.emoji} ${r.label}'),
                        selected: _repeat == r,
                        onSelected: (_) => setState(() {
                          if (_repeat != r) _weekdays = {};
                          _repeat = r;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_repeat != Repeat.monthly)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(GameRules.weekdayShort[d - 1]),
                          showCheckmark: false,
                          selected: _weekdays.contains(d),
                          onSelected: (on) => setState(() {
                            if (_repeat == Repeat.weekly) {
                              _weekdays = on ? {d} : {};
                            } else if (on) {
                              _weekdays.add(d);
                            } else {
                              _weekdays.remove(d);
                            }
                          }),
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Text('Число по плану:', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      DropdownButton<int?>(
                        value: _monthDay,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('любой день')),
                          for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d-е')),
                        ],
                        onChanged: (v) => setState(() => _monthDay = v),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    switch (_repeat) {
                      Repeat.daily => _weekdays.isEmpty
                          ? 'Каждый день. Выберите дни, если дело не ежедневное (например, пн, ср, пт).'
                          : 'Только в выбранные дни — пропуск других дней серию не сбивает.',
                      Repeat.weekly => _weekdays.isEmpty
                          ? 'Раз в неделю в любой день. Выберите день, чтобы прокачивать пунктуальность.'
                          : 'Можно сделать в любой день недели, но в выбранный — растёт ⏰ пунктуальность.',
                      Repeat.monthly => _monthDay == null
                          ? 'Раз в месяц в любой день. Выберите число, чтобы прокачивать пунктуальность.'
                          : 'Можно сделать в любой день месяца, но $_monthDay-го — растёт ⏰ пунктуальность. '
                              'Если в месяце меньше дней — последний день.',
                    },
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                // v6: сколько раз за период — решает взрослый (родитель).
                if (game.activeHero?.role.isAdult ?? false) ...[
                  _Label(switch (_repeat) {
                    Repeat.daily => 'Сколько раз в день',
                    Repeat.weekly => 'Сколько раз в неделю',
                    Repeat.monthly => 'Сколько раз в месяц',
                  }),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in const [1, 2, 3, 4, 5, 10, 0])
                        ChoiceChip(
                          label: Text(n == 0 ? '∞ без ограничения' : n == 1 ? '1 раз' : '$n ${GameRules.timesWord(n)}'),
                          selected: _perPeriod == n,
                          onSelected: (_) => setState(() => _perPeriod = n),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _perPeriod == 1
                          ? 'Один раз за период — как обычная рутина.'
                          : 'Можно отмечать несколько раз: первый раз — опыт с бонусом серии, '
                              'каждый следующий — +${_repeat.baseXp} XP и ${_repeat.coins} 🪙. '
                              '${_perPeriod == 0 ? 'Без ограничения (но не больше ${Goal.maxPerPeriod} раз).' : 'Рутина выполнена, когда отмечена $_perPeriod ${GameRules.timesWord(_perPeriod)}.'} '
                              'Например: «Почистить зубы» — 2 раза, «Стакан воды» — 8 раз.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
              if (_tier != GoalTier.legend) ...[
                _Label(_tier == GoalTier.daily ? 'Ведёт к цели (необязательно)' : 'Ведёт к цели'),
                if (parents.isEmpty)
                  Text('Пока нет подходящих целей — эта будет самостоятельной.', style: theme.textTheme.bodySmall)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Самостоятельная'),
                        selected: !parents.any((g) => g.id == _parentId),
                        onSelected: (_) => setState(() => _parentId = null),
                      ),
                      for (final p in parents)
                        ChoiceChip(
                          label: Text('${p.tier.emoji} ${p.title}', overflow: TextOverflow.ellipsis),
                          selected: _parentId == p.id,
                          selectedColor: RqColors.tint(RqColors.tier(p.tier), 0.25),
                          onSelected: (_) => setState(() {
                            _parentId = p.id;
                            if (p.isFamily) _family = true;
                          }),
                        ),
                    ],
                  ),
              ],
              if (_tier != GoalTier.daily) ...[
                const _Label('Срок'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      avatar: const Text('📅'),
                      label: Text(_due == null
                          ? 'Без срока'
                          : 'До ${GameRules.shortDate(_due!)}.${_due!.year}'),
                      onPressed: _pickDue,
                    ),
                    for (final (label, days) in const [('Сегодня', 0), ('Через неделю', 7), ('Через месяц', 30)])
                      ActionChip(
                        label: Text(label),
                        onPressed: () => setState(() {
                          final n = game.now;
                          _due = DateTime(n.year, n.month, n.day).add(Duration(days: days));
                        }),
                      ),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Убрать срок',
                        icon: Icon(Icons.close_rounded, color: RqColors.inkSoft),
                        onPressed: () => setState(() => _due = null),
                      ),
                  ],
                ),
              ],
              const _Label('Раздел жизни'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in LifeArea.values)
                    if (!a.adultOnly || (game.activeHero?.role.isAdult ?? false) || _area == a)
                      ChoiceChip(
                        label: Text('${a.emoji} ${a.short}'),
                        tooltip: a.hint,
                        selected: _area == a,
                        onSelected: (on) => setState(() {
                          _area = on ? a : null;
                          // Раздел подсказывает характеристику, пока её не выбрали вручную.
                          if (on && !_statTouched) _stat = a.stat;
                        }),
                      ),
                ],
              ),
              if (_showSaving(game)) ...[
                const _Label('💰 Сколько нужно накопить'),
                TextField(
                  controller: _saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Например: 300 000', suffixText: '₽'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'В «Бюджете» появится копилка этой цели. Отложенные деньги вписывайте прямо из цели '
                    '(«💰 Отложить») — они попадут в бюджет как пополнение копилки.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              const _Label('Прокачивает'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in HeroStat.values)
                    ChoiceChip(
                      label: Text('${s.emoji} ${s.label}'),
                      tooltip: s.hint,
                      selected: _stat == s,
                      selectedColor: RqColors.tint(RqColors.stat(s), 0.25),
                      onSelected: (_) => setState(() {
                        _stat = s;
                        _statTouched = true;
                      }),
                    ),
                ],
              ),
              if (game.heroes.length > 1 && !_private) ...[
                const _Label('Исполнитель'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in game.heroes)
                      ChoiceChip(
                        label: Text('${h.avatar} ${h.name}'),
                        selected: _ownerId == h.id,
                        onSelected: (_) => setState(() => _ownerId = h.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (!game.solo) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _family && !_private,
                  onChanged: (v) => setState(() {
                    _family = v;
                    if (v) _private = false;
                  }),
                  title: Text('${Words.emoji} ${Words.sharedGoal}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('Видна всем в ${Words.groupPrep} в общем прогрессе'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _private,
                  onChanged: (v) => setState(() {
                    _private = v;
                    if (v) _family = false;
                  }),
                  title: const Text('🔒 Личная цель', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('Видна только вам. В ленте ${Words.groupGen} — без названия'),
                ),
              ],
              const SizedBox(height: 12),
              ChunkyButton(
                label: isEdit ? 'Сохранить' : 'Создать ${_tier.label.toLowerCase()}',
                icon: _tier.emoji,
                color: RqColors.tier(_tier),
                onPressed: _title.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
      );
}


/// «💰 Отложить»: вписать сумму, отложенную на цель. Деньги попадают
/// в «Бюджет» как пополнение копилки цели (или её предка).
Future<void> openDeposit(BuildContext context, Goal goal, {bool markRoutine = true}) async {
  final game = GameScope.read(context);
  final pot = game.potForGoal(goal.id);
  if (pot == null) return;
  final amount = TextEditingController();
  final note = TextEditingController();
  final saved = GameRules.potSaved(pot.id, game.money);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${pot.emoji} Отложить'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Копилка «${pot.name}»: ${GameRules.rub(saved)} из ${GameRules.rub(pot.target)}',
              style: Theme.of(ctx).textTheme.bodySmall),
          if (pot.target > saved)
            Text('Осталось: ${GameRules.rub(pot.target - saved)}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 10),
          NumberField(controller: amount, hint: 'Сумма', suffix: '₽', autofocus: true),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(hintText: 'Комментарий (необязательно)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отложить')),
      ],
    ),
  );
  final value = parseAmount(amount.text);
  final comment = note.text;
  disposeLater(amount);
  disposeLater(note);
  if (ok != true || value == null || value <= 0) return;
  final (entry, reward) = await game.depositToGoal(goal.id, value, note: comment, markRoutine: markRoutine);
  if (!context.mounted || entry == null) return;
  if (reward.xp > 0) showReward(context, reward);
  final now = GameRules.potSaved(pot.id, game.money);
  final messenger = ScaffoldMessenger.of(context);
  Future<void>.delayed(const Duration(milliseconds: 50), () {
    messenger.showSnackBar(SnackBar(
      content: Text(now >= pot.target && pot.target > 0
          ? '🎉 Копилка «${pot.name}» наполнена: ${GameRules.rub(now)}!'
          : '${pot.emoji} +${GameRules.rub(value)} в «${pot.name}» · ${GameRules.rub(now)} из ${GameRules.rub(pot.target)}'),
    ));
  });
}

/// Задать или изменить сумму накопления на цель.
Future<void> openSavingTarget(BuildContext context, Goal goal) async {
  final game = GameScope.read(context);
  final pot = game.ownPotOf(goal.id);
  final ctrl = TextEditingController(text: pot == null ? '' : '${pot.target}');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('💰 Сколько нужно накопить'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NumberField(controller: ctrl, hint: 'Сумма', suffix: '₽', autofocus: true),
          const SizedBox(height: 8),
          Text('Копилка цели появится в «Бюджете». Пусто — отвязать копилку.',
              style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
      ],
    ),
  );
  disposeLater(ctrl);
  if (result == null) return;
  await game.setGoalSavingTarget(goal.id, parseAmount(result));
}
