package com.example.suggestion_dialer

import android.annotation.TargetApi
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.CallRedirectionService
import android.telecom.PhoneAccountHandle

@TargetApi(Build.VERSION_CODES.Q)
class MyCallRedirectionService : CallRedirectionService() {

    override fun onPlaceCall(
        handle: Uri,
        initialPhoneAccount: PhoneAccountHandle,
        allowInteractiveResponse: Boolean
    ) {
        val phoneNumber = handle.schemeSpecificPart ?: "Unknown"

        // 1. Asli call ko lagne dein taaki JioFSM ko CALL_STATE_OFFHOOK mil jaye
        placeCallUnmodified()

        // 2. 600ms baad apni MainActivity screen upar open karein jo call ko auto-cut aur edit karegi
        Handler(Looper.getMainLooper()).postDelayed({
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("redirected_number", phoneNumber)
            }
            startActivity(launchIntent)
        }, 600)
    }
}
