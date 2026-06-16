package com.orcholdings.pharmtally

import android.content.Intent
import android.os.Bundle
import com.syn.syndrive.NewFileNotifier
import com.syn.syndrive.SyncScheduler
import com.syn.syndrive.SyndriveActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "pharmtally/native"
    private var channel: MethodChannel? = null

    /** 알림 탭으로 콜드스타트된 경우, 그 날짜를 Flutter 가 가져갈 때까지 보관. */
    private var pendingTargetDate: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingTargetDate = intent?.getStringExtra(NewFileNotifier.EXTRA_TARGET_DATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // 폴더 버튼 → SynDrive 설정 화면 열기
                    "openSyndriveSettings" -> {
                        startActivity(Intent(this, SyndriveActivity::class.java))
                        result.success(null)
                    }
                    // 앱 시작 시: SynDrive 가 설정돼 있으면 고속 동기화 재개
                    "resumeFastSyncIfConfigured" -> {
                        SyncScheduler.apply(this)
                        result.success(null)
                    }
                    // 콜드스타트가 새 매출 알림 탭으로 시작된 경우의 날짜
                    "getInitialTargetDate" -> {
                        result.success(pendingTargetDate)
                        pendingTargetDate = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** 앱이 떠 있는 동안 새 매출 알림을 탭한 경우 — 날짜를 Flutter 로 전달. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val date = intent.getStringExtra(NewFileNotifier.EXTRA_TARGET_DATE)
        if (date != null) {
            channel?.invokeMethod("onTargetDate", date)
        }
    }
}
