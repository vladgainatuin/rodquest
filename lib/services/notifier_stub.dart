import 'package:flutter/services.dart';

// Мобильные и настольные платформы: системный звук и вибрация,
// пока приложение открыто. Окно будильника показывает само приложение.

bool get supported => false;

String get permission => 'unsupported';

Future<bool> requestPermission() async => false;

void show(String title, String body) {}

void beep({bool alarm = false}) {
  SystemSound.play(SystemSoundType.alert).then((_) {}, onError: (Object _) {});
  if (alarm) {
    HapticFeedback.vibrate().then((_) {}, onError: (Object _) {});
  }
}
