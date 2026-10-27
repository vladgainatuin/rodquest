import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodquest/data/repository.dart';
import 'package:rodquest/data/templates.dart';
import 'package:rodquest/logic/backup.dart';
import 'package:rodquest/logic/game_rules.dart';
import 'package:rodquest/logic/push_rules.dart';
import 'package:rodquest/logic/time_rules.dart';
import 'package:rodquest/models/models.dart';
import 'package:rodquest/services/push.dart';
import 'package:rodquest/state/game_controller.dart';

void main() {
  group('Уровни', () {
    test('порог уровней растёт', () {
      expect(GameRules.levelFor(0).level, 1);
      expect(GameRules.levelFor(99).level, 1);
      expect(GameRules.levelFor(100).level, 2);
      expect(GameRules.levelFor(249).level, 2);
      expect(GameRules.levelFor(250).level, 3);
      expect(GameRules.levelFor(260).xpInLevel, 10);
    });

    test('бонус серии ограничен', () {
      expect(GameRules.dailyXp(1), 5);
      expect(GameRules.dailyXp(4), 8);
      expect(GameRules.dailyXp(100), 15);
    });
  });

  group('Контроллер', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 12);
      game = GameController(MemoryGameRepository(), clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Дом Смелых', heroName: 'Папа', avatar: '🧙');
    });

    test('цепочка: выполнение всех шагов выполняет родителя', () async {
      final epic = await game.addGoal(title: 'Эпик', tier: GoalTier.epic);
      final a = await game.addGoal(title: 'A', tier: GoalTier.task, parentId: epic.id);
      final b = await game.addGoal(title: 'B', tier: GoalTier.task, parentId: epic.id);

      await game.completeGoal(a.id);
      expect(GameRules.progress(game.goalById(epic.id)!, game.goals), closeTo(0.5, 1e-9));
      expect(game.goalById(epic.id)!.done, isFalse);

      final r = await game.completeGoal(b.id);
      expect(game.goalById(epic.id)!.done, isTrue);
      expect(r.chain, ['Эпик']);
      expect(game.activeHero!.xp, 10 + 10 + 100);
    });

    test('возврат шага отменяет авто-выполнение и опыт', () async {
      final epic = await game.addGoal(title: 'Эпик', tier: GoalTier.epic);
      final a = await game.addGoal(title: 'A', tier: GoalTier.task, parentId: epic.id);
      await game.completeGoal(a.id);
      expect(game.goalById(epic.id)!.done, isTrue);

      await game.uncompleteGoal(a.id);
      expect(game.goalById(epic.id)!.done, isFalse);
      expect(game.activeHero!.xp, 0);
    });

    test('задание юнги ждёт подтверждения', () async {
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      final t = await game.addGoal(title: 'Убрать комнату', tier: GoalTier.task, ownerId: kid.id);
      final leaderId = game.activeHero!.id;

      await game.switchHero(kid.id);
      final r = await game.completeGoal(t.id);
      expect(r.pending, isTrue);
      expect(game.heroById(kid.id)!.xp, 0);

      await game.switchHero(leaderId);
      await game.approve(t.id);
      expect(game.goalById(t.id)!.done, isTrue);
      expect(game.heroById(kid.id)!.xp, 10);
    });

    test('серия рутины растёт по дням и сгорает при пропуске', () async {
      final d = await game.addGoal(title: 'Зарядка', tier: GoalTier.daily);
      await game.toggleDaily(d.id);
      expect(game.goalById(d.id)!.streak, 1);

      now = now.add(const Duration(days: 1));
      await game.toggleDaily(d.id);
      expect(game.goalById(d.id)!.streak, 2);

      now = now.add(const Duration(days: 3));
      expect(GameRules.liveStreak(game.goalById(d.id)!, now), 0);
      await game.toggleDaily(d.id);
      expect(game.goalById(d.id)!.streak, 1);
    });

    test('удаление цели удаляет вложенные', () async {
      final legend = await game.addGoal(title: 'Л', tier: GoalTier.legend);
      final epic = await game.addGoal(title: 'Э', tier: GoalTier.epic, parentId: legend.id);
      await game.addGoal(title: 'З', tier: GoalTier.task, parentId: epic.id);
      await game.deleteGoal(legend.id);
      expect(game.goals, isEmpty);
    });

    test('состояние переживает сохранение и загрузку', () async {
      final repo = MemoryGameRepository();
      final g1 = GameController(repo, clock: () => now);
      await g1.load();
      await g1.createGuild(guildName: 'Гильдия', heroName: 'Мама', avatar: '👸');
      await g1.seedDemo();

      final g2 = GameController(repo, clock: () => now);
      await g2.load();
      expect(g2.guildName, 'Гильдия');
      expect(g2.goals.length, g1.goals.length);
      expect(g2.goals.where((g) => g.tier == GoalTier.legend).single.isFamily, isTrue);
    });
  });

  group('Версия 0.2', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 12);
      game = GameController(MemoryGameRepository(), clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Дом Смелых', heroName: 'Папа', avatar: '🧙');
    });

    test('монеты начисляются за цели и снимаются при возврате', () async {
      final epic = await game.addGoal(title: 'Эпик', tier: GoalTier.epic);
      final a = await game.addGoal(title: 'A', tier: GoalTier.task, parentId: epic.id);
      final r = await game.completeGoal(a.id);
      expect(r.coins, GoalTier.task.coins + GoalTier.epic.coins);
      expect(game.activeHero!.coins, 55);
      await game.uncompleteGoal(a.id);
      expect(game.activeHero!.coins, 0);
    });

    test('лавка: юнга покупает, взрослый выдаёт или отказывает', () async {
      final leaderId = game.activeHero!.id;
      final reward = (await game.addReward(title: 'Кино', emoji: '🎬', cost: 10))!;
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      kid.coins = 25;

      await game.switchHero(kid.id);
      expect(await game.addReward(title: 'Чит', emoji: '🎁', cost: 1), isNull);
      expect(await game.buyReward(reward.id), BuyResult.pending);
      expect(game.heroById(kid.id)!.coins, 15);
      expect(await game.buyReward(reward.id), BuyResult.pending);
      expect(await game.buyReward(reward.id), BuyResult.notEnough);

      await game.switchHero(leaderId);
      final claims = game.pendingClaims;
      expect(claims.length, 2);
      await game.grantClaim(claims[0].id);
      await game.rejectClaim(claims[1].id);
      expect(game.heroById(kid.id)!.coins, 15);
      expect(game.pendingClaims, isEmpty);
    });

    test('взрослый получает награду сразу', () async {
      final reward = (await game.addReward(title: 'Пицца', emoji: '🍕', cost: 5))!;
      game.activeHero!.coins = 5;
      expect(await game.buyReward(reward.id), BuyResult.granted);
      expect(game.activeHero!.coins, 0);
    });

    test('бюджет: сводка месяца, лимиты и копилки', () async {
      expect(game.categories.where((c) => c.kind == MoneyKind.expense), isNotEmpty);
      final food = game.categories.firstWhere((c) => c.name == 'Продукты');
      final salary = game.categories.firstWhere((c) => c.name == 'Зарплата');
      await game.addMoney(kind: MoneyKind.income, amount: 100000, categoryId: salary.id);
      await game.addMoney(kind: MoneyKind.expense, amount: 12000, categoryId: food.id);
      await game.addMoney(kind: MoneyKind.expense, amount: 3000, categoryId: food.id);
      // Прошлый месяц не попадает в сводку.
      await game.addMoney(
          kind: MoneyKind.expense, amount: 999, categoryId: food.id, date: DateTime(2026, 9, 30));
      final pot = (await game.addPot(name: 'Море', emoji: '🏖', target: 50000))!;
      await game.addMoney(kind: MoneyKind.saving, amount: 20000, potId: pot.id);
      await game.setCategoryLimit(food.id, 14000);

      final sum = GameRules.monthSummary(game.money, 2026, 10);
      expect(sum.income, 100000);
      expect(sum.expense, 15000);
      expect(sum.saved, 20000);
      expect(sum.balance, 65000);
      expect(sum.byCategory[food.id], 15000);
      expect(game.categoryById(food.id)!.limit, 14000);
      expect(GameRules.potSaved(pot.id, game.money), 20000);

      await game.deletePot(pot.id);
      expect(game.money.where((m) => m.kind == MoneyKind.saving), isEmpty);
    });

    test('юнга не видит бюджет', () async {
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect(game.canSeeBudget, isFalse);
      expect(await game.addMoney(kind: MoneyKind.expense, amount: 100, categoryId: 'cat0'), isNull);
    });

    test('сроки: просрочено, сегодня, скоро', () async {
      final old = await game.addGoal(title: 'Старое', tier: GoalTier.task, dueDate: DateTime(2026, 10, 18));
      final today = await game.addGoal(title: 'Сегодня', tier: GoalTier.task, dueDate: DateTime(2026, 10, 20));
      final far = await game.addGoal(title: 'Потом', tier: GoalTier.task, dueDate: DateTime(2026, 12, 1));
      final daily = await game.addGoal(title: 'Рутина', tier: GoalTier.daily, dueDate: DateTime(2026, 10, 19));

      expect(GameRules.dueState(old, now), DueState.overdue);
      expect(GameRules.dueState(today, now), DueState.today);
      expect(GameRules.dueState(far, now), DueState.later);
      expect(daily.dueDate, isNull);
      expect(GameRules.reminders(game.goals, now).map((g) => g.title), ['Старое', 'Сегодня']);
      expect(GameRules.dueLabel(old, now), 'просрочено на 2 дн.');

      await game.completeGoal(old.id);
      expect(GameRules.dueState(old, now), DueState.none);
    });

    test('тема: игровая для юнги, строгая для взрослых, можно выбрать свою', () async {
      expect(game.skin, AppSkin.graphite);
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect(game.skin, AppSkin.fairy);
      await game.updateHero(kid, skin: AppSkin.lagoon);
      expect(game.skin, AppSkin.lagoon);
    });

    test('данные версии 0.1 открываются и получают категории бюджета', () async {
      final repo = MemoryGameRepository();
      final v1 = {
        'schema': 1,
        'guildName': 'Старая гильдия',
        'activeHeroId': 'h1',
        'heroes': [
          {'id': 'h1', 'name': 'Мама', 'avatar': '👸', 'role': 'leader', 'xp': 120, 'statXp': {}},
        ],
        'goals': [
          {'id': 'g1', 'title': 'Цель', 'tier': 'task', 'ownerId': 'h1', 'createdAt': '2026-10-01T10:00:00.000'},
        ],
        'feed': [],
      };
      await repo.save(AppState.fromJson(jsonDecode(jsonEncode(v1)) as Map<String, dynamic>));
      final g = GameController(repo, clock: () => now);
      await g.load();
      expect(g.activeHero!.coins, 0);
      expect(g.activeHero!.skin, AppSkin.auto);
      expect(g.goals.single.dueDate, isNull);
      expect(g.categories, isNotEmpty);
    });
  });

  group('Версия 0.3', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 12);
      game = GameController(MemoryGameRepository(), clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Дом Смелых', heroName: 'Папа', avatar: '🧙');
    });

    test('журнал опыта: запись при выполнении, удаление при возврате', () async {
      final epic = await game.addGoal(title: 'Эпик', tier: GoalTier.epic);
      final a = await game.addGoal(title: 'A', tier: GoalTier.task, parentId: epic.id);
      await game.completeGoal(a.id);
      expect(game.records.length, 2); // задание + эпик по цепочке
      expect(game.records.fold<int>(0, (s, r) => s + r.xp), 110);

      await game.uncompleteGoal(a.id);
      expect(game.records, isEmpty);

      final d = await game.addGoal(title: 'Зарядка', tier: GoalTier.daily);
      await game.toggleDaily(d.id);
      expect(game.records.single.tier, GoalTier.daily);
      await game.toggleDaily(d.id);
      expect(game.records, isEmpty);
    });

    test('статистика: опыт по дням, период, серии активности', () async {
      final d = await game.addGoal(title: 'Зарядка', tier: GoalTier.daily);
      final start = DateTime(2026, 10, 14);
      // Активны 14, 15, 16 и 18–20 октября.
      for (final day in [14, 15, 16, 18, 19, 20]) {
        now = DateTime(2026, 10, day, 9);
        await game.toggleDaily(d.id);
      }
      now = DateTime(2026, 10, 20, 12);
      final perDay = GameRules.xpPerDay(game.records, start, 7);
      expect(perDay, [5, 6, 7, 0, 5, 6, 7]);

      final st = GameRules.periodStats(game.records, start, 7);
      expect(st.xp, 36);
      expect(st.dailies, 6);
      expect(st.goals, 0);
      expect(st.activeDays, 6);
      expect(st.byStat[HeroStat.mastery], 36);

      expect(GameRules.activityStreak(game.records, now), 3);
      expect(GameRules.bestActivityRun(game.records), 3);
      expect(GameRules.deltaPercent(150, 100), 50);
      expect(GameRules.deltaPercent(5, 0), isNull);
    });

    test('достижения: ступени растут, полученное не теряется', () async {
      final first = await game.addGoal(title: 'Первое', tier: GoalTier.task);
      final r = await game.completeGoal(first.id);
      expect(r.badges.map((a) => a.id), contains('first_task'));

      for (var i = 0; i < 9; i++) {
        final t = await game.addGoal(title: 'Т$i', tier: GoalTier.task);
        await game.completeGoal(t.id);
      }
      final hero = game.activeHero!;
      Achievement worker() => game.achievementsOf(hero).firstWhere((a) => a.id == 'worker');
      expect(worker().level, 1);
      expect(worker().medal, '🥉');
      expect(worker().nextTarget, 50);
      expect(hero.badges['worker'], 1);
      expect(game.feed.any((e) => e.text.contains('Трудяга')), isTrue);

      // Вернули задание — счётчик меньше 10, но бронза остаётся.
      await game.uncompleteGoal(first.id);
      expect(worker().value, 9);
      expect(worker().level, 1);
    });

    test('достижения: рекорд серии и ранняя пташка', () async {
      final d = await game.addGoal(title: 'Зарядка', tier: GoalTier.daily);
      for (var i = 0; i < 7; i++) {
        now = DateTime(2026, 10, 1 + i, 7);
        await game.toggleDaily(d.id);
      }
      expect(game.goalById(d.id)!.bestStreak, 7);
      // Пропуск: серия сгорает, рекорд остаётся.
      now = DateTime(2026, 10, 12, 10);
      await game.toggleDaily(d.id);
      expect(game.goalById(d.id)!.streak, 1);
      expect(game.goalById(d.id)!.bestStreak, 7);

      final ach = {for (final a in game.achievementsOf(game.activeHero!)) a.id: a};
      expect(ach['fire']!.unlocked, isTrue);
      expect(ach['early']!.value, 7);
      expect(ach['no_days_off']!.level, 2); // 7 дней подряд — серебро
    });

    test('чемпион недели — только если в гильдии есть с кем соревноваться', () async {
      final t = await game.addGoal(title: 'Т', tier: GoalTier.task);
      await game.completeGoal(t.id);
      expect(game.activeHero!.badges['champion'], isNull);

      await game.addHero(name: 'Мама', avatar: '👸', role: HeroRole.member);
      final t2 = await game.addGoal(title: 'Т2', tier: GoalTier.task);
      await game.completeGoal(t2.id);
      expect(game.activeHero!.badges['champion'], 1);
    });

    test('PIN: юнга не входит во взрослый профиль без PIN', () async {
      final leaderId = game.activeHero!.id;
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      final kid2 = await game.addHero(name: 'Аня', avatar: '🐱', role: HeroRole.child);
      expect(await game.setParentPin('12a4'), isFalse);
      expect(await game.setParentPin('1234'), isTrue);
      expect(game.hasParentPin, isTrue);

      await game.switchHero(kid.id); // взрослый → юнга: без PIN
      expect(game.activeHero!.id, kid.id);
      expect(game.needsPinToSwitch(leaderId), isTrue);
      expect(game.needsPinToSwitch(kid2.id), isFalse);
      expect(await game.setParentPin('0000'), isFalse); // юнга не меняет PIN

      expect(await game.switchHero(leaderId), isFalse);
      expect(await game.switchHero(leaderId, pin: '9999'), isFalse);
      expect(game.activeHero!.id, kid.id);
      expect(await game.switchHero(leaderId, pin: '1234'), isTrue);
      expect(game.activeHero!.id, leaderId);
    });

    test('PIN: пауза после 5 ошибок, смена и сброс', () async {
      await game.setParentPin('1234');
      for (var i = 0; i < 4; i++) {
        expect(game.checkPin('0000'), PinCheck.wrong);
      }
      expect(game.checkPin('0000'), PinCheck.locked);
      expect(game.checkPin('1234'), PinCheck.locked);
      now = now.add(const Duration(minutes: 2));
      expect(game.checkPin('1234'), PinCheck.ok);

      expect(await game.setParentPin('5555', oldPin: '1111'), isFalse);
      expect(await game.setParentPin('5555', oldPin: '1234'), isTrue);
      expect(game.checkPin('5555'), PinCheck.ok);

      await game.resetForgottenPin();
      expect(game.hasParentPin, isFalse);
    });

    test('PIN хранится как хэш и переживает перезапуск', () async {
      final repo = MemoryGameRepository();
      final g1 = GameController(repo, clock: () => now);
      await g1.load();
      await g1.createGuild(guildName: 'Г', heroName: 'Мама', avatar: '👸');
      await g1.setParentPin('2468');
      final saved = jsonEncode((await repo.load())!.toJson());
      expect(saved.contains('2468'), isFalse);

      final g2 = GameController(repo, clock: () => now);
      await g2.load();
      expect(g2.hasParentPin, isTrue);
      expect(g2.checkPin('2468'), PinCheck.ok);
    });

    test('данные версии 0.2 получают журнал опыта из выполненных целей', () async {
      final repo = MemoryGameRepository();
      final v2 = {
        'schema': 2,
        'guildName': 'Гильдия',
        'activeHeroId': 'h1',
        'heroes': [
          {'id': 'h1', 'name': 'Мама', 'avatar': '👸', 'role': 'leader', 'xp': 40, 'coins': 20, 'statXp': {}},
        ],
        'goals': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'g$i',
              'title': 'Цель $i',
              'tier': 'task',
              'ownerId': 'h1',
              'createdAt': '2026-10-01T10:00:00.000',
              'done': true,
              'completedById': 'h1',
              'completedAt': '2026-10-1${i}T10:00:00.000',
            },
          {'id': 'd', 'title': 'Рутина', 'tier': 'daily', 'ownerId': 'h1', 'createdAt': '2026-10-01T10:00:00.000', 'streak': 3},
        ],
        'feed': [],
      };
      await repo.save(AppState.fromJson(jsonDecode(jsonEncode(v2)) as Map<String, dynamic>));
      final g = GameController(repo, clock: () => now);
      await g.load();
      expect(g.records.length, 4);
      expect(g.goalById('d')!.bestStreak, 3);
      // Достижение за первое задание выдано тихо, без поздравлений в ленте.
      expect(g.activeHero!.badges['first_task'], 1);
      expect(g.feed.where((e) => e.emoji == '🏆'), isEmpty);
      expect(g.hasParentPin, isFalse);
    });
  });

  group('Версия 0.4', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 12); // вторник
      game = GameController(MemoryGameRepository(), clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Дом Смелых', heroName: 'Папа', avatar: '🧙');
    });

    test('еженедельная: серия по неделям, пунктуальность в день по плану', () async {
      final g = await game.addGoal(title: 'Уборка', tier: GoalTier.daily, repeat: Repeat.weekly, weekdays: const [6]);
      expect(GameRules.scheduleLabel(g), 'по субботам');

      final r1 = await game.toggleDaily(g.id); // вторник — не по плану
      expect(r1.xp, 20);
      expect(r1.coins, 8);
      expect(r1.traits[HeroTrait.punctuality], isNull);
      expect(r1.traits[HeroTrait.habit], 4);
      expect(GameRules.isDoneToday(g, DateTime(2026, 10, 25)), isTrue); // до конца недели — выполнено

      now = DateTime(2026, 10, 31, 10); // суббота следующей недели
      expect(GameRules.isPlannedDay(g, now), isTrue);
      final r2 = await game.toggleDaily(g.id);
      expect(game.goalById(g.id)!.streak, 2);
      expect(r2.xp, 22);
      expect(r2.traits[HeroTrait.punctuality], 5);
      expect(r2.traits[HeroTrait.endurance], 2);
      expect(game.activeHero!.traitXp[HeroTrait.punctuality], 5);

      // Неделю пропустили — серия начинается заново.
      now = DateTime(2026, 11, 12, 10);
      expect(GameRules.liveStreak(game.goalById(g.id)!, now), 0);
      await game.toggleDaily(g.id);
      expect(game.goalById(g.id)!.streak, 1);
      expect(game.goalById(g.id)!.bestStreak, 2);
    });

    test('ежедневная по дням недели: другие дни не сбивают серию', () async {
      final g = await game.addGoal(
          title: 'Пробежка', tier: GoalTier.daily, weekdays: const [5, 1, 3, 3]); // пн, ср, пт
      expect(g.weekdays, [1, 3, 5]);
      expect(GameRules.scheduleLabel(g), 'пн, ср, пт');

      // Вторник: отметить нельзя.
      expect(GameRules.canDoNow(g, now), isFalse);
      final r = await game.toggleDaily(g.id);
      expect(r.xp, 0);
      expect(game.goalById(g.id)!.lastDoneDay, isNull);

      now = DateTime(2026, 10, 19, 8); // пн
      await game.toggleDaily(g.id);
      now = DateTime(2026, 10, 21, 8); // ср
      await game.toggleDaily(g.id);
      expect(game.goalById(g.id)!.streak, 2);
      now = DateTime(2026, 10, 26, 8); // пн — пятницу пропустили
      await game.toggleDaily(g.id);
      expect(game.goalById(g.id)!.streak, 1);
      expect(game.records.where((x) => x.onTime).length, 3);
    });

    test('ежемесячная: 31-е в ноябре — это 30-е; отмена возвращает черты', () async {
      final g = await game.addGoal(title: 'Счета', tier: GoalTier.daily, repeat: Repeat.monthly, monthDay: 31);
      expect(GameRules.scheduleLabel(g), '31-го числа');
      expect(GameRules.isPlannedDay(g, DateTime(2026, 11, 30)), isTrue);
      expect(GameRules.isPlannedDay(g, DateTime(2026, 11, 29)), isFalse);

      now = DateTime(2026, 11, 30, 9);
      final r = await game.toggleDaily(g.id);
      expect(r.xp, 50);
      expect(r.traits[HeroTrait.punctuality], 10);
      final hero = game.activeHero!;
      expect(hero.coins, 25);

      await game.toggleDaily(g.id); // отмена
      expect(hero.xp, 0);
      expect(hero.coins, 0);
      expect(hero.traitXp.values.every((v) => v == 0), isTrue);
      expect(game.records, isEmpty);

      // Смена периода сбрасывает серию.
      await game.toggleDaily(g.id);
      await game.updateGoal(game.goalById(g.id)!,
          title: 'Счета',
          description: '',
          tier: GoalTier.daily,
          parentId: null,
          ownerId: hero.id,
          isFamily: false,
          stat: HeroStat.mastery,
          repeat: Repeat.weekly);
      expect(game.goalById(g.id)!.streak, 0);
      expect(game.goalById(g.id)!.monthDay, isNull);
    });

    test('уровни черт характера', () {
      expect(GameRules.traitLevel(0).level, 1);
      expect(GameRules.traitLevel(30).level, 2);
      expect(GameRules.traitLevel(79).level, 2);
      expect(GameRules.traitLevel(80).level, 3);
    });

    test('личная цель видна только владельцу, вложенные наследуют', () async {
      final papaId = game.activeHero!.id;
      final mama = await game.addHero(name: 'Мама', avatar: '👸', role: HeroRole.member);
      final secret = await game.addGoal(title: 'Подарок маме', tier: GoalTier.quest, isPrivate: true, isFamily: true);
      final step = await game.addGoal(title: 'Выбрать подарок', tier: GoalTier.task, parentId: secret.id);
      expect(secret.isFamily, isFalse);
      expect(step.isPrivate, isTrue);
      expect(step.ownerId, papaId);
      expect(game.goals.length, 2);

      await game.completeGoal(step.id);
      expect(game.feed.any((e) => e.text.contains('Подарок') || e.text.contains('Выбрать')), isFalse);

      await game.switchHero(mama.id);
      expect(game.goals, isEmpty);
      expect(game.canEdit(secret), isFalse);
    });

    test('режим «Только я»: без гильдии, PIN и семейных достижений', () async {
      final repo = MemoryGameRepository();
      final g = GameController(repo, clock: () => now);
      await g.load();
      await g.createGuild(guildName: '', heroName: 'Аня', avatar: '🦊', solo: true);
      expect(g.solo, isTrue);
      expect(g.guildName, contains('Аня'));
      await g.seedDemo();
      expect(g.goals.where((x) => x.repeat == Repeat.weekly), isNotEmpty);
      expect(g.goals.any((x) => x.isFamily), isFalse);
      final fam = await g.addGoal(title: 'Т', tier: GoalTier.task, isFamily: true);
      expect(fam.isFamily, isFalse);
      final ids = g.achievementsOf(g.activeHero!).map((a) => a.id);
      expect(ids, isNot(contains('champion')));
      expect(ids, isNot(contains('team')));
      expect(ids, contains('weekly'));

      // Пригласили семью — режим стал семейным.
      expect(await g.setSolo(false, guildName: 'Лисья нора'), isTrue);
      expect(g.guildName, 'Лисья нора');
      await g.addHero(name: 'Миша', avatar: '🐻', role: HeroRole.child);
      expect(await g.setSolo(true), isFalse); // героев уже двое

      final g2 = GameController(repo, clock: () => now);
      await g2.load();
      expect(g2.solo, isFalse);
      expect(g2.heroes.length, 2);
    });

    test('данные версии 0.3 открываются: рутина ежедневная, черты по нулям', () async {
      final repo = MemoryGameRepository();
      final v3 = {
        'schema': 3,
        'guildName': 'Гильдия',
        'activeHeroId': 'h1',
        'heroes': [
          {'id': 'h1', 'name': 'Мама', 'avatar': '👸', 'role': 'leader', 'xp': 10, 'statXp': {}, 'badges': {}},
        ],
        'goals': [
          {
            'id': 'd',
            'title': 'Зарядка',
            'tier': 'daily',
            'ownerId': 'h1',
            'createdAt': '2026-10-01T10:00:00.000',
            'streak': 2,
            'lastDoneDay': '2026-10-19',
          },
        ],
        'feed': [],
        'records': [],
      };
      await repo.save(AppState.fromJson(jsonDecode(jsonEncode(v3)) as Map<String, dynamic>));
      final g = GameController(repo, clock: () => now);
      await g.load();
      final d = g.goalById('d')!;
      expect(d.repeat, Repeat.daily);
      expect(d.weekdays, isEmpty);
      expect(d.isPrivate, isFalse);
      expect(g.solo, isFalse);
      expect(g.activeHero!.traitXp[HeroTrait.habit], 0);
      await g.toggleDaily('d');
      expect(g.goalById('d')!.streak, 3); // серия из 0.3 продолжается
    });
  });

  group('Версия 0.5', () {
    late DateTime now;
    late MemoryGameRepository repo;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 6, 50); // вторник
      repo = MemoryGameRepository();
      game = GameController(repo, clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Дом', heroName: 'Папа', avatar: '🧙');
    });

    test('будильник по будням: звонит один раз, «Отложить», подъём вовремя', () async {
      final r = (await game.addReminder(
          title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 0, weekdays: const [1, 2, 3, 4, 5], wakeUp: true))!;
      expect(TimeRules.nextOccurrence(r, now), DateTime(2026, 10, 20, 7));
      // Пятница после звонка → следующий в понедельник.
      expect(TimeRules.nextOccurrence(r, DateTime(2026, 10, 23, 8)), DateTime(2026, 10, 26, 7));
      expect(game.tick(), isEmpty);

      now = DateTime(2026, 10, 20, 7, 0, 3);
      final ring = game.tick();
      expect(ring.single.kind, TickKind.alarm);
      expect(game.tick(), isEmpty, reason: 'не звонит дважды');

      await game.snooze(r.id);
      now = DateTime(2026, 10, 20, 7, 4);
      expect(game.tick(), isEmpty);
      now = DateTime(2026, 10, 20, 7, 5, 10);
      final again = game.tick();
      expect(again.single.kind, TickKind.alarm);

      final res = await game.dismissAlarm(r.id, again.single.at);
      expect(res.xp, 5);
      expect(game.activeHero!.traitXp[HeroTrait.punctuality], 2);
      expect(game.reminderById(r.id)!.snoozedUntil, isNull);
      // Второй подъём за день опыт не даёт.
      final second = await game.dismissAlarm(r.id, again.single.at);
      expect(second.xp, 0);
      // В статистике это опыт, но не «выполненная цель».
      final st = GameRules.periodStats(game.records, DateTime(2026, 10, 20), 1);
      expect(st.xp, 5);
      expect(st.goals, 0);
    });

    test('после перезапуска будильник из прошлого — пропущенный, а не звонок', () async {
      await game.addReminder(title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 0);
      now = DateTime(2026, 10, 20, 8, 15);
      final reopened = GameController(repo, clock: () => now);
      await reopened.load();
      final ev = reopened.tick();
      expect(ev.single.kind, TickKind.missed);
      expect(reopened.tick(), isEmpty);
    });

    test('разовое напоминание выключается после звонка', () async {
      final r = (await game.addReminder(
          title: 'Позвонить в банк', kind: ReminderKind.reminder, hour: 9, minute: 0, date: DateTime(2026, 10, 20)))!;
      expect(r.oneTime, isTrue);
      now = DateTime(2026, 10, 20, 9, 0, 2);
      expect(game.tick().single.kind, TickKind.reminder);
      expect(game.reminderById(r.id)!.enabled, isFalse);
      expect(TimeRules.nextRing(game.reminderById(r.id)!, now), isNull);
    });

    test('таймер «успеть за время»: бонус, выполнение цели и звонок по окончании', () async {
      final task = await game.addGoal(title: 'Уборка', tier: GoalTier.task, area: LifeArea.home);
      final t = (await game.startTimer(title: '', mode: TimerMode.countdown, plannedSec: 15 * 60, goalId: task.id))!;
      expect(t.title, 'Уборка');
      expect(t.area, LifeArea.home);
      expect(await game.startTimer(title: 'Второй', mode: TimerMode.stopwatch), isNull, reason: 'один таймер на героя');

      now = now.add(const Duration(minutes: 12));
      final res = await game.finishTimer(completeGoal: true);
      expect(res.session!.beat, isTrue);
      expect(res.session!.xp, 2 + TimeRules.beatBonusXp);
      expect(game.goalById(task.id)!.done, isTrue);
      expect(res.reward.xp, 7 + 10);
      expect(TimeRules.bestTimeFor(task.id, game.sessions), 12 * 60);
      expect(game.activeTimer, isNull);

      await game.startTimer(title: 'Отчёт', mode: TimerMode.countdown, plannedSec: 600);
      now = now.add(const Duration(minutes: 11));
      final ev = game.tick();
      expect(ev.single.kind, TickKind.timerDone);
      expect(game.tick(), isEmpty);
      final late = await game.finishTimer();
      expect(late.session!.beat, isFalse);
    });

    test('таймер: пауза не считается, опыт за день ограничен, удаление возвращает опыт', () async {
      await game.startTimer(title: 'Английский', mode: TimerMode.stopwatch, area: LifeArea.study);
      now = now.add(const Duration(minutes: 10));
      await game.pauseTimer();
      now = now.add(const Duration(minutes: 30));
      await game.resumeTimer();
      now = now.add(const Duration(minutes: 5));
      expect(game.activeTimer!.elapsedSec(now), 15 * 60);
      final a = await game.finishTimer();
      expect(a.session!.xp, 3);

      await game.startTimer(title: 'Долго', mode: TimerMode.stopwatch);
      now = now.add(const Duration(hours: 3));
      expect((await game.finishTimer()).session!.xp, 24);
      await game.startTimer(title: 'Ещё', mode: TimerMode.stopwatch);
      now = now.add(const Duration(hours: 2));
      final c = await game.finishTimer();
      expect(c.session!.xp, TimeRules.focusXpPerDay - 27);

      final xpBefore = game.activeHero!.xp;
      await game.deleteSession(c.session!.id);
      expect(game.activeHero!.xp, xpBefore - c.session!.xp);
      expect(game.sessions.length, 2);
    });

    test('навык: стартовая точка, рекорд, опыт раз в день, удаление замера', () async {
      final s = (await game.addSkill(name: 'Отжимания', emoji: '💪', unit: 'раз', area: LifeArea.sport))!;
      expect(s.stat, HeroStat.strength);
      final (e1, r1) = await game.addSkillEntry(s.id, 20);
      expect(e1!.pb, isFalse, reason: 'первый замер — стартовая точка');
      expect(r1.xp, TimeRules.practiceXp);
      final (e2opt, r2) = await game.addSkillEntry(s.id, 25);
      final e2 = e2opt!;
      expect(e2.pb, isTrue);
      expect(r2.xp, TimeRules.pbXp);
      final (e3, r3) = await game.addSkillEntry(s.id, 30);
      expect(e3!.pb, isTrue);
      expect(r3.xp, 0, reason: 'бонус за рекорд — раз в день');
      now = now.add(const Duration(days: 1));
      final (e4, r4) = await game.addSkillEntry(s.id, 28);
      expect(e4!.pb, isFalse);
      expect(r4.xp, TimeRules.practiceXp);
      expect(TimeRules.personalBest(s, game.skillEntries), 30);
      expect(game.activeHero!.xp, 3 + 15 + 3);
      expect(game.achievementsOf(game.activeHero!).firstWhere((a) => a.id == 'record').level, 1);

      await game.deleteSkillEntry(e2.id);
      expect(game.activeHero!.xp, 6);

      final run = (await game.addSkill(
          name: 'Бег 1 км', emoji: '🏃', timed: true, better: SkillBetter.lower, target: 270))!;
      await game.addSkillEntry(run.id, 300);
      final (fast, _) = await game.addSkillEntry(run.id, 290);
      expect(fast!.pb, isTrue);
      expect(TimeRules.formatValue(run, 290), '4:50');
      expect(TimeRules.parseValue('4:50', timed: true), 290);
      expect(TimeRules.targetProgress(run, game.skillEntries), closeTo(1 / 3, 1e-9));
      expect(TimeRules.formatValue(s, 12.5), '12,5');
    });

    test('секундомер для навыка «на время» сам записывает замер', () async {
      final plank = (await game.addSkill(name: 'Планка', emoji: '🧱', timed: true))!;
      await game.startTimer(title: '', mode: TimerMode.stopwatch, skillId: plank.id);
      now = now.add(const Duration(seconds: 95));
      final res = await game.finishTimer();
      expect(res.entry!.value, 95);
      expect(TimeRules.entriesOf(plank.id, game.skillEntries).length, 1);
    });

    test('шаблон «Финансовая подушка» создаёт цепочку; юнга шаблоны не применяет', () async {
      final t = goalTemplates.firstWhere((t) => t.id == 'safety_cushion');
      final top = (await game.applyTemplate(t, private: true))!;
      expect(top.tier, GoalTier.epic);
      expect(game.goals.length, t.count);
      expect(game.goals.every((g) => g.area == LifeArea.finance && g.isPrivate), isTrue);
      expect(game.goals.where((g) => g.isDaily).single.repeat, Repeat.monthly);

      // Все шаблоны собираются по правилам вложенности рангов.
      for (final tpl in goalTemplates) {
        void check(TplNode n, GoalTier? parent) {
          if (parent != null) expect(n.tier.allowedParents, contains(parent), reason: '${tpl.id}: ${n.title}');
          for (final k in n.children) {
            check(k, n.tier);
          }
        }

        for (final n in tpl.nodes) {
          check(n, null);
        }
      }

      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect(await game.applyTemplate(t), isNull);
    });

    test('разделы жизни: опыт по разделам и достижение «Гармония»', () async {
      for (final a in [LifeArea.health, LifeArea.finance, LifeArea.family]) {
        final g = await game.addGoal(title: a.label, tier: GoalTier.task, area: a);
        await game.completeGoal(g.id);
      }
      final step = await game.addGoal(
          title: 'Шаг', tier: GoalTier.task, parentId: (await game.addGoal(title: 'Квест', tier: GoalTier.quest, area: LifeArea.docs)).id);
      expect(step.area, LifeArea.docs, reason: 'шаг наследует раздел');
      final st = GameRules.periodStats(game.records, DateTime(2026, 10, 20), 1);
      expect(st.byArea.length, 3);
      expect(st.byArea[LifeArea.finance], 10);
      expect(game.achievementsOf(game.activeHero!).firstWhere((a) => a.id == 'balance').level, 1);

      final g = game.goals.firstWhere((g) => g.area == LifeArea.health);
      await game.updateGoal(g,
          title: g.title,
          description: '',
          tier: g.tier,
          parentId: null,
          ownerId: g.ownerId,
          isFamily: false,
          stat: g.stat,
          area: null);
      expect(game.goalById(g.id)!.area, isNull);
    });

    test('финансовые цели и бюджет: сумма цели, «Отложить», авто-выполнение', () async {
      final epic = await game.addGoal(title: 'Подушка', tier: GoalTier.epic, area: LifeArea.finance);
      final pot = (await game.setGoalSavingTarget(epic.id, 100000))!;
      expect(pot.goalId, epic.id);
      expect(game.pots.single.target, 100000);

      // Рутина внутри цели пополняет копилку цели и отмечается выполненной.
      final routine = await game.addGoal(
          title: 'Отложить 10%', tier: GoalTier.daily, repeat: Repeat.monthly, parentId: epic.id);
      expect(game.potForGoal(routine.id)!.id, pot.id);
      final (e, r) = await game.depositToGoal(routine.id, 15000);
      expect(e!.kind, MoneyKind.saving);
      expect(e.potId, pot.id);
      expect(GameRules.isDoneToday(game.goalById(routine.id)!, now), isTrue);
      expect(r.xp, Repeat.monthly.baseXp);
      expect(GameRules.monthSummary(game.money, 2026, 10).saved, 15000);
      expect(game.goalById(epic.id)!.done, isFalse);

      await game.setGoalSavingTarget(epic.id, 120000);
      expect(game.pots.single.target, 120000);

      // Цель без шагов выполняется, когда копилка наполнилась.
      final laptop = await game.addGoal(title: 'Ноутбук', tier: GoalTier.quest, area: LifeArea.finance);
      await game.setGoalSavingTarget(laptop.id, 50000);
      await game.depositToGoal(laptop.id, 30000);
      expect(game.goalById(laptop.id)!.done, isFalse);
      final (_, done) = await game.depositToGoal(laptop.id, 20000);
      expect(game.goalById(laptop.id)!.done, isTrue);
      expect(done.xp, GoalTier.quest.xp);

      // Пусто — отвязать копилку, деньги остаются в бюджете.
      await game.setGoalSavingTarget(laptop.id, null);
      expect(game.ownPotOf(laptop.id), isNull);
      expect(game.pots.length, 2);

      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect((await game.depositToGoal(epic.id, 100)).$1, isNull);
    });

    test('новые данные переживают перезапуск, данные 0.4 открываются', () async {
      await game.addReminder(title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 30, wakeUp: true);
      final s = (await game.addSkill(name: 'Чтение', emoji: '📖', unit: 'стр.'))!;
      await game.addSkillEntry(s.id, 12);
      await game.startTimer(title: 'Фокус', mode: TimerMode.countdown, plannedSec: 1500);
      await game.updateHero(game.activeHero!, skin: AppSkin.espresso);

      final again = GameController(repo, clock: () => now);
      await again.load();
      expect(again.reminders.single.timeLabel, '07:30');
      expect(again.reminders.single.wakeUp, isTrue);
      expect(again.skillEntries.single.value, 12);
      expect(again.activeTimer!.plannedSec, 1500);
      expect(again.records.single.kind, XpKind.skill);
      expect(again.skin, AppSkin.espresso);

      final old = AppState.fromJson({
        'schema': 4,
        'guildName': 'Старый дом',
        'heroes': [
          {'id': 'h1', 'name': 'Аня', 'avatar': '👸', 'role': 'leader'},
        ],
        'goals': [
          {'id': 'g1', 'title': 'Задание', 'tier': 'task', 'ownerId': 'h1', 'createdAt': '2026-10-01T10:00:00.000'},
        ],
        'records': [
          {'h': 'h1', 'g': 'g1', 't': 'task', 's': 'mastery', 'x': 10, 'c': 5, 'a': '2026-10-01T10:00:00.000'},
        ],
      });
      expect(old.reminders, isEmpty);
      expect(old.skills, isEmpty);
      expect(old.goals.single.area, isNull);
      expect(old.records.single.kind, XpKind.goal);
      expect(jsonDecode(jsonEncode(old.toJson()))['schema'], AppState.schemaVersion);
    });
  });

  group('Версия 0.6', () {
    late DateTime now;
    late MemoryGameRepository repo;
    late FakePush push;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 20, 6, 50); // вторник
      repo = MemoryGameRepository();
      push = FakePush();
      game = GameController(repo, clock: () => now, push: push);
      await game.load();
      await game.createGuild(guildName: 'Дом', heroName: 'Папа', avatar: '🧙');
    });

    test('номер уведомления стабилен и помещается в 31 бит', () {
      final a = PushRules.idFor('weekly|r1|2|07:00');
      expect(a, PushRules.idFor('weekly|r1|2|07:00'));
      expect(a, isNot(PushRules.idFor('weekly|r1|3|07:00')));
      for (final k in ['', 'a', 'будильник', 'x' * 500]) {
        final id = PushRules.idFor(k);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('расписание: будни по дням недели, каждый день, разово, выключенные — нет', () async {
      await game.addReminder(
          title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 0, weekdays: const [1, 2, 3, 4, 5], wakeUp: true);
      await game.addReminder(title: 'Таблетки', kind: ReminderKind.reminder, hour: 21, minute: 0);
      await game.addReminder(
          title: 'Позвонить в банк', kind: ReminderKind.reminder, hour: 9, minute: 30, date: DateTime(2026, 10, 22));
      final off = (await game.addReminder(title: 'Выключен', kind: ReminderKind.alarm, hour: 8, minute: 0))!;
      await game.setReminderEnabled(off.id, false);

      final plan = game.plannedPushes();
      final alarms = plan.where((p) => p.kind == PushKind.alarm).toList();
      expect(alarms.length, 5);
      expect(alarms.every((p) => p.repeat == PushRepeat.weekly), isTrue);
      expect(alarms.map((p) => p.at.weekday).toSet(), {1, 2, 3, 4, 5});
      expect(alarms.first.at, DateTime(2026, 10, 20, 7), reason: 'сегодня вторник, 7:00 ещё впереди');
      expect(alarms.firstWhere((p) => p.at.weekday == 1).at, DateTime(2026, 10, 26, 7));
      expect(alarms.map((p) => p.id).toSet().length, 5);
      expect(alarms.first.title, '⏰ Подъём');

      final daily = plan.singleWhere((p) => p.repeat == PushRepeat.daily);
      expect(daily.at, DateTime(2026, 10, 20, 21));
      expect(daily.kind, PushKind.reminder);

      final once = plan.singleWhere((p) => p.title.contains('банк'));
      expect(once.repeat, PushRepeat.none);
      expect(once.at, DateTime(2026, 10, 22, 9, 30));
      expect(plan.any((p) => p.title.contains('Выключен')), isFalse);

      // Время уже прошло сегодня — первый звонок завтра.
      now = DateTime(2026, 10, 20, 21, 30);
      expect(game.plannedPushes().singleWhere((p) => p.repeat == PushRepeat.daily).at, DateTime(2026, 10, 21, 21));
      // Разовое из прошлого больше не планируется.
      now = DateTime(2026, 10, 23, 8);
      expect(game.plannedPushes().any((p) => p.title.contains('банк')), isFalse);
    });

    test('«Отложить», таймер и личная цель в уведомлении', () async {
      final secret = await game.addGoal(title: 'Подарок жене', tier: GoalTier.task, isPrivate: true);
      final r = (await game.addReminder(
          title: 'Купить', kind: ReminderKind.reminder, hour: 18, minute: 0, goalId: secret.id))!;
      final p = game.plannedPushes().single;
      expect(p.body, contains('личная цель'));
      expect(p.body, isNot(contains('Подарок')));

      await game.snooze(r.id);
      final snoozed = game.plannedPushes().where((x) => x.at == DateTime(2026, 10, 20, 6, 55)).toList();
      expect(snoozed.single.repeat, PushRepeat.none);

      await game.startTimer(title: 'Уборка', mode: TimerMode.countdown, plannedSec: 1500);
      final timer = game.plannedPushes().singleWhere((x) => x.kind == PushKind.timer);
      expect(timer.at, DateTime(2026, 10, 20, 7, 15));
      expect(timer.body, contains('Уборка'));

      await game.pauseTimer();
      expect(game.plannedPushes().any((x) => x.kind == PushKind.timer), isFalse, reason: 'на паузе не звонит');
      now = DateTime(2026, 10, 20, 7, 0);
      await game.resumeTimer();
      expect(game.plannedPushes().singleWhere((x) => x.kind == PushKind.timer).at, DateTime(2026, 10, 20, 7, 25));
    });

    test('сроки целей: утром в день срока, выполненные и личные — без названий', () async {
      await game.addGoal(title: 'Сдать отчёт', tier: GoalTier.task, dueDate: DateTime(2026, 10, 21));
      await game.addGoal(title: 'Записаться к врачу', tier: GoalTier.task, dueDate: DateTime(2026, 10, 22));
      await game.addGoal(title: 'Тайна', tier: GoalTier.task, dueDate: DateTime(2026, 10, 22), isPrivate: true);
      final done = await game.addGoal(title: 'Готово', tier: GoalTier.task, dueDate: DateTime(2026, 10, 23));
      await game.completeGoal(done.id);
      await game.addGoal(title: 'Далеко', tier: GoalTier.task, dueDate: DateTime(2026, 12, 31));

      final due = game.plannedPushes().where((p) => p.kind == PushKind.deadline).toList();
      expect(due.length, 2);
      expect(due[0].at, DateTime(2026, 10, 21, 9));
      expect(due[0].title, '⏰ Срок сегодня');
      expect(due[0].body, '«Сдать отчёт»');
      expect(due[1].title, '⏰ Сроки сегодня: 2');
      expect(due[1].body, contains('«Записаться к врачу»'));
      expect(due[1].body, isNot(contains('Тайна')));
      expect(due[1].body, contains('личных: 1'));

      // Сегодня после 9 утра о сегодняшнем сроке уже не напоминаем.
      now = DateTime(2026, 10, 21, 10);
      expect(game.plannedPushes().where((p) => p.kind == PushKind.deadline).length, 1);
    });

    test('не больше 60 уведомлений: будильники важнее сроков', () async {
      for (var i = 0; i < 12; i++) {
        await game.addReminder(
            title: 'Будильник $i', kind: ReminderKind.alarm, hour: 6, minute: i, weekdays: const [1, 2, 3, 4, 5, 6]);
      }
      for (var d = 1; d <= 10; d++) {
        await game.addGoal(title: 'Срок $d', tier: GoalTier.task, dueDate: DateTime(2026, 10, 20 + d));
      }
      final plan = game.plannedPushes();
      expect(plan.length, PushRules.limit);
      expect(plan.where((p) => p.kind == PushKind.alarm).length, 60);
      expect(plan.any((p) => p.kind == PushKind.deadline), isFalse);
    });

    test('свернули — уведомления запланированы, открыли — сняты', () async {
      expect(push.clears, 1, reason: 'при запуске снимаем старые');
      await game.addReminder(title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 0);
      expect(push.scheduled, isEmpty, reason: 'пока приложение открыто, звонит оно само');

      await game.setBackground(true);
      expect(game.inBackground, isTrue);
      expect(push.scheduled.single.title, '⏰ Подъём');

      // Изменения в фоне сразу попадают в расписание.
      await game.addReminder(title: 'Вода', kind: ReminderKind.reminder, hour: 12, minute: 0);
      await Future<void>.delayed(Duration.zero);
      expect(push.scheduled.length, 2);

      await game.setBackground(false);
      expect(push.scheduled, isEmpty);
      expect(push.clears, 2);

      // Пока приложение было свёрнуто, будильник прозвенел — при возвращении
      // приложение покажет его само (окно будильника, если опоздание меньше 30 мин).
      await game.setBackground(true);
      now = DateTime(2026, 10, 20, 7, 3);
      await game.setBackground(false);
      expect(game.tick().first.kind, TickKind.alarm);

      await game.resetAll();
      expect(push.scheduled, isEmpty);
    });

    test('резервная копия: сохранить и восстановить на новом устройстве', () async {
      final epic = await game.addGoal(title: 'Отпуск', tier: GoalTier.epic, isFamily: true);
      final t = await game.addGoal(title: 'Билеты', tier: GoalTier.task, parentId: epic.id);
      await game.completeGoal(t.id);
      await game.addReminder(title: 'Подъём', kind: ReminderKind.alarm, hour: 6, minute: 0);
      await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      expect(await game.setParentPin('2468'), isTrue);
      expect(game.canBackup, isTrue);
      expect(game.backupFileName, 'rodquest-2026-10-20-0650.json');

      final text = game.exportBackup();
      final data = Backup.decode(text);
      expect(data.guildName, 'Дом');
      expect(data.heroCount, 2);
      expect(data.goalCount, game.goals.length);
      expect(data.doneCount, 2, reason: 'задание и эпик по цепочке');
      expect(data.exportedAt, now);
      expect(data.appVersion, Backup.appVersion);

      now = DateTime(2026, 10, 21, 8);
      final fresh = GameController(MemoryGameRepository(), clock: () => now, push: FakePush());
      await fresh.load();
      expect(fresh.needsOnboarding, isTrue);
      expect(await fresh.restoreBackup(data), isTrue);
      expect(fresh.guildName, 'Дом');
      expect(fresh.heroes.length, 2);
      expect(fresh.goalById(epic.id)!.done, isTrue);
      expect(fresh.activeHero!.xp, game.activeHero!.xp);
      expect(fresh.checkPin('2468'), PinCheck.ok);
      expect(fresh.feed.first.text, contains('резервной копии'));
      // Будильник в 6:00 уже прошёл — после восстановления он не звонит и не «пропущен».
      expect(fresh.tick(), isEmpty);
    });

    test('резервная копия: юнга не восстанавливает, чужие и новые файлы не читаются', () async {
      final data = Backup.decode(game.exportBackup());
      final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect(game.canBackup, isFalse);
      expect(await game.restoreBackup(data), isFalse);
      expect(game.heroes.length, 2);

      expect(() => Backup.decode('не json'), throwsA(isA<BackupException>()));
      expect(() => Backup.decode('[1, 2]'), throwsA(isA<BackupException>()));
      expect(() => Backup.decode('{"app": "other", "state": {}}'), throwsA(isA<BackupException>()));
      expect(() => Backup.decode('{"app": "rodquest", "format": 1, "state": {"schema": 99, "heroes": []}}'),
          throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('новой версии'))));
      expect(() => Backup.decode('{"app": "rodquest", "format": 1, "state": {"heroes": [], "goals": []}}'),
          throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('нет ни одного героя'))));

      // «Голое» состояние (без обёртки) тоже подходит; метка BOM не мешает.
      final raw = jsonEncode((jsonDecode(game.exportBackup()) as Map)['state']);
      expect(Backup.decode('\uFEFF$raw').heroCount, 2);
    });
  });
  group('Версия 0.9', () {
    late DateTime now;
    late GameController game;

    setUp(() async {
      now = DateTime(2026, 10, 27, 9); // вторник
      game = GameController(MemoryGameRepository(), clock: () => now);
      await game.load();
      await game.createGuild(guildName: 'Волки', heroName: 'Папа', avatar: '🧙', kind: GroupKind.clan);
    });

    test('семья или клан: слова и роль главы меняются, данные переживают перезапуск', () async {
      expect(game.groupKind, GroupKind.clan);
      expect(Words.group, 'Клан');
      expect(HeroRole.leader.label, 'Глава клана');
      expect(game.feed.first.text, contains('клан «Волки»'));
      expect(await game.setGroupKind(GroupKind.family), isTrue);
      expect(Words.group, 'Семья');
      expect(HeroRole.leader.label, 'Глава семьи');
      final back = AppState.fromJson(jsonDecode(jsonEncode(game.syncState.toJson())) as Map<String, dynamic>);
      expect(back.groupKind, GroupKind.family);
      // Юнга не меняет вид группы.
      final kid = await game.addHero(name: 'Миша', avatar: '🧒', role: HeroRole.child);
      await game.switchHero(kid.id);
      expect(await game.setGroupKind(GroupKind.clan), isFalse);
      expect(game.groupKind, GroupKind.family);
    });

    test('старые данные без вида группы — семья', () {
      final s = AppState.fromJson({'schema': 5, 'guildName': 'Дом', 'heroes': [], 'goals': [], 'feed': []});
      expect(s.groupKind, GroupKind.family);
    });

    test('рутина 3 раза в день: опыт за каждый раз, серия одна, отмена по одному', () async {
      final g = await game.addGoal(title: 'Почистить зубы', tier: GoalTier.daily, perPeriod: 3);
      expect(g.perPeriod, 3);
      final hero = game.activeHero!;
      final r1 = await game.toggleDaily(g.id);
      expect(r1.xp, 5);
      expect(GameRules.timesDone(game.goalById(g.id)!, now), 1);
      expect(GameRules.isDoneToday(game.goalById(g.id)!, now), isFalse);
      final r2 = await game.toggleDaily(g.id);
      expect(r2.xp, GameRules.repeatAgainXp(g));
      await game.toggleDaily(g.id);
      final goal = game.goalById(g.id)!;
      expect(GameRules.timesDone(goal, now), 3);
      expect(GameRules.isDoneToday(goal, now), isTrue);
      expect(GameRules.canRepeat(goal, now), isFalse);
      expect(goal.streak, 1);
      expect(GameRules.timesLabel(goal, now), '3/3');
      final xp3 = hero.xp;
      expect(xp3, 5 + 5 + 5);
      expect(game.records.where((r) => r.goalId == g.id).length, 3);
      // Четвёртое нажатие снимает последнюю отметку.
      await game.toggleDaily(g.id);
      expect(GameRules.timesDone(game.goalById(g.id)!, now), 2);
      expect(game.activeHero!.xp, 10);
      await game.undoDaily(g.id);
      await game.undoDaily(g.id);
      expect(GameRules.timesDone(game.goalById(g.id)!, now), 0);
      expect(game.goalById(g.id)!.streak, 0);
      expect(game.activeHero!.xp, 0);
      expect(game.activeHero!.coins, 0);
      // Назавтра — снова с нуля, серия продолжается.
      await game.toggleDaily(g.id);
      now = now.add(const Duration(days: 1));
      expect(GameRules.timesDone(game.goalById(g.id)!, now), 0);
      await game.toggleDaily(g.id);
      expect(game.goalById(g.id)!.streak, 2);
      expect(GameRules.timesDone(game.goalById(g.id)!, now), 1);
    });

    test('рутина без ограничения: отмечается сколько угодно (до потолка)', () async {
      final g = await game.addGoal(title: 'Стакан воды', tier: GoalTier.daily, perPeriod: 0);
      for (var i = 0; i < Goal.maxPerPeriod + 3; i++) {
        await game.toggleDaily(g.id);
      }
      final goal = game.goalById(g.id)!;
      expect(GameRules.isDoneToday(goal, now), isTrue);
      // На потолке следующее нажатие снимает последнюю отметку, а не добавляет.
      expect(GameRules.timesDone(goal, now), lessThanOrEqualTo(Goal.maxPerPeriod));
      expect(GameRules.timesLabel(goal, now), startsWith('×'));
    });

    test('сколько раз за день выбирает взрослый; JSON обычной рутины не меняется', () async {
      final plain = await game.addGoal(title: 'Зарядка', tier: GoalTier.daily);
      expect(plain.toJson().containsKey('perPeriod'), isFalse);
      final kid = await game.addHero(name: 'Миша', avatar: '🧒', role: HeroRole.child);
      await game.switchHero(kid.id);
      final byKid = await game.addGoal(title: 'Конфета', tier: GoalTier.daily, perPeriod: 0);
      expect(byKid.perPeriod, 1);
      final task = await game.addGoal(title: 'Задание', tier: GoalTier.task, perPeriod: 5);
      expect(task.perPeriod, 1);
      // Сохранение и чтение многоразовой рутины.
      final multi = Goal.fromJson(jsonDecode(jsonEncode(
          Goal(id: 'x', title: 'Вода', tier: GoalTier.daily, ownerId: '', createdAt: now, perPeriod: 8, doneCount: 3)
              .toJson())) as Map<String, dynamic>);
      expect(multi.perPeriod, 8);
      expect(multi.doneCount, 3);
    });

    test('вклад в цель гильдии даёт опыт и монеты, но не больше дневного предела', () async {
      final hero = game.activeHero!;
      var total = 0;
      for (var i = 0; i < 10; i++) {
        total += game.rewardGuildContribution(goalId: 'g1', title: '1000 км', amount: 5, unit: 'км').xp;
      }
      expect(total, GameController.guildXpPerDay);
      expect(hero.xp, GameController.guildXpPerDay);
      expect(hero.statXp[HeroStat.charisma], GameController.guildXpPerDay);
      expect(game.records.where((r) => r.kind == XpKind.guild).length, GameController.guildXpPerDay ~/ GameController.guildXp);
      expect(game.feed.first.text, contains('цель гильдии «1000 км»'));
      now = now.add(const Duration(days: 1));
      expect(game.rewardGuildContribution(goalId: 'g1', title: '1000 км', amount: 1, unit: 'км').xp, GameController.guildXp);
    });
  });
}
