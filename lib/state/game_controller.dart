import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../data/templates.dart';
import '../logic/backup.dart';
import '../logic/game_rules.dart';
import '../logic/push_rules.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../services/push.dart';

/// Итог выполнения цели — чтобы показать игроку красивое уведомление.
class CompletionResult {
  CompletionResult({
    this.xp = 0,
    this.coins = 0,
    this.newLevel,
    this.pending = false,
    List<String>? chain,
    List<Achievement>? badges,
  })  : chain = chain ?? [],
        badges = badges ?? [],
        traits = {};

  int xp;
  int coins;
  int? newLevel;
  bool pending;

  /// Названия целей, которые выполнились автоматически по цепочке.
  final List<String> chain;

  /// Новые достижения (или новые ступени) героя, выполнившего цель.
  final List<Achievement> badges;

  /// Опыт черт характера за рутину.
  final Map<HeroTrait, int> traits;
}

/// Результат проверки PIN.
enum PinCheck { ok, wrong, locked }

/// Что произошло при очередной проверке времени (см. [GameController.tick]).
enum TickKind { alarm, reminder, missed, timerDone }

class TickEvent {
  const TickEvent({required this.kind, required this.at, this.reminder, this.timer});

  final TickKind kind;
  final DateTime at;
  final Reminder? reminder;
  final ActiveTimer? timer;
}

/// Итог остановки таймера.
class TimerResult {
  TimerResult({this.session, this.entry, CompletionResult? reward}) : reward = reward ?? CompletionResult();

  final FocusSession? session;

  /// Замер навыка, если таймер мерил навык (например, «Планка»).
  final SkillEntry? entry;
  final CompletionResult reward;
}

/// Итог покупки награды.
enum BuyResult { granted, pending, notEnough, unavailable }

class GameController extends ChangeNotifier {
  GameController(this._repo, {DateTime Function()? clock, PushScheduler? push})
      : _clock = clock ?? DateTime.now,
        push = push ?? const NoPush();

  final GameRepository _repo;
  final DateTime Function() _clock;

  /// Системные уведомления: звонят, когда приложение закрыто (v0.6).
  final PushScheduler push;
  final _rnd = Random();

  AppState _state = AppState.empty();
  bool _ready = false;

  bool get ready => _ready;
  bool get needsOnboarding => _state.heroes.isEmpty;
  String get guildName => _state.guildName;
  List<HeroProfile> get heroes => List.unmodifiable(_state.heroes);
  /// Цели, которые видит активный герой: чужие личные цели скрыты.
  List<Goal> get goals {
    final me = activeHero?.id;
    return List.unmodifiable(_state.goals.where((g) => !g.isPrivate || g.ownerId == me));
  }

  /// Личный режим «Только я»: без гильдии, юнг и семейных целей.
  bool get solo => _state.solo;
  List<FeedEvent> get feed => List.unmodifiable(_state.feed);
  DateTime get now => _clock();

  /// Награды в лавке (без архивных).
  List<Reward> get rewards => _state.rewards.where((r) => !r.archived).toList()
    ..sort((a, b) => a.cost.compareTo(b.cost));
  List<RewardClaim> get claims => List.unmodifiable(_state.claims);
  List<RewardClaim> get pendingClaims =>
      _state.claims.where((c) => c.status == ClaimStatus.pending).toList();

  List<BudgetCategory> get categories => List.unmodifiable(_state.categories);
  List<MoneyEntry> get money => List.unmodifiable(_state.money);
  List<SavingsPot> get pots => List.unmodifiable(_state.pots);
  List<XpRecord> get records => List.unmodifiable(_state.records);

  // v5: будильники, таймеры, навыки.
  List<Reminder> get reminders {
    final now = _clock();
    int key(Reminder r) => TimeRules.nextRing(r, now)?.millisecondsSinceEpoch ?? 8640000000000000;
    return _state.reminders.toList()..sort((a, b) => key(a).compareTo(key(b)));
  }

  List<Reminder> remindersOf(String? heroId) => reminders.where((r) => r.heroId == heroId).toList();

  Reminder? reminderById(String? id) {
    for (final r in _state.reminders) {
      if (r.id == id) return r;
    }
    return null;
  }

  ActiveTimer? timerOf(String? heroId) {
    for (final t in _state.timers) {
      if (t.heroId == heroId) return t;
    }
    return null;
  }

  /// Таймер активного героя.
  ActiveTimer? get activeTimer => timerOf(activeHero?.id);
  List<FocusSession> get sessions => List.unmodifiable(_state.sessions);
  List<SkillEntry> get skillEntries => List.unmodifiable(_state.skillEntries);

  /// Навыки героя (без архивных).
  List<Skill> skillsOf(String? heroId) =>
      _state.skills.where((s) => s.heroId == heroId && !s.archived).toList()..sort((a, b) => a.name.compareTo(b.name));

