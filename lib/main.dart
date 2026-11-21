import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_lock.dart';
import 'browser_page.dart';
import 'lock_ctl.dart';
import 'lock_modes.dart';
import 'moodle_page.dart';
import 'nav.dart';
import 'player_page.dart';
import 'setup_page.dart';
import 'shell.dart';
import 'study.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await study.load(); // study data, settings and the Moodle address first
  await lock.init(); // a strict session that was running comes back
  study.scheduleReminders();
  homeBuilder = () => const MainShell();
  // Free rotation: landscape video / documents whenever you turn the phone
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    study.addListener(_theme);
    _theme(first: true);
  }

  @override
  void dispose() {
    study.removeListener(_theme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _theme();

  // Day / night: follows the phone, or is forced from the settings
  void _theme({bool first = false}) {
    final sys = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final d = study.themeMode == 'dark' || (study.themeMode == 'system' && sys);
    if (d == Pal.dark && !first) return;
    Pal.dark = d;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: d ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: d ? const Color(0xFF1A1A1D) : Colors.white,
      systemNavigationBarIconBrightness: d ? Brightness.light : Brightness.dark,
    ));
    if (!first) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuildAll());
    }
  }

  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Focus Lock',
        theme: buildTheme(),
        navigatorKey: navKey,
        // Arabic RTL layout, behind the phone's fingerprint / PIN, with the thin strict-mode bar on top of everything
        builder: (ctx, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: AppLockGate(
            child: AnimatedBuilder(
              animation: lock,
              builder: (_, __) {
                final bar = lock.active || lock.flash != null;
                return Column(children: [
                  const LockBanner(),
                  Expanded(child: MediaQuery.removePadding(context: ctx, removeTop: bar, child: child!)),
                ]);
              },
            ),
          ),
        ),
        home: const Boot(),
      );
}

// On launch: first start -> setup; a video lock that was running -> back into that video; else the app
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  void _go() {
    if (!mounted) return;
    Widget next = const MainShell();
    if (study.moodleHost.isEmpty) {
      next = const SetupPage();
    } else if (lock.vidOn) {
      final t = lock.vidTarget, left = lock.vidLeft;
      next = switch (lock.vidType) {
        'web' => StrictWebPage(url: t, leftMs: left),
        'moodle' => StrictMoodlePage(url: t, leftMs: left),
        'playlist' => PlaylistLockPage(ids: t.split(','), leftMs: left),
        _ => PlayerPage(path: t, leftMs: left),
      };
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext c) => Scaffold(body: Center(child: CircularProgressIndicator(color: kAccent)));
}
