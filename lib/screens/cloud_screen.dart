import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../state/game_controller.dart';
import '../sync/cloud_scope.dart';
import '../sync/sync_api.dart';
import '../sync/sync_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'onboarding_screen.dart';

/// v0.8: облако семьи — синхронизация, приглашения, устройства, почта.
Future<void> openCloud(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CloudScreen()));

/// Вход в семью (клан) по коду или восстановление по почте.
Future<void> openJoin(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const JoinGuildScreen()));

String _deviceLine(GameController game, GuildDevice d) {
  final who = [
    for (final id in d.heroIds)
      if (game.heroById(id) case final HeroProfile h) '${h.avatar} ${h.name}',
  ].join(', ');
  final seen = 'в сети ${_dateTime(d.lastSeen)}';
  return who.isEmpty ? seen : '$who · $seen';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _dateTime(DateTime t) => '${_two(t.day)}.${_two(t.month)} ${_time(t)}';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
}

/// Короткая строка состояния синхронизации.
String cloudStatusText(SyncEngine cloud, DateTime now) {
  final last = cloud.lastSyncAt;
  return switch (cloud.status) {
    SyncStatus.off => 'Данные только на этом устройстве',
    SyncStatus.syncing => 'Синхронизация…',
    SyncStatus.offline => 'Нет связи — правки сохранены и уйдут позже',
    SyncStatus.error => '⚠️ ${cloud.error ?? 'Ошибка синхронизации'}',
    SyncStatus.idle => last == null
        ? 'Подключено'
        : now.difference(last).inMinutes < 1
            ? 'Синхронизировано только что'
            : last.day == now.day && last.month == now.month
                ? 'Синхронизировано в ${_time(last)}'
                : 'Синхронизировано ${_dateTime(last)}',
  };
}

