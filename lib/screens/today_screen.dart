import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/goal_widgets.dart';
import 'alarms_screen.dart';
import 'goal_detail_screen.dart';
import 'skills_screen.dart';
import 'timer_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final now = game.now;
    final goals = game.goals;

    // Сначала невыполненные, среди них — запланированные на сегодня.
    int order(Goal a, Goal b) {
      int score(Goal g) => (GameRules.isDoneToday(g, now) ? 2 : 0) + (GameRules.isPlannedDay(g, now) ? 0 : 1);
      return score(a).compareTo(score(b));
    }

    List<Goal> routine(Repeat r) => goals
        .where((g) => g.isDaily && g.ownerId == hero.id && g.repeat == r && GameRules.isScheduledDay(g, now))
        .toList()
      ..sort(order);
    final dailies = routine(Repeat.daily);
    final weeklies = routine(Repeat.weekly);
    final monthlies = routine(Repeat.monthly);
    final reminders = GameRules.reminders(goals, now, heroId: hero.id);
    final reminderIds = reminders.map((g) => g.id).toSet();
    // «Листья» — то, что можно сделать прямо сейчас (без невыполненных подшагов).
    final active = goals
        .where((g) =>
            !g.isDaily &&
            !g.done &&
            g.ownerId == hero.id &&
            !reminderIds.contains(g.id) &&
            g.tier.rank >= GoalTier.quest.rank &&
            !GameRules.childrenOf(g.id, goals).any((k) => !k.isDaily && !k.done))
        .toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));
    final pending = hero.role.canApprove ? goals.where((g) => g.pendingApproval).toList() : const <Goal>[];
    final claims = game.canManageRewards ? game.pendingClaims : const <RewardClaim>[];
    final legends = goals.where((g) => g.tier == GoalTier.legend && !g.done).toList();
    final dailyDone = dailies.where((d) => GameRules.isDoneToday(d, now)).length;
    final overdue = reminders.where((g) => GameRules.dueState(g, now) == DueState.overdue).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        HeroHeaderCard(hero: hero),
        const SizedBox(height: 10),
        const _ToolsRow(),
        if (reminders.isNotEmpty) ...[
          SectionTitle(
            '⏰ Сроки',
            trailing: overdue > 0 ? MiniPill('просрочено: $overdue', RqColors.danger) : null,
          ),
          for (final g in reminders) GoalTile(goal: g, showPath: true, onOpen: () => openGoal(context, g)),
        ],
        if (pending.isNotEmpty) ...[
          const SectionTitle('⏳ Ждут подтверждения'),
          for (final g in pending) _ApprovalCard(goal: g),
        ],
        if (claims.isNotEmpty) ...[
          const SectionTitle('🎁 Награды к выдаче'),
          for (final c in claims) ClaimCard(claim: c),
        ],
        if (legends.isNotEmpty) ...[
          const SectionTitle('👑 Главная цель'),
          _LegendSpotlight(goal: legends.first),
        ],
        SectionTitle(
          '🔁 Рутина на сегодня',
          trailing: dailies.isEmpty
              ? null
              : Text('$dailyDone/${dailies.length}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.inkSoft)),
        ),
        if (dailies.isEmpty)
          const EmptyHint(
              emoji: '🌱',
              text: 'На сегодня рутины нет. Добавьте привычку по расписанию — '
                  'каждый день, по дням недели, раз в неделю или раз в месяц.'),
        for (final d in dailies) GoalTile(goal: d, showPath: true, onOpen: () => openGoal(context, d)),
        for (final (title, list) in [('📆 На этой неделе', weeklies), ('🗓 В этом месяце', monthlies)])
          if (list.isNotEmpty) ...[
            SectionTitle(
              title,
              trailing: Text('${list.where((g) => GameRules.isDoneToday(g, now)).length}/${list.length}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.inkSoft)),
            ),
            for (final g in list) GoalTile(goal: g, showPath: true, onOpen: () => openGoal(context, g)),
          ],
        const SectionTitle('⚔️ Можно сделать сейчас'),
        if (active.isEmpty)
          const EmptyHint(emoji: '🗺', text: 'Нет активных заданий. Загляните на вкладку «Квесты» или создайте новое.'),
        for (final g in active.take(12)) GoalTile(goal: g, showPath: true, onOpen: () => openGoal(context, g)),
      ],
    );
  }
}

class HeroHeaderCard extends StatelessWidget {
  const HeroHeaderCard({super.key, required this.hero});