  Skill? skillById(String? id) {
    for (final s in _state.skills) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Достижения героя с прогрессом и сохранёнными ступенями.
  List<Achievement> achievementsOf(HeroProfile hero) => GameRules.achievements(
        hero,
        _state.goals,
        _clock(),
        records: _state.records,
        heroes: _state.heroes,
        money: _state.money,
        pots: _state.pots,
        claims: _state.claims,
        solo: _state.solo,
        sessions: _state.sessions,
        skillEntries: _state.skillEntries,
      );

  /// Тема оформления активного героя.
  AppSkin get skin => activeHero?.resolvedSkin ?? AppSkin.fairy;

  HeroProfile? get activeHero {
    final id = _state.activeHeroId;
    for (final h in _state.heroes) {
      if (h.id == id) return h;
    }
    return _state.heroes.isEmpty ? null : _state.heroes.first;
  }

  HeroProfile? heroById(String? id) {
    for (final h in _state.heroes) {
      if (h.id == id) return h;
    }
    return null;
  }

  Goal? goalById(String? id) {
    for (final g in _state.goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  // ---------- Загрузка и сохранение ----------

  Future<void> load() async {
    _state = await _repo.load() ?? AppState.empty();
    // Миграция с v1: у старых гильдий ещё нет категорий бюджета.
    if (_state.heroes.isNotEmpty) _ensureBudgetDefaults();
    // Миграция с v2: достижения, полученные раньше, записываем без поздравлений.
    for (final h in _state.heroes) {
      _checkBadges(h, log: false);
    }
    _lastTick = _state.remindersCheckedAt ?? _clock();
    _ready = true;
    notifyListeners();
    // Приложение открыто — звонит оно само, системные уведомления снимаем.
    unawaited(push.clear());
  }

  Future<void> _commit() async {
    if (_lastTick != null) _state.remindersCheckedAt = _lastTick;
    notifyListeners();
    await _repo.save(_state);
    if (_background) unawaited(push.schedule(plannedPushes()));
  }

  // ---------- v6: уведомления при закрытом приложении ----------

  bool _background = false;

  /// Приложение свёрнуто или закрыто.
  bool get inBackground => _background;

  /// Что звенит, пока приложение закрыто: будильники, напоминания,
  /// конец таймера, сроки целей.
  List<PlannedPush> plannedPushes() => PushRules.plan(
        reminders: _state.reminders,
        timers: _state.timers,
        goals: _state.goals,
        heroes: _state.heroes,
        now: _clock(),
      );

  /// Приложение ушло в фон — планируем системные уведомления; вернулось —
  /// снимаем их: дальше звонит само приложение (окно будильника, плашки).
  Future<void> setBackground(bool value) async {
    if (!_ready) return;
    if (value == _background && !value) return;
    _background = value;
    if (value) {
      // Сохраняем, пока приложение ещё живо: система может его закрыть.
      _state.remindersCheckedAt = _lastTick ?? _clock();
      await _repo.save(_state);
      await push.schedule(plannedPushes());
    } else {
      await push.clear();
    }
  }

  // ---------- v6: резервная копия ----------

  /// Сохранять и восстанавливать данные может глава гильдии (в личном режиме — сам герой).
  bool get canBackup => activeHero?.role.canApprove ?? false;

  /// Все данные устройства одним файлом JSON.
  String exportBackup() => Backup.encode(_state, _clock());

  String get backupFileName => Backup.fileName(_clock());

  /// Заменить все данные устройства копией. На новом устройстве (до создания
  /// гильдии) — может любой; потом — только глава гильдии.
  Future<bool> restoreBackup(BackupData data) async {
    if (!needsOnboarding && !canBackup) return false;
    _state = data.state;
    if (!_state.heroes.any((h) => h.id == _state.activeHeroId)) _state.activeHeroId = _state.heroes.first.id;
    _ensureBudgetDefaults();
    for (final h in _state.heroes) {
      _checkBadges(h, log: false);
    }
    // Звонки из прошлого после восстановления не показываем.
    _lastTick = _clock();
    final me = activeHero;
    if (me != null) _log(me.id, '💾', 'восстановил(а) данные из резервной копии');
    await _commit();
    return true;
  }

  String _id() =>
      '${_clock().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  void _log(String heroId, String emoji, String text, {int xp = 0}) {
    _state.feed.insert(
      0,
      FeedEvent(
        id: _id(),
        heroId: heroId,
        text: text,
        emoji: emoji,
        at: _clock(),
        xp: xp,
      ),
    );
    if (_state.feed.length > 200) _state.feed.removeRange(200, _state.feed.length);
  }

  /// Хранить журнал опыта не дольше этого срока (для статистики хватает).
  static const _recordsKeepDays = 400;

  void _record(HeroProfile hero, Goal goal, int xp, int coins,
      {bool onTime = false, Map<HeroTrait, int> traits = const {}}) {
    _addRecord(XpRecord(
      heroId: hero.id,
      goalId: goal.id,
      tier: goal.tier,
      stat: goal.stat,
      xp: xp,
      coins: coins,
      at: _clock(),
      family: goal.isFamily,
      onTime: onTime,
      traits: traits,
      area: goal.area,
    ));
  }

  void _addRecord(XpRecord r) {
    _state.records.add(r);
    final oldest = _clock().subtract(const Duration(days: _recordsKeepDays));
    _state.records.removeWhere((x) => x.at.isBefore(oldest));
  }

  /// Опыт не за цель: таймер, навык, подъём. [sourceId] — id сессии/замера/будильника.
  void _recordOther(HeroProfile hero, XpKind kind, String sourceId, HeroStat stat, int xp, int coins,
      {LifeArea? area, Map<HeroTrait, int> traits = const {}}) {
    _addRecord(XpRecord(
      heroId: hero.id,
      goalId: sourceId,
      tier: GoalTier.task,
      stat: stat,
      xp: xp,
      coins: coins,
      at: _clock(),
      traits: traits,
      kind: kind,
      area: area,
    ));
  }

  /// Убрать последнюю запись о цели (при возврате в работу или снятии отметки).
  XpRecord? _unrecord(String goalId, String heroId) {
    for (var i = _state.records.length - 1; i >= 0; i--) {
      final r = _state.records[i];
      if (r.goalId == goalId && r.heroId == heroId) {
        return _state.records.removeAt(i);
      }
    }
    return null;
  }

  /// Обновить ступени достижений героя. Возвращает новые (для поздравления).
  List<Achievement> _checkBadges(HeroProfile hero, {bool log = true}) {
    final fresh = <Achievement>[];
    for (final a in achievementsOf(hero)) {
      final stored = hero.badges[a.id] ?? 0;
      if (a.level > stored) {
        hero.badges[a.id] = a.level;
        fresh.add(a);
        if (log) {
          final step = a.tiered ? ' (${Achievement.levelName(a.level)})' : '';
          _log(hero.id, '🏆', 'получил(а) достижение «${a.title}»$step');
        }
      }
    }
    return fresh;
  }

  // ---------- PIN родителя ----------

  int _pinFails = 0;
  DateTime? _pinLockedUntil;

  /// Сколько неверных попыток подряд допускается до паузы.
  static const pinMaxFails = 5;
  static const pinLockDuration = Duration(minutes: 1);

  bool get hasParentPin => _state.parentPinHash != null;

  /// Сколько ещё ждать после неверных попыток (null — можно вводить).
  Duration? get pinLockLeft {
    final until = _pinLockedUntil;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left.isNegative ? null : left;
  }

  /// Нужен ли PIN, чтобы переключиться на героя: юнга не может без PIN
  /// войти во взрослый профиль (и подтвердить задания сам себе).
  bool needsPinToSwitch(String heroId) {
    final target = heroById(heroId);
    final me = activeHero;
    if (_state.solo || !hasParentPin || target == null || me == null) return false;
    return me.role == HeroRole.child && target.role.isAdult;
  }

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// Хэш FNV-1a (32 бита) с солью. Это семейный «замок от детей», а не защита
  /// от взлома: PIN просто не хранится в открытом виде.
  static String hashPin(String pin, String salt) {
    var h = 0x811c9dc5;
    for (var round = 0; round < 64; round++) {
      for (final c in '$salt:$pin:$round'.codeUnits) {
        h ^= c;
        // h * 16777619 по модулю 2^32 без переполнения и на вебе.
        h = (h * 403 + ((h << 24) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      }
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  PinCheck checkPin(String pin) {
    if (!hasParentPin) return PinCheck.ok;
    if (pinLockLeft != null) return PinCheck.locked;
    if (hashPin(pin, _state.parentPinSalt ?? '') == _state.parentPinHash) {
      _pinFails = 0;
      _pinLockedUntil = null;
      return PinCheck.ok;
    }
    _pinFails++;
    if (_pinFails >= pinMaxFails) {
      _pinFails = 0;
      _pinLockedUntil = _clock().add(pinLockDuration);
      notifyListeners();
      return PinCheck.locked;
    }
    return PinCheck.wrong;
  }

  /// Задать или сменить PIN. Только глава гильдии; при смене нужен старый PIN.
  Future<bool> setParentPin(String pin, {String? oldPin}) async {
    if (activeHero?.role.canApprove != true || !isValidPin(pin)) return false;
    if (hasParentPin && checkPin(oldPin ?? '') != PinCheck.ok) return false;
    final salt = _id();
    _state
      ..parentPinSalt = salt
      ..parentPinHash = hashPin(pin, salt);
    await _commit();
    return true;
  }

  /// Выключить PIN (глава гильдии, с вводом текущего PIN).
  Future<bool> removeParentPin(String pin) async {
    if (activeHero?.role.canApprove != true || !hasParentPin) return false;
    if (checkPin(pin) != PinCheck.ok) return false;
    _state
      ..parentPinSalt = null
      ..parentPinHash = null;
    await _commit();
    return true;
  }

  /// Сброс забытого PIN после «родительской проверки» в интерфейсе.
  Future<void> resetForgottenPin() async {
    _state
      ..parentPinSalt = null
      ..parentPinHash = null;
    _pinFails = 0;
    _pinLockedUntil = null;
    final me = activeHero;
    if (me != null) _log(me.id, '🔓', 'сбросил(а) PIN родителя');
    await _commit();
  }

  // ---------- Гильдия и герои ----------

  Future<void> createGuild({
    required String guildName,
    required String heroName,
    required String avatar,
    bool solo = false,
  }) async {
    final hero = HeroProfile(
      id: _id(),
      name: heroName.trim(),
      avatar: avatar,
      role: HeroRole.leader,
    );
    _state = AppState(
      guildName: guildName.trim().isEmpty ? 'Путь героя ${heroName.trim()}' : guildName.trim(),
      heroes: [hero],
      goals: [],
      feed: [],
      activeHeroId: hero.id,
      solo: solo,
    );
    _ensureBudgetDefaults();
    _log(hero.id, solo ? '🧭' : '🛡',
        solo ? 'начал(а) свой путь героя' : 'основал(а) гильдию «${_state.guildName}»');
    await _commit();
  }

  /// Превратить личный путь в семейную гильдию (или обратно, пока герой один).
  Future<bool> setSolo(bool value, {String? guildName}) async {
    if (value == _state.solo) return true;
    if (value && _state.heroes.length > 1) return false;
    _state.solo = value;
    if (!value && guildName != null && guildName.trim().isNotEmpty) _state.guildName = guildName.trim();
    if (value) {
      // В личном режиме нет семейных целей и PIN.
      for (final g in _state.goals) {
        g.isFamily = false;
      }
      _state
        ..parentPinHash = null
        ..parentPinSalt = null;
    }
    final me = activeHero;
    if (me != null && !value) _log(me.id, '🛡', 'основал(а) гильдию «${_state.guildName}»');
    await _commit();
    return true;
  }

  Future<HeroProfile> addHero({
    required String name,
    required String avatar,
    required HeroRole role,
  }) async {
    final hero = HeroProfile(id: _id(), name: name.trim(), avatar: avatar, role: role);
    // Новый член семьи превращает личный путь в гильдию.
    _state.solo = false;
    _state.heroes.add(hero);
    _log(hero.id, '🎉', 'вступил(а) в гильдию как «${role.label}»');
    await _commit();
    return hero;
  }

  Future<void> updateHero(
    HeroProfile hero, {
    String? name,
    String? avatar,
    HeroRole? role,
    AppSkin? skin,
  }) async {
    if (name != null && name.trim().isNotEmpty) hero.name = name.trim();
    if (avatar != null) hero.avatar = avatar;
    if (role != null) hero.role = role;
    if (skin != null) hero.skin = skin;
    await _commit();
  }

  Future<void> removeHero(String heroId) async {
    if (_state.heroes.length <= 1) return;
    _state.heroes.removeWhere((h) => h.id == heroId);
    final fallback = _state.heroes.first.id;
    for (final g in _state.goals) {
      if (g.ownerId == heroId) g.ownerId = fallback;
    }
    if (_state.activeHeroId == heroId) _state.activeHeroId = fallback;
    _state.reminders.removeWhere((r) => r.heroId == heroId);
    _state.timers.removeWhere((t) => t.heroId == heroId);
    final skillIds = {for (final s in _state.skills) if (s.heroId == heroId) s.id};
    _state.skills.removeWhere((s) => skillIds.contains(s.id));
    _state.skillEntries.removeWhere((e) => skillIds.contains(e.skillId));
    await _commit();
  }

  /// Переключить активного героя. Если нужен PIN ([needsPinToSwitch]),
  /// без верного [pin] переключение не произойдёт.
  Future<bool> switchHero(String heroId, {String? pin}) async {
    if (heroById(heroId) == null) return false;
    if (needsPinToSwitch(heroId) && checkPin(pin ?? '') != PinCheck.ok) return false;
    _state.activeHeroId = heroId;
    await _commit();
    return true;
  }

  Future<void> renameGuild(String name) async {
    if (name.trim().isEmpty) return;
    _state.guildName = name.trim();
    await _commit();
  }

  // ---------- Цели ----------

  /// Привести расписание к порядку: дни недели 1..7 без повторов,
  /// у недельной — один день «по плану», у месячной — число 1..31.
  static (List<int>, int?) _normSchedule(Repeat repeat, List<int> weekdays, int? monthDay) {
    final days = {for (final d in weekdays) if (d >= 1 && d <= 7) d}.toList()..sort();
    return switch (repeat) {
      Repeat.daily => (days.length == 7 ? <int>[] : days, null),
      Repeat.weekly => (days.isEmpty ? <int>[] : [days.first], null),
      Repeat.monthly => (<int>[], monthDay?.clamp(1, 31)),
    };
  }

  Future<Goal> addGoal({
    required String title,
    required GoalTier tier,
    String description = '',
    String? parentId,
    String? ownerId,
    bool isFamily = false,
    bool isPrivate = false,
    HeroStat stat = HeroStat.mastery,
    DateTime? dueDate,
    Repeat repeat = Repeat.daily,
    List<int> weekdays = const [],
    int? monthDay,
    LifeArea? area,
  }) async {
    final parent = goalById(parentId);
    final validParent = parent != null && tier.allowedParents.contains(parent.tier) ? parent : null;
    // Цель внутри личной — тоже личная и того же владельца.
    final private = !_state.solo && (isPrivate || (validParent?.isPrivate ?? false));
    final (days, mDay) = _normSchedule(repeat, weekdays, monthDay);
    final goal = Goal(
      id: _id(),
      title: title.trim(),
      description: description.trim(),
      tier: tier,
      parentId: validParent?.id,
      ownerId: private && validParent != null ? validParent.ownerId : (ownerId ?? activeHero?.id ?? ''),
      // Цель внутри семейной тоже становится семейной. Личная семейной быть не может.
      isFamily: !_state.solo && !private && (isFamily || (validParent?.isFamily ?? false)),
      isPrivate: private,
      stat: stat,
      createdAt: _clock(),
      dueDate: tier == GoalTier.daily ? null : dueDate,
      repeat: repeat,
      weekdays: tier == GoalTier.daily ? days : [],
      monthDay: tier == GoalTier.daily ? mDay : null,
      // Шаг без своего раздела наследует раздел родителя.
      area: area ?? validParent?.area,
    );
    _state.goals.add(goal);
    if (tier.rank <= GoalTier.epic.rank) {
      final what = tier == GoalTier.legend ? 'легенду' : 'эпик';
      _log(activeHero?.id ?? goal.ownerId, private ? '🔒' : tier.emoji,
          private ? 'объявил(а) личную $what' : 'объявил(а) $what «${goal.title}»');
    }
    await _commit();
    return goal;
  }

  Future<void> updateGoal(
    Goal goal, {
    required String title,
    required String description,
    required GoalTier tier,
    required String? parentId,
    required String ownerId,
    required bool isFamily,
    required HeroStat stat,
    DateTime? dueDate,
    bool? isPrivate,
    Repeat? repeat,
    List<int>? weekdays,
    int? monthDay,
    Object? area = _keep,
  }) async {
    final parent = goalById(parentId);
    final invalidParent = parent == null ||
        !tier.allowedParents.contains(parent.tier) ||
        GameRules.descendantIds(goal.id, _state.goals).contains(parent.id) ||
        parent.id == goal.id;
    final private = !_state.solo && (isPrivate ?? goal.isPrivate);
    final newRepeat = repeat ?? goal.repeat;
    final (days, mDay) = _normSchedule(newRepeat, weekdays ?? goal.weekdays, monthDay);
    if (newRepeat != goal.repeat) {
      // Периоды другой длины — серия начинается заново.
      goal
        ..streak = 0
        ..lastDoneDay = null;
    }
    goal
      ..title = title.trim()
      ..description = description.trim()
      ..tier = tier
      ..parentId = invalidParent ? null : parent.id
      ..ownerId = ownerId
      ..isFamily = !_state.solo && !private && isFamily
      ..isPrivate = private
      ..stat = stat
      ..dueDate = tier == GoalTier.daily ? null : dueDate
      ..repeat = newRepeat
      ..weekdays = tier == GoalTier.daily ? days : []
      ..monthDay = tier == GoalTier.daily ? mDay : null;
    if (!identical(area, _keep)) goal.area = area is LifeArea ? area : null;
    // Вложенные цели наследуют «личность» родителя.
    for (final id in GameRules.descendantIds(goal.id, _state.goals)) {
      final k = goalById(id)!;
      k.isPrivate = private;
      if (private) {
        k
          ..isFamily = false
          ..ownerId = goal.ownerId;
      }
    }
    await _commit();
  }

  /// Маркер «не менять» для необязательных параметров, где null — тоже значение.
  static const _keep = Object();

  Future<void> deleteGoal(String id) async {
    final ids = GameRules.descendantIds(id, _state.goals)..add(id);
    _state.goals.removeWhere((g) => ids.contains(g.id));
    for (final r in _state.reminders) {
      if (ids.contains(r.goalId)) r.goalId = null;
    }
    for (final pot in _state.pots) {
      if (ids.contains(pot.goalId)) pot.goalId = null;
    }
    await _commit();
  }

  /// Может ли активный герой удалить/изменить цель.
  bool canEdit(Goal goal) {
    final hero = activeHero;
    if (hero == null) return false;
    if (hero.role == HeroRole.child) return false;
    if (goal.isPrivate && goal.ownerId != hero.id) return false;
    return true;
  }

  int? _award(HeroProfile hero, HeroStat stat, int xp) {
    final before = GameRules.levelFor(hero.xp).level;
    hero.xp = max(0, hero.xp + xp);
    hero.statXp[stat] = max(0, (hero.statXp[stat] ?? 0) + xp);
    final after = GameRules.levelFor(hero.xp).level;
    return after > before ? after : null;
  }

  /// Выполнить цель активным героем. Юнга отправляет на подтверждение.
  Future<CompletionResult> completeGoal(String id) async {
    final goal = goalById(id);
    final hero = activeHero;
    final result = CompletionResult();
    if (goal == null || hero == null || goal.isDaily || goal.done) return result;
    if (goal.pendingApproval) return result..pending = true;

    if (hero.role == HeroRole.child) {
      goal
        ..pendingApproval = true
        ..completedById = hero.id;
      _log(hero.id, '⏳', 'выполнил(а) «${goal.title}» — ждёт подтверждения');
      result.pending = true;
      await _commit();
      return result;
    }

    _finish(goal, hero, result);
    result.badges.addAll(_checkBadges(hero));
    await _commit();
    return result;
  }

  void _finish(Goal goal, HeroProfile hero, CompletionResult result) {
    goal
      ..done = true
      ..pendingApproval = false
      ..completedAt = _clock()
      ..completedById = hero.id;
    final xp = goal.tier.xp;
    result.xp += xp;
    result.coins += goal.tier.coins;
    hero.coins += goal.tier.coins;
    result.newLevel = _award(hero, goal.stat, xp) ?? result.newLevel;
    _record(hero, goal, xp, goal.tier.coins);
    _log(hero.id, goal.isPrivate ? '🔒' : goal.tier.emoji,
        goal.isPrivate
            ? 'выполнил(а) личную цель'
            : 'выполнил(а) ${goal.tier.label.toLowerCase()} «${goal.title}»',
        xp: xp);

    // Цепочка: если все шаги родителя выполнены — родитель выполняется сам,
    // а награду получает герой, сделавший последний шаг.
    final parent = goalById(goal.parentId);
    if (parent != null && !parent.done && GameRules.allChildrenDone(parent, _state.goals)) {
      result.chain.add(parent.title);
      _finish(parent, hero, result);
    }
  }

  /// Вернуть цель в работу (и отменить авто-выполненных предков).
  Future<void> uncompleteGoal(String id) async {
    final goal = goalById(id);
    if (goal == null || goal.isDaily) return;
    if (goal.pendingApproval) {
      goal
        ..pendingApproval = false
        ..completedById = null;
      await _commit();
      return;
    }
    if (!goal.done) return;
    for (final g in [goal, ...GameRules.ancestors(goal, _state.goals)]) {
      if (!g.done) continue;
      final completer = heroById(g.completedById);
      if (completer != null) {
        _award(completer, g.stat, -g.tier.xp);
        completer.coins = max(0, completer.coins - g.tier.coins);
        _unrecord(g.id, completer.id);
      }
      g
        ..done = false
        ..completedAt = null
        ..completedById = null;
    }
    await _commit();
  }

  Future<CompletionResult> approve(String id) async {
    final goal = goalById(id);
    final result = CompletionResult();
    if (goal == null || !goal.pendingApproval) return result;
    final doer = heroById(goal.completedById) ?? activeHero;
    if (doer == null) return result;
    _finish(goal, doer, result);
    result.badges.addAll(_checkBadges(doer));
    _log(activeHero?.id ?? doer.id, '✅', 'подтвердил(а) «${goal.title}» для ${doer.name}');
    await _commit();
    return result;
  }

  Future<void> reject(String id) async {
    final goal = goalById(id);
    if (goal == null || !goal.pendingApproval) return;
    goal
      ..pendingApproval = false
      ..completedById = null;
    await _commit();
  }

  /// Отметить рутину в текущем периоде (сегодня / на этой неделе / в этом месяце).
  /// Повторное нажатие снимает отметку. Ежедневную по дням недели можно
  /// отметить только в выбранные дни.
  Future<CompletionResult> toggleDaily(String id) async {
    final goal = goalById(id);
    final hero = activeHero;
    final result = CompletionResult();
    if (goal == null || hero == null || !goal.isDaily) return result;
    final now = _clock();
    final anchor = GameRules.periodAnchor(goal, now);
    final key = GameRules.dayKey(anchor);

    if (goal.lastDoneDay == key) {
      // Отмена: возвращаем ровно то, что начислили (опыт, монеты, черты).
      final rec = _unrecord(goal.id, hero.id);
      final xp = rec?.xp ?? GameRules.repeatXp(goal, goal.streak);
      _award(hero, goal.stat, -xp);
      hero.coins = max(0, hero.coins - (rec?.coins ?? goal.repeat.coins));
      for (final e in (rec?.traits ?? const <HeroTrait, int>{}).entries) {
        hero.traitXp[e.key] = max(0, (hero.traitXp[e.key] ?? 0) - e.value);
      }
      goal.streak = max(0, goal.streak - 1);
      goal.lastDoneDay = goal.streak > 0 ? GameRules.dayKey(GameRules.previousAnchor(goal, anchor)) : null;
      await _commit();
      return result;
    }
    if (!GameRules.canDoNow(goal, now)) return result;

    goal.streak = GameRules.nextStreak(goal, now);
    goal.bestStreak = max(goal.bestStreak, goal.streak);
    goal.lastDoneDay = key;
    final xp = GameRules.repeatXp(goal, goal.streak);
    final coins = goal.repeat.coins;
    final onTime = GameRules.isPlannedDay(goal, now);
    final traits = GameRules.traitGain(goal, goal.streak, onTime: onTime);
    for (final e in traits.entries) {
      hero.traitXp[e.key] = (hero.traitXp[e.key] ?? 0) + e.value;
    }
    result
      ..xp = xp
      ..coins = coins
      ..traits.addAll(traits);
    hero.coins += coins;
    result.newLevel = _award(hero, goal.stat, xp);
    _record(hero, goal, xp, coins, onTime: onTime, traits: traits);
    result.badges.addAll(_checkBadges(hero));
    final milestone = switch (goal.repeat) {
      Repeat.daily => goal.streak % 7 == 0,
      Repeat.weekly => goal.streak % 4 == 0,
      Repeat.monthly => goal.streak % 3 == 0,
    };
    if (goal.streak > 1 && milestone) {
      final title = goal.isPrivate ? 'личное дело' : '«${goal.title}»';
      _log(hero.id, '🔥', 'держит серию ${goal.streak} ${goal.repeat.unit}: $title', xp: xp);
    }
    await _commit();
    return result;
  }

  // ---------- Лут: лавка наград ----------

  bool get canManageRewards => activeHero?.role.isAdult ?? false;

  Future<Reward?> addReward({required String title, required String emoji, required int cost}) async {
    if (!canManageRewards || title.trim().isEmpty || cost <= 0) return null;
    final r = Reward(id: _id(), title: title.trim(), emoji: emoji, cost: cost);
    _state.rewards.add(r);
    _log(activeHero!.id, '🎁', 'добавил(а) в лавку «${r.title}» за $cost монет');
    await _commit();
    return r;
  }

  Future<void> updateReward(Reward r, {required String title, required String emoji, required int cost}) async {
    if (!canManageRewards || title.trim().isEmpty || cost <= 0) return;
    r
      ..title = title.trim()
      ..emoji = emoji
      ..cost = cost;
    await _commit();
  }

  Future<void> archiveReward(String id) async {
    if (!canManageRewards) return;
    for (final r in _state.rewards) {
      if (r.id == id) r.archived = true;
    }
    await _commit();
  }

  /// Купить награду активным героем. Взрослым выдаётся сразу,
  /// юнгам — после подтверждения взрослого. Монеты списываются сразу.
  Future<BuyResult> buyReward(String rewardId) async {
    final hero = activeHero;
    Reward? reward;
    for (final r in _state.rewards) {
      if (r.id == rewardId && !r.archived) reward = r;
    }
    if (hero == null || reward == null) return BuyResult.unavailable;
    if (hero.coins < reward.cost) return BuyResult.notEnough;
    hero.coins -= reward.cost;
    final instant = hero.role.isAdult;
    _state.claims.insert(
      0,
      RewardClaim(
        id: _id(),
        rewardId: reward.id,
        heroId: hero.id,
        title: reward.title,
        emoji: reward.emoji,
        cost: reward.cost,
        at: _clock(),
        status: instant ? ClaimStatus.granted : ClaimStatus.pending,
      ),
    );
    _log(hero.id, reward.emoji,
        instant ? 'получил(а) награду «${reward.title}»' : 'купил(а) «${reward.title}» — ждёт выдачи');
    if (instant) _checkBadges(hero);
    await _commit();
    return instant ? BuyResult.granted : BuyResult.pending;
  }

  RewardClaim? _claim(String id) {
    for (final c in _state.claims) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> grantClaim(String id) async {
    final c = _claim(id);
    if (c == null || c.status != ClaimStatus.pending || !canManageRewards) return;
    c.status = ClaimStatus.granted;
    final who = heroById(c.heroId);
    _log(activeHero!.id, '🎁', 'выдал(а) «${c.title}» для ${who?.name ?? 'героя'}');
    if (who != null) _checkBadges(who);
    await _commit();
  }

  /// Отказать в выдаче — монеты возвращаются герою.
  Future<void> rejectClaim(String id) async {
    final c = _claim(id);
    if (c == null || c.status != ClaimStatus.pending || !canManageRewards) return;
    c.status = ClaimStatus.rejected;
    heroById(c.heroId)?.coins += c.cost;
    await _commit();
  }

  // ---------- Семейный бюджет (взрослые) ----------

  bool get canSeeBudget => activeHero?.role.isAdult ?? false;

  void _ensureBudgetDefaults() {
    if (_state.categories.isNotEmpty) return;
    var n = 0;
    BudgetCategory c(String name, String emoji, MoneyKind kind) =>
        BudgetCategory(id: 'cat${n++}', name: name, emoji: emoji, kind: kind);
    _state.categories.addAll([
      c('Продукты', '🛒', MoneyKind.expense),
      c('Дом и ЖКХ', '🏠', MoneyKind.expense),
      c('Транспорт', '🚗', MoneyKind.expense),
      c('Дети', '🧸', MoneyKind.expense),
      c('Здоровье', '💊', MoneyKind.expense),
      c('Одежда', '👕', MoneyKind.expense),
      c('Отдых и досуг', '🎉', MoneyKind.expense),
      c('Связь и подписки', '📱', MoneyKind.expense),
      c('Прочее', '📦', MoneyKind.expense),
      c('Зарплата', '💼', MoneyKind.income),
      c('Подработка', '💡', MoneyKind.income),
      c('Другие доходы', '💰', MoneyKind.income),
    ]);
  }

  BudgetCategory? categoryById(String? id) {
    for (final c in _state.categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  SavingsPot? potById(String? id) {
    for (final p in _state.pots) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<MoneyEntry?> addMoney({
    required MoneyKind kind,
    required int amount,
    String? categoryId,
    String? potId,
    String note = '',
    DateTime? date,
  }) async {
    final hero = activeHero;
    if (hero == null || !canSeeBudget || amount <= 0) return null;
    if (kind == MoneyKind.saving && potById(potId) == null) return null;
    final e = MoneyEntry(
      id: _id(),
      kind: kind,
      amount: amount,
      date: date ?? _clock(),
      heroId: hero.id,
      categoryId: kind == MoneyKind.saving ? null : categoryId,
      potId: kind == MoneyKind.saving ? potId : null,
      note: note.trim(),
    );
    _state.money.add(e);
    var filled = false;
    SavingsPot? pot;
    if (kind == MoneyKind.saving) {
      pot = potById(potId)!;
      final saved = GameRules.potSaved(pot.id, _state.money);
      if (pot.target > 0 && saved >= pot.target && saved - amount < pot.target) {
        filled = true;
        _log(hero.id, '🐷', 'наполнил(а) копилку «${pot.name}»!');
      }
    }
    _checkBadges(hero);
    await _commit();
    // Копилка цели наполнилась — цель без своих шагов выполняется сама.
    _lastPotReward = null;
    final owner = goalById(pot?.goalId);
    if (filled &&
        owner != null &&
        !owner.done &&
        !owner.pendingApproval &&
        !owner.isDaily &&
        !GameRules.childrenOf(owner.id, _state.goals).any((k) => !k.isDaily)) {
      _lastPotReward = await completeGoal(owner.id);
    }
    return e;
  }

  CompletionResult? _lastPotReward;

  // ---------- v5: накопления на цели ----------

  /// Копилка самой цели (не предка).
  SavingsPot? ownPotOf(String? goalId) {
    if (goalId == null) return null;
    for (final p in _state.pots) {
      if (p.goalId == goalId) return p;
    }
    return null;
  }

  /// Копилка цели или ближайшего предка: шаг «Отложить 10%» внутри
  /// «Финансовой подушки» пополняет копилку подушки.
  SavingsPot? potForGoal(String? goalId) {
    var g = goalById(goalId);
    var guard = 0;
    while (g != null && guard++ < 20) {
      final p = ownPotOf(g.id);
      if (p != null) return p;
      g = goalById(g.parentId);
    }
    return null;
  }

  static String _potEmoji(Goal g) => switch (g.area) {
        LifeArea.travel => '🏖',
        LifeArea.home => '🏠',
        LifeArea.car => '🚗',
        LifeArea.study => '🎓',
        LifeArea.health || LifeArea.sport => '🩺',
        LifeArea.family => '💍',
        _ => g.title.toLowerCase().contains('подушк') ? '🛟' : '🐷',
      };

  /// Задать сумму, которую нужно накопить на цель (только взрослые).
  /// Создаёт в «Бюджете» копилку цели или меняет её сумму. Пусто или 0 —
  /// отвязать копилку от цели (накопленные деньги остаются в бюджете).
  Future<SavingsPot?> setGoalSavingTarget(String goalId, int? target) async {
    final goal = goalById(goalId);
    if (goal == null || !canSeeBudget || goal.isDaily) return null;
    final pot = ownPotOf(goalId);
    if (target == null || target <= 0) {
      if (pot == null) return null;
      pot.goalId = null;
      await _commit();
      return null;
    }
    if (pot != null) {
      pot.target = target;
      await _commit();
      return pot;
    }
    final p = SavingsPot(id: _id(), name: goal.title, emoji: _potEmoji(goal), target: target, goalId: goal.id);
    _state.pots.add(p);
    await _commit();
    return p;
  }

  /// Вписать отложенную сумму прямо из цели: пополнение копилки цели (или
  /// её предка) записывается в «Бюджет». Для рутины («Отложить 10% дохода»)
  /// заодно отмечается выполнение за период. Если копилка наполнилась,
  /// цель без шагов выполняется сама.
  Future<(MoneyEntry?, CompletionResult)> depositToGoal(String goalId, int amount,
      {String note = '', bool markRoutine = true}) async {
    final goal = goalById(goalId);
    final pot = potForGoal(goalId);
    final result = CompletionResult();
    if (goal == null || pot == null || amount <= 0 || !canSeeBudget) return (null, result);
    final e = await addMoney(
      kind: MoneyKind.saving,
      amount: amount,
      potId: pot.id,
      note: note.trim().isEmpty ? goal.title : note,
    );
    if (e == null) return (null, result);
    final auto = _lastPotReward;
    if (auto != null) _merge(result, auto);
    final now = _clock();
    if (markRoutine && goal.isDaily && GameRules.canDoNow(goal, now) && !GameRules.isDoneToday(goal, now)) {
      _merge(result, await toggleDaily(goal.id));
    }
    return (e, result);
  }

  Future<void> deleteMoney(String id) async {
    if (!canSeeBudget) return;
    _state.money.removeWhere((m) => m.id == id);
    await _commit();
  }

  Future<void> setCategoryLimit(String categoryId, int? limit) async {
    final c = categoryById(categoryId);
    if (c == null || !canSeeBudget) return;
    c.limit = (limit == null || limit <= 0) ? null : limit;
    await _commit();
  }

  Future<BudgetCategory?> addCategory({required String name, required String emoji, required MoneyKind kind}) async {
    if (!canSeeBudget || name.trim().isEmpty || kind == MoneyKind.saving) return null;
    final c = BudgetCategory(id: _id(), name: name.trim(), emoji: emoji, kind: kind);
    _state.categories.add(c);
    await _commit();
    return c;
  }

  Future<SavingsPot?> addPot({required String name, required String emoji, required int target, String? goalId}) async {
    if (!canSeeBudget || name.trim().isEmpty || target <= 0) return null;
    final pot = SavingsPot(id: _id(), name: name.trim(), emoji: emoji, target: target, goalId: goalById(goalId)?.id);
    _state.pots.add(pot);
    await _commit();
    return pot;
  }

  Future<void> updatePot(SavingsPot pot, {required String name, required String emoji, required int target, String? goalId}) async {
    if (!canSeeBudget || name.trim().isEmpty || target <= 0) return;
    pot
      ..name = name.trim()
      ..emoji = emoji
      ..target = target
      ..goalId = goalById(goalId)?.id;
    await _commit();
  }

  /// Удалить копилку вместе с её пополнениями.
  Future<void> deletePot(String id) async {
    if (!canSeeBudget) return;
    _state.pots.removeWhere((p) => p.id == id);
    _state.money.removeWhere((m) => m.potId == id);
    await _commit();
  }

  // ---------- v5: шаблоны целей ----------

  /// Создать цепочку целей по шаблону («Финансовая подушка», «Чек-ап»…).
  /// Только взрослые. Возвращает верхнюю цель.
  Future<Goal?> applyTemplate(GoalTemplate t, {bool family = false, bool private = false}) async {
    final hero = activeHero;
    if (hero == null || !hero.role.isAdult || t.nodes.isEmpty) return null;
    Goal? top;
    Future<void> make(TplNode n, String? parentId) async {
      final g = await addGoal(
        title: n.title,
        tier: n.tier,
        description: n.description,
        parentId: parentId,
        ownerId: hero.id,
        isFamily: family && !private,
        isPrivate: private,
        stat: n.stat ?? (n.area ?? t.area).stat,
        area: n.area ?? t.area,
        repeat: n.repeat,
        weekdays: n.weekdays,
        monthDay: n.monthDay,
      );
      top ??= g;
      for (final k in n.children) {
        await make(k, g.id);
      }
    }

    for (final n in t.nodes) {
      await make(n, null);
    }
    return top;
  }

  // ---------- v5: будильники и напоминания ----------

  DateTime? _lastTick;

  bool canEditReminder(Reminder r) {
    final me = activeHero;
    return me != null && (r.heroId == me.id || me.role.isAdult);
  }

  Future<Reminder?> addReminder({
    required String title,
    required ReminderKind kind,
    required int hour,
    required int minute,
    List<int> weekdays = const [],
    DateTime? date,
    String? goalId,
    String? heroId,
    bool wakeUp = false,
    int snoozeMinutes = 5,
  }) async {
    final me = activeHero;
    if (me == null) return null;
    // Юнга ставит будильники только себе.
    final owner = me.role.isAdult ? (heroById(heroId) ?? me) : me;
    final r = Reminder(
      id: _id(),
      heroId: owner.id,
      title: title.trim().isEmpty ? kind.label : title.trim(),
      kind: kind,
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      weekdays: date == null ? _normDays(weekdays) : [],
      date: date == null ? null : DateTime(date.year, date.month, date.day),
      goalId: goalById(goalId)?.id,
      createdAt: _clock(),
      wakeUp: kind == ReminderKind.alarm && wakeUp,
      snoozeMinutes: snoozeMinutes.clamp(1, 60),
    );
    _state.reminders.add(r);
    await _commit();
    return r;
  }

  static List<int> _normDays(List<int> days) {
    final d = {for (final x in days) if (x >= 1 && x <= 7) x}.toList()..sort();
    return d.length == 7 ? <int>[] : d;
  }

  Future<void> updateReminder(
    Reminder r, {
    required String title,
    required ReminderKind kind,
    required int hour,
    required int minute,
    List<int> weekdays = const [],
    DateTime? date,
    String? goalId,
    bool wakeUp = false,
    int snoozeMinutes = 5,
  }) async {
    if (!canEditReminder(r)) return;
    r
      ..title = title.trim().isEmpty ? kind.label : title.trim()
      ..kind = kind
      ..hour = hour.clamp(0, 23)
      ..minute = minute.clamp(0, 59)
      ..weekdays = date == null ? _normDays(weekdays) : []
      ..date = date == null ? null : DateTime(date.year, date.month, date.day)
      ..goalId = goalById(goalId)?.id
      ..wakeUp = kind == ReminderKind.alarm && wakeUp
      ..snoozeMinutes = snoozeMinutes.clamp(1, 60)
      ..snoozedUntil = null
      ..enabled = true;
    await _commit();
  }

  Future<void> setReminderEnabled(String id, bool on) async {
    final r = reminderById(id);
    if (r == null || !canEditReminder(r)) return;
    r
      ..enabled = on
      ..snoozedUntil = null;
    // Разовое напоминание из прошлого при включении переносим на ближайшее такое же время.
    if (on && r.date != null && TimeRules.nextOccurrence(r, _clock()) == null) {
      final now = _clock();
      var d = DateTime(now.year, now.month, now.day);
      if (!DateTime(d.year, d.month, d.day, r.hour, r.minute).isAfter(now)) d = DateTime(d.year, d.month, d.day + 1);
      r.date = d;
    }
    await _commit();
  }

  Future<void> deleteReminder(String id) async {
    final r = reminderById(id);
    if (r == null || !canEditReminder(r)) return;
    _state.reminders.removeWhere((x) => x.id == id);
    await _commit();
  }

  /// Проверить время: какие будильники и напоминания прозвенели с прошлой
  /// проверки и не закончился ли таймер. Вызывается раз в несколько секунд.
  List<TickEvent> tick() {
    final now = _clock();
    var since = _lastTick ?? _state.remindersCheckedAt ?? now;
    final floor = now.subtract(TimeRules.missedWindow);
    if (since.isBefore(floor)) since = floor;
    _lastTick = now;
    final events = <TickEvent>[];
    for (final r in _state.reminders) {
      final at = TimeRules.firedBetween(r, since, now);
      if (at == null) continue;
      final snooze = r.snoozedUntil;
      if (snooze != null && !snooze.isAfter(now)) r.snoozedUntil = null;
      // Разовое отзвенело — выключаем (при «Отложить» оно снова включится).
      if (r.oneTime && r.snoozedUntil == null) r.enabled = false;
      final late = now.difference(at) > TimeRules.alarmGrace;
      events.add(TickEvent(
        kind: late
            ? TickKind.missed
            : r.kind == ReminderKind.alarm
                ? TickKind.alarm
                : TickKind.reminder,
        at: at,
        reminder: r,
      ));
    }
    for (final t in _state.timers) {
      if (t.mode == TimerMode.countdown && !t.rang && !t.paused && t.leftSec(now) <= 0) {
        t.rang = true;
        events.add(TickEvent(kind: TickKind.timerDone, at: now, timer: t));
      }
    }
    if (events.isNotEmpty) {
      _state.remindersCheckedAt = now;
      notifyListeners();
      _repo.save(_state);
    }
    return events;
  }

  /// Отложить будильник на [Reminder.snoozeMinutes] минут.
  Future<void> snooze(String id) async {
    final r = reminderById(id);
    if (r == null) return;
    r
      ..enabled = true
      ..snoozedUntil = _clock().add(Duration(minutes: r.snoozeMinutes));
    await _commit();
  }

  /// Выключить прозвеневший будильник. Если это «Подъём» и выключили вовремя
  /// (до 10 минут после звонка) — +XP, монеты и ⏰ пунктуальность, раз в день.
  Future<CompletionResult> dismissAlarm(String id, DateTime firedAt) async {
    final r = reminderById(id);
    final result = CompletionResult();
    if (r == null) return result;
    r.snoozedUntil = null;
    final hero = heroById(r.heroId);
    final now = _clock();
    final onTime = !now.isBefore(firedAt) && now.difference(firedAt) <= TimeRules.wakeWindow;
    final today = GameRules.dayKey(now);
    final already = _state.records
        .any((x) => x.heroId == hero?.id && x.kind == XpKind.wake && GameRules.dayKey(x.at) == today);
    if (hero != null && r.kind == ReminderKind.alarm && r.wakeUp && onTime && !already) {
      const xp = 5, coins = 2;
      const traits = {HeroTrait.punctuality: 2};
      hero.coins += coins;
      hero.traitXp[HeroTrait.punctuality] = (hero.traitXp[HeroTrait.punctuality] ?? 0) + 2;
      result
        ..xp = xp
        ..coins = coins
        ..traits.addAll(traits);
      result.newLevel = _award(hero, HeroStat.strength, xp);
      _recordOther(hero, XpKind.wake, r.id, HeroStat.strength, xp, coins, area: LifeArea.health, traits: traits);
      result.badges.addAll(_checkBadges(hero));
    }
    await _commit();
    return result;
  }

  // ---------- v5: таймеры «на время» ----------

  /// Запустить таймер активного героя (у героя может быть один таймер).
  Future<ActiveTimer?> startTimer({
    required String title,
    required TimerMode mode,
    int plannedSec = 0,
    String? goalId,
    String? skillId,
    HeroStat? stat,
    LifeArea? area,
  }) async {
    final hero = activeHero;
    if (hero == null || activeTimer != null) return null;
    if (mode == TimerMode.countdown && plannedSec < 10) return null;
    final goal = goalById(goalId);
    final skill = skillById(skillId);
    final t = ActiveTimer(
      id: _id(),
      heroId: hero.id,
      title: title.trim().isEmpty ? (goal?.title ?? skill?.name ?? 'Фокус') : title.trim(),
      mode: mode,
      plannedSec: mode == TimerMode.countdown ? plannedSec : 0,
      startedAt: _clock(),
      goalId: goal?.id,
      skillId: skill?.id,
      stat: stat ?? goal?.stat ?? skill?.stat ?? area?.stat ?? HeroStat.mastery,
      area: area ?? goal?.area ?? skill?.area,
    );
    _state.timers.add(t);
    await _commit();
    return t;
  }

  Future<void> pauseTimer() async {
    final t = activeTimer;
    if (t == null || t.paused) return;
    t.pausedAt = _clock();
    await _commit();
  }

  Future<void> resumeTimer() async {
    final t = activeTimer;
    final at = t?.pausedAt;
    if (t == null || at == null) return;
    t
      ..pausedSec += _clock().difference(at).inSeconds
      ..pausedAt = null;
    await _commit();
  }

  /// Сбросить таймер без записи.
  Future<void> cancelTimer() async {
    final t = activeTimer;
    if (t == null) return;
    _state.timers.remove(t);
    await _commit();
  }

  int _todayXp(String heroId, XpKind kind) {
    final today = GameRules.dayKey(_clock());
    return _state.records
        .where((r) => r.heroId == heroId && r.kind == kind && GameRules.dayKey(r.at) == today)
        .fold<int>(0, (s, r) => s + r.xp);
  }

  /// Остановить таймер и записать сессию. [completeGoal] — заодно выполнить
  /// связанную цель (или отметить рутину). Для навыка «на время» замер
  /// сохраняется автоматически.
  Future<TimerResult> finishTimer({bool completeGoal = false}) async {
    final t = activeTimer;
    final hero = activeHero;
    if (t == null || hero == null) return TimerResult();
    final now = _clock();
    final sec = t.elapsedSec(now);
    final beat = t.mode == TimerMode.countdown && sec >= 10 && sec <= t.plannedSec;
    var xp = TimeRules.focusXp(sec) + (beat ? TimeRules.beatBonusXp : 0);
    xp = min(xp, max(0, TimeRules.focusXpPerDay - _todayXp(hero.id, XpKind.focus)));
    final coins = xp <= 0 ? 0 : xp ~/ 3 + (beat ? TimeRules.beatBonusCoins : 0);
    final reward = CompletionResult(xp: xp, coins: coins);
    final session = FocusSession(
      id: _id(),
      heroId: hero.id,
      title: t.title,
      mode: t.mode,
      plannedSec: t.plannedSec,
      actualSec: sec,
      at: now,
      goalId: t.goalId,
      skillId: t.skillId,
      beat: beat,
      xp: xp,
      coins: coins,
      stat: t.stat,
      area: t.area,
    );
    _state.timers.remove(t);
    _state.sessions.add(session);
    final oldest = now.subtract(const Duration(days: _recordsKeepDays));
    _state.sessions.removeWhere((x) => x.at.isBefore(oldest));
    if (xp > 0) {
      hero.coins += coins;
      reward.newLevel = _award(hero, t.stat, xp);
      _recordOther(hero, XpKind.focus, session.id, t.stat, xp, coins, area: t.area);
    }
    final goal = goalById(t.goalId);
    if (beat) {
      final what = goal?.isPrivate == true ? 'личное дело' : '«${t.title}»';
      _log(hero.id, '⚡', 'успел(а) $what за ${TimeRules.clock(sec)}', xp: xp);
    }
    SkillEntry? entry;
    final skill = skillById(t.skillId);
    if (skill != null && skill.timed && sec > 0) {
      final r = _addEntry(skill, hero, sec.toDouble(), note: '⏱ таймер');
      entry = r.$1;
      _merge(reward, r.$2);
    }
    reward.badges.addAll(_checkBadges(hero));
    await _commit();
    if (completeGoal && goal != null) {
      final CompletionResult r;
      if (goal.isDaily) {
        r = GameRules.isDoneToday(goal, _clock()) ? CompletionResult() : await toggleDaily(goal.id);
      } else {
        r = await this.completeGoal(goal.id);
      }
      _merge(reward, r);
    }
    return TimerResult(session: session, entry: entry, reward: reward);
  }

  static void _merge(CompletionResult into, CompletionResult r) {
    into
      ..xp += r.xp
      ..coins += r.coins
      ..newLevel = r.newLevel ?? into.newLevel
      ..pending = into.pending || r.pending;
    into.chain.addAll(r.chain);
    into.badges.addAll(r.badges);
    for (final e in r.traits.entries) {
      into.traits[e.key] = (into.traits[e.key] ?? 0) + e.value;
    }
  }

  /// Удалить запись таймера — опыт и монеты за неё возвращаются.
  Future<void> deleteSession(String id) async {
    FocusSession? s;
    for (final x in _state.sessions) {
      if (x.id == id) s = x;
    }
    if (s == null) return;
    final hero = heroById(s.heroId);
    if (hero != null) {
      final rec = _unrecord(s.id, hero.id);
      if (rec != null) {
        _award(hero, rec.stat, -rec.xp);
        hero.coins = max(0, hero.coins - rec.coins);
      }
    }
    _state.sessions.remove(s);
    await _commit();
  }

  // ---------- v5: навыки и личные рекорды ----------

  Future<Skill?> addSkill({
    required String name,
    required String emoji,
    String unit = '',
    SkillBetter better = SkillBetter.higher,
    bool timed = false,
    double? target,
    HeroStat? stat,
    LifeArea? area,
  }) async {
    final hero = activeHero;
    if (hero == null || name.trim().isEmpty) return null;
    final s = Skill(
      id: _id(),
      heroId: hero.id,
      name: name.trim(),
      emoji: emoji,
      unit: timed ? '' : unit.trim(),
      better: better,
      timed: timed,
      target: target != null && target > 0 ? target : null,
      stat: stat ?? area?.stat ?? HeroStat.mastery,
      area: area,
      createdAt: _clock(),
    );
    _state.skills.add(s);
    await _commit();
    return s;
  }

  Future<void> updateSkill(
    Skill s, {
    required String name,
    required String emoji,
    String unit = '',
    SkillBetter better = SkillBetter.higher,
    bool timed = false,
    double? target,
    HeroStat? stat,
    LifeArea? area,
  }) async {
    if (name.trim().isEmpty || s.heroId != activeHero?.id) return;
    s
      ..name = name.trim()
      ..emoji = emoji
      ..unit = timed ? '' : unit.trim()
      ..better = better
      ..timed = timed
      ..target = target != null && target > 0 ? target : null
      ..stat = stat ?? s.stat
      ..area = area;
    await _commit();
  }

  /// Удалить навык с замерами. Уже полученный опыт остаётся (как у целей).
  Future<void> deleteSkill(String id) async {
    final s = skillById(id);
    if (s == null || s.heroId != activeHero?.id) return;
    _state.skills.remove(s);
    _state.skillEntries.removeWhere((e) => e.skillId == id);
    await _commit();
  }

  /// Записать замер навыка. Первый замер дня даёт опыт за тренировку,
  /// новый личный рекорд — бонус (раз в день на навык). Самый первый замер
  /// навыка — стартовая точка, а не рекорд.
  Future<(SkillEntry?, CompletionResult)> addSkillEntry(String skillId, double value, {String note = ''}) async {
    final s = skillById(skillId);
    final hero = activeHero;
    if (s == null || hero == null || s.heroId != hero.id || value < 0 || value.isNaN || value.isInfinite) {
      return (null, CompletionResult());
    }
    final r = _addEntry(s, hero, value, note: note);
    r.$2.badges.addAll(_checkBadges(hero));
    await _commit();
    return r;
  }

  (SkillEntry, CompletionResult) _addEntry(Skill s, HeroProfile hero, double value, {String note = ''}) {
    final now = _clock();
    final today = GameRules.dayKey(now);
    final prevBest = TimeRules.personalBest(s, _state.skillEntries);
    final pb = prevBest != null && TimeRules.isBetter(s, value, prevBest);
    final todays = _state.skillEntries.where((e) => e.skillId == s.id && GameRules.dayKey(e.at) == today).toList();
    final practice = todays.isEmpty;
    final pbBonus = pb && !todays.any((e) => e.pb);
    final xp = (practice ? TimeRules.practiceXp : 0) + (pbBonus ? TimeRules.pbXp : 0);
    final coins = (practice ? TimeRules.practiceCoins : 0) + (pbBonus ? TimeRules.pbCoins : 0);
    final entry = SkillEntry(
      id: _id(),
      skillId: s.id,
      heroId: hero.id,
      value: value,
      at: now,
      note: note.trim(),
      pb: pb,
      xp: xp,
      coins: coins,
    );
    _state.skillEntries.add(entry);
    final result = CompletionResult(xp: xp, coins: coins);
    if (xp > 0) {
      hero.coins += coins;
      result.newLevel = _award(hero, s.stat, xp);
      _recordOther(hero, XpKind.skill, entry.id, s.stat, xp, coins, area: s.area);
    }
    if (pb) {
      _log(hero.id, '🏅', 'новый рекорд: ${s.name} — ${TimeRules.formatWithUnit(s, value)}', xp: xp);
    }
    final target = s.target;
    if (target != null) {
      bool reached(double v) => v == target || TimeRules.isBetter(s, v, target);
      if (reached(value) && (prevBest == null || !reached(prevBest))) {
        _log(hero.id, '🎯', 'достиг(ла) цели навыка «${s.name}»: ${TimeRules.formatWithUnit(s, target)}');
      }
    }
    return (entry, result);
  }

  /// Удалить замер — опыт и монеты за него возвращаются.
  Future<void> deleteSkillEntry(String id) async {
    SkillEntry? e;
    for (final x in _state.skillEntries) {
      if (x.id == id) e = x;
    }
    final hero = heroById(e?.heroId);
    if (e == null || hero == null || hero.id != activeHero?.id) return;
    final rec = _unrecord(e.id, hero.id);
    if (rec != null) {
      _award(hero, rec.stat, -rec.xp);
      hero.coins = max(0, hero.coins - rec.coins);
    }
    _state.skillEntries.remove(e);
    await _commit();
  }

  // ---------- Сервисное ----------

  Future<void> resetAll() async {
    await _repo.clear();
    _state = AppState.empty();
    notifyListeners();
    await push.clear();
  }

  /// Пример целей, чтобы сразу увидеть, как работают цепочки.
  Future<void> seedDemo() async {
    final hero = activeHero;
    if (hero == null) return;
    if (_state.solo) return _seedSoloDemo(hero);
    final legend = await addGoal(
      title: 'Семейный отпуск на море',
      tier: GoalTier.legend,
      isFamily: true,
      stat: HeroStat.charisma,
      area: LifeArea.travel,
      description: 'Летом всей гильдией едем к морю!',
    );
    final epic1 = await addGoal(
        title: 'Накопить на путешествие',
        tier: GoalTier.epic,
        parentId: legend.id,
        stat: HeroStat.mastery,
        area: LifeArea.finance);
    final q1 = await addGoal(
        title: 'Открыть накопительный счёт', tier: GoalTier.quest, parentId: epic1.id, stat: HeroStat.intellect);
    await addGoal(title: 'Сравнить 3 банка', tier: GoalTier.task, parentId: q1.id, stat: HeroStat.intellect);
    await addGoal(title: 'Открыть вклад', tier: GoalTier.task, parentId: q1.id, stat: HeroStat.intellect);
    final q2 = await addGoal(
        title: 'Откладывать каждый месяц', tier: GoalTier.quest, parentId: epic1.id, stat: HeroStat.mastery);
    await addGoal(title: 'Составить семейный бюджет', tier: GoalTier.task, parentId: q2.id);
    final epic2 = await addGoal(
        title: 'Спланировать маршрут', tier: GoalTier.epic, parentId: legend.id, stat: HeroStat.charisma);
    await addGoal(title: 'Выбрать город', tier: GoalTier.task, parentId: epic2.id, stat: HeroStat.charisma);
    await addGoal(title: 'Забронировать жильё', tier: GoalTier.task, parentId: epic2.id);
    final workout = await addGoal(
        title: 'Зарядка 10 минут', tier: GoalTier.daily, stat: HeroStat.strength, ownerId: hero.id, area: LifeArea.sport);
    await addGoal(
        title: 'Прочитать 10 страниц',
        tier: GoalTier.daily,
        stat: HeroStat.intellect,
        ownerId: hero.id,
        area: LifeArea.study);
    await addGoal(
        title: 'Генеральная уборка',
        tier: GoalTier.daily,
        repeat: Repeat.weekly,
        weekdays: const [6],
        isFamily: true,
        ownerId: hero.id,
        area: LifeArea.home);
    await addGoal(
        title: 'Оплатить коммуналку',
        tier: GoalTier.daily,
        repeat: Repeat.monthly,
        monthDay: 10,
        stat: HeroStat.intellect,
        ownerId: hero.id,
        area: LifeArea.finance);
    await addReminder(
        title: 'Подъём', kind: ReminderKind.alarm, hour: 7, minute: 0, weekdays: const [1, 2, 3, 4, 5], wakeUp: true);
    await addReminder(title: 'Зарядка', kind: ReminderKind.reminder, hour: 7, minute: 15, goalId: workout.id);
    await addSkill(name: 'Отжимания', emoji: '💪', unit: 'раз', area: LifeArea.sport);
    if (hero.role.isAdult) {
      await addReward(title: 'Мультфильм перед сном', emoji: '📺', cost: 20);
      await addReward(title: 'Пицца на ужин', emoji: '🍕', cost: 60);
      await addReward(title: 'Поход в кино', emoji: '🎬', cost: 200);
      await addPot(name: 'Отпуск на море', emoji: '🏖', target: 150000, goalId: legend.id);
    }
  }

  /// Пример для личного режима: своя мечта и регулярные дела.
  Future<void> _seedSoloDemo(HeroProfile hero) async {
    final legend = await addGoal(
      title: 'Пробежать полумарафон',
      tier: GoalTier.legend,
      stat: HeroStat.strength,
      area: LifeArea.sport,
      description: '21 км к следующей осени — шаг за шагом.',
    );
    final epic = await addGoal(
        title: 'Выйти на 10 км без остановки', tier: GoalTier.epic, parentId: legend.id, stat: HeroStat.strength);
    final quest = await addGoal(
        title: 'Подготовиться к тренировкам', tier: GoalTier.quest, parentId: epic.id, stat: HeroStat.strength);
    await addGoal(title: 'Купить беговые кроссовки', tier: GoalTier.task, parentId: quest.id);
    await addGoal(
        title: 'Составить план тренировок', tier: GoalTier.task, parentId: quest.id, stat: HeroStat.intellect);
    await addGoal(
        title: 'Пробежка',
        tier: GoalTier.daily,
        parentId: epic.id,
        stat: HeroStat.strength,
        weekdays: const [1, 3, 5]);
    await addGoal(title: 'Прочитать 10 страниц', tier: GoalTier.daily, stat: HeroStat.intellect);
    await addGoal(
        title: 'Длинная пробежка', tier: GoalTier.daily, repeat: Repeat.weekly, weekdays: const [7], stat: HeroStat.strength);
    await addGoal(
        title: 'Подвести итоги месяца', tier: GoalTier.daily, repeat: Repeat.monthly, monthDay: 1, stat: HeroStat.intellect);
    await addSkill(name: 'Бег 1 км', emoji: '🏃', timed: true, better: SkillBetter.lower, area: LifeArea.sport);
    await addReminder(title: 'Пробежка', kind: ReminderKind.reminder, hour: 19, minute: 0, weekdays: const [1, 3, 5]);
    await addReward(title: 'Новая книга', emoji: '📚', cost: 100);
    await addReward(title: 'Вечер кино', emoji: '🎬', cost: 60);
  }
}