/// Карточка облака на экране семьи (клана).
class CloudCard extends StatelessWidget {
  const CloudCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context);
    final game = GameScope.of(context);
    final me = game.activeHero;
    if (cloud == null || me == null) return const SizedBox.shrink();
    if (!cloud.connected && !me.role.isAdult) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return RqCard(
      onTap: () => openCloud(context),
      child: Row(
        children: [
          Text(cloud.connected ? '☁️' : '📱', style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cloud.connected ? 'Облако ${Words.groupGen}' : 'Подключить ${Words.groupAcc} к облаку', style: theme.textTheme.titleMedium),
                Text(
                  cloud.connected
                      ? cloudStatusText(cloud, game.now)
                      : 'У каждого свой телефон — ${Words.groupLower} ${Words.clan ? 'общий' : 'общая'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (cloud.status == SyncStatus.syncing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          else
            Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
        ],
      ),
    );
  }
}

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  Future<List<GuildDevice>>? _devices;

  @override
  void initState() {
    super.initState();
    final cloud = CloudScope.read(context);
    if (cloud != null && cloud.connected) {
      _devices = cloud.devices();
      () async {
        try {
          await cloud.refreshInfo();
        } on SyncError catch (_) {
          // Нет связи — покажем то, что известно.
        }
      }();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? get _urlOrNull => _url.text.trim().isEmpty ? null : _url.text.trim();

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted && done != null) _snack(context, done);
    } on SyncError catch (e) {
      if (mounted) _snack(context, '⚠️ ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(SyncEngine cloud) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('☁️ Подключить ${Words.groupAcc}'),
        content: Text(
          'Все данные этого устройства — герои, цели, лента, лавка, бюджет и будильники — '
          'будут храниться на сервере в России и обновляться на телефонах ${Words.groupGen}.\n\n'
          'Потом пригласите близких кодом: у каждого будет свой телефон, а ${Words.groupLower} — ${Words.clan ? 'общий' : 'общая'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Подключить')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await cloud.createGuild(url: _urlOrNull);
      _devices = cloud.devices();
    }, done: '☁️ ${Words.group} в облаке! Теперь пригласите близких');
  }

  Future<void> _invite(SyncEngine cloud, {required bool kid}) async {
    Invite? inv;
    await _run(() async => inv = await cloud.invite(kid: kid));
    final invite = inv;
    if (invite == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kid ? '🧒 Код для юнги' : '🧑 Код для взрослого'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('На другом телефоне откройте Родквест и нажмите «У меня есть код приглашения».'),
            const SizedBox(height: 16),
            SelectableText(
              invite.pretty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 3, color: RqColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Код одноразовый, действует до ${_dateTime(invite.expiresAt)}.'
              '${kid ? '\nНа устройстве юнги не будет бюджета и взрослых профилей.' : ''}',
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

  Future<void> _linkEmail(SyncEngine cloud) async {
    final email = await _ask(
      title: '✉️ Почта для восстановления',
      text: 'Если телефон потеряется, по этой почте можно будет войти в ${Words.groupAcc} на новом устройстве.',
      hint: 'name@yandex.ru',
      keyboard: TextInputType.emailAddress,
    );
    if (email == null || email.trim().isEmpty) return;
    String? dev;
    var sent = false;
    await _run(() async {
      dev = await cloud.linkEmailStart(email);
      sent = true;
    });
    if (!sent || !mounted) return;
    final code = await _ask(
      title: 'Код из письма',
      text: 'Мы отправили 6 цифр на ${email.trim()}. Письмо может попасть в «Спам».',
      hint: '123456',
      keyboard: TextInputType.number,
      initial: dev,
    );
    if (code == null || code.trim().isEmpty) return;
    await _run(() => cloud.linkEmailFinish(email, code), done: '✉️ Почта привязана');
  }

  Future<String?> _ask({
    required String title,
    required String text,
    required String hint,
    TextInputType? keyboard,
    String? initial,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
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
              keyboardType: keyboard,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Дальше')),
        ],
      ),
    );
    disposeLater(ctrl);
    return v;
  }

  Future<void> _revoke(SyncEngine cloud, GuildDevice d) async {
    final ok = await _confirm('Отключить «${d.name}»?',
        'Устройство перестанет получать данные ${Words.groupGen}. Данные на нём останутся, но обновляться не будут.');
    if (!ok) return;
    await _run(() async {
      await cloud.revoke(d.id);
      _devices = cloud.devices();
    }, done: 'Устройство отключено');
  }

  Future<void> _leave(SyncEngine cloud) async {
    final ok = await _confirm('Отключить это устройство?',
        'Данные останутся здесь, но перестанут обновляться. Подключиться снова можно по новому коду приглашения.');
    if (!ok) return;
    await _run(() => cloud.disconnect(), done: 'Устройство отключено от облака');
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Отключить', style: TextStyle(color: RqColors.danger)),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context);
    final game = GameScope.of(context);
    final me = game.activeHero;
    return Scaffold(
      appBar: AppBar(title: Text('Облако ${Words.groupGen}')),
      body: cloud == null || me == null
          ? const Center(child: Text('Облако недоступно в этой сборке'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: cloud.connected ? _connected(cloud, me) : _offline(cloud, me),
            ),
    );
  }

  List<Widget> _offline(SyncEngine cloud, HeroProfile me) {
    final theme = Theme.of(context);
    return [
      RqCard(
        color: RqColors.p.tintCard,
        borderColor: RqColors.p.tintCardBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('☁️ ${Words.clan ? 'Один клан' : 'Одна семья'} — много телефонов', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Цели, опыт, лента, лавка наград и бюджет обновляются у всех в ${Words.groupPrep}. '
              'Юнга выполнил задание на своём телефоне — родитель сразу видит его и подтверждает на своём.\n\n'
              'Без интернета всё работает как раньше: правки сохраняются и уходят, когда появится связь.',
            ),
          ],
        ),
      ),
      if (me.role.canApprove || GameScope.of(context).solo) ...[
        const SizedBox(height: 8),
        ChunkyButton(
          label: _busy ? 'Подключаем…' : 'Подключить ${Words.groupAcc} к облаку',
          icon: '☁️',
          onPressed: _busy ? null : () => _connect(cloud),
        ),
      ] else
        EmptyHint(emoji: Words.emoji, text: 'Подключить ${Words.groupAcc} к облаку может ${Words.leader.toLowerCase()}.'),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => openJoin(context),
          child: const Text('🎟 У меня есть код приглашения', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 8),
      ExpansionTile(
        initiallyExpanded: !cloud.hasServer,
        tilePadding: EdgeInsets.zero,
        title: const Text('Дополнительно', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Адрес сервера',
              hintText: cloud.hasServer ? cloud.defaultUrl : 'https://functions.yandexcloud.net/…',
              helperText: cloud.hasServer ? 'Пусто — сервер Родквеста' : 'В этой сборке адрес сервера не задан',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _connected(SyncEngine cloud, HeroProfile me) {
    final theme = Theme.of(context);
    final s = cloud.session!;
    final game = GameScope.of(context);
    final adult = !cloud.kidDevice;
    return [
      RqCard(
        color: RqColors.p.tintCard,
        borderColor: RqColors.p.tintCardBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('☁️', style: TextStyle(fontSize: 36)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(game.solo ? 'Мой путь' : game.guildName, style: theme.textTheme.titleLarge),
                      Text(adult ? 'Взрослое устройство' : 'Устройство юнги', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(cloudStatusText(cloud, game.now), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: cloud.status == SyncStatus.syncing ? null : () => cloud.syncNow(),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Синхронизировать'),
              ),
            ),
          ],
        ),
      ),
      if (adult) ...[
        SectionTitle('🎟 Пригласить в ${Words.groupAcc}'),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                label: 'Взрослого',
                icon: '🧑',
                onPressed: _busy ? null : () => _invite(cloud, kid: false),
              ),
            ),
            const SizedBox(width: 10),
            if (!game.solo)
              Expanded(
                child: ChunkyButton(
                  label: 'Юнгу',
                  icon: '🧒',
                  color: RqColors.xp,
                  onPressed: _busy ? null : () => _invite(cloud, kid: true),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          game.solo
              ? 'Код для вашего второго устройства: планшета или компьютера.'
              : 'Каждому — свой код. Юнга увидит только свои дела, лавку и ленту.',
          style: theme.textTheme.bodySmall,
        ),
        const SectionTitle('✉️ Почта для восстановления'),
        RqCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.email == null
                      ? 'Не привязана. Если все телефоны потеряются, войти в ${Words.groupAcc} будет нельзя.'
                      : 'Привязана: ${s.email}. По ней можно войти на новом устройстве.',
                ),
              ),
              const SizedBox(width: 8),
              if (s.email == null)
                TextButton(onPressed: _busy ? null : () => _linkEmail(cloud), child: const Text('Привязать'))
              else
                TextButton(
                  onPressed: _busy ? null : () => _run(() => cloud.unlinkEmail(), done: 'Почта отвязана'),
                  child: const Text('Отвязать'),
                ),
            ],
          ),
        ),
      ],
      SectionTitle('📱 Устройства ${Words.groupGen}'),
      FutureBuilder<List<GuildDevice>>(
        future: _devices,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyHint(
              emoji: '📡',
              text: snap.error is SyncError ? (snap.error as SyncError).message : 'Не удалось загрузить список',
            );
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            children: [
              for (final d in snap.data!)
                RqCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Text(d.kid ? '🧒' : '📱', style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d.name}${d.me ? ' (это)' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(_deviceLine(game, d), style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      if (adult && !d.me)
                        IconButton(
                          tooltip: 'Отключить',
                          icon: Icon(Icons.link_off_rounded, color: RqColors.danger),
                          onPressed: _busy ? null : () => _revoke(cloud, d),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => _leave(cloud),
          child: Text('Отключить это устройство от облака',
              style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800)),
        ),
      ),
    ];
  }
}

