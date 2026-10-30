package com.example.suggestion_dialer

import android.telecom.Call
import android.telecom.InCallService

class MyInCallService : InCallService() {
    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            if (state == Call.STATE_DISCONNECTED) {
                CallStateHolder.activeCall = null
            }
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallStateHolder.activeCall = call
        call.registerCallback(callCallback)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(callCallback)
        if (CallStateHolder.activeCall == call) {
            CallStateHolder.activeCall = null
        }
    }
}
