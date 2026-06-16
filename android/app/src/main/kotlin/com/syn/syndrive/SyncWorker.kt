package com.syn.syndrive

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val prefs = Prefs(applicationContext)
        val auth = AuthManager(prefs)
        if (!auth.isSignedIn) return Result.failure()

        return try {
            val summary = SyncEngine(applicationContext, prefs, auth).sync { }
            prefs.lastSyncInfo = "${now()} 자동 — $summary"
            // 새로 받은 엑셀이 있으면 PharmTally 새 매출 알림을 띄운다.
            NewFileNotifier.notifyNewFiles(applicationContext, summary.newExcelFiles)
            if (summary.failed > 0) Result.retry() else Result.success()
        } catch (e: Exception) {
            prefs.lastSyncInfo = "${now()} 자동 — 오류: ${e.message}"
            Result.retry()
        }
    }

    private fun now(): String = SimpleDateFormat("MM-dd HH:mm", Locale.KOREA).format(Date())

    companion object {
        private const val WORK_NAME = "syndrive-periodic-sync"

        fun schedule(context: Context, minutes: Int) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(minutes.toLong(), TimeUnit.MINUTES)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
