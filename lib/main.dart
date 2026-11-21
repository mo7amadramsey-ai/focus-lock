import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_lock.dart';
import 'nav.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'home/home_page.dart';
import 'lock_modes.dart';
import 'moodle_page.dart';
import 'player_page.dart';
import 'strict_shell.dart';
import 'study.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await study.load(); // study data, settings and the Moodle address first
  study.scheduleReminders();
  homeBuilder = () => const Home();
  // Free rotation: landscape video / documents whenever you turn the phone
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Focus Lock',
        theme: buildTheme(),
        navigatorKey: navKey,
        // Arabic RTL layout + the whole app is behind the phone's fingerprint / PIN
        builder: (_, child) =>
            Directionality(textDirection: TextDirection.rtl, child: AppLockGate(child: child!)),
        home: const Boot(),
      );
}

// On launch: if a strict session is still running, jump straight back into it
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    final s = await ch.invokeMapMethod<String, dynamic>('getSession');
    if (!mounted) return;
    Widget next = const Home();
    if (s != null) {
      final left = (s['left'] as num).toInt();
      final target = s['target'] as String;
      next = s['type'] == 'web'
          ? StrictWebPage(url: target, leftMs: left)
          : s['type'] == 'moodle'
              ? StrictMoodlePage(url: target, leftMs: left)
              : s['type'] == 'playlist'
                  ? PlaylistLockPage(ids: target.split(','), leftMs: left)
                  : s['type'] == 'app'
                      ? AppLockPage(leftMs: left)
                      : PlayerPage(path: target, leftMs: left);
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext c) => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kAccent)),
      );
}
