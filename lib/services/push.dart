import '../logic/push_rules.dart';

/// Разрешения на системные уведомления.
class PushAccess {
  const PushAccess({required this.supported, this.allowed = false, this.exact = true});

  /// Платформа умеет звонить при закрытом приложении (Android, iOS, macOS).
  final bool supported;

  /// Пользователь разрешил уведомления.
  final bool allowed;

  /// Android 12+: будильники звонят минута в минуту (иначе система может
  /// сдвинуть звонок на несколько минут ради экономии батареи).
  final bool exact;

  static const unsupported = PushAccess(supported: false);
}

/// Системные уведомления, которые звонят при закрытом приложении (версия 0.6).
///
/// Контроллер планирует их, когда приложение уходит в фон, и снимает, когда
/// оно снова открыто — тогда звонит само приложение.
abstract class PushScheduler {
  const PushScheduler();

  /// Заменить все запланированные уведомления на [pushes].
  Future<void> schedule(List<PlannedPush> pushes);

  /// Снять все запланированные (приложение снова на экране).
  Future<void> clear();

  Future<PushAccess> access();

  /// Попросить разрешение на уведомления. [exact] — заодно на точные
  /// будильники (Android откроет экран настроек).
  Future<PushAccess> request({bool exact = false});
}

/// Ничего не делает: браузер, Windows и тесты.
class NoPush extends PushScheduler {
  const NoPush();

  @override
  Future<void> schedule(List<PlannedPush> pushes) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<PushAccess> access() async => PushAccess.unsupported;

  @override
  Future<PushAccess> request({bool exact = false}) async => PushAccess.unsupported;
}

/// Запоминает расписание — для тестов.
class FakePush extends PushScheduler {
  FakePush();

  List<PlannedPush> scheduled = [];
  int clears = 0;
  bool allowed = false;

  @override
  Future<void> schedule(List<PlannedPush> pushes) async => scheduled = List.of(pushes);

  @override
  Future<void> clear() async {
    clears++;
    scheduled = [];
  }

  @override
  Future<PushAccess> access() async => PushAccess(supported: true, allowed: allowed);

  @override
  Future<PushAccess> request({bool exact = false}) async {
    allowed = true;
    return access();
  }
}
