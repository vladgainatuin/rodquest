import 'dart:convert';
import 'dart:math';

import 'codec.dart';

/// Трёхстороннее слияние сущности: [base] — версия, от которой обе стороны
/// начали править, [local] — правки этого устройства, [remote] — с сервера.
/// null — сущности нет (удалена).
///
/// Правила:
/// * поменяла одна сторона — берём её версию;
/// * удаление сильнее правки (удалённую цель не воскрешаем);
/// * объекты сливаются по полям, вложенные — рекурсивно;
/// * у героя опыт, монеты, опыт характеристик и черт — счётчики: прибавки
///   с обоих устройств складываются (папа подтвердил задание, пока юнга
///   выполнял рутину на своём телефоне — опыт за оба);
/// * ступени достижений — берём большую;
/// * остальное при споре — версия этого устройства (её сделали позже).
class SyncMerge {
  const SyncMerge._();

  static String? entity(String key, String? base, String? local, String? remote) {
    if (local == base) return remote;
    if (remote == base) return local;
    if (local == null || remote == null) return null;
    final type = key.substring(0, max(0, key.indexOf('/')));
    // У героя одинаковые прибавки с двух устройств — это две разные прибавки,
    // поэтому совпадение версий ещё не значит «правка одна».
    if (remote == local && type != 'hero') return local;
    try {
      final b = base == null ? const <String, dynamic>{} : jsonDecode(base);
      final l = jsonDecode(local);
      final r = jsonDecode(remote);
      return SyncCodec.canon(_value(b, l, r, type == 'hero' ? const _HeroRules() : const _Rules(), const []));
    } catch (_) {
      return local;
    }
  }

  static Object? _value(Object? b, Object? l, Object? r, _Rules rules, List<String> path) {
    if (_eq(l, b)) return r;
    if (_eq(r, b)) return l;
    if (rules.isCounter(path) && (l is num?) && (r is num?) && (b is num?)) {
      final base = b ?? 0, dl = (l ?? 0) - base, dr = (r ?? 0) - base;
      final v = base + dl + dr;
      return max(0, v is int ? v : v.round());
    }
    if (rules.isMax(path) && l is num && r is num) return max(l, r);
    if (l is Map && r is Map) {
      final bm = b is Map ? b : const {};
      final out = <String, dynamic>{};
      for (final k in {...l.keys, ...r.keys}.map((e) => e.toString())) {
        final v = _value(bm[k], l[k], r[k], rules, [...path, k]);
        if (v != null || l.containsKey(k) || r.containsKey(k)) out[k] = v;
      }
      // Порядок полей как у локальной версии — чтобы JSON совпадал байт в байт.
      final ordered = <String, dynamic>{
        for (final k in l.keys) k.toString(): out[k.toString()],
        for (final k in out.keys) if (!l.containsKey(k)) k: out[k],
      };
      return ordered;
    }
    return l; // одинаковые или спорные — версия этого устройства
  }

  static bool _eq(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_eq(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

class _Rules {
  const _Rules();
  bool isCounter(List<String> path) => false;
  bool isMax(List<String> path) => false;
}

class _HeroRules extends _Rules {
  const _HeroRules();

  @override
  bool isCounter(List<String> path) =>
      (path.length == 1 && (path[0] == 'xp' || path[0] == 'coins')) ||
      (path.length == 2 && (path[0] == 'statXp' || path[0] == 'traitXp'));

  @override
  bool isMax(List<String> path) => path.length == 2 && path[0] == 'badges';
}
