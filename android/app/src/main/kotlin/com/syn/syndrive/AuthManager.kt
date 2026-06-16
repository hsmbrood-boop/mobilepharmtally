package com.syn.syndrive

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException

/**
 * Microsoft 개인 계정 OAuth 2.0 — 디바이스 코드 흐름.
 * 앱 등록 없이 공개(first-party) 클라이언트 ID를 빌려 쓰므로 Azure 포털 작업이 전혀 필요 없다.
 * 사용자는 브라우저에서 microsoft.com/devicelogin 에 코드만 입력하면 된다.
 */
class AuthManager(private val prefs: Prefs) {

    companion object {
        // 사용자 본인 Azure 디렉터리에 등록한 SynDrive 앱 (개인 계정 전용, 퍼블릭 클라이언트 흐름 허용)
        const val DEFAULT_CLIENT_ID = "87fb0ed1-35ce-43a5-ada6-47913743069e"
        const val SCOPE = "Files.Read offline_access"
        private const val BASE = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    }

    private val http = Http.client

    private fun clientId() = prefs.clientId.ifBlank { DEFAULT_CLIENT_ID }

    val isSignedIn: Boolean get() = prefs.refreshToken != null

    data class DeviceCode(
        val deviceCode: String,
        val userCode: String,
        val verificationUri: String,
        val interval: Int,
        val expiresIn: Int,
    )

    /** 1단계: 디바이스 코드 요청 → 사용자에게 보여줄 코드/URL 반환 */
    suspend fun requestDeviceCode(): DeviceCode = withContext(Dispatchers.IO) {
        val body = FormBody.Builder()
            .add("client_id", clientId())
            .add("scope", SCOPE)
            .build()
        val req = Request.Builder().url("$BASE/devicecode").post(body).build()
        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IOException("디바이스 코드 요청 실패 (${resp.code}): ${text.take(200)}")
            val j = JSONObject(text)
            DeviceCode(
                deviceCode = j.getString("device_code"),
                userCode = j.getString("user_code"),
                verificationUri = j.optString("verification_uri", "https://microsoft.com/devicelogin"),
                interval = j.optInt("interval", 5),
                expiresIn = j.optInt("expires_in", 900),
            )
        }
    }

    /** 2단계: 사용자가 브라우저에서 승인할 때까지 폴링. 성공하면 토큰 저장. */
    suspend fun pollForToken(dc: DeviceCode, onWaiting: (String) -> Unit): Boolean = withContext(Dispatchers.IO) {
        val deadline = dc.expiresIn
        var elapsed = 0
        var interval = dc.interval
        while (elapsed < deadline) {
            delay(interval * 1000L)
            elapsed += interval
            val body = FormBody.Builder()
                .add("client_id", clientId())
                .add("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                .add("device_code", dc.deviceCode)
                .build()
            val req = Request.Builder().url("$BASE/token").post(body).build()
            // 폴링 중 일시적 네트워크 오류(DNS 실패 등)는 로그인을 중단시키지 않고 다음 주기에 재시도한다.
            val resp = try {
                http.newCall(req).execute()
            } catch (e: IOException) {
                onWaiting("네트워크 재시도 중… (${e.message?.take(60)})")
                continue
            }
            resp.use {
                val text = resp.body?.string() ?: ""
                val j = runCatching { JSONObject(text) }.getOrNull()
                if (resp.isSuccessful && j != null) {
                    storeTokens(j)
                    return@withContext true
                }
                when (j?.optString("error")) {
                    "authorization_pending" -> onWaiting("승인 대기 중…")
                    "slow_down" -> interval += 5
                    "expired_token", "code_expired" -> throw IOException("코드가 만료됐습니다. 다시 시도하세요.")
                    "authorization_declined" -> throw IOException("로그인이 취소됐습니다.")
                    else -> throw IOException("로그인 실패: ${j?.optString("error_description")?.take(200) ?: text.take(200)}")
                }
            }
        }
        throw IOException("시간이 초과됐습니다. 다시 시도하세요.")
    }

    /** 만료 5분 전이면 refresh token으로 갱신 후 access token 반환 */
    suspend fun getValidAccessToken(): String = withContext(Dispatchers.IO) {
        val current = prefs.accessToken
        if (current != null && System.currentTimeMillis() < prefs.tokenExpiresAt - 5 * 60_000L) {
            return@withContext current
        }
        val rt = prefs.refreshToken ?: throw IOException("로그인이 필요합니다")
        val body = FormBody.Builder()
            .add("client_id", clientId())
            .add("grant_type", "refresh_token")
            .add("refresh_token", rt)
            .add("scope", SCOPE)
            .build()
        val req = Request.Builder().url("$BASE/token").post(body).build()
        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IOException("토큰 갱신 실패 (${resp.code}): ${text.take(200)}")
            storeTokens(JSONObject(text))
        }
        prefs.accessToken ?: throw IOException("토큰 갱신 실패")
    }

    fun signOut() = prefs.clearTokens()

    private fun storeTokens(json: JSONObject) {
        prefs.accessToken = json.getString("access_token")
        if (json.has("refresh_token")) prefs.refreshToken = json.getString("refresh_token")
        prefs.tokenExpiresAt = System.currentTimeMillis() + json.optLong("expires_in", 3600L) * 1000L
    }
}
