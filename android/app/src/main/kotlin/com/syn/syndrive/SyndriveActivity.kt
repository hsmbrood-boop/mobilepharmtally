package com.syn.syndrive

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.switchmaterial.SwitchMaterial
import com.orcholdings.pharmtally.R
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * SynDrive 설정 화면 — PharmTally 폴더 버튼으로 열린다.
 *
 * (원래 SynDrive 의 MainActivity. 통합되면서 PharmTally 의 Flutter MainActivity 와
 * 구분하기 위해 SyndriveActivity 로 이름을 바꿨다.)
 *
 * 통합 포인트: "폰 폴더 선택"으로 고른 SAF 폴더의 실제 경로를 PharmTally 가 읽는
 * SharedPreferences 키에도 써넣어, SynDrive 가 받는 폴더 = PharmTally 가 읽는
 * 폴더가 자동으로 일치하게 한다.
 */
class SyndriveActivity : AppCompatActivity() {

    private lateinit var prefs: Prefs
    private lateinit var auth: AuthManager

    private lateinit var btnLogin: Button
    private lateinit var tvAuthStatus: TextView
    private lateinit var etRemotePath: EditText
    private lateinit var btnPickFolder: Button
    private lateinit var tvLocalFolder: TextView
    private lateinit var spInterval: Spinner
    private lateinit var swDelete: SwitchMaterial
    private lateinit var btnSyncNow: Button
    private lateinit var btnBattery: Button
    private lateinit var tvLastSync: TextView
    private lateinit var tvLog: TextView
    private lateinit var scrollLog: ScrollView

