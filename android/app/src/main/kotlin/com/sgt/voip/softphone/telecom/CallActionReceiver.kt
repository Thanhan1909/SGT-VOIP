package com.sgt.voip.softphone.telecom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.sgt.voip.softphone.MainActivity

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallActionReceiver"
        const val PREFS_PENDING = "sgt_pending_actions"
        const val KEY_ACTION = "pending_action"
        const val KEY_UUID = "pending_uuid"
        var actionListener: ((action: String, callUuid: String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val callUuid = intent.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID) ?: ""
        Log.i(TAG, "onReceive: action=$action, callUuid=$callUuid")

        val actionStr = if (action == CallNotificationHelper.ACTION_ANSWER) "answer" else "decline"

        // 1. Persist action in SharedPreferences so cold-start engine can read and ACK
        val prefs = context.getSharedPreferences(PREFS_PENDING, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_ACTION, actionStr)
            .putString(KEY_UUID, callUuid)
            .apply()

        // 2. Stop foreground notification service
        CallForegroundService.stopCall(context)

        // 3. Notify static listener if present
        actionListener?.invoke(actionStr, callUuid)

        // 4. Notify active MainActivity if running
        MainActivity.notifyCallAction(actionStr, callUuid)

        // 5. If answering, bring MainActivity to foreground
        if (action == CallNotificationHelper.ACTION_ANSWER) {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(CallNotificationHelper.EXTRA_CALL_UUID, callUuid)
                putExtra("call_action", "answer")
            }
            context.startActivity(launchIntent)
        }
    }
}
