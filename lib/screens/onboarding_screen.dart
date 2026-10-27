import 'package:flutter/material.dart';

import '../models/words.dart';
import '../sync/cloud_scope.dart';
import '../theme.dart';
import '../widgets/backup_ui.dart';
import '../widgets/common.dart';
import 'cloud_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _guild = TextEditingController();
  final _name = TextEditingController();
  String _avatar = heroAvatars.first;
  bool _demo = true;
  bool _solo = false;
  GroupKind _kind = GroupKind.family;
  bool _busy = false;

  @override
  void dispose() {
    _guild.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid => (_solo || _guild.text.trim().isNotEmpty) && _name.text.trim().isNotEmpty;

  Future<void> _start() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final game = GameScope.read(context);
    await game.createGuild(
        guildName: _solo ? '' : _guild.text, heroName: _name.text, avatar: _avatar, solo: _solo, kind: _kind);
    if (_demo) await game.seedDemo();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Center(
                  child: Image.asset('assets/brand/logo.png', width: 112, height: 112, semanticLabel: 'Логотип Родквеста'),
                ),
                const SizedBox(height: 8),
                Text('Родквест',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(color: RqColors.primary, fontSize: 40)),
                const SizedBox(height: 6),
                Text(
                  'Превратите дела в приключение: цели — в квесты,\nпривычки — в прокачку героя.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: RqColors.inkSoft),
                ),
                const SizedBox(height: 24),
                Text('Для кого Родквест?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ModeCard(
                        emoji: '👨‍👩‍👧',
                        title: 'Семья',
                        text: 'Дети-юнги, общие цели',
                        selected: !_solo && _kind == GroupKind.family,
                        onTap: () => setState(() {
                          _solo = false;
                          _kind = GroupKind.family;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeCard(
                        emoji: '⚔️',
                        title: 'Клан',
                        text: 'Друзья, соседи, команда',
                        selected: !_solo && _kind == GroupKind.clan,
                        onTap: () => setState(() {
                          _solo = false;
                          _kind = GroupKind.clan;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeCard(
                        emoji: '🧭',
                        title: 'Только я',
                        text: 'Личные цели и привычки',
                        selected: _solo,
                        onTap: () => setState(() => _solo = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!_solo) ...[
                  Text(_kind == GroupKind.clan ? 'Название клана' : 'Название семьи', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _guild,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        hintText: _kind == GroupKind.clan ? 'Например: Клан Северных Волков' : 'Например: Дом Смелых'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                ],
                Text('Ваше имя героя', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Например: Папа'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _start(),
                ),
                const SizedBox(height: 18),
                Text('Аватар', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                AvatarPicker(selected: _avatar, onSelected: (a) => setState(() => _avatar = a)),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _demo,
                  onChanged: (v) => setState(() => _demo = v),
                  title: const Text('Добавить пример целей', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_solo
                      ? 'Легенда «Полумарафон», пробежки по расписанию и дела раз в неделю и месяц'
                      : 'Легенда «Семейный отпуск» с эпиками, заданиями и регулярными делами'),
                ),
                const SizedBox(height: 16),
                ChunkyButton(
                  label: _busy
                      ? 'Создаём…'
                      : (_solo ? 'Начать путь' : (_kind == GroupKind.clan ? 'Основать клан' : 'Создать семью')),
                  icon: '🚀',
                  onPressed: _valid && !_busy ? _start : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _solo
                      ? 'Позже можно пригласить близких — личный путь станет семьёй или кланом. '
                          'А ещё — вступить в гильдию вместе с другими героями.'
                      : 'Вы станете главой ${_kind == GroupKind.clan ? 'клана' : 'семьи'}. Близких можно добавить позже, '
                          'а потом — объединиться с другими семьями и кланами в гильдию.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (CloudScope.of(context) != null)
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => openJoin(context),
                      child: const Text('🎟 У меня есть код приглашения в семью или клан',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => importBackupFlow(context),
                    child: const Text('📂 Восстановить из резервной копии',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in heroAvatars)
          GestureDetector(
            onTap: () => onSelected(a),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: a == selected ? RqColors.tint(RqColors.primary, 0.18) : RqColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: a == selected ? RqColors.primary : RqColors.line, width: 2),
              ),
              child: Text(a, style: const TextStyle(fontSize: 24)),
            ),
          ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.emoji,
    required this.title,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: RqCard(
        margin: EdgeInsets.zero,
        onTap: onTap,
        color: selected ? RqColors.tint(RqColors.primary, 0.12) : RqColors.surface,
        borderColor: selected ? RqColors.primary : RqColors.line,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
