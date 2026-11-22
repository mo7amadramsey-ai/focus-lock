import 'flavor.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'links_page.dart';
import 'preview_page.dart';
import 'study.dart';
import 'theme.dart';

String _stampUrl(String id, int s) => 'https://m.youtube.com/watch?v=$id&t=${s}s';

/// Adds a review question (open / true-false / multiple choice) to a lecture notebook
Future<QA?> askQuestion(BuildContext c) async {
  final q = TextEditingController(), a = TextEditingController();
  final opts = List.generate(4, (_) => TextEditingController());
  var type = 'qa', ci = 0, tf = true;
  return showDialog<QA>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('سؤال مراجعة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final t in const {'qa': 'مفتوح', 'tf': 'صح/خطأ', 'mcq': 'اختيار'}.entries)
                ChoiceChip(label: Text(t.value), selected: type == t.key, onSelected: (_) => set(() => type = t.key)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: q, autofocus: true, decoration: const InputDecoration(hintText: 'السؤال')),
            const SizedBox(height: 10),
            if (type == 'qa') TextField(controller: a, maxLines: 3, decoration: const InputDecoration(hintText: 'الإجابة')),
            if (type == 'tf')
              Row(children: [
                const Text('الإجابة الصحيحة: '),
                ChoiceChip(label: const Text('صحيح'), selected: tf, onSelected: (_) => set(() => tf = true)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('خطأ'), selected: !tf, onSelected: (_) => set(() => tf = false)),
              ]),
            if (type == 'mcq')
              for (var i = 0; i < 4; i++)
                Row(children: [
                  Radio<int>(value: i, groupValue: ci, onChanged: (v) => set(() => ci = v ?? 0)),
                  Expanded(child: TextField(controller: opts[i], decoration: InputDecoration(hintText: 'الخيار ${i + 1}'))),
                ]),
            if (type == 'mcq') Text('اختر الدائرة بجانب الإجابة الصحيحة', style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (q.text.trim().isEmpty) return;
              if (type == 'tf') {
                Navigator.pop(ctx, QA(q.text.trim(), tf ? 'صحيح' : 'خطأ', type: 'tf', opts: ['صحيح', 'خطأ'], ci: tf ? 0 : 1));
              } else if (type == 'mcq') {
                final o = opts.map((e) => e.text.trim()).toList();
                if (o.where((e) => e.isNotEmpty).length < 2 || o[ci].isEmpty) return;
                Navigator.pop(ctx, QA(q.text.trim(), o[ci], type: 'mcq', opts: o.where((e) => e.isNotEmpty).toList(), ci: o.sublist(0, ci).where((e) => e.isNotEmpty).length));
              } else {
                Navigator.pop(ctx, QA(q.text.trim(), a.text.trim()));
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    ),
  );
}

/// Notebook of one lecture: notes, notes tied to a second of the video, review questions, video captions
class NotebookPage extends StatefulWidget {
  final MoodleLink link;
  const NotebookPage({super.key, required this.link});
  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  late final Note note = study.ensureNote(widget.link);
  late final TextEditingController tc = TextEditingController(text: note.text);
  bool loadingCaps = false;

  @override
  void dispose() {
    tc.dispose();
    study.saveSoon();
    super.dispose();
  }

  List<QRef> get _refs => note.qs.map((q) => QRef(linkKey(widget.link), q, widget.link)).toList();

  void _toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _asText() {
    final b = StringBuffer('${widget.link.title}\n\n');
    if (note.text.trim().isNotEmpty) b.writeln('${note.text.trim()}\n');
    if (note.stamps.isNotEmpty) {
      b.writeln('ملاحظات مرتبطة بالفيديو:');
      for (final s in note.stamps) {
        b.writeln('[${fmtClock(s.s)}] ${s.text}${s.src == 'lecturer' ? ' (من كلام المحاضر)' : ''}');
      }
      b.writeln();
    }
    if (note.qs.isNotEmpty) {
      b.writeln('أسئلة المراجعة:');
      for (final q in note.qs) {
        b.writeln('- ${q.q}\n  ${q.a}');
      }
    }
    return b.toString();
  }

  Future<void> _captions() async {
    final id = ytId(widget.link);
    if (id == null) return;
    setState(() => loadingCaps = true);
    final yt = YoutubeExplode();
    try {
      final man = await yt.videos.closedCaptions.getManifest(id);
      if (man.tracks.isEmpty) {
        _toast('لا توجد ترجمة نصية لهذا الفيديو');
      } else {
        var track = man.tracks.first;
        for (final t in man.tracks) {
          if (t.language.code.startsWith('ar')) track = t;
        }
        final cc = await yt.videos.closedCaptions.get(track);
        final lines = [for (final c in cc.captions) (c.offset.inSeconds, c.text.replaceAll('\n', ' ').trim())]
            .where((e) => e.$2.isNotEmpty)
            .toList();
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => _TranscriptPage(link: widget.link, note: note, lines: lines)));
        if (mounted) setState(() {});
      }
    } catch (_) {
      _toast('تعذّر جلب الترجمة (تحتاج إنترنت)');
    }
    yt.close();
    if (mounted) setState(() => loadingCaps = false);
  }

  Future<void> _addStamp() async {
    final sc = TextEditingController(), tx = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملاحظة عند ثانية'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: sc, keyboardType: TextInputType.datetime, decoration: const InputDecoration(hintText: 'الوقت مثل 12:30')),
          const SizedBox(height: 10),
          TextField(controller: tx, autofocus: true, decoration: const InputDecoration(hintText: 'الملاحظة')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || tx.text.trim().isEmpty) return;
    final parts = sc.text.trim().split(':').map((e) => int.tryParse(e) ?? 0).toList();
    final s = parts.length == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts.length == 2 ? parts[0] * 60 + parts[1] : (parts.isEmpty ? 0 : parts[0]);
    setState(() => note.stamps.add(Stamp(s, tx.text.trim())..src = 'me'));
    note.stamps.sort((a, b) => a.s.compareTo(b.s));
    study.saveSoon();
  }

  @override
  Widget build(BuildContext c) {
    final id = ytId(widget.link);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.link.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'نسخ الدفتر كنص',
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _asText()));
              _toast('نُسخ الدفتر');
            },
          ),
          IconButton(
            tooltip: 'اختبار على أسئلة هذه المحاضرة',
            icon: const Icon(Icons.quiz_outlined),
            onPressed: note.qs.isEmpty
                ? null
                : () => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: _refs, title: widget.link.title))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('ملاحظاتي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        TextField(
          controller: tc,
          minLines: 5,
          maxLines: 12,
          onChanged: (v) {
            note.text = v;
            study.saveSoon();
          },
          decoration: const InputDecoration(hintText: 'اكتب ملخص المحاضرة ونقاطها المهمة'),
        ),
        if (id != null) ...[
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('ملاحظات مرتبطة بالفيديو', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(tooltip: 'إضافة', icon: const Icon(Icons.add_comment_outlined), onPressed: _addStamp),
            FilledButton.tonalIcon(
              onPressed: loadingCaps || kPlay ? null : _captions,
              icon: loadingCaps
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.subtitles_outlined),
              label: const Text('نص المحاضرة'),
            ),
          ]),
          for (var i = 0; i < note.stamps.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Chip(label: Text(fmtClock(note.stamps[i].s))),
              title: Text(note.stamps[i].text),
              subtitle: Text(note.stamps[i].src == 'lecturer' ? 'من كلام المحاضر (ترجمة الفيديو)' : 'ملاحظتي',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => PreviewPage(url: _stampUrl(id, note.stamps[i].s), title: widget.link.title))),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => note.stamps.removeAt(i));
                  study.saveSoon();
                },
              ),
            ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Text('أسئلة المراجعة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          FilledButton.tonalIcon(
            onPressed: () async {
              final q = await askQuestion(context);
              if (q != null) {
                setState(() => note.qs.add(q));
                study.saveSoon();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('سؤال'),
          ),
        ]),
        const SizedBox(height: 8),
        if (note.qs.isEmpty)
          Padding(
            padding: EdgeInsets.all(12),
            child: Text('أضف أسئلة من المحاضرة لتختبر نفسك عليها لاحقاً', style: TextStyle(color: kMuted)),
          ),
        for (var i = 0; i < note.qs.length; i++)
          Card(
            color: kSurface,
            child: ListTile(
              title: Text(note.qs[i].q),
              subtitle: Text('${note.qs[i].a}${note.qs[i].right + note.qs[i].wrong > 0 ? '\nصح ${note.qs[i].right} · خطأ ${note.qs[i].wrong}' : ''}',
                  style: TextStyle(color: kMuted)),
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
}

/// The video's own captions with times: copy a line into the notes (it is marked as the lecturer's words)
class _TranscriptPage extends StatefulWidget {
  final MoodleLink link;
  final Note note;
  final List<(int, String)> lines;
  const _TranscriptPage({required this.link, required this.note, required this.lines});
  @override
  State<_TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends State<_TranscriptPage> {
  String q = '';
  @override
  Widget build(BuildContext c) {
    final shown = widget.lines.where((e) => q.isEmpty || e.$2.contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('نص المحاضرة')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث في النص')),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, i) {
              final e = shown[i];
              final added = widget.note.stamps.any((s) => s.s == e.$1 && s.text == e.$2);
              return ListTile(
                dense: true,
                leading: Text(fmtClock(e.$1), style: TextStyle(color: kAccent)),
                title: Text(e.$2),
                trailing: IconButton(
                  icon: Icon(added ? Icons.bookmark_added : Icons.bookmark_add_outlined),
                  onPressed: added
                      ? null
                      : () {
                          setState(() => widget.note.stamps.add(Stamp(e.$1, e.$2, 'lecturer')));
                          widget.note.stamps.sort((a, b) => a.s.compareTo(b.s));
                          study.saveSoon();
                        },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Self-test / exam. Questions come from the lecture notebooks; every answer feeds the spaced review
/// and the understanding indicator. Exam mode: timer, no hints, result with the source lecture of each mistake.
class QuizPage extends StatefulWidget {
  final List<QRef> refs;
  final String title;
  final bool exam;
  final int? minutes;
  final String? cid;
  const QuizPage({super.key, required this.refs, this.title = 'اختبار', this.exam = false, this.minutes, this.cid});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<QRef> qs = (List.of(widget.refs)..shuffle(Random()));
  int i = 0, right = 0, picked = -1;
  bool show = false, finished = false;
  final wrong = <QRef>[];
  Timer? _t;
  late int left = (widget.minutes ?? 0) * 60;

  @override
  void initState() {
    super.initState();
    if (widget.exam && widget.minutes != null) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => left--);
        if (left <= 0) _finish();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _finish() {
    if (finished) return;
    _t?.cancel();
    finished = true;
    if (widget.exam) study.logExam(widget.cid, right, qs.length);
    setState(() {});
  }

  void _answer(bool ok) {
    final r = qs[i];
    study.grade(r.qa, ok);
    if (ok) {
      right++;
    } else {
      wrong.add(r);
    }
    if (i + 1 >= qs.length) {
      _finish();
    } else {
      setState(() {
        i++;
        show = false;
        picked = -1;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final end = finished || i >= qs.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(end ? 'النتيجة' : '${widget.title} · ${i + 1}/${qs.length}'),
        actions: [
          if (!end && widget.exam && widget.minutes != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(child: Text(fmtClock(left < 0 ? 0 : left), style: TextStyle(fontWeight: FontWeight.w800, color: left < 60 ? Colors.redAccent : kAccent))),
            ),
        ],
      ),
      body: Padding(padding: const EdgeInsets.all(18), child: end ? _result(c) : _question(c)),
    );
  }

  Widget _result(BuildContext c) => ListView(children: [
        Icon(wrong.isEmpty ? Icons.emoji_events : Icons.fact_check, size: 64, color: kAccent),
        const SizedBox(height: 12),
        Center(child: Text('$right من ${qs.length}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800))),
        const SizedBox(height: 18),
        if (wrong.isNotEmpty) ...[
          const Text('ما أخطأت فيه (راجع محاضرته):', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final r in wrong)
            Card(
              color: kSurface,
              child: ListTile(
                title: Text(r.qa.q),
                subtitle: Text('الإجابة: ${r.qa.a}${r.link != null ? '\nالمصدر: ${r.link!.title}' : ''}', style: TextStyle(color: kMuted)),
                onTap: r.link == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => NotebookPage(link: r.link!))),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => setState(() {
              qs = List.of(wrong)..shuffle(Random());
              wrong.clear();
              i = 0;
              right = 0;
              show = false;
              picked = -1;
              finished = false;
            }),
            icon: const Icon(Icons.replay),
            label: Text('أعد الأسئلة التي أخطأت فيها (${wrong.length})'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('إنهاء')),
      ]);

  Widget _question(BuildContext c) {
    final r = qs[i], q = r.qa;
    final choice = q.type != 'qa';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LinearProgressIndicator(value: i / qs.length, color: kAccent),
      const SizedBox(height: 20),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(22)),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r.link != null) Text(r.link!.title, style: TextStyle(color: kFaint, fontSize: 12)),
              const SizedBox(height: 6),
              Text(q.q, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.5)),
              if (choice) ...[
                const SizedBox(height: 14),
                for (var k = 0; k < q.opts.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.all(14),
                        backgroundColor: picked < 0 || widget.exam
                            ? (picked == k ? kAccent.withOpacity(0.2) : null)
                            : k == q.ci
                                ? Colors.green.withOpacity(0.25)
                                : picked == k
                                    ? Colors.red.withOpacity(0.25)
                                    : null,
                      ),
                      onPressed: picked >= 0 && !widget.exam ? null : () => setState(() => picked = k),
                      child: Text(q.opts[k], style: const TextStyle(color: Colors.white)),
                    ),
                  ),
              ],
              if (!choice && show) ...[
                const Divider(height: 32),
                Text(q.a.isEmpty ? '(لا توجد إجابة مكتوبة)' : q.a, style: TextStyle(fontSize: 17, color: kSoft, height: 1.6)),
              ],
            ]),
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (choice)
        FilledButton(
          onPressed: picked < 0 ? null : () => _answer(picked == q.ci),
          child: Text(widget.exam ? 'التالي' : 'تأكيد والتالي'),
        )
      else if (!show)
        FilledButton(onPressed: () => setState(() => show = true), child: const Text('إظهار الإجابة'))
      else
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('لم أعرفها'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('عرفتها'))),
        ]),
      if (widget.exam) TextButton(onPressed: _finish, child: const Text('إنهاء الامتحان الآن')),
    ]);
  }
}
