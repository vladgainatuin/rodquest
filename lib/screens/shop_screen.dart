import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/game_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'today_screen.dart';

/// Лавка наград для взрослых открывается отдельным экраном из «Гильдии».
void openShop(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Лавка наград')),
        body: const ShopScreen(),
      ),
    ),
  );
}

const rewardEmojis = [
  '🎁', '🍕', '🍦', '🍫', '🎬', '📺', '🎮', '📱', '🧸', '⚽', '🚲', '🎡',
  '🏊', '🛝', '📚', '🎨', '🎧', '🛌', '🍔', '🧁', '💸', '🎟', '🐶', '🌙',
];

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final rewards = game.rewards;
    final manage = game.canManageRewards;
    final pending = manage ? game.pendingClaims : const <RewardClaim>[];
    final mine = game.claims.where((c) => c.heroId == hero.id).take(10).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        RqCard(
          color: RqColors.p.highlightBg,
          borderColor: RqColors.p.highlightBorder,
          child: Row(
            children: [
              Text(RqColors.playful ? '💰' : '🪙', style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('У вас ${hero.coins} ${coinWord(hero.coins)}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      'Задание +${GoalTier.task.coins} · квест +${GoalTier.quest.coins} · '
                      'эпик +${GoalTier.epic.coins} · рутина +${GoalTier.daily.coins}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty) ...[
          const SectionTitle('⏳ Ждут выдачи'),
          for (final c in pending) ClaimCard(claim: c),
        ],
        SectionTitle(
          '🎁 Награды',
          trailing: manage
              ? TextButton.icon(
                  onPressed: () => openRewardEditor(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Добавить'),
                )
              : null,
        ),
        if (rewards.isEmpty)
          EmptyHint(
            emoji: '🏪',
            text: game.solo
                ? 'Лавка пуста. Назначьте себе награды за монеты: «Новая книга», «Вечер кино», «Выходной без дел».'
                : manage
                ? 'Лавка пуста. Добавьте награды, за которые дети будут копить монеты: '
                    '«Мультфильм», «Пицца», «Поход в кино».'
                : 'Лавка пока пуста. Попросите родителей добавить награды!',
          ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 560 ? 3 : 2;
            final w = (c.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final r in rewards) SizedBox(width: w, child: _RewardTile(reward: r, coins: hero.coins)),
              ],
            );
          },
        ),
        if (mine.isNotEmpty) ...[
          const SectionTitle('🧾 Мои покупки'),
          for (final c in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                  MiniPill(
                    switch (c.status) {
                      ClaimStatus.pending => 'ждёт выдачи',
                      ClaimStatus.granted => 'получено',
                      ClaimStatus.rejected => 'отказ, монеты вернулись',
                    },
                    switch (c.status) {
                      ClaimStatus.pending => RqColors.gold,
                      ClaimStatus.granted => RqColors.xp,
                      ClaimStatus.rejected => RqColors.danger,
                    },
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

String coinWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'монета';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'монеты';
  return 'монет';
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.reward, required this.coins});

  final Reward reward;
  final int coins;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final enough = coins >= reward.cost;
    final missing = reward.cost - coins;

    Future<void> buy() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${reward.emoji} ${reward.title}'),
          content: Text('Потратить ${reward.cost} ${coinWord(reward.cost)}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Купить')),
          ],
        ),
      );
      if (ok != true) return;
      final r = await game.buyReward(reward.id);
      if (!context.mounted) return;
      final text = switch (r) {
        BuyResult.granted => '🎉 Награда ваша: «${reward.title}»',
        BuyResult.pending => '⏳ Куплено! Родители скоро выдадут «${reward.title}»',
        BuyResult.notEnough => 'Не хватает монет',
        BuyResult.unavailable => 'Награда недоступна',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    return RqCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      onTap: game.canManageRewards ? () => openRewardEditor(context, reward: reward) : null,
      child: Column(
        children: [
          Text(reward.emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 6),
          Text(
            reward.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 6),
          CoinBadge(reward.cost),
          const SizedBox(height: 10),
          ChunkyButton(
            label: enough ? 'Купить' : 'ещё $missing',
            onPressed: enough ? buy : null,
          ),
        ],
      ),
    );
  }
}

Future<void> openRewardEditor(BuildContext context, {Reward? reward}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(
      controller: GameScope.read(context),
      child: _RewardEditor(reward: reward),
    ),
  );
}

class _RewardEditor extends StatefulWidget {
  const _RewardEditor({this.reward});

  final Reward? reward;

  @override
  State<_RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends State<_RewardEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.reward?.title ?? '');
  late final TextEditingController _cost = TextEditingController(text: widget.reward?.cost.toString() ?? '');
  late String _emoji = widget.reward?.emoji ?? rewardEmojis.first;

  @override
  void dispose() {
    _title.dispose();
    _cost.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && (parseAmount(_cost.text) ?? 0) > 0;

  Future<void> _save() async {
    if (!_valid) return;
    final game = GameScope.read(context);
    final cost = parseAmount(_cost.text)!;
    if (widget.reward == null) {
      await game.addReward(title: _title.text, emoji: _emoji, cost: cost);
    } else {
      await game.updateReward(widget.reward!, title: _title.text, emoji: _emoji, cost: cost);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.reward == null ? 'Новая награда' : 'Награда', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: widget.reward == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Например: Поход в кино'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Цена в монетах', suffixText: '🪙'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Text('Ориентир: задание даёт ${GoalTier.task.coins} 🪙, квест — ${GoalTier.quest.coins} 🪙, '
                  'рутина — ${GoalTier.daily.coins} 🪙 в день.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in rewardEmojis)
                    GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: e == _emoji ? RqColors.tint(RqColors.primary, 0.18) : RqColors.surface,
                          borderRadius: BorderRadius.circular(RqColors.playful ? 12 : 8),
                          border: Border.all(color: e == _emoji ? RqColors.primary : RqColors.line),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              ChunkyButton(
                label: widget.reward == null ? 'Добавить в лавку' : 'Сохранить',
                icon: _emoji,
                onPressed: _valid ? _save : null,
              ),
              if (widget.reward != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await game.archiveReward(widget.reward!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text('Убрать из лавки', style: TextStyle(color: RqColors.danger)),
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
