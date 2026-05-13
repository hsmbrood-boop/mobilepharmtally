import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// PharmTally 의 로컬 알림 (Android/iOS) 진입점.
///
/// - [initialize] 는 앱 시작 시(또는 백그라운드 isolate 시작 시) 한 번 호출.
/// - [notifyNewExcel] 은 폴더 감시 작업이 새 엑셀을 찾았을 때 호출.
/// - 알림을 탭해서 앱이 켜진 경우, payload(`YYYY-MM-DD`) 가
///   [pendingTargetDate] 에 실려서 앱이 그 날짜로 자동 이동하도록 한다.
class PharmTallyNotifications {
  PharmTallyNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 알림 채널 식별자/이름. 같은 채널 이름은 사용자가 시스템 설정에서
  /// 한 번에 켜고/끄게 보인다.
  static const String _channelId = 'pharm_tally_new_excel';
  static const String _channelName = '새 매출 데이터 알림';
  static const String _channelDesc =
      'OneDrive 동기화 폴더에 새 엑셀 파일이 도착했을 때 알림합니다.';

  /// 알림을 탭하면 그 알림 payload(=ISO 날짜 문자열)가 여기에 들어온다.
  /// `SalesScreen` 이 이 값을 watch 해서 자동으로 그 날짜로 이동.
  static final ValueNotifier<String?> pendingTargetDate =
      ValueNotifier<String?>(null);

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          pendingTargetDate.value = payload;
        }
      },
    );

    // Android 8.0+ 채널 사전 생성 (앱이 처음 알림 보내기 전에 미리 등록).
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Android 13+ 알림 권한, iOS 알림 권한을 요청. 이미 허용돼 있으면 무해.
  static Future<void> requestRuntimePermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// 앱이 알림 탭으로 launch 된 경우, 그 payload 를 한 번만 꺼내준다.
  /// cold start 시 `main()` 직후에 호출해서 첫 화면에 반영하기 위함.
  static Future<String?> consumeLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null) return null;
    if (!details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  /// 새 엑셀 파일이 감지됐을 때 호출.
  ///
  /// [payloadIsoDate] 는 알림 탭 시 앱이 점프할 날짜(`YYYY-MM-DD`). 파일명에서
  /// 추출이 안 되면 null 로 넘기면 된다.
  static Future<void> notifyNewExcel({
    required String fileName,
    String? payloadIsoDate,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'PharmTally',
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    // 알림 id 는 파일명 해시로 고정 → 같은 파일이 두 번 감지돼도 알림이
    // 쌓이지 않고 갱신만 된다.
    final id = fileName.hashCode & 0x7fffffff;
    await _plugin.show(
      id,
      '새 매출 데이터 도착',
      '$fileName — 탭해서 PharmTally 에서 열기',
      details,
      payload: payloadIsoDate,
    );
  }
}
