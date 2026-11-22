// Opens links extracted from Moodle INSIDE the app, the way Al-Murshid / ALMULZIM do:
// YouTube lectures and Moodle videos play in the app's own player (no YouTube app, no suggestions),
// documents open in the in-app viewer, other sites are limited to Moodle / YouTube / Google Drive,
// and every item can be downloaded (YouTube with a quality choice).
import 'lock_ctl.dart';
import 'lock_setup.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'browser_page.dart' show isYoutube;
import 'channel.dart';
import 'downloads.dart';
import 'moodle_page.dart' show isMoodle;
import 'preview_page.dart';
import 'storage.dart';
import 'theme.dart';
import 'yt_embed.dart' show downloadYoutubeVideo;

void _toast(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));

/// Moodle, YouTube and Google Drive / Docs only
bool allowedHost(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  final h = u.host.toLowerCase();
  return isMoodle(url) || isYoutube(url) || h == 'drive.google.com' || h == 'docs.google.com' || h.endsWith('.google.com') && h.startsWith('drive');
}

int qualityRank(String label) => int.tryParse(RegExp(r'^\d+').stringMatch(label) ?? '') ?? 0;

class YtOption {
  final String label; // "720p" or "audio"
  final bool audio;
  final int bytes;
  YtOption(this.label, this.audio, this.bytes);
  String get text => audio ? 'صوت فقط' : label;
}

/// Qualities of a YouTube video (video + audio in one file) and the audio-only option
Future<List<YtOption>> youtubeOptions(String id) async {
  final yt = YoutubeExplode();
  try {
    final m = await yt.videos.streamsClient.getManifest(VideoId(id)).timeout(const Duration(seconds: 20));
    final best = <String, MuxedStreamInfo>{};
    for (final s in m.muxed) {
      final cur = best[s.videoQualityLabel];
      if (cur == null || s.bitrate.bitsPerSecond > cur.bitrate.bitsPerSecond) best[s.videoQualityLabel] = s;
    }
    final opts = best.values.map((s) => YtOption(s.videoQualityLabel, false, s.size.totalBytes)).toList()
      ..sort((a, b) => qualityRank(b.label).compareTo(qualityRank(a.label)));
    if (m.audioOnly.isNotEmpty) opts.add(YtOption('audio', true, m.audioOnly.withHighestBitrate().size.totalBytes));
    return opts;
  } finally {
    yt.close();
  }
}

/// Direct video+audio stream (up to 720p). The first URL the server really serves wins.
Future<String?> youtubeStreamUrl(String id) async {
  final yt = YoutubeExplode();
  try {
    final m = await yt.videos.streamsClient.getManifest(VideoId(id)).timeout(const Duration(seconds: 20));
    final all = m.muxed.toList();
    if (all.isEmpty) return null;
    all.sort((a, b) => qualityRank(b.videoQualityLabel).compareTo(qualityRank(a.videoQualityLabel)));
    final fit = all.where((s) => qualityRank(s.videoQualityLabel) <= 720).toList();
    final ordered = [...fit, ...all.where((s) => !fit.contains(s)).toList().reversed];
    for (final s in ordered.take(4)) {
      if (await _serves(s.url.toString())) return s.url.toString();
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    yt.close();
  }
}

Future<bool> _serves(String url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final r = await c.getUrl(Uri.parse(url));
    r.headers.set('range', 'bytes=0-1');
    final res = await r.close().timeout(const Duration(seconds: 8));
    await res.drain<void>();
    return res.statusCode != 403 && res.statusCode != 404 && res.statusCode != 410;
  } catch (_) {
    return false;
  } finally {
    c.close(force: true);
  }
}

