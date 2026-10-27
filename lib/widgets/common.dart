import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../theme.dart';
import 'effects.dart';

/// Даёт доступ к [GameController] из любого виджета и перерисовывает
/// зависимые виджеты при изменениях.
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({super.key, required GameController controller, required super.child})
      : super(notifier: controller);

  static GameController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameScope>()!.notifier!;

  static GameController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GameScope>()!.notifier!;
}

/// Карточка. В игровой теме — «мультяшная» сплошная тень снизу,
/// во взрослой — тонкая рамка и мягкая тень.
class RqCard extends StatelessWidget {
  const RqCard({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final radius = BorderRadius.circular(p.radius);
    final border = borderColor ?? p.line;
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: color ?? p.surface,
          borderRadius: radius,
          border: Border.all(color: border, width: p.playful ? 2 : 1),
          boxShadow: p.playful
              ? [BoxShadow(color: border, offset: const Offset(0, 4))]
              : p.dark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Крупная кнопка. В игровой теме — объёмная, как в играх; во взрослой — плоская.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final String? icon;
  final bool expand;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final enabled = widget.onPressed != null;
    final color = enabled ? (widget.color ?? p.primary) : p.disabled;
    final maxDepth = p.playful ? 5.0 : 0.0;
    final depth = _down ? math.min(1.0, maxDepth) : maxDepth;
    final textColor = enabled ? p.onAccent : p.inkSoft;
    final label = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Text(widget.icon!, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: p.playful ? 0 : 0.3,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: EdgeInsets.only(top: maxDepth - depth),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: p.playful ? 14 : 15),
          decoration: BoxDecoration(
            color: _down && !p.playful ? RqColors.shade(color, 0.06) : color,
            borderRadius: BorderRadius.circular(p.playful ? 18 : 10),
            boxShadow: depth > 0 ? [BoxShadow(color: RqColors.shade(color), offset: Offset(0, depth))] : null,
          ),
          child: label,
        ),
      ),
    );
  }
}

/// Полоска прогресса / опыта. Плавно анимирует изменения значения.
class RqBar extends StatelessWidget {
  const RqBar({
    super.key,
    required this.value,
    this.color,
    this.height = 14,
    this.background,
  });

  final double value;
  final Color? color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final h = p.playful ? height : math.max(6.0, height * 0.7);
    final fill = color ?? p.xp;
    return ClipRRect(
      borderRadius: BorderRadius.circular(h),
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: background ?? p.track),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: Container(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(h),
                  ),
                  // Блик сверху — для «мультяшного» объёма (только в игровой теме).
                  alignment: Alignment.topCenter,
                  padding: EdgeInsets.fromLTRB(h / 2, h * 0.18, h / 2, 0),
                  child: p.playful && v > 0.04
                      ? Container(
                          height: h * 0.22,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(h),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.compact = false});

  final GoalTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = RqColors.tier(tier);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 3),
      decoration: BoxDecoration(
        color: RqColors.tint(c, 0.16),
        borderRadius: BorderRadius.circular(RqColors.playful ? 10 : 6),
      ),
      child: Text(
        compact ? tier.emoji : '${tier.emoji} ${tier.label}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: RqColors.strong(c)),
      ),
    );
  }
}

/// Маленькая цветная плашка с текстом.
class MiniPill extends StatelessWidget {
  const MiniPill(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: RqColors.tint(color, 0.13),
        borderRadius: BorderRadius.circular(RqColors.playful ? 10 : 6),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: RqColors.strong(color))),
    );
  }
}

class AvatarBubble extends StatelessWidget {
  const AvatarBubble(this.emoji, {super.key, this.size = 44, this.color});

  final String emoji;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? RqColors.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RqColors.tint(c, 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: RqColors.tint(c, 0.45), width: RqColors.playful ? 2 : 1),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// Счётчик монет героя.
class CoinBadge extends StatelessWidget {
  const CoinBadge(this.coins, {super.key, this.large = false});

