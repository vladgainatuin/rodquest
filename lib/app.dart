import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'logic/game_rules.dart';
import 'models/models.dart';
import 'screens/budget_screen.dart';
import 'screens/guild_screen.dart';
import 'screens/hero_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/quests_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/timer_screen.dart';
import 'screens/today_screen.dart';
import 'state/game_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/effects.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/pin_pad.dart';
import 'widgets/ring.dart';
import 'widgets/spiral_splash.dart';

class RodquestApp extends StatefulWidget {
  const RodquestApp({super.key, required this.controller});

  final GameController controller;

  @override
  State<RodquestApp> createState() => _RodquestAppState();
}

class _RodquestAppState extends State<RodquestApp> {
  static final _themes = <AppSkin, ThemeData>{};

  /// Заставка-спираль показывается только при холодном запуске, пока грузятся данные.
  late bool _splash = !widget.controller.ready;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return GameScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (_splash) {
            return MaterialApp(
              key: const ValueKey('splash'),
              title: 'Родквест',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(scaffoldBackgroundColor: SpiralSplash.background),
              home: SpiralSplash(
                ready: controller.ready,
                onDone: () => setState(() => _splash = false),
              ),
            );
          }
          // Тема зависит от активного героя: юнгам — игровая, взрослым — строгая
          // (или та, что герой выбрал сам).
          final skin = controller.needsOnboarding ? AppSkin.fairy : controller.skin;
          final palette = RqPalette.of(skin);
          RqColors.p = palette;
          final theme = _themes.putIfAbsent(palette.skin, () => buildTheme(palette));
          return MaterialApp(
            // Новый ключ при смене темы перестраивает всё дерево с новыми цветами.
            key: ValueKey(palette.skin),
            title: 'Родквест',
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const _Root(),
          );
        },
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    if (!game.ready) return const Scaffold(backgroundColor: SpiralSplash.background);
    if (game.needsOnboarding) return const OnboardingScreen();
    return const HomeShell();
  }
}

enum _Fab { none, goal, legend, money }

class _Tab {
  const _Tab({
    required this.label,
    required this.title,
    required this.emoji,
    required this.icon,
    required this.page,
    this.fab = _Fab.none,
  });

  final String label;
  final String title;
  final String emoji;
  final IconData icon;
  final Widget page;
  final _Fab fab;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  /// Проверка будильников, напоминаний и таймера — каждые 5 секунд.
  Timer? _clock;
  final _alarmQueue = <TickEvent>[];
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    WidgetsBinding.instance.addObserver(this);
    // Сразу после запуска — показать пропущенное, пока приложение было закрыто.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  /// Свернули приложение — будильники зазвонят системными уведомлениями;
  /// вернулись — уведомления снимаются, и сразу видно, что прозвенело.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final game = GameScope.read(context);
    switch (state) {
      case AppLifecycleState.resumed:
        game.setBackground(false);
        _tick();
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        game.setBackground(true);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _tick() {
    if (!mounted) return;
    final game = GameScope.read(context);
    for (final e in game.tick()) {
      if (e.kind == TickKind.alarm) {
        _alarmQueue.add(e);
      } else {
        showReminderBanner(context, e);
      }
    }
    _ringNext();
  }

  Future<void> _ringNext() async {
    if (_ringing || _alarmQueue.isEmpty || !mounted) return;
    _ringing = true;
    final e = _alarmQueue.removeAt(0);
    await showAlarmRing(context, e);
    _ringing = false;
    _ringNext();
  }

  List<_Tab> _tabsFor(HeroProfile hero, {required bool solo}) {
    final adult = hero.role.isAdult;
    return [
      _Tab(
        label: 'Сегодня',
        title: 'Сегодня',
        emoji: '🏠',
        icon: Icons.today_outlined,
        page: const TodayScreen(),
        fab: adult ? _Fab.goal : _Fab.none,
      ),
      _Tab(
        label: 'Квесты',
        title: 'Карта квестов',
        emoji: '🗺',
        icon: Icons.account_tree_outlined,
        page: const QuestsScreen(),
        fab: adult ? _Fab.legend : _Fab.none,
      ),
      if (adult)
        const _Tab(
          label: 'Бюджет',
          title: 'Семейный бюджет',
          emoji: '💰',
          icon: Icons.account_balance_wallet_outlined,
          page: BudgetScreen(),
          fab: _Fab.money,
        )
      else
        const _Tab(
          label: 'Лавка',
          title: 'Лавка наград',
          emoji: '🏪',
          icon: Icons.storefront_outlined,
          page: ShopScreen(),
        ),
      // В личном режиме гильдии нет — вместо неё лавка наград себе.
      if (solo)
        const _Tab(
          label: 'Лавка',
          title: 'Награды себе',
          emoji: '🏪',
          icon: Icons.storefront_outlined,
          page: ShopScreen(),
        )
      else
        _Tab(
          label: 'Гильдия',
          title: 'Гильдия',
          emoji: '🛡',
          icon: Icons.groups_outlined,
          page: const GuildScreen(),
          fab: adult ? _Fab.goal : _Fab.none,
        ),
      const _Tab(
        label: 'Герой',
        title: 'Герой',
        emoji: '🧙',
        icon: Icons.person_outline_rounded,
        page: HeroScreen(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final tabs = _tabsFor(hero, solo: game.solo);
    if (_tab >= tabs.length) _tab = 0;
    final tab = tabs[_tab];
    final playful = RqColors.playful;
    final reminders = GameRules.reminders(game.goals, game.now, heroId: hero.id).length;
    final todayBadge = reminders +
        (hero.role.canApprove ? game.goals.where((g) => g.pendingApproval).length : 0) +
        (game.canManageRewards ? game.pendingClaims.length : 0);

    Widget navIcon(_Tab t, int i) {
      final Widget icon = playful ? Text(t.emoji, style: const TextStyle(fontSize: 22)) : Icon(t.icon);
      if (i == 0 && todayBadge > 0) {
        return Badge(label: Text('$todayBadge'), backgroundColor: RqColors.danger, child: icon);
      }
      return icon;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tab.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: CoinTargetBox(child: CoinBadge(hero.coins))),
          ),
          if (game.heroes.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Сменить героя',
              onSelected: (id) => switchHeroGuarded(context, id),
              itemBuilder: (_) => [
                for (final h in game.heroes)
                  PopupMenuItem(
                    value: h.id,
                    child: Text(
                        '${h.avatar}  ${h.name}${h.id == hero.id ? '  ✓' : ''}'
                        '${game.needsPinToSwitch(h.id) ? '  🔒' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AvatarBubble(hero.avatar, size: 40),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AvatarBubble(hero.avatar, size: 40),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                const ActiveTimerBanner(),
                Expanded(child: IndexedStack(index: _tab, children: [for (final t in tabs) t.page])),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: switch (tab.fab) {
        _Fab.none => null,
        _Fab.money => FloatingActionButton.extended(
            backgroundColor: RqColors.primary,
            foregroundColor: RqColors.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(playful ? 18 : 12)),
            onPressed: () => openMoneyEditor(context, kind: MoneyKind.expense),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Операция', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        _ => FloatingActionButton.extended(
            backgroundColor: RqColors.primary,
            foregroundColor: RqColors.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(playful ? 18 : 12)),
            onPressed: () => openGoalEditor(
              context,
              tier: tab.fab == _Fab.legend ? GoalTier.legend : GoalTier.task,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новая цель', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final (i, t) in tabs.indexed) NavigationDestination(icon: navIcon(t, i), label: t.label),
        ],
      ),
    );
  }
}
