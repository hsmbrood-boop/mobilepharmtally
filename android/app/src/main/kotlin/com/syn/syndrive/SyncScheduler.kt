package com.syn.syndrive

import android.content.Context

/**
 * 설정된 주기에 맞춰 동기화 실행 방식을 선택한다.
 * - 15분 미만: 상시 실행 포그라운드 서비스(고속 모드)
 * - 15분 이상: WorkManager 주기 작업
 *
 * SyndriveActivity(설정 화면)와 PharmTally MainActivity(앱 시작 시 재개) 양쪽에서
 * 같은 로직을 쓰도록 분리했다. 로그인 안 됐으면 아무것도 안 한다.
 */
object SyncScheduler {
    fun apply(context: Context) {
        val prefs = Prefs(context)
        val auth = AuthManager(prefs)
        if (!auth.isSignedIn) return
        if (prefs.intervalMinutes < 15) {
            SyncWorker.cancel(context)
            FastSyncService.start(context)
        } else {
            FastSyncService.stop(context)
            SyncWorker.schedule(context, prefs.intervalMinutes)
        }
    }
}