  final int coins;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = RqColors.coin;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(
        color: RqColors.tint(c, 0.16),
        borderRadius: BorderRadius.circular(RqColors.playful ? 12 : 8),
      ),
      child: Text(
        '🪙 $coins',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: large ? 18 : 13, color: RqColors.strong(c)),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RqCard(
      color: RqColors.surfaceAlt,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Варианты аватаров героев.
const heroAvatars = [
  '🧙', '🧝‍♀️', '🦸', '🦸‍♀️', '🧑‍🚀', '👸', '🤴', '🥷',
  '🧚', '🐱', '🦊', '🐻', '🐼', '🐯', '🦁', '🐸',
  '🦄', '🐲', '🤖', '👾', '👩‍💼', '👨‍💼', '👵', '👴',
];

/// Показать награду после выполнения цели: всплывающие «+XP» и монеты,
/// а при новом уровне — праздничное окно.
void showReward(BuildContext context, CompletionResult r) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  if (r.pending) {
    messenger.showSnackBar(SnackBar(content: Text('⏳ Отправлено на подтверждение: ${Words.leader.toLowerCase()}')));
    return;
  }
  if (r.xp <= 0) return;
  showXpBurst(context, xp: r.xp, coins: r.coins);
  // v0.7: конфетти, монеты летят в счётчик, «удар по боссу» для цепочки.
  showConfetti(context);
  showCoinFlight(context, r.coins);
  if (r.chain.isNotEmpty) showChainBurst(context, r.chain);
  final lines = [
    if (r.traits.isNotEmpty)
      'Черты: ${[for (final t in HeroTrait.values) if ((r.traits[t] ?? 0) > 0) '${t.emoji} ${t.label} +${r.traits[t]}'].join(' · ')}',
    for (final a in r.badges)
      '🏆 Достижение «${a.title}»${a.tiered ? ' ${a.medal} ${Achievement.levelName(a.level)}' : ''}!',
  ];
  if (lines.isNotEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(lines.join('\n')),
      duration: Duration(seconds: 3 + r.badges.length),
    ));
  }
  if (r.newLevel != null) {
    final level = r.newLevel!;
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (context.mounted) showLevelUp(context, level);
    });
  }
}

/// Анимация «+10 XP  +5 🪙», всплывающая над экраном.
void showXpBurst(BuildContext context, {required int xp, int coins = 0}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _XpBurst(xp: xp, coins: coins, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _XpBurst extends StatefulWidget {
  const _XpBurst({required this.xp, required this.coins, required this.onDone});

  final int xp;
  final int coins;
  final VoidCallback onDone;

  @override
  State<_XpBurst> createState() => _XpBurstState();
}

class _XpBurstState extends State<_XpBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Появление с «пружинкой», подъём вверх и растворение в конце.
          final scale = Curves.elasticOut.transform((t * 2.2).clamp(0.0, 1.0)) * (p.playful ? 1.0 : 0.85);
          final rise = Curves.easeOut.transform(t) * 90;
          final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
          return Align(
            alignment: const Alignment(0, 0.25),
            child: Transform.translate(
              offset: Offset(0, -rise),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(p.playful ? 20 : 12),
                        border: Border.all(color: p.playful ? p.xp : p.line, width: p.playful ? 3 : 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.playful ? '✨' : '▲',
                              style: TextStyle(fontSize: p.playful ? 22 : 14, color: p.xp)),
                          const SizedBox(width: 6),
                          Text('+${widget.xp} XP',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p.xpDark)),
                          if (widget.coins > 0) ...[
                            const SizedBox(width: 14),
                            Text('+${widget.coins} 🪙',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w900, color: RqColors.strong(p.coin))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Праздничное окно нового уровня с анимацией.
Future<void> showLevelUp(BuildContext context, int level) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Новый уровень',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (ctx, _, _) => _LevelUpCard(level: level),
    transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut, reverseCurve: Curves.easeIn),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _LevelUpCard extends StatefulWidget {
  const _LevelUpCard({required this.level});

  final int level;

  @override
  State<_LevelUpCard> createState() => _LevelUpCardState();
}

class _LevelUpCardState extends State<_LevelUpCard> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    final title = GameRules.levelFor(GameRules.totalXpForLevel(widget.level)).title;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(p.radius + 6),
            border: Border.all(color: p.playful ? p.gold : p.highlightBorder, width: p.playful ? 3 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.playful ? '🎉 Новый уровень!' : 'Новый уровень',
                  style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (p.playful)
                      RotationTransition(
                        turns: _spin,
                        child: CustomPaint(size: const Size(150, 150), painter: _RaysPainter(p.gold)),
                      ),
                    Container(
                      width: 104,
                      height: 104,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.playful ? p.gold : p.surface,
                        border: Border.all(color: p.playful ? RqColors.shade(p.gold, 0.12) : p.gold, width: 3),
                      ),
                      child: Text(
                        '${widget.level}',
                        style: TextStyle(
                          fontFamily: p.fontDisplay,
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          color: p.playful ? Colors.white : p.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Звание: $title', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(p.playful ? 'Так держать, герой!' : 'Отличный темп. Продолжайте в том же духе.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              ChunkyButton(
                label: p.playful ? 'Ура!' : 'Продолжить',
                icon: p.playful ? '⭐' : null,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()..color = color.withValues(alpha: 0.28);
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * math.pi / rays;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.12), c.dy + r * math.sin(a - 0.12))
        ..lineTo(c.dx + r * math.cos(a + 0.12), c.dy + r * math.sin(a + 0.12))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}

/// Поле ввода суммы/числа с подписью.
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.controller, required this.hint, this.suffix, this.autofocus = false});

  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(hintText: hint, suffixText: suffix),
    );
  }
}

/// Разобрать число из поля ввода: «12 500» → 12500.
int? parseAmount(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Освободить контроллер поля из диалога чуть позже: окно ещё доигрывает
/// анимацию закрытия и может перестроиться, если данные изменились.
void disposeLater(ChangeNotifier c) {
  Future<void>.delayed(const Duration(seconds: 1), c.dispose);
}
