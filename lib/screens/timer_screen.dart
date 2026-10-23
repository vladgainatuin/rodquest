import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/time_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Запустить таймер: для цели («Уборка за 15 минут»), навыка («Планка»)
/// или просто фокус-сессию. Если таймер уже идёт — открыть его.
Future<void> openTimerStart(BuildContext context, {Goal? goal, Skill? skill}) async {
  final game = GameScope.read(context);
  if (game.activeTimer != null) {
    openTimerScreen(context);
    return;
  }
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(controller: game, child: _TimerStartSheet(goal: goal, skill: skill)),
  );
  if (started == true && context.mounted) openTimerScreen(context);
}

void openTimerScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TimerScreen()));
}

class _TimerStartSheet extends StatefulWidget {
  const _TimerStartSheet({this.goal, this.skill});

  final Goal? goal;
  final Skill? skill;

  @override
  State<_TimerStartSheet> createState() => _TimerStartSheetState();
}

class _TimerStartSheetState extends State<_TimerStartSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.goal?.title ?? widget.skill?.name ?? '');
  final TextEditingController _minutes = TextEditingController();
  late TimerMode _mode = widget.skill != null ? TimerMode.stopwatch : TimerMode.countdown;
  int _planned = 15;
  LifeArea? _area;

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final game = GameScope.read(context);
    final custom = int.tryParse(_minutes.text.trim());
    final minutes = custom != null && custom > 0 ? custom.clamp(1, 600) : _planned;
    final t = await game.startTimer(
      title: _title.text,
      mode: _mode,
      plannedSec: minutes * 60,
      goalId: widget.goal?.id,
      skillId: widget.skill?.id,
      area: widget.goal?.area ?? widget.skill?.area ?? _area,
    );
    if (mounted) Navigator.pop(context, t != null);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final theme = Theme.of(context);
    final goal = widget.goal;
    final best = goal == null ? null : TimeRules.bestTimeFor(goal.id, game.sessions);
    final skill = widget.skill;
    final pb = skill == null ? null : TimeRules.personalBest(skill, game.skillEntries);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⏱ Таймер', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Что делаем: «Уборка», «Английский», «Отчёт»'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TimerMode>(
                showSelectedIcon: false,
                segments: [
                  for (final m in TimerMode.values) ButtonSegment(value: m, label: Text('${m.emoji} ${m.label}')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                _mode == TimerMode.countdown
                    ? 'Успейте до конца времени — бонус +${TimeRules.beatBonusXp} XP и ⚡ «Быстрее ветра». '
                        'Опыт: 1 XP за каждые 5 минут.'
                    : skill != null && skill.timed
                        ? 'Секундомер замерит результат навыка «${skill.name}» и сохранит его.'
                        : 'Считает, сколько ушло времени. Опыт: 1 XP за каждые 5 минут.',
                style: theme.textTheme.bodySmall,
              ),
              if (_mode == TimerMode.countdown) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in const [5, 10, 15, 25, 45, 60])
                      ChoiceChip(
                        label: Text('$m мин'),
                        selected: _planned == m && _minutes.text.trim().isEmpty,
                        onSelected: (_) => setState(() {
                          _planned = m;
                          _minutes.clear();
                        }),
                      ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(hintText: 'своё', suffixText: 'мин', isDense: true),
                      ),
                    ),
                  ],
                ),
              ],
              if (goal == null && skill == null) ...[
                const SizedBox(height: 14),
                Text('Раздел (необязательно)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in LifeArea.values)
                      if (!a.adultOnly || (game.activeHero?.role.isAdult ?? false))
                        ChoiceChip(
                          label: Text('${a.emoji} ${a.short}'),
                          selected: _area == a,
                          onSelected: (on) => setState(() => _area = on ? a : null),
                        ),
                  ],
                ),
              ],
              if (best != null) ...[
                const SizedBox(height: 12),
                Text('🏁 Ваш рекорд для этого дела: ${TimeRules.clock(best)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
              if (skill != null && pb != null) ...[
                const SizedBox(height: 12),
                Text('🏅 Личный рекорд: ${TimeRules.formatWithUnit(skill, pb)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 18),
              ChunkyButton(label: 'Старт', icon: '▶️', color: RqColors.xp, onPressed: _start),
            ],
          ),
        ),
      ),
    );
  }
}

