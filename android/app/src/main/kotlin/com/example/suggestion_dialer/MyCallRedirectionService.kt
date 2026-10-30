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
        // Let the carrier network call start immediately (so call time starts counting)
        placeCallUnmodified()

        val phoneNumber = handle.schemeSpecificPart ?: "Unknown"
        
        // Launch your 1-minute suggestion UI instantly on top as an ongoing call screen
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("redirected_number", phoneNumber)
        }
        startActivity(launchIntent)
    }
}
