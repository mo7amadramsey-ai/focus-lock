import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lock_setup.dart';
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
            const Text('ساعات الدراسة اليومية', style: TextStyle(fontWeight: FontWeight.w800)),
            Slider(
              min: 30,
              max: 600,
              divisions: 19,
              label: fmtMinutes(study.dailyMinutes),
              value: study.dailyMinutes.clamp(30, 600).toDouble(),
              onChanged: (v) => study.setSettings(daily: v.round()),
            ),
            Text('${fmtMinutes(study.dailyMinutes)} يومياً. تعتمد عليها الخطة لتحذّرك عند العجز.', style: const TextStyle(color: Colors.white54)),
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
            TextField(controller: host, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'moodle.ucas.edu.ps')),
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
              const Expanded(child: Text('المتصفح يقتصر على هذا النطاق فقط.', style: TextStyle(color: Colors.white54, fontSize: 12.5))),
            ]),
            const Divider(height: 28),
            const Text('البيانات والخصوصية', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('كل شيء محفوظ على هاتفك فقط. لا خادم ولا حساب. الحفظ على مرحلتين (ملف مؤقت ثم استبدال) مع نسخة سابقة تُستعاد إن تلف الملف.', style: TextStyle(color: Colors.white54, height: 1.5)),
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
