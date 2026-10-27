import 'dart:convert';

import '../models/models.dart';

/// Ошибка чтения резервной копии — текст можно показать пользователю.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Прочитанная резервная копия: состояние и краткая сводка для подтверждения.
class BackupData {
  const BackupData({required this.state, this.exportedAt, this.appVersion = ''});

  final AppState state;
  final DateTime? exportedAt;
  final String appVersion;

  String get guildName => state.guildName;
  bool get solo => state.solo;
  GroupKind get groupKind => state.groupKind;
  int get heroCount => state.heroes.length;
  int get goalCount => state.goals.length;
  int get doneCount => state.goals.where((g) => g.done).length;
  int get reminderCount => state.reminders.length;
  int get moneyCount => state.money.length;
}

/// Резервная копия всех данных устройства в файл JSON (версия 0.6).
///
/// В файле — семья (клан), герои, цели, лента, лавка, бюджет, журнал опыта,
/// будильники, таймеры и навыки. PIN родителя — только хэш, как и на устройстве.
class Backup {
  const Backup._();

  static const app = 'rodquest';
  static const format = 1;
  static const appVersion = '0.9.0';
  static const fileExtension = 'json';

  /// Резервная копия не может быть больше — защита от случайного выбора
  /// огромного файла (фильма, архива).
  static const maxBytes = 20 * 1024 * 1024;

  static String encode(AppState state, DateTime now) => const JsonEncoder.withIndent(' ').convert({
        'app': app,
        'format': format,
        'appVersion': appVersion,
        'schema': AppState.schemaVersion,
        'exportedAt': now.toIso8601String(),
        'state': state.toJson(),
      });

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// «rodquest-2026-10-23-1915.json».
  static String fileName(DateTime now) =>
      'rodquest-${now.year}-${_two(now.month)}-${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}.$fileExtension';

  /// Прочитать резервную копию. Подходит и «голое» состояние без обёртки
  /// (например, сохранённое вручную из хранилища браузера).
  static BackupData decode(String text) {
    final trimmed = text.startsWith('\uFEFF') ? text.substring(1) : text;
    Object? raw;
    try {
      raw = jsonDecode(trimmed);
    } catch (_) {
      throw const BackupException('Это не файл резервной копии Родквеста.');
    }
    if (raw is! Map) throw const BackupException('Это не файл резервной копии Родквеста.');
    final root = Map<String, dynamic>.from(raw);

    Map<String, dynamic> stateJson;
    DateTime? exportedAt;
    var version = '';
    if (root.containsKey('state')) {
      if (root['app'] != app || root['state'] is! Map) {
        throw const BackupException('Это не файл резервной копии Родквеста.');
      }
      final fmt = (root['format'] as num?)?.toInt() ?? 1;
      if (fmt > format) {
        throw const BackupException('Копия сделана в более новой версии Родквеста — сначала обновите приложение.');
      }
      stateJson = Map<String, dynamic>.from(root['state'] as Map);
      exportedAt = DateTime.tryParse(root['exportedAt'] as String? ?? '');
      version = root['appVersion'] as String? ?? '';
    } else if (root.containsKey('heroes') && root.containsKey('goals')) {
      stateJson = root;
    } else {
      throw const BackupException('Это не файл резервной копии Родквеста.');
    }

    final schema = (stateJson['schema'] as num?)?.toInt() ?? 1;
    if (schema > AppState.schemaVersion) {
      throw const BackupException('Копия сделана в более новой версии Родквеста — сначала обновите приложение.');
    }
    final state = _parseState(stateJson);
    if (state.heroes.isEmpty) throw const BackupException('В копии нет ни одного героя — восстанавливать нечего.');
    return BackupData(state: state, exportedAt: exportedAt, appVersion: version);
  }

  static AppState _parseState(Map<String, dynamic> json) {
    try {
      return AppState.fromJson(json);
    } catch (_) {
      throw const BackupException('Файл повреждён: данные не читаются.');
    }
  }
}
