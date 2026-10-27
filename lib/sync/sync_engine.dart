import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../state/game_controller.dart';
import 'alliance.dart';
import 'codec.dart';
import 'merge.dart';
import 'sync_api.dart';

/// Подключение устройства к гильдии на сервере (хранится на устройстве).
class SyncSession {
  SyncSession({
    required this.url,
    required this.token,
    required this.guildId,
    required this.deviceId,
    required this.role,
    this.guildName = '',
    this.rev = 0,
    Map<String, BaseEntry>? base,
    List<String>? heroes,
    this.pickHero = false,
    this.lastSyncAt,
    this.email,
    this.ally,
    this.allyVer = 0,
  })  : base = base ?? {},
        heroes = heroes ?? [];

  final String url;
  final String token;
  final String guildId;
  final String deviceId;

  /// adult — взрослое устройство, kid — устройство юнги (без бюджета и взрослых профилей).
  String role;
  String guildName;

  /// Последняя ревизия гильдии, которую видело устройство.
  int rev;

  /// Последняя известная серверу версия каждой сущности — от неё считаются
  /// свои правки и сливаются чужие.
  final Map<String, BaseEntry> base;

  /// Герои, которые играют на этом устройстве (их будильники звонят здесь,
  /// их личные цели приходят сюда).
  final List<String> heroes;

  /// После входа по коду нужно выбрать, кто играет на устройстве.
  bool pickHero;
  DateTime? lastSyncAt;

  /// Почта для восстановления (скрытая: p***a@ya.ru).
  String? email;

  /// v0.9: гильдия, в которой состоит семья (документ с сервера), и его версия.
  Map<String, dynamic>? ally;
  int allyVer;

  bool get kid => role == 'kid';

  Map<String, dynamic> toJson() => {
        'url': url,
        'token': token,
        'guildId': guildId,
        'deviceId': deviceId,
        'role': role,
        'guildName': guildName,
        'rev': rev,
        'base': {for (final e in base.entries) e.key: [e.value.rev, e.value.data]},
        'heroes': heroes,
        'pickHero': pickHero,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'email': email,
        'ally': ally,
        'allyVer': allyVer,
      };

  factory SyncSession.fromJson(Map<String, dynamic> j) => SyncSession(
        url: j['url'] as String,
        token: j['token'] as String,
        guildId: j['guildId'] as String,
        deviceId: j['deviceId'] as String? ?? '',
        role: j['role'] as String? ?? 'adult',
        guildName: j['guildName'] as String? ?? '',
        rev: (j['rev'] as num?)?.toInt() ?? 0,
        base: {
          for (final e in ((j['base'] as Map?) ?? const {}).entries)
            if (e.value case [final num r, final String d]) e.key.toString(): BaseEntry(r.toInt(), d),
        },
        heroes: [for (final h in (j['heroes'] as List?) ?? const []) h.toString()],
        pickHero: j['pickHero'] as bool? ?? false,
        lastSyncAt: DateTime.tryParse(j['lastSyncAt'] as String? ?? ''),
        email: j['email'] as String?,
        ally: j['ally'] is Map ? Map<String, dynamic>.from(j['ally'] as Map) : null,
        allyVer: (j['allyVer'] as num?)?.toInt() ?? 0,
      );
}

class BaseEntry {
  const BaseEntry(this.rev, this.data);
  final int rev;
  final String data;
}

/// Где хранится подключение.
abstract class SyncStorage {
  Future<String?> read();
  Future<void> write(String? value);
}

class PrefsSyncStorage implements SyncStorage {
  static const _key = 'rodquest_sync_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String? value) async {
    final p = await SharedPreferences.getInstance();
    value == null ? await p.remove(_key) : await p.setString(_key, value);
  }
}

class MemorySyncStorage implements SyncStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? v) async => value = v;
}

enum SyncStatus { off, idle, syncing, offline, error }

/// Приглашение в гильдию.
class Invite {
  const Invite(this.code, this.kid, this.expiresAt);
  final String code;
  final bool kid;
  final DateTime expiresAt;

  /// ABCD-EFGH
  String get pretty => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
}

class GuildDevice {
  const GuildDevice({
    required this.id,
    required this.name,
    required this.kid,
    required this.heroIds,
    required this.lastSeen,
    required this.me,
  });

