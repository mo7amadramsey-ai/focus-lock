import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'library_page.dart';
import 'links_page.dart';
import 'lock_ctl.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'nav.dart';
import 'strict_shell.dart';
import 'study.dart';
import 'theme.dart';
import 'web_fs.dart';
import 'yt_embed.dart';

/// Starts a lock over a list of Moodle YouTube videos (folder / playlist lock).
/// Length = sum of their durations (+ extra), at most 1.5 hours (actual playing time); the videos beyond that are left for the next session.
Future<void> startPlaylistLock(BuildContext c, List<MoodleLink> items) async {
  final ids = <String>[];
  var sec = 0;
  for (final l in items) {
    final id = ytId(l);
    if (id == null || ids.contains(id)) continue;
    final s = study.dur[id] ?? 900;
    if (ids.isNotEmpty && (sec + s) * 1000 > kMaxVideoLockMs) break;
    ids.add(id);
    sec += s;
  }
  if (ids.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لا توجد فيديوهات يوتيوب في هذه القائمة')));
    return;
  }
  if (!await ensureLockReady(c) || !c.mounted) return;
  final base = Duration(seconds: sec);
  final extra = await confirmStrict(c, base, max: kMaxVideoLockMs, title: 'قفل ${ids.length} فيديو');
  if (extra == null || !c.mounted) return;
  final left = lockMs(base, extra, max: kMaxVideoLockMs);
  await lock.startVideo(left, 'playlist', ids.join(','));
  if (!c.mounted) return;
  Navigator.push(c, MaterialPageRoute(builder: (_) => PlaylistLockPage(ids: ids, leftMs: left)));
}

/// Starts the whole-app lock: you cannot leave the app, everything inside the app works as usual.
/// A thin bar on top shows the time left. Up to 3 hours, no emergency exit, extend only.
Future<void> startAppLock(BuildContext c) async {
  if (lock.appOn) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('الوضع الصارم يعمل الآن، اضغط الشريط العلوي لتمديده')));
    return;
  }
  var minutes = 60;
  final ok = await showModalBottomSheet<bool>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الوضع الصارم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('يمنعك من الخروج من التطبيق فقط. تستخدمه كله بحرية، وشريط رفيع في الأعلى يريك الوقت المتبقي. لا يوجد مخرج طوارئ، والتمديد فقط. حتى 3 ساعات.',
              style: TextStyle(color: kMuted, height: 1.5)),
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
            Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('ابدأ ${fmtMinutes(minutes)}'))),
          ]),
        ]),
      ),
    ),
  );
  if (ok != true || !c.mounted) return;
  if (!await ensureLockReady(c) || !c.mounted) return;
  await lock.startApp(minutes * 60000);
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

  // A note tied to the second now playing (kept in that lecture's notebook)
  Future<void> _stampHere() async {
    var sec = 0;
    try {
      final r = await w.runJavaScriptReturningResult(
          "(function(){var v=document.querySelector('video');return v?Math.floor(v.currentTime):0;})()");
      sec = int.tryParse(r.toString().replaceAll('"', '')) ?? 0;
    } catch (_) {}
    final l = link;
    if (l == null || !mounted) return;
    final tc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملاحظة عند ${fmtClock(sec)}'),
        content: TextField(controller: tc, autofocus: true, decoration: const InputDecoration(hintText: 'الملاحظة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && tc.text.trim().isNotEmpty) {
      final n = study.ensureNote(l);
      n.stamps.add(Stamp(sec, tc.text.trim()));
      n.stamps.sort((a, b) => a.s.compareTo(b.s));
      study.saveSoon();
    }
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
      maxMs: kMaxVideoLockMs,
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
              IconButton(tooltip: 'ملاحظة عند هذه الثانية', onPressed: _stampHere, icon: const Icon(Icons.add_comment_outlined)),
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
