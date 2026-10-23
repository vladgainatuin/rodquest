import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Хранилище состояния. Сейчас — локально на устройстве; в версии 1.x
/// появится серверная реализация с синхронизацией семьи.
abstract class GameRepository {
  Future<AppState?> load();
  Future<void> save(AppState state);
  Future<void> clear();
}

class LocalGameRepository implements GameRepository {
  static const _key = 'rodquest_state_v1';

  @override
  Future<AppState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Повреждённые данные не должны ронять приложение.
      return null;
    }
  }

  @override
  Future<void> save(AppState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Хранилище в памяти — для тестов.
class MemoryGameRepository implements GameRepository {
  String? _raw;

  @override
  Future<AppState?> load() async =>
      _raw == null ? null : AppState.fromJson(jsonDecode(_raw!) as Map<String, dynamic>);

  @override
  Future<void> save(AppState state) async => _raw = jsonEncode(state.toJson());

  @override
  Future<void> clear() async => _raw = null;
}
