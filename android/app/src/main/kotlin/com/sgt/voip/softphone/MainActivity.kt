package com.sgt.voip.softphone

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.sgt.voip.softphone.telecom.CallActionReceiver
import com.sgt.voip.softphone.telecom.CallForegroundService
import com.sgt.voip.softphone.telecom.CallNotificationHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL_NAME = "com.sgt.voip.softphone/native_call"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenFlags()
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showIncomingCall" -> {
                    val callUuid = call.argument<String>("callUuid") ?: ""
                    val callerName = call.argument<String>("callerName") ?: ""
                    val callerNumber = call.argument<String>("callerNumber") ?: ""
                    CallForegroundService.startIncomingCall(this, callUuid, callerName, callerNumber)
                    result.success(true)
                }
                "dismissIncomingCall" -> {
                    CallForegroundService.stopCall(this)
                    result.success(true)
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }

        CallActionReceiver.actionListener = { action, callUuid ->
            runOnUiThread {
                methodChannel?.invokeMethod("onCallAction", mapOf("action" to action, "callUuid" to callUuid))
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val action = intent?.getStringExtra("call_action")
        val callUuid = intent?.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID)
        if (!action.isNullOrBlank() && !callUuid.isNullOrBlank()) {
            methodChannel?.invokeMethod("onCallAction", mapOf("action" to action, "callUuid" to callUuid))
        }
    }

    private fun configureLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun onDestroy() {
        CallActionReceiver.actionListener = null
        super.onDestroy()
    }
}
