import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// Доступ к синхронизации из экранов. В тестах и сборках без облака её нет.
class CloudScope extends InheritedNotifier<SyncEngine> {
  const CloudScope({super.key, required SyncEngine cloud, required super.child}) : super(notifier: cloud);

  static SyncEngine? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()?.notifier;

  static SyncEngine? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CloudScope>()?.notifier;
}
