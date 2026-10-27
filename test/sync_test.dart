import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodquest/data/repository.dart';
import 'package:rodquest/models/models.dart';
import 'package:rodquest/state/game_controller.dart';
import 'package:rodquest/sync/alliance.dart';
import 'package:rodquest/sync/codec.dart';
import 'package:rodquest/sync/merge.dart';
import 'package:rodquest/sync/sync_api.dart';
import 'package:rodquest/sync/sync_engine.dart';

/// v0.9: гильдии в памяти — упрощённые правила server/rodquest_server/alliance.py.
/// Общая для нескольких [FakeServer] (у каждого — своя семья).
class FakeAllyHub {
  final docs = <String, Map<String, dynamic>>{};
  final vers = <String, int>{};
  final links = <String, String>{};
  final invites = <String, String>{};
  int _n = 0;

  bool _can(Map<String, dynamic> d, String who, String perm) =>
      d['leader'] == who || ((d['perms'] as Map)[who] as List? ?? const []).contains(perm);

  Map<String, dynamic> _out(String aid, [Map<String, dynamic> extra = const {}]) {
    vers[aid] = (vers[aid] ?? 0) + 1;
    return {'ok': true, ...extra, 'alliance': docs[aid], 'ver': vers[aid]};
  }

  Map<String, dynamic> handle(String op, Map<String, dynamic> b, String space, List<String> heroes, String role) {
    final hero = b['heroId'];
    if (op != 'ally_get' && op != 'ally_member' && (hero is! String || !heroes.contains(hero))) {
      throw const SyncError('no_hero', 'Выберите героя', status: 403);
    }
    final who = '$space|$hero';
    if (op == 'ally_create') {
      final aid = 'a${_n++}';
      docs[aid] = {
        'id': aid, 'name': b['name'], 'emblem': b['emblem'], 'motto': b['motto'], 'leader': who,
        'members': {space: {...(b['member'] as Map), 'joinedAt': 0}}, 'perms': <String, dynamic>{},
        'goals': <dynamic>[], 'feed': <dynamic>[],
      };
      links[space] = aid;
      return _out(aid);
    }
    if (op == 'ally_join') {
      final aid = invites.remove((b['code'] as String).replaceAll('-', '').toUpperCase());
      if (aid == null) throw const SyncError('bad_code', 'Код не подошёл', status: 404);
      (docs[aid]!['members'] as Map)[space] = {...(b['member'] as Map), 'joinedAt': _n++};
      links[space] = aid;
      return _out(aid);
    }
    final aid = links[space];
    if (aid == null) {
      if (op == 'ally_get') return {'ok': true, 'alliance': null, 'ver': 0};
      throw const SyncError('no_alliance', 'Вы пока не в гильдии', status: 404);
    }
    final d = docs[aid]!;
    switch (op) {
      case 'ally_get':
        if (b['ver'] == vers[aid]) return {'ok': true, 'same': true, 'ver': vers[aid]};
        return {'ok': true, 'alliance': d, 'ver': vers[aid]};
      case 'ally_member':
        (d['members'] as Map)[space] = {...(b['member'] as Map), 'joinedAt': 0};
        return _out(aid);
      case 'ally_invite':
        if (!_can(d, who, 'invite')) throw const SyncError('no_rights', 'Нет права', status: 403);
        final code = 'ALLY${_n++}'.padRight(8, 'Y');
        invites[code] = aid;
        return {'ok': true, 'code': code, 'expiresAt': 0};
      case 'ally_perms':
        if (d['leader'] != who) throw const SyncError('no_rights', 'Только глава', status: 403);
        (d['perms'] as Map)[b['target'] as String] = b['perms'];
        return _out(aid);
      case 'ally_goal_save':
        if (!_can(d, who, 'goals')) throw const SyncError('no_rights', 'Нет права', status: 403);
        final g = Map<String, dynamic>.from(b['goal'] as Map);
        (d['goals'] as List).add({...g, 'id': 'g${_n++}', 'done': false, 'contrib': <String, dynamic>{}, 'createdBy': who});
        return _out(aid);
      case 'ally_contribute':
        final g = (d['goals'] as List).cast<Map>().firstWhere((x) => x['id'] == b['goalId']);
        final c = g['contrib'] as Map;
        c[who] = ((c[who] as int?) ?? 0) + (b['amount'] as int);
        final total = c.values.fold<int>(0, (s, v) => s + (v as int));
        final completed = total >= (g['target'] as int);
        if (completed) g['done'] = true;
        return _out(aid, {'total': total, 'completed': completed});
      case 'ally_leave':
        if (role != 'adult') throw const SyncError('adults_only', 'Только взрослый', status: 403);
        (d['members'] as Map).remove(space);
        links.remove(space);
        return _out(aid, {'left': true});
    }
    throw SyncError('bad_op', op);
  }
}

