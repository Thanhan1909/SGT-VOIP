package com.sgt.voip.softphone

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.sgt.voip.softphone.telecom.CallActionReceiver
import com.sgt.voip.softphone.telecom.CallForegroundService
import com.sgt.voip.softphone.telecom.CallNotificationHelper
import com.sgt.voip.softphone.telecom.SgtFirebaseMessagingService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL_NAME = "com.sgt.voip.softphone/native_call"
    var methodChannel: MethodChannel? = null

    companion object {
        private const val PERMISSION_REQUEST_POST_NOTIFICATIONS = 2026
        var activeInstance: MainActivity? = null

        fun notifyCallAction(action: String, callUuid: String) {
            activeInstance?.runOnUiThread {
                activeInstance?.dispatchCallAction(action, callUuid)
            }
        }

        fun notifyVoipToken(token: String) {
            activeInstance?.runOnUiThread {
                activeInstance?.methodChannel?.invokeMethod("onVoipToken", mapOf("token" to token))
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
        configureLockScreenFlags()
        saveIntentAction(intent)
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
                "getPendingCallAction" -> {
                    val prefs = getSharedPreferences(CallActionReceiver.PREFS_PENDING, Context.MODE_PRIVATE)
                    val action = prefs.getString(CallActionReceiver.KEY_ACTION, null)
                    val uuid = prefs.getString(CallActionReceiver.KEY_UUID, null)
                    if (!action.isNullOrBlank() && !uuid.isNullOrBlank()) {
                        prefs.edit().clear().apply()
                        result.success(mapOf("action" to action, "callUuid" to uuid))
                    } else {
                        result.success(null)
                    }
                }
                "ackCallAction" -> {
                    val prefs = getSharedPreferences(CallActionReceiver.PREFS_PENDING, Context.MODE_PRIVATE)
                    prefs.edit().clear().apply()
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                PERMISSION_REQUEST_POST_NOTIFICATIONS
                            )
                        }
                        result.success(granted)
                    } else {
                        result.success(true)
                    }
                }
                "getVoipToken" -> {
                    val token = SgtFirebaseMessagingService.getSavedToken(this)
                    result.success(token)
                }
                else -> result.notImplemented()
            }
        }

        CallActionReceiver.actionListener = { action, callUuid ->
            runOnUiThread {
                dispatchCallAction(action, callUuid)
            }
        }

        // Process any launch intent after Flutter engine is fully initialized
        dispatchIntentAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        saveIntentAction(intent)
        dispatchIntentAction(intent)
    }

    private var lastDispatchedActionKey: String? = null
    private var lastDispatchedTimeMs: Long = 0L

    private fun saveIntentAction(intent: Intent?) {
        val action = intent?.getStringExtra("call_action")
        val callUuid = intent?.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID)
        if (!action.isNullOrBlank() && !callUuid.isNullOrBlank()) {
            val prefs = getSharedPreferences(CallActionReceiver.PREFS_PENDING, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(CallActionReceiver.KEY_ACTION, action)
                .putString(CallActionReceiver.KEY_UUID, callUuid)
                .apply()
        }
    }

    fun dispatchCallAction(action: String, callUuid: String) {
        if (action.isNotBlank() && callUuid.isNotBlank()) {
            val key = "$action:$callUuid"
            val now = android.os.SystemClock.elapsedRealtime()
            if (key == lastDispatchedActionKey && (now - lastDispatchedTimeMs) < 3000L) {
                Log.d("MainActivity", "Duplicate call action suppressed: $key")
                return
            }
            lastDispatchedActionKey = key
            lastDispatchedTimeMs = now
            methodChannel?.invokeMethod("onCallAction", mapOf("action" to action, "callUuid" to callUuid))
        }
    }

    private fun dispatchIntentAction(intent: Intent?) {
        val action = intent?.getStringExtra("call_action")
        val callUuid = intent?.getStringExtra(CallNotificationHelper.EXTRA_CALL_UUID)
        if (!action.isNullOrBlank() && !callUuid.isNullOrBlank()) {
            intent.removeExtra("call_action")
            intent.removeExtra(CallNotificationHelper.EXTRA_CALL_UUID)
            dispatchCallAction(action, callUuid)
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
        if (activeInstance == this) {
            activeInstance = null
        }
        CallActionReceiver.actionListener = null
        super.onDestroy()
    }
}
