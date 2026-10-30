package com.example.suggestion_dialer

import android.Manifest
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.telecom.Call
import android.telecom.TelecomManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

object CallStateHolder {
    var bypassNextInterception: Boolean = false
    var activeCall: Call? = null
}

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "com.example.suggestion_dialer/call_channel"
    private var methodChannel: MethodChannel? = null
    private var pendingPhoneNumber: String? = null
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
        extractNumberFromIntent(intent)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            isTtsReady = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialNumber" -> {
                    val number = pendingPhoneNumber
                    pendingPhoneNumber = null
                    result.success(number)
                }
                "requestPermissions" -> {
                    requestCallPermissions()
                    result.success(true)
                }
                "requestCallRedirectionRole" -> {
                    requestRole(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                            RoleManager.ROLE_CALL_REDIRECTION
                        else ""
                    )
                    result.success(true)
                }
                "requestDefaultDialerRole" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        requestRole(RoleManager.ROLE_DIALER)
                    } else {
                        val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                            putExtra(
                                TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                                packageName
                            )
                        }
                        startActivityForResult(intent, 1002)
                    }
                    result.success(true)
                }
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (isTtsReady && text.isNotEmpty()) {
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "suggestion_id")
                    }
                    result.success(true)
                }
                "stopSpeaking" -> {
                    tts?.stop()
                    result.success(true)
                }
                "placeRealCall" -> {
                    val number = call.argument<String>("number") ?: ""
                    placeActualPhoneCall(number)
                    result.success(true)
                }
                "hangupActiveCall" -> {
                    CallStateHolder.activeCall?.disconnect()
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
        pendingPhoneNumber?.let { number ->
            methodChannel?.invokeMethod("onIncomingDial", number)
            pendingPhoneNumber = null
        }
    }

    private fun extractNumberFromIntent(intent: Intent?) {
        if (intent == null) return

        val redirected = intent.getStringExtra("redirected_number")
        if (!redirected.isNullOrBlank()) {
            pendingPhoneNumber = redirected
            return
        }

        val data: Uri? = intent.data
        if (data != null && data.scheme == "tel") {
            val number = data.schemeSpecificPart
            if (!number.isNullOrBlank()) {
                pendingPhoneNumber = number
            }
        }
    }

    private fun requestCallPermissions() {
        val permissions = arrayOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_PHONE_STATE
        )
        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), 1001)
        }
    }

    private fun requestRole(roleName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && roleName.isNotEmpty()) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null &&
                roleManager.isRoleAvailable(roleName) &&
                !roleManager.isRoleHeld(roleName)
            ) {
                val roleIntent = roleManager.createRequestRoleIntent(roleName)
                startActivityForResult(roleIntent, 1003)
            }
        }
    }

    private fun placeActualPhoneCall(number: String) {
        if (number.isBlank()) return
        CallStateHolder.bypassNextInterception = true

        val uri = Uri.fromParts("tel", number, null)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecomManager.placeCall(uri, Bundle())
        } else {
            val dialIntent = Intent(Intent.ACTION_DIAL, uri)
            startActivity(dialIntent)
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