  final String id;
  final String name;
  final bool kid;
  final List<String> heroIds;
  final DateTime lastSeen;
  final bool me;
}

/// Синхронизация семьи (версия 0.8).
///
/// Один цикл: забрать с сервера всё новое → слить с правками устройства →
/// отправить свои правки. Если кто-то успел поменять ту же сущность — сервер
/// вернёт конфликт, сливаем ещё раз и повторяем.
///
/// Работает без интернета: правки копятся на устройстве и уходят, как только
/// появится связь.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.game,
    required this.defaultUrl,
    SyncApi Function(String url)? api,
    SyncStorage? storage,
    this.deviceLabel = 'Устройство',
    this.pollEvery = const Duration(seconds: 60),
    this.debounce = const Duration(seconds: 2),
  })  : _apiFor = api ?? ((url) => HttpSyncApi(url)),
        _storage = storage ?? PrefsSyncStorage();

  final GameController game;

  /// Адрес сервера из сборки (--dart-define=RODQUEST_SERVER=…). Пусто — не задан.
  final String defaultUrl;
  final SyncApi Function(String url) _apiFor;
  final SyncStorage _storage;

  /// Как назвать устройство в списке устройств гильдии.
  final String deviceLabel;
  final Duration pollEvery;
  final Duration debounce;

  SyncSession? _s;
  SyncApi? _api;
  SyncStatus _status = SyncStatus.off;
  String? _error;
  Timer? _poll;
  Timer? _soon;
  bool _again = false;
  bool _foreground = true;

  SyncSession? get session => _s;
  bool get connected => _s != null;
  bool get hasServer => defaultUrl.isNotEmpty;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSyncAt => _s?.lastSyncAt;
  bool get kidDevice => _s?.kid ?? false;
  bool get needsHeroPick => _s?.pickHero ?? false;

  /// Загрузить подключение. Вызывать до [GameController.load].
  Future<void> init() async {
    try {
      final raw = await _storage.read();
      if (raw != null) _s = SyncSession.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      _s = null;
    }
    _bindGame();
    if (_s != null) {
      _api = _apiFor(_s!.url);
      _status = SyncStatus.idle;
    }
  }

  /// Запустить фоновую синхронизацию (после загрузки данных).
  void start() {
    game.onLocalChange = _changed;
    game.onHeroActivated = _heroActivated;
    game.beforeReset = () => disconnect();
    if (_s == null) return;
    _schedulePoll();
    unawaited(syncNow());
  }

  void _bindGame() {
    final s = _s;
    game.cloudKid = s?.kid ?? false;
    game.deviceHeroIds = s == null ? null : {...s.heroes};
  }

  /// Приложение свернули/развернули.
  void setForeground(bool value) {
    _foreground = value;
    if (_s == null) return;
    if (value) {
      _schedulePoll();
      unawaited(syncNow());
    } else {
      _poll?.cancel();
      // Перед сном отправляем то, что успели наделать.
      unawaited(syncNow());
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_foreground) return;
    _poll = Timer.periodic(pollEvery, (_) => unawaited(syncNow()));
  }

  void _changed() {
    if (_s == null) return;
    _soon?.cancel();
    _soon = Timer(debounce, () => unawaited(syncNow()));
  }

  void _heroActivated(String heroId) {
    final s = _s;
    if (s == null || s.heroes.contains(heroId)) return;
    s.heroes.add(heroId);
    _bindGame();
    unawaited(_sendHeroes(fullResync: true));
  }

  Future<void> _sendHeroes({bool fullResync = false}) async {
    final s = _s;
    if (s == null) return;
    try {
      await _api!.call('set_heroes', {'heroIds': s.heroes}, token: s.token);
      // Новый герой на устройстве — забираем всё заново, чтобы пришли его личные цели.
      if (fullResync) _fullResync = true;
      await syncNow();
      if (_fullResync) await syncNow();
    } on SyncError catch (e) {
      _fail(e);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _soon?.cancel();
    super.dispose();
  }

  // ---------- подключение ----------

  String _url(String? url) {
    final u = (url ?? '').trim().isNotEmpty ? url!.trim() : defaultUrl;
    if (u.isEmpty) throw const SyncError('no_server', 'В этой сборке не задан адрес сервера');
    return u;
  }

  String _deviceName() {
    final me = game.activeHero;
    return me == null ? deviceLabel : '$deviceLabel · ${me.name}';
  }

  /// Глава подключает свою гильдию к облаку: все данные устройства уходят на сервер.
  Future<void> createGuild({String? url}) async {
    if (game.needsOnboarding) throw const SyncError('empty', 'Сначала создайте гильдию');
    final u = _url(url);
    final api = _apiFor(u);
    final heroes = [for (final h in game.heroes) h.id];
    final r = await api.call('create_guild', {
      'name': game.guildName,
      'deviceName': _deviceName(),
      'heroIds': heroes,
    });
    _s = SyncSession(
      url: u,
      token: r['token'] as String,
      guildId: r['guildId'] as String,
      deviceId: r['deviceId'] as String? ?? '',
      role: 'adult',
      guildName: r['guildName'] as String? ?? game.guildName,
      heroes: heroes,
    );
    _api = api;
    _bindGame();
    await _save();
    _schedulePoll();
    notifyListeners();
    // Первая отправка всех данных. Нет связи — уйдут позже, статус покажет.
    await syncNow();
  }

  /// Войти в гильдию по коду приглашения. Данные этого устройства заменяются данными гильдии.
  Future<void> join(String code, {String? url}) async {
    final u = _url(url);
    final api = _apiFor(u);
    final r = await api.call('join', {'code': code, 'deviceName': deviceLabel});
    await _connected(api, u, r);
  }

  /// Восстановление по почте — шаг 1: письмо с кодом.
  Future<String?> recoverStart(String email, {String? url}) async {
    final r = await _apiFor(_url(url)).call('recover_start', {'email': email});
    return r['devCode'] as String?;
  }

  /// Восстановление по почте — шаг 2: код из письма. Устройство входит как взрослое.
  Future<void> recoverFinish(String email, String code, {String? url}) async {
    final u = _url(url);
    final api = _apiFor(u);
    final r = await api.call('recover_finish', {'email': email, 'code': code, 'deviceName': deviceLabel});
    await _connected(api, u, r);
  }

  Future<void> _connected(SyncApi api, String url, Map<String, dynamic> r) async {
    final s = SyncSession(
      url: url,
      token: r['token'] as String,
      guildId: r['guildId'] as String,
      deviceId: r['deviceId'] as String? ?? '',
      role: r['role'] as String? ?? 'adult',
      guildName: r['guildName'] as String? ?? '',
      pickHero: true,
    );
    // Забираем гильдию целиком и только потом заменяем данные устройства.
    final remote = <String, String>{};
    var since = 0;
    while (true) {
      final p = await api.call('pull', {'since': since}, token: s.token);
      for (final c in (p['changes'] as List? ?? const [])) {
        final m = c as Map;
        final d = m['d'] as String?;
        final k = m['k'] as String;
        if (d == null) {
          remote.remove(k);
          s.base.remove(k);
        } else {
          remote[k] = d;
          s.base[k] = BaseEntry((m['r'] as num).toInt(), d);
        }
      }
      since = (p['rev'] as num).toInt();
      if (p['more'] != true) break;
    }
    s.rev = since;
    s.lastSyncAt = game.now;
    _s = s;
    _api = api;
    _bindGame();
    game.replaceFromSync(SyncCodec.decode(remote, AppState.empty()), fresh: true);
    await _save();
    _status = SyncStatus.idle;
    _error = null;
    _schedulePoll();
    notifyListeners();
  }

  /// Кто играет на этом устройстве (после входа по коду).
  Future<void> pickHero(String heroId) async {
    final s = _s;
    if (s == null) return;
    if (!game.claimHero(heroId)) return;
    s.pickHero = false;
    if (!s.heroes.contains(heroId)) s.heroes.add(heroId);
    _bindGame();
    await _save();
    notifyListeners();
    // Теперь устройству видны личные цели выбранного героя — забираем гильдию заново.
    await _sendHeroes(fullResync: true);
  }

  /// Новый герой на этом устройстве (после входа по коду).
  Future<void> pickNewHero(String name, String avatar) async {
    final hero = await game.addHero(name: name, avatar: avatar, role: kidDevice ? HeroRole.child : HeroRole.member);
    await pickHero(hero.id);
  }

  /// Отключить устройство от гильдии. Данные на устройстве остаются.
  Future<void> disconnect({bool tellServer = true}) async {
    final s = _s;
    if (s == null) return;
    if (tellServer) {
      try {
        await _api!.call('leave', const {}, token: s.token);
      } on SyncError catch (_) {
        // Нет связи — всё равно отключаемся; на сервере устройство можно удалить из списка.
      }
    }
    _s = null;
    _api = null;
    _poll?.cancel();
    _soon?.cancel();
    _status = SyncStatus.off;
    _error = null;
    _bindGame();
    await _storage.write(null);
    notifyListeners();
  }

  // ---------- гильдия ----------

  Future<Map<String, dynamic>> _call(String op, [Map<String, dynamic> body = const {}]) async {
    final s = _s;
    if (s == null) throw const SyncError('off', 'Устройство не подключено к облаку');
    try {
      return await _api!.call(op, body, token: s.token);
    } on SyncError catch (e) {
      if (e.revoked) await _revoked();
      rethrow;
    }
  }

  Future<Invite> invite({required bool kid}) async {
    final r = await _call('invite', {'role': kid ? 'kid' : 'adult'});
    return Invite(r['code'] as String, kid, DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num).toInt()));
  }

  Future<List<GuildDevice>> devices() async {
    final r = await _call('devices');
    return [
      for (final d in (r['devices'] as List? ?? const []))
        GuildDevice(
          id: (d as Map)['id'] as String,
          name: d['name'] as String? ?? '',
          kid: d['role'] == 'kid',
          heroIds: [for (final h in (d['heroIds'] as List? ?? const [])) h.toString()],
          lastSeen: DateTime.fromMillisecondsSinceEpoch((d['lastSeen'] as num?)?.toInt() ?? 0),
          me: d['me'] == true,
        ),
    ];
  }

  Future<void> revoke(String deviceId) => _call('revoke', {'deviceId': deviceId});

  Future<void> refreshInfo() async {
    final r = await _call('guild');
    final s = _s!;
    s
      ..email = r['email'] as String?
      ..role = r['role'] as String? ?? s.role
      ..guildName = r['guildName'] as String? ?? s.guildName;
    _bindGame();
    await _save();
    notifyListeners();
  }

  /// Почта для восстановления — шаг 1. Возвращает код только у локального сервера разработки.
  Future<String?> linkEmailStart(String email) async =>
      (await _call('email_link_start', {'email': email}))['devCode'] as String?;

  Future<void> linkEmailFinish(String email, String code) async {
    final r = await _call('email_link_finish', {'email': email, 'code': code});
    _s!.email = r['email'] as String?;
    await _save();
    notifyListeners();
  }

  Future<void> unlinkEmail() async {
    await _call('email_unlink');
    _s!.email = null;
    await _save();
    notifyListeners();
  }

  // ---------- синхронизация ----------

  /// Синхронизировать сейчас. Ошибки не бросаются — видны в [status].
  /// Если синхронизация уже идёт, она повторится с новыми правками, а
  /// возвращается её же Future.
  Future<void> syncNow() {
    if (_s == null) return Future.value();
    final running = _inflight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inflight = _runSync();
  }

  Future<void>? _inflight;

  /// Забрать гильдию целиком при следующем заходе (на устройстве новый герой).
  bool _fullResync = false;

  Future<void> _runSync() async {
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      var rounds = 0;
      while (true) {
        _again = false;
        await _syncOnce();
        if (!_again || _s == null || ++rounds >= 5) break;
      }
      final s = _s;
      if (s != null) {
        s.lastSyncAt = game.now;
        _status = SyncStatus.idle;
        _error = null;
        // v0.9: заодно — свежая гильдия (если она изменилась).
        await _refreshAllianceQuiet();
        await _save();
      }
    } on SyncError catch (e) {
      if (e.revoked) await _revoked();
      _fail(e);
    } catch (e) {
      // Ошибка в данных не должна ронять приложение — покажем её в статусе.
      _fail(SyncError('crash', 'Сбой синхронизации: $e'));
    } finally {
      _inflight = null;
      notifyListeners();
      // Правка пришла в самом конце — отправим следующим заходом.
      if (_again && _s != null) {
        _again = false;
        _changed();
      }
    }
  }

  void _fail(SyncError e) {
    if (_s == null) return;
    _status = e.offline ? SyncStatus.offline : SyncStatus.error;
    _error = e.message;
    notifyListeners();
  }

  Future<void> _revoked() async {
    await disconnect(tellServer: false);
    _error = 'Устройство отключили от гильдии. Данные на нём остались.';
  }

  Future<void> _syncOnce() async {
    final s = _s!;
    final api = _api!;

    // 1. Забрать новое.
    final remote = <String, (String?, int)>{};
    var since = s.rev;
    if (_fullResync) {
      _fullResync = false;
      since = 0;
    }
    while (true) {
      final p = await api.call('pull', {'since': since}, token: s.token);
      for (final c in (p['changes'] as List? ?? const [])) {
        final m = c as Map;
        remote[m['k'] as String] = (m['d'] as String?, (m['r'] as num).toInt());
      }
      since = (p['rev'] as num).toInt();
      if (p['guildName'] is String) s.guildName = p['guildName'] as String;
      if (p['role'] is String && p['role'] != s.role) {
        s.role = p['role'] as String;
        _bindGame();
      }
      if (p['more'] != true) break;
    }
    if (_s != s) return;
    _apply(remote);
    s.rev = since;

    // 2. Отправить своё. Конфликт — слить и отправить ещё раз.
    for (var round = 0; round < 4; round++) {
      final local = SyncCodec.encode(game.syncState);
      final changes = <Map<String, dynamic>>[];
      for (final e in local.entries) {
        final b = s.base[e.key];
        if (b?.data == e.value) continue;
        changes.add({'k': e.key, 'd': e.value, 'base': b?.rev ?? 0, 's': SyncCodec.scopeOf(e.key, e.value)});
      }
      for (final e in s.base.entries) {
        if (!local.containsKey(e.key)) {
          changes.add({'k': e.key, 'd': null, 'base': e.value.rev, 's': _scopeOfBase(e.key, e.value.data)});
        }
      }
      if (changes.isEmpty) return;
      final conflicts = <String, (String?, int)>{};
      for (var i = 0; i < changes.length; i += 400) {
        final part = changes.sublist(i, i + 400 > changes.length ? changes.length : i + 400);
        final r = await api.call('push', {'changes': part}, token: s.token);
        if (_s != s) return;
        final sent = {for (final c in part) c['k'] as String: c};
        for (final res in (r['results'] as List? ?? const [])) {
          final m = res as Map;
          final k = m['k'] as String;
          final c = sent[k];
          if (c == null) continue;
          if (m['conflict'] == true) {
            conflicts[k] = (m['d'] as String?, (m['r'] as num).toInt());
          } else {
            // Принято (или запрещено — тогда больше не пытаемся).
            final d = c['d'] as String?;
            final rev = (m['r'] as num?)?.toInt() ?? 0;
            if (d == null) {
              s.base.remove(k);
            } else {
              s.base[k] = BaseEntry(rev, d);
            }
          }
        }
      }
      await _save();
      if (conflicts.isEmpty) return;
      _apply(conflicts);
    }
    _again = true;
  }

  static String _scopeOfBase(String key, String data) {
    try {
      return SyncCodec.scopeOf(key, data);
    } catch (_) {
      return SyncCodec.all;
    }
  }

  /// Слить пришедшие с сервера версии с данными устройства.
  void _apply(Map<String, (String?, int)> remote) {
    if (remote.isEmpty) return;
    final s = _s!;
    final local = SyncCodec.encode(game.syncState);
    final merged = Map<String, String>.of(local);
    var changed = false;
    for (final e in remote.entries) {
      final k = e.key;
      final (d, rev) = e.value;
      final b = s.base[k]?.data;
      final l = local[k];
      if (d == null) {
        s.base.remove(k);
      } else {
        s.base[k] = BaseEntry(rev, d);
      }
      if (d == b) continue; // наше же изменение вернулось или ничего нового
      final m = l == b ? d : SyncMerge.entity(k, b, l, d);
      if (m == l) continue;
      changed = true;
      if (m == null) {
        merged.remove(k);
      } else {
        merged[k] = m;
      }
    }
    if (changed) game.replaceFromSync(SyncCodec.decode(merged, game.syncState));
  }

  Future<void> _save() async {
    final s = _s;
    await _storage.write(s == null ? null : jsonEncode(s.toJson()));
  }

  // ---------- v0.9: гильдия (союз семей, кланов и одиночек) ----------

  Alliance? _ally;
  Map<String, dynamic>? _allyRaw;
  String? _lastCardSent;

  /// Гильдия, в которой состоит эта семья (клан, личный путь). null — не состоит
  /// или устройство не подключено к облаку.
  Alliance? get alliance {
    final raw = _s?.ally;
    if (raw == null) return null;
    if (!identical(raw, _allyRaw)) {
      _allyRaw = raw;
      _ally = Alliance.tryParse(raw);
    }
    return _ally;
  }

  /// Id семьи на сервере — так её видит гильдия.
  String? get mySpace => _s?.guildId;

  /// Ссылка на активного героя в гильдии: «семья|герой».
  String? get myRef {
    final s = _s, me = game.activeHero;
    return s == null || me == null ? null : '${s.guildId}|${me.id}';
  }

  bool allyCan(AllyPerm p) => alliance?.can(myRef, p) ?? false;
  bool get allyLeader => alliance?.isLeader(myRef) ?? false;

  /// Вступать в гильдию, основывать её и выходить решает глава семьи
  /// (в личном режиме — сам герой) на взрослом устройстве.
  bool get canManageMembership => !kidDevice && (game.activeHero?.role.canApprove ?? false);

  /// Карточка семьи для гильдии: название, вид и герои.
  Map<String, dynamic> _memberCard() {
    final solo = game.solo;
    final me = game.activeHero;
    return {
      'kind': solo ? 'solo' : game.groupKind.name,
      'name': solo ? (me?.name ?? 'Герой') : game.guildName,
      'emoji': solo ? (me?.avatar ?? '🧭') : game.groupKind.emoji,
      'heroes': {
        for (final h in game.heroes) h.id: {'n': h.name, 'a': h.avatar, 'k': h.role == HeroRole.child},
      },
    };
  }

  /// Совпадает ли карточка на сервере с нашей (без даты вступления).
  bool _sameCard(Alliance a) {
    final m = a.member(_s!.guildId);
    if (m == null) return true;
    final card = _memberCard();
    final heroes = card['heroes'] as Map;
    if (m.kind.name != card['kind'] || m.name != card['name'] || m.emoji != card['emoji']) return false;
    if (m.heroes.length != heroes.length) return false;
    for (final h in m.heroes) {
      final x = heroes[h.id] as Map?;
      if (x == null || x['n'] != h.name || x['a'] != h.avatar || x['k'] != h.kid) return false;
    }
    return true;
  }

  void _setAlliance(Map<String, dynamic> r) {
    final s = _s;
    if (s == null) return;
    if (r['same'] == true) return;
    final doc = r['alliance'];
    s
      ..ally = doc is Map ? Map<String, dynamic>.from(doc) : null
      ..allyVer = (r['ver'] as num?)?.toInt() ?? 0;
  }

  /// Забрать гильдию. Ошибки не показываются — старый сервер без гильдий
  /// или нет связи: остаётся то, что было.
  Future<void> _refreshAllianceQuiet() async {
    try {
      await refreshAlliance();
    } on SyncError catch (_) {
      // ничего — попробуем в следующий раз
    }
  }

  Future<void> refreshAlliance() async {
    final s = _s;
    if (s == null) return;
    final hadAlliance = s.ally != null;
    final r = await _api!.call('ally_get', {'ver': s.allyVer}, token: s.token);
    if (_s != s) return;
    _setAlliance(r);
    if (r['kicked'] == true && hadAlliance) {
      await game.logGuildEvent('🚪', 'узнал(а): нас исключили из гильдии');
    }
    final a = alliance;
    // Сменилось название семьи, вид или герои — обновить карточку в гильдии
    // (одну и ту же карточку отправляем один раз: сервер мог обрезать длинное имя).
    if (a != null && !_sameCard(a)) {
      final card = _memberCard();
      final key = jsonEncode(card);
      if (key != _lastCardSent) {
        _lastCardSent = key;
        _setAlliance(await _api!.call('ally_member', {'member': card}, token: s.token));
      }
    }
    await _save();
    notifyListeners();
  }

  /// Подключить семью к облаку, если ещё нет: гильдия живёт на сервере.
  Future<void> _ensureCloud() async {
    if (_s != null) return;
    if (!canManageMembership) {
      throw SyncError('no_rights', 'Подключить к облаку может ${Words.leader.toLowerCase()}');
    }
    await createGuild();
  }

  Future<Map<String, dynamic>> _allyCall(String op, [Map<String, dynamic> body = const {}]) async {
    final me = game.activeHero;
    if (me == null) throw const SyncError('no_hero', 'Выберите героя');
    final r = await _call(op, {...body, 'heroId': me.id});
    _setAlliance(r);
    await _save();
    notifyListeners();
    return r;
  }

  /// Основать гильдию. Семья (клан, одиночка) становится её первым участником,
  /// активный герой — главой гильдии.
  Future<void> createAlliance({required String name, required String emblem, String motto = ''}) async {
    await _ensureCloud();
    await _allyCall('ally_create', {'name': name, 'emblem': emblem, 'motto': motto, 'member': _memberCard()});
    await game.logGuildEvent(emblem, 'основал(а) гильдию «${name.trim()}»');
  }

  /// Вступить в гильдию по коду.
  Future<void> joinAlliance(String code) async {
    await _ensureCloud();
    await _allyCall('ally_join', {'code': code, 'member': _memberCard()});
    final a = alliance;
    if (a != null) {
      await game.logGuildEvent(a.emblem,
          game.solo ? 'вступил(а) в гильдию «${a.name}»' : 'привёл(а) ${Words.groupAcc} в гильдию «${a.name}»');
    }
  }

  Future<Invite> allianceInvite() async {
    final r = await _allyCall('ally_invite');
    return Invite(r['code'] as String, false, DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num).toInt()));
  }

  Future<void> leaveAlliance() async {
    final name = alliance?.name ?? '';
    final r = await _allyCall('ally_leave');
    _s?.ally = null;
    await _save();
    notifyListeners();
    await game.logGuildEvent('🚪', r['deleted'] == true ? 'распустил(а) гильдию «$name»' : 'вышел(шла) из гильдии «$name»');
  }

  Future<void> kickFromAlliance(String space) => _allyCall('ally_kick', {'space': space});

  Future<void> setAllyPerms(String ref, Set<AllyPerm> perms) =>
      _allyCall('ally_perms', {'target': ref, 'perms': [for (final p in perms) p.name]});

  Future<void> transferAlliance(String ref) => _allyCall('ally_transfer', {'target': ref});

  Future<void> allianceSettings({required String name, required String emblem, required String motto}) =>
      _allyCall('ally_settings', {'name': name, 'emblem': emblem, 'motto': motto});

  Future<void> announce(String text) => _allyCall('ally_announce', {'text': text});

  Future<void> saveAllyGoal({
    String? id,
    required String title,
    required String emoji,
    required int target,
    required String unit,
    String description = '',
    DateTime? deadline,
  }) =>
      _allyCall('ally_goal_save', {
        'goal': {
          'id': ?id,
          'title': title,
          'emoji': emoji,
          'target': target,
          'unit': unit,
          'description': description,
          'deadline': deadline?.millisecondsSinceEpoch,
        },
      });

  Future<void> deleteAllyGoal(String id) => _allyCall('ally_goal_delete', {'goalId': id});

  /// Внести вклад в цель гильдии. Герой получает опыт и монеты (см.
  /// [GameController.rewardGuildContribution]), вклад виден всей гильдии.
  Future<CompletionResult> contribute(AllyGoal goal, int amount) async {
    final me = game.activeHero;
    final r = await _allyCall('ally_contribute', {
      'goalId': goal.id,
      'amount': amount,
      'heroName': me?.name,
      'heroAvatar': me?.avatar,
    });
    return game.rewardGuildContribution(
      goalId: goal.id,
      title: goal.title,
      amount: amount,
      unit: goal.unit,
      completed: r['completed'] == true,
    );
  }
}
