import 'dart:math';
import 'package:flutter/material.dart';
import 'links_page.dart';
import 'notebook_page.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// Lecture notebooks of every course + review, mistakes notebook, exam lab, search
class NotebookTab extends StatefulWidget {
  const NotebookTab({super.key});
  @override
  State<NotebookTab> createState() => _NotebookTabState();
}

class _NotebookTabState extends State<NotebookTab> {
  String q = '';

  bool _match(MoodleLink l) {
    if (q.isEmpty) return true;
    final n = study.noteOf(l);
    final hay = StringBuffer(l.title);
    if (n != null) {
      hay.write(' ${n.text} ');
      for (final s in n.stamps) {
        hay.write(' ${s.text}');
      }
      for (final x in n.qs) {
        hay.write(' ${x.q} ${x.a}');
      }
    }
    return hay.toString().toLowerCase().contains(q.toLowerCase());
  }

  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty) return emptyStudy(c);
    final due = study.dueQuestions(), mist = study.mistakes(), all = study.allQuestions();
    void quiz(List<QRef> r, String t) => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: r, title: t)));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: due.isEmpty ? null : () => quiz(due, 'مراجعة اليوم'), icon: const Icon(Icons.replay), label: Text('مراجعة اليوم (${due.length})')),
        FilledButton.tonalIcon(
            onPressed: mist.isEmpty ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MistakesPage())),
            icon: const Icon(Icons.error_outline),
            label: Text('دفتر الأخطاء (${mist.length})')),
        FilledButton.tonalIcon(
            onPressed: all.length < 2 ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ExamLabPage())),
            icon: const Icon(Icons.school),
            label: const Text('مختبر الامتحانات')),
        OutlinedButton.icon(onPressed: all.isEmpty ? null : () => quiz(all, 'اختبار عام'), icon: const Icon(Icons.quiz), label: Text('اختبار عام (${all.length})')),
      ]),
      const SizedBox(height: 10),
      TextField(
        onChanged: (v) => setState(() => q = v.trim()),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث في كل الدفاتر'),
      ),
      const SizedBox(height: 8),
      for (final id in study.courseIds())
        if (study.countableOf(id).any(_match))
          Card(
            color: kSurface,
            child: ExpansionTile(
              key: ValueKey('nb$id$q'),
              initiallyExpanded: q.isNotEmpty,
              title: Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
              children: [
                for (final l in study.countableOf(id).where(_match))
                  ListTile(
                    dense: true,
                    leading: Icon(groupIcon(l.group), color: l.group == 'yt' ? kAccent : null),
                    title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: study.understandingOf(l) == null ? null : Text('الفهم ${(study.understandingOf(l)! * 100).round()}%', style: const TextStyle(fontSize: 12)),
                    trailing: (study.noteOf(l)?.isEmpty ?? true)
                        ? null
                        : Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.edit_note, color: kAccent), Text('${study.noteOf(l)!.qs.length}')]),
                    onTap: () => openNotebook(c, l),
                  ),
              ],
            ),
          ),
    ]);
  }
}

/// Questions that were answered wrong and are not yet mastered
class MistakesPage extends StatelessWidget {
  const MistakesPage({super.key});
  @override
  Widget build(BuildContext c) {
    final m = study.mistakes();
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر الأخطاء')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        FilledButton.icon(
          onPressed: m.isEmpty ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: m, title: 'الأخطاء'))),
          icon: const Icon(Icons.replay),
          label: const Text('اختبرني في أخطائي'),
        ),
        for (final r in m)
          Card(
            color: kSurface,
            child: ListTile(
              title: Text(r.qa.q),
              subtitle: Text('الإجابة: ${r.qa.a}\n${r.link != null ? 'المصدر: ${r.link!.title}\n' : ''}أخطأت ${r.qa.wrong} مرة',
                  style: const TextStyle(color: Colors.white54, height: 1.5)),
              onTap: r.link == null ? null : () => openNotebook(c, r.link!),
            ),
          ),
      ]),
    );
  }
}

/// Builds a timed exam from the questions of your notebooks (one course or all), linked to the lectures they came from
class ExamLabPage extends StatefulWidget {
  const ExamLabPage({super.key});
  @override
  State<ExamLabPage> createState() => _ExamLabPageState();
}

class _ExamLabPageState extends State<ExamLabPage> {
  String? cid;
  double count = 10, minutes = 15;

  @override
  Widget build(BuildContext c) {
    final ids = study.courseIds().where((id) => study.allQuestions(cid: id).isNotEmpty).toList();
    final pool = study.allQuestions(cid: cid);
    final n = pool.length;
    final cnt = n < 2 ? n : count.clamp(1, n.toDouble()).round();
    return Scaffold(
      appBar: AppBar(title: const Text('مختبر الامتحانات')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('المادة', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('كل المواد'), selected: cid == null, onSelected: (_) => setState(() => cid = null)),
          for (final id in ids)
            ChoiceChip(label: Text(study.courses[id] ?? id, overflow: TextOverflow.ellipsis), selected: cid == id, onSelected: (_) => setState(() => cid = id)),
        ]),
        const SizedBox(height: 16),
        Text('عدد الأسئلة: $cnt من $n', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (n > 2) Slider(min: 1, max: n.toDouble(), divisions: n - 1, value: count.clamp(1, n.toDouble()), onChanged: (v) => setState(() => count = v)),
        Text('الوقت: ${minutes.round()} دقيقة', style: const TextStyle(fontWeight: FontWeight.w800)),
        Slider(min: 5, max: 180, divisions: 35, value: minutes, onChanged: (v) => setState(() => minutes = v)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: n == 0
              ? null
              : () {
                  final pick = (List.of(pool)..shuffle(Random())).take(cnt).toList();
                  Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: pick, title: 'امتحان', exam: true, minutes: minutes.round(), cid: cid)));
                },
          icon: const Icon(Icons.play_arrow),
          label: const Text('ابدأ الامتحان'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('الأسئلة من دفاترك فقط، وفي النهاية ترى محاضرة كل خطأ لتراجعها.', style: TextStyle(color: Colors.white54, height: 1.5)),
        ),
      ]),
    );
  }
}
