import 'package:flutter/material.dart';
import 'channel.dart';
import 'lock_modes.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'notebook_page.dart';
import 'shell.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// Home: open the app, see what to study today, press start.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool? lockReady;

  @override
  void initState() {
    super.initState();
    study.load().then((_) {
      study.fetchDurations();
      if (study.remindersOn) study.askNotifications();
    });
    _status();
  }

  Future<void> _status() async {
    try {
      final owner = await ch.invokeMethod<bool>('isDeviceOwner') ?? false;
      final acc = await ch.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      if (mounted) setState(() => lockReady = owner || acc);
    } catch (_) {}
  }

  Future<void> _sync() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage(autoSync: true)));
    await study.load();
    study.fetchDurations();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: study,
        builder: (_, __) {
          final res = study.planFull();
          final today = res.days.where((d) => dayOnly(d.date) == dayOnly(DateTime.now())).toList();
          final now = DateTime.now();
          final soon = study.agenda().where((a) => !a.done && !a.when.isBefore(now) && a.when.isBefore(now.add(const Duration(days: 7)))).toList();
          final late = study.overdue();
          final due = study.dueQuestions().length;
          final all = study.totalAll;
          final hasToday = today.isNotEmpty && today.first.items.isNotEmpty;
          return Scaffold(
            appBar: topBar(c, 'الرئيسية'),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              if (study.notice != null)
                Card(color: kWarn.withOpacity(.18), child: Padding(padding: const EdgeInsets.all(12), child: Text(study.notice!))),
              // hero: what to do now
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kAccent.withOpacity(.95), kAccent.withOpacity(.65)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(study.links.isEmpty ? 'اربط مودلك' : hasToday ? 'جاهز للدراسة؟' : 'لا خطة لليوم',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      study.links.isEmpty
                          ? 'سجّل الدخول مرة واحدة ليقرأ التطبيق موادك ويعرضها لك بشكل بسيط.'
                          : hasToday
                              ? '${today.first.items.length} فيديو · ${fmtMinutes(today.first.minutes)} في خطة اليوم'
                              : 'اختر مادة من «المواد» أو ركّز على مواد من «الخطة».',
                      style: const TextStyle(color: Colors.white, height: 1.5)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kAccent),
                        onPressed: study.links.isEmpty ? _sync : hasToday ? () => startPlaylistLock(c, today.first.items) : () => startAppLock(c),
                        child: Text(study.links.isEmpty ? 'مزامنة المودل' : hasToday ? 'ابدأ جلسة اليوم' : 'الوضع الصارم'),
                      ),
                    ),
                    if (study.links.isNotEmpty && hasToday) ...[
                      const SizedBox(width: 10),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.white24),
                        tooltip: 'الوضع الصارم للتطبيق كله',
                        onPressed: () => startAppLock(c),
                        icon: const Icon(Icons.lock_outline_rounded, color: Colors.white),
                      ),
                    ],
                  ]),
                ]),
              ),
              if (lockReady == false)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.shield_outlined, color: kWarn),
                    title: const Text('فعّل خدمة الوضع الصارم'),
                    subtitle: Text('مرة واحدة من إمكانية الوصول، لتمنعك من الخروج أثناء الدراسة', style: TextStyle(color: kMuted)),
                    onTap: () async {
                      await ensureLockReady(c);
                      _status();
                    },
                  ),
                ),
              if (res.shortMin > 0)
                Card(
                  color: kAccent.withOpacity(.12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('المطلوب لا يتسع في ساعاتك: ينقصك ${fmtMinutes(res.shortMin)}. عدّل ساعاتك أو الموعد من «الخطة».', style: const TextStyle(height: 1.5)),
                  ),
                ),
              if (all > 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('تقدمك ${(study.doneAll * 100 / all).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const Spacer(),
                        Text('${study.doneAll}/$all', style: TextStyle(color: kMuted)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: study.doneAll / all, minHeight: 8)),
                    ]),
                  ),
                ),
              if (due > 0)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.replay_circle_filled, color: kAccent),
                    title: Text('مراجعة اليوم: $due سؤال'),
                    subtitle: Text('من أسئلة دفاترك', style: TextStyle(color: kMuted)),
                    onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: study.dueQuestions(), title: 'مراجعة اليوم'))),
                  ),
                ),
              if (late.isNotEmpty) ...[
                _head('متأخر', color: kAccent),
                for (final a in late.reversed.take(4)) agendaTile(a),
              ],
              if (soon.isNotEmpty) ...[
                _head('القادم خلال 7 أيام'),
                for (final a in soon.take(6)) agendaTile(a),
              ],
            ]),
          );
        },
      );

  Widget _head(String t, {Color? color}) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 4), child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: color)));
}
