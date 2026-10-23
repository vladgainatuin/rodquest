import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/templates.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'timer_screen.dart';

void openSkills(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SkillsScreen()));
}

void openSkill(BuildContext context, Skill s) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SkillDetailScreen(skillId: s.id)));
}

/// Навыки героя и личные рекорды.
class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final skills = game.skillsOf(hero.id);
    final pbs = game.skillEntries.where((e) => e.heroId == hero.id && e.pb).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Навыки и рекорды')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: RqColors.primary,
        foregroundColor: RqColors.onAccent,
        onPressed: () => openSkillEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Навык', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Записывайте результаты — отжимания, время на километр, скорость печати. '
                  'Первый замер за день: +${TimeRules.practiceXp} XP, новый личный рекорд: '
                  '+${TimeRules.pbXp} XP и 🏅.${pbs > 0 ? ' Ваших рекордов: $pbs.' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (skills.isEmpty)
                const EmptyHint(
                  emoji: '🏅',
                  text: 'Добавьте навык, который хотите развивать, и запишите стартовый результат. '
                      'Дальше каждый рекорд — повод для гордости.',
                ),
              for (final s in skills) SkillCard(skill: s),
            ],
          ),
        ),
      ),
    );
  }
}

class SkillCard extends StatelessWidget {
  const SkillCard({super.key, required this.skill});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final entries = TimeRules.entriesOf(skill.id, game.skillEntries);
    final pb = TimeRules.personalBest(skill, game.skillEntries);
    final progress = TimeRules.targetProgress(skill, game.skillEntries);
    final color = RqColors.stat(skill.stat);
    return RqCard(
      onTap: () => openSkill(context, skill),
      child: Row(
        children: [
          Text(skill.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (pb != null) MiniPill('🏅 ${TimeRules.formatWithUnit(skill, pb)}', RqColors.gold),
                    if (entries.isNotEmpty)
                      MiniPill('последний: ${TimeRules.formatWithUnit(skill, entries.last.value)}', RqColors.inkSoft),
                    if (entries.isEmpty) MiniPill('нет замеров', RqColors.inkSoft),
                    if (skill.target != null) MiniPill('🎯 ${TimeRules.formatWithUnit(skill, skill.target!)}', color),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  RqBar(value: progress, color: color, height: 8),
                ],
              ],
            ),
          ),
          if (entries.length >= 2) ...[
            const SizedBox(width: 8),
            SizedBox(width: 70, height: 36, child: Sparkline(values: [for (final e in entries) e.value])),
          ],
        ],
      ),
    );
  }
}

/// Маленький график результатов.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color});

  final List<double> values;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparkPainter(values.length > 30 ? values.sublist(values.length - 30) : values, color ?? RqColors.primary));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - lo) / span * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

class SkillDetailScreen extends StatelessWidget {
  const SkillDetailScreen({super.key, required this.skillId});

  final String skillId;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final skill = game.skillById(skillId);
    if (skill == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Навык удалён')));
    }
    final entries = TimeRules.entriesOf(skill.id, game.skillEntries);
    final pb = TimeRules.personalBest(skill, game.skillEntries);
    final progress = TimeRules.targetProgress(skill, game.skillEntries);
    final theme = Theme.of(context);
    final color = RqColors.stat(skill.stat);

    return Scaffold(
      appBar: AppBar(
        title: Text(skill.name),
        actions: [
          IconButton(
            tooltip: 'Изменить',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => openSkillEditor(context, skill: skill),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              RqCard(
                color: RqColors.p.highlightBg,
                borderColor: RqColors.p.highlightBorder,
                child: Column(
                  children: [
                    Text(skill.emoji, style: const TextStyle(fontSize: 44)),
                    const SizedBox(height: 4),
                    Text('Личный рекорд', style: theme.textTheme.bodySmall),
                    Text(
                      pb == null ? '—' : TimeRules.formatWithUnit(skill, pb),
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, fontFamily: RqColors.p.fontDisplay),
                    ),
                    Text(skill.better == SkillBetter.higher ? 'больше — лучше' : 'меньше — лучше',
                        style: theme.textTheme.bodySmall),
                    if (skill.target != null) ...[
                      const SizedBox(height: 10),
                      Text('🎯 Цель: ${TimeRules.formatWithUnit(skill, skill.target!)}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        RqBar(value: progress, color: color, height: 12),
                      ],
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: 'Записать',
                      icon: '➕',
                      color: RqColors.xp,
                      onPressed: () => addSkillResult(context, skill),
                    ),
                  ),
                  if (skill.timed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChunkyButton(
                        label: 'Замерить',
                        icon: '⏱',
                        onPressed: () => openTimerStart(context, skill: skill),
                      ),
                    ),
                  ],
                ],
              ),
              if (entries.length >= 2) ...[
                const SectionTitle('📈 Прогресс'),
                RqCard(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: SizedBox(
                    height: 120,
                    child: Sparkline(values: [for (final e in entries) e.value], color: color),
                  ),
                ),
              ],
              SectionTitle('🗒 Замеры (${entries.length})'),
              if (entries.isEmpty)
                const EmptyHint(emoji: '📏', text: 'Запишите первый результат — это ваша стартовая точка.'),
              if (entries.isNotEmpty)
                RqCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final e in entries.reversed.take(50))
                        ListTile(
                          dense: true,
                          leading: Text(e.pb ? '🏅' : '•', style: const TextStyle(fontSize: 20)),
                          title: Text(TimeRules.formatWithUnit(skill, e.value),
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${_date(e.at)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.xp > 0)
                                Text('+${e.xp} XP',
                                    style: TextStyle(fontWeight: FontWeight.w900, color: RqColors.xpDark)),
                              IconButton(
                                tooltip: 'Удалить замер',
                                icon: Icon(Icons.close_rounded, color: RqColors.inkSoft, size: 18),
                                onPressed: () => game.deleteSkillEntry(e.id),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Диалог «Записать результат».
Future<void> addSkillResult(BuildContext context, Skill skill) async {
  final game = GameScope.read(context);
  final value = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${skill.emoji} ${skill.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: value,
            autofocus: true,
            keyboardType: skill.timed ? TextInputType.datetime : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: skill.timed ? 'Время, например 4:35' : 'Результат',
              suffixText: skill.timed ? 'мм:сс' : skill.unit,
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(hintText: 'Заметка (необязательно)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Записать')),
      ],
    ),
  );
  final v = TimeRules.parseValue(value.text, timed: skill.timed);
  final n = note.text;
  disposeLater(value);
  disposeLater(note);
  if (ok != true || v == null) return;
  final (entry, reward) = await game.addSkillEntry(skill.id, v, note: n);
  if (!context.mounted || entry == null) return;
  if (reward.xp > 0) showReward(context, reward);
  final messenger = ScaffoldMessenger.of(context);
  Future<void>.delayed(const Duration(milliseconds: 50), () {
    messenger.showSnackBar(SnackBar(
      content: Text(entry.pb
          ? '🏅 Новый личный рекорд: ${TimeRules.formatWithUnit(skill, v)}!'
          : '📏 Записано: ${TimeRules.formatWithUnit(skill, v)}'),
    ));
  });
}

Future<void> openSkillEditor(BuildContext context, {Skill? skill}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(controller: GameScope.read(context), child: _SkillEditor(skill: skill)),
  );
}

class _SkillEditor extends StatefulWidget {
  const _SkillEditor({this.skill});

