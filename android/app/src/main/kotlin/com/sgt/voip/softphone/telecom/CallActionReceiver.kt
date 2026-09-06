package com.sgt.voip.softphone.telecom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.sgt.voip.softphone.MainActivity

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallActionReceiver"
        var actionListener: ((action: String, callUuid: String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val callUuid = intent.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID) ?: ""
        Log.i(TAG, "onReceive: action=$action, callUuid=$callUuid")

        when (action) {
            CallNotificationHelper.ACTION_ANSWER -> {
                CallForegroundService.stopCall(context)
                actionListener?.invoke("answer", callUuid)

                // Launch MainActivity into foreground to handle call
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(CallNotificationHelper.EXTRA_CALL_UUID, callUuid)
                    putExtra("call_action", "answer")
                }
                context.startActivity(launchIntent)
            }
            CallNotificationHelper.ACTION_DECLINE -> {
                CallForegroundService.stopCall(context)
                actionListener?.invoke("decline", callUuid)
            }
        }
    }
}
