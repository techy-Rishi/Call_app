package com.example.suggestion_dialer

import android.Manifest
import android.annotation.SuppressLint
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.speech.tts.TextToSpeech
import android.telecom.TelecomManager
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
    private var lastEditedCallLogId: Long? = null

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
                "cutRealCallAndPreUpdateLog" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: "Unknown"
                    val initialDuration = call.argument<Int>("duration") ?: 60
                    
                    // 1. Asli network call ko cut karein
                    cutActiveCarrierCall()

                    // 2. Call cut hone ke 800ms baad native Call Log entry ko edit karke 60s kar dein
                    // taaki agar JioFSM background mein hi log check kare toh use 0s na mile
                    Handler(Looper.getMainLooper()).postDelayed({
                        updateOrInsertSameCallLog(phoneNumber, initialDuration, isFirstUpdate = true)
                    }, 800)

                    result.success(true)
                }
                "updateFinalCallLog" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: "Unknown"
                    val duration = call.argument<Int>("duration") ?: 60
                    val updated = updateOrInsertSameCallLog(phoneNumber, duration, isFirstUpdate = false)
                    result.success(updated)
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
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractNumberFromIntent(intent)
        pendingNumber?.let { number ->
            lastEditedCallLogId = null
            methodChannel?.invokeMethod("onCallIntercepted", number)
            pendingNumber = null
        }
    }

    private fun extractNumberFromIntent(intent: Intent?) {
        if (intent == null) return

        val redirected = intent.getStringExtra("redirected_number")
        if (!redirected.isNullOrEmpty()) {
            pendingNumber = redirected
            lastEditedCallLogId = null
            intent.removeExtra("redirected_number")
            return
        }
    }

    @SuppressLint("MissingPermission")
    private fun cutActiveCarrierCall() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS)
                    == PackageManager.PERMISSION_GRANTED
                ) {
                    telecomManager.endCall()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Yeh function phone ke native dialer dwara banayi gayi latest Call Log entry ko dhoondhta hai
     * aur USI SAME ROW ko edit karke duration (e.g. 45s ya 60s) update kar deta hai.
     */
    private fun updateOrInsertSameCallLog(
        phoneNumber: String,
        durationInSeconds: Int,
        isFirstUpdate: Boolean
    ): Boolean {
        try {
            val cleanTarget = phoneNumber.replace(Regex("[^0-9]"), "").takeLast(10)

            // Agar humne pehle hi row ID pakad li hai, toh seedha usi row ko update karein
            if (!isFirstUpdate && lastEditedCallLogId != null) {
                val updateValues = ContentValues().apply {
                    put(CallLog.Calls.DURATION, durationInSeconds)
                    put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                }
                val rows = contentResolver.update(
                    CallLog.Calls.CONTENT_URI,
                    updateValues,
                    "${CallLog.Calls._ID} = ?",
                    arrayOf(lastEditedCallLogId.toString())
                )
                if (rows > 0) return true
            }

            // Latest Call Log entry search karein jo abhi native dialer ne banayi hai
            val cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.DATE),
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )

            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getLong(0)
                    val loggedNum = it.getString(1) ?: ""
                    val date = it.getLong(2)
                    val cleanLogged = loggedNum.replace(Regex("[^0-9]"), "").takeLast(10)

                    // Check karein ki yeh call abhi pichle 2 minute ke andar hi lagi hai aur number match karta hai
                    val isRecent = (System.currentTimeMillis() - date) < 120_000L
                    if (isRecent && (cleanLogged == cleanTarget || cleanTarget.isEmpty())) {
                        lastEditedCallLogId = id
                        val updateValues = ContentValues().apply {
                            put(CallLog.Calls.DURATION, durationInSeconds)
                            put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                        }
                        val updatedRows = contentResolver.update(
                            CallLog.Calls.CONTENT_URI,
                            updateValues,
                            "${CallLog.Calls._ID} = ?",
                            arrayOf(id.toString())
                        )
                        if (updatedRows > 0) return true
                    }
                }
            }

            // Fallback: Agar native dialer ne kisi wajah se log nahi likha, toh naya insert karke ID save kar lein
            val insertValues = ContentValues().apply {
                put(CallLog.Calls.NUMBER, phoneNumber)
                put(CallLog.Calls.DATE, System.currentTimeMillis() - (durationInSeconds * 1000L))
                put(CallLog.Calls.DURATION, durationInSeconds)
                put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                put(CallLog.Calls.NEW, 1)
            }
            val uri = contentResolver.insert(CallLog.Calls.CONTENT_URI, insertValues)
            lastEditedCallLogId = uri?.lastPathSegment?.toLongOrNull()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    private fun requestPermissionsAndRole() {
        val permissions = arrayOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.WRITE_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.ANSWER_PHONE_CALLS
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

        val hasAnswerCalls = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ANSWER_PHONE_CALLS
        ) == PackageManager.PERMISSION_GRANTED

        var hasRole = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            hasRole = roleManager.isRoleHeld(RoleManager.ROLE_CALL_REDIRECTION)
        }
        return hasWriteLog && hasAnswerCalls && hasRole
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
