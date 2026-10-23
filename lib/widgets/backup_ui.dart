import 'package:flutter/material.dart';

import '../logic/backup.dart';
import '../services/backup_files.dart';
import '../theme.dart';
import 'common.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _dateTime(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Сохранить все данные устройства в файл.
Future<void> exportBackupFlow(BuildContext context) async {
  final game = GameScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final saved = await BackupFiles.save(game.backupFileName, game.exportBackup());
    if (!saved) return;
    messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 6),
      content: Text('💾 Резервная копия сохранена. Храните файл в надёжном месте — в нём бюджет семьи.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('⚠️ Не удалось сохранить файл: $e')));
  }
}

/// Выбрать файл копии, показать, что в нём, и после подтверждения восстановить.
Future<void> importBackupFlow(BuildContext context) async {
  final game = GameScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final data = await _pickBackup(messenger);
  if (data == null || !context.mounted) return;
  final fresh = game.needsOnboarding;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Восстановить из копии?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.solo ? '🧭 Личный путь' : '🛡 ${data.guildName.isEmpty ? 'Гильдия' : data.guildName}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Героев: ${data.heroCount} · целей: ${data.goalCount} (выполнено ${data.doneCount})'),
          if (data.reminderCount > 0 || data.moneyCount > 0)
            Text('Будильников: ${data.reminderCount} · операций бюджета: ${data.moneyCount}'),
          if (data.exportedAt != null) Text('Копия от ${_dateTime(data.exportedAt!)}'),
          if (!fresh) ...[
            const SizedBox(height: 12),
            Text('Все текущие данные на этом устройстве будут заменены копией.',
                style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Восстановить')),
      ],
    ),
  );
  if (ok != true) return;
  final done = await game.restoreBackup(data);
  // После восстановления тема могла смениться — экран перестроен заново.
  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(
    content: Text(done ? '📂 Данные восстановлены из копии' : '⚠️ Восстановить данные может только глава гильдии'),
  ));
}

Future<BackupData?> _pickBackup(ScaffoldMessengerState messenger) async {
  try {
    final text = await BackupFiles.pick();
    if (text == null) return null;
    return Backup.decode(text);
  } on BackupException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('⚠️ ${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('⚠️ Не удалось открыть файл: $e')));
  }
  return null;
}
