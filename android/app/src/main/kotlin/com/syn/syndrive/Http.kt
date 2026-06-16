package com.syn.syndrive

import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** 앱 전역 공유 HTTP 클라이언트 — 연결 풀/TLS 세션 재사용으로 요청 속도 확보 */
object Http {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .build()
}
