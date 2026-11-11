package com.mohammed.focus_lock

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.net.Uri
import android.telecom.TelecomManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Region
import android.graphics.RegionIterator
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView

// During an active strict session, any window that is not ours (home, recents,
// settings, other apps, notification shade, power menu) pulls the app back to the front.
// It checks the saved time-left itself, so it always stops when the timer ends
// (the timer only counts down while the video is playing).
class LockService : AccessibilityService() {

    // Only calling is allowed: dialer (keypad), contacts, and the in-call screen
    private val allowed: Set<String> by lazy {
        val set = mutableSetOf(
            "com.android.incallui", "com.google.android.dialer", "com.android.dialer",
            "com.android.server.telecom", "com.samsung.android.incallui", "com.android.phone",
            "com.android.contacts", "com.google.android.contacts", "com.samsung.android.dialer",
            "com.samsung.android.contacts", "com.android.providers.contacts",
            // Google Drive only (to view files) + its file picker
            "com.google.android.apps.docs", "com.google.android.documentsui", "com.android.documentsui"
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

    // ---------- Floating / split / pop-up windows of OTHER apps ----------
    // Phone-maker pop-up windows cannot be closed by a normal app, so instead every visible
    // app window that is not ours (or the call/Drive apps) is covered by an opaque black panel
    // drawn above it with an accessibility overlay. The panel also swallows all touches.
    private val handler = Handler(Looper.getMainLooper())
    private val panels = HashMap<String, View>()
    private var lastRelaunch = 0L

    private val ticker = object : Runnable {
        override fun run() {
            try { refresh() } catch (e: Exception) {}
            handler.postDelayed(this, 500)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        handler.removeCallbacks(ticker)
        drawPanels(emptyList())
        return super.onUnbind(intent)
    }

    private fun active() = getSharedPreferences("strict", MODE_PRIVATE).getLong("left", 0L) > 0L

    private fun okPkg(p: String?) = p != null && (p == packageName || p in allowed)

    private fun refresh() {
        if (!active()) { drawPanels(emptyList()); return }
        val list = windows.sortedByDescending { it.layer } // top-most window first
        val allowedAbove = Region()
        val rects = mutableListOf<Rect>()
        var ourVisible = false
        for (w in list) {
            val b = Rect()
            w.getBoundsInScreen(b)
            val pkg = w.root?.packageName?.toString()
            val isApp = w.type == AccessibilityWindowInfo.TYPE_APPLICATION
            if (isApp && okPkg(pkg)) ourVisible = true
            if (!isApp || pkg == null || okPkg(pkg)) {
                allowedAbove.union(b) // our windows, system bars, keyboard: never covered
            } else {
                // cover this foreign window, except the parts hidden under our own windows
                val r = Region(b)
                r.op(allowedAbove, Region.Op.DIFFERENCE)
                val it = RegionIterator(r)
                val rr = Rect()
                while (it.next(rr)) if (rr.width() > 20 && rr.height() > 20) rects.add(Rect(rr))
            }
        }
        drawPanels(rects)
        // Our own window disappeared (e.g. it was closed to leave a pop-up): bring it back full screen
        val now = System.currentTimeMillis()
        if (!ourVisible && list.isNotEmpty() && now - lastRelaunch > 1500) {
            lastRelaunch = now
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
        }
    }

    private fun drawPanels(rects: List<Rect>) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val keys = rects.map { "${it.left},${it.top},${it.right},${it.bottom}" }
        for (k in panels.keys.toList()) if (k !in keys) {
            panels.remove(k)?.let { try { wm.removeView(it) } catch (e: Exception) {} }
        }
        rects.forEachIndexed { i, r ->
            if (panels.containsKey(keys[i])) return@forEachIndexed
            val v = TextView(this).apply {
                setBackgroundColor(Color.BLACK)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                textSize = 16f
                text = "ممنوع أثناء الوضع الصارم"
            }
            val lp = WindowManager.LayoutParams(
                r.width(), r.height(), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.OPAQUE
            )
            lp.gravity = Gravity.TOP or Gravity.START
            lp.x = r.left
            lp.y = r.top
            try { wm.addView(v, lp); panels[keys[i]] = v } catch (e: Exception) {}
        }
    }

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        val prefs = getSharedPreferences("strict", MODE_PRIVATE)
        if (prefs.getLong("left", 0L) <= 0L) return // no active session (time left = 0)
        val pkg = e?.packageName?.toString() ?: return
        if (pkg == packageName || pkg in allowed) return
        // Quick settings / notification shade: close it first (Android 12+)
        if (pkg == "com.android.systemui" && android.os.Build.VERSION.SDK_INT >= 31) {
            performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
        }
        // Bring our activity back to the front (also covers floating windows,
        // split-screen partners and picture-in-picture from other apps)
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        )
    }

    override fun onInterrupt() {}
}
