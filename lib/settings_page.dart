import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'downloads.dart';
import 'follow_tab.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'stats_tab.dart';
import 'study.dart';
import 'theme.dart';

/// Study settings: daily hours, reminders, Moodle address, backup / restore / delete
class StudySettingsPage extends StatefulWidget {
  const StudySettingsPage({super.key});
  @override
  State<StudySettingsPage> createState() => _StudySettingsPageState();
}

class _StudySettingsPageState extends State<StudySettingsPage> {
  late final host = TextEditingController(text: study.moodleHost);
  final user = TextEditingController(), pass = TextEditingController();
  bool hasLogin = false;

  @override
  void initState() {
    super.initState();
    savedLogin().then((v) {
      if (mounted) setState(() => hasLogin = v != null);
    });
  }

  void _toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _restore() async {
    final tc = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null && clip!.text!.contains('"state"')) tc.text = clip.text!;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: TextField(controller: tc, maxLines: 6, decoration: const InputDecoration(hintText: 'ألصق نص النسخة الاحتياطية هنا')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await study.importJson(tc.text.trim());
    _toast(done ? 'تمت الاستعادة' : 'النص غير صالح، لم يتغير شيء');
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف كل بيانات الدراسة؟'),
        content: const Text('تُحذف الروابط والخطة والدفاتر والأسئلة والإحصاءات من هذا الهاتف. لا يمكن التراجع، فخذ نسخة احتياطية أولاً. الفيديوهات والمستندات المحمّلة لا تُحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف كل شيء')),
        ],
      ),
    );
    if (ok == true) {
      await study.wipe();
      _toast('حُذفت بيانات الدراسة');
    }
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: study,
        builder: (_, __) => Scaffold(
          appBar: AppBar(title: const Text('إعدادات المرشد')),
          body: ListView(padding: const EdgeInsets.all(14), children: [
            const Text('المظهر', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'system', icon: Icon(Icons.phone_android, size: 18), label: Text('تلقائي')),
                  ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('نهار')),
                  ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('ليل')),
                ],
                selected: {study.themeMode},
                onSelectionChanged: (v) => study.setSettings(theme: v.first),
              ),
            ),
            const Divider(height: 28),
            const Text('الوضع الصارم', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('يمنعك من الخروج من التطبيق فقط. تبقى حراً داخل التطبيق، وشريط رفيع في الأعلى يريك الوقت المتبقي. '
                'للتطبيق كله حتى 3 ساعات، وعند مشاهدة فيديو يمكن قفل الفيديو حتى ساعة ونصف (يتوقف قفل التطبيق خلاله ثم يعود وحده).',
                style: TextStyle(color: kMuted, height: 1.6)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ensureLockReady(context),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('تفعيل خدمة الوضع الصارم في الجهاز'),
            ),
            const Divider(height: 28),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_rounded),
              title: const Text('مزامنة المودل'),
              subtitle: const Text('قراءة موادك من جديد'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage(autoSync: true))).then((_) => study.load()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: const Text('فتح المودل كمتصفح'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage())),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('المتابعة'),
              subtitle: const Text('الواجبات وما رُفع حديثاً'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('المتابعة')), body: const FollowTab()))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insights_rounded),
              title: const Text('الإحصاءات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الإحصاءات')), body: const StatsTab()))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_rounded),
              title: const Text('التنزيلات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
            ),
            const Divider(height: 28),
            const Text('ساعات الدراسة اليومية', style: TextStyle(fontWeight: FontWeight.w800)),
            Slider(
              min: 30,
              max: 600,
              divisions: 19,
              label: fmtMinutes(study.dailyMinutes),
              value: study.dailyMinutes.clamp(30, 600).toDouble(),
              onChanged: (v) => study.setSettings(daily: v.round()),
            ),
            Text('${fmtMinutes(study.dailyMinutes)} يومياً. تعتمد عليها الخطة لتحذّرك عند العجز.', style: TextStyle(color: kMuted)),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التنبيهات والتذكيرات'),
              subtitle: const Text('قبل التسليم بيوم وثلاث ساعات، قبل الامتحان بـ 3 أيام ويوم، وتذكير دراسة يومي 17:00، وإشعار بالجديد في المودل'),
              value: study.remindersOn,
              onChanged: (v) {
                study.setSettings(reminders: v);
                if (v) study.askNotifications();
              },
            ),
            const Divider(height: 28),
            const Text('عنوان المودل', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            TextField(controller: host, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'moodle.university.edu')),
            const SizedBox(height: 6),
            Row(children: [
              FilledButton.tonal(
                onPressed: () {
                  final h = host.text.trim().replaceAll(RegExp(r'^https?://'), '').split('/').first;
                  study.setSettings(host: h);
                  host.text = study.moodleHost;
                  _toast('حُفظ العنوان. أعد فتح صفحة المودل ليُستخدم');
                },
                child: const Text('حفظ العنوان'),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('المتصفح يقتصر على هذا النطاق فقط.', style: TextStyle(color: kMuted, fontSize: 12.5))),
            ]),
            const Divider(height: 28),
            const Text('تسجيل الدخول إلى المودل', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(hasLogin ? 'يوجد دخول محفوظ على هذا الهاتف.' : 'اختياري. إن لم تحفظ شيئاً فستكتب بياناتك في صفحة المودل كل مرة.',
                style: TextStyle(color: kMuted, height: 1.5)),
            const SizedBox(height: 6),
            TextField(controller: user, decoration: const InputDecoration(hintText: 'اسم المستخدم')),
            const SizedBox(height: 6),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(hintText: 'كلمة المرور')),
            const SizedBox(height: 6),
            Row(children: [
              FilledButton.tonal(
                onPressed: () async {
                  if (user.text.trim().isEmpty || pass.text.isEmpty) return;
                  await saveLogin(user.text.trim(), pass.text);
                  user.clear();
                  pass.clear();
                  setState(() => hasLogin = true);
                  _toast('حُفظ الدخول مشفراً. سيُملأ تلقائياً دون تسجيل الدخول عنك');
                },
                child: const Text('حفظ'),
              ),
              const SizedBox(width: 8),
              if (hasLogin)
                OutlinedButton(
                  onPressed: () async {
                    await clearLogin();
                    setState(() => hasLogin = false);
                  },
                  child: const Text('حذف المحفوظ'),
                ),
            ]),
            const Divider(height: 28),
            const Text('البيانات والخصوصية', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('كل شيء محفوظ على هاتفك فقط. لا خادم ولا حساب. الحفظ على مرحلتين (ملف مؤقت ثم استبدال) مع نسخة سابقة تُستعاد إن تلف الملف.', style: TextStyle(color: kMuted, height: 1.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: study.exportJson()));
                  _toast('نُسخت النسخة الاحتياطية. الصقها في ملاحظة أو رسالة لنفسك');
                },
                icon: const Icon(Icons.backup),
                label: const Text('نسخ احتياطي (إلى الحافظة)'),
              ),
              FilledButton.tonalIcon(onPressed: _restore, icon: const Icon(Icons.restore), label: const Text('استعادة')),
              OutlinedButton.icon(
                onPressed: _wipe,
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                label: const Text('حذف كل بيانات الدراسة', style: TextStyle(color: Colors.redAccent)),
              ),
            ]),
          ]),
        ),
      );
}