Future<T> _spin<T>(BuildContext c, Future<T> f) async {
  showDialog<void>(context: c, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
  try {
    return await f;
  } finally {
    if (c.mounted) Navigator.of(c, rootNavigator: true).pop();
  }
}

/// One entry point for tapping an extracted link. [group] is the crawler's group (yt, video, pdf, doc, file, ext).
Future<void> openLinkInApp(BuildContext c,
    {required String url,
    required String title,
    required String group,
    required void Function(String url) onOpenDoc}) async {
  final u = Uri.tryParse(url);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
    _toast(c, 'رابط غير صالح');
    return;
  }
  final yid = VideoId.parseVideoId(url);
  if (yid != null) {
    final su = await _spin(c, youtubeStreamUrl(yid));
    if (!c.mounted) return;
    if (su != null) {
      await Navigator.push(c, MaterialPageRoute(builder: (_) => StreamPlayerPage(url: su, title: title, resumeKey: 'yt:$yid', lockType: 'yt', lockTarget: yid)));
    } else {
      await Navigator.push(c, MaterialPageRoute(builder: (_) => PreviewPage(url: url, title: title, youtubeId: yid)));
    }
    return;
  }
  if (group == 'pdf' || group == 'doc') {
    _toast(c, 'جاري فتح المستند...');
    onOpenDoc(url);
    return;
  }
  if (isMoodle(url) && (group == 'video' || isVideo(Uri.decodeFull(u.path)))) {
    final ck = await cookiesFor(url);
    if (!c.mounted) return;
    await Navigator.push(
        c,
        MaterialPageRoute(
            builder: (_) => StreamPlayerPage(
                url: url, title: title, resumeKey: 'moodle:$url', lockType: 'stream', lockTarget: url, headers: {if (ck.isNotEmpty) 'Cookie': ck})));
    return;
  }
  if (group == 'file') {
    await showLinkActions(c, url: url, title: title, group: group, onOpenDoc: onOpenDoc);
    return;
  }
  if (!allowedHost(url)) {
    Clipboard.setData(ClipboardData(text: url));
    _toast(c, 'هذا الرابط خارج المواقع المسموحة (مودل، يوتيوب، درايف) — نُسخ الرابط');
    return;
  }
  await Navigator.push(c, MaterialPageRoute(builder: (_) => PreviewPage(url: url, title: title)));
}

/// Long-press / file menu: open as document, download, copy link
Future<void> showLinkActions(BuildContext c,
    {required String url,
    required String title,
    required String group,
    required void Function(String url) onOpenDoc}) async {
  final yid = VideoId.parseVideoId(url);
  final canDownload = yid != null || isMoodle(url);
  await showModalBottomSheet<void>(
    context: c,
    backgroundColor: kSurface,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (group == 'file' && isMoodle(url))
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('فتح كمستند'),
            onTap: () {
              Navigator.pop(sheet);
              onOpenDoc(url);
            },
          ),
        if (canDownload)
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('تحميل'),
            subtitle: Text(yid != null ? 'اختيار الجودة ثم المجلد' : 'يُحفظ بجلسة دخولك إلى المودل'),
            onTap: () {
              Navigator.pop(sheet);
              if (yid != null) {
                downloadYoutubeVideo(c, yid, title: title);
              } else {
                downloadDirect(c, url, title);
              }
            },
          ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('نسخ الرابط'),
          onTap: () {
            Navigator.pop(sheet);
            Clipboard.setData(ClipboardData(text: url));
            _toast(c, 'تم نسخ الرابط');
          },
        ),
      ]),
    ),
  );
}

/// Plain file (Moodle resource): choose folder + name, then download with the Moodle session
Future<void> downloadDirect(BuildContext c, String url, String title) async {
  final dir = await chooseFolder(c);
  if (dir == null || !c.mounted) return;
  final r = await askNameNumber(c, title: 'اسم الملف', initialName: safeName(title), initialNumber: null);
  if (r == null || !c.mounted) return;
  final ok = dl.startFile(url, dir, name: r.name.isEmpty ? safeName(title) : r.name, number: r.number);
  _toast(c, ok ? 'أُضيف إلى التحميلات' : 'هذا الملف يُحمَّل إلى هذا المجلد بالفعل');
}

/// Plays a network video (YouTube stream or Moodle file with the login cookie) in the app's own player.
class StreamPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final String resumeKey;
  final Map<String, String> headers;
  final String lockType, lockTarget; // how a video lock on this video is resumed after a restart (yt id / Moodle file url)
  const StreamPlayerPage(
      {super.key, required this.url, required this.title, required this.resumeKey, this.headers = const {}, this.lockType = '', this.lockTarget = ''});
  @override
  State<StreamPlayerPage> createState() => _StreamPlayerPageState();
}

