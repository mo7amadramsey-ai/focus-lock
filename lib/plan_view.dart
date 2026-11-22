import 'package:flutter/material.dart';
import 'lock_modes.dart';
import 'lock_setup.dart';
import 'plan_smart.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

const _wd = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _palette = [Color(0xFFFF5A5A), Color(0xFF4DA3FF), Color(0xFF3FBF6F), Color(0xFFFFB347), Color(0xFFB583FF), Color(0xFF2DD4BF)];
Color _courseColor(String cid) => _palette[cid.hashCode.abs() % _palette.length];

/// The plan screen: where you stand, what is risky, then one clear card per day.
class SmartPlanTab extends StatelessWidget {
  const SmartPlanTab({super.key});

  Future<void> _pickDeadline(BuildContext c) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: c,
      initialDate: study.deadline.isBefore(now) ? now : study.deadline,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'موعد إنهاء كل المواد',
    );
    if (d != null) study.setDeadline(d);
  }

  Widget _stat(String v, String l) => Expanded(
        child: Column(children: [
          Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(l, style: TextStyle(color: kMuted, fontSize: 12)),
        ]),
      );

  Widget _badge(DateTime d, bool today) => Container(
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: kAccent.withOpacity(today ? .20 : .10), borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${d.day}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kAccent)),
          Text(_wd[d.weekday - 1], maxLines: 1, style: TextStyle(fontSize: 10.5, color: kSoft)),
        ]),
      );

  Widget _chip(String cid) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: _courseColor(cid).withOpacity(.16), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _courseColor(cid), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(study.courses[cid] ?? cid, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _day(BuildContext c, SmartDay d, int i) {
    final isToday = dayOnly(d.date) == dayOnly(DateTime.now());
    final daily = study.dailyMinutes <= 0 ? 1 : study.dailyMinutes;
    final ratio = (d.minutes / daily).clamp(0.0, 1.0).toDouble();
    final over = d.minutes > daily;
    return Card(
      child: Theme(
        data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('d${d.date.millisecondsSinceEpoch}-${d.items.length}-${d.tasks.length}'),
          initiallyExpanded: isToday || i == 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: _badge(d.date, isToday),
          title: Text(isToday ? 'اليوم' : dayLabel(d.date), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${d.items.length} فيديو${d.tasks.isNotEmpty ? ' · ${d.tasks.length} تسليم/اختبار' : ''} · ${fmtMinutes(d.minutes)}${over ? ' · أكثر من ساعاتك' : ''}',
                style: TextStyle(color: over ? kWarn : kMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: kSurface2, color: over ? kWarn : kAccent),
              ),
              if (d.courses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final cid in d.courses) _chip(cid)]),
              ],
            ]),
          ),
          children: [
            if (d.why.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 18, color: kWarn),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d.why, style: TextStyle(color: kSoft, height: 1.5))),
                ]),
              ),
            if (d.items.isNotEmpty && isToday)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(onPressed: () => startPlaylistLock(c, d.items), icon: const Icon(Icons.lock), label: const Text('ابدأ جلسة اليوم (قفل)')),
                ),
              ),
            for (final a in d.tasks) agendaTile(a),
            for (final l in d.items) videoTile(c, l),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty && study.manual.isEmpty) return emptyStudy(c);
    final p = study.smartPlan();
    final focus = study.focusCourses.isNotEmpty;
    final scope = study.videoLinks().where((l) => !focus || study.focusCourses.contains(l.cid)).toList();
    final doneN = scope.where(study.isDone).length;
    final prog = scope.isEmpty ? 0.0 : doneN / scope.length;
    final end = study.planEnd;
    final daysLeft = end.difference(dayOnly(DateTime.now())).inDays + 1;
    final late = study.overdue();
    final status = p.shortMin > 0 ? 'مضغوط' : p.risks.isNotEmpty ? 'انتبه' : 'على المسار';
    final color = p.shortMin > 0 ? kAccent : p.risks.isNotEmpty ? kWarn : kOk;
    final remaining = scope.length - doneN;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(focus ? Icons.center_focus_strong : Icons.event_available, color: kAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  focus ? 'تركيز على ${study.focusCourses.length} مواد حتى ${end.day}/${end.month}' : 'الموعد: ${end.day}/${end.month}/${end.year}${daysLeft > 0 ? ' (باقي $daysLeft يوم)' : ' (انتهى)'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(.16), borderRadius: BorderRadius.circular(12)),
                child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: prog, minHeight: 10, backgroundColor: kSurface2, color: kOk),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(prog * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(remaining <= 0 && p.needMin == 0 ? 'أنهيت كل المطلوب 🎉' : 'أنجزت $doneN من ${scope.length} فيديو', style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Row(children: [
              _stat('$remaining', 'فيديو متبقٍ'),
              _stat(fmtMinutes(p.needMin), 'المطلوب'),
              _stat(fmtMinutes(p.capacityMin), 'متاحك'),
            ]),
            if (p.shortMin > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('⚠ العجز ${fmtMinutes(p.shortMin)}: لا يتسع كل المطلوب في هذه الساعات. زد ساعاتك اليومية (من الإعدادات) أو أطل المدة.', style: TextStyle(color: kAccent, height: 1.5)),
              ),
            if (study.fetching)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('جاري قراءة مدد الفيديوهات ${study.fetched}/${study.toFetch}...', style: TextStyle(color: kMuted, fontSize: 12.5)))
            else if (study.unknownDurations > 0)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('${study.unknownDurations} فيديو لم تُعرف مدته (حُسب كـ 15 دقيقة)', style: TextStyle(color: kMuted, fontSize: 12.5))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.tonalIcon(onPressed: () => showFocusSheet(c), icon: const Icon(Icons.center_focus_strong, size: 18), label: Text(focus ? 'تعديل التركيز' : 'ركّز على مواد')),
              if (!focus) OutlinedButton(onPressed: () => _pickDeadline(c), child: const Text('تغيير الموعد')),
              if (focus) OutlinedButton(onPressed: study.clearFocus, child: const Text('إلغاء التركيز')),
            ]),
          ]),
        ),
      ),
      if (p.risks.isNotEmpty)
        Card(
          color: kWarn.withOpacity(.10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.warning_amber_rounded, color: kWarn), const SizedBox(width: 8), const Text('تنبيهات الخطة', style: TextStyle(fontWeight: FontWeight.w800))]),
              const SizedBox(height: 8),
              for (final r in p.risks) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r', style: TextStyle(color: kSoft, height: 1.5))),
            ]),
          ),
        ),
      if (late.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('متأخر (${late.length})', style: TextStyle(fontWeight: FontWeight.w800, color: kAccent)),
              ),
              for (final a in late.take(5)) agendaTile(a),
            ]),
          ),
        ),
      const SizedBox(height: 4),
      for (var i = 0; i < p.days.length; i++) _day(c, p.days[i], i),
    ]);
  }
}
