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
        // If the user clicked "Call Real Number Now" inside our app, let the call go through
        if (CallStateHolder.bypassNextInterception) {
            CallStateHolder.bypassNextInterception = false
            placeCallUnmodified()
            return
        }

        // Otherwise, cancel the network call and launch our Suggestion UI
        cancelCall()

        val phoneNumber = handle.schemeSpecificPart ?: "Unknown"
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("redirected_number", phoneNumber)
        }
        startActivity(launchIntent)
    }
}
