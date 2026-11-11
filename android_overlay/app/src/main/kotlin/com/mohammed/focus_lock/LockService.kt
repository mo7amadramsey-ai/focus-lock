package com.mohammed.focus_lock

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.net.Uri
import android.telecom.TelecomManager
import android.view.accessibility.AccessibilityEvent

// During an active strict session, any window that is not ours (home, recents,
// settings, other apps, notification shade, power menu) pulls the app back to the front.
// It checks the saved end time itself, so it always stops when the timer ends.
class LockService : AccessibilityService() {

    // Only calling is allowed: dialer (keypad), contacts, and the in-call screen
    private val allowed: Set<String> by lazy {
        val set = mutableSetOf(
            "com.android.incallui", "com.google.android.dialer", "com.android.dialer",
            "com.android.server.telecom", "com.samsung.android.incallui", "com.android.phone",
            "com.android.contacts", "com.google.android.contacts", "com.samsung.android.dialer",
            "com.samsung.android.contacts", "com.android.providers.contacts"
        )
        // The phone's real default dialer
        try { getSystemService(TelecomManager::class.java).defaultDialerPackage?.let { set.add(it) } } catch (e: Exception) {}
        // Whatever app handles "dial" and "contacts" on this phone
        listOf(
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:")),
            Intent(Intent.ACTION_VIEW, Uri.parse("content://contacts/people/"))
        ).forEach { i ->
            packageManager.resolveActivity(i, 0)?.activityInfo?.packageName?.let { set.add(it) }
        }
        set
    }

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        val prefs = getSharedPreferences("strict", MODE_PRIVATE)
        if (prefs.getLong("end", 0L) <= System.currentTimeMillis()) return // no active session
        val pkg = e?.packageName?.toString() ?: return
        if (pkg == packageName || pkg in allowed) return
        // Bring our activity back to the front
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        )
    }

    override fun onInterrupt() {}
}