    // 15분 미만은 WorkManager 제한 때문에 상시 실행 서비스(고속 모드)로 동작
    private val intervalMinutes = intArrayOf(1, 2, 5, 10, 15, 30, 60, 180)

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private val pickFolder = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            prefs.treeUri = uri.toString()
            prefs.deltaLink = null // 대상 폴더가 바뀌었으니 전체 재열거
            // PharmTally 가 엑셀을 읽을 실제 경로를 함께 저장 → 한 번 설정으로 끝.
            bridgeFolderToPharmTally(uri)
            updateUi()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_syndrive)

        // Android 15 edge-to-edge: 시스템 바 영역만큼 패딩 추가 (기본 16dp 유지)
        val basePad = (16 * resources.displayMetrics.density).toInt()
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.rootLayout)) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(basePad + bars.left, basePad + bars.top, basePad + bars.right, basePad + bars.bottom)
            WindowInsetsCompat.CONSUMED
        }

        prefs = Prefs(this)
        auth = AuthManager(prefs)

        btnLogin = findViewById(R.id.btnLogin)
        tvAuthStatus = findViewById(R.id.tvAuthStatus)
        etRemotePath = findViewById(R.id.etRemotePath)
        btnPickFolder = findViewById(R.id.btnPickFolder)
        tvLocalFolder = findViewById(R.id.tvLocalFolder)
        spInterval = findViewById(R.id.spInterval)
        swDelete = findViewById(R.id.swDelete)
        btnSyncNow = findViewById(R.id.btnSyncNow)
        btnBattery = findViewById(R.id.btnBattery)
        tvLastSync = findViewById(R.id.tvLastSync)
        tvLog = findViewById(R.id.tvLog)
        scrollLog = findViewById(R.id.scrollLog)

        etRemotePath.setText(prefs.remotePath)
        swDelete.isChecked = prefs.deleteRemoved

        spInterval.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_dropdown_item,
            arrayOf(
                "1분마다 (고속 모드)", "2분마다 (고속 모드)", "5분마다 (고속 모드)", "10분마다 (고속 모드)",
                "15분마다", "30분마다", "1시간마다", "3시간마다"
            )
        )
        spInterval.setSelection(intervalMinutes.indexOf(prefs.intervalMinutes).coerceAtLeast(0))
        spInterval.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                if (prefs.intervalMinutes != intervalMinutes[pos]) {
                    prefs.intervalMinutes = intervalMinutes[pos]
                    applySchedule()
                }
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }

        swDelete.setOnCheckedChangeListener { _, checked -> prefs.deleteRemoved = checked }

        btnLogin.setOnClickListener { startLogin() }
        btnPickFolder.setOnClickListener { pickFolder.launch(null) }
        btnSyncNow.setOnClickListener { runSyncNow() }
        btnBattery.setOnClickListener { requestBatteryException() }

        updateUi()
        applySchedule() // 재부팅 후 앱을 열면 고속 모드 서비스가 다시 시작된다
    }

    override fun onResume() {
        super.onResume()
        updateUi()
    }

    /** 주기에 맞는 실행 방식 선택: 15분 미만 = 상시 실행 서비스, 이상 = WorkManager */
    private fun applySchedule() {
        if (!auth.isSignedIn) return
        if (prefs.intervalMinutes < 15) {
            SyncWorker.cancel(this)
            ensureNotifPermission()
            FastSyncService.start(this)
        } else {
            FastSyncService.stop(this)
            SyncWorker.schedule(this, prefs.intervalMinutes)
        }
    }

    private fun ensureNotifPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onPause() {
        super.onPause()
        saveTextSettings()
    }

    private fun saveTextSettings() {
        val newPath = etRemotePath.text.toString().trim()
        if (newPath != prefs.remotePath) {
            prefs.remotePath = newPath
            prefs.deltaLink = null // 원격 폴더가 바뀌었으니 전체 재열거
        }
    }

    /** 디바이스 코드 로그인: 코드를 띄우고 브라우저를 연 뒤 승인될 때까지 폴링 */
    private fun startLogin() {
        saveTextSettings()
        btnLogin.isEnabled = false
        appendLog("── 로그인 시작 ──")
        lifecycleScope.launch {
            try {
                val dc = auth.requestDeviceCode()
                // 코드를 클립보드에 복사해두고 브라우저를 연다
                val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                cm.setPrimaryClip(android.content.ClipData.newPlainText("code", dc.userCode))
                appendLog("브라우저에서 코드를 입력하세요: ${dc.userCode}")
                appendLog("(코드는 복사돼 있습니다. 붙여넣기 하세요)")
                showCodeDialog(dc.userCode, dc.verificationUri)
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(dc.verificationUri)))
                auth.pollForToken(dc) { }
                appendLog("로그인 성공 ✓")
                applySchedule()
            } catch (e: Exception) {
                appendLog("로그인 실패: ${e.message}")
            }
            btnLogin.isEnabled = true
            updateUi()
        }
    }

    private fun showCodeDialog(code: String, url: String) {
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Microsoft 로그인")
            .setMessage("브라우저가 열립니다.\n\n아래 코드를 입력하세요 (이미 복사됨):\n\n$code\n\n입력 후 원드라이브 계정으로 로그인하면 이 앱으로 자동 연결됩니다.")
            .setPositiveButton("브라우저 다시 열기") { _, _ ->
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            }
            .setNegativeButton("확인", null)
            .show()
    }

    private fun runSyncNow() {
        saveTextSettings()
        btnSyncNow.isEnabled = false
        appendLog("── ${now()} 수동 동기화 시작 ──")
        lifecycleScope.launch {
            try {
                val summary = SyncEngine(this@SyndriveActivity, prefs, auth).sync { msg ->
                    runOnUiThread { appendLog(msg) }
                }
                prefs.lastSyncInfo = "${now()} 수동 — $summary"
                appendLog("완료: $summary")
                // 수동 동기화로 받은 새 엑셀도 알림을 띄운다.
                NewFileNotifier.notifyNewFiles(applicationContext, summary.newExcelFiles)
            } catch (e: Exception) {
                appendLog("동기화 오류: ${e.message}")
            }
            btnSyncNow.isEnabled = true
            updateUi()
        }
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryException() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) {
            Toast.makeText(this, "이미 배터리 최적화에서 제외되어 있습니다", Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            )
        )
    }

    private fun updateUi() {
        tvAuthStatus.text = if (auth.isSignedIn) "로그인됨 ✓" else "로그인 필요"
        tvLocalFolder.text = prefs.treeUri?.let { friendlyTreePath(it) } ?: "선택 안 됨"
        tvLastSync.text = "마지막 동기화: ${prefs.lastSyncInfo}"
    }

    private fun friendlyTreePath(uriStr: String): String =
        Uri.decode(uriStr).substringAfterLast(':').ifEmpty { uriStr }

    private fun appendLog(msg: String) {
        tvLog.append("$msg\n")
        scrollLog.post { scrollLog.fullScroll(View.FOCUS_DOWN) }
    }

    private fun now(): String = SimpleDateFormat("MM-dd HH:mm", Locale.KOREA).format(Date())

    // ── PharmTally 연동 ────────────────────────────────────────────────────

    /**
     * SAF tree URI 의 실제 파일 경로를 계산해 PharmTally(Flutter) 가 읽는
     * SharedPreferences 키에 써넣는다. PharmTally 는 dart:io + 모든 파일 접근
     * 권한으로 이 경로를 직접 읽으므로, SynDrive 가 내려받는 폴더와 PharmTally 가
     * 읽는 폴더가 자동으로 같아진다.
     *
     * 변환은 기본(primary) 저장소와 SD카드의 일반적인 경우를 지원한다. 변환이
     * 불가능한 특수 제공자면 조용히 건너뛴다(이 경우 사용자가 PharmTally 데스크톱
     * 등에서 폴더를 직접 지정).
     */
    private fun bridgeFolderToPharmTally(treeUri: Uri) {
        val path = treeUriToRealPath(treeUri) ?: return
        // Flutter shared_preferences 는 "FlutterSharedPreferences" 파일에
        // "flutter." 접두어를 붙여 저장한다.
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.pharm_tally.savedFolderPath", path)
            .apply()
        appendLog("PharmTally 읽기 폴더로 연결됨: $path")
    }

    private fun treeUriToRealPath(treeUri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val parts = docId.split(":", limit = 2)
            if (parts.size < 2) return null
            val type = parts[0]
            val rel = parts[1]
            if (type.equals("primary", ignoreCase = true)) {
                "${Environment.getExternalStorageDirectory().absolutePath}/$rel".trimEnd('/')
            } else {
                // SD카드 등 보조 저장소: 대부분의 기기에서 /storage/<volume>/<rel>
                "/storage/$type/$rel".trimEnd('/')
            }
        } catch (e: Exception) {
            null
        }
    }
}
