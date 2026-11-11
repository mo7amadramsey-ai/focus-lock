import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_lock.dart';
import 'nav.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'docs.dart';
import 'library_page.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'player_page.dart';
import 'strict_shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      final end = (s['end'] as num).toInt();
      final target = s['target'] as String;
      next = s['type'] == 'web'
          ? StrictWebPage(url: target, endMillis: end)
          : s['type'] == 'moodle'
              ? StrictMoodlePage(url: target, endMillis: end)
              : PlayerPage(path: target, endMillis: end);
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext c) => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kAccent)),
      );
}

// Home: header, status, 4 cards, how-it-works
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool? lockReady;

  @override
  void initState() {
    super.initState();
    _status();
  }

  Future<void> _status() async {
    try {
      final owner = await ch.invokeMethod<bool>('isDeviceOwner') ?? false;
      final acc = await ch.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      if (mounted) setState(() => lockReady = owner || acc);
    } catch (_) {}
  }

  Widget _tile(BuildContext c, IconData icon, String title, String sub, List<Color> colors, Widget page) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withOpacity(.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () async {
              await Navigator.push(c, MaterialPageRoute(builder: (_) => page));
              _status();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const Spacer(),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ),
        ),
      );

  Widget _step(IconData i, String t, String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: kAccent.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(i, color: kAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(s, style: const TextStyle(color: Colors.white60, height: 1.5, fontSize: 13)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [kAccent, Color(0xFFB71C1C)]),
                  boxShadow: [BoxShadow(color: kAccent.withOpacity(.4), blurRadius: 16)],
                ),
                child: const Icon(Icons.lock_clock, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Focus Lock', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text('ذاكر بتركيز مطلق، بلا تشتت', style: TextStyle(color: Colors.white60)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            // Status chips
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.fingerprint, 'التطبيق محمي ببصمتك', Colors.greenAccent),
              GestureDetector(
                onTap: lockReady == false ? () => ensureLockReady(c).then((_) => _status()) : null,
                child: _chip(
                  lockReady == true ? Icons.verified_user : Icons.warning_amber_rounded,
                  lockReady == true ? 'القفل الصارم جاهز' : (lockReady == null ? 'جاري الفحص' : 'فعّل القفل الصارم'),
                  lockReady == true ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                _tile(c, Icons.smart_display, 'يوتيوب', 'متصفح مقيّد + تحميل', const [Color(0xFFFF4D4D), Color(0xFFB71C1C)], const BrowserPage()),
                _tile(c, Icons.school, 'المودل', 'محاضرات ومستندات الجامعة', const [Color(0xFF3D7BFF), Color(0xFF1A3C9C)], const MoodlePage()),
                _tile(c, Icons.video_library, 'الفيديوهات', 'المحمّلة حسب المواد', const [Color(0xFF8E44FF), Color(0xFF4A1C9C)], const LibraryPage()),
                _tile(c, Icons.description, 'المستندات', 'PDF وWord وExcel وPowerPoint', const [Color(0xFF16A085), Color(0xFF0B5345)], const DocsPage()),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardBox(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('كيف يعمل الوضع الصارم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _step(Icons.play_circle_outline, 'افتح فيديو', 'من يوتيوب أو المودل أو الفيديوهات المحمّلة، ثم اضغط "الوضع الصارم".'),
                _step(Icons.more_time, 'مدة القفل = مدة الفيديو', 'ويمكنك إضافة وقت إضافي قبل البدء أو أثناءه.'),
                _step(Icons.timer_off, 'عند انتهاء الوقت', 'لا يُغلق الفيديو، بل يُعرض عليك تمديد فترة التركيز.'),
              ]),
            ),
          ]),
        ),
      );

  Widget _chip(IconData i, String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: col.withOpacity(.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: col.withOpacity(.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: col),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(color: col, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      );
}
