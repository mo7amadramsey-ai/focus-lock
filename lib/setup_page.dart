import 'package:flutter/material.dart';
import 'moodle_page.dart';
import 'nav.dart';
import 'study.dart';
import 'theme.dart';

/// First start: which Moodle is yours? (Any university's Moodle works.)
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final host = TextEditingController();
  String? err;

  Future<void> _go() async {
    final h = host.text.trim().toLowerCase().replaceAll(RegExp(r'^https?://'), '').split('/').first;
    if (!h.contains('.') || h.contains(' ')) {
      setState(() => err = 'اكتب عنوان المودل كاملاً، مثل moodle.جامعتك.edu');
      return;
    }
    study.setSettings(host: h);
    // Log in once: the app reads your courses and shows them in a simple interface
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage(autoSync: true)));
    if (mounted) goHome(context);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 30),
            Icon(Icons.school, size: 56, color: kAccent),
            const SizedBox(height: 16),
            const Text('أهلاً بك', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('هذا التطبيق واجهة بسيطة لمودل جامعتك: تفتحه فتدرس. يقرأ موادك ويعرضها لك مرتبة، ويضع لك خطة، ويمنعك من الخروج عند الدراسة إن أردت.',
                style: TextStyle(color: kSoft, height: 1.7, fontSize: 15)),
            const SizedBox(height: 26),
            const Text('عنوان مودل جامعتك', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: host,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(hintText: 'moodle.university.edu', errorText: err),
            ),
            const SizedBox(height: 8),
            Text('تجده في المتصفح عندما تفتح المودل. لا يُرسَل شيء إلى أي خادم، كل بياناتك على هاتفك.', style: TextStyle(color: kMuted, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton(onPressed: _go, child: const Text('متابعة وتسجيل الدخول')),
          ]),
        ),
      );
}
