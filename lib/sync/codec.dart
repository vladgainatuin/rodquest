import 'dart:convert';

import '../models/models.dart';

/// Версия 0.8: состояние семьи (клана) как набор сущностей «ключ → JSON».
///
/// Каждая цель, герой, запись ленты… — отдельная сущность. Так правки двух
/// членов семьи на разных телефонах не затирают друг друга целиком:
/// сервер сравнивает и сливает сущности по отдельности.
///
/// Только для этого устройства (не синхронизируются): активный герой и время
/// последней проверки будильников.
class SyncCodec {
  const SyncCodec._();

  static const all = 'all';
  static const adults = 'adults';
  static String private(String heroId) => 'private:$heroId';

  /// Видимость сущности: кто её получит с сервера.
  /// Бюджет и PIN — только взрослым, личные цели — только устройствам владельца.
  static String scopeOf(String key, String data) {
    final type = key.substring(0, key.indexOf('/'));
    switch (type) {
      case 'cat' || 'money' || 'pot' || 'pin':
        return adults;
      case 'goal':
        final j = jsonDecode(data) as Map<String, dynamic>;
        if (j['isPrivate'] == true && j['ownerId'] is String && (j['ownerId'] as String).isNotEmpty) {
          return private(j['ownerId'] as String);
        }
        return all;
      default:
        return all;
    }
  }

  /// Безопасный ключ: только латиница, цифры и `_-.:|`.
  static String _safe(String id) {
    if (RegExp(r'^[A-Za-z0-9_\-.:|]{1,160}$').hasMatch(id)) return id;
    final b = StringBuffer();
    for (final c in id.runes) {
      final ch = String.fromCharCode(c);
      b.write(RegExp(r'[A-Za-z0-9\-.:|]').hasMatch(ch) ? ch : '_${c.toRadixString(16)}');
    }
    final s = b.toString();
    return s.length <= 160 ? s : '${s.substring(0, 140)}_${hash(s)}';
  }

  /// Два 32-битных FNV-1a с разными началами. Умножение на 16777619 разложено
  /// как h·403 + h·2²⁴ — без переполнения, поэтому на вебе и в приложении
  /// ключ получается одинаковым.
  static String hash(String s) {
    int mul(int h) => (h * 403 + ((h << 24) & 0xffffffff)) & 0xffffffff;
    var a = 0x811c9dc5, b = 0x050c5d1f;
    for (final c in s.codeUnits) {
      a = mul((a ^ c) & 0xffffffff);
      b = mul(((b ^ c) + 0x9e37) & 0xffffffff);
    }
    return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
  }

  /// JSON, одинаковый на телефоне и в браузере: целые дробные числа (5.0)
  /// пишутся как целые (5) — в браузере jsonEncode иначе не умеет, и без этого
  /// телефон и браузер бесконечно «исправляли» бы друг друга.
  static String canon(Object? json) => jsonEncode(_norm(json));

