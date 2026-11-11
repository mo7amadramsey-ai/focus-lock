import 'package:flutter/material.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'docs.dart';
import 'library_page.dart';
import 'moodle_page.dart';
import 'player_page.dart';
import 'strict_shell.dart';
import 'theme.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Focus Lock',
        theme: buildTheme(),
        // Arabic RTL layout
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
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

// Home: header + 4 cards
class Home extends StatelessWidget {
  const Home({super.key});

  Widget _tile(BuildContext c, IconData icon, String title, String sub, List<Color> colors, Widget page) =>
      Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const Spacer(),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.lock_clock, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Focus Lock', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text('ذاكر بتركيز مطلق، بلا تشتت', style: TextStyle(color: Colors.white60)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                _tile(c, Icons.smart_display, 'يوتيوب', 'متصفح مقيّد + تحميل',
                    const [Color(0xFFFF3B3B), Color(0xFFB71C1C)], const BrowserPage()),
                _tile(c, Icons.school, 'المودل', 'محاضرات ومستندات الجامعة',
                    const [Color(0xFF3D7BFF), Color(0xFF1A3C9C)], const MoodlePage()),
                _tile(c, Icons.video_library, 'الفيديوهات', 'المحمّلة حسب المواد',
                    const [Color(0xFF8E44FF), Color(0xFF4A1C9C)], const LibraryPage()),
                _tile(c, Icons.description, 'المستندات', 'PDF وصور وملفات',
                    const [Color(0xFF16A085), Color(0xFF0B5345)], const DocsPage()),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, color: kAccent),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الوضع الصارم: افتح أي فيديو واضغط "الوضع الصارم". مدة القفل = مدة الفيديو، '
                    'ولا يوجد زر خروج حتى ينتهي المؤقت.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}
