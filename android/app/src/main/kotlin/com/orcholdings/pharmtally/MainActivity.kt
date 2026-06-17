package com.orcholdings.pharmtally

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.content.PackageManagerCompat
import androidx.core.content.UnusedAppRestrictionsConstants
import com.syn.syndrive.AuthManager
import com.syn.syndrive.NewFileNotifier
import com.syn.syndrive.Prefs
import com.syn.syndrive.SyncEngine
import com.syn.syndrive.SyncScheduler
import com.syn.syndrive.SyndriveActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val channelName = "pharmtally/native"
    private var channel: MethodChannel? = null

    /** 메인 화면 새로고침 버튼이 부르는 즉시 동기화용 스코프. */
    private val syncScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** 알림 탭으로 콜드스타트된 경우, 그 날짜를 Flutter 가 가져갈 때까지 보관. */
    private var pendingTargetDate: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingTargetDate = intent?.getStringExtra(NewFileNotifier.EXTRA_TARGET_DATE)
    }

    override fun onDestroy() {
        syncScope.cancel()
        super.onDestroy()
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
                    // 앱 시작 시: SynDrive 가 설정돼 있으면 고속 동기화 재개 +
                    // 앱 휴면(미사용 시 자동 권한 삭제) 해제 안내.
                    "resumeFastSyncIfConfigured" -> {
                        SyncScheduler.apply(this)
                        promptDisableHibernationIfNeeded()
                        result.success(null)
                    }
                    // 콜드스타트가 새 매출 알림 탭으로 시작된 경우의 날짜
                    "getInitialTargetDate" -> {
                        result.success(pendingTargetDate)
                        pendingTargetDate = null
                    }
                    // 메인 화면 새로고침 버튼 → 즉시 1회 동기화.
                    "syncNow" -> {
                        syncScope.launch {
                            val map: Map<String, Any> = try {
                                val prefs = Prefs(applicationContext)
                                val auth = AuthManager(prefs)
                                if (!auth.isSignedIn) {
                                    mapOf("ok" to false, "msg" to "Microsoft 로그인이 필요합니다 (폴더 버튼에서 설정)")
                                } else {
                                    val summary = SyncEngine(applicationContext, prefs, auth).sync { }
                                    prefs.lastSyncInfo = "수동 — $summary"
                                    NewFileNotifier.notifyNewFiles(applicationContext, summary.newExcelFiles)
                                    mapOf("ok" to true, "msg" to summary.toString())
                                }
                            } catch (e: Exception) {
                                mapOf("ok" to false, "msg" to (e.message ?: "동기화 오류"))
                            }
                            withContext(Dispatchers.Main) { result.success(map) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * 앱을 한동안 안 열면 안드로이드(API 30+)가 "미사용 앱"으로 보고 권한을
     * 자동 삭제 + 휴면시켜 백그라운드 동기화가 끊긴다. 이 앱은 백그라운드로만
     * 도는 일이 많으므로, 제한이 켜져 있으면 해제 설정 화면을 한 번 띄워 안내한다.
     * (사용자가 처리하면 상태가 DISABLED 가 되어 다시 뜨지 않는다. 설치당 1회.)
     */
    private fun promptDisableHibernationIfNeeded() {
        if (Build.VERSION.SDK_INT < 30) return
        val sp = getSharedPreferences("pharmtally_native", MODE_PRIVATE)
        if (sp.getBoolean("hibernation_prompt_shown", false)) return
        try {
            val future = PackageManagerCompat.getUnusedAppRestrictionsStatus(this)
            future.addListener({
                try {
                    when (future.get()) {
                        UnusedAppRestrictionsConstants.API_30_BACKPORT,
                        UnusedAppRestrictionsConstants.API_30,
                        UnusedAppRestrictionsConstants.API_31 -> {
                            // 제한이 켜져 있음 → 해제 화면을 띄우고, 다시 안 뜨게 표시.
                            sp.edit().putBoolean("hibernation_prompt_shown", true).apply()
                            try {
                                startActivity(
                                    IntentCompat.createManageUnusedAppRestrictionsIntent(
                                        this, packageName
                                    )
                                )
                            } catch (e: Exception) {
                                // 설정 화면을 못 열면 무시.
                            }
                        }
                        else -> {
                            // DISABLED / 미지원 — 아무것도 안 함.
                        }
                    }
                } catch (e: Exception) {
                    // 무시.
                }
            }, ContextCompat.getMainExecutor(this))
        } catch (e: Exception) {
            // 무시.
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
