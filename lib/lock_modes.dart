import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'library_page.dart';
import 'links_page.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'nav.dart';
import 'strict_shell.dart';
import 'study.dart';
import 'theme.dart';
import 'web_fs.dart';
import 'yt_embed.dart';

/// Starts a lock over a list of Moodle YouTube videos (folder / playlist lock).
/// Length = sum of their durations (+ extra), at most 3 hours; the videos beyond that are left for the next session.
Future<void> startPlaylistLock(BuildContext c, List<MoodleLink> items) async {
  final ids = <String>[];
  var sec = 0;
  for (final l in items) {
    final id = ytId(l);
    if (id == null || ids.contains(id)) continue;
    final s = study.dur[id] ?? 900;
    if (ids.isNotEmpty && (sec + s) * 1000 > kMaxAppLockMs) break;
    ids.add(id);
    sec += s;
  }
  if (ids.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لا توجد فيديوهات يوتيوب في هذه القائمة')));
    return;
  }
  if (!await ensureLockReady(c) || !c.mounted) return;
  final base = Duration(seconds: sec);
  final extra = await confirmStrict(c, base, max: kMaxAppLockMs, title: 'قفل ${ids.length} فيديو');
  if (extra == null || !c.mounted) return;
  final left = lockMs(base, extra, max: kMaxAppLockMs);
  await ch.invokeMethod('startLock', {'left': left, 'type': 'playlist', 'target': ids.join(',')});
  if (!c.mounted) return;
  Navigator.push(c, MaterialPageRoute(builder: (_) => PlaylistLockPage(ids: ids, leftMs: left)));
}

/// Starts the whole-app lock (free use inside the app; other apps and floating windows are blocked).
Future<void> startAppLock(BuildContext c) async {
  var minutes = 60;
  final ok = await showModalBottomSheet<bool>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('قفل التطبيق كله', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('تتصفح داخل التطبيق بحرية، وكل التطبيقات والنوافذ العائمة الأخرى محجوبة. لا يوجد مخرج طوارئ، والتمديد فقط. الحد الأقصى 3 ساعات.',
              style: TextStyle(color: Colors.white60, height: 1.5)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in [30, 60, 90, 120, 180])
              ChoiceChip(label: Text(fmtMinutes(m)), selected: minutes == m, onSelected: (_) => set(() => minutes = m)),
            ActionChip(
              avatar: const Icon(Icons.edit, size: 16),
              label: Text([30, 60, 90, 120, 180].contains(minutes) ? 'مخصص' : fmtMinutes(minutes)),
              onPressed: () async {
                final n = await askMinutes(ctx, max: 180);
                if (n != null) set(() => minutes = n);
              },
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('اقفل ${fmtMinutes(minutes)}'))),
          ]),
        ]),
      ),
    ),
  );
  if (ok != true || !c.mounted) return;
  if (!await ensureLockReady(c) || !c.mounted) return;
  final left = minutes * 60000;
  await ch.invokeMethod('startLock', {'left': left, 'type': 'app', 'target': ''});
  if (!c.mounted) return;
  Navigator.pushReplacement(c, MaterialPageRoute(builder: (_) => AppLockPage(leftMs: left)));
}

/// Whole-app lock: the normal app runs inside the strict shell (timer, no exit, other apps blocked)
class AppLockPage extends StatefulWidget {
  final int leftMs;
  const AppLockPage({super.key, required this.leftMs});
  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  @override
  void initState() {
    super.initState();
    appLocked.value = true;
  }

  @override
  void dispose() {
    appLocked.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => StrictShell(
        leftMs: widget.leftMs,
        maxMs: kMaxAppLockMs,
        child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => homeBuilder!())),
      );
}

/// Folder / playlist lock: only the listed YouTube videos can be watched, one after another.
class PlaylistLockPage extends StatefulWidget {
  final List<String> ids;
  final int leftMs;
  const PlaylistLockPage({super.key, required this.ids, required this.leftMs});
  @override
  State<PlaylistLockPage> createState() => _PlaylistLockPageState();
}

class _PlaylistLockPageState extends State<PlaylistLockPage> {
  late final WebViewController w;
  final playing = ValueNotifier<bool>(true);
  Timer? _poll, _end;
  int idx = 0;
  bool _advancing = false;

  String get id => widget.ids[idx];

  MoodleLink? get link {
    for (final l in study.links) {
      if (ytId(l) == id) return l;
    }
    return null;
  }

  String get title => link?.title ?? 'فيديو ${idx + 1}';

  // Kills link clicks, hides the navigation UI, forces the page back to the current video
  String get lockJs => '''
(function(){
  if (window.__fl) return; window.__fl = true;
  var id = '$id', base = '${watchUrl(id)}';
  var st = document.createElement('style');
  st.textContent = 'ytm-pivot-bar-renderer,ytm-mobile-topbar-renderer,ytm-item-section-renderer,'
    + 'ytm-related-chip-cloud-renderer,ytm-comments-entry-point-header-renderer,'
    + 'ytm-companion-slot,ytm-rich-section-renderer,.related-chips-slot-wrapper{display:none!important}';
  document.head.appendChild(st);
  document.addEventListener('click', function(e){
    if (e.target.closest && e.target.closest('a')) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  setInterval(function(){
    if (location.href.indexOf('v=' + id) < 0) location.replace(base);
  }, 500);
})();
''';

