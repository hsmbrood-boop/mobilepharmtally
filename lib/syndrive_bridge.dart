import 'package:flutter/services.dart';

import 'notifications.dart';

/// PharmTally(Flutter) ↔ 임베드된 SynDrive(네이티브 안드로이드) 사이의 다리.
///
/// - 폴더 버튼 → [openSettings] 로 SynDrive 설정 화면(SyndriveActivity)을 연다.
/// - 앱 시작 시 [resumeFastSyncIfConfigured] 로 고속 동기화를 재개한다.
/// - 동기화로 새 엑셀이 도착해 알림을 탭하면, 네이티브가 그 날짜를 보내오고
///   ([initialize] 의 `onTargetDate`), PharmTally 가 해당 날짜로 자동 이동한다.
///
/// 안드로이드 외 플랫폼에서는 채널이 없어 `MissingPluginException` 이 나므로
/// 모든 호출을 try/catch 로 감싼다(데스크톱/웹에서는 조용히 no-op).
class SyndriveBridge {
  SyndriveBridge._();

  static const MethodChannel _channel = MethodChannel('pharmtally/native');

  /// 앱 시작 시 한 번. 네이티브가 보내는 `onTargetDate` 콜백을 연결한다.
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTargetDate') {
        final date = call.arguments as String?;
        if (date != null && date.isNotEmpty) {
          PharmTallyNotifications.pendingTargetDate.value = date;
        }
      }
      return null;
    });
  }

  /// 폴더 버튼 → SynDrive(원드라이브 동기화) 설정 화면 열기.
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSyndriveSettings');
    } catch (_) {
      // 안드로이드가 아니거나 채널 미연결 — 무시.
    }
  }

  /// 메인 화면 새로고침 버튼 → 즉시 1회 동기화. 결과는 {ok, msg}.
  /// 안드로이드가 아니거나 실패하면 {ok:false, msg:...} 를 돌려준다.
  static Future<Map<String, dynamic>> syncNow() async {
    try {
      final r = await _channel.invokeMethod('syncNow');
      if (r is Map) {
        return {
          'ok': r['ok'] == true,
          'msg': r['msg']?.toString() ?? '',
        };
      }
      return {'ok': false, 'msg': '알 수 없는 응답'};
    } catch (e) {
      return {'ok': false, 'msg': '$e'};
    }
  }

  /// SynDrive 가 이미 설정돼 있으면 고속 동기화 서비스를 재개.
  static Future<void> resumeFastSyncIfConfigured() async {
    try {
      await _channel.invokeMethod('resumeFastSyncIfConfigured');
    } catch (_) {
      // 무시.
    }
  }

  /// 콜드스타트가 새 매출 알림 탭으로 시작됐다면 그 날짜(YYYY-MM-DD)를 돌려준다.
  static Future<String?> getInitialTargetDate() async {
    try {
      return await _channel.invokeMethod<String>('getInitialTargetDate');
    } catch (_) {
      return null;
    }
  }
}
