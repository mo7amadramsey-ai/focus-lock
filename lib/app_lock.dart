import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'channel.dart';
import 'docs.dart';
import 'lock_setup.dart';
import 'nav.dart';
import 'theme.dart';

/// Locks the whole app behind the phone's own fingerprint / PIN / pattern.
/// Only the phone owner can open it. Re-locks when the app stays in the
/// background for a while (not during a running strict session).
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool unlocked = false, everUnlocked = false, authing = false, noLockOnPhone = false;
  DateTime? _bg;
  static const relockAfter = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (authing) return; // the system prompt itself pauses the app
    if (s == AppLifecycleState.paused) {
      _bg = DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final away = _bg == null ? Duration.zero : DateTime.now().difference(_bg!);
      _bg = null;
      if (unlocked && !strictActive.value && away >= relockAfter) {
        setState(() => unlocked = false);
        _authenticate();
      } else if (unlocked) {
        _takeIncoming();
      }
    }
  }

  Future<void> _authenticate() async {
    if (authing) return;
    authing = true;
    bool ok = false;
    try {
      if (!await _auth.isDeviceSupported()) {
        // Phone has no screen lock at all: nothing to check against
        noLockOnPhone = true;
        ok = true;
      } else {
        ok = await _auth.authenticate(
          localizedReason: 'أثبت أنك صاحب الهاتف لفتح Focus Lock',
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
        );
      }
    } catch (_) {
      ok = false;
    }
    authing = false;
    if (!mounted) return;
    setState(() {
      unlocked = ok;
      if (ok) everUnlocked = true;
    });
    if (ok) _takeIncoming();
  }

  // A file sent from Google Drive ("Open with" / Share) -> save and open it
  Future<void> _takeIncoming() async {
    if (strictActive.value) return;
    try {
      final p = await ch.invokeMethod<String>('takeIncoming');
      if (p == null || !isDocPath(p)) return;
      final root = await docsRoot();
      var name = baseName(p);
      var out = File('${root.path}/$name');
      var n = 1;
      while (await out.exists()) {
        final dot = name.lastIndexOf('.');
        out = File('${root.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}');
        n++;
      }
      await File(p).copy(out.path);
      navKey.currentState?.push(MaterialPageRoute(builder: (_) => DocViewerPage(path: out.path)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => Stack(children: [
        if (everUnlocked) widget.child,
        if (!unlocked)
          Positioned.fill(
            child: Material(
              color: kBg,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [kAccent, Color(0xFFB71C1C)]),
                        boxShadow: [BoxShadow(color: kAccent.withOpacity(.35), blurRadius: 30)],
                      ),
                      child: const Icon(Icons.lock, size: 46, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    const Text('Focus Lock', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('التطبيق مقفل. افتحه ببصمتك أو رمز هاتفك',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.5)),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _authenticate,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('فتح القفل'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}
