import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pin_pad.dart';
import 'alliance_screen.dart';
import 'cloud_screen.dart';
import 'goal_detail_screen.dart';
import 'onboarding_screen.dart';
import 'shop_screen.dart';
import 'stats_screen.dart';

/// Вкладка «Семья» («Клан»): герои, общие цели, лента, облако и вход в гильдию.
///
/// До v0.9 семья называлась гильдией. Теперь гильдия — уровень выше:
/// союз семей, кланов и одиночек (см. alliance_screen.dart).
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final me = game.activeHero!;
    final heroes = [...game.heroes]..sort((a, b) => b.xp.compareTo(a.xp));
    final totalXp = heroes.fold<int>(0, (s, h) => s + h.xp);
    final familyGoals = game.goals
        .where((g) => g.isFamily && !g.isDaily && !g.done && g.tier.rank <= GoalTier.quest.rank)
        .toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));
    final feed = game.feed.take(25).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        RqCard(
          color: RqColors.p.tintCard,
          borderColor: RqColors.p.tintCardBorder,
          child: Row(
            children: [
              Text(Words.emoji, style: const TextStyle(fontSize: 42)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.guildName, style: Theme.of(context).textTheme.titleLarge),
                    Text('${Words.group} · ${heroes.length} ${_heroWord(heroes.length)} · $totalXp XP',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (me.role.canApprove)
                IconButton(
                  tooltip: 'Переименовать',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => _renameGuild(context),
                ),
            ],
          ),
        ),
        // v0.8: синхронизация семьи.
        const CloudCard(),
        // v0.9: гильдия — союз семей, кланов и одиночек.
        const AllianceCard(),
        SectionTitle(
          '⚔️ ${Words.people}',
          trailing: me.role.canApprove
              ? TextButton.icon(
                  onPressed: () => openHeroEditor(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Добавить'),
                )
              : null,
        ),
        for (final (i, h) in heroes.indexed) _MemberTile(hero: h, place: i + 1, isMe: h.id == me.id),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openStats(context, guild: true),
            icon: const Text('📈'),
            label: Text('Итоги ${Words.groupGen}: кто сколько сделал за неделю и месяц'),
          ),
        ),
        if (me.role.isAdult) ...[
          const SectionTitle('🎁 Лавка наград'),
          RqCard(
            onTap: () => openShop(context),
            child: Row(
              children: [
                const Text('🏪', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Награды за монеты', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        game.pendingClaims.isEmpty
                            ? '${game.rewards.length} в лавке · дети тратят монеты, вы выдаёте награды'
                            : 'Ждут выдачи: ${game.pendingClaims.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
              ],
            ),
          ),
        ],
        SectionTitle('${Words.emoji} ${Words.sharedGoals}'),
        if (familyGoals.isEmpty)
          EmptyHint(
              emoji: '🤝',
              text: 'Создайте цель с отметкой «${Words.sharedGoal}» — к ней ${Words.clan ? 'пойдёт весь клан' : 'пойдёт вся семья'}.'),
        for (final g in familyGoals) _FamilyGoalCard(goal: g),
        SectionTitle('📣 Лента ${Words.groupGen}'),
        if (feed.isEmpty) const EmptyHint(emoji: '📭', text: 'Пока тихо. Выполните первое задание!'),
        for (final e in feed) _FeedTile(event: e),
      ],
    );
  }

  static String _heroWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'герой';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'героя';
    return 'героев';
  }

  Future<void> _renameGuild(BuildContext context) async {
    final game = GameScope.read(context);
    final ctrl = TextEditingController(text: game.guildName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Название ${Words.groupGen}'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
        ],
      ),
    );
    disposeLater(ctrl);
    if (name != null) await game.renameGuild(name);
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.hero, required this.place, required this.isMe});

  final HeroProfile hero;
  final int place;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final lvl = GameRules.levelFor(hero.xp);
    final medal = switch (place) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '' };
    return RqCard(
      borderColor: isMe ? RqColors.tint(RqColors.primary, 0.5) : RqColors.line,
      onTap: () => _showMemberActions(context),
      child: Row(
        children: [
          AvatarBubble(hero.avatar, size: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('${hero.name}${isMe ? ' (вы)' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    if (medal.isNotEmpty) Text(' $medal'),
                  ],
                ),
                Text('${hero.role.label} · ${lvl.title}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Ур. ${lvl.level}', style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.primary)),
                    const SizedBox(width: 6),
                    CoinBadge(hero.coins),
                    const SizedBox(width: 8),
                    Expanded(child: RqBar(value: lvl.fraction, height: 10)),
                  ],
                ),
              ],
            ),
          ),
          if (!isMe && game.heroes.length > 1) Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
        ],
      ),
    );
  }

  void _showMemberActions(BuildContext context) {
    final game = GameScope.read(context);
    final me = game.activeHero!;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${hero.avatar} ${hero.name}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (!isMe && game.canSwitchTo(hero.id))
              ListTile(
                leading: const Text('🎮', style: TextStyle(fontSize: 24)),
                title: const Text('Играть за этого героя', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(game.needsPinToSwitch(hero.id)
                    ? '🔒 Нужен PIN родителя'
                    : 'Переключить профиль на этом устройстве'),
                onTap: () {
                  Navigator.pop(ctx);
                  switchHeroGuarded(context, hero.id);
                },
              ),
            if (me.role.canApprove || isMe)
              ListTile(
                leading: const Text('✏️', style: TextStyle(fontSize: 24)),
                title: const Text('Изменить профиль', style: TextStyle(fontWeight: FontWeight.w800)),
                onTap: () {
                  Navigator.pop(ctx);
                  openHeroEditor(context, hero: hero);
                },
              ),
            if (me.role.canApprove && !isMe)
              ListTile(
                leading: const Text('🚪', style: TextStyle(fontSize: 24)),
                title: Text('Исключить из ${Words.groupGen}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: RqColors.danger)),
                subtitle: Text('Его цели перейдут: ${Words.leader.toLowerCase()}'),
                onTap: () {
                  Navigator.pop(ctx);
                  game.removeHero(hero.id);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _FamilyGoalCard extends StatelessWidget {
  const _FamilyGoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final p = GameRules.progress(goal, game.goals);
    final c = RqColors.tier(goal.tier);
    // Вклад: кто сколько шагов выполнил внутри этой цели.
    final ids = GameRules.descendantIds(goal.id, game.goals);
    final contrib = <String, int>{};
    for (final g in game.goals) {
      if (ids.contains(g.id) && g.done && g.completedById != null) {
        contrib[g.completedById!] = (contrib[g.completedById!] ?? 0) + 1;
      }
    }
    return RqCard(
      onTap: () => openGoal(context, goal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(goal.tier.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(goal.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Text('${(p * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.strong(c))),
            ],
          ),
          const SizedBox(height: 8),
          RqBar(value: p, color: c),
          if (contrib.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in contrib.entries)
                  if (game.heroById(e.key) case final h?)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${h.avatar} ${e.value}'),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.event});

  final FeedEvent event;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final h = game.heroById(event.heroId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarBubble(h?.avatar ?? '❔', size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: h?.name ?? 'Герой', style: const TextStyle(fontWeight: FontWeight.w900)),
                    TextSpan(text: ' ${event.text} ${event.emoji}'),
                  ]),
                ),
                Text(_ago(event.at, game.now), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (event.xp > 0)
            Text('+${event.xp}', style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.xpDark)),
        ],
      ),
    );
  }

  static String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'только что';
    if (d.inHours < 1) return '${d.inMinutes} мин назад';
    if (d.inDays < 1) return '${d.inHours} ч назад';
    if (d.inDays == 1) return 'вчера';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
  }
}

/// Добавить или изменить героя.
Future<void> openHeroEditor(BuildContext context, {HeroProfile? hero}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HeroEditor(hero: hero),
  );
}

