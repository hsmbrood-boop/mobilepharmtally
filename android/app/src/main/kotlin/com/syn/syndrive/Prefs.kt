package com.syn.syndrive

import android.content.Context

/** 앱 설정/토큰/동기화 상태 저장소 */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("syndrive", Context.MODE_PRIVATE)

    var clientId: String
        get() = sp.getString("client_id", "") ?: ""
        set(v) = sp.edit().putString("client_id", v).apply()

    var codeVerifier: String?
        get() = sp.getString("code_verifier", null)
        set(v) = sp.edit().putString("code_verifier", v).apply()

    var accessToken: String?
        get() = sp.getString("access_token", null)
        set(v) = sp.edit().putString("access_token", v).apply()

    var refreshToken: String?
        get() = sp.getString("refresh_token", null)
        set(v) = sp.edit().putString("refresh_token", v).apply()

    var tokenExpiresAt: Long
        get() = sp.getLong("token_expires_at", 0L)
        set(v) = sp.edit().putLong("token_expires_at", v).apply()

    /** OneDrive 쪽 동기화 대상 폴더 경로 (예: "Documents/Sync") */
    var remotePath: String
        get() = sp.getString("remote_path", "") ?: ""
        set(v) = sp.edit().putString("remote_path", v).apply()

    /** SAF로 선택한 폰 로컬 폴더의 tree URI */
    var treeUri: String?
        get() = sp.getString("tree_uri", null)
        set(v) = sp.edit().putString("tree_uri", v).apply()

    /**
     * 폰 로컬 저장 폴더의 실제 경로(예: /storage/emulated/0/OneSyncFiles).
     * SAF tree URI 대신 "모든 파일 접근" 권한으로 직접 파일을 쓰기 위해 사용한다.
     * (삼성 등에서 SAF 폴더 선택이 막히는 문제를 피하려고 경로 방식으로 전환.)
     */
    var localDirPath: String?
        get() = sp.getString("local_dir_path", null)
        set(v) = sp.edit().putString("local_dir_path", v).apply()

    /** Graph delta API의 deltaLink — null이면 다음 동기화 때 전체 목록부터 다시 받음 */
    var deltaLink: String?
        get() = sp.getString("delta_link", null)
        set(v) = sp.edit().putString("delta_link", v).apply()

    var intervalMinutes: Int
        get() = sp.getInt("interval_minutes", 5)
        set(v) = sp.edit().putInt("interval_minutes", v).apply()

    /** 원드라이브에서 삭제된 파일을 폰에서도 삭제할지 */
    var deleteRemoved: Boolean
        get() = sp.getBoolean("delete_removed", true)
        set(v) = sp.edit().putBoolean("delete_removed", v).apply()

    var lastSyncInfo: String
        get() = sp.getString("last_sync_info", "아직 동기화한 적 없음") ?: ""
        set(v) = sp.edit().putString("last_sync_info", v).apply()

    fun clearTokens() {
        sp.edit()
            .remove("access_token")
            .remove("refresh_token")
            .remove("token_expires_at")
            .remove("code_verifier")
            .apply()
    }
}
