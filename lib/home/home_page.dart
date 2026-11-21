import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../browser_page.dart';
import '../channel.dart';
import '../design/focus_dial.dart';
import '../docs.dart';
import '../library_page.dart';
import '../lock_modes.dart';
import '../lock_setup.dart';
import '../moodle_page.dart';
import '../storage.dart';
import '../study_page.dart';
import '../theme.dart';

/// Home: header → the safe-dial (primary action) → "rooms" → how strict mode works.
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  bool? lockReady;
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    _status();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askStorage());
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  // Offer the public folder (survives uninstall, visible in file managers)
  Future<void> _askStorage() async {
    if (await hasAllFiles() || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ الملفات خارج التطبيق'),
        content: const Text(
            'اسمح بالوصول لمجلد FocusLock على الجهاز لتبقى فيديوهاتك ومستنداتك محفوظة عند حذف التطبيق وإعادة تثبيته، '
            'ولتضيف ملفات إليه من مدير الملفات فتظهر داخل التطبيق.\n\nالمسار: FocusLock/videos و FocusLock/documents'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('السماح')),
        ],
      ),
    );
    if (ok == true) await ch.invokeMethod('requestAllFiles');
  }

  Future<void> _status() async {
    try {
      final owner = await ch.invokeMethod<bool>('isDeviceOwner') ?? false;
      final acc = await ch.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      if (mounted) setState(() => lockReady = owner || acc);
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _status();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'ليل هادئ، وتركيز أعمق';
    if (h < 12) return 'صباح التركيز';
    if (h < 17) return 'ظهر منتج';
    if (h < 21) return 'مساء الإنجاز';
    return 'ختام يوم بتركيز';
  }

  // ───────────────────────── pieces ─────────────────────────

  Widget _header() => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text.rich(TextSpan(
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: .2, color: kText),
                  children: const [
                    TextSpan(text: 'Focus'),
                    TextSpan(text: ' Lock', style: TextStyle(color: kAccent)),
                  ],
                )),
              ),
            ),
            const SizedBox(height: 2),
            Text(_greeting(), style: const TextStyle(color: kTextDim, fontSize: 13)),
          ]),
        ),
        _pill(Icons.fingerprint, 'محمي ببصمتك', kMint),
      ]);

  Widget _pill(IconData i, String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: col.withOpacity(.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: col.withOpacity(.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: col),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(color: col, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _dial(BuildContext c) {
    final ready = lockReady;
    return Center(
      child: SizedBox(
        width: 280,
        child: FocusDial(
          armed: ready,
          title: ready == true ? 'القفل جاهز' : (ready == null ? 'جارٍ الفحص…' : 'القفل غير مفعّل'),
          caption: ready == true ? 'اضغط لاختيار نوع القفل' : (ready == null ? '' : 'اضغط لتفعيله'),
          onTap: () {
            if (ready == false) {
              ensureLockReady(c).then((_) => _status());
            } else {
              _open(const LockHubPage());
            }
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
        child: Row(children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
        ]),
      );

  Widget _room({
    required IconData icon,
    required String title,
    required String sub,
    required Color tint,
    required Widget page,
    bool wide = false,
  }) {
    final badge = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tint.withOpacity(.14),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tint.withOpacity(.35)),
      ),
      child: Icon(icon, color: tint, size: 24),
    );
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      const SizedBox(height: 3),
      Text(sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, height: 1.4, color: kTextDim)),
    ]);
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _open(page),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: kOutline)),
          child: wide
              ? Row(children: [
                  badge,
                  const SizedBox(width: 14),
                  Expanded(child: texts),
                  Icon(Icons.chevron_left_rounded, color: tint),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  badge,
                  const SizedBox(height: 22),
                  texts,
                ]),
        ),
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]),
      );

  Widget _timeline() {
    const steps = [
      ['١', 'افتح فيديو', 'من يوتيوب أو المودل أو المحمّلة، ثم اضغط «الوضع الصارم».'],
      ['٢', 'المدة = مدة الفيديو', 'ويمكنك إضافة وقت إضافي قبل البدء أو أثناءه.'],
      ['٣', 'عند الانتهاء', 'لا يُغلق الفيديو؛ يُعرض عليك تمديد فترة التركيز.'],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: cardBox(22),
      child: Column(children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 30,
                child: Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kAccent.withOpacity(.14),
                      border: Border.all(color: kAccent.withOpacity(.5)),
                    ),
                    child: Text(steps[i][0],
                        style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  if (i < steps.length - 1)
                    Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: kOutline)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 18 : 0, top: 3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i][1], style: const TextStyle(fontWeight: FontWeight.w700, color: kText)),
                    const SizedBox(height: 3),
                    Text(steps[i][2], style: const TextStyle(color: kTextDim, height: 1.55, fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    var n = 0;
    Widget r(Widget w) => _Reveal(parent: _enter, index: n++, child: w);
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
          r(_header()),
          const SizedBox(height: 14),
          r(_dial(c)),
          r(_sectionTitle('غرف التركيز')),
          r(_room(
            icon: Icons.event_note_rounded,
            title: 'المرشد الدراسي',
            sub: 'خطة يومية، مواعيد التسليم، دفتر واختبارات',
            tint: kAccent,
            page: const StudyPage(),
            wide: true,
          )),
          const SizedBox(height: 12),
          r(_pair(
            _room(
              icon: Icons.smart_display_rounded,
              title: 'يوتيوب',
              sub: 'متصفح مقيّد وتحميل',
              tint: const Color(0xFFFF6B6B),
              page: const BrowserPage(),
            ),
            _room(
              icon: Icons.school_rounded,
              title: 'المودل',
              sub: 'محاضرات الجامعة ومستنداتها',
              tint: kGold,
              page: const MoodlePage(),
            ),
          )),
          const SizedBox(height: 12),
          r(_pair(
            _room(
              icon: Icons.video_library_rounded,
              title: 'الفيديوهات',
              sub: 'المحمّلة حسب المواد',
              tint: const Color(0xFFB69CFF),
              page: const LibraryPage(),
            ),
            _room(
              icon: Icons.description_rounded,
              title: 'المستندات',
              sub: 'PDF وWord وExcel وPowerPoint',
              tint: kMint,
              page: const DocsPage(),
            ),
          )),
          const SizedBox(height: 12),
          r(_room(
            icon: Icons.lock_clock_rounded,
            title: 'أنواع القفل',
            sub: 'قفل التطبيق · المجلد · الفيديو',
            tint: const Color(0xFF8EC5FF),
            page: const LockHubPage(),
            wide: true,
          )),
          r(_sectionTitle('كيف يعمل الوضع الصارم')),
          r(_timeline()),
        ]),
      ),
    );
  }
}

/// Fade + slight rise, staggered by [index], driven by one shared controller.
class _Reveal extends StatelessWidget {
  final Animation<double> parent;
  final int index;
  final Widget child;
  const _Reveal({required this.parent, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = math.min(0.09 * index, 0.6);
    final a = parent.drive(CurveTween(curve: Interval(start, start + 0.4, curve: Curves.easeOutCubic)));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: a.drive(Tween<Offset>(begin: const Offset(0, .06), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
