import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repository.dart';
import 'services/push.dart';
import 'services/push_local.dart';
import 'state/game_controller.dart';
import 'sync/sync_engine.dart';

/// Адрес сервера синхронизации задаётся при сборке:
/// `flutter build apk --dart-define=RODQUEST_SERVER=https://functions.yandexcloud.net/ID_ФУНКЦИИ`
const serverUrl = String.fromEnvironment('RODQUEST_SERVER');

String _deviceLabel() {
  if (kIsWeb) {
    // В списке устройств гильдии видно, с какого телефона открыт сайт.
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone · браузер',
      TargetPlatform.android => 'Android · браузер',
      _ => 'Браузер',
    };
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Устройство',
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = GameController(
    LocalGameRepository(),
    // Звонок при закрытом приложении — Android, iOS, macOS. В браузере и на
    // Windows звонит само приложение, пока оно открыто.
    push: LocalPush.platformSupported ? LocalPush() : const NoPush(),
  );
  // v0.8: синхронизация семьи через облако.
  final cloud = SyncEngine(game: controller, defaultUrl: serverUrl, deviceLabel: _deviceLabel());
  runApp(RodquestApp(controller: controller, cloud: cloud));
  await cloud.init();
  await controller.load();
  cloud.start();
}
