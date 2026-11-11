package com.mohammed.focus_lock

import android.Manifest
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Empty receiver: lets the app be registered as Device Owner via adb
class FocusAdmin : DeviceAdminReceiver()

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var listening = false

    // The session lives in native storage so it survives app kill / reboot
    private val prefs by lazy { getSharedPreferences("strict", MODE_PRIVATE) }

    private fun endMillis() = prefs.getLong("end", 0L)
    private fun sessionActive() = endMillis() > System.currentTimeMillis()

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "focus_lock")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // args: end (epoch ms), type ("web"/"local"), target (url or file path)
                "startLock" -> {
                    prefs.edit()
                        .putLong("end", (call.argument<Number>("end"))!!.toLong())
                        .putString("type", call.argument<String>("type"))
                        .putString("target", call.argument<String>("target"))
                        .apply()
                    askPermissions()
                    enforceLock()
                    listenCalls()
                    result.success(true)
                }
                "stopLock" -> {
                    prefs.edit().clear().apply()
                    try { stopLockTask() } catch (e: Exception) {}
                    result.success(true)
                }
                // Returns the saved session so Dart can resume it after a restart
                "getSession" -> {
                    if (sessionActive()) {
                        listenCalls()
                        result.success(mapOf(
                            "end" to endMillis(),
                            "type" to prefs.getString("type", ""),
                            "target" to prefs.getString("target", "")
                        ))
                    } else {
                        prefs.edit().clear().apply()
                        result.success(null)
                    }
                }
                "answerCall" -> {
                    if (hasPerm(Manifest.permission.ANSWER_PHONE_CALLS)) {
                        getSystemService(TelecomManager::class.java).acceptRingingCall()
                    }
                    result.success(true)
                }
                // Is our accessibility service switched on?
                "isAccessibilityEnabled" -> {
                    val on = android.provider.Settings.Secure.getString(
                        contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                    ) ?: ""
                    result.success(on.contains("$packageName/"))
                }
                "openAccessibilitySettings" -> {
                    startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "isDeviceOwner" -> {
                    val dpm = getSystemService(DevicePolicyManager::class.java)
                    result.success(dpm.isDeviceOwnerApp(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    // Re-enter lock whenever the app comes back during an active session
    override fun onResume() {
        super.onResume()
        if (sessionActive()) enforceLock()
    }

    private fun enforceLock() {
        val dpm = getSystemService(DevicePolicyManager::class.java)
        if (dpm.isDeviceOwnerApp(packageName)) {
            // Device Owner = real kiosk: no dialog, no exit gesture, no power menu
            val admin = ComponentName(this, FocusAdmin::class.java)
            dpm.setLockTaskPackages(admin, arrayOf(packageName))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dpm.setLockTaskFeatures(admin, 0) // disable every system UI feature
            }
        }
        try { startLockTask() } catch (e: Exception) {}
    }

    private fun hasPerm(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun askPermissions() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ANSWER_PHONE_CALLS, Manifest.permission.READ_PHONE_STATE),
            1
        )
    }

    // Send call state to Flutter (1 = ringing)
    private fun listenCalls() {
        if (listening || !hasPerm(Manifest.permission.READ_PHONE_STATE)) return
        listening = true
        val tm = getSystemService(TelephonyManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            tm.registerTelephonyCallback(mainExecutor, object : TelephonyCallback(),
                TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    channel.invokeMethod("callState", state)
                }
            })
        } else {
            @Suppress("DEPRECATION")
            tm.listen(object : PhoneStateListener() {
                @Deprecated("old api")
                override fun onCallStateChanged(state: Int, number: String?) {
                    channel.invokeMethod("callState", state)
                }
            }, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }
}