/// Сервер в памяти — те же правила, что у настоящего (server/rodquest_server/core.py).
class FakeServer {
  FakeServer({this.space = 'g', FakeAllyHub? hub}) : hub = hub ?? FakeAllyHub();

  /// Id семьи на сервере (у каждого FakeServer — одна семья).
  final String space;
  final FakeAllyHub hub;
  int rev = 0;
  final entities = <String, ({int rev, String? data, String scope})>{};
  final devices = <String, ({String role, List<String> heroes, String id})>{};
  final invites = <String, String>{};
  bool offline = false;
  int _n = 0;
  String guildName = '';

  bool visible(String scope, ({String role, List<String> heroes, String id}) d) {
    if (scope == 'all') return true;
    if (scope == 'adults') return d.role == 'adult';
    if (scope.startsWith('private:')) return d.heroes.contains(scope.substring(8));
    return false;
  }

  Map<String, dynamic> _device(String role, List<String> heroes) {
    final token = 't${_n++}';
    devices[token] = (role: role, heroes: heroes, id: 'd$_n');
    return {'ok': true, 'token': token, 'guildId': space, 'deviceId': 'd$_n', 'role': role, 'guildName': guildName};
  }

  Map<String, dynamic> handle(String op, Map<String, dynamic> b, String? token) {
    if (offline) throw const SyncError('offline', 'Нет связи');
    switch (op) {
      case 'create_guild':
        guildName = b['name'] as String;
        return _device('adult', [for (final h in b['heroIds'] as List) h as String]);
      case 'join':
        final role = invites.remove((b['code'] as String).replaceAll('-', '').toUpperCase());
        if (role == null) throw const SyncError('bad_code', 'Код не подошёл', status: 404);
        return _device(role, []);
    }
    final dev = devices[token];
    if (dev == null) throw const SyncError('revoked', 'Отключено', status: 401);
    switch (op) {
      case 'invite':
        if (dev.role != 'adult') throw const SyncError('adults_only', 'Только взрослый', status: 403);
        final code = 'CODE${_n++}'.padRight(8, 'X');
        invites[code] = b['role'] as String;
        return {'ok': true, 'code': code, 'expiresAt': 0};
      case 'set_heroes':
        devices[token!] = (role: dev.role, heroes: [for (final h in b['heroIds'] as List) h as String], id: dev.id);
        return {'ok': true};
      case 'pull':
        final since = b['since'] as int;
        final out = <Map<String, dynamic>>[];
        final rows = entities.entries.where((e) => e.value.rev > since).toList()
          ..sort((a, x) => a.value.rev.compareTo(x.value.rev));
        for (final e in rows) {
          final seen = visible(e.value.scope, dev);
          if (since == 0 && (!seen || e.value.data == null)) continue;
          out.add({'k': e.key, 'r': e.value.rev, 'd': seen ? e.value.data : null});
        }
        return {'ok': true, 'rev': rev, 'changes': out, 'more': false, 'role': dev.role};
      case 'push':
        final results = <Map<String, dynamic>>[];
        for (final c in (b['changes'] as List).cast<Map<String, dynamic>>()) {
          final k = c['k'] as String, d = c['d'] as String?, base = c['base'] as int, s = c['s'] as String;
          final cur = entities[k];
          if (dev.role != 'adult' && (s == 'adults' || cur?.scope == 'adults')) {
            results.add({'k': k, 'denied': true});
            continue;
          }
          if (cur != null && cur.rev > base) {
            results.add({'k': k, 'conflict': true, 'r': cur.rev, 'd': visible(cur.scope, dev) ? cur.data : null});
            continue;
          }
          if (d == null && (cur == null || cur.data == null)) {
            results.add({'k': k, 'ok': true, 'r': cur?.rev ?? 0});
            continue;
          }
          if (cur != null && cur.data == d && cur.scope == s) {
            results.add({'k': k, 'ok': true, 'r': cur.rev});
            continue;
          }
          rev++;
          entities[k] = (rev: rev, data: d, scope: s);
          results.add({'k': k, 'ok': true, 'r': rev});
        }
        return {'ok': true, 'rev': rev, 'results': results};
      case 'leave':
        devices.remove(token);
        return {'ok': true};
      case 'devices':
        return {'ok': true, 'devices': []};
      case 'guild':
        return {'ok': true, 'role': dev.role, 'guildName': guildName};
    }
    if (op.startsWith('ally_')) return hub.handle(op, b, space, dev.heroes, dev.role);
    throw SyncError('bad_op', op);
  }

