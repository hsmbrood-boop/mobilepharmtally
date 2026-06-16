package com.syn.syndrive

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * 원드라이브 → 폰 단방향 동기화 엔진.
 * Graph delta API로 변경분만 받고, 파일은 병렬(6개 동시)로 다운로드한다.
 *
 * 저장은 SAF 가 아니라 일반 파일 경로(java.io.File)로 직접 쓴다. 앱이 "모든 파일
 * 접근(MANAGE_EXTERNAL_STORAGE)" 권한을 갖고 있으므로 가능하며, 삼성 등에서 SAF
 * 폴더 선택이 막히는 문제를 피한다. PharmTally 도 같은 경로를 dart:io 로 읽는다.
 */
class SyncEngine(
    private val context: Context,
    private val prefs: Prefs,
    private val auth: AuthManager,
) {
    private val http = Http.client

    class Summary {
        var downloaded = 0
        var skipped = 0
        var deleted = 0
        var failed = 0
        /** 이번 동기화로 새로 내려받은 .xlsx 파일 이름들 (PharmTally 새 매출 알림용) */
        val newExcelFiles = ArrayList<String>()
        override fun toString() = "내려받음 ${downloaded}개, 건너뜀 $skipped, 삭제 $deleted, 실패 $failed"
    }

    suspend fun sync(log: (String) -> Unit): Summary = withContext(Dispatchers.IO) {
        val remotePath = prefs.remotePath.trim().trim('/')
        if (remotePath.isEmpty()) throw IOException("원드라이브 폴더 경로를 입력하세요")
        val localPath = prefs.localDirPath?.trim()
        if (localPath.isNullOrEmpty()) throw IOException("폰 저장 폴더를 먼저 지정하세요")
        val localRoot = File(localPath)
        if (!localRoot.exists() && !localRoot.mkdirs()) {
            throw IOException("폴더를 만들 수 없습니다: $localPath\n(설정에서 '모든 파일 접근'을 켰는지 확인하세요)")
        }
        if (!localRoot.isDirectory) throw IOException("폴더가 아닙니다: $localPath")

        val token = auth.getValidAccessToken()
        val fileMap = loadFileMap()
        val summary = Summary()

        // deltaLink가 없으면 첫 전체 열거 → 이미 있는 파일은 크기 비교로 재다운로드를 피한다
        val isInitial = prefs.deltaLink == null
        var url = prefs.deltaLink
            ?: "https://graph.microsoft.com/v1.0/me/drive/root:/${encodePath(remotePath)}:/delta"
        var newDeltaLink: String? = null

        // 1) delta 전체 페이지를 먼저 수집
        val items = ArrayList<JSONObject>()
        while (true) {
            val resp = graphGet(url, token)
            val page = resp.optJSONArray("value")
            if (page != null) for (i in 0 until page.length()) items.add(page.getJSONObject(i))
            url = if (resp.has("@odata.nextLink")) resp.getString("@odata.nextLink") else {
                newDeltaLink = resp.optString("@odata.deltaLink").ifEmpty { null }
                break
            }
        }

        // 2) 폴더 생성
        for (item in items) {
            if (item.has("deleted") || !item.has("folder")) continue
            val rel = relativePath(item, remotePath, item.optString("name")) ?: continue
            File(localRoot, rel).mkdirs()
            fileMap.put(item.getString("id"), rel)
        }

        // 3) 파일 병렬 다운로드 (동시 6개)
        val fileItems = items.filter { !it.has("deleted") && it.has("file") }
        val semaphore = Semaphore(6)
        coroutineScope {
            fileItems.map { item ->
                async(Dispatchers.IO) {
                    semaphore.withPermit {
                        val name = item.optString("name")
                        val rel = relativePath(item, remotePath, name) ?: return@withPermit
                        try {
                            val done = downloadFile(item, token, localRoot, rel, isInitial)
                            synchronized(summary) {
                                if (done) summary.downloaded++ else summary.skipped++
                                // 새로 내려받은 엑셀만 PharmTally 알림 대상으로 모은다
                                // (OneDrive/Excel 임시 잠금 파일 `~$...` 제외)
                                if (done && name.endsWith(".xlsx", true) && !name.startsWith("~")) {
                                    summary.newExcelFiles.add(name)
                                }
                            }
                            if (done) log("다운로드: $rel")
                            synchronized(fileMap) { fileMap.put(item.getString("id"), rel) }
                        } catch (e: Exception) {
                            synchronized(summary) { summary.failed++ }
                            log("실패: $rel — ${e.message}")
                        }
                    }
                }
            }.awaitAll()
        }

        // 4) 삭제 처리
        for (item in items) {
            if (!item.has("deleted")) continue
            val id = item.getString("id")
            val rel = fileMap.optString(id).ifEmpty { null }
            if (rel != null && prefs.deleteRemoved) {
                val f = File(localRoot, rel)
                if (f.exists() && f.delete()) {
                    summary.deleted++
                    log("삭제: $rel")
                }
            }
            fileMap.remove(id)
        }

        saveFileMap(fileMap)
        // 실패한 파일이 있으면 deltaLink를 갱신하지 않아 다음 동기화 때 다시 시도된다
        if (summary.failed == 0 && newDeltaLink != null) prefs.deltaLink = newDeltaLink
        summary
    }

    /**
     * parentReference.path("/drive/root:/Documents/Sync/sub")에서
     * 동기화 루트 기준 상대 경로("sub/파일명")를 계산한다.
     */
    private fun relativePath(item: JSONObject, remotePath: String, name: String): String? {
        if (name.isEmpty()) return null
        val parent = item.optJSONObject("parentReference") ?: return null
        val raw = parent.optString("path")
        if (!raw.contains("root:")) return null
        val decoded = Uri.decode(raw.substringAfter("root:")).trim('/')
        if (!decoded.startsWith(remotePath, ignoreCase = true)) return null
        val sub = decoded.substring(remotePath.length).trim('/')
        return if (sub.isEmpty()) name else "$sub/$name"
    }

    /** @return true = 실제 다운로드함, false = 동일 파일이 이미 있어 건너뜀 */
    private fun downloadFile(
        item: JSONObject,
        token: String,
        localRoot: File,
        rel: String,
        isInitial: Boolean,
    ): Boolean {
        val target = File(localRoot, rel)

        // 첫 전체 동기화 때만: 같은 크기의 파일이 이미 있으면 그대로 둔다 (재다운로드 방지)
        if (isInitial && target.exists()) {
            val size = item.optLong("size", -1L)
            if (size >= 0 && target.length() == size) return false
        }

        target.parentFile?.mkdirs()

        val downloadUrl = item.optString("@microsoft.graph.downloadUrl")
        val req = if (downloadUrl.isNotEmpty()) {
            Request.Builder().url(downloadUrl).build() // 사전 인증된 임시 URL — 헤더 불필요
        } else {
            Request.Builder()
                .url("https://graph.microsoft.com/v1.0/me/drive/items/${item.getString("id")}/content")
                .header("Authorization", "Bearer $token")
                .build()
        }

        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
            val body = resp.body ?: throw IOException("응답 본문 없음")
            // 임시 파일에 받은 뒤 교체 — 중간에 실패해도 깨진 파일이 남지 않게.
            val tmp = File(target.parentFile, ".${target.name}.part")
            body.byteStream().use { input ->
                tmp.outputStream().use { out -> input.copyTo(out) }
            }
            if (target.exists()) target.delete()
            if (!tmp.renameTo(target)) {
                // rename 실패 시(드묾) 직접 복사로 폴백
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
        }
        return true
    }

    private fun graphGet(url: String, token: String): JSONObject {
        val req = Request.Builder().url(url).header("Authorization", "Bearer $token").build()
        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) {
                if (resp.code == 404) throw IOException("원드라이브에서 폴더를 찾을 수 없습니다: ${prefs.remotePath}")
                // deltaLink가 만료된 경우(410) 처음부터 다시
                if (resp.code == 410) {
                    prefs.deltaLink = null
                    throw IOException("동기화 상태가 만료됐습니다. 다시 동기화를 실행하세요.")
                }
                throw IOException("Graph API 오류 ${resp.code}: ${text.take(200)}")
            }
            return JSONObject(text)
        }
    }

    private fun encodePath(path: String): String =
        path.split('/').joinToString("/") { Uri.encode(it) }

    // ── 파일 id → 상대경로 매핑 (삭제 동기화용) ──────────────────────────────

    private val mapFile: File get() = File(context.filesDir, "filemap.json")

    private fun loadFileMap(): JSONObject =
        runCatching { JSONObject(mapFile.readText()) }.getOrElse { JSONObject() }

    private fun saveFileMap(map: JSONObject) {
        mapFile.writeText(map.toString())
    }
}
