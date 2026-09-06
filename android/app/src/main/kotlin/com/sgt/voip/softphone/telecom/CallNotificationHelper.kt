package com.sgt.voip.softphone.telecom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.annotation.RequiresApi
import com.sgt.voip.softphone.MainActivity
import com.sgt.voip.softphone.R

object CallNotificationHelper {
    const val CHANNEL_ID = "sgt_voip_incoming_calls"
    const val CHANNEL_NAME = "Cuộc gọi đến"
    const val NOTIFICATION_ID = 2026

    const val ACTION_ANSWER = "com.sgt.voip.softphone.ACTION_ANSWER_CALL"
    const val ACTION_DECLINE = "com.sgt.voip.softphone.ACTION_DECLINE_CALL"
    const val EXTRA_CALL_UUID = "extra_call_uuid"
    const val EXTRA_CALLER_NAME = "extra_caller_name"
    const val EXTRA_CALLER_NUMBER = "extra_caller_number"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .build()

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Thông báo cuộc gọi đến SGT Softphone"
                    setSound(ringtoneUri, audioAttributes)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 800, 800, 800)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
            }
        }
    }

    fun buildIncomingCallNotification(
        context: Context,
        callUuid: String,
        callerName: String,
        callerNumber: String
    ): Notification {
        createNotificationChannel(context)

        // Intent when tapping the notification body -> Open MainActivity
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CALL_UUID, callUuid)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            101,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Full screen intent for lock screen wakeup
        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CALL_UUID, callUuid)
            putExtra("is_full_screen_call", true)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            102,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Answer PendingIntent (sent to BroadcastReceiver)
        val answerIntent = Intent(context, CallActionReceiver::class.java).apply {
            action = ACTION_ANSWER
            putExtra(EXTRA_CALL_UUID, callUuid)
        }
        val answerPendingIntent = PendingIntent.getBroadcast(
            context,
            103,
            answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Decline PendingIntent (sent to BroadcastReceiver)
        val declineIntent = Intent(context, CallActionReceiver::class.java).apply {
            action = ACTION_DECLINE
            putExtra(EXTRA_CALL_UUID, callUuid)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            104,
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val displayName = if (callerName.isNotBlank() && callerName != callerNumber) {
            "$callerName ($callerNumber)"
        } else {
            "Extension $callerNumber"
        }

        // Android 12+ (API 31+) CallStyle Notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callerPerson = Person.Builder()
                .setName(displayName)
                .setImportant(true)
                .build()

            val callStyle = Notification.CallStyle.forIncomingCall(
                callerPerson,
                declinePendingIntent,
                answerPendingIntent
            )

            return Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setContentTitle("Cuộc gọi đến")
                .setContentText(displayName)
                .setContentIntent(contentPendingIntent)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setStyle(callStyle)
                .setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .build()
        }

        // Android 8.0 - 11 fallback
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Cuộc gọi đến")
            .setContentText(displayName)
            .setContentIntent(contentPendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            val declineAction = Notification.Action.Builder(
                null,
                "Từ chối",
                declinePendingIntent
            ).build()

            val answerAction = Notification.Action.Builder(
                null,
                "Trả lời",
                answerPendingIntent
            ).build()

            builder.addAction(declineAction)
            builder.addAction(answerAction)
        }

        return builder.build()
    }

    fun dismissCallNotification(context: Context) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }
}