/// Экран идущего таймера: большой циферблат, пауза, «Готово».
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _finish({required bool complete}) async {
    if (_busy) return;
    _busy = true;
    final game = GameScope.read(context);
    final t = game.activeTimer;
    final skill = game.skillById(t?.skillId);
    final res = await game.finishTimer(completeGoal: complete);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = res.session;
    final nav = Navigator.of(context);
    final lines = [
      if (s != null) '⏱ ${s.title}: ${TimeRules.clock(s.actualSec)}${s.beat ? ' — успели! ⚡' : ''}',
      if (res.entry != null && skill != null)
        res.entry!.pb
            ? '🏅 Новый рекорд: ${TimeRules.formatWithUnit(skill, res.entry!.value)}!'
            : '📏 Результат записан: ${TimeRules.formatWithUnit(skill, res.entry!.value)}',
      if (s != null && s.xp == 0 && s.actualSec >= TimeRules.minSessionSec)
        'Лимит опыта за таймеры на сегодня исчерпан — время всё равно записано.',
    ];
    // Всплывающий опыт показываем здесь, а окно нового уровня — уже на экране под таймером.
    final level = res.reward.newLevel;
    if (res.reward.xp > 0) showReward(context, res.reward..newLevel = null);
    nav.pop();
    if (level != null) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (nav.mounted) showLevelUp(nav.context, level);
      });
    }
    if (lines.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        messenger.showSnackBar(SnackBar(content: Text(lines.join('\n'))));
      });
    }
  }

  Future<void> _confirmCancel() async {
    final game = GameScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить таймер?'),
        content: const Text('Время не будет записано, опыт не начислится.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Сбросить', style: TextStyle(color: RqColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await game.cancelTimer();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final t = game.activeTimer;
    final p = RqColors.p;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Таймер')),
        body: const Center(child: Text('Таймер не запущен')),
      );
    }
    final now = game.now;
    final elapsed = t.elapsedSec(now);
    final countdown = t.mode == TimerMode.countdown;
    final left = t.leftSec(now);
    final over = countdown && left < 0;
    final fraction = countdown ? (elapsed / math.max(1, t.plannedSec)).clamp(0.0, 1.0) : (elapsed % 60) / 60;
    final big = countdown ? (over ? '+${TimeRules.clock(-left)}' : TimeRules.clock(left)) : TimeRules.clock(elapsed);
    final goal = game.goalById(t.goalId);
    final skill = game.skillById(t.skillId);
    final color = over ? p.danger : (countdown ? p.primary : p.xp);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.mode.label),
        actions: [
          IconButton(
            tooltip: 'Сбросить без записи',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _confirmCancel,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(t.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              if (t.area != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${t.area!.emoji} ${t.area!.label}',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: fraction,
                          strokeWidth: p.playful ? 18 : 10,
                          backgroundColor: p.track,
                          color: color,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            big,
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              fontFamily: p.fontDisplay,
                              color: over ? p.danger : p.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            t.paused
                                ? '⏸ пауза'
                                : over
                                    ? 'время вышло'
                                    : countdown
                                        ? 'из ${TimeRules.minutesLabel(t.plannedSec)}'
                                        : 'идёт',
                            style: TextStyle(fontWeight: FontWeight.w800, color: p.inkSoft),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: t.paused ? 'Продолжить' : 'Пауза',
                      icon: t.paused ? '▶️' : '⏸',
                      color: p.inkSoft,
                      onPressed: () => t.paused ? game.resumeTimer() : game.pauseTimer(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChunkyButton(
                      label: 'Стоп',
                      icon: '⏹',
                      color: p.primary,
                      onPressed: () => _finish(complete: false),
                    ),
                  ),
                ],
              ),
              if (goal != null && !goal.done) ...[
                const SizedBox(height: 12),
                ChunkyButton(
                  label: goal.isDaily ? 'Готово — отметить «${goal.title}»' : 'Готово — выполнить «${goal.title}»',
                  icon: '✅',
                  color: p.xp,
                  onPressed: () => _finish(complete: true),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                skill != null && skill.timed
                    ? 'Нажмите «Стоп» — время запишется как результат навыка «${skill.name}».'
                    : countdown
                        ? 'Успели до конца — «Стоп» или «Готово» засчитает победу над временем.'
                        : 'Таймер идёт, даже если закрыть этот экран или приложение.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плашка идущего таймера — видна на всех вкладках.
class ActiveTimerBanner extends StatefulWidget {
  const ActiveTimerBanner({super.key});

  @override
  State<ActiveTimerBanner> createState() => _ActiveTimerBannerState();
}

class _ActiveTimerBannerState extends State<ActiveTimerBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && GameScope.read(context).activeTimer != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final t = game.activeTimer;
    if (t == null) return const SizedBox.shrink();
    final now = game.now;
    final countdown = t.mode == TimerMode.countdown;
    final left = t.leftSec(now);
    final over = countdown && left < 0;
    final text = countdown
        ? (over ? 'время вышло +${TimeRules.clock(-left)}' : 'осталось ${TimeRules.clock(left)}')
        : TimeRules.clock(t.elapsedSec(now));
    final p = RqColors.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: RqCard(
        margin: EdgeInsets.zero,
        onTap: () => openTimerScreen(context),
        color: over ? p.warnBg : p.tintCard,
        borderColor: over ? p.warnBorder : p.tintCardBorder,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(t.paused ? '⏸' : t.mode.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            Text(text,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: over ? p.danger : p.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            Icon(Icons.chevron_right_rounded, color: p.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// История таймеров героя (последние сессии).
class SessionHistory extends StatelessWidget {
  const SessionHistory({super.key, this.limit = 10});

  final int limit;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final me = game.activeHero?.id;
    final list = game.sessions.where((s) => s.heroId == me).toList().reversed.take(limit).toList();
    if (list.isEmpty) {
      return const EmptyHint(emoji: '⏱', text: 'Здесь появятся ваши таймеры: сколько времени и что успели.');
    }
    return RqCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final s in list)
            ListTile(
              dense: true,
              leading: Text(s.beat ? '⚡' : s.mode.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${s.at.day.toString().padLeft(2, '0')}.${s.at.month.toString().padLeft(2, '0')} · '
                  '${TimeRules.clock(s.actualSec)}'
                  '${s.mode == TimerMode.countdown ? ' из ${TimeRules.minutesLabel(s.plannedSec)}' : ''}'),
              trailing: Text(s.xp > 0 ? '+${s.xp} XP' : '',
                  style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.xpDark)),
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Удалить запись?'),
                    content: Text('Опыт за «${s.title}» (${s.xp} XP) будет снят.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true) await game.deleteSession(s.id);
              },
            ),
        ],
      ),
    );
  }
}
