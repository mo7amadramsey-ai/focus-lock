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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Empty receiver: lets the app be registered as Device Owner via adb
class FocusAdmin : DeviceAdminReceiver()

class MainActivity : FlutterFragmentActivity() {
    private lateinit var channel: MethodChannel
    private var listening = false
    private var incoming: String? = null // file opened from Drive / another app

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
                // Extend the running (or just-expired) session: new end time, lock again
                "extendLock" -> {
                    prefs.edit().putLong("end", (call.argument<Number>("end"))!!.toLong()).apply()
                    enforceLock()
                    result.success(true)
                }
                // Timer ended: release kiosk mode but keep the session data so it can be extended
                "releaseLock" -> {
                    try { stopLockTask() } catch (e: Exception) {}
                    result.success(true)
                }
                // Path of a file that another app (Drive) sent to us, once
                "takeIncoming" -> {
                    val p = incoming
                    incoming = null
                    result.success(p)
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
                // Opens the phone's dialer (keypad + contacts) for emergency calls
                "openDialer" -> {
                    startActivity(android.content.Intent(android.content.Intent.ACTION_DIAL)
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                // Opens ONLY the Google Drive app (never a browser or other app)
                "openDrive" -> {
                    val i = packageManager.getLaunchIntentForPackage("com.google.android.apps.docs")
                    if (i != null) {
                        i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } else {
                        result.success(false) // Drive not installed
                    }
                }
                "isDeviceOwner" -> {
                    val dpm = getSystemService(DevicePolicyManager::class.java)
                    result.success(dpm.isDeviceOwnerApp(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        grabIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        grabIntent(intent)
    }

    // Copies a file shared/opened from Drive into our cache so Dart can import it
    @Suppress("DEPRECATION")
    private fun grabIntent(i: android.content.Intent?) {
        if (i == null) return
        val uri: android.net.Uri = when (i.action) {
            android.content.Intent.ACTION_VIEW -> i.data
            android.content.Intent.ACTION_SEND -> i.getParcelableExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        try {
            var name = "file"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val ix = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (ix >= 0 && c.moveToFirst()) name = c.getString(ix) ?: "file"
            }
            val dir = java.io.File(cacheDir, "incoming")
            dir.mkdirs()
            val out = java.io.File(dir, name.replace(Regex("[/:*?<>|]"), "_"))
            contentResolver.openInputStream(uri)?.use { inp -> out.outputStream().use { inp.copyTo(it) } }
            incoming = out.absolutePath
        } catch (e: Exception) {}
    }

    // Re-enter lock whenever the app comes back during an active session
    override fun onResume() {
        super.onResume()
        if (sessionActive()) enforceLock()
    }

    private fun enforceLock() {
        val dpm = getSystemService(DevicePolicyManager::class.java)
        if (dpm.isDeviceOwnerApp(packageName)) {
            // Device Owner = real kiosk. The dialer is whitelisted so calls still work.
            val admin = ComponentName(this, FocusAdmin::class.java)
            val dialer = try { getSystemService(TelecomManager::class.java).defaultDialerPackage } catch (e: Exception) { null }
            dpm.setLockTaskPackages(admin, listOfNotNull(packageName, dialer, "com.google.android.apps.docs").toTypedArray())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dpm.setLockTaskFeatures(admin, 0) // disable every system UI feature
            }
            try { startLockTask() } catch (e: Exception) {}
        }
        // Not Device Owner: plain screen pinning would block the dialer,
        // so the accessibility service (LockService) does the enforcing instead.
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
