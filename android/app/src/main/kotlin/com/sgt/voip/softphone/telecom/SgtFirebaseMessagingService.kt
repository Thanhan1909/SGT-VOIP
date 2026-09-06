package com.sgt.voip.softphone.telecom

import android.content.Context
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.sgt.voip.softphone.MainActivity

class SgtFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "SgtFirebaseMsgService"
        private const val PREFS_NAME = "sgt_voip_push_prefs"
        private const val KEY_FCM_TOKEN = "fcm_token"

        fun getSavedToken(context: Context): String? {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_FCM_TOKEN, null)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val maskedToken = if (token.length > 10) "${token.take(4)}...${token.takeLast(4)}" else "***"
        Log.i(TAG, "New FCM token received: $maskedToken")

        // Persist token locally
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_FCM_TOKEN, token)
            .apply()

        // Notify active Flutter engine if available
        MainActivity.notifyVoipToken(token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        if (data.isEmpty()) {
            Log.w(TAG, "Received FCM message with empty data payload")
            return
        }

        val action = data["action"] ?: "incoming_call"
        val callUuid = data["call_uuid"] ?: ""
        val callerName = data["caller_display_name"] ?: ""
        val callerNumber = data["caller_extension"] ?: ""

        Log.i(TAG, "onMessageReceived: action=$action, callUuid=$callUuid")

        // 1. Check TTL / stale push
        val timestampStr = data["timestamp"]
        if (!timestampStr.isNullOrBlank()) {
            val sentTime = timestampStr.toDoubleOrNull()?.toLong() ?: 0L
            val now = System.currentTimeMillis() / 1000
            val ttl = data["ttl_seconds"]?.toLongOrNull() ?: 30L
            if (sentTime > 0 && (now - sentTime) > ttl) {
                Log.w(TAG, "Ignoring stale push notification: age=${now - sentTime}s > ttl=${ttl}s")
                return
            }
        }

        // 2. Handle remote cancel
        if (action == "cancel_call") {
            Log.i(TAG, "Remote cancel received for call UUID: $callUuid")
            CallForegroundService.stopCall(this)
            CallNotificationHelper.dismissCallNotification(this)
            MainActivity.notifyCallAction("cancel", callUuid)
            return
        }

        // 3. Handle incoming call with deduplication
        if (callUuid.isBlank()) {
            Log.w(TAG, "Incoming push missing call_uuid, dropping")
            return
        }

        if (CallForegroundService.currentCallUuid == callUuid) {
            Log.i(TAG, "Call UUID $callUuid is already ringing, ignoring duplicate push")
            return
        }

        // Launch CallStyle / ForegroundService
        CallForegroundService.startIncomingCall(this, callUuid, callerName, callerNumber)

        // Forward to Flutter engine if active
        MainActivity.notifyCallAction("incoming_push", callUuid)
    }
}