  final HeroProfile hero;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final lvl = GameRules.levelFor(hero.xp);
    final onCard = p.dark ? p.ink : Colors.white;
    final soft = onCard.withValues(alpha: 0.82);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: p.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(p.radius + 4),
        border: p.dark ? Border.all(color: p.line) : null,
        boxShadow: p.playful
            ? [BoxShadow(color: p.primaryDark, offset: const Offset(0, 5))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onCard.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: onCard.withValues(alpha: 0.45), width: p.playful ? 3 : 1.5),
            ),
            child: Text(hero.avatar, style: const TextStyle(fontSize: 38)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(hero.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: onCard, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: p.fontDisplay)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: onCard.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(p.playful ? 12 : 8),
                      ),
                      child: Text('🪙 ${hero.coins}',
                          style: TextStyle(color: onCard, fontWeight: FontWeight.w900, fontSize: 13)),
                    ),
                  ],
                ),
                Text('${lvl.title} · ${hero.role.label}',
                    style: TextStyle(color: soft, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: p.gold, borderRadius: BorderRadius.circular(p.playful ? 10 : 6)),
                      child: Text('УР. ${lvl.level}',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: p.playful ? p.ink : Colors.white, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RqBar(
                        value: lvl.fraction,
                        color: p.gold,
                        background: onCard.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${lvl.xpInLevel} / ${lvl.xpNeeded} XP до следующего уровня',
                    style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendSpotlight extends StatelessWidget {
  const _LegendSpotlight({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final p = GameRules.progress(goal, game.goals);
    final c = RqColors.tier(GoalTier.legend);
    final pots = game.pots.where((x) => x.goalId == goal.id).toList();
    return RqCard(
      onTap: () => openGoal(context, goal),
      color: RqColors.p.highlightBg,
      borderColor: RqColors.p.highlightBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 10),
              Expanded(child: Text(goal.title, style: Theme.of(context).textTheme.titleLarge)),
              if (goal.isFamily) Text(Words.emoji, style: const TextStyle(fontSize: 20)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: RqBar(value: p, color: c, height: 16)),
              const SizedBox(width: 10),
              Text('${(p * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          // Взрослым показываем, сколько накоплено на эту цель.
          if (game.canSeeBudget)
            for (final pot in pots)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${pot.emoji} Накоплено ${GameRules.rub(GameRules.potSaved(pot.id, game.money))} '
                  'из ${GameRules.rub(pot.target)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final doer = game.heroById(goal.completedById);
    return RqCard(
      color: RqColors.p.warnBg,
      borderColor: RqColors.p.warnBorder,
      child: Row(
        children: [
          AvatarBubble(doer?.avatar ?? '🧒', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text('${doer?.name ?? 'Юнга'} говорит, что выполнил(а) · +${goal.tier.xp} XP',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отклонить',
            icon: Icon(Icons.close_rounded, color: RqColors.danger),
            onPressed: () => game.reject(goal.id),
          ),
          IconButton.filled(
            tooltip: 'Подтвердить',
            style: IconButton.styleFrom(backgroundColor: RqColors.xp, foregroundColor: RqColors.onAccent),
            icon: const Icon(Icons.check_rounded),
            onPressed: () async {
              final r = await game.approve(goal.id);
              if (context.mounted && r.xp > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ ${doer?.name ?? 'Юнга'} получает +${r.xp} XP и ${r.coins} 🪙'
                        '${r.badges.isEmpty ? '' : '\n🏆 И достижение: ${r.badges.map((a) => a.title).join(', ')}'}')));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Заявка на награду: взрослый выдаёт её или отказывает (монеты вернутся).
class ClaimCard extends StatelessWidget {
  const ClaimCard({super.key, required this.claim});

  final RewardClaim claim;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final who = game.heroById(claim.heroId);
    return RqCard(
      color: RqColors.p.highlightBg,
      borderColor: RqColors.p.highlightBorder,
      child: Row(
        children: [
          Text(claim.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text('${who?.avatar ?? ''} ${who?.name ?? 'Герой'} купил(а) за ${claim.cost} 🪙',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отказать (вернуть монеты)',
            icon: Icon(Icons.close_rounded, color: RqColors.danger),
            onPressed: () => game.rejectClaim(claim.id),
          ),
          IconButton.filled(
            tooltip: 'Выдать',
            style: IconButton.styleFrom(backgroundColor: RqColors.xp, foregroundColor: RqColors.onAccent),
            icon: const Icon(Icons.redeem_rounded),
            onPressed: () => game.grantClaim(claim.id),
          ),
        ],
      ),
    );
  }
}


/// Будильники, таймер и рекорды — быстрый доступ с главного экрана.
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final now = game.now;
    final next = nextReminderOf(game, hero.id);
    final timer = game.activeTimer;
    final skills = game.skillsOf(hero.id).length;
    final todayFocus = game.sessions
        .where((s) => s.heroId == hero.id && GameRules.dayKey(s.at) == GameRules.dayKey(now))
        .fold<int>(0, (m, s) => m + s.actualSec);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ToolCard(
            emoji: '⏰',
            title: 'Будильники',
            subtitle: next == null ? 'не заданы' : '${next.$1.timeLabel} · ${TimeRules.untilLabel(next.$2, now)}',
            onTap: () => openAlarms(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ToolCard(
            emoji: '⏱',
            title: 'Таймер',
            subtitle: timer != null
                ? 'идёт: ${timer.title}'
                : todayFocus >= 60
                    ? 'сегодня ${TimeRules.minutesLabel(todayFocus)}'
                    : 'дело на время',
            onTap: () => openTimerStart(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ToolCard(
            emoji: '🏅',
            title: 'Рекорды',
            subtitle: skills == 0 ? 'развивать навык' : 'навыков: $skills',
            onTap: () => openSkills(context),
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.emoji, required this.title, required this.subtitle, required this.onTap});

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RqCard(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 2),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
