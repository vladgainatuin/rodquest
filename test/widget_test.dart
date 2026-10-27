import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodquest/app.dart';
import 'package:rodquest/data/repository.dart';
import 'package:rodquest/logic/game_rules.dart';
import 'package:rodquest/models/models.dart';
import 'package:rodquest/screens/hero_screen.dart';
import 'package:rodquest/screens/stats_screen.dart';
import 'package:rodquest/state/game_controller.dart';
import 'package:rodquest/widgets/effects.dart';
import 'package:rodquest/widgets/spiral_splash.dart';

void main() {
  testWidgets('онбординг → главный экран с примером целей', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    expect(find.text('Название семьи'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Дом Смелых');
    await tester.enterText(find.byType(TextField).at(1), 'Папа');
    await tester.pump();
    // Кнопка внизу прокручиваемого списка — сначала докручиваем до неё.
    final startButton = find.text('Создать семью');
    await _scrollTo(tester, startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('Сегодня'), findsWidgets);
    expect(find.text('Семейный отпуск на море'), findsWidgets);

    // Все вкладки открываются без ошибок.
    for (final tab in ['Квесты', 'Бюджет', 'Семья', 'Герой', 'Сегодня']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('юнга видит лавку и игровую тему, но не бюджет', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    await game.seedDemo();
    final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
    await game.switchHero(kid.id);

    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Лавка')), findsOneWidget);
    expect(find.text('Бюджет'), findsNothing);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Лавка')));
    await tester.pumpAndSettle();
    expect(find.text('Поход в кино'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('статистика и достижения открываются с экрана героя', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    await game.seedDemo();
    final task = game.goals.firstWhere((g) => g.tier == GoalTier.task);
    await game.completeGoal(task.id);
    await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);

    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Герой')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    expect(find.text('📈 Опыт по дням'), findsOneWidget);
    await tester.tap(find.text('🏡 Семья'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    // Блок ниже первого экрана — прокручиваем список статистики до него.
    await tester.scrollUntilVisible(
      find.textContaining('Вклад героев'),
      300,
      scrollable: find.descendant(of: find.byType(StatsScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.textContaining('Вклад героев'), findsOneWidget);
    await _back(tester);
    await tester.pumpAndSettle();

    final tile = find.text('Первый шаг');
    await _scrollTo(tester, tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Понятно'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('с PIN юнга не может переключиться на взрослого', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    final mamaId = game.activeHero!.id;
    await game.setParentPin('1357');
    final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
    await game.switchHero(kid.id);

    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Сменить героя'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Мама'));
    await tester.pumpAndSettle();
    expect(find.text('🔐 PIN родителя'), findsOneWidget);

    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Неверный PIN'), findsOneWidget);
    expect(game.activeHero!.id, kid.id);

    for (final d in ['1', '3', '5', '7']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(game.activeHero!.id, mamaId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('режим «Только я»: онбординг без семьи, вкладка «Гильдия» с лавкой и черты характера', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Только я'));
    await tester.pumpAndSettle();
    expect(find.text('Название семьи'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Аня');
    await tester.pump();
    final start = find.text('Начать путь');
    await _scrollTo(tester, start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(game.solo, isTrue);
    final nav = find.byType(NavigationBar);
    expect(find.descendant(of: nav, matching: find.text('Гильдия')), findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Лавка')), findsNothing);
    // v0.9: на вкладке «Гильдия» — вход в лавку наград себе.
    await tester.tap(find.descendant(of: nav, matching: find.text('Гильдия')));
    await tester.pumpAndSettle();
    expect(find.text('Награды себе'), findsOneWidget);

    await tester.tap(find.descendant(of: nav, matching: find.text('Герой')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('🧭 Черты характера'));
    expect(find.text('🧭 Черты характера'), findsOneWidget);
    expect(find.text('Пунктуальность'), findsOneWidget);

    // Редактор рутины: выбор повтора.
    await tester.tap(find.descendant(of: nav, matching: find.text('Сегодня')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая цель'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '🔁 Рутина'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '📆 Каждую неделю'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Раз в неделю в любой день'), findsOneWidget);
    expect(find.text('🔒 Личная цель'), findsNothing); // в личном режиме не нужна
    expect(tester.takeException(), isNull);
  });

  testWidgets('будильники, рекорды, таймер и готовые планы открываются', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    await game.seedDemo();

    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Будильники'));
    await tester.pumpAndSettle();
    expect(find.text('Будильники и напоминания'), findsOneWidget);
    expect(find.text('Подъём'), findsOneWidget);
    await tester.tap(find.text('Подъём'));
    await tester.pumpAndSettle();
    expect(find.text('🌄 Это подъём'), findsOneWidget);
    Navigator.of(tester.element(find.text('🌄 Это подъём'))).pop(); // закрыть редактор
    await tester.pumpAndSettle();
    await _back(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Рекорды'));
    await tester.pumpAndSettle();
    expect(find.text('Отжимания'), findsOneWidget);
    await tester.tap(find.text('Отжимания'));
    await tester.pumpAndSettle();
    expect(find.text('Личный рекорд'), findsOneWidget);
    await _back(tester);
    await tester.pumpAndSettle();
    await _back(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Таймер'));
    await tester.pumpAndSettle();
    expect(find.text('⏱ Таймер'), findsOneWidget);
    expect(find.text('25 мин'), findsOneWidget);
    Navigator.of(tester.element(find.text('⏱ Таймер'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Квесты')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готовые планы'));
    await tester.pumpAndSettle();
    expect(find.text('Финансовая подушка'), findsOneWidget);
    await tester.tap(find.text('Финансовая подушка'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Создать план'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать план'));
    await tester.pumpAndSettle();
    expect(game.goals.any((g) => g.title == 'Финансовая подушка на 6 месяцев'), isTrue);
    await tester.pump(const Duration(seconds: 2)); // отложенное освобождение полей ввода
    expect(tester.takeException(), isNull);
  });

  testWidgets('резервная копия: в профиле главы и на первом экране', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('📂 Восстановить из резервной копии'));
    expect(find.text('📂 Восстановить из резервной копии'), findsOneWidget);

    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Герой')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Родквест v0.9 · данные хранятся на этом устройстве'), 300,
        scrollable: find.descendant(of: find.byType(HeroScreen), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    expect(find.text('Сохранить резервную копию'), findsOneWidget);
    expect(find.text('Восстановить из копии'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('заставка-спираль: показывается при загрузке и уходит после неё', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SpiralSplash), findsOneWidget);
    expect(find.text('Ход за ходом — к большой цели'), findsOneWidget);

    await game.load();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SpiralSplash), findsOneWidget, reason: 'не меньше 2,6 с, чтобы успели увидеть');
    await tester.pump(SpiralSplash.minDuration);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(SpiralSplash), findsNothing);
    expect(find.text('Название семьи'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('эффекты: конфетти, монеты, цепочка, пешка на карте и огонь серии', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final game = GameController(MemoryGameRepository());
    await game.load();
    await game.createGuild(guildName: 'Дом', heroName: 'Мама', avatar: '👸');
    await game.seedDemo();
    final kid = await game.addHero(name: 'Миша', avatar: '🦊', role: HeroRole.child);
    await game.switchHero(kid.id);
    final daily = game.goals.firstWhere((g) => g.isDaily && g.ownerId == kid.id, orElse: () => game.goals.firstWhere((g) => g.isDaily));
    daily
      ..streak = 7
      ..lastDoneDay = GameRules.dayKey(game.now.subtract(const Duration(days: 1)));

    await tester.pumpWidget(RodquestApp(controller: game));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavigationBar));
    showConfetti(context);
    showCoinFlight(context, 15);
    showChainBurst(context, ['Купить билеты', 'Семейный отпуск на море']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Цепочка завершена: Семейный отпуск на море'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Цепочка завершена: Семейный отпуск на море'), findsNothing, reason: 'эффекты сами исчезают');

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Квесты')));
    await tester.pumpAndSettle();
    expect(find.byType(PawnTrack), findsWidgets, reason: 'у легенд и эпиков в игровой теме — дорожка с пешкой');
    expect(tester.takeException(), isNull);
  });
}

/// Прокрутить первый список на экране до виджета (списки строятся лениво).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// Вернуться на предыдущий экран.
Future<void> _back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).last).pop();
  await tester.pumpAndSettle();
}
