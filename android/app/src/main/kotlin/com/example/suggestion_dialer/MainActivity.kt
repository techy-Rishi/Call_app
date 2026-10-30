package com.example.suggestion_dialer

import android.Manifest
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.CallLog
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    private val CHANNEL = "com.example.suggestion/call_channel"
    private var methodChannel: MethodChannel? = null
    private var pendingNumber: String? = null
    private var tts: TextToSpeech? = null

    private val PERMISSION_REQUEST_CODE = 1001
    private val ROLE_REQUEST_CODE = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
        extractNumberFromIntent(intent)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale("en", "IN")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialNumber" -> {
                    result.success(pendingNumber)
                    pendingNumber = null
                }
                "requestSetup" -> {
                    requestPermissionsAndRole()
                    result.success(true)
                }
                "checkSetupStatus" -> {
                    result.success(isSetupComplete())
                }
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ivr_tts")
                    result.success(true)
                }
                "stopSpeaking" -> {
                    tts?.stop()
                    result.success(true)
                }
                "insertCallLog" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: "Unknown"
                    val duration = call.argument<Int>("duration") ?: 0
                    val inserted = insertFakeCallLog(phoneNumber, duration)
                    result.success(inserted)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractNumberFromIntent(intent)
        pendingNumber?.let { number ->
            methodChannel?.invokeMethod("onCallIntercepted", number)
            pendingNumber = null
        }
    }

    private fun extractNumberFromIntent(intent: Intent?) {
        if (intent == null) return

        // Case 1: MyCallRedirectionService se aaya hua number
        val redirected = intent.getStringExtra("redirected_number")
        if (!redirected.isNullOrEmpty()) {
            pendingNumber = redirected
            intent.removeExtra("redirected_number")
            return
        }

        // Case 2: Direct tel: intent se aaya hua number
        if (intent.action == Intent.ACTION_DIAL || intent.action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null && data.scheme == "tel") {
                pendingNumber = data.schemeSpecificPart
            }
        }
    }

    private fun requestPermissionsAndRole() {
        val permissions = arrayOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.WRITE_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.CALL_PHONE
        )
        ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_CALL_REDIRECTION) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_CALL_REDIRECTION)
            ) {
                val roleIntent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_REDIRECTION)
                startActivityForResult(roleIntent, ROLE_REQUEST_CODE)
            }
        }
    }

    private fun isSetupComplete(): Boolean {
        val hasWriteLog = ContextCompat.checkSelfPermission(
            this, Manifest.permission.WRITE_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        var hasRole = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            hasRole = roleManager.isRoleHeld(RoleManager.ROLE_CALL_REDIRECTION)
        }
        return hasWriteLog && hasRole
    }

    private fun insertFakeCallLog(phoneNumber: String, durationInSeconds: Int): Boolean {
        return try {
            val values = ContentValues().apply {
                put(CallLog.Calls.NUMBER, phoneNumber)
                // Call start time = current time minus jitne seconds call chali
                put(CallLog.Calls.DATE, System.currentTimeMillis() - (durationInSeconds * 1000L))
                put(CallLog.Calls.DURATION, durationInSeconds)
                put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                put(CallLog.Calls.NEW, 1)
                put(CallLog.Calls.CACHED_NAME, "")
            }
            contentResolver.insert(CallLog.Calls.CONTENT_URI, values)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
