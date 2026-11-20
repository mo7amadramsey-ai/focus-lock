import 'dart:math';
import 'package:flutter/material.dart';
import 'links_page.dart';
import 'study.dart';
import 'theme.dart';

/// Notebook of one lecture: free notes + review questions (+ a quiz on them)
class NotebookPage extends StatefulWidget {
  final MoodleLink link;
  const NotebookPage({super.key, required this.link});
  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  late final Note note = study.ensureNote(widget.link);
  late final TextEditingController tc = TextEditingController(text: note.text);

  @override
  void dispose() {
    tc.dispose();
    study.saveSoon();
    super.dispose();
  }

  Future<void> _addQuestion() async {
    final q = TextEditingController(), a = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سؤال مراجعة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: q, autofocus: true, decoration: const InputDecoration(hintText: 'السؤال')),
          const SizedBox(height: 10),
          TextField(controller: a, maxLines: 3, decoration: const InputDecoration(hintText: 'الإجابة')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok == true && q.text.trim().isNotEmpty) {
      setState(() => note.qs.add(QA(q.text.trim(), a.text.trim())));
      study.saveSoon();
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: Text(widget.link.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'اختبار على أسئلة هذه المحاضرة',
              icon: const Icon(Icons.quiz_outlined),
              onPressed: note.qs.isEmpty
                  ? null
                  : () => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(questions: List.of(note.qs)))),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          const Text('ملاحظاتي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: tc,
            minLines: 6,
            maxLines: 14,
            onChanged: (v) {
              note.text = v;
              study.saveSoon();
            },
            decoration: const InputDecoration(hintText: 'اكتب ملخص المحاضرة ونقاطها المهمة'),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('أسئلة المراجعة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            FilledButton.tonalIcon(onPressed: _addQuestion, icon: const Icon(Icons.add), label: const Text('سؤال')),
          ]),
          const SizedBox(height: 8),
          if (note.qs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('أضف أسئلة من المحاضرة لتختبر نفسك عليها لاحقاً', style: TextStyle(color: Colors.white54)),
            ),
          for (var i = 0; i < note.qs.length; i++)
            Card(
              color: kSurface,
              child: ListTile(
                title: Text(note.qs[i].q),
                subtitle: Text(note.qs[i].a, style: const TextStyle(color: Colors.white54)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => note.qs.removeAt(i));
                    study.saveSoon();
                  },
                ),
              ),
            ),
        ]),
      );
}

/// Self-test: question -> reveal the answer -> "knew it" / "did not know it"; wrong ones can be repeated
class QuizPage extends StatefulWidget {
  final List<QA> questions;
  const QuizPage({super.key, required this.questions});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<QA> qs = (List.of(widget.questions)..shuffle(Random()));
  int i = 0, right = 0;
  bool show = false;
  final wrong = <QA>[];

  void _answer(bool ok) {
    if (ok) {
      right++;
    } else {
      wrong.add(qs[i]);
    }
    setState(() {
      i++;
      show = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    final end = i >= qs.length;
    return Scaffold(
      appBar: AppBar(title: Text(end ? 'النتيجة' : 'سؤال ${i + 1} من ${qs.length}')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: end
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(wrong.isEmpty ? Icons.emoji_events : Icons.fact_check, size: 64, color: kAccent),
                const SizedBox(height: 12),
                Text('$right من ${qs.length}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                if (wrong.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      qs = List.of(wrong)..shuffle(Random());
                      wrong.clear();
                      i = 0;
                      right = 0;
                      show = false;
                    }),
                    icon: const Icon(Icons.replay),
                    label: Text('أعد الأسئلة التي أخطأت فيها (${wrong.length})'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('إنهاء')),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LinearProgressIndicator(value: i / qs.length, color: kAccent),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(22)),
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(qs[i].q, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.5)),
                        if (show) ...[
                          const Divider(height: 32),
                          Text(qs[i].a.isEmpty ? '(لا توجد إجابة مكتوبة)' : qs[i].a,
                              style: const TextStyle(fontSize: 17, color: Colors.white70, height: 1.6)),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (!show)
                  FilledButton(onPressed: () => setState(() => show = true), child: const Text('إظهار الإجابة'))
                else
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('لم أعرفها'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('عرفتها'))),
                  ]),
              ]),
      ),
    );
  }
}