  static Object? _norm(Object? v) {
    if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9007199254740992) return v.toInt();
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _norm(e.value)};
    if (v is List) return [for (final x in v) _norm(x)];
    return v;
  }

  static String recordKey(XpRecord r) =>
      'xp/${hash('${r.heroId}|${r.goalId}|${r.kind.name}|${r.at.toIso8601String()}')}';

  /// Состояние → сущности (ключ → JSON-строка).
  static Map<String, String> encode(AppState s) {
    final out = <String, String>{};
    void put(String type, String id, Map<String, dynamic> json) => out['$type/${_safe(id)}'] = canon(json);

    // v0.9: «клан» пишем, только если выбран — у семей сущность не меняется.
    put('meta', 'guild', {
      'guildName': s.guildName,
      'solo': s.solo,
      if (s.groupKind == GroupKind.clan) 'kind': 'clan',
    });
    if (s.parentPinHash != null) put('pin', 'parent', {'h': s.parentPinHash, 's': s.parentPinSalt});
    for (final x in s.heroes) {
      put('hero', x.id, x.toJson());
    }
    for (final x in s.goals) {
      put('goal', x.id, x.toJson());
    }
    for (final x in s.feed) {
      put('feed', x.id, x.toJson());
    }
    for (final x in s.rewards) {
      put('reward', x.id, x.toJson());
    }
    for (final x in s.claims) {
      put('claim', x.id, x.toJson());
    }
    for (final x in s.categories) {
      put('cat', x.id, x.toJson());
    }
    for (final x in s.money) {
      put('money', x.id, x.toJson());
    }
    for (final x in s.pots) {
      put('pot', x.id, x.toJson());
    }
    for (final x in s.records) {
      final j = x.toJson();
      // Черты — в порядке перечисления, как после чтения из JSON: иначе после
      // перезапуска та же запись выглядела бы изменённой.
      if (j['tr'] case final Map tr) {
        j['tr'] = {for (final t in HeroTrait.values) if (tr.containsKey(t.name)) t.name: tr[t.name]};
      }
      out[recordKey(x)] = canon(j);
    }
    for (final x in s.reminders) {
      put('rem', x.id, x.toJson());
    }
    for (final x in s.timers) {
      put('timer', x.id, x.toJson());
    }
    for (final x in s.sessions) {
      put('sess', x.id, x.toJson());
    }
    for (final x in s.skills) {
      put('skill', x.id, x.toJson());
    }
    for (final x in s.skillEntries) {
      put('skent', x.id, x.toJson());
    }
    return out;
  }

  /// Сущности → состояние. Порядок элементов берём из [local] (чтобы списки
  /// на экране не прыгали), новые добавляем в конец; лента — новые сверху,
  /// журнал опыта — по времени. Поля устройства тоже берутся из [local].
  static AppState decode(Map<String, String> e, AppState local) {
    final byType = <String, Map<String, Map<String, dynamic>>>{};
    for (final entry in e.entries) {
      final i = entry.key.indexOf('/');
      if (i <= 0) continue;
      try {
        final j = jsonDecode(entry.value);
        if (j is! Map) continue;
        (byType[entry.key.substring(0, i)] ??= {})[entry.key] = Map<String, dynamic>.from(j);
      } catch (_) {
        // Испорченная сущность не должна ронять приложение.
      }
    }

    List<T> list<T>(String type, List<T> old, String Function(T) idOf, T Function(Map<String, dynamic>) from) {
      final items = byType[type] ?? const {};
      final byId = <String, Map<String, dynamic>>{
        for (final j in items.values)
          if (j['id'] is String) j['id'] as String: j,
      };
      final out = <T>[];
      final used = <String>{};
      for (final o in old) {
        final id = idOf(o);
        final j = byId[id];
        if (j == null || used.contains(id)) continue;
        used.add(id);
        try {
          out.add(from(j));
        } catch (_) {}
      }
      final rest = byId.keys.where((id) => !used.contains(id)).toList()..sort();
      for (final id in rest) {
        try {
          out.add(from(byId[id]!));
        } catch (_) {}
      }
      return out;
    }

    final meta = (byType['meta'] ?? const {})['meta/guild'];
    final pin = (byType['pin'] ?? const {})['pin/parent'];
    final records = <XpRecord>[
      for (final j in (byType['xp'] ?? const {}).values)
        if (_tryRecord(j) case final XpRecord r) r,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final feed = list<FeedEvent>('feed', local.feed, (x) => x.id, FeedEvent.fromJson)
      ..sort((a, b) => b.at.compareTo(a.at));

    return AppState(
      guildName: meta?['guildName'] as String? ?? local.guildName,
      solo: meta?['solo'] as bool? ?? false,
      groupKind: GroupKindInfo.fromName(meta?['kind']),
      parentPinHash: pin?['h'] as String?,
      parentPinSalt: pin?['s'] as String?,
      heroes: list('hero', local.heroes, (x) => x.id, HeroProfile.fromJson),
      goals: list('goal', local.goals, (x) => x.id, Goal.fromJson),
      feed: feed,
      rewards: list('reward', local.rewards, (x) => x.id, Reward.fromJson),
      claims: list('claim', local.claims, (x) => x.id, RewardClaim.fromJson),
      categories: list('cat', local.categories, (x) => x.id, BudgetCategory.fromJson),
      money: list('money', local.money, (x) => x.id, MoneyEntry.fromJson),
      pots: list('pot', local.pots, (x) => x.id, SavingsPot.fromJson),
      records: records,
      reminders: list('rem', local.reminders, (x) => x.id, Reminder.fromJson),
      timers: list('timer', local.timers, (x) => x.id, ActiveTimer.fromJson),
      sessions: list('sess', local.sessions, (x) => x.id, FocusSession.fromJson),
      skills: list('skill', local.skills, (x) => x.id, Skill.fromJson),
      skillEntries: list('skent', local.skillEntries, (x) => x.id, SkillEntry.fromJson),
      activeHeroId: local.activeHeroId,
      remindersCheckedAt: local.remindersCheckedAt,
    );
  }

  static XpRecord? _tryRecord(Map<String, dynamic> j) {
    try {
      return XpRecord.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
