import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'goal_detail_screen.dart';

const _months = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

const potEmojis = ['🐷', '🏖', '🏠', '🚗', '🎓', '💍', '🛋', '💻', '✈️', '🩺', '🎁', '🛟'];

/// Семейный бюджет: доходы, расходы по категориям с лимитами и копилки.
/// Доступен только взрослым героям.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  DateTime? _month;
  bool _allCategories = false;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    if (!game.canSeeBudget) {
      return const Center(child: Text('Бюджет доступен только взрослым'));
    }
    final now = game.now;
    final month = _month ?? DateTime(now.year, now.month);
    final isCurrent = month.year == now.year && month.month == now.month;
    final sum = GameRules.monthSummary(game.money, month.year, month.month);
    final expenseCats = game.categories.where((c) => c.kind == MoneyKind.expense).toList();
    final incomeCats = game.categories.where((c) => c.kind == MoneyKind.income).toList();
    final shownCats = _allCategories
        ? expenseCats
        : expenseCats.where((c) => (sum.byCategory[c.id] ?? 0) > 0 || c.limit != null).toList();
    shownCats.sort((a, b) => (sum.byCategory[b.id] ?? 0).compareTo(sum.byCategory[a.id] ?? 0));
    final entries = game.money
        .where((m) => m.date.year == month.year && m.date.month == month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final totalLimit = expenseCats.fold<int>(0, (s, c) => s + (c.limit ?? 0));

    void shift(int delta) => setState(() => _month = DateTime(month.year, month.month + delta));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущий месяц',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => shift(-1),
            ),
            Expanded(
              child: Text(
                '${_months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Следующий месяц',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: isCurrent ? null : () => shift(1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _SummaryCard(summary: sum, totalLimit: totalLimit),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                label: 'Расход',
                icon: '➖',
                color: RqColors.danger,
                onPressed: () => openMoneyEditor(context, kind: MoneyKind.expense, month: month),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                label: 'Доход',
                icon: '➕',
                color: RqColors.xp,
                onPressed: () => openMoneyEditor(context, kind: MoneyKind.income, month: month),
              ),
            ),
          ],
        ),
        SectionTitle(
          '📊 Расходы по категориям',
          trailing: TextButton(
            onPressed: () => setState(() => _allCategories = !_allCategories),
            child: Text(_allCategories ? 'Только активные' : 'Все'),
          ),
        ),
        if (shownCats.isEmpty)
          const EmptyHint(
            emoji: '🧾',
            text: 'Расходов в этом месяце нет. Запишите первую трату или задайте лимиты категориям — нажмите «Все».',
          ),
        if (shownCats.isNotEmpty)
          RqCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (final c in shownCats) _CategoryRow(category: c, spent: sum.byCategory[c.id] ?? 0),
              ],
            ),
          ),
        if (sum.income > 0) ...[
          const SectionTitle('💼 Доходы'),
          RqCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                for (final c in incomeCats)
                  if ((sum.byCategory[c.id] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(c.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(GameRules.rub(sum.byCategory[c.id]!),
                              style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.xpDark)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
        SectionTitle(
          '🐷 Копилки',
          trailing: TextButton.icon(
            onPressed: () => openPotEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новая'),
          ),
        ),
        if (game.pots.isEmpty)
          const EmptyHint(
            emoji: '🐷',
            text: 'Копилка — накопление на большую цель. Свяжите её с легендой, например «Отпуск на море», '
                'и прогресс будет виден прямо в квесте.',
          ),
        for (final pot in game.pots) _PotCard(pot: pot, month: month),
        SectionTitle('🧾 Операции', trailing: Text('${entries.length}', style: Theme.of(context).textTheme.bodySmall)),
        if (entries.isEmpty) const EmptyHint(emoji: '📭', text: 'В этом месяце операций пока нет.'),
        for (final e in entries) _EntryTile(entry: e),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.totalLimit});

  final MonthSummary summary;
  final int totalLimit;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final onCard = p.dark ? p.ink : Colors.white;
    final soft = onCard.withValues(alpha: 0.78);
    Widget cell(String label, int value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(GameRules.rub(value),
                    style: TextStyle(color: onCard, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(p.radius + 4),
        border: p.dark ? Border.all(color: p.line) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Остаток за месяц', style: TextStyle(color: soft, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              GameRules.rub(summary.balance),
              style: TextStyle(
                color: onCard,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                fontFamily: p.fontDisplay,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              cell('Доходы', summary.income),
              cell('Расходы', summary.expense),
              cell('Отложено', summary.saved),
            ],
          ),
          if (totalLimit > 0) ...[
            const SizedBox(height: 14),
            Text('Лимиты: потрачено ${GameRules.rub(summary.expense)} из ${GameRules.rub(totalLimit)}',
                style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            RqBar(
              value: summary.expense / totalLimit,
              color: summary.expense > totalLimit ? p.danger : p.gold,
              background: onCard.withValues(alpha: 0.2),
              height: 10,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.spent});

  final BudgetCategory category;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final limit = category.limit;
    final frac = limit == null || limit == 0 ? 0.0 : spent / limit;
    final color = frac > 1
        ? RqColors.danger
        : frac > 0.8
            ? RqColors.gold
            : RqColors.primary;
    return InkWell(
      onTap: () => _editLimit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Text(category.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  limit == null ? GameRules.rub(spent) : '${GameRules.rub(spent)} / ${GameRules.rub(limit)}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: frac > 1 ? RqColors.danger : RqColors.ink),
                ),
              ],
            ),
            if (limit != null) ...[
              const SizedBox(height: 6),
              RqBar(value: frac, color: color, height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editLimit(BuildContext context) async {
    final game = GameScope.read(context);
    final ctrl = TextEditingController(text: category.limit?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${category.emoji} Лимит на месяц'),
        content: NumberField(controller: ctrl, hint: 'Например: 30000', suffix: '₽', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Без лимита')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
        ],
      ),
    );
    disposeLater(ctrl);
    if (result != null) await game.setCategoryLimit(category.id, parseAmount(result));
  }
}

class _PotCard extends StatelessWidget {
  const _PotCard({required this.pot, required this.month});

  final SavingsPot pot;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final saved = GameRules.potSaved(pot.id, game.money);
    final frac = pot.target == 0 ? 0.0 : saved / pot.target;
    final goal = game.goalById(pot.goalId);
    final full = saved >= pot.target;
    return RqCard(
      onTap: () => openPotEditor(context, pot: pot),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(pot.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pot.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(
                      goal == null ? 'Без привязки к цели' : '${goal.tier.emoji} ${goal.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text('${(frac * 100).clamp(0, 999).round()}%',
                  style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.strong(RqColors.coin))),
            ],
          ),
          const SizedBox(height: 10),
          RqBar(value: frac, color: full ? RqColors.xp : RqColors.coin),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('${GameRules.rub(saved)} из ${GameRules.rub(pot.target)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (goal != null)
                TextButton(onPressed: () => openGoal(context, goal), child: const Text('К цели')),
              TextButton.icon(
                onPressed: () => openMoneyEditor(context, kind: MoneyKind.saving, potId: pot.id, month: month),
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Пополнить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final MoneyEntry entry;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final cat = game.categoryById(entry.categoryId);
    final pot = game.potById(entry.potId);
    final who = game.heroById(entry.heroId);
    final (emoji, title) = switch (entry.kind) {
      MoneyKind.saving => (pot?.emoji ?? '🐷', 'В копилку «${pot?.name ?? '—'}»'),
      _ => (cat?.emoji ?? '📦', cat?.name ?? entry.kind.label),
    };
    final sign = entry.kind == MoneyKind.income ? '+' : '−';
    final color = switch (entry.kind) {
      MoneyKind.income => RqColors.xpDark,
      MoneyKind.expense => RqColors.ink,
      MoneyKind.saving => RqColors.strong(RqColors.coin),
    };
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: RqColors.tint(RqColors.danger, 0.2),
          borderRadius: BorderRadius.circular(RqColors.p.radius),
        ),
        child: Icon(Icons.delete_outline_rounded, color: RqColors.danger),
      ),
      onDismissed: (_) => game.deleteMoney(entry.id),
      child: RqCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    [
                      GameRules.shortDate(entry.date),
                      if (who != null) who.name,
                      if (entry.note.isNotEmpty) entry.note,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text('$sign${GameRules.rub(entry.amount)}', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------- Редакторы ----------

Future<void> openMoneyEditor(
  BuildContext context, {
  required MoneyKind kind,
  String? potId,
  DateTime? month,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(
      controller: GameScope.read(context),
      child: _MoneyEditor(kind: kind, potId: potId, month: month),
    ),
  );
}

class _MoneyEditor extends StatefulWidget {
  const _MoneyEditor({required this.kind, this.potId, this.month});

  final MoneyKind kind;
  final String? potId;
  final DateTime? month;

  @override
  State<_MoneyEditor> createState() => _MoneyEditorState();
}

class _MoneyEditorState extends State<_MoneyEditor> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late MoneyKind _kind = widget.kind;
  String? _categoryId;
  String? _potId;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _potId = widget.potId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _valid() {
    final a = parseAmount(_amount.text) ?? 0;
    if (a <= 0) return false;
    return _kind == MoneyKind.saving ? _potId != null : _categoryId != null;
  }

  Future<void> _save() async {
    if (!_valid()) return;
    final game = GameScope.read(context);
    await game.addMoney(
      kind: _kind,
      amount: parseAmount(_amount.text)!,
      categoryId: _categoryId,
      potId: _potId,
      note: _note.text,
      date: _date ?? _defaultDate(game.now),
    );
    if (mounted) Navigator.pop(context);
  }

  /// Если открыт прошлый месяц — по умолчанию ставим его последний день.
  DateTime _defaultDate(DateTime now) {
    final m = widget.month;
    if (m == null || (m.year == now.year && m.month == now.month)) return now;
    return DateTime(m.year, m.month + 1, 0, 12);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final theme = Theme.of(context);
    final cats = game.categories.where((c) => c.kind == _kind).toList();
    final date = _date ?? _defaultDate(game.now);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_kind == MoneyKind.saving ? 'Пополнить копилку' : 'Новая операция',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_kind != MoneyKind.saving)
                SegmentedButton<MoneyKind>(
                  segments: const [
                    ButtonSegment(value: MoneyKind.expense, label: Text('Расход')),
                    ButtonSegment(value: MoneyKind.income, label: Text('Доход')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _categoryId = null;
                  }),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: RqColors.ink),
                decoration: const InputDecoration(hintText: 'Сумма', suffixText: '₽'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (_kind == MoneyKind.saving)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in game.pots)
                      ChoiceChip(
                        label: Text('${p.emoji} ${p.name}'),
                        selected: _potId == p.id,
                        onSelected: (_) => setState(() => _potId = p.id),
                      ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats)
                      ChoiceChip(
                        label: Text('${c.emoji} ${c.name}'),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() => _categoryId = c.id),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Комментарий (необязательно)'),
              ),
              const SizedBox(height: 10),
              ActionChip(
                avatar: const Text('📅'),
                label: Text('${GameRules.shortDate(date)}.${date.year}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: game.now.add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, 12));
                },
              ),
              const SizedBox(height: 16),
              ChunkyButton(
                label: 'Записать',
                color: switch (_kind) {
                  MoneyKind.expense => RqColors.danger,
                  MoneyKind.income => RqColors.xp,
                  MoneyKind.saving => RqColors.coin,
                },
                onPressed: _valid() ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openPotEditor(BuildContext context, {SavingsPot? pot}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(
      controller: GameScope.read(context),
      child: _PotEditor(pot: pot),
    ),
  );
}

class _PotEditor extends StatefulWidget {
  const _PotEditor({this.pot});

  final SavingsPot? pot;

  @override
  State<_PotEditor> createState() => _PotEditorState();
}

class _PotEditorState extends State<_PotEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.pot?.name ?? '');
  late final TextEditingController _target = TextEditingController(text: widget.pot?.target.toString() ?? '');
  late String _emoji = widget.pot?.emoji ?? potEmojis.first;
  late String? _goalId = widget.pot?.goalId;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (parseAmount(_target.text) ?? 0) > 0;

  Future<void> _save() async {
    if (!_valid) return;
    final game = GameScope.read(context);
    final target = parseAmount(_target.text)!;
    if (widget.pot == null) {
      await game.addPot(name: _name.text, emoji: _emoji, target: target, goalId: _goalId);
    } else {
      await game.updatePot(widget.pot!, name: _name.text, emoji: _emoji, target: target, goalId: _goalId);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    // Финансовые цели — первыми; связать можно любую цель, кроме рутины.
    int finance(Goal g) => g.area == LifeArea.finance ? 0 : 1;
    final goals = game.goals
        .where((g) => !g.done && !g.isDaily && (game.ownPotOf(g.id) == null || g.id == widget.pot?.goalId))
        .toList()
      ..sort((a, b) {
        final f = finance(a).compareTo(finance(b));
        return f != 0 ? f : a.tier.rank.compareTo(b.tier.rank);
      });
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.pot == null ? 'Новая копилка' : 'Копилка', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.pot == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Например: Отпуск на море'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Сколько нужно накопить', suffixText: '₽'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in potEmojis)
                    ChoiceChip(
                      label: Text(e, style: const TextStyle(fontSize: 18)),
                      selected: _emoji == e,
                      onSelected: (_) => setState(() => _emoji = e),
                    ),
                ],
              ),
              if (goals.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Связать с целью', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Без цели'),
                      selected: _goalId == null,
                      onSelected: (_) => setState(() => _goalId = null),
                    ),
                    for (final g in goals)
                      ChoiceChip(
                        label: Text('${g.tier.emoji} ${g.title}', overflow: TextOverflow.ellipsis),
                        selected: _goalId == g.id,
                        onSelected: (_) => setState(() => _goalId = g.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ChunkyButton(
                label: widget.pot == null ? 'Создать копилку' : 'Сохранить',
                icon: _emoji,
                onPressed: _valid ? _save : null,
              ),
              if (widget.pot != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Удалить копилку?'),
                          content: const Text('Все пополнения этой копилки тоже будут удалены.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await game.deletePot(widget.pot!.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    child: Text('Удалить копилку', style: TextStyle(color: RqColors.danger)),
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
