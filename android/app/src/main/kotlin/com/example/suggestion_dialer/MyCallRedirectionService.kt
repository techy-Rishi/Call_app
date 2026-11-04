package com.example.suggestion_dialer

import android.annotation.TargetApi
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
        val phoneNumber = handle.schemeSpecificPart ?: "Unknown"

        // Hamesha call ko unmodified jane do taaki network/system block na kare
        placeCallUnmodified()

        // Agar user ne dialer active rakha hai tabhi automation trigger karein
        if (MainActivity.isDialerActive) {
            MainActivity.startBackgroundCallProcess(applicationContext, phoneNumber)
        }
    }
}
