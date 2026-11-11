import 'package:flutter/material.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'library_page.dart';
import 'player_page.dart';
import 'strict_shell.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
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
          : PlayerPage(path: target, endMillis: end);
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext c) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Focus Lock')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BrowserPage())),
              icon: const Icon(Icons.public),
              label: const Text('متصفح يوتيوب'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const LibraryPage())),
              icon: const Icon(Icons.video_library),
              label: const Text('الفيديوهات المحملة'),
            ),
          ]),
        ),
      );
}
