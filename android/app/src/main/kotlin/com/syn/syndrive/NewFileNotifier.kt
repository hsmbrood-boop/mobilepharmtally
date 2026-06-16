package com.syn.syndrive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.orcholdings.pharmtally.R

/**
 * 동기화로 새 엑셀이 들어왔을 때 PharmTally "새 매출 데이터 도착" 알림을 띄운다.
 *
 * 통합 전에는 Flutter 쪽 폴더 감시 서비스가 이 알림을 보냈지만, 이제 동기화를
 * 직접 수행하는 네이티브 동기화 엔진이 "방금 받은 파일"을 알고 있으므로 여기서
 * 바로 알림을 띄운다(폴더를 다시 스캔할 필요 없음). 알림을 탭하면 파일명에서
 * 뽑은 날짜를 인텐트 extra 로 실어 PharmTally(MainActivity)를 열고, Flutter 가
 * 그 날짜로 자동 이동한다.
 */
object NewFileNotifier {

    /** Flutter 쪽이 쓰던 채널과 같은 id — 사용자의 알림 설정이 그대로 이어진다. */
    private const val CHANNEL_ID = "pharm_tally_new_excel"
    private const val CHANNEL_NAME = "새 매출 데이터 알림"

    /** MainActivity 가 읽는 인텐트 extra 키 (YYYY-MM-DD). */
    const val EXTRA_TARGET_DATE = "pharmtally_target_date"

    private val isoDateRegex = Regex("""^(\d{4})-(\d{2})-(\d{2})""")

    fun notifyNewFiles(context: Context, fileNames: List<String>) {
        if (fileNames.isEmpty()) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH)
        )

        // 한 번에 여러 개면 5개까지 개별, 그 이상은 요약 1개.
        val maxIndividual = 5
        if (fileNames.size <= maxIndividual) {
            for (name in fileNames) {
                post(context, nm, name.hashCode(), "새 매출 데이터 도착", "$name — 탭해서 열기", extractIsoDate(name))
            }
        } else {
            val latest = fileNames.last()
            post(
                context, nm, latest.hashCode(),
                "새 매출 데이터 도착",
                "${fileNames.size}개 파일이 새로 도착했습니다 (최신: $latest)",
                extractIsoDate(latest),
            )
        }
    }

    private fun post(
        context: Context,
        nm: NotificationManager,
        id: Int,
        title: String,
        text: String,
        isoDate: String?,
    ) {
        val intent = Intent().apply {
            setClassName(context.packageName, "com.orcholdings.pharmtally.MainActivity")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            if (isoDate != null) putExtra(EXTRA_TARGET_DATE, isoDate)
        }
        val pi = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notif = android.app.Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        nm.notify(id and 0x7fffffff, notif)
    }

    /** `2026-05-13 (수).xlsx` → `2026-05-13`. 매칭 안 되면 null. */
    private fun extractIsoDate(fileName: String): String? {
        val m = isoDateRegex.find(fileName) ?: return null
        return "${m.groupValues[1]}-${m.groupValues[2]}-${m.groupValues[3]}"
    }
}
