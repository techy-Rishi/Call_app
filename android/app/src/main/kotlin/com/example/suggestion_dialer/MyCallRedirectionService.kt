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

        // Call ko unmodified jane dein taaki system block na kare
        placeCallUnmodified()

        // Persistent SharedPreferences se check karein ki dialer active hai ya nahi
        if (MainActivity.getSavedActiveState(applicationContext)) {
            MainActivity.startBackgroundCallProcess(applicationContext, phoneNumber)
        }
    }
}
