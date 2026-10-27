import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../state/game_controller.dart';
import '../sync/alliance.dart';
import '../sync/cloud_scope.dart';
import '../sync/sync_api.dart';
import '../sync/sync_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shop_screen.dart';

/// v0.9: гильдия — союз семей, кланов и одиночных героев ради общих целей.
///
/// Открывается карточкой на вкладке «Семья» («Клан»), а в личном режиме
/// «Только я» — отдельной вкладкой «Гильдия».
Future<void> openAlliance(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Гильдия')),
        body: const SafeArea(top: false, child: AllianceView()),
      ),
    ));

/// Гербы гильдии на выбор.
const allianceEmblems = ['🏰', '🐺', '🦅', '🐻', '🦁', '🐉', '🌲', '⛵', '🔥', '⭐', '🛡', '🌊'];

/// Значки целей гильдии на выбор.
const allyGoalEmojis = ['🎯', '🏃', '📚', '💪', '🚶', '🧹', '🌳', '🚴', '🧘', '💧', '🍎', '🎨'];

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

/// Выполнить действие гильдии: ошибку сервера показать понятным текстом.
Future<bool> _run(BuildContext context, Future<void> Function() job, {String? done}) async {
  try {
    await job();
    if (context.mounted && done != null) _snack(context, done);
    return true;
  } on SyncError catch (e) {
    if (context.mounted) {
      _snack(context, e.code == 'bad_op' ? '⚠️ Сервер ещё не умеет гильдии — обновите его (rodquest_deploy.bat)' : '⚠️ ${e.message}');
    }
    return false;
  }
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inHours < 1) return '${d.inMinutes} мин назад';
  if (d.inDays < 1) return '${d.inHours} ч назад';
  if (d.inDays == 1) return 'вчера';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
}

// ---------- карточка на вкладке семьи ----------

