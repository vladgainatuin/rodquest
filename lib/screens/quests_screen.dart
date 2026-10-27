import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/goal_widgets.dart';
import 'goal_detail_screen.dart';
import 'templates_screen.dart';

enum _Filter { all, mine, family, private }

class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  _Filter _filter = _Filter.all;
  bool _showDone = false;
  LifeArea? _area;
  final Set<String> _collapsed = {};

  bool _matches(Goal g, String heroId, List<Goal> all) {
    bool self(Goal x) =>
        (_area == null || x.area == _area) &&
        switch (_filter) {
          _Filter.all => true,
          _Filter.mine => x.ownerId == heroId,
          _Filter.family => x.isFamily,
          _Filter.private => x.isPrivate,
        };
    // Цель видна, если подходит она сама или кто-то из её потомков.
    if (self(g)) return true;
    final ids = GameRules.descendantIds(g.id, all);
    return all.any((x) => ids.contains(x.id) && self(x));
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final all = game.goals;
    bool visible(Goal g) => (_showDone || !g.done) && _matches(g, hero.id, all);

    final roots = all.where((g) => g.parentId == null && !g.isDaily && visible(g)).toList()
      ..sort((a, b) {
        final r = a.tier.rank.compareTo(b.tier.rank);
        return r != 0 ? r : a.createdAt.compareTo(b.createdAt);
      });
    final looseDailies = all.where((g) => g.isDaily && g.parentId == null && visible(g)).toList();
    final counts = <LifeArea, int>{};
    for (final g in all) {
      final a = g.area;
      if (a != null && (_showDone || !g.done)) counts[a] = (counts[a] ?? 0) + 1;
    }
    final usedAreas = counts.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    if (_area != null && !usedAreas.contains(_area)) usedAreas.add(_area!);

    List<Widget> branch(Goal g, int depth) {
      final kids = GameRules.childrenOf(g.id, all).where(visible).toList();
      final open = !_collapsed.contains(g.id);
      return [
        Padding(
          padding: EdgeInsets.only(left: depth * 18.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: kids.isEmpty
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: open ? 'Свернуть' : 'Развернуть',
                        icon: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                            color: RqColors.inkSoft),
                        onPressed: () => setState(() => open ? _collapsed.add(g.id) : _collapsed.remove(g.id)),
                      ),
              ),
              Expanded(child: GoalTile(goal: g, onOpen: () => openGoal(context, g))),
            ],
          ),
        ),
        if (open) for (final k in kids) ...branch(k, depth + 1),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in _Filter.values)
              if (!game.solo || f == _Filter.all)
              ChoiceChip(
                label: Text(switch (f) {
                  _Filter.all => 'Все',
                  _Filter.mine => '${hero.avatar} Мои',
                  _Filter.family => Words.clan ? '⚔️ Клана' : '🏡 Семейные',
                  _Filter.private => '🔒 Личные',
                }),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            FilterChip(
              label: const Text('✓ Выполненные'),
              selected: _showDone,
              onSelected: (v) => setState(() => _showDone = v),
            ),
          ],
        ),
        if (usedAreas.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Все разделы'),
                    selected: _area == null,
                    onSelected: (_) => setState(() => _area = null),
                  ),
                ),
                for (final a in usedAreas)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${a.emoji} ${a.short} · ${counts[a] ?? 0}'),
                      tooltip: a.label,
                      selected: _area == a,
                      onSelected: (on) => setState(() => _area = on ? a : null),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (hero.role.isAdult) ...[
          const SizedBox(height: 8),
          RqCard(
            onTap: () => openTemplates(context, area: _area),
            color: RqColors.p.tintCard,
            borderColor: RqColors.p.tintCardBorder,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Text('📋', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Готовые планы', style: TextStyle(fontWeight: FontWeight.w900)),
                      Text('Подушка, долги, налоговый вычет, чек-ап, документы, карьера…',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (roots.isEmpty && looseDailies.isEmpty)
          const EmptyHint(
            emoji: '🗺',
            text: 'Карта квестов пуста. Начните с легенды — главной мечты, '
                'а потом разбейте её на эпики, квесты и задания.',
          ),
        for (final r in roots) ...branch(r, 0),
        if (looseDailies.isNotEmpty) ...[
          const SectionTitle('🔁 Рутина'),
          for (final d in looseDailies)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: GoalTile(goal: d, onOpen: () => openGoal(context, d)),
            ),
        ],
      ],
    );
  }
}
