package com.mohammed.focus_lock

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

// During an active strict session, any window that is not ours (home, recents,
// settings, other apps, notification shade, power menu) pulls the app back to the front.
// It checks the saved end time itself, so it always stops when the timer ends.
class LockService : AccessibilityService() {

    // Call UI must stay reachable so calls can be answered
    private val allowed = setOf(
        "com.android.incallui", "com.google.android.dialer", "com.android.dialer",
        "com.android.server.telecom", "com.samsung.android.incallui", "com.android.phone"
    )

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
