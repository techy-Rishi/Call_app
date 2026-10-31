package com.example.suggestion_dialer

import android.Manifest
import android.annotation.SuppressLint
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.random.Random

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    private val CHANNEL = "com.example.suggestion/call_channel"
    private var methodChannel: MethodChannel? = null
    private var tts: TextToSpeech? = null

    private val PERMISSION_REQUEST_CODE = 1001
    private val ROLE_REQUEST_CODE = 1002
    private val OVERLAY_REQUEST_CODE = 1003

    companion object {
        private val mainHandler = Handler(Looper.getMainLooper())
        var instance: MainActivity? = null

        var activePhoneNumber: String? = null
        var activeTargetDuration: Int = 48
        var ringCutDelaySeconds: Int = 3
        var callStartTimeMillis: Long = 0L
        var isSessionRunning: Boolean = false
        private var callLogObserver: ContentObserver? = null

        /**
         * Yeh function background se hi pura kaam संभालta hai:
         * 1. 41-55s ke beech random time chunta hai.
         * 2. 3s baad asli call cut karta hai.
         * 3. ContentObserver + 4 retries se Call Log ko 100% update karta hai.
         * 4. Suggestion Dialer UI ko automatically Phone app ke upar le aata hai.
         */
        fun startBackgroundCallProcess(context: Context, rawNumber: String) {
            val now = System.currentTimeMillis()
            // Agar pichle 6 second me pehle hi trigger ho chuka hai toh duplicate trigger rokein
            if (isSessionRunning && (now - callStartTimeMillis) < 6000L) {
                return
            }

            isSessionRunning = true
            callStartTimeMillis = now
            activePhoneNumber = if (rawNumber.isBlank()) "Unknown" else rawNumber
            // 41 se 55 seconds ke beech random duration
            activeTargetDuration = Random.nextInt(41, 56)

            mainHandler.removeCallbacksAndMessages(null)
            unregisterLogObserver(context)

            mainHandler.post {
                Toast.makeText(
                    context,
                    "AI Dialer Active: Auto-cut in ${ringCutDelaySeconds}s -> Log: ${activeTargetDuration}s",
                    Toast.LENGTH_SHORT
                ).show()

                instance?.notifyFlutterSession(activePhoneNumber!!, activeTargetDuration)
            }

            // Step A: 1.2s baad UI ko Phone app ke upar pop-up karein
            mainHandler.postDelayed({
                bringActivityToFront(context, activePhoneNumber!!, activeTargetDuration)
            }, 1200L)

            // Step B: 3s (ringCutDelaySeconds) par asli call cut karein aur Call Log observer lagayein
            val cutDelayMillis = ringCutDelaySeconds * 1000L
            mainHandler.postDelayed({
                registerLogObserver(context, activePhoneNumber!!, activeTargetDuration)
                cutActiveCarrierCall(context)

                // Call cut hone ke turant baad UI wapas front par layein
                bringActivityToFront(context, activePhoneNumber!!, activeTargetDuration)

                // Multi-Retry Call Log Updates (taaki kisi bhi phone par 0s na reh jaye)
                val retryDelays = listOf(700L, 1500L, 2800L, 4500L)
                for ((index, delay) in retryDelays.withIndex()) {
                    mainHandler.postDelayed({
                        val allowInsertFallback = (index == retryDelays.lastIndex)
                        updateSameCallLog(
                            context,
                            activePhoneNumber!!,
                            activeTargetDuration,
                            allowInsertFallback
                        )
                    }, delay)
                }

                // 8 second baad observer hata dein aur session flag reset kar dein
                mainHandler.postDelayed({
                    unregisterLogObserver(context)
                    isSessionRunning = false
                }, 8000L)

            }, cutDelayMillis)
        }

        private fun bringActivityToFront(context: Context, number: String, targetDuration: Int) {
            try {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    putExtra("redirected_number", number)
                    putExtra("target_duration", targetDuration)
                }
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        @SuppressLint("MissingPermission")
        fun cutActiveCarrierCall(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        telecomManager.endCall()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        private fun registerLogObserver(context: Context, number: String, duration: Int) {
            try {
                unregisterLogObserver(context)
                val observer = object : ContentObserver(mainHandler) {
                    override fun onChange(selfChange: Boolean) {
                        super.onChange(selfChange)
                        // Jaise hi Phone app 0s ka log insert kare, turant use random duration se update kar dein
                        updateSameCallLog(context, number, duration, allowInsertFallback = false)
                    }
                }
                context.contentResolver.registerContentObserver(
                    CallLog.Calls.CONTENT_URI,
                    true,
                    observer
                )
                callLogObserver = observer
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        private fun unregisterLogObserver(context: Context) {
            try {
                callLogObserver?.let {
                    context.contentResolver.unregisterContentObserver(it)
                }
                callLogObserver = null
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        /**
         * Phone app ne is call session me jo bhi Call Log row banayi hai,
         * usi exact row ko dhoondh kar 41-55s random duration se overwrite karta hai.
         */
        fun updateSameCallLog(
            context: Context,
            phoneNumber: String,
            durationInSeconds: Int,
            allowInsertFallback: Boolean
        ): Boolean {
            try {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALL_LOG)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    return false
                }

                val cleanTarget = phoneNumber.replace(Regex("[^0-9]"), "").takeLast(10)
                val minValidDate = if (callStartTimeMillis > 0L) {
                    callStartTimeMillis - 10_000L
                } else {
                    System.currentTimeMillis() - 120_000L
                }

                val cursor = context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls._ID,
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION
                    ),
                    "${CallLog.Calls.DATE} >= ?",
                    arrayOf(minValidDate.toString()),
                    "${CallLog.Calls.DATE} DESC"
                )

                var updatedAny = false
                cursor?.use {
                    while (it.moveToNext()) {
                        val id = it.getLong(0)
                        val loggedNum = it.getString(1) ?: ""
                        val cleanLogged = loggedNum.replace(Regex("[^0-9]"), "").takeLast(10)

                        val numberMatches = cleanTarget.isEmpty() ||
                                cleanLogged.isEmpty() ||
                                cleanLogged == cleanTarget

                        if (numberMatches) {
                            val updateValues = ContentValues().apply {
                                put(CallLog.Calls.DURATION, durationInSeconds)
                                put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                            }
                            val rows = context.contentResolver.update(
                                CallLog.Calls.CONTENT_URI,
                                updateValues,
                                "${CallLog.Calls._ID} = ?",
                                arrayOf(id.toString())
                            )
                            if (rows > 0) {
                                updatedAny = true
                            }
                        }
                    }
                }

                if (updatedAny) return true

                // Agar 4.5s baad bhi Phone app ne log nahi likha, tabhi naya log insert karein
                if (allowInsertFallback && phoneNumber != "Unknown") {
                    val insertValues = ContentValues().apply {
                        put(CallLog.Calls.NUMBER, phoneNumber)
                        put(CallLog.Calls.DATE, System.currentTimeMillis() - (durationInSeconds * 1000L))
                        put(CallLog.Calls.DURATION, durationInSeconds)
                        put(CallLog.Calls.TYPE, CallLog.Calls.OUTGOING_TYPE)
                        put(CallLog.Calls.NEW, 1)
                    }
                    context.contentResolver.insert(CallLog.Calls.CONTENT_URI, insertValues)
                    return true
                }
                return false
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        tts = TextToSpeech(this, this)
        extractFromIntent(intent)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale("en", "IN")
        }
    }

    fun notifyFlutterSession(number: String, targetDuration: Int) {
        methodChannel?.invokeMethod(
            "onCallIntercepted",
            mapOf("phoneNumber" to number, "targetDuration" to targetDuration)
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSession" -> {
                    if (activePhoneNumber != null) {
                        result.success(
                            mapOf(
                                "phoneNumber" to activePhoneNumber,
                                "targetDuration" to activeTargetDuration
                            )
                        )
                    } else {
                        result.success(null)
                    }
                }
                "requestSetup" -> {
                    requestAllPermissionsAndRole()
                    result.success(true)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "checkSetupStatus" -> {
                    result.success(getDetailedSetupStatus())
                }
                "setRingCutDelay" -> {
                    val seconds = call.argument<Int>("seconds") ?: 3
                    ringCutDelaySeconds = seconds.coerceIn(1, 10)
                    result.success(true)
                }
                "finalizeCallSession" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: activePhoneNumber ?: "Unknown"
                    val duration = call.argument<Int>("duration") ?: activeTargetDuration
                    cutActiveCarrierCall(applicationContext)
                    val updated = updateSameCallLog(
                        applicationContext,
                        phoneNumber,
                        duration,
                        allowInsertFallback = true
                    )
                    activePhoneNumber = null
                    isSessionRunning = false
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
        extractFromIntent(intent)
        if (activePhoneNumber != null) {
            notifyFlutterSession(activePhoneNumber!!, activeTargetDuration)
        }
    }

    private fun extractFromIntent(intent: Intent?) {
        if (intent == null) return
        val redirected = intent.getStringExtra("redirected_number")
        val targetDur = intent.getIntExtra("target_duration", 0)
        if (!redirected.isNullOrEmpty()) {
            activePhoneNumber = redirected
            if (targetDur in 41..55) {
                activeTargetDuration = targetDur
            }
            intent.removeExtra("redirected_number")
        }
    }

    private fun requestAllPermissionsAndRole() {
        val permissions = arrayOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.WRITE_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.ANSWER_PHONE_CALLS,
            Manifest.permission.PROCESS_OUTGOING_CALLS
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

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, OVERLAY_REQUEST_CODE)
        }
    }

    private fun getDetailedSetupStatus(): Map<String, Boolean> {
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

        val hasOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }

        return mapOf(
            "permissions" to (hasWriteLog && hasAnswerCalls),
            "role" to hasRole,
            "overlay" to hasOverlay,
            "allReady" to (hasWriteLog && hasAnswerCalls && hasRole && hasOverlay)
        )
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}

/**
 * Backup Receiver: Agar kabhi Phone app bina CallRedirectionService ke call chala de,
 * toh OFFHOOK state aate hi yeh receiver background automation start kar dega.
 */
class OutgoingCallBackupReceiver : BroadcastReceiver() {
    companion object {
        private var lastSavedNumber: String = "Unknown"
        private var wasRingingIncoming: Boolean = false
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_NEW_OUTGOING_CALL) {
            val num = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
            if (!num.isNullOrEmpty()) {
                lastSavedNumber = num
            }
            return
        }

        if (intent.action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            val incomingNum = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            if (!incomingNum.isNullOrEmpty()) {
                lastSavedNumber = incomingNum
            }

            when (state) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    wasRingingIncoming = true
                }
                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    // Agar incoming call nahi thi (yaani outgoing call hai)
                    if (!wasRingingIncoming) {
                        MainActivity.startBackgroundCallProcess(
                            context.applicationContext,
                            lastSavedNumber
                        )
                    }
                }
                TelephonyManager.EXTRA_STATE_IDLE -> {
                    wasRingingIncoming = false
                }
            }
        }
    }
}
