import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ai.dart';
import 'study.dart';
import 'theme.dart';

// ---------------- hub: general assistant + one specialised assistant per course ----------------
class AiHubPage extends StatefulWidget {
  const AiHubPage({super.key});
  @override
  State<AiHubPage> createState() => _AiHubPageState();
}

class _AiHubPageState extends State<AiHubPage> {
  @override
  void initState() {
    super.initState();
    ai.load();
  }

  String _preview(String cid) {
    final l = ai.chats[cid];
    if (l == null || l.isEmpty) return 'ابدأ محادثة جديدة';
    final t = l.last.text.replaceAll('\n', ' ');
    return t.length > 70 ? '${t.substring(0, 70)}…' : t;
  }

  Widget _tile(BuildContext c, String cid, String title, IconData icon) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: kAccent.withOpacity(.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: kAccent),
          ),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(_preview(cid), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kMuted)),
          trailing: Icon(Icons.chevron_left, color: kMuted),
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => AiChatPage(cid: cid, title: title))),
        ),
      );

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: Listenable.merge([ai, study]),
        builder: (_, __) => Scaffold(
          appBar: AppBar(
            title: const Text('المساعد الذكي'),
            actions: [
              IconButton(tooltip: 'إعدادات الذكاء', icon: const Icon(Icons.tune_rounded), onPressed: () => showAiSettings(c)),
              const SizedBox(width: 4),
            ],
          ),
          body: !ai.ready
              ? const Center(child: CircularProgressIndicator())
              : !ai.hasKey
                  ? ListView(padding: const EdgeInsets.all(16), children: const [AiSetupCard()])
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('لكل مادة مساعد متخصص يعرف فصولها ومحاضراتها ومواعيدها. المحادثات محفوظة على هاتفك فقط.', style: TextStyle(color: kMuted, height: 1.6)),
                      ),
                      _tile(c, '', 'المساعد العام', Icons.auto_awesome),
                      for (final id in study.courseIds()) _tile(c, id, study.courses[id] ?? id, Icons.school_rounded),
                    ]),
        ),
      );
}

// ---------------- how to get a free key ----------------
class AiSteps extends StatelessWidget {
  const AiSteps({super.key});
  static const steps = [
    'افتح الرابط الرسمي: Google AI Studio (زر النسخ أدناه) في المتصفح.',
    'سجّل الدخول بحساب Google.',
    'اضغط على Create API Key.',
    'اختر مشروعاً موجوداً أو أنشئ مشروعاً جديداً (Create project).',
    'انتظر إنشاء المفتاح ثم اضغط Copy.',
    'ارجع إلى هنا والصق المفتاح في الخانة ثم احفظ.',
  ];

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 11, backgroundColor: kAccent.withOpacity(.16), child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAccent))),
              const SizedBox(width: 10),
              Expanded(child: Text(steps[i], style: const TextStyle(height: 1.5))),
            ]),
          ),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: kAiKeyUrl));
            ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('نُسخ الرابط: الصقه في المتصفح')));
          },
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('نسخ رابط Google AI Studio'),
        ),
        const SizedBox(height: 10),
        Text('لا تشارك المفتاح مع أحد؛ فهو يستهلك حصتك من Gemini. المفتاح يُحفظ مشفّراً على هاتفك. الأسئلة التي تكتبها (مع اسم المادة وعناوين محاضراتها) تُرسل إلى Google لتوليد الجواب.',
            style: TextStyle(color: kMuted, height: 1.6, fontSize: 12.5)),
      ]);
}

class AiSetupCard extends StatefulWidget {
  const AiSetupCard({super.key});
  @override
  State<AiSetupCard> createState() => _AiSetupCardState();
}

class _AiSetupCardState extends State<AiSetupCard> {
  final ctl = TextEditingController();
  bool hide = true;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = ctl.text.trim();
    if (v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الصق المفتاح أولاً')));
      return;
    }
    await ai.setKey(v);
  }

  @override
  Widget build(BuildContext c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: kAccent),
              const SizedBox(width: 10),
              const Expanded(child: Text('فعّل المساعد الذكي مجاناً', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('تحتاج فقط إلى مفتاح مجاني من Google، بلا خادم ولا إعداد. الموديل الافتراضي: $kDefaultAiModel (يمكن تغييره من الإعدادات).', style: TextStyle(color: kMuted, height: 1.6)),
            const SizedBox(height: 14),
            const AiSteps(),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              obscureText: hide,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'الصق المفتاح هنا (AIza...)',
                filled: true,
                fillColor: kSurface2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => hide = !hide)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('احفظ وابدأ'))),
          ]),
        ),
      );
}