/// Карточка гильдии на вкладке «Семья» («Клан»).
class AllianceCard extends StatelessWidget {
  const AllianceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context);
    if (cloud == null) return const SizedBox.shrink();
    final a = cloud.alliance;
    final theme = Theme.of(context);
    return RqCard(
      onTap: () => openAlliance(context),
      color: RqColors.tint(RqColors.gold, 0.12),
      borderColor: RqColors.tint(RqColors.gold, 0.5),
      child: Row(
        children: [
          Text(a?.emblem ?? '🏰', style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a == null ? 'Гильдия' : 'Гильдия «${a.name}»', style: theme.textTheme.titleMedium),
                Text(
                  a == null
                      ? 'Объединитесь с другими семьями, кланами и героями ради общих целей'
                      : '${a.members.length} ${_membersWord(a.members.length)} · '
                          '${a.activeGoals.length} ${_goalsWord(a.activeGoals.length)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
        ],
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

String _membersWord(int n) => _plural(n, 'участник', 'участника', 'участников');
String _goalsWord(int n) => _plural(n, 'цель', 'цели', 'целей');
String _heroesWord(int n) => _plural(n, 'герой', 'героя', 'героев');

// ---------- экран гильдии ----------

class AllianceView extends StatefulWidget {
  const AllianceView({super.key, this.showShop = false});

  /// Личный режим: вкладка «Гильдия» заменяет «Лавку» — показать вход в лавку.
  final bool showShop;

  @override
  State<AllianceView> createState() => _AllianceViewState();
}

class _AllianceViewState extends State<AllianceView> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Открыли экран — забрать свежую гильдию (тихо: без сети покажем, что было).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cloud = CloudScope.read(context);
      if (cloud == null || !cloud.connected) return;
      try {
        await cloud.refreshAlliance();
      } on SyncError catch (_) {}
    });
  }

  Future<void> _go(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _run(context, job, done: done);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context);
    final game = GameScope.of(context);
    final me = game.activeHero;
    final children = <Widget>[
      if (widget.showShop && me != null) _ShopEntry(game: game),
    ];
    if (cloud == null || me == null) {
      children.add(const EmptyHint(
          emoji: '🏰', text: 'Гильдии работают через облако, а в этой сборке оно не настроено.'));
    } else {
      final a = cloud.alliance;
      children.addAll(a == null ? _intro(cloud, game) : _guild(cloud, game, a));
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (cloud != null && cloud.connected) await _run(context, cloud.refreshAlliance);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: children,
      ),
    );
  }

  // ----- ещё не в гильдии -----

  List<Widget> _intro(SyncEngine cloud, GameController game) {
    final theme = Theme.of(context);
    final can = cloud.canManageMembership;
    return [
      RqCard(
        color: RqColors.p.tintCard,
        borderColor: RqColors.p.tintCardBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🏰 Гильдия — союз героев', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'В гильдию вступают целые семьи и кланы, а ещё — одиночные герои. Вместе ставьте большие '
              'цели: «1000 км пешком», «100 книг за год», «Посадить аллею» — каждый вносит свой вклад '
              'и получает опыт, а прогресс виден всем.\n\n'
              'Глава гильдии раздаёт участникам права: приглашать, ставить цели, писать объявления.',
            ),
          ],
        ),
      ),
      if (can) ...[
        ChunkyButton(
          label: _busy ? 'Минутку…' : 'Основать гильдию',
          icon: '🏰',
          onPressed: _busy ? null : () => _create(cloud),
        ),
        const SizedBox(height: 10),
        ChunkyButton(
          label: 'У меня есть код гильдии',
          icon: '🎟',
          color: RqColors.inkSoft,
          onPressed: _busy ? null : () => _join(cloud),
        ),
        if (!cloud.connected)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              game.solo
                  ? 'Гильдия живёт в облаке — ваш личный путь подключится к нему автоматически.'
                  : 'Гильдия живёт в облаке — ${Words.groupLower} подключится к нему автоматически.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ] else
        EmptyHint(
            emoji: '🛡',
            text: cloud.kidDevice
                ? 'Когда ${Words.leader.toLowerCase()} вступит в гильдию, здесь появятся её цели — вносите вклад!'
                : 'Основать гильдию или вступить в неё может ${Words.leader.toLowerCase()}.'),
    ];
  }

  Future<void> _create(SyncEngine cloud) async {
    final r = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => const _AllianceSettingsDialog(title: 'Новая гильдия', action: 'Основать'),
    );
    if (r == null || !mounted) return;
    await _go(() => cloud.createAlliance(name: r.$1, emblem: r.$2, motto: r.$3),
        done: '${r.$2} Гильдия «${r.$1}» основана! Пригласите другие семьи и кланы');
  }

  Future<void> _join(SyncEngine cloud) async {
    final code = await _askText(context,
        title: '🎟 Вступить в гильдию',
        text: 'Код из 8 символов даёт глава гильдии (или тот, кому он разрешил приглашать). '
            '${GameScope.read(context).solo ? 'Вы вступите как одиночный герой.' : 'Вы вступите всей ${Words.groupIns}.'}',
        hint: 'ABCD-EFGH',
        action: 'Вступить');
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _go(() => cloud.joinAlliance(code), done: '🎉 Добро пожаловать в гильдию!');
  }

  // ----- в гильдии -----

  List<Widget> _guild(SyncEngine cloud, GameController game, Alliance a) {
    final theme = Theme.of(context);
    final myRef = cloud.myRef;
    final now = game.now;
    final roleLabel = a.isLeader(myRef)
        ? '👑 Глава гильдии'
        : a.isOfficer(myRef)
            ? '🎖 С правами: ${[for (final p in a.perms[myRef] ?? const <AllyPerm>{}) p.emoji].join(' ')}'
            : '🛡 Участник';
    final active = a.activeGoals;
    final done = a.doneGoals;
    final totals = a.totals.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return [
      RqCard(
        color: RqColors.tint(RqColors.gold, 0.12),
        borderColor: RqColors.tint(RqColors.gold, 0.5),
        child: Row(
          children: [
            Text(a.emblem, style: const TextStyle(fontSize: 46)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: theme.textTheme.titleLarge),
                  if (a.motto.isNotEmpty) Text('«${a.motto}»', style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 4),
                  Text(
                    '${a.members.length} ${_membersWord(a.members.length)} · ${a.heroCount} ${_heroesWord(a.heroCount)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  MiniPill(roleLabel, RqColors.primary),
                ],
              ),
            ),
            if (a.can(myRef, AllyPerm.settings))
              IconButton(
                tooltip: 'Название и герб',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => _settings(cloud, a),
              ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (a.can(myRef, AllyPerm.invite))
            ActionChip(avatar: const Text('🎟'), label: const Text('Пригласить'), onPressed: () => _invite(cloud)),
          if (a.can(myRef, AllyPerm.goals))
            ActionChip(avatar: const Text('🎯'), label: const Text('Новая цель'), onPressed: () => _editGoal(cloud)),
          if (a.can(myRef, AllyPerm.announce))
            ActionChip(avatar: const Text('📣'), label: const Text('Объявление'), onPressed: () => _announce(cloud)),
        ],
      ),
      const SectionTitle('🎯 Цели гильдии'),
      if (active.isEmpty)
        EmptyHint(
            emoji: '🎯',
            text: a.can(myRef, AllyPerm.goals)
                ? 'Поставьте первую общую цель — например, «Пройти 1000 км» или «Прочитать 100 книг».'
                : 'Пока целей нет. Их ставит глава гильдии или тот, кому он дал это право.'),
      for (final g in active) _GoalCard(goal: g, alliance: a, cloud: cloud, onEdit: () => _editGoal(cloud, goal: g)),
      if (done.isNotEmpty) ...[
        SectionTitle('🏆 Выполнено: ${done.length}'),
        for (final g in done.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(g.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('${g.total} ${g.unit}', style: theme.textTheme.bodySmall),
                if (g.doneAt != null) Text('  ${_date(g.doneAt!)}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
      const SectionTitle('🛡 Участники'),
      for (final m in a.members) _MemberCard(member: m, alliance: a, cloud: cloud),
      if (totals.isNotEmpty) ...[
        const SectionTitle('🏅 Лучшие вкладчики'),
        RqCard(
          child: Column(
            children: [
              for (final (i, e) in totals.take(10).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 30,
                          child: Text(switch (i) { 0 => '🥇', 1 => '🥈', 2 => '🥉', _ => '${i + 1}.' })),
                      Text(a.hero(e.key)?.$2.avatar ?? '❔', style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a.heroName(e.key)} · ${a.hero(e.key)?.$1.name ?? 'ушёл из гильдии'}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: e.key == myRef ? FontWeight.w900 : FontWeight.w600),
                        ),
                      ),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      const SectionTitle('📣 Лента гильдии'),
      if (a.feed.isEmpty) const EmptyHint(emoji: '📭', text: 'Пока тихо.'),
      for (final f in a.feed.take(30)) _FeedRow(item: f, alliance: a, now: now),
      if (cloud.canManageMembership) ...[
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : () => _leave(cloud, a),
            icon: Icon(Icons.logout_rounded, color: RqColors.danger),
            label: Text(
              a.isLeader(myRef) && a.members.length == 1 ? 'Распустить гильдию' : 'Выйти из гильдии',
              style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ];
  }

  Future<void> _settings(SyncEngine cloud, Alliance a) async {
    final r = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _AllianceSettingsDialog(
          title: 'Гильдия', action: 'Сохранить', name: a.name, emblem: a.emblem, motto: a.motto),
    );
    if (r == null || !mounted) return;
    await _go(() => cloud.allianceSettings(name: r.$1, emblem: r.$2, motto: r.$3), done: 'Сохранено');
  }

  Future<void> _invite(SyncEngine cloud) async {
    Invite? inv;
    await _go(() async => inv = await cloud.allianceInvite());
    final invite = inv;
    if (invite == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎟 Код в гильдию'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Передайте код главе другой семьи или клана либо одиночному герою. '
                'Ввести его: «Гильдия» → «У меня есть код гильдии».'),
            const SizedBox(height: 16),
            SelectableText(
              invite.pretty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 3, color: RqColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Код одноразовый: одна семья, клан или герой. Действует до ${_date(invite.expiresAt)}.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.pretty));
              _snack(context, '📋 Код скопирован');
            },
            child: const Text('Копировать'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
        ],
      ),
    );
  }

  Future<void> _announce(SyncEngine cloud) async {
    final text = await _askText(context,
        title: '📣 Объявление', text: 'Его увидят все в гильдии.', hint: 'В субботу — общий забег!', action: 'Опубликовать');
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _go(() => cloud.announce(text.trim()), done: '📣 Опубликовано');
  }

  Future<void> _editGoal(SyncEngine cloud, {AllyGoal? goal}) async {
    final r = await showModalBottomSheet<_GoalDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GoalEditor(goal: goal),
    );
    if (r == null || !mounted) return;
    if (r.delete && goal != null) {
      await _go(() => cloud.deleteAllyGoal(goal.id), done: 'Цель удалена');
      return;
    }
    await _go(
      () => cloud.saveAllyGoal(
        id: goal?.id,
        title: r.title,
        emoji: r.emoji,
        target: r.target,
        unit: r.unit,
        description: r.description,
        deadline: r.deadline,
      ),
      done: goal == null ? '🎯 Цель гильдии поставлена' : 'Сохранено',
    );
  }

  Future<void> _leave(SyncEngine cloud, Alliance a) async {
    final dissolve = a.isLeader(cloud.myRef) && a.members.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dissolve ? 'Распустить гильдию?' : 'Выйти из гильдии?'),
        content: Text(dissolve
            ? 'Вы последний участник — гильдия «${a.name}» и её цели будут удалены.'
            : a.isLeader(cloud.myRef)
                ? 'Сначала передайте главенство другому взрослому: «Участники» → герой → «Сделать главой».'
                : '${GameScope.read(context).solo ? 'Вы' : 'Вся ${Words.groupLower}'} выйдете из гильдии «${a.name}». '
                    'Опыт за вклады останется у героев.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          if (dissolve || !a.isLeader(cloud.myRef))
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dissolve ? 'Распустить' : 'Выйти', style: TextStyle(color: RqColors.danger)),
            ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _go(() => cloud.leaveAlliance(), done: dissolve ? 'Гильдия распущена' : 'Вы вышли из гильдии');
  }
}

