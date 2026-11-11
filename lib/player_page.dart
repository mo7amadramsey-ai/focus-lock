import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'channel.dart';
import 'docs.dart' show baseName;
import 'lock_setup.dart';
import 'storage.dart';
import 'strict_shell.dart';
import 'theme.dart';

String fmtDur(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
      : '${d.inMinutes}:${two(d.inSeconds % 60)}';
}

String titleOf(String path) => baseName(path).replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');

const _speeds = [1.0, 1.25, 1.5, 2.0, 0.5, 0.75];

/// Local video player styled like the YouTube app.
/// endMillis == null -> normal playback (up-next list, auto-play next video).
/// endMillis != null -> strict mode (timer = video length, fixed at start).
class PlayerPage extends StatefulWidget {
  final String path;
  final int? endMillis;
  const PlayerPage({super.key, required this.path, this.endMillis});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController v;
  bool ready = false, showCtl = true, fullscreen = false, leaving = false, toStrict = false;
  String? error;
  Timer? _hide, _flashT;
  String? flash;
  bool flashLeft = false;
  double speed = 1.0;
  List<File> siblings = [];

  bool get strict => widget.endMillis != null;
  File get me => File(widget.path);

  File? get nextFile {
    final i = siblings.indexWhere((f) => f.path == widget.path);
    return i >= 0 && i + 1 < siblings.length ? siblings[i + 1] : null;
  }

  @override
  void initState() {
    super.initState();
    siblings = me.parent.listSync().whereType<File>().where((f) => isVideo(f.path)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    v = VideoPlayerController.file(me);
    v.initialize().then((_) {
      v.play();
      v.addListener(_onTick);
      if (mounted) setState(() => ready = true);
      _poke();
    }).catchError((e) {
      if (mounted) setState(() => error = e.toString());
    });
    if (!strict) WakelockPlus.enable(); // strict mode handles it in StrictShell
  }

  @override
  void dispose() {
    _hide?.cancel();
    _flashT?.cancel();
    v.removeListener(_onTick);
    v.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!strict && !toStrict) WakelockPlus.disable();
    super.dispose();
  }

  // Auto-play the next video of the folder when this one ends (normal mode only)
  void _onTick() {
    final val = v.value;
    if (strict || leaving || !val.isInitialized || !val.isCompleted) return;
    final n = nextFile;
    if (n != null) {
      leaving = true;
      _open(n);
    } else if (mounted && !showCtl) {
      setState(() => showCtl = true);
    }
  }