  String? data(String key) => entities[key]?.data;
}

class FakeApi implements SyncApi {
  FakeApi(this.server);
  final FakeServer server;

  @override
  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> body, {String? token}) async {
    // Как по сети: JSON туда и обратно.
    final b = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
    return jsonDecode(jsonEncode(server.handle(op, b, token))) as Map<String, dynamic>;
  }
}

class Phone {
  Phone._(this.game, this.cloud, this.storage);

  final GameController game;
  final SyncEngine cloud;
  final MemorySyncStorage storage;

  static Future<Phone> make(FakeServer server, DateTime Function() clock, {MemorySyncStorage? storage}) async {
    final game = GameController(MemoryGameRepository(), clock: clock);
    final st = storage ?? MemorySyncStorage();
    final cloud = SyncEngine(
      game: game,
      defaultUrl: 'https://test',
      api: (_) => FakeApi(server),
      storage: st,
      pollEvery: const Duration(days: 1),
      debounce: const Duration(days: 1),
    );
    addTearDown(cloud.dispose);
    await cloud.init();
    await game.load();
    cloud.start();
    return Phone._(game, cloud, st);
  }

  Future<void> sync() => cloud.syncNow();
}

void main() {
  group('Кодек 0.8', () {
    test('состояние → сущности → состояние без потерь', () async {
      final game = GameController(MemoryGameRepository(), clock: () => DateTime(2026, 10, 24, 12));
      await game.load();
      await game.createGuild(guildName: 'Дом', heroName: 'Папа', avatar: '🧙');
      await game.seedDemo();
      await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.setParentPin('1234');
      final e = SyncCodec.encode(game.syncState);
      final back = SyncCodec.encode(SyncCodec.decode(e, AppState.empty()));
      expect(back, e);
      expect(e.keys, contains('meta/guild'));
      expect(SyncCodec.scopeOf('pin/parent', e['pin/parent']!), 'adults');
      expect(e.keys.where((k) => k.startsWith('cat/')).every((k) => SyncCodec.scopeOf(k, e[k]!) == 'adults'), isTrue);
    });

    test('личная цель видна только устройствам владельца', () {
      final g = Goal(id: 'g', title: 'Секрет', tier: GoalTier.task, ownerId: 'dad', createdAt: DateTime(2026), isPrivate: true);
      expect(SyncCodec.scopeOf('goal/g', jsonEncode(g.toJson())), 'private:dad');
      g.isPrivate = false;
      expect(SyncCodec.scopeOf('goal/g', jsonEncode(g.toJson())), 'all');
    });

    test('ключи безопасные и одинаковые для одной записи', () {
      final r = XpRecord(
          heroId: 'h', goalId: 'g', tier: GoalTier.task, stat: HeroStat.mastery, xp: 1, coins: 1, at: DateTime(2026, 1, 2));
      expect(SyncCodec.recordKey(r), SyncCodec.recordKey(XpRecord.fromJson(r.toJson())));
      expect(SyncCodec.recordKey(r), matches(RegExp(r'^xp/[0-9a-f]{16}$')));
      // Хэш как у FNV-1a: «a» → e40c292c
      expect(SyncCodec.hash('a').substring(0, 8), 'e40c292c');
    });
  });

  group('Слияние 0.8', () {
    String j(Object o) => jsonEncode(o);

    test('опыт и монеты героя складываются, ступени — большая', () {
      final base = j({'id': 'h', 'xp': 100, 'coins': 10, 'statXp': {'strength': 5}, 'badges': {'a': 1}});
      final local = j({'id': 'h', 'xp': 130, 'coins': 13, 'statXp': {'strength': 35}, 'badges': {'a': 2}});
      final remote = j({'id': 'h', 'xp': 110, 'coins': 5, 'statXp': {'strength': 5}, 'badges': {'a': 1, 'b': 1}});
      final m = jsonDecode(SyncMerge.entity('hero/h', base, local, remote)!) as Map;
      expect(m['xp'], 140);
      expect(m['coins'], 8);
      expect(m['statXp'], {'strength': 35});
      expect(m['badges'], {'a': 2, 'b': 1});
    });

    test('цели сливаются по полям, удаление сильнее правки', () {
      final base = j({'id': 'g', 'title': 'A', 'done': false});
      final m = jsonDecode(SyncMerge.entity(
          'goal/g', base, j({'id': 'g', 'title': 'B', 'done': false}), j({'id': 'g', 'title': 'A', 'done': true}))!);
      expect(m, {'id': 'g', 'title': 'B', 'done': true});
      expect(SyncMerge.entity('goal/g', base, null, j({'id': 'g', 'title': 'C'})), isNull);
      expect(SyncMerge.entity('goal/g', base, j({'id': 'g', 'title': 'C'}), null), isNull);
      expect(SyncMerge.entity('goal/g', base, base, j({'x': 1})), j({'x': 1}));
      // Одинаковая прибавка с двух устройств — две прибавки.
      final h = jsonDecode(SyncMerge.entity('hero/h', j({'xp': 0}), j({'xp': 10}), j({'xp': 10}))!) as Map;
      expect(h['xp'], 20);
    });
  });

  group('Синхронизация семьи 0.8', () {
    late FakeServer server;
    late DateTime now;
    late Phone dad;

    DateTime clock() => now;

    setUp(() async {
      server = FakeServer();
      now = DateTime(2026, 10, 24, 12);
      dad = await Phone.make(server, clock);
      await dad.game.createGuild(guildName: 'Дом Смелых', heroName: 'Папа', avatar: '🧙');
      await dad.game.seedDemo();
      await dad.cloud.createGuild();
    });

    Future<Phone> joinPhone({required bool kid, String? asHero, String? newName}) async {
      final code = (await dad.cloud.invite(kid: kid)).code;
      final p = await Phone.make(server, clock);
      expect(p.game.needsOnboarding, isTrue);
      await p.cloud.join(code);
      expect(p.cloud.needsHeroPick, isTrue);
      if (asHero != null) {
        await p.cloud.pickHero(asHero);
      } else {
        await p.cloud.pickNewHero(newName ?? 'Мама', '👸');
      }
      expect(p.cloud.needsHeroPick, isFalse);
      await dad.sync();
      return p;
    }

    test('глава подключает гильдию — всё уходит на сервер', () {
      expect(dad.cloud.connected, isTrue);
      expect(dad.cloud.status, SyncStatus.idle);
      expect(server.data('meta/guild'), contains('Дом Смелых'));
      final goals = server.entities.keys.where((k) => k.startsWith('goal/')).length;
      expect(goals, dad.game.goals.length);
      // Повторная синхронизация ничего не отправляет.
      final rev = server.rev;
      return dad.sync().then((_) => expect(server.rev, rev));
    });

    test('мама входит по коду, создаёт героя и видит цели семьи', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      expect(mom.game.guildName, 'Дом Смелых');
      expect(mom.game.activeHero!.name, 'Мама');
      expect(mom.game.activeHero!.role, HeroRole.member);
      expect(mom.game.goals.map((g) => g.id).toSet(), dad.game.goals.map((g) => g.id).toSet());
      // Папа видит нового героя.
      expect(dad.game.heroes.map((h) => h.name), containsAll(['Папа', 'Мама']));
      expect(mom.game.categories, isNotEmpty);
    });

    test('оба выполняют задания одновременно — опыт не теряется', () async {
      final mom = await joinPhone(kid: false, asHero: dad.game.activeHero!.id);
      final tasks = dad.game.goals.where((g) => g.tier == GoalTier.task && !g.done).toList();
      expect(tasks.length, greaterThanOrEqualTo(2));
      final xp0 = dad.game.activeHero!.xp;
      await dad.game.completeGoal(tasks[0].id);
      await mom.game.completeGoal(tasks[1].id);
      await dad.sync();
      await mom.sync(); // конфликт по герою → слияние счётчиков
      await dad.sync();
      final expected = xp0 + tasks[0].tier.xp + tasks[1].tier.xp;
      expect(dad.game.activeHero!.xp, greaterThanOrEqualTo(expected));
      expect(mom.game.heroById(dad.game.activeHero!.id)!.xp, dad.game.activeHero!.xp);
      expect(dad.game.goalById(tasks[1].id)!.done, isTrue);
      expect(mom.game.goalById(tasks[0].id)!.done, isTrue);
      expect(SyncCodec.encode(mom.game.syncState), SyncCodec.encode(dad.game.syncState));
    });

    test('юнга: без бюджета и PIN, только детские профили, задание — на подтверждение папе', () async {
      await dad.game.setParentPin('1234');
      await dad.game.addMoney(kind: MoneyKind.expense, amount: 500);
      await dad.sync();
      final kid = await joinPhone(kid: true, newName: 'Миша');
      expect(kid.cloud.kidDevice, isTrue);
      expect(kid.game.activeHero!.role, HeroRole.child);
      expect(kid.game.money, isEmpty);
      expect(kid.game.categories, isEmpty);
      expect(kid.game.syncState.parentPinHash, isNull);
      expect(kid.game.canSwitchTo(dad.game.activeHero!.id), isFalse);
      expect(await kid.game.switchHero(dad.game.activeHero!.id), isFalse);

      final task = kid.game.goals.firstWhere((g) => g.tier == GoalTier.task && !g.done && !g.isPrivate);
      await kid.game.completeGoal(task.id);
      await kid.sync();
      await dad.sync();
      expect(dad.game.goalById(task.id)!.pendingApproval, isTrue);
      await dad.game.approve(task.id);
      await dad.sync();
      await kid.sync();
      final me = kid.game.activeHero!;
      expect(kid.game.goalById(task.id)!.done, isTrue);
      expect(me.xp, greaterThanOrEqualTo(task.tier.xp));
      expect(dad.game.heroById(me.id)!.xp, me.xp);
      // Бюджет и PIN на сервере не тронуты.
      expect(server.data('pin/parent'), isNotNull);
      expect(server.entities.keys.where((k) => k.startsWith('money/')), isNotEmpty);
    });

    test('личные цели папы не уходят на телефон мамы', () async {
      final secret = await dad.game.addGoal(title: 'Подарок маме', tier: GoalTier.task, isPrivate: true);
      await dad.sync();
      final mom = await joinPhone(kid: false, newName: 'Мама');
      expect(mom.game.syncState.goals.any((g) => g.id == secret.id), isFalse);
      // Цель стала общей — приходит.
      await dad.game.updateGoal(
        secret,
        title: secret.title,
        description: secret.description,
        tier: secret.tier,
        parentId: secret.parentId,
        ownerId: secret.ownerId,
        isFamily: secret.isFamily,
        stat: secret.stat,
        isPrivate: false,
      );
      await dad.sync();
      await mom.sync();
      expect(mom.game.syncState.goals.any((g) => g.id == secret.id), isTrue);
    });

    test('будильники звонят только на телефоне своего героя', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      final before = mom.game.reminders.length;
      await dad.game.addReminder(title: 'Подъём папы', kind: ReminderKind.alarm, hour: 13, minute: 0);
      await dad.sync();
      await mom.sync();
      expect(mom.game.reminders.length, before + 1);
      expect(mom.game.reminders.any((r) => r.title == 'Подъём папы'), isTrue);
      expect(mom.game.plannedPushes().where((p) => p.title.contains('Подъём')), isEmpty);
      expect(dad.game.plannedPushes(), isNotEmpty);
      now = DateTime(2026, 10, 24, 13, 0, 10);
      expect(mom.game.tick(), isEmpty);
      expect(dad.game.tick().any((e) => e.reminder?.title == 'Подъём папы'), isTrue);
    });

    test('без связи правки копятся и уходят потом', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      server.offline = true;
      final g = await mom.game.addGoal(title: 'Купить хлеб', tier: GoalTier.task, isFamily: true);
      await mom.sync();
      expect(mom.cloud.status, SyncStatus.offline);
      server.offline = false;
      await mom.sync();
      expect(mom.cloud.status, SyncStatus.idle);
      await dad.sync();
      expect(dad.game.goalById(g.id)?.title, 'Купить хлеб');
    });

    test('удаление цели доходит до всех', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      final g = dad.game.goals.firstWhere((g) => g.tier == GoalTier.task);
      await dad.game.deleteGoal(g.id);
      await dad.sync();
      await mom.sync();
      expect(mom.game.goalById(g.id), isNull);
    });

    test('подключение переживает перезапуск приложения', () async {
      final storage = MemorySyncStorage();
      final code = (await dad.cloud.invite(kid: false)).code;
      final p = await Phone.make(server, clock, storage: storage);
      await p.cloud.join(code);
      await p.cloud.pickNewHero('Мама', '👸');
      final again = SyncEngine(game: p.game, defaultUrl: 'x', api: (_) => FakeApi(server), storage: storage);
      await again.init();
      expect(again.connected, isTrue);
      expect(again.session!.heroes, [p.game.activeHero!.id]);
      expect(again.session!.base.length, greaterThan(10));
    });

    test('сброс данных отключает устройство, у семьи всё остаётся', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      final goals = server.entities.keys.where((k) => k.startsWith('goal/')).length;
      await mom.game.resetAll();
      expect(mom.cloud.connected, isFalse);
      expect(mom.game.needsOnboarding, isTrue);
      await dad.sync();
      expect(server.entities.keys.where((k) => k.startsWith('goal/') && server.data(k) != null).length, goals);
      expect(dad.game.goals, isNotEmpty);
    });

    test('отключённое устройство само выходит из облака', () async {
      final mom = await joinPhone(kid: false, newName: 'Мама');
      server.devices.removeWhere((t, d) => d.role == 'adult' && t != dad.cloud.session!.token);
      await mom.sync();
      expect(mom.cloud.connected, isFalse);
      expect(mom.game.goals, isNotEmpty); // данные остались
    });
  });
  group('Гильдия 0.9', () {
    late FakeAllyHub hub;
    late DateTime now;

    DateTime clock() => now;

    setUp(() {
      hub = FakeAllyHub();
      now = DateTime(2026, 10, 27, 12);
    });

    Future<Phone> family(String space, String guild, String hero, {bool solo = false, GroupKind kind = GroupKind.family}) async {
      final p = await Phone.make(FakeServer(space: space, hub: hub), clock);
      await p.game.createGuild(guildName: guild, heroName: hero, avatar: '🧙', solo: solo, kind: kind);
      return p;
    }

    test('семья основывает гильдию, клан и одиночка вступают по коду', () async {
      final dad = await family('s1', 'Ивановы', 'Папа');
      expect(dad.cloud.connected, isFalse);
      await dad.cloud.createAlliance(name: 'Северный союз', emblem: '🐺');
      // Семья подключилась к облаку сама.
      expect(dad.cloud.connected, isTrue);
      final a = dad.cloud.alliance!;
      expect(a.name, 'Северный союз');
      expect(dad.cloud.allyLeader, isTrue);
      expect(a.members.single.kind, AllyKind.family);
      expect(dad.game.feed.first.text, contains('основал(а) гильдию'));

      final clan = await family('s2', 'Волки', 'Вожак', kind: GroupKind.clan);
      final solo = await family('s3', '', 'Лёша', solo: true);
      for (final p in [clan, solo]) {
        final inv = await dad.cloud.allianceInvite();
        await p.cloud.joinAlliance(inv.code);
      }
      await dad.cloud.refreshAlliance();
      final kinds = {for (final m in dad.cloud.alliance!.members) m.kind};
      expect(kinds, {AllyKind.family, AllyKind.clan, AllyKind.solo});
      expect(solo.cloud.alliance!.member('s3')!.name, 'Лёша');
      expect(clan.cloud.allyLeader, isFalse);
      expect(clan.cloud.allyCan(AllyPerm.goals), isFalse);
    });

    test('глава даёт права, участник ставит цель, все вносят вклад и получают опыт', () async {
      final dad = await family('s1', 'Ивановы', 'Папа');
      await dad.cloud.createAlliance(name: 'Союз', emblem: '🏰');
      final mom = await family('s2', 'Петровы', 'Мама');
      await mom.cloud.joinAlliance((await dad.cloud.allianceInvite()).code);

      // Без прав — нельзя.
      await expectLater(
          mom.cloud.saveAllyGoal(title: '1000 км', emoji: '🏃', target: 1000, unit: 'км'), throwsA(isA<SyncError>()));
      await dad.cloud.setAllyPerms(mom.cloud.myRef!, {AllyPerm.goals});
      await mom.cloud.refreshAlliance();
      expect(mom.cloud.allyCan(AllyPerm.goals), isTrue);
      expect(mom.cloud.allyCan(AllyPerm.invite), isFalse);
      await mom.cloud.saveAllyGoal(title: '1000 км', emoji: '🏃', target: 10, unit: 'км');

      await dad.cloud.refreshAlliance();
      final goal = dad.cloud.alliance!.activeGoals.single;
      final r = await dad.cloud.contribute(goal, 4);
      expect(r.xp, GameController.guildXp);
      expect(dad.game.activeHero!.xp, GameController.guildXp);
      await mom.cloud.refreshAlliance();
      await mom.cloud.contribute(mom.cloud.alliance!.activeGoals.single, 6);
      final done = mom.cloud.alliance!.goals.single;
      expect(done.done, isTrue);
      expect(done.byMember('s1'), 4);
      expect(done.byMember('s2'), 6);
      expect(mom.game.feed.first.text, contains('завершил(а) цель гильдии'));
    });

    test('новый герой семьи попадает в карточку гильдии; выход из гильдии', () async {
      final dad = await family('s1', 'Ивановы', 'Папа');
      await dad.cloud.createAlliance(name: 'Союз', emblem: '🏰');
      await dad.game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await dad.sync();
      final m = dad.cloud.alliance!.member('s1')!;
      expect(m.heroes.map((h) => h.name), containsAll(['Папа', 'Миша']));
      expect(m.heroes.firstWhere((h) => h.name == 'Миша').kid, isTrue);
      await dad.cloud.leaveAlliance();
      expect(dad.cloud.alliance, isNull);
      await dad.sync();
      expect(dad.cloud.alliance, isNull);
    });

    test('гильдия хранится на устройстве и видна без связи', () async {
      final storage = MemorySyncStorage();
      final server = FakeServer(space: 's1', hub: hub);
      final p = await Phone.make(server, clock, storage: storage);
      await p.game.createGuild(guildName: 'Ивановы', heroName: 'Папа', avatar: '🧙');
      await p.cloud.createAlliance(name: 'Союз', emblem: '🏰');
      server.offline = true;
      final again = SyncEngine(game: p.game, defaultUrl: 'x', api: (_) => FakeApi(server), storage: storage);
      await again.init();
      expect(again.alliance?.name, 'Союз');
    });
  });
}
