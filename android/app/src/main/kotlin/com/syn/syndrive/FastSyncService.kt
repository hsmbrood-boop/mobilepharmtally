package com.syn.syndrive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.orcholdings.pharmtally.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 고속 동기화 모드 — WorkManager의 최소 15분 제한을 우회하는 상시 실행 서비스.
 * 알림 하나가 떠 있는 대신 1~10분 간격 동기화가 가능하다.
 *
 * 동기화 직후 새로 받은 엑셀이 있으면 [NewFileNotifier] 로 "새 매출 데이터 도착"
 * 알림을 띄운다(PharmTally 의 별도 폴더 감시 서비스를 대체).
 */
class FastSyncService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var loop: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        ServiceCompat.startForeground(
            this, NOTIF_ID, buildNotification("동기화 대기 중"),
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        )
        if (loop?.isActive != true) loop = scope.launch { runLoop() }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun runLoop() {
        val prefs = Prefs(applicationContext)
        val auth = AuthManager(prefs)
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager

        // 주기 사이 delay 동안 CPU 가 깊은 절전(도즈)에 들면 코루틴 타이머가
        // 밀려 2분 주기가 수십 분~1시간씩 늘어진다(배터리 최적화 제외만으론
        // 못 막음 — delay 는 기기를 깨우지 않음). 서비스가 도는 내내 부분
        // wakelock 을 잡아 CPU 를 깨어 있게 해 주기를 정확히 지킨다.
        // (고속 모드의 트레이드오프 — 배터리를 더 쓰는 대신 거의 실시간.)
        val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "syndrive:fastsync")
        wl.setReferenceCounted(false)
        wl.acquire()
        try {
            while (true) {
                if (auth.isSignedIn) {
                    try {
                        notify("동기화 중…")
                        val summary = SyncEngine(applicationContext, prefs, auth).sync { }
                        prefs.lastSyncInfo = "${now()} 자동 — $summary"
                        notify("마지막: ${prefs.lastSyncInfo}")
                        // 새로 받은 엑셀이 있으면 PharmTally 새 매출 알림을 띄운다.
                        NewFileNotifier.notifyNewFiles(applicationContext, summary.newExcelFiles)
                    } catch (e: Exception) {
                        prefs.lastSyncInfo = "${now()} 자동 — 오류: ${e.message}"
                        notify("오류: ${e.message?.take(50)}")
                    }
                }
                delay(prefs.intervalMinutes.coerceAtLeast(1) * 60_000L)
            }
        } finally {
            if (wl.isHeld) wl.release()
        }
    }

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "동기화 상태", NotificationManager.IMPORTANCE_LOW)
        )
    }

    private fun buildNotification(text: String): Notification {
        // 알림을 탭하면 PharmTally 본 화면을 연다.
        val launch = Intent().apply {
            setClassName(packageName, "com.orcholdings.pharmtally.MainActivity")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("PharmTally 동기화")
            .setContentText(text)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun notify(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun now(): String = SimpleDateFormat("MM-dd HH:mm", Locale.KOREA).format(Date())

    companion object {
        private const val NOTIF_ID = 1
        private const val CHANNEL_ID = "sync"

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, FastSyncService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FastSyncService::class.java))
        }
    }
}