// ---------------- settings ----------------
Future<void> showAiSettings(BuildContext c) async {
  final model = TextEditingController(text: ai.model);
  final key = TextEditingController();
  await showModalBottomSheet<void>(
    context: c,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('إعدادات الذكاء الاصطناعي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          const Text('اسم الموديل', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: model,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: kDefaultAiModel, filled: true, fillColor: kSurface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 4),
          Text('اسم الموديل فقط، وليس رابط الـ API. إن ظهر خطأ «الموديل غير موجود» فجرّب اسماً آخر من Google AI Studio.', style: TextStyle(color: kMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 6),
          Row(children: [
            FilledButton.tonal(
              onPressed: () {
                ai.setModel(model.text);
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('حُفظ الموديل')));
              },
              child: const Text('حفظ الموديل'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => model.text = kDefaultAiModel, child: const Text('الافتراضي')),
          ]),
          const Divider(height: 28),
          Text(ai.hasKey ? 'استبدال المفتاح' : 'المفتاح', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(hintText: 'الصق المفتاح الجديد', filled: true, fillColor: kSurface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            FilledButton.tonal(
              onPressed: () async {
                if (key.text.trim().isEmpty) return;
                await ai.setKey(key.text);
                key.clear();
                if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('حُفظ المفتاح')));
              },
              child: const Text('حفظ المفتاح'),
            ),
            const SizedBox(width: 8),
            if (ai.hasKey)
              TextButton(
                onPressed: () async {
                  await ai.setKey('');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('حذف المفتاح', style: TextStyle(color: kAccent)),
              ),
          ]),
          const Divider(height: 28),
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: ctx,
                builder: (d) => AlertDialog(
                  title: const Text('حذف كل المحادثات؟'),
                  content: const Text('تُحذف محادثات كل المواد من هذا الهاتف.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))],
                ),
              );
              if (ok == true) ai.clearAll();
            },
            icon: Icon(Icons.delete_outline, color: kAccent),
            label: Text('حذف كل المحادثات', style: TextStyle(color: kAccent)),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('كيف أحصل على مفتاح مجاني؟', style: TextStyle(fontWeight: FontWeight.w700)),
            children: const [Align(alignment: AlignmentDirectional.centerStart, child: AiSteps())],
          ),
        ]),
      ),
    ),
  );
}

// ---------------- chat ----------------
class AiChatPage extends StatefulWidget {
  final String cid, title;
  const AiChatPage({super.key, required this.cid, required this.title});
  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final input = TextEditingController();
  final sc = ScrollController();

  @override
  void initState() {
    super.initState();
    ai.load();
    ai.addListener(_down);
    _down();
  }

  @override
  void dispose() {
    ai.removeListener(_down);
    input.dispose();
    sc.dispose();
    super.dispose();
  }

  void _down() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? q]) async {
    final t = (q ?? input.text).trim();
    if (t.isEmpty) return;
    input.clear();
    await ai.send(widget.cid, t);
  }

  List<String> get _quick => widget.cid.isEmpty
      ? const ['اقترح لي طريقة مذاكرة فعّالة', 'كيف أنظّم وقتي قبل الاختبارات؟', 'كيف أركّز أكثر أثناء المحاضرة؟']
      : const ['لخّص لي أهم أفكار المادة', 'ما أهم ما قد يأتي في الاختبار؟', 'اشرح لي أصعب موضوع ببساطة', 'اختبرني بخمسة أسئلة'];

  Widget _bubble(AiMsg m) {
    final mine = m.role == 'user';
    final bg = mine ? kAccent : m.error ? kWarn.withOpacity(.16) : kSurface;
    final fg = mine ? Colors.white : kInk;
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: mine ? null : Border.all(color: kOutline),
        ),
        child: SelectableText(m.text, style: TextStyle(color: fg, height: 1.6, fontSize: 15)),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: ai,
        builder: (_, __) {
          final msgs = ai.chats[widget.cid] ?? const <AiMsg>[];
          final busy = ai.isBusy(widget.cid);
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                if (msgs.isNotEmpty)
                  IconButton(
                    tooltip: 'محادثة جديدة',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: c,
                        builder: (d) => AlertDialog(
                          title: const Text('مسح هذه المحادثة؟'),
                          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('مسح'))],
                        ),
                      );
                      if (ok == true) ai.clearChat(widget.cid);
                    },
                  ),
                IconButton(tooltip: 'إعدادات الذكاء', icon: const Icon(Icons.tune_rounded), onPressed: () => showAiSettings(c)),
              ],
            ),
            body: !ai.ready
                ? const Center(child: CircularProgressIndicator())
                : !ai.hasKey
                    ? ListView(padding: const EdgeInsets.all(16), children: const [AiSetupCard()])
                    : Column(children: [
                        Expanded(
                          child: msgs.isEmpty
                              ? ListView(padding: const EdgeInsets.all(20), children: [
                                  const SizedBox(height: 30),
                                  Icon(Icons.auto_awesome, size: 42, color: kAccent),
                                  const SizedBox(height: 12),
                                  Text(widget.cid.isEmpty ? 'اسألني أي شيء عن دراستك' : 'مساعدك المتخصص في هذه المادة', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 16),
                                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                                    for (final q in _quick) ActionChip(label: Text(q), onPressed: () => _send(q)),
                                  ]),
                                ])
                              : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), children: [
                                  for (final m in msgs) _bubble(m),
                                  if (busy)
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                          const SizedBox(width: 10),
                                          Text('جارٍ التفكير…', style: TextStyle(color: kMuted)),
                                        ]),
                                      ),
                                    ),
                                ]),
                        ),
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                            decoration: BoxDecoration(color: kBg, border: Border(top: BorderSide(color: kOutline))),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Expanded(
                                child: TextField(
                                  controller: input,
                                  minLines: 1,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: 'اكتب سؤالك…',
                                    filled: true,
                                    fillColor: kSurface2,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: busy ? null : _send,
                                icon: const Icon(Icons.arrow_upward_rounded),
                                style: IconButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.white),
                              ),
                            ]),
                          ),
                        ),
                      ]),
          );
        },
      );
}
