import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../logic/backup.dart';

/// Сохранение и выбор файла резервной копии (плагин file_picker).
///
/// В браузере файл скачивается, на телефоне и компьютере — системное окно
/// «Сохранить как» / «Открыть».
class BackupFiles {
  const BackupFiles._();

  /// Сохранить копию. Возвращает false, если пользователь отменил сохранение.
  static Future<bool> save(String fileName, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Сохранить резервную копию',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const [Backup.fileExtension],
    );
    // В браузере файл просто скачивается, и адреса нет.
    return kIsWeb || uri != null;
  }

  /// Выбрать файл копии и прочитать текст. null — выбор отменён.
  static Future<String?> pick() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Открыть резервную копию');
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > Backup.maxBytes) {
      throw const BackupException('Файл слишком большой для резервной копии Родквеста.');
    }
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const BackupException('Это не файл резервной копии Родквеста.');
    }
  }
}