  void _open(File f) => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => PlayerPage(path: f.path)));

  // Show controls, hide again after 3 seconds while playing
  void _poke() {
    if (!showCtl && mounted) setState(() => showCtl = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && v.value.isPlaying) setState(() => showCtl = false);
    });
  }

  void _skip(int s) {
    var t = v.value.position + Duration(seconds: s);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.value.duration) t = v.value.duration;
    v.seekTo(t);
    setState(() {
      flash = s > 0 ? '+$s ث' : '$s ث';
      flashLeft = s < 0;
    });
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => flash = null);
    });
  }

  void _toggle() {
    final val = v.value;
    if (val.isCompleted) {
      v.seekTo(Duration.zero);
      v.play();
    } else {
      val.isPlaying ? v.pause() : v.play();
    }
    _poke();
  }

  Future<void> _fullscreen() async {
    fullscreen = !fullscreen;
    if (fullscreen) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
  }

  void _cycleSpeed() {
    speed = _speeds[(_speeds.indexOf(speed) + 1) % _speeds.length];
    v.setPlaybackSpeed(speed);
    setState(() {});
  }

  // Start strict mode: timer = full video duration, from now
  Future<void> startStrict() async {
    if (!await ensureLockReady(context)) return; // strong lock must be enabled first
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بدء الوضع الصارم'),
        content: Text('سيُقفل الهاتف لمدة ${v.value.duration.inMinutes} دقيقة ولا يمكن الخروج قبل انتهائها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (ok != true) return;
    final end = DateTime.now().add(v.value.duration).millisecondsSinceEpoch;
    await ch.invokeMethod('startLock', {'end': end, 'type': 'local', 'target': widget.path});
    if (!mounted) return;
    toStrict = true;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => PlayerPage(path: widget.path, endMillis: end)));
  }

  // ---------- UI pieces ----------

  Widget _flashBubble() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
        child: Text(flash!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _controls() => AnimatedOpacity(
        opacity: showCtl ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !showCtl,
          child: Container(
            color: Colors.black45,
            child: Column(children: [
              Row(children: [
                if (!strict)
                  IconButton(
                    icon: Icon(fullscreen ? Icons.arrow_back : Icons.keyboard_arrow_down, color: Colors.white),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _cycleSpeed,
                  child: Text(speed == 1.0 ? '1x' : '${speed}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: v,
                  builder: (_, VideoPlayerValue val, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(iconSize: 38, color: Colors.white, icon: const Icon(Icons.replay_10), onPressed: () { _skip(-10); _poke(); }),
                    const SizedBox(width: 28),
                    IconButton(
                      iconSize: 58,
                      color: Colors.white,
                      icon: Icon(val.isCompleted ? Icons.replay : (val.isPlaying ? Icons.pause : Icons.play_arrow)),
                      onPressed: _toggle,
                    ),
                    const SizedBox(width: 28),
                    IconButton(iconSize: 38, color: Colors.white, icon: const Icon(Icons.forward_10), onPressed: () { _skip(10); _poke(); }),
                  ]),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: v,
                builder: (ctx, VideoPlayerValue val, __) {
                  final dur = val.duration.inMilliseconds.toDouble();
                  final pos = val.position.inMilliseconds.clamp(0, dur.toInt()).toDouble();
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        Text('${fmtDur(val.position)} / ${fmtDur(val.duration)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const Spacer(),
                        if (!strict)
                          GestureDetector(
                            onTap: _fullscreen,
                            child: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                          ),
                      ]),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(ctx).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: kAccent,
                        thumbColor: kAccent,
                        inactiveTrackColor: Colors.white24,
                      ),
                      child: Slider(
                        value: pos,
                        min: 0,
                        max: dur > 0 ? dur : 1,
                        onChanged: (x) => v.seekTo(Duration(milliseconds: x.toInt())),
                        onChangeEnd: (_) => _poke(),
                      ),
                    ),
                  ]);
                },
              ),
            ]),
          ),
        ),
      );

  // Video + gestures (tap = controls, double tap left/right = -/+10s, center = play/pause)
  Widget _video() => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (ctx, cs) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showCtl ? setState(() => showCtl = false) : _poke(),
              onDoubleTapDown: (d) {
                final x = d.localPosition.dx / cs.maxWidth;
                if (x < .35) {
                  _skip(-10);
                } else if (x > .65) {
                  _skip(10);
                } else {
                  _toggle();
                }
              },
              onDoubleTap: () {},
              child: Stack(children: [
                Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))),
                if (flash != null)
                  Align(
                    alignment: flashLeft ? Alignment.centerLeft : Alignment.centerRight,
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 36), child: _flashBubble()),
                  ),
                Positioned.fill(child: _controls()),
                // thin red progress line while the controls are hidden (like YouTube)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: showCtl ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: ValueListenableBuilder(
                        valueListenable: v,
                        builder: (_, VideoPlayerValue val, __) => LinearProgressIndicator(
                          value: val.duration.inMilliseconds > 0
                              ? val.position.inMilliseconds / val.duration.inMilliseconds
                              : 0,
                          minHeight: 3,
                          color: kAccent,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _sibTile(File f) {
    final cur = f.path == widget.path;
    return InkWell(
      onTap: cur ? null : () => _open(f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Container(
            width: 130,
            height: 73,
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8)),
            child: Icon(cur ? Icons.equalizer : Icons.play_arrow_rounded,
                size: 34, color: cur ? kAccent : Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(titleOf(f.path),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cur ? kAccent : null, fontWeight: cur ? FontWeight.bold : FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  // Title, chips and the "up next" list under the video
  Widget _info() {
    final folder = baseName(me.parent.path) == 'videos' ? 'الرئيسية' : baseName(me.parent.path);
    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(titleOf(widget.path), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$folder  •  ${fmtDur(v.value.duration)}', style: const TextStyle(color: Colors.white60)),
      ),
      if (!strict)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: startStrict, icon: const Icon(Icons.lock, size: 18), label: const Text('الوضع الصارم')),
            ActionChip(
              avatar: const Icon(Icons.speed, size: 18),
              label: Text(speed == 1.0 ? 'السرعة' : '${speed}x'),
              onPressed: _cycleSpeed,
            ),
          ]),
        ),
      if (!strict && siblings.length > 1) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text('فيديوهات المجلد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        for (final f in siblings) _sibTile(f),
      ],
    ]);
  }

  @override
  Widget build(BuildContext c) {
    if (error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text('تعذّر تشغيل الفيديو\n$error', textAlign: TextAlign.center)));
    }
    if (!ready) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: kAccent)));
    }
    final body = fullscreen
        ? _video()
        : Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: _video()),
            Expanded(child: _info()),
          ]);
    if (strict) return StrictShell(endMillis: widget.endMillis!, child: body);
    return PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && fullscreen) _fullscreen();
      },
      child: Scaffold(backgroundColor: kBg, body: fullscreen ? body : SafeArea(child: body)),
    );
  }
}