class _HeroEditor extends StatefulWidget {
  const _HeroEditor({this.hero});

  final HeroProfile? hero;

  @override
  State<_HeroEditor> createState() => _HeroEditorState();
}

class _HeroEditorState extends State<_HeroEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.hero?.name ?? '');
  late String _avatar = widget.hero?.avatar ?? heroAvatars[2];
  late HeroRole _role = widget.hero?.role ?? HeroRole.child;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final game = GameScope.read(context);
    if (_name.text.trim().isEmpty) return;
    if (widget.hero == null) {
      await game.addHero(name: _name.text, avatar: _avatar, role: _role);
    } else {
      final me = game.activeHero;
      await game.updateHero(
        widget.hero!,
        name: _name.text,
        avatar: _avatar,
        role: me?.role.canApprove == true ? _role : null,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final canSetRole = game.activeHero?.role.canApprove == true;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.hero == null ? 'Новый герой' : 'Профиль героя',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.hero == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Имя: Мама, Миша, Бабушка…'),
                onChanged: (_) => setState(() {}),
              ),
              if (canSetRole) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in HeroRole.values)
                      ChoiceChip(
                        label: Text(switch (r) {
                          HeroRole.leader => '👑 ${r.label}',
                          HeroRole.member => '🗡 ${r.label}',
                          HeroRole.child => '🧒 ${r.label}',
                        }),
                        selected: _role == r,
                        onSelected: (_) => setState(() => _role = r),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_role) {
                    HeroRole.leader => 'Управляет ${Words.clan ? 'кланом' : 'семьёй'} и подтверждает задания юнг.',
                    HeroRole.member => 'Взрослый участник: выполняет и создаёт цели.',
                    HeroRole.child => 'Ребёнок: задания засчитываются после подтверждения главы.',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              AvatarPicker(selected: _avatar, onSelected: (a) => setState(() => _avatar = a)),
              const SizedBox(height: 20),
              ChunkyButton(
                label: widget.hero == null ? 'Принять в ${Words.groupAcc}' : 'Сохранить',
                icon: _avatar,
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
