import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Открыть статистику: по герою или сразу по всей семье (клану).
void openStats(BuildContext context, {bool guild = false}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Статистика')),
        body: StatsScreen(guild: guild),
      ),
    ),
  );
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.guild = false});

  final bool guild;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = 7;
  late bool _guild = widget.guild;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final now = game.now;
    final records = game.records;
    final heroId = _guild ? null : hero.id;
    final start = GameRules.dayStart(now).subtract(Duration(days: _days - 1));
    final prevStart = start.subtract(Duration(days: _days));
    final cur = GameRules.periodStats(records, start, _days, heroId: heroId);
    final prev = GameRules.periodStats(records, prevStart, _days, heroId: heroId);
    final perDay = GameRules.xpPerDay(records, start, _days, heroId: heroId);
    final streak = GameRules.activityStreak(records, now, heroId: heroId);
    final bestRun = GameRules.bestActivityRun(records, heroId: heroId);
    final bestDay = GameRules.bestWeekday(records, heroId: heroId);
    final period = _days == 7 ? 'неделю' : 'месяц';
    final focusSec = game.sessions
        .where((x) => (heroId == null || x.heroId == heroId) && GameRules.daysBetween(start, x.at) >= 0)
        .fold<int>(0, (m, x) => m + x.actualSec);
    final pbs = game.skillEntries
        .where((e) => (heroId == null || e.heroId == heroId) && e.pb && GameRules.daysBetween(start, e.at) >= 0)
        .length;
    final areaMax = cur.byArea.values.fold<int>(0, (m, v) => v > m ? v : m);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 7, label: Text('Неделя')),
                    ButtonSegment(value: 30, label: Text('Месяц')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
                if (game.heroes.length > 1)
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: false, label: Text('${hero.avatar} Я')),
                      ButtonSegment(value: true, label: Text('${Words.emoji} ${Words.group}')),
                    ],
                    selected: {_guild},
                    onSelectionChanged: (s) => setState(() => _guild = s.first),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 560 ? 4 : 2;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: w,
                    child: _Tile(
                      emoji: '✨',
                      value: '${cur.xp}',
                      label: 'XP за $period',
                      delta: GameRules.deltaPercent(cur.xp, prev.xp),
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _Tile(
                      emoji: '✅',
                      value: '${cur.goals}',
                      label: 'целей выполнено',
                      delta: GameRules.deltaPercent(cur.goals, prev.goals),
                    ),
                  ),
                  SizedBox(width: w, child: _Tile(emoji: '🔁', value: '${cur.dailies}', label: 'отметок рутины')),
                  SizedBox(
                    width: w,
                    child: _Tile(emoji: '📅', value: '${cur.activeDays} из $_days', label: 'активных дней'),
                  ),
                  SizedBox(
                    width: w,
                    child: _Tile(
                        emoji: '⏱', value: focusSec < 60 ? '0' : TimeRules.minutesLabel(focusSec), label: 'на таймере'),
                  ),
                  SizedBox(width: w, child: _Tile(emoji: '🏅', value: '$pbs', label: 'личных рекордов')),
                ],
              );
            }),
            const SectionTitle('📈 Опыт по дням'),
            RqCard(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: cur.xp == 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'За этот период опыта пока нет. Выполните задание или отметьте рутину — '
                        'и здесь появится график.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : _XpBars(values: perDay, start: start),
            ),
            RqCard(
              child: Column(
                children: [
                  _FactRow(
                    emoji: '🔥',
                    text: streak > 0 ? 'Дней подряд в игре: $streak' : 'Сегодня ещё ничего не выполнено',
                    trailing: bestRun > 0 ? 'рекорд $bestRun' : null,
                  ),
                  if (bestDay != null)
                    _FactRow(
                      emoji: '🗓',
                      text: 'Самый продуктивный день — ${GameRules.weekdayLong[bestDay - 1]}',
                    ),
                  _FactRow(emoji: '🪙', text: 'Монет заработано за $period: ${cur.coins}'),
                  if (cur.dailies > 0)
                    _FactRow(
                      emoji: '⏰',
                      text: 'Рутина в день по плану',
                      trailing: '${cur.onTime} из ${cur.dailies}',
                    ),
                ],
              ),
            ),
            if (_guild && game.heroes.length > 1) ...[
              SectionTitle('⚔️ Вклад героев за $period'),
              _HeroContribution(byHero: cur.byHero),
            ],
            const SectionTitle('📊 Опыт по характеристикам'),
            RqCard(
              child: Column(
                children: [
                  for (final s in HeroStat.values)
                    _BarRow(
                      leading: s.emoji,
                      label: s.label,
                      value: cur.byStat[s] ?? 0,
                      max: cur.byStat.values.fold<int>(0, (m, v) => v > m ? v : m),
                      color: RqColors.stat(s),
                      suffix: 'XP',
                    ),
                ],
              ),
            ),
            if (cur.byArea.isNotEmpty) ...[
              const SectionTitle('🧩 Опыт по разделам жизни'),
              RqCard(
                child: Column(
                  children: [
                    for (final a in LifeArea.values)
                      if ((cur.byArea[a] ?? 0) > 0)
                        _BarRow(
                          leading: a.emoji,
                          label: a.short,
                          value: cur.byArea[a] ?? 0,
                          max: areaMax,
                          color: RqColors.stat(a.stat),
                          suffix: 'XP',
                        ),
                  ],
                ),
              ),
            ],
            const SectionTitle('🧭 Черты характера'),
            RqCard(
              child: Column(
                children: [
                  for (final t in HeroTrait.values)
                    _BarRow(
                      leading: t.emoji,
                      label: t.label,
                      value: cur.traits[t] ?? 0,
                      max: cur.traits.values.fold<int>(0, (m, v) => v > m ? v : m),
                      color: RqColors.gold,
                      suffix: 'оч.',
                    ),
                ],
              ),
            ),
            const SectionTitle('🏅 Выполнено по рангам'),
            RqCard(
              child: Column(
                children: [
                  for (final t in GoalTier.values)
                    _FactRow(
                      emoji: t.emoji,
                      text: t.label,
                      trailing: '${cur.byTier[t] ?? 0}',
                    ),
                ],
              ),
            ),
            Center(
              child: Text(
                'Статистика ведётся с версии 0.3, черты характера — с 0.4, разделы и таймеры — с 0.5.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.emoji, required this.value, required this.label, this.delta});

  final String emoji;
  final String value;
  final String label;

  /// Изменение к прошлому периоду, %.
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    return RqCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          if (d != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              // Стрелка + слово, а не только цвет: понятно и без различения цветов.
              child: Text(
                d == 0 ? '= как в прошлый раз' : '${d > 0 ? '▲' : '▼'} ${d.abs()}% к прошлому',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: d > 0 ? RqColors.xpDark : d < 0 ? RqColors.danger : RqColors.inkSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Столбики опыта по дням. Подсказка со значением — при наведении или долгом нажатии.
class _XpBars extends StatelessWidget {
  const _XpBars({required this.values, required this.start});

  final List<int> values;
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final maxV = values.fold<int>(0, (m, v) => v > m ? v : m);
    final n = values.length;
    const chartH = 140.0;
    final small = Theme.of(context).textTheme.bodySmall;
    String dateOf(int i) => GameRules.shortDate(DateTime(start.year, start.month, start.day + i));
    String labelOf(int i) {
      final d = DateTime(start.year, start.month, start.day + i);
      if (n <= 7) return GameRules.weekdayShort[d.weekday - 1];
      // В месяце подписываем каждый 7-й день, считая от сегодня.
      return (n - 1 - i) % 7 == 0 ? GameRules.shortDate(d) : '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('макс. $maxV XP в день', style: small),
        const SizedBox(height: 8),
        SizedBox(
          height: chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Tooltip(
                    message: '${dateOf(i)}: ${values[i]} XP',
                    child: Container(
                      // Прозрачная область во всю высоту — по ней легко попасть пальцем.
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      padding: EdgeInsets.symmetric(horizontal: n <= 7 ? 6 : 1),
                      child: Container(
                        height: values[i] == 0 ? 2 : (values[i] / maxV * chartH).clamp(4.0, chartH),
                        decoration: BoxDecoration(
                          color: values[i] == 0 ? p.track : p.xp,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: p.line),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Text(
                  labelOf(i),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textAlign: TextAlign.center,
                  style: small?.copyWith(
                    fontSize: 11,
                    fontWeight: i == n - 1 ? FontWeight.w900 : null,
                    color: i == n - 1 ? p.ink : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.emoji, required this.text, this.trailing});

  final String emoji;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text(emoji, style: const TextStyle(fontSize: 20))),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (trailing != null)
            Text(trailing!, style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.inkSoft)),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.suffix = '',
  });

  final String leading;
  final String label;
  final int value;
  final int max;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text(leading, style: const TextStyle(fontSize: 20))),
          SizedBox(
            width: 104,
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(child: RqBar(value: max == 0 ? 0 : value / max, color: color, height: 12)),
          SizedBox(
            width: 70,
            child: Text('$value $suffix'.trim(),
                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _HeroContribution extends StatelessWidget {
  const _HeroContribution({required this.byHero});

  final Map<String, int> byHero;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final heroes = [...game.heroes]..sort((a, b) => (byHero[b.id] ?? 0).compareTo(byHero[a.id] ?? 0));
    final maxV = byHero.values.fold<int>(0, (m, v) => v > m ? v : m);
    final total = byHero.values.fold<int>(0, (s, v) => s + v);
    return RqCard(
      child: Column(
        children: [
          for (final h in heroes)
            _BarRow(
              leading: h.avatar,
              label: h.name,
              value: byHero[h.id] ?? 0,
              max: maxV,
              color: RqColors.primary,
              suffix: 'XP',
            ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Всего ${Words.groupLower}: $total XP', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
