import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'folder_watcher.dart';
import 'notifications.dart';

/// "거의 실시간" 폴더 감시를 위한 포그라운드 서비스.
///
/// WorkManager 는 최소 주기가 15분이고 도즈(절전)로 1~2시간까지 밀린다.
/// 그래서 더 빠른(기본 1분) 감지가 필요할 때는 상시 알림이 떠 있는
/// 포그라운드 서비스에서 짧은 주기로 폴더를 스캔한다.
///
/// 실제 스캔/알림 로직은 [pharmTallyScanFolderAndNotify] 를 그대로 재사용하며,
/// 중복 알림은 그쪽의 seen-files 로 방지된다(WorkManager 백스톱과 공존 가능).

/// 감시 주기(ms). 1분. OneDrive 폴더를 1분마다 훑어 새 .xlsx 를 찾는다.
const int _kWatchIntervalMs = 60 * 1000;

/// 서비스 알림이 뜨는 별도 채널(상시 "감시 중" 알림). 새 파일 알림 채널과
/// 다르게 두어, 사용자가 시스템 설정에서 따로 끄고 켤 수 있다.
const String _kServiceChannelId = 'pharm_tally_folder_watch_service';
const String _kServiceChannelName = '폴더 감시 (상시)';

/// 포그라운드 서비스의 작업 진입점. **top-level + `vm:entry-point`** 여야
/// release 모드에서 백그라운드 isolate 로 살아남는다.
@pragma('vm:entry-point')
void pharmTallyForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_FolderWatchTaskHandler());
}

class _FolderWatchTaskHandler extends TaskHandler {
  bool _scanning = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 백그라운드 isolate 는 알림 플러그인을 새로 초기화해야 한다.
    await PharmTallyNotifications.initialize();
    // 서비스가 켜지자마자 한 번 즉시 스캔(다음 주기까지 기다리지 않게).
    await _runScan();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // onRepeatEvent 는 동기 콜백 — fire-and-forget 으로 비동기 스캔을 돌린다.
    _runScan();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // 정리할 리소스 없음.
  }

  /// 스캔이 1분보다 오래 걸리는 드문 경우에 겹쳐 도는 것을 막는다.
  Future<void> _runScan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      await pharmTallyScanFolderAndNotify();
    } catch (e, st) {
      debugPrint('[folder_watch_service] scan error: $e\n$st');
    } finally {
      _scanning = false;
    }
  }
}

/// 앱 시작 시 한 번 호출. 서비스 옵션/알림 채널을 초기화한다(아직 시작은 안 함).
void initFolderWatchService() {
  if (kIsWeb || !Platform.isAndroid) return;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _kServiceChannelId,
      channelName: _kServiceChannelName,
      channelDescription: '새 매출 엑셀이 도착했는지 폴더를 주기적으로 확인합니다.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(_kWatchIntervalMs),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// 포그라운드 서비스를 시작한다. 이미 돌고 있으면 아무것도 안 함.
///
/// 필요한 권한(알림 권한 + 배터리 최적화 제외)을 먼저 요청한다.
Future<void> startFolderWatchService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    // Android 13+ 알림 권한 — 포그라운드 서비스 상시 알림에도 필요.
    final notiPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notiPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    // 배터리 최적화 제외 — 도즈에서 서비스가 잠드는 것을 줄인다.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId: 451,
      notificationTitle: 'PharmTally 폴더 감시 중',
      notificationText: '새 매출 엑셀이 도착하면 알려드립니다.',
      callback: pharmTallyForegroundCallback,
    );
  } catch (e, st) {
    debugPrint('[folder_watch_service] start failed: $e\n$st');
  }
}

/// 포그라운드 서비스를 중지한다(상시 알림도 사라짐).
Future<void> stopFolderWatchService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  } catch (e, st) {
    debugPrint('[folder_watch_service] stop failed: $e\n$st');
  }
}