/// Вход в лавку наград в личном режиме (вкладка «Гильдия» заменила «Лавку»).
class _ShopEntry extends StatelessWidget {
  const _ShopEntry({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return RqCard(
      onTap: () => openShop(context),
      child: Row(
        children: [
          const Text('🏪', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Награды себе', style: Theme.of(context).textTheme.titleMedium),
                Text('${game.rewards.length} в лавке · тратьте монеты на приятное',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
        ],
      ),
    );
  }
}

// ---------- цель гильдии ----------

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.alliance, required this.cloud, required this.onEdit});

  final AllyGoal goal;
  final Alliance alliance;
  final SyncEngine cloud;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mine = goal.contrib[cloud.myRef] ?? 0;
    final c = RqColors.gold;
    final byMember = [
      for (final m in alliance.members)
        if (goal.byMember(m.space) > 0) (m, goal.byMember(m.space)),
    ]..sort((x, y) => y.$2.compareTo(x.$2));
    final now = GameScope.of(context).now;
    final overdue = goal.deadline != null && goal.deadline!.isBefore(now);
    return RqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(goal.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(child: Text(goal.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              if (alliance.can(cloud.myRef, AllyPerm.goals))
                IconButton(tooltip: 'Изменить', icon: const Icon(Icons.edit_rounded, size: 20), onPressed: onEdit),
            ],
          ),
          if (goal.description.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(goal.description)),
          Row(
            children: [
              Expanded(child: RqBar(value: goal.progress, color: c)),
              const SizedBox(width: 10),
              Text('${goal.total} / ${goal.target} ${goal.unit}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (goal.deadline != null)
                MiniPill('📅 до ${_date(goal.deadline!)}', overdue ? RqColors.danger : RqColors.inkSoft),
              if (mine > 0) MiniPill('ваш вклад: $mine', RqColors.xp),
              for (final (m, n) in byMember.take(4)) MiniPill('${m.emoji} ${m.name}: $n', RqColors.primary),
            ],
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'Внести вклад  +${GameController.guildXp} XP',
            icon: '🤝',
            color: c,
            onPressed: () => _contribute(context),
          ),
        ],
      ),
    );
  }

  Future<void> _contribute(BuildContext context) async {
    final amount = await showDialog<int>(context: context, builder: (_) => _ContributeDialog(goal: goal));
    if (amount == null || amount <= 0 || !context.mounted) return;
    CompletionResult? r;
    final ok = await _run(context, () async => r = await cloud.contribute(goal, amount));
    if (!ok || !context.mounted) return;
    final res = r;
    if (res != null) showReward(context, res);
    if (goal.total + amount >= goal.target && context.mounted) {
      _snack(context, '🏆 Цель гильдии «${goal.title}» выполнена!');
    } else if (res != null && res.xp == 0 && context.mounted) {
      _snack(context, '🤝 Вклад принят! Опыт за вклады сегодня уже получен — завтра снова');
    }
  }
}

