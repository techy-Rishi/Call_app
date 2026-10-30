package com.example.suggestion_dialer

import android.telecom.Call
import android.telecom.InCallService

class MyInCallService : InCallService() {
    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
    }
}
