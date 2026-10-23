import 'package:flutter/material.dart';

import '../data/templates.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'goal_detail_screen.dart';

void openTemplates(BuildContext context, {LifeArea? area}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TemplatesScreen(area: area)));
}

/// Готовые планы для взрослых тем: финансы, здоровье, документы, карьера…
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, this.area});

  final LifeArea? area;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late LifeArea? _area = widget.area;

  @override
  Widget build(BuildContext context) {
    final areas = {for (final t in goalTemplates) t.area}.toList()..sort((a, b) => a.index.compareTo(b.index));
    final list = goalTemplates.where((t) => _area == null || t.area == _area).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Готовые планы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  'Серьёзные взрослые темы, разложенные на шаги: деньги, здоровье, документы, карьера, дом. '
                  'План создаётся целиком — дальше его можно менять как обычные цели.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(label: const Text('Все'), selected: _area == null, onSelected: (_) => setState(() => _area = null)),
                  for (final a in areas)
                    ChoiceChip(
                      label: Text('${a.emoji} ${a.short}'),
                      selected: _area == a,
                      onSelected: (_) => setState(() => _area = a),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final t in list)
                RqCard(
                  onTap: () => _preview(context, t),
                  child: Row(
                    children: [
                      Text(t.emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(t.description, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, children: [
                              MiniPill('${t.area.emoji} ${t.area.short}', RqColors.primary),
                              MiniPill('${t.count} шагов', RqColors.inkSoft),
                            ]),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _preview(BuildContext context, GoalTemplate t) async {
    final game = GameScope.read(context);
    var family = false;
    var private = false;
    final amount = TextEditingController();
    final money = t.area == LifeArea.finance && game.canSeeBudget;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final lines = <Widget>[];
          void walk(TplNode n, int depth) {
            lines.add(Padding(
              padding: EdgeInsets.only(left: depth * 16.0, top: 3, bottom: 3),
              child: Text(
                '${n.tier.emoji} ${n.title}'
                '${n.tier == GoalTier.daily ? ' · ${n.repeat.label.toLowerCase()}' : ''}',
                style: TextStyle(fontWeight: depth == 0 ? FontWeight.w900 : FontWeight.w600),
              ),
            ));
            for (final k in n.children) {
              walk(k, depth + 1);
            }
          }

          for (final n in t.nodes) {
            walk(n, 0);
          }
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t.emoji} ${t.title}', style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(t.description, style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  RqCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
                  if (money) ...[
                    Text('💰 Сколько нужно накопить (необязательно)',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    NumberField(controller: amount, hint: 'Например: 300 000', suffix: '₽'),
                    const SizedBox(height: 4),
                    Text('В «Бюджете» появится копилка плана, а суммы можно вписывать прямо из шагов.',
                        style: Theme.of(ctx).textTheme.bodySmall),
                    const SizedBox(height: 8),
                  ],
                  if (!game.solo) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: family,
                      onChanged: (v) => setSheet(() {
                        family = v;
                        if (v) private = false;
                      }),
                      title: const Text('🛡 Семейная цель', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Идти к ней всей гильдией'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: private,
                      onChanged: (v) => setSheet(() {
                        private = v;
                        if (v) family = false;
                      }),
                      title: const Text('🔒 Личная цель', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Например, долги или здоровье — видно только вам'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ChunkyButton(label: 'Создать план', icon: '📋', onPressed: () => Navigator.pop(ctx, true)),
                ],
              ),
            ),
          );
        },
      ),
    );
    final target = parseAmount(amount.text);
    disposeLater(amount);
    if (go != true) return;
    final top = await game.applyTemplate(t, family: family, private: private);
    if (top != null && money && target != null && target > 0) await game.setGoalSavingTarget(top.id, target);
    if (!context.mounted || top == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('📋 План «${t.title}» создан: ${t.count} шагов')));
    openGoal(context, top);
  }
}
