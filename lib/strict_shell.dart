import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'lock_ctl.dart';
import 'lock_setup.dart';

/// Page of a video lock. The lock itself (time, "do not leave the app") lives in [lock] and shows as a thin bar
/// on top of the app. This wrapper only keeps you inside the video while the video lock runs (no back button)
/// and tells the lock whether the video is playing (the video lock counts only then).
/// [leftMs] and [maxMs] are kept for the callers; the lock already holds the time.
class StrictShell extends StatefulWidget {
  final int leftMs;
  final Widget child;
  final ValueListenable<bool>? playing; // null = always counts while the app is on screen
  final int maxMs;
  const StrictShell({super.key, required this.leftMs, required this.child, this.playing, this.maxMs = kMaxVideoLockMs});
  @override
  State<StrictShell> createState() => _StrictShellState();
}

class _StrictShellState extends State<StrictShell> {
  @override
  void initState() {
    super.initState();
    lock.attachPlaying(widget.playing);
  }

  @override
  void dispose() {
    lock.attachPlaying(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: lock,
        builder: (_, __) => PopScope(
          canPop: !lock.vidOn,
          child: Scaffold(backgroundColor: Colors.black, body: SafeArea(child: widget.child)),
        ),
      );
}

// ---- Play state of a <video> inside a web page (YouTube / Moodle) ----
// 0 = paused / ended / buffering, 1 = playing, 2 = no <video> in the main page (e.g. a player inside an iframe):
// then we cannot know, so the time simply counts (never leaves you stuck).
const _pollJs = "(function(){var vs=document.querySelectorAll('video');if(!vs.length)return 2;"
    "for(var i=0;i<vs.length;i++){var v=vs[i];if(!v.paused&&!v.ended&&v.readyState>2)return 1;}return 0;})()";

/// Updates [out] every second with whether the page's video is playing. Cancel the returned timer in dispose.
Timer startPlayPoll(WebViewController w, ValueNotifier<bool> out) => Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final r = await w.runJavaScriptReturningResult(_pollJs);
        out.value = (int.tryParse(r.toString().replaceAll('"', '')) ?? 2) != 0;
      } catch (_) {
        out.value = true;
      }
    });