/// Вход в семью (клан): по коду приглашения или по почте главы.
class JoinGuildScreen extends StatefulWidget {
  const JoinGuildScreen({super.key});

  @override
  State<JoinGuildScreen> createState() => _JoinGuildScreenState();
}

class _JoinGuildScreenState extends State<JoinGuildScreen> {
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _mailCode = TextEditingController();
  final _url = TextEditingController();
  bool _byEmail = false;
  bool _sent = false;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _mailCode.dispose();
    _url.dispose();
    super.dispose();
  }

  String? get _urlOrNull => _url.text.trim().isEmpty ? null : _url.text.trim();

  /// Данные этого устройства заменятся данными семьи — предупредить, если они есть.
  Future<bool> _okToReplace() async {
    final game = GameScope.read(context);
    if (game.needsOnboarding) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Заменить данные устройства?'),
            content: Text(
              'Сейчас на этом устройстве есть ${Words.clan ? 'свой клан' : 'своя семья'}. После входа здесь будут данные той семьи или клана, '
              'куда вас пригласили, а нынешние пропадут.\n\nЕсли они нужны — сначала сохраните резервную копию.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Заменить', style: TextStyle(color: RqColors.danger)),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _go(Future<void> Function(SyncEngine cloud) job) async {
    final cloud = CloudScope.read(context);
    if (cloud == null || _busy) return;
    setState(() => _busy = true);
    try {
      await job(cloud);
      if (!mounted) return;
      if (cloud.connected) Navigator.of(context).popUntil((r) => r.isFirst);
    } on SyncError catch (e) {
      if (mounted) _snack(context, '⚠️ ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    if (_code.text.trim().length < 8 || !await _okToReplace()) return;
    await _go((cloud) async {
      if (cloud.connected) await cloud.disconnect();
      await cloud.join(_code.text, url: _urlOrNull);
    });
  }

  Future<void> _sendMail() async {
    if (!_email.text.contains('@')) return;
    await _go((cloud) async {
      final dev = await cloud.recoverStart(_email.text, url: _urlOrNull);
      if (dev != null) _mailCode.text = dev;
      setState(() => _sent = true);
      if (mounted) _snack(context, '✉️ Если почта привязана к семье или клану, письмо с кодом уже в пути');
    });
  }

  Future<void> _recover() async {
    if (_mailCode.text.trim().length < 6 || !await _okToReplace()) return;
    await _go((cloud) async {
      if (cloud.connected) await cloud.disconnect();
      await cloud.recoverFinish(_email.text, _mailCode.text, url: _urlOrNull);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = CloudScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в семью или клан')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('🎟 Код приглашения')),
                  ButtonSegment(value: true, label: Text('✉️ Почта главы')),
                ],
                selected: {_byEmail},
                onSelectionChanged: (v) => setState(() => _byEmail = v.first),
              ),
              const SizedBox(height: 20),
              if (!_byEmail) ...[
                Text('Код от главы семьи или клана', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('Глава: вкладка «Семья» (или «Клан») → Облако → Пригласить.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3),
                  decoration: const InputDecoration(hintText: 'ABCD-EFGH'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 16),
                ChunkyButton(
                  label: _busy ? 'Входим…' : 'Войти',
                  icon: '🎟',
                  onPressed: _busy || _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 8 ? null : _join,
                ),
              ] else ...[
                Text('Восстановление по почте', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('Если глава привязал почту, по ней можно войти как взрослый — например, на новом телефоне.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Почта', hintText: 'name@yandex.ru'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (!_sent)
                  ChunkyButton(
                    label: _busy ? 'Отправляем…' : 'Получить код',
                    icon: '✉️',
                    onPressed: _busy || !_email.text.contains('@') ? null : _sendMail,
                  )
                else ...[
                  TextField(
                    controller: _mailCode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Код из письма', hintText: '123456'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _recover(),
                  ),
                  const SizedBox(height: 12),
                  ChunkyButton(
                    label: _busy ? 'Входим…' : 'Войти',
                    icon: '🔑',
                    onPressed: _busy || _mailCode.text.trim().length < 6 ? null : _recover,
                  ),
                  TextButton(
                    onPressed: _busy ? null : _sendMail,
                    child: const Text('Отправить код ещё раз'),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              ExpansionTile(
                initiallyExpanded: cloud != null && !cloud.hasServer,
                tilePadding: EdgeInsets.zero,
                title: const Text('Дополнительно', style: TextStyle(fontWeight: FontWeight.w800)),
                children: [
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Адрес сервера',
                      hintText: cloud?.defaultUrl.isNotEmpty == true
                          ? cloud!.defaultUrl
                          : 'https://functions.yandexcloud.net/…',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// После входа по коду: кто играет на этом устройстве?
class HeroPickScreen extends StatefulWidget {
  const HeroPickScreen({super.key});

  @override
  State<HeroPickScreen> createState() => _HeroPickScreenState();
}

class _HeroPickScreenState extends State<HeroPickScreen> {
  final _name = TextEditingController();
  String _avatar = heroAvatars.first;
  bool _creating = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function(SyncEngine cloud) job) async {
    final cloud = CloudScope.read(context);
    if (cloud == null || _busy) return;
    setState(() => _busy = true);
    try {
      await job(cloud);
    } on SyncError catch (e) {
      if (mounted) _snack(context, '⚠️ ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final cloud = CloudScope.of(context);
    final theme = Theme.of(context);
    final heroes = [for (final h in game.heroes) if (game.canSwitchTo(h.id)) h];
    final kid = cloud?.kidDevice ?? false;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Center(child: Text(Words.emoji, style: const TextStyle(fontSize: 56))),
                const SizedBox(height: 8),
                Text('Добро пожаловать в «${game.guildName}»!',
                    textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('Кто играет на этом устройстве?',
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: RqColors.inkSoft)),
                const SizedBox(height: 20),
                if (!_creating) ...[
                  for (final h in heroes)
                    RqCard(
                      onTap: _busy ? null : () => _do((c) => c.pickHero(h.id)),
                      child: Row(
                        children: [
                          AvatarBubble(h.avatar, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                Text(h.role.label, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: RqColors.inkSoft),
                        ],
                      ),
                    ),
                  if (heroes.isEmpty)
                    const EmptyHint(emoji: '🧭', text: 'Для этого устройства пока нет героя — создайте его.'),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => setState(() => _creating = true),
                      child: Text(kid ? '🧒 Я новый юнга в ${Words.groupPrep}' : '✨ Я новый герой в ${Words.groupPrep}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ] else ...[
                  Text('Имя героя', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(hintText: kid ? 'Например: Маша' : 'Например: Мама'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text('Аватар', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  AvatarPicker(selected: _avatar, onSelected: (a) => setState(() => _avatar = a)),
                  const SizedBox(height: 20),
                  ChunkyButton(
                    label: _busy ? 'Создаём…' : 'Вступить в ${Words.groupAcc}',
                    icon: '🎉',
                    onPressed: _busy || _name.text.trim().isEmpty
                        ? null
                        : () => _do((c) => c.pickNewHero(_name.text, _avatar)),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _creating = false),
                    child: const Text('Назад к списку'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
