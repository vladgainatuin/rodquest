import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/push_rules.dart';
import 'push.dart';

/// Системные уведомления Android, iOS и macOS (плагин flutter_local_notifications).
///
/// Время передаётся в UTC: так не нужна база часовых поясов. Повторяющиеся
/// звонки (каждый день, по дням недели) идут по UTC — в России перехода на
/// летнее время нет, а при каждом сворачивании приложения расписание
/// пересчитывается заново.
class LocalPush extends PushScheduler {
  LocalPush();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  /// Android flag FLAG_INSISTENT: звук повторяется, пока уведомление не тронут.
  static const _insistent = 4;

  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _androidImpl =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _init() => _ready ??= _doInit();

  Future<bool> _doInit() async {
    if (!platformSupported) return false;
    try {
      // Разрешение спрашиваем не при запуске, а по кнопке или при первом будильнике.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rodquest'),
          iOS: darwin,
          macOS: darwin,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Родквест: уведомления недоступны: $e');
      return false;
    }
  }

  NotificationDetails _details(PushKind kind) {
    const darwin = DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBanner: true);
    final android = switch (kind) {
      PushKind.alarm => AndroidNotificationDetails(
          'rq_alarm',
          'Будильники',
          channelDescription: 'Звонок будильника, даже если Родквест закрыт',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          visibility: NotificationVisibility.public,
          additionalFlags: Int32List.fromList(const [_insistent]),
          timeoutAfter: PushRules.alarmRingFor.inMilliseconds,
        ),
      PushKind.timer => const AndroidNotificationDetails(
          'rq_timer',
          'Таймеры',
          channelDescription: 'Время таймера «Успеть за время» вышло',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      PushKind.reminder => const AndroidNotificationDetails(
          'rq_reminder',
          'Напоминания',
          channelDescription: 'Напоминания о делах и рутине',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      PushKind.deadline => const AndroidNotificationDetails(
          'rq_deadline',
          'Сроки целей',
          channelDescription: 'Утром в день срока цели',
          category: AndroidNotificationCategory.reminder,
        ),
    };
    return NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  static DateTimeComponents? _components(PushRepeat r) => switch (r) {
        PushRepeat.none => null,
        PushRepeat.daily => DateTimeComponents.time,
        PushRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
      };

  @override
  Future<void> schedule(List<PlannedPush> pushes) async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final exact = !_android || (await _androidImpl?.canScheduleExactNotifications() ?? true);
      for (final p in pushes) {
        try {
          await _plugin.zonedSchedule(
            id: p.id,
            title: p.title,
            body: p.body,
            payload: p.payload,
            scheduledDate: tz.TZDateTime.from(p.at, tz.UTC),
            notificationDetails: _details(p.kind),
            androidScheduleMode: !exact
                ? AndroidScheduleMode.inexactAllowWhileIdle
                : p.kind == PushKind.alarm
                    ? AndroidScheduleMode.alarmClock
                    : AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: _components(p.repeat),
          );
        } catch (e) {
          debugPrint('Родквест: не удалось запланировать «${p.title}»: $e');
        }
      }
    } catch (e) {
      debugPrint('Родквест: ошибка расписания уведомлений: $e');
    }
  }

  @override
  Future<void> clear() async {
    if (!await _init()) return;
    try {
      // Снимаем и запланированные, и уже показанные: звенящий в шторке будильник
      // замолкает, а приложение само покажет, что прозвенело.
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Родквест: не удалось снять уведомления: $e');
    }
  }

  @override
  Future<PushAccess> access() async {
    if (!await _init()) return PushAccess.unsupported;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final impl = _androidImpl;
          return PushAccess(
            supported: true,
            allowed: await impl?.areNotificationsEnabled() ?? false,
            exact: await impl?.canScheduleExactNotifications() ?? true,
          );
        case TargetPlatform.iOS:
          final ios = await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions();
          return PushAccess(supported: true, allowed: ios?.isEnabled ?? false);
        case TargetPlatform.macOS:
          final mac = await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions();
          return PushAccess(supported: true, allowed: mac?.isEnabled ?? false);
        default:
          return PushAccess.unsupported;
      }
    } catch (_) {
      return const PushAccess(supported: true);
    }
  }

  @override
  Future<PushAccess> request({bool exact = false}) async {
    if (!await _init()) return PushAccess.unsupported;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final impl = _androidImpl;
          await impl?.requestNotificationsPermission();
          if (exact && !(await impl?.canScheduleExactNotifications() ?? true)) {
            await impl?.requestExactAlarmsPermission();
          }
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true);
        case TargetPlatform.macOS:
          await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true);
        default:
          break;
      }
    } catch (e) {
      debugPrint('Родквест: не удалось запросить разрешение: $e');
    }
    return access();
  }
}
