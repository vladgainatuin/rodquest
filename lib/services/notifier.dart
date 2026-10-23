import 'notifier_stub.dart' if (dart.library.js_interop) 'notifier_web.dart' as impl;

/// Звук и системные уведомления для будильников, напоминаний и таймера.
///
/// В браузере — уведомления браузера (даже если вкладка в фоне) и звонок
/// через Web Audio. В приложении — системный звук и вибрация, пока
/// приложение открыто. Звонок при закрытом приложении — следующий шаг
/// (push-уведомления, версия 0.6).
class Notifier {
  const Notifier._();

  /// Можно ли показывать системные уведомления на этой платформе.
  static bool get supported => _safe(() => impl.supported, false);

  /// 'granted', 'denied', 'default' или 'unsupported'.
  static String get permission => _safe(() => impl.permission, 'unsupported');

  static Future<bool> requestPermission() async {
    try {
      return await impl.requestPermission();
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body) {
    try {
      impl.show(title, body);
    } catch (_) {
      // Уведомление — приятное дополнение, приложение работает и без него.
    }
  }

  /// Короткий сигнал; [alarm] — громкий тройной звонок будильника.
  static void beep({bool alarm = false}) {
    try {
      impl.beep(alarm: alarm);
    } catch (_) {
      // Без звука окно будильника всё равно появится.
    }
  }

  static T _safe<T>(T Function() f, T fallback) {
    try {
      return f();
    } catch (_) {
      return fallback;
    }
  }
}
