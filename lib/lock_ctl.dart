import 'flavor.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'channel.dart';
import 'lock_setup.dart';
import 'study.dart';
import 'theme.dart';

/// The strict mode. It does ONE thing: it stops you from leaving the app (the Android side pulls you back).
/// Inside the app everything works as usual; the only sign is a thin bar at the top with the time left.
///
/// Two layers can exist:
///  - app lock (outer): counts real time while the app is on screen. Up to 3 hours.
///  - video lock (inner): keeps you inside one video / playlist and counts only while it plays. Up to 1.5 hours.
/// While the video lock runs the app lock is paused; when the video lock ends the app lock continues by itself.
/// There is no emergency exit. The time can only be extended.
class LockCtl extends ChangeNotifier with WidgetsBindingObserver {
  bool appOn = false, vidOn = false;
  int appLeft = 0, vidLeft = 0;
  String vidType = '', vidTarget = '';
  bool fg = true, focus = true, ringing = false, counting = false;
  bool permsOk = true; // the permissions that make the lock work (accessibility service / device owner) are on
  String? flash; // short message after a layer ended
  DateTime _flashUntil = DateTime.fromMillisecondsSinceEpoch(0);
  ValueListenable<bool>? _playing;
  Timer? _t;
  DateTime _last = DateTime.now();
  int _n = 0;

