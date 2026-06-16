package com.syn.syndrive

import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
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
import java.util.concurrent.ConcurrentHashMap

/**
 * 원드라이브 → 폰 단방향 동기화 엔진.
 * Graph delta API로 변경분만 받고, 파일은 병렬(6개 동시)로 다운로드한다.
 * SAF의 findFile()이 호출마다 전체 자식 조회를 하므로 디렉터리 목록을 캐시한다.
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
        val treeUriStr = prefs.treeUri ?: throw IOException("폰 저장 폴더를 먼저 선택하세요")
        val localRoot = DocumentFile.fromTreeUri(context, Uri.parse(treeUriStr))
            ?: throw IOException("폰 폴더에 접근할 수 없습니다 (폴더를 다시 선택하세요)")
        if (!localRoot.canWrite()) throw IOException("폰 폴더에 쓰기 권한이 없습니다 (폴더를 다시 선택하세요)")

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

        val cache = DirCache(localRoot)

        // 2) 폴더 생성 (순차 — 부모가 자식보다 먼저 오도록 delta가 보장하지만, ensureDir가 중간 경로도 만든다)
        for (item in items) {
            if (item.has("deleted") || !item.has("folder")) continue
            val rel = relativePath(item, remotePath, item.optString("name")) ?: continue
            cache.ensureDir(rel)
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
                            val done = downloadFile(item, token, cache, rel, isInitial)
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
            if (rel != null && prefs.deleteRemoved && deleteLocal(cache, rel)) {
                summary.deleted++
                log("삭제: $rel")
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
        cache: DirCache,
        rel: String,
        isInitial: Boolean,
    ): Boolean {
        val name = item.getString("name")
        val dirRel = rel.substringBeforeLast('/', "")
        val existing = cache.child(dirRel, name)

        // 첫 전체 동기화 때만: 같은 크기의 파일이 이미 있으면 그대로 둔다 (OneSync로 받아둔 파일 재다운로드 방지)
        if (isInitial && existing != null) {
            val size = item.optLong("size", -1L)
            if (size >= 0 && existing.length() == size) return false
        }

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
            val target = existing ?: cache.createFile(dirRel, name)
            // DocumentsProvider가 확장자를 덧붙여 이름을 바꿨으면 원래 이름으로 되돌린다
            if (target.name != name) target.renameTo(name)
            context.contentResolver.openOutputStream(target.uri, "wt")?.use { out ->
                resp.body?.byteStream()?.copyTo(out) ?: throw IOException("응답 본문 없음")
            } ?: throw IOException("파일 쓰기 스트림을 열 수 없음")
            cache.put(dirRel, name, target)
        }
        return true
    }

    private fun deleteLocal(cache: DirCache, rel: String): Boolean {
        val dirRel = rel.substringBeforeLast('/', "")
        val name = rel.substringAfterLast('/')
        val f = cache.childIfExists(dirRel, name) ?: return false
        val ok = f.delete()
        if (ok) cache.remove(dirRel, name)
        return ok
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

    private fun guessMime(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    // ── SAF 디렉터리/목록 캐시 ───────────────────────────────────────────────

    private inner class DirCache(root: DocumentFile) {
        private val dirs = ConcurrentHashMap<String, DocumentFile>().apply { put("", root) }
        private val listings = ConcurrentHashMap<String, ConcurrentHashMap<String, DocumentFile>>()

        fun ensureDir(relDir: String): DocumentFile {
            val norm = relDir.trim('/')
            dirs[norm]?.let { return it }
            synchronized(this) {
                dirs[norm]?.let { return it }
                val parentRel = norm.substringBeforeLast('/', "")
                val name = norm.substringAfterLast('/')
                val parent = ensureDir(parentRel)
                val found = listing(parentRel)[name]?.takeIf { it.isDirectory }
                val dir = found ?: parent.createDirectory(name)?.also { listing(parentRel)[name] = it }
                    ?: throw IOException("폴더 생성 실패: $name")
                dirs[norm] = dir
                return dir
            }
        }

        fun child(relDir: String, name: String): DocumentFile? = listing(relDir.trim('/'))[name]

        /** 중간 폴더를 만들지 않고 조회만 (삭제 처리용) */
        fun childIfExists(relDir: String, name: String): DocumentFile? {
            val norm = relDir.trim('/')
            if (norm.isNotEmpty() && !dirExists(norm)) return null
            return listing(norm)[name]
        }

        fun createFile(relDir: String, name: String): DocumentFile =
            ensureDir(relDir).createFile(guessMime(name), name)
                ?: throw IOException("파일 생성 실패: $name")

        fun put(relDir: String, name: String, doc: DocumentFile) {
            listing(relDir.trim('/'))[name] = doc
        }

        fun remove(relDir: String, name: String) {
            listings[relDir.trim('/')]?.remove(name)
        }

        private fun dirExists(norm: String): Boolean {
            dirs[norm]?.let { return true }
            val parentRel = norm.substringBeforeLast('/', "")
            if (parentRel.isNotEmpty() && !dirExists(parentRel)) return false
            val name = norm.substringAfterLast('/')
            val d = listing(parentRel)[name]?.takeIf { it.isDirectory } ?: return false
            dirs[norm] = d
            return true
        }

        private fun listing(relDir: String): ConcurrentHashMap<String, DocumentFile> {
            listings[relDir]?.let { return it }
            val dir = ensureDir(relDir)
            val m = ConcurrentHashMap<String, DocumentFile>()
            for (f in dir.listFiles()) f.name?.let { n -> m[n] = f }
            return listings.putIfAbsent(relDir, m) ?: m
        }
    }

    // ── 파일 id → 상대경로 매핑 (삭제 동기화용) ──────────────────────────────

    private val mapFile: File get() = File(context.filesDir, "filemap.json")

    private fun loadFileMap(): JSONObject =
        runCatching { JSONObject(mapFile.readText()) }.getOrElse { JSONObject() }

    private fun saveFileMap(map: JSONObject) {
        mapFile.writeText(map.toString())
    }
}