class _ContributeDialog extends StatefulWidget {
  const _ContributeDialog({required this.goal});

  final AllyGoal goal;

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  final _ctrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    final quick = {1, 5, 10, if (g.left > 0 && g.left <= 1000) g.left}.toList()..sort();
    return AlertDialog(
      title: Text('${g.emoji} ${g.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Сколько вы сделали? Осталось ${g.left} ${g.unit}.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final n in quick)
                ActionChip(label: Text(n == g.left ? 'всё: $n' : '+$n'), onPressed: () => _ctrl.text = '$n'),
            ],
          ),
          const SizedBox(height: 8),
          NumberField(controller: _ctrl, hint: 'Сколько', suffix: g.unit, autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, parseAmount(_ctrl.text)), child: const Text('Внести')),
      ],
    );
  }
}

class _GoalDraft {
  const _GoalDraft({
    required this.title,
    required this.emoji,
    required this.target,
    required this.unit,
    required this.description,
    required this.deadline,
    this.delete = false,
  });

  final String title;
  final String emoji;
  final int target;
  final String unit;
  final String description;
  final DateTime? deadline;
  final bool delete;
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.goal});

  final AllyGoal? goal;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _target = TextEditingController(text: widget.goal == null ? '' : '${widget.goal!.target}');
  late final _unit = TextEditingController(text: widget.goal?.unit ?? 'раз');
  late final _desc = TextEditingController(text: widget.goal?.description ?? '');
  late String _emoji = widget.goal?.emoji ?? allyGoalEmojis.first;
  late DateTime? _deadline = widget.goal?.deadline;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _unit.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && (parseAmount(_target.text) ?? 0) > 0;

  void _save() {
    if (!_valid) return;
    Navigator.pop(
      context,
      _GoalDraft(
        title: _title.text.trim(),
        emoji: _emoji,
        target: parseAmount(_target.text)!,
        unit: _unit.text.trim().isEmpty ? 'раз' : _unit.text.trim(),
        description: _desc.text.trim(),
        deadline: _deadline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = GameScope.of(context).now;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.goal == null ? 'Новая цель гильдии' : 'Цель гильдии', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                autofocus: widget.goal == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Например: Пройти вместе 1000 км'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _target,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Сколько: 1000'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      decoration: const InputDecoration(hintText: 'Чего: км, книг, раз'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Описание (необязательно)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in allyGoalEmojis)
                    ChoiceChip(label: Text(e), selected: _emoji == e, onSelected: (_) => setState(() => _emoji = e)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Text('📅'),
                    label: Text(_deadline == null ? 'Без срока' : 'До ${_date(_deadline!)}'),
                    onPressed: () async {
                      final today = DateTime(now.year, now.month, now.day);
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _deadline ?? today.add(const Duration(days: 30)),
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365 * 3)),
                        helpText: 'Срок цели гильдии',
                      );
                      if (d != null) setState(() => _deadline = DateTime(d.year, d.month, d.day, 23, 59));
                    },
                  ),
                  if (_deadline != null)
                    IconButton(
                      tooltip: 'Убрать срок',
                      icon: Icon(Icons.close_rounded, color: RqColors.inkSoft),
                      onPressed: () => setState(() => _deadline = null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ChunkyButton(
                label: widget.goal == null ? 'Поставить цель' : 'Сохранить',
                icon: _emoji,
                color: RqColors.gold,
                onPressed: _valid ? _save : null,
              ),
              if (widget.goal != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _GoalDraft(title: '', emoji: '', target: 0, unit: '', description: '', deadline: null, delete: true),
                    ),
                    child: Text('Удалить цель', style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- участники и права ----------

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.alliance, required this.cloud});

  final AllyMember member;
  final Alliance alliance;
  final SyncEngine cloud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leaderHere = alliance.leader.startsWith('${member.space}|');
    final me = member.space == cloud.mySpace;
    return RqCard(
      borderColor: me ? RqColors.tint(RqColors.primary, 0.5) : RqColors.line,
      onTap: () => _openMember(context),
      child: Row(
        children: [
          AvatarBubble(member.emoji, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${member.name}${me ? ' (вы)' : ''}${leaderHere ? ' 👑' : ''}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(
                  '${member.kind.emoji} ${member.kind.label}'
                  '${member.kind == AllyKind.solo ? '' : ' · ${member.heroes.length} ${_heroesWord(member.heroes.length)}'}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final h in member.heroes)
                      Text(
                        '${h.avatar}${alliance.isOfficer(member.refOf(h.id)) && !alliance.isLeader(member.refOf(h.id)) ? '🎖' : ''}',
                        style: const TextStyle(fontSize: 18),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
        ],
      ),
    );
  }

  void _openMember(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CloudScope(
        cloud: cloud,
        child: GameScope(controller: GameScope.read(context), child: _MemberSheet(space: member.space)),
      ),
    );
  }
}

/// Участник гильдии: его герои, их права; у главы — выдать права,
/// передать главенство; у кого есть право — исключить.
class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.space});

  final String space;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context)!;
    final a = cloud.alliance;
    final m = a?.member(space);
    if (a == null || m == null) {
      return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('Участник покинул гильдию')));
    }
    final myRef = cloud.myRef;
    final iAmLeader = a.isLeader(myRef);
    final leaderHere = a.leader.startsWith('$space|');
    final canKick = a.can(myRef, AllyPerm.members) && !leaderHere && space != cloud.mySpace && cloud.canManageMembership;
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('${m.emoji} ${m.name}', style: theme.textTheme.headlineSmall),
            Text('${m.kind.label} · в гильдии с ${_date(m.joinedAt)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final h in m.heroes) _HeroPerms(alliance: a, member: m, hero: h, editable: iAmLeader && cloud.canManageMembership),
            if (iAmLeader)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Права даёт только глава гильдии и только взрослым. Юнги вносят вклад в цели без прав управления.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (canKick) ...[
              const SizedBox(height: 12),
              ChunkyButton(
                label: 'Исключить из гильдии',
                icon: '🚪',
                color: RqColors.danger,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Исключить «${m.name}»?'),
                      content: const Text('Их вклад в цели останется в общем счёте.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Исключить', style: TextStyle(color: RqColors.danger)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  final done = await _run(context, () => cloud.kickFromAlliance(space), done: 'Исключены из гильдии');
                  if (done && context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroPerms extends StatelessWidget {
  const _HeroPerms({required this.alliance, required this.member, required this.hero, required this.editable});

  final Alliance alliance;
  final AllyMember member;
  final AllyHero hero;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context)!;
    final ref = member.refOf(hero.id);
    final isLeader = alliance.isLeader(ref);
    final perms = alliance.perms[ref] ?? const <AllyPerm>{};
    final theme = Theme.of(context);
    return RqCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(hero.avatar, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${hero.name}${hero.kid ? ' · юнга' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (isLeader) MiniPill('👑 Глава гильдии', RqColors.gold),
            ],
          ),
          if (!isLeader && !hero.kid) ...[
            const SizedBox(height: 8),
            if (editable)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in AllyPerm.values)
                    FilterChip(
                      label: Text('${p.emoji} ${p.label}'),
                      tooltip: p.hint,
                      selected: perms.contains(p),
                      onSelected: (on) => _run(
                        context,
                        () => cloud.setAllyPerms(ref, on ? {...perms, p} : ({...perms}..remove(p))),
                      ),
                    ),
                  ActionChip(
                    avatar: const Text('🎖'),
                    label: const Text('Все права'),
                    onPressed: () => _run(context, () => cloud.setAllyPerms(ref, AllyPerm.values.toSet())),
                  ),
                  ActionChip(
                    avatar: const Text('👑'),
                    label: const Text('Сделать главой'),
                    onPressed: () => _transfer(context, cloud, ref),
                  ),
                ],
              )
            else
              Text(
                perms.isEmpty ? 'Без прав управления' : [for (final p in perms) '${p.emoji} ${p.label}'].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _transfer(BuildContext context, SyncEngine cloud, String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сделать главой: ${hero.name}?'),
        content: const Text('Новый глава получит все права. Вы останетесь в гильдии с полными правами заместителя — '
            'новый глава сможет их изменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Передать')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, () => cloud.transferAlliance(ref), done: '👑 Главенство передано');
    }
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.item, required this.alliance, required this.now});

  final AllyFeed item;
  final Alliance alliance;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final who = alliance.hero(item.who);
    final name = who?.$2.name ?? (item.name.isEmpty ? 'Герой' : item.name);
    final from = who == null ? '' : ' (${who.$1.name})';
    final announce = item.emoji == '📣';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarBubble(who?.$2.avatar ?? item.emoji, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$name$from', style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(
                    text: announce ? ': 📣 ${item.text}' : ' ${item.text} ${item.emoji}',
                    style: announce ? const TextStyle(fontWeight: FontWeight.w700) : null,
                  ),
                ])),
                Text(_ago(item.at, now), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- диалоги ----------

class _AllianceSettingsDialog extends StatefulWidget {
  const _AllianceSettingsDialog({
    required this.title,
    required this.action,
    this.name = '',
    this.emblem = '🏰',
    this.motto = '',
  });

  final String title;
  final String action;
  final String name;
  final String emblem;
  final String motto;

  @override
  State<_AllianceSettingsDialog> createState() => _AllianceSettingsDialogState();
}

class _AllianceSettingsDialogState extends State<_AllianceSettingsDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _motto = TextEditingController(text: widget.motto);
  late String _emblem = widget.emblem;

  @override
  void dispose() {
    _name.dispose();
    _motto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.name.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Название: Северный союз'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motto,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Девиз (необязательно)'),
            ),
            const SizedBox(height: 12),
            const Text('Герб', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in allianceEmblems)
                  ChoiceChip(label: Text(e), selected: _emblem == e, onSelected: (_) => setState(() => _emblem = e)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_name.text.trim(), _emblem, _motto.text.trim())),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String text,
  required String hint,
  required String action,
}) async {
  final ctrl = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(action)),
      ],
    ),
  );
  disposeLater(ctrl);
  return v;
}
