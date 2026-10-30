package com.example.suggestion_dialer

import android.annotation.TargetApi
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telecom.CallRedirectionService
import android.telecom.PhoneAccountHandle

@TargetApi(Build.VERSION_CODES.Q)
class MyCallRedirectionService : CallRedirectionService() {

    override fun onPlaceCall(
        handle: Uri,
        initialPhoneAccount: PhoneAccountHandle,
        allowInteractiveResponse: Boolean
    ) {
        // 1. Asli network call ko yahin rok dein taaki samne wale ko call na jaye
        cancelCall()

        // 2. Dial kiya gaya number nikalein
        val phoneNumber = handle.schemeSpecificPart ?: "Unknown"

        // 3. Turant MainActivity (Live Timer Screen) open karein
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("redirected_number", phoneNumber)
        }
        startActivity(launchIntent)
    }
}
