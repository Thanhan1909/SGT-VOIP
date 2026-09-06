package com.sgt.voip.softphone.telecom

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

class CallForegroundService : Service() {

    companion object {
        private const val TAG = "CallForegroundService"
        const val ACTION_START_INCOMING = "com.sgt.voip.softphone.ACTION_START_INCOMING_CALL"
        const val ACTION_STOP_CALL = "com.sgt.voip.softphone.ACTION_STOP_CALL"

        fun startIncomingCall(context: Context, callUuid: String, callerName: String, callerNumber: String) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START_INCOMING
                putExtra(CallNotificationHelper.EXTRA_CALL_UUID, callUuid)
                putExtra(CallNotificationHelper.EXTRA_CALLER_NAME, callerName)
                putExtra(CallNotificationHelper.EXTRA_CALLER_NUMBER, callerNumber)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start foreground service: ${e.message}")
            }
        }

        fun stopCall(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_STOP_CALL
            }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop call service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        when (action) {
            ACTION_START_INCOMING -> {
                val callUuid = intent.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID) ?: ""
                val callerName = intent.getStringExtra(CallNotificationHelper.EXTRA_CALLER_NAME) ?: ""
                val callerNumber = intent.getStringExtra(CallNotificationHelper.EXTRA_CALLER_NUMBER) ?: ""

                val notification = CallNotificationHelper.buildIncomingCallNotification(
                    this,
                    callUuid,
                    callerName,
                    callerNumber
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val foregroundType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                    } else {
                        0
                    }
                    if (foregroundType != 0) {
                        startForeground(CallNotificationHelper.NOTIFICATION_ID, notification, foregroundType)
                    } else {
                        startForeground(CallNotificationHelper.NOTIFICATION_ID, notification)
                    }
                } else {
                    startForeground(CallNotificationHelper.NOTIFICATION_ID, notification)
                }
            }
            ACTION_STOP_CALL -> {
                CallNotificationHelper.dismissCallNotification(this)
                stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        CallNotificationHelper.dismissCallNotification(this)
        super.onDestroy()
    }
}
