package com.mohammed.focus_lock

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

// Study reminders: assignment / exam / daily study notifications. They are scheduled with AlarmManager,
// so they fire with the app closed, and are re-armed after a phone restart.
object Notifier {
    private const val CH = "fl_reminders"
    private const val PREFS = "fl_reminders"

    private fun channel(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = c.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CH, "تذكيرات الدراسة", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    fun show(c: Context, id: Int, title: String, body: String) {
        channel(c)
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName)
        val tap = PendingIntent.getActivity(c, id, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification26.builder(c, CH) else android.app.Notification.Builder(c)
        b.setSmallIcon(c.applicationInfo.icon).setContentTitle(title).setContentText(body)
            .setContentIntent(tap).setAutoCancel(true)
        try { c.getSystemService(NotificationManager::class.java).notify(id, b.build()) } catch (e: Exception) {}
    }

    private fun alarm(c: Context, id: Int, at: Long, title: String, body: String) {
        val i = Intent(c, ReminderReceiver::class.java).putExtra("id", id).putExtra("title", title).putExtra("body", body)
        val pi = PendingIntent.getBroadcast(c, id, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
    }

    private fun cancel(c: Context, id: Int) {
        val i = Intent(c, ReminderReceiver::class.java)
        val pi = PendingIntent.getBroadcast(c, id, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE) ?: return
        (c.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pi)
        pi.cancel()
    }

    // Replaces every scheduled reminder with this list: [{id, at, title, body}]
    fun set(c: Context, json: String) {
        val p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        try {
            val old = JSONArray(p.getString("items", "[]"))
            for (k in 0 until old.length()) cancel(c, old.getJSONObject(k).getInt("id"))
        } catch (e: Exception) {}
        p.edit().putString("items", json).apply()
        arm(c, json)
    }

    private fun arm(c: Context, json: String) {
        val now = System.currentTimeMillis()
        try {
            val a = JSONArray(json)
            for (k in 0 until a.length()) {
                val o: JSONObject = a.getJSONObject(k)
                val at = o.getLong("at")
                if (at > now) alarm(c, o.getInt("id"), at, o.getString("title"), o.getString("body"))
            }
        } catch (e: Exception) {}
    }

    fun rearm(c: Context) = arm(c, c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("items", "[]") ?: "[]")
}

object Notification26 {
    fun builder(c: Context, ch: String): android.app.Notification.Builder = android.app.Notification.Builder(c, ch)
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) { Notifier.rearm(c); return }
        Notifier.show(c, i.getIntExtra("id", 1), i.getStringExtra("title") ?: "", i.getStringExtra("body") ?: "")
    }
}
