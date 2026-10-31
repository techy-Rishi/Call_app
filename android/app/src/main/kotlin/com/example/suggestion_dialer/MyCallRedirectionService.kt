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

        // 1. Asli call jane dein taaki JioFSM ko CALL_STATE_OFFHOOK mil jaye
        placeCallUnmodified()

        // 2. Turant Background Engine start karein (bina app manually khole bhi kaam karega)
        MainActivity.startBackgroundCallProcess(applicationContext, phoneNumber)
    }
}