  final Skill? skill;

  @override
  State<_SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends State<_SkillEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.skill?.name ?? '');
  late final TextEditingController _unit = TextEditingController(text: widget.skill?.unit ?? '');
  late final TextEditingController _target = TextEditingController(
      text: widget.skill?.target == null ? '' : TimeRules.formatValue(widget.skill!, widget.skill!.target!));
  late String _emoji = widget.skill?.emoji ?? '🏅';
  late SkillBetter _better = widget.skill?.better ?? SkillBetter.higher;
  late bool _timed = widget.skill?.timed ?? false;
  late LifeArea? _area = widget.skill?.area;

  static const _emojis = ['🏅', '💪', '🏃', '🧱', '🧗', '🚴', '🏊', '⌨️', '🗣', '📖', '🎸', '🎹', '🧩', '♟', '🎯', '🧠'];

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _target.dispose();
    super.dispose();
  }

  void _preset(SkillPreset p) => setState(() {
        _name.text = p.name;
        _emoji = p.emoji;
        _unit.text = p.unit;
        _better = p.better;
        _timed = p.timed;
        _area = p.area;
      });

  Future<void> _save() async {
    final game = GameScope.read(context);
    final target = TimeRules.parseValue(_target.text, timed: _timed);
    final s = widget.skill;
    if (s == null) {
      await game.addSkill(
          name: _name.text, emoji: _emoji, unit: _unit.text, better: _better, timed: _timed, target: target, area: _area);
    } else {
      await game.updateSkill(s,
          name: _name.text,
          emoji: _emoji,
          unit: _unit.text,
          better: _better,
          timed: _timed,
          target: target,
          stat: _area?.stat,
          area: _area);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final theme = Theme.of(context);
    final isEdit = widget.skill != null;
    final adult = game.activeHero?.role.isAdult ?? false;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Изменить навык' : 'Новый навык', style: theme.textTheme.headlineSmall),
              if (!isEdit) ...[
                label('Быстрый выбор'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in skillPresets)
                      if (adult || p.area != LifeArea.career)
                        ActionChip(label: Text('${p.emoji} ${p.name}'), onPressed: () => _preset(p)),
                  ],
                ),
              ],
              label('Название'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Например: «Отжимания»'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in _emojis)
                    ChoiceChip(
                      label: Text(e, style: const TextStyle(fontSize: 18)),
                      selected: _emoji == e,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _emoji = e),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _timed,
                onChanged: (v) => setState(() => _timed = v),
                title: const Text('⏱ Результат — время', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Замер секундомером: планка, бег, сборка кубика'),
              ),
              if (!_timed)
                TextField(
                  controller: _unit,
                  decoration: const InputDecoration(hintText: 'Единица: раз, кг, км, зн/мин'),
                ),
              label('Что лучше'),
              SegmentedButton<SkillBetter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SkillBetter.higher, label: Text('⬆ Больше')),
                  ButtonSegment(value: SkillBetter.lower, label: Text('⬇ Меньше')),
                ],
                selected: {_better},
                onSelectionChanged: (s) => setState(() => _better = s.first),
              ),
              label('Цель (необязательно)'),
              TextField(
                controller: _target,
                keyboardType: _timed ? TextInputType.datetime : const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(hintText: _timed ? 'Например 5:00' : 'Например 50', suffixText: _timed ? 'мм:сс' : _unit.text),
              ),
              label('Раздел'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in LifeArea.values)
                    if (adult || !a.adultOnly)
                      ChoiceChip(
                        label: Text('${a.emoji} ${a.short}'),
                        selected: _area == a,
                        onSelected: (on) => setState(() => _area = on ? a : null),
                      ),
                ],
              ),
              const SizedBox(height: 18),
              ChunkyButton(
                label: isEdit ? 'Сохранить' : 'Добавить навык',
                icon: _emoji,
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
              if (isEdit) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    icon: Icon(Icons.delete_outline_rounded, color: RqColors.danger),
                    label: Text('Удалить навык', style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800)),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await game.deleteSkill(widget.skill!.id);
                      nav.pop();
                    },
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
