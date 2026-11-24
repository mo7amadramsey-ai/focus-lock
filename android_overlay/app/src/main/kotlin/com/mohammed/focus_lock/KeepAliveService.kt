package com.mohammed.focus_lock

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

// Foreground service (type "data sync") that only keeps the app process alive while downloads run,
// so downloads continue when the app is in the background or the screen is off. It shows an ongoing notification.
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra("text") ?: "جاري التنزيل"
        val n = Notifier.build(this, "Focus Lock", text, 7002)
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(7002, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(7002, n)
        } catch (e: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }
}