  @override
  void initState() {
    super.initState();
    study.load();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kChromeUA)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => isYoutube(r.url) && r.url.contains('v=$id')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => w.runJavaScript(lockJs),
      ))
      ..loadRequest(Uri.parse(watchUrl(id)));
    _poll = startPlayPoll(w, playing);
    // When the video ends: mark it done and go to the next one
    _end = Timer.periodic(const Duration(seconds: 2), (_) => _checkEnded());
  }

  Future<void> _checkEnded() async {
    if (_advancing || !mounted) return;
    try {
      final r = await w.runJavaScriptReturningResult("(function(){var v=document.querySelector('video');return v&&v.ended?1:0;})()");
      if ((int.tryParse(r.toString().replaceAll('"', '')) ?? 0) == 1) {
        _advancing = true;
        final l = link;
        if (l != null) study.setDone(l, true);
        if (idx < widget.ids.length - 1) {
          _go(idx + 1);
        }
        await Future.delayed(const Duration(seconds: 3));
        _advancing = false;
      }
    } catch (_) {}
  }

  void _go(int i) {
    if (i < 0 || i >= widget.ids.length) return;
    setState(() => idx = i);
    w.loadRequest(Uri.parse(watchUrl(id)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _end?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final land = MediaQuery.orientationOf(c) == Orientation.landscape;
    final l = link;
    return StrictShell(
      leftMs: widget.leftMs,
      maxMs: kMaxAppLockMs,
      playing: playing,
      child: Column(children: [
        Expanded(child: FsWebView(w, strict: true)),
        if (!land)
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(children: [
              IconButton(
                  tooltip: 'السابق',
                  onPressed: idx > 0 ? () => _go(idx - 1) : null,
                  icon: const Icon(Icons.skip_next)),
              Expanded(
                child: Text('${idx + 1}/${widget.ids.length} · $title',
                    maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              ),
              if (l != null)
                AnimatedBuilder(
                  animation: study,
                  builder: (_, __) => IconButton(
                    tooltip: 'منجز',
                    onPressed: () => study.toggleDone(l),
                    icon: Icon(study.isDone(l) ? Icons.check_circle : Icons.check_circle_outline,
                        color: study.isDone(l) ? Colors.greenAccent : null),
                  ),
                ),
              IconButton(
                  tooltip: 'التالي',
                  onPressed: idx < widget.ids.length - 1 ? () => _go(idx + 1) : null,
                  icon: const Icon(Icons.skip_previous)),
            ]),
          ),
      ]),
    );
  }
}

/// Hub of the three lock types
class LockHubPage extends StatefulWidget {
  const LockHubPage({super.key});
  @override
  State<LockHubPage> createState() => _LockHubPageState();
}

class _LockHubPageState extends State<LockHubPage> {
  @override
  void initState() {
    super.initState();
    study.load();
  }

  Widget _card(IconData i, String t, String s, VoidCallback onTap) => Card(
        color: kSurface,
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: Icon(i, color: kAccent, size: 30),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(s, style: const TextStyle(height: 1.5))),
          onTap: onTap,
        ),
      );

  Future<void> _pickCourse() async {
    final cids = study.courseIds().where((id) => study.videoLinks().any((l) => l.cid == id && !study.isDone(l))).toList();
    if (cids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد فيديوهات غير منجزة. استخرج الروابط من المودل أولاً')));
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('اختر المادة (المجلد)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final id in cids)
            ListTile(
              title: Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${study.videoLinks().where((l) => l.cid == id && !study.isDone(l)).length} فيديو غير منجز'),
              onTap: () => Navigator.pop(ctx, id),
            ),
        ]),
      ),
    );
    if (id == null || !mounted) return;
    await startPlaylistLock(context, study.videoLinks().where((l) => l.cid == id && !study.isDone(l)).toList());
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Row(children: [Icon(Icons.lock_clock, color: kAccent), SizedBox(width: 10), Text('أنواع القفل')])),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          const Text('لا يوجد مخرج طوارئ في أي نوع. المدة تُمدَّد فقط ولا تُقصَّر. عند انتهاء الوقت لا يُغلق شيء، بل يُعرض عليك التمديد.',
              style: TextStyle(color: Colors.white60, height: 1.6)),
          const SizedBox(height: 12),
          _card(Icons.phone_android, 'قفل التطبيق كله', 'تتنقل داخل التطبيق بحرية والباقي محجوب. حتى 3 ساعات.', () => startAppLock(c)),
          _card(Icons.folder_special, 'قفل مجلد / قائمة تشغيل', 'فيديوهات مادة واحدة متتابعة، مدة القفل مجموع مددها. حتى 3 ساعات.', _pickCourse),
          _card(Icons.smart_display, 'قفل فيديو واحد', 'افتح الفيديو من يوتيوب أو المودل أو المحمّلة ثم «الوضع الصارم». مدة القفل = مدة الفيديو، حتى ساعة ونصف.', () {
            showModalBottomSheet<void>(
              context: c,
              builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    leading: const Icon(Icons.smart_display),
                    title: const Text('يوتيوب'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(c, MaterialPageRoute(builder: (_) => const BrowserPage()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: const Text('المودل'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(c, MaterialPageRoute(builder: (_) => const MoodlePage()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: const Text('الفيديوهات المحمّلة'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(c, MaterialPageRoute(builder: (_) => const LibraryPage()));
                    },
                  ),
                ]),
              ),
            );
          }),
        ]),
      );
}