class _StreamPlayerPageState extends State<StreamPlayerPage> {
  late final VideoPlayerController v;
  bool ready = false, controls = true, landscape = false;
  String? error;
  double speed = 1.0;
  Timer? _hide;
  final playing = ValueNotifier<bool>(true); // tells the video lock whether the video is playing

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    v = VideoPlayerController.networkUrl(Uri.parse(widget.url), httpHeaders: widget.headers);
    v.addListener(() => playing.value = v.value.isPlaying);
    if (lock.vidOn && widget.lockType.isNotEmpty) lock.attachPlaying(playing); // resumed after a restart
    _init();
  }

  Future<void> _init() async {
    try {
      await v.initialize();
      final saved = await loadPos(widget.resumeKey);
      if (saved > 3000 && Duration(milliseconds: saved) < v.value.duration - const Duration(seconds: 5)) {
        await v.seekTo(Duration(milliseconds: saved));
      }
      await v.play();
      if (!mounted) return;
      setState(() => ready = true);
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تشغيل الفيديو (قد تكون الجلسة منتهية: افتح المودل وسجّل الدخول)');
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && v.value.isPlaying) setState(() => controls = false);
    });
  }

  // Lock this video: you cannot leave it until the time ends (the app lock, if any, pauses meanwhile)
  Future<void> _lockVideo() async {
    if (widget.lockType.isEmpty) return;
    if (lock.vidOn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('قفل الفيديو يعمل. اضغط الشريط العلوي لتمديده')));
      return;
    }
    if (!await ensureLockReady(context) || !mounted) return;
    final remain = v.value.duration - v.value.position;
    final extra = await confirmStrict(context, remain, max: kMaxVideoLockMs, title: 'قفل الفيديو');
    if (extra == null || !mounted) return;
    await lock.startVideo(lockMs(remain, extra, max: kMaxVideoLockMs), widget.lockType, widget.lockTarget);
    lock.attachPlaying(playing);
  }

  void _seekBy(int sec) {
    final p = v.value.position + Duration(seconds: sec);
    final max = v.value.duration;
    v.seekTo(p < Duration.zero ? Duration.zero : (p > max ? max : p));
    _scheduleHide();
  }

  Future<void> _rotate() async {
    landscape = !landscape;
    await SystemChrome.setPreferredOrientations(
        landscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    lock.attachPlaying(null);
    if (ready) {
      setPos(widget.resumeKey, v.value.position.inMilliseconds);
      flushPos();
    }
    v.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: lock,
      builder: (_, __) => PopScope(
        canPop: !lock.vidOn,
        child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
                    ]),
                  ),
                )
              : !ready
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => controls = !controls);
                        if (controls) _scheduleHide();
                      },
                      child: Stack(children: [
                        Center(
                            child: AspectRatio(
                                aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio, child: VideoPlayer(v))),
                        if (controls) _controls(),
                      ]),
                    ),
        ),
      )));

  Widget _controls() => Container(
        color: Colors.black54,
        child: Column(children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: lock.vidOn ? null : () => Navigator.pop(context)),
            Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
            if (widget.lockType.isNotEmpty)
              IconButton(
                tooltip: 'قفل الفيديو',
                icon: Icon(lock.vidOn ? Icons.lock_rounded : Icons.lock_outline_rounded, color: lock.vidOn ? Colors.redAccent : Colors.white),
                onPressed: _lockVideo,
              ),
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed, color: Colors.white),
              onSelected: (s) {
                setState(() => speed = s);
                v.setPlaybackSpeed(s);
              },
              itemBuilder: (_) => [
                for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  CheckedPopupMenuItem(value: s, checked: s == speed, child: Text('${s}x')),
              ],
            ),
            IconButton(
                icon: Icon(landscape ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _rotate),
          ]),
          const Spacer(),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: v,
            builder: (_, val, __) {
              final total = val.duration.inMilliseconds;
              final pos = val.position.inMilliseconds.clamp(0, total == 0 ? 1 : total).toDouble();
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(iconSize: 36, icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () => _seekBy(-10)),
                  IconButton(
                    iconSize: 56,
                    icon: Icon(val.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                    onPressed: () {
                      val.isPlaying ? v.pause() : v.play();
                      _scheduleHide();
                    },
                  ),
                  IconButton(iconSize: 36, icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () => _seekBy(10)),
                ]),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(children: [
                    Padding(padding: const EdgeInsets.only(left: 12), child: Text(_fmt(val.position), style: const TextStyle(color: Colors.white))),
                    Expanded(
                      child: Slider(
                        value: pos,
                        max: total == 0 ? 1 : total.toDouble(),
                        onChanged: (x) => v.seekTo(Duration(milliseconds: x.toInt())),
                        onChangeEnd: (_) => _scheduleHide(),
                      ),
                    ),
                    Padding(padding: const EdgeInsets.only(right: 12), child: Text(_fmt(val.duration), style: const TextStyle(color: Colors.white))),
                  ]),
                ),
              ]);
            },
          ),
        ]),
      );
}
