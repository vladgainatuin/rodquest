import 'dart:math';

import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../theme.dart';
import 'common.dart';

/// Окно ввода PIN из 4 цифр с крупной цифровой клавиатурой.
///
/// [validate] вызывается после ввода 4 цифр: вернёт текст ошибки — окно
/// покажет её и очистит ввод; вернёт null — окно закроется с PIN.
Future<String?> showPinPad(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? Function(String pin)? validate,
  VoidCallback? onForgot,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: title, subtitle: subtitle, validate: validate, onForgot: onForgot),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.subtitle, this.validate, this.onForgot});

  final String title;
  final String? subtitle;
  final String? Function(String pin)? validate;
  final VoidCallback? onForgot;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  String? _error;

  void _tap(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) {
      final err = widget.validate?.call(_pin);
      if (err == null) {
        Navigator.pop(context, _pin);
      } else {
        setState(() {
          _error = err;
          _pin = '';
        });
      }
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    Widget key(String label, {VoidCallback? onTap, String? semantics}) => Padding(
          padding: const EdgeInsets.all(5),
          child: Semantics(
            button: true,
            label: semantics ?? label,
            child: Material(
              color: onTap == null ? Colors.transparent : p.surfaceAlt,
              borderRadius: BorderRadius.circular(p.playful ? 18 : 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(p.playful ? 18 : 10),
                onTap: onTap,
                child: SizedBox(
                  width: 64,
                  height: 54,
                  child: Center(
                    child: Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: p.ink)),
                  ),
                ),
              ),
            ),
          ),
        );

    return AlertDialog(
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(widget.subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? p.primary : Colors.transparent,
                    border: Border.all(color: _error != null ? p.danger : p.primary, width: 2),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 30,
            child: Center(
              child: Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.danger, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d, onTap: () => _tap(d))]),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              key(''),
              key('0', onTap: () => _tap('0')),
              key('⌫', onTap: _back, semantics: 'Стереть'),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.onForgot != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onForgot!();
            },
            child: const Text('Забыли PIN?'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      ],
    );
  }
}

String _lockText(Duration left) => 'Слишком много попыток. Подождите ${left.inSeconds + 1} с.';

/// Переключиться на героя; если юнга входит во взрослый профиль — спросить PIN.
Future<void> switchHeroGuarded(BuildContext context, String heroId) async {
  final game = GameScope.read(context);
  if (!game.needsPinToSwitch(heroId)) {
    await game.switchHero(heroId);
    return;
  }
  final hero = game.heroById(heroId)!;
  final pin = await showPinPad(
    context,
    title: '🔐 PIN родителя',
    subtitle: 'Чтобы войти в профиль «${hero.name}», введите PIN',
    validate: (pin) => switch (game.checkPin(pin)) {
      PinCheck.ok => null,
      PinCheck.wrong => 'Неверный PIN',
      PinCheck.locked => _lockText(game.pinLockLeft ?? GameController.pinLockDuration),
    },
    onForgot: () => _forgotPin(context),
  );
  // PIN уже проверен в окне — повторная проверка внутри switchHero пройдёт.
  if (pin != null) await game.switchHero(heroId, pin: pin);
}

/// «Родительская проверка»: пример, который легко решит взрослый.
/// Если ответ верный — PIN сбрасывается и его можно задать заново.
Future<void> _forgotPin(BuildContext context) async {
  final game = GameScope.read(context);
  final rnd = Random();
  final a = 12 + rnd.nextInt(28), b = 13 + rnd.nextInt(17);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Проверка для взрослых'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Чтобы сбросить PIN, решите пример:'),
          const SizedBox(height: 10),
          Text('$a × $b = ?', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text) == a * b),
          child: const Text('Сбросить PIN'),
        ),
      ],
    ),
  );
  disposeLater(ctrl);
  if (ok == null) return;
  if (ok) await game.resetForgottenPin();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? '🔓 PIN сброшен. Задайте новый в профиле главы гильдии.' : 'Ответ неверный'),
  ));
}

/// Настройки PIN для главы гильдии: включить, сменить, выключить.
Future<void> openPinSettings(BuildContext context) async {
  final game = GameScope.read(context);
  final messenger = ScaffoldMessenger.of(context);

  Future<String?> askNew() async {
    final first = await showPinPad(context, title: 'Новый PIN', subtitle: 'Придумайте 4 цифры');
    if (first == null || !context.mounted) return null;
    return showPinPad(
      context,
      title: 'Повторите PIN',
      validate: (p) => p == first ? null : 'PIN не совпадает, попробуйте ещё раз',
    );
  }

  String? checkCurrent(String pin) => switch (game.checkPin(pin)) {
        PinCheck.ok => null,
        PinCheck.wrong => 'Неверный PIN',
        PinCheck.locked => _lockText(game.pinLockLeft ?? GameController.pinLockDuration),
      };

  if (!game.hasParentPin) {
    final pin = await askNew();
    if (pin == null) return;
    await game.setParentPin(pin);
    messenger.showSnackBar(const SnackBar(content: Text('🔐 PIN включён: юнги не смогут войти во взрослый профиль')));
    return;
  }

  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🔐 PIN родителя', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: const Text('🔁', style: TextStyle(fontSize: 22)),
            title: const Text('Сменить PIN', style: TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => Navigator.pop(ctx, 'change'),
          ),
          ListTile(
            leading: const Text('🔓', style: TextStyle(fontSize: 22)),
            title: Text('Выключить PIN', style: TextStyle(fontWeight: FontWeight.w800, color: RqColors.danger)),
            onTap: () => Navigator.pop(ctx, 'off'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final current = await showPinPad(context, title: 'Текущий PIN', validate: checkCurrent);
  if (current == null || !context.mounted) return;
  if (action == 'off') {
    // PIN только что проверен; повторная проверка внутри пройдёт.
    await game.removeParentPin(current);
    messenger.showSnackBar(const SnackBar(content: Text('🔓 PIN выключен')));
    return;
  }
  final pin = await askNew();
  if (pin == null) return;
  await game.setParentPin(pin, oldPin: current);
  messenger.showSnackBar(const SnackBar(content: Text('🔐 PIN изменён')));
}
