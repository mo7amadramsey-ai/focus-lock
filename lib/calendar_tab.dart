import 'package:flutter/material.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// Month calendar: exam dates, assignment / quiz deadlines (from Moodle or added by hand) and the study plan.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime sel = dayOnly(DateTime.now());

  Future<void> _add() async {
    final tc = TextEditingController();
    var kind = 'exam';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('إضافة موعد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('امتحان'), selected: kind == 'exam', onSelected: (_) => set(() => kind = 'exam')),
              ChoiceChip(label: const Text('مهمة / تسليم'), selected: kind == 'task', onSelected: (_) => set(() => kind = 'task')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: tc, autofocus: true, decoration: const InputDecoration(hintText: 'العنوان، مثل: امتحان نصفي - الشبكات')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('التاريخ')),
          ],
        ),
      ),
    );
    if (ok != true || tc.text.trim().isEmpty || !mounted) return;
    final d = await showDatePicker(
      context: context,
      initialDate: sel.isBefore(dayOnly(DateTime.now())) ? DateTime.now() : sel,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: kind == 'exam' ? 9 : 23, minute: kind == 'exam' ? 0 : 59));
    study.addManual(tc.text.trim(), kind, DateTime(d.year, d.month, d.day, t?.hour ?? (kind == 'exam' ? 9 : 23), t?.minute ?? (kind == 'exam' ? 0 : 59)));
    setState(() => sel = dayOnly(d));
  }

  @override
  Widget build(BuildContext c) {
    final ag = study.agenda();
    final plan = study.plan();
    final byDay = <String, List<AgendaItem>>{};
    for (final a in ag) {
      byDay.putIfAbsent(dayKey(a.when), () => []).add(a);
    }
    final planDay = {for (final p in plan) dayKey(p.date): p};
    final first = DateTime(month.year, month.month, 1);
    final lead = (first.weekday + 1) % 7; // the week starts on Saturday
    final dim = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + dim + 6) ~/ 7) * 7;
    final today = dayOnly(DateTime.now());
    const names = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
    final selAg = byDay[dayKey(sel)] ?? [];
    final selPlan = planDay[dayKey(sel)];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('موعد')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
          Expanded(child: Center(child: Text('${names[month.month - 1]} ${month.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)))),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
        ]),
        Row(children: [
          for (final d in const ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج']) Expanded(child: Center(child: Text(d, style: TextStyle(color: kMuted)))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < cells; i++)
              () {
                final dn = i - lead + 1;
                if (dn < 1 || dn > dim) return const SizedBox();
                final d = DateTime(month.year, month.month, dn);
                final k = dayKey(d);
                final items = byDay[k] ?? [];
                final isSel = d == sel, isToday = d == today;
                return InkWell(
                  onTap: () => setState(() => sel = d),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSel ? kAccent.withOpacity(0.25) : null,
                      border: isToday ? Border.all(color: kAccent) : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$dn'),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (items.any((a) => a.isExam)) const _Dot(Colors.redAccent),
                        if (items.any((a) => !a.isExam)) const _Dot(Colors.amber),
                        if (planDay[k] != null) _Dot(kAccent),
                      ]),
                    ]),
                  ),
                );
              }(),
          ],
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Dot(Colors.redAccent), Text(' امتحان   '), _Dot(Colors.amber), Text(' تسليم   '), _Dot(kAccent), Text(' خطة'),
        ]),
        const Divider(height: 24),
        Text(dayLabel(sel), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (selAg.isEmpty && selPlan == null) Padding(padding: EdgeInsets.all(10), child: Text('لا شيء في هذا اليوم', style: TextStyle(color: kMuted))),
        for (final a in selAg)
          GestureDetector(
            onLongPress: a.manualId == null
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('حذف الموعد؟'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                        ],
                      ),
                    );
                    if (ok == true) study.removeManual(a.manualId!);
                  },
            child: agendaTile(a),
          ),
        if (selPlan != null) ...[
          Padding(padding: EdgeInsets.only(top: 8), child: Text('خطة الدراسة', style: TextStyle(color: kMuted))),
          for (final l in selPlan.items) videoTile(c, l),
        ],
        const SizedBox(height: 80),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext c) => Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