  bool get active => appOn || vidOn;
  int get leftMs => vidOn ? vidLeft : appLeft;
  int get maxMs => vidOn ? kMaxVideoLockMs : kMaxAppLockMs;

  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/lock_state.json');

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        final a = (j['app'] as Map?) ?? {}, v = (j['vid'] as Map?) ?? {};
        appLeft = (a['left'] as num?)?.toInt() ?? 0;
        appOn = a['on'] == true && appLeft > 0;
        vidLeft = (v['left'] as num?)?.toInt() ?? 0;
        vidOn = v['on'] == true && vidLeft > 0;
        vidType = '${v['type'] ?? ''}';
        vidTarget = '${v['target'] ?? ''}';
      }
    } catch (_) {}
    ch.setMethodCallHandler((call) async {
      if (call.method == 'callState') {
        ringing = call.arguments == 1;
        notifyListeners();
      }
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    strictActive.value = active;
    if (active) {
      await _native();
      if (vidOn) WakelockPlus.enable();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    fg = s == AppLifecycleState.resumed;
    _last = DateTime.now();
    if (!fg) _save();
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode({
        'app': {'on': appOn, 'left': appLeft},
        'vid': {'on': vidOn, 'left': vidLeft, 'type': vidType, 'target': vidTarget},
      }));
    } catch (_) {}
  }

  // Tells the Android side what to enforce: "stay in the app" while any layer is on
  Future<void> _native() async {
    if (kPlay) {
      // Google Play build: Android screen pinning (the system asks you once; no accessibility service)
      try {
        await ch.invokeMethod(active ? 'pin' : 'unpin');
      } catch (_) {}
      strictActive.value = active;
      return;
    }
    try {
      if (vidOn) {
        await ch.invokeMethod('startLock', {'left': vidLeft, 'type': vidType.isEmpty ? 'local' : vidType, 'target': vidTarget});
      } else if (appOn) {
        await ch.invokeMethod('startLock', {'left': appLeft, 'type': 'app', 'target': ''});
      } else {
        await ch.invokeMethod('stopLock');
      }
    } catch (_) {}
    strictActive.value = active;
  }

  Future<void> startApp(int ms) async {
    appOn = true;
    appLeft = ms.clamp(1, kMaxAppLockMs).toInt();
    flash = null;
    _last = DateTime.now();
    await _native();
    await _save();
    study.addSession();
    notifyListeners();
  }

  Future<void> startVideo(int ms, String type, String target) async {
    vidOn = true;
    vidLeft = ms.clamp(1, kMaxVideoLockMs).toInt();
    vidType = type;
    vidTarget = target;
    flash = null;
    _last = DateTime.now();
    WakelockPlus.enable();
    await _native();
    await _save();
    study.addSession();
    notifyListeners();
  }

  /// The page that shows the video tells whether it is playing (the video lock counts only then)
  void attachPlaying(ValueListenable<bool>? p) => _playing = p;

  /// Adds time to the layer that is running (never shortens, never above the layer's maximum)
  Future<bool> extend(int addMs) async {
    final before = leftMs;
    final now = (before + addMs).clamp(0, maxMs).toInt();
    if (now <= before) return false;
    if (vidOn) {
      vidLeft = now;
    } else {
      appLeft = now;
    }
    try {
      await ch.invokeMethod('extendLock', {'left': now});
    } catch (_) {}
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    var dt = now.difference(_last).inMilliseconds;
    _last = now;
    if (dt > 2500) dt = 1000;
    if (flash != null && now.isAfter(_flashUntil)) {
      flash = null;
      notifyListeners();
    }
    if (!active) {
      if (counting) counting = false;
      return;
    }
    if (_n % 2 == 0) {
      try {
        focus = await ch.invokeMethod<bool>('isFocused') ?? true;
      } catch (_) {}
    }
    if (!kPlay && _n % 3 == 0) {
      try {
        final owner = await ch.invokeMethod<bool>('isDeviceOwner') ?? false;
        final acc = await ch.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
        permsOk = owner || acc;
      } catch (_) {}
    }
    // no permissions = the lock cannot hold you, so the time does not run
    final can = fg && focus && permsOk && (vidOn ? (_playing?.value ?? true) : true);
    counting = can;
    if (can) {
      if (vidOn) {
        vidLeft -= dt;
      } else {
        appLeft -= dt;
      }
      study.addStudyMs(dt);
    }
    if (vidOn && vidLeft <= 0) {
      vidOn = false;
      vidLeft = 0;
      WakelockPlus.disable();
      _ended(appOn ? 'انتهى قفل الفيديو وعاد قفل التطبيق' : 'انتهى الوضع الصارم');
    } else if (!vidOn && appOn && appLeft <= 0) {
      appOn = false;
      appLeft = 0;
      _ended('انتهى الوضع الصارم');
    }
    _n++;
    if (_n % 3 == 0 && active) {
      _save();
      try {
        await ch.invokeMethod('setLeft', {'left': leftMs});
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _ended(String msg) async {
    flash = msg;
    _flashUntil = DateTime.now().add(const Duration(seconds: 7));
    await _native();
    await _save();
  }
}

final lock = LockCtl();

String fmtLeft(int ms) {
  final s = (ms / 1000).ceil();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  if (h > 0) return m == 0 ? '$h ساعة' : '$h ساعة و$m د';
  if (m > 0) return '$m د';
  return '$s ث';
}

/// The thin bar on top of the whole app. Tap it to add time. It never covers anything else.
class LockBanner extends StatelessWidget {
  const LockBanner({super.key});

  Future<void> _more(BuildContext c) async {
    final r = await pickExtension(c, expired: false);
    if (r == null || r <= 0) return;
    final ok = await lock.extend(r * 60000);
    if (!ok && c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('بلغت الحد الأقصى: ${fmtMinutes(lock.maxMs ~/ 60000)}')));
    }
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: lock,
        builder: (_, __) {
          if (!lock.active && lock.flash == null) return const SizedBox.shrink();
          final ended = !lock.active;
          final bg = ended ? kOk : (lock.counting ? kAccent : kWarn);
          final text = ended
              ? lock.flash!
              : lock.permsOk
                  ? '${lock.vidOn ? 'قفل الفيديو' : 'الوضع الصارم قيد التنفيذ'} · بقي ${fmtLeft(lock.leftMs)}${lock.counting ? '' : ' (متوقف)'}'
                  : 'المؤقت متوقف: الصلاحيات ناقصة · اضغط لتفعيلها';
          return Material(
            color: bg,
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: ended ? null : (lock.permsOk ? () => _more(c) : () => ch.invokeMethod('openAccessibilitySettings')),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Icon(ended ? Icons.lock_open : Icons.lock, size: 15, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
                    if (!ended && lock.ringing)
                      InkWell(
                        onTap: () => ch.invokeMethod('answerCall'),
                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.call, size: 18, color: Colors.white)),
                      ),
                    if (!ended)
                      InkWell(
                        onTap: () => ch.invokeMethod('openDialer'),
                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.dialpad, size: 17, color: Colors.white)),
                      ),
                    if (!ended) const Icon(Icons.add_alarm, size: 17, color: Colors.white),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}
