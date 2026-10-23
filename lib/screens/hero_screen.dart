import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/backup_ui.dart';
import '../widgets/common.dart';
import '../widgets/pin_pad.dart';
import 'alarms_screen.dart';
import 'guild_screen.dart';
import 'skills_screen.dart';
import 'stats_screen.dart';
import 'timer_screen.dart';
import 'today_screen.dart';

class HeroScreen extends StatelessWidget {
  const HeroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final achievements = game.achievementsOf(hero)
      // Сначала полученные (по ступени), затем самые близкие к получению.
      ..sort((a, b) {
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        if (a.level != b.level) return b.level.compareTo(a.level);
        return b.progress.compareTo(a.progress);
      });
    final unlocked = achievements.where((a) => a.unlocked).length;
    final medals = achievements.fold<int>(0, (s, a) => s + a.level);
    final maxMedals = achievements.fold<int>(0, (s, a) => s + a.maxLevel);
    final weekXp = GameRules.periodStats(
            game.records, GameRules.dayStart(game.now).subtract(const Duration(days: 6)), 7,
            heroId: hero.id)
        .xp;
    final activeStreak = GameRules.activityStreak(game.records, game.now, heroId: hero.id);
    final maxStat = hero.statXp.values.fold<int>(0, (m, v) => v > m ? v : m);
    final done = game.goals.where((g) => g.done && g.completedById == hero.id).length;
    final bestStreak = game.goals
        .where((g) => g.isDaily && g.ownerId == hero.id)
        .fold<int>(0, (m, g) => g.bestStreak > m ? g.bestStreak : m);
    final skills = game.skillsOf(hero.id).length;
    final pbs = game.skillEntries.where((e) => e.heroId == hero.id && e.pb).length;
    final alarmsOn = game.remindersOf(hero.id).where((r) => r.enabled).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        HeroHeaderCard(hero: hero),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatBox(emoji: '✅', value: '$done', label: 'выполнено')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(emoji: '🔥', value: '$bestStreak', label: 'лучшая серия')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(emoji: '🪙', value: '${hero.coins}', label: 'монет')),
          ],
        ),
        const SizedBox(height: 12),
        RqCard(
          onTap: () => openStats(context),
          child: Row(
            children: [
              const Text('📈', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Статистика', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '$weekXp XP за неделю'
                      '${activeStreak > 0 ? ' · $activeStreak дн. подряд в игре' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
            ],
          ),
        ),
        RqCard(
          onTap: () => openSkills(context),
          child: Row(
            children: [
              const Text('🏅', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Навыки и рекорды', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      skills == 0
                          ? 'Отжимания, бег, скорость печати — следите за личными рекордами'
                          : 'Навыков: $skills · рекордов: $pbs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
            ],
          ),
        ),
        RqCard(
          onTap: () => openAlarms(context),
          child: Row(
            children: [
              const Text('⏰', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Будильники и напоминания', style: Theme.of(context).textTheme.titleMedium),
                    Text('Включено: $alarmsOn', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
            ],
          ),
        ),
        const SectionTitle('⏱ Таймеры'),
        const SessionHistory(limit: 5),
        SectionTitle('🧭 Черты характера',
            trailing: Tooltip(
              message: 'Растут от регулярных дел: рутины по дням, неделям и месяцам',
              child: Icon(Icons.info_outline_rounded, size: 18, color: RqColors.inkSoft),
            )),
        RqCard(
          child: Column(
            children: [
              for (final t in HeroTrait.values)
                Builder(builder: (context) {
                  final lvl = GameRules.traitLevel(hero.traitXp[t] ?? 0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 34, child: Text(t.emoji, style: const TextStyle(fontSize: 22))),
                        SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text(t.hint, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RqBar(value: lvl.fraction, color: RqColors.gold, height: 10),
                              const SizedBox(height: 2),
                              Text('${lvl.xpInLevel}/${lvl.xpNeeded}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          child: Text('ур. ${lvl.level}',
                              textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SectionTitle('📊 Характеристики'),
        RqCard(
          child: Column(
            children: [
              for (final s in HeroStat.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 34, child: Text(s.emoji, style: const TextStyle(fontSize: 22))),
                      SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text(s.hint, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RqBar(
                          value: maxStat == 0 ? 0 : (hero.statXp[s] ?? 0) / maxStat,
                          color: RqColors.stat(s),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text('${hero.statXp[s] ?? 0}',
                            textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionTitle('🏆 Достижения',
            trailing: Tooltip(
              message: 'Получено достижений: $unlocked из ${achievements.length}, ступеней: $medals из $maxMedals',
              child: Text('$unlocked/${achievements.length} · 🏅 $medals/$maxMedals',
                  style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.inkSoft)),
            )),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 600 ? 4 : 3;
            final w = (c.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final a in achievements) SizedBox(width: w, child: _AchievementTile(a))],
            );
          },
        ),
        const SectionTitle('⚙️ Профиль'),
        RqCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: const Text('✏️', style: TextStyle(fontSize: 22)),
                title: const Text('Изменить имя и аватар', style: TextStyle(fontWeight: FontWeight.w800)),
                onTap: () => openHeroEditor(context, hero: hero),
              ),
              ListTile(
                leading: Text(hero.skin.emoji, style: const TextStyle(fontSize: 22)),
                title: const Text('Тема оформления', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(hero.skin == AppSkin.auto
                    ? 'Авто · сейчас «${hero.resolvedSkin.label}»'
                    : '${hero.skin.label} · ${hero.skin.hint}'),
                onTap: () => openSkinPicker(context, hero),
              ),
              if (game.solo)
                ListTile(
                  leading: const Text('🛡', style: TextStyle(fontSize: 22)),
                  title: const Text('Пригласить семью', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Личный путь станет гильдией: цели и прогресс сохранятся'),
                  onTap: () => _toFamily(context),
                )
              else if (hero.role.canApprove && game.heroes.length == 1)
                ListTile(
                  leading: const Text('🧭', style: TextStyle(fontSize: 22)),
                  title: const Text('Личный режим «Только я»', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Без гильдии и семейных целей. Семью можно пригласить позже'),
                  onTap: () => game.setSolo(true),
                ),
              if (hero.role.canApprove && !game.solo)
                ListTile(
                  leading: Text(game.hasParentPin ? '🔐' : '🔓', style: const TextStyle(fontSize: 22)),
                  title: const Text('PIN родителя', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(game.hasParentPin
                      ? 'Включён: юнги входят во взрослые профили только по PIN'
                      : 'Выключен: юнга может переключиться на профиль взрослого'),
                  onTap: () => openPinSettings(context),
                ),
              if (game.canBackup) ...[
                ListTile(
                  leading: const Text('💾', style: TextStyle(fontSize: 22)),
                  title: const Text('Сохранить резервную копию', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Все данные в файл: герои, цели, бюджет, будильники'),
                  onTap: () => exportBackupFlow(context),
                ),
                ListTile(
                  leading: const Text('📂', style: TextStyle(fontSize: 22)),
                  title: const Text('Восстановить из копии', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Перенос на новое устройство или откат. Заменит данные здесь'),
                  onTap: () => importBackupFlow(context),
                ),
              ],
              if (hero.role.canApprove)
                ListTile(
                  leading: const Text('🧹', style: TextStyle(fontSize: 22)),
                  title: Text('Сбросить все данные',
                      style: TextStyle(fontWeight: FontWeight.w800, color: RqColors.danger)),
                  subtitle: const Text('Удалит гильдию, героев и цели на этом устройстве'),
                  onTap: () => _confirmReset(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('Родквест v0.7 · данные хранятся на этом устройстве',
            style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }

  Future<void> _toFamily(BuildContext context) async {
    final game = GameScope.read(context);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название гильдии'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Например: Дом Смелых'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Основать')),
        ],
      ),
    );
    disposeLater(ctrl);
    if (name == null || name.trim().isEmpty) return;
    await game.setSolo(false, guildName: name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🛡 Гильдия основана! Добавьте близких на вкладке «Гильдия»')));
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final game = GameScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить всё?'),
        content: const Text('Гильдия, герои и все цели будут удалены. Вернуть их можно только из резервной копии.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Сбросить', style: TextStyle(color: RqColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await game.resetAll();
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.emoji, required this.value, required this.label});

  final String emoji;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RqCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.a);

  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    return Tooltip(
      message: a.description,
      child: RqCard(
        margin: EdgeInsets.zero,
        onTap: () => _showAchievement(context, a),
        color: a.unlocked ? p.highlightBg : p.surface,
        borderColor: a.unlocked ? p.highlightBorder : p.line,
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: a.unlocked ? 1 : 0.4,
                  child: Text(a.unlocked ? a.emoji : '🔒', style: const TextStyle(fontSize: 28)),
                ),
                if (a.medal.isNotEmpty)
                  Positioned(right: -14, bottom: -4, child: Text(a.medal, style: const TextStyle(fontSize: 16))),
              ],
            ),
            const SizedBox(height: 4),
            Text(a.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: a.unlocked ? p.ink : p.inkSoft,
                )),
            const SizedBox(height: 6),
            if (a.maxed)
              Text(a.tiered ? 'золото' : 'получено',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.xpDark))
            else ...[
              RqBar(value: a.progress, height: 6, color: p.gold),
              const SizedBox(height: 2),
              Text('${a.value.clamp(0, a.nextTarget!)}/${a.nextTarget}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Подробности достижения: все ступени и текущий прогресс.
void _showAchievement(BuildContext context, Achievement a) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${a.unlocked ? a.emoji : '🔒'} ${a.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, t) in a.thresholds.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Opacity(
                      opacity: a.level > i ? 1 : 0.35,
                      child: Text(a.tiered ? const ['🥉', '🥈', '🥇'][i] : '🏆', style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  Expanded(child: Text(a.describe(t))),
                  Text(a.level > i ? '✓' : '',
                      style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.xpDark)),
                ],
              ),
            ),
          if (!a.maxed) ...[
            const SizedBox(height: 10),
            RqBar(value: a.progress, height: 10, color: RqColors.gold),
            const SizedBox(height: 4),
            Text('Сейчас: ${a.value} из ${a.nextTarget}', style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
    ),
  );
}

/// Выбор темы оформления для героя.
Future<void> openSkinPicker(BuildContext context, HeroProfile hero) {
  final game = GameScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Тема оформления', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('У каждого героя своя тема — она включается, когда вы играете за него.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final (title, group) in [
              ('', [AppSkin.auto]),
              ('🎮 Игровые', [for (final s in AppSkin.values) if (s != AppSkin.auto && !s.adult) s]),
              ('🖋 Строгие — для взрослых', [for (final s in AppSkin.values) if (s.adult) s]),
            ]) ...[
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(title, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                ),
              for (final s in group)
                SkinOption(
                  skin: s,
                  role: hero.role,
                  selected: hero.skin == s,
                  onTap: () {
                    Navigator.pop(ctx);
                    game.updateHero(hero, skin: s);
                  },
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Карточка темы с мини-превью её цветов.
class SkinOption extends StatelessWidget {
  const SkinOption({super.key, required this.skin, required this.role, required this.selected, required this.onTap});

  final AppSkin skin;
  final HeroRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = RqPalette.of(skin.resolve(role));
    return RqCard(
      onTap: onTap,
      borderColor: selected ? RqColors.primary : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 44,
            decoration: BoxDecoration(
              color: pal.background,
              borderRadius: BorderRadius.circular(pal.radius / 2),
              border: Border.all(color: pal.line),
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (final c in [pal.primary, pal.tiers[GoalTier.legend]!, pal.xp])
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(pal.playful ? 8 : 3)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${skin.emoji} ${skin.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(skin.hint, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: RqColors.primary),
        ],
      ),
    );
  }
}
