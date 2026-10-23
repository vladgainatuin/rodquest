import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repository.dart';
import 'services/push.dart';
import 'services/push_local.dart';
import 'state/game_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = GameController(
    LocalGameRepository(),
    // Звонок при закрытом приложении — Android, iOS, macOS. В браузере и на
    // Windows звонит само приложение, пока оно открыто.
    push: LocalPush.platformSupported ? LocalPush() : const NoPush(),
  )..load();
  runApp(RodquestApp(controller: controller));
}
