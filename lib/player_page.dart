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

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// Local video player.
/// endMillis == null -> normal playback (up-next list, auto-play next video).
/// endMillis != null -> strict mode (timer = video length + extra time).
/// Gestures: tap = controls, double tap sides = -/+10s, hold = 2x speed,
/// swipe up/down on the left = brightness, on the right = volume.
class PlayerPage extends StatefulWidget {
  final String path;
  final int? endMillis;
  const PlayerPage({super.key, required this.path, this.endMillis});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late VideoPlayerController v;
  late String path = widget.path; // current video (changes when switching inside the same folder)
  late final Directory folder = File(widget.path).parent; // switching is limited to THIS folder
  final _vKey = GlobalKey(); // keeps the video alive when the phone rotates
  bool _userPaused = false, switching = false;
  bool ready = false, showCtl = true, fullscreen = false, leaving = false, toStrict = false, loop = false;
  String? error;
  Timer? _hide, _flashT;
  String? flash;
  Alignment flashAt = Alignment.center;
  double speed = 1.0, dim = 0, vol = 1.0;
  BoxFit fit = BoxFit.contain;
  int _lastSaved = -1;
  bool _land = false, _dragLeft = true;
  List<File> siblings = [];
  SortMode sortMode = SortMode.nameAsc;

  bool get strict => widget.endMillis != null;
  File get me => File(path);

  int get _idx => siblings.indexWhere((f) => f.path == path);
  File? get nextFile => _idx >= 0 && _idx + 1 < siblings.length ? siblings[_idx + 1] : null;
  File? get prevFile => _idx > 0 ? siblings[_idx - 1] : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSiblings();
    v = VideoPlayerController.file(me);
    v.initialize().then((_) async {
      final p = await loadPos(path);
      final d = v.value.duration.inMilliseconds;
      if (p > 5000 && p < d - 5000) await v.seekTo(Duration(milliseconds: p)); // continue where you stopped
      v.play();
      v.addListener(_onTick);
      if (mounted) setState(() => ready = true);
      _poke();
    }).catchError((e) {
      if (mounted) setState(() => error = e.toString());
    });
    if (!strict) WakelockPlus.enable(); // strict mode handles it in StrictShell
  }

  // Videos of the same folder only, in the folder's saved sort order
  Future<void> _loadSiblings() async {
    final list = folder.listSync().whereType<File>().where((f) => isVideo(f.path)).toList();
    final mode = await loadSort(folder.path);
    siblings = sortEntities(list, mode);
    sortMode = mode;
    if (mounted) setState(() {});
  }

  Future<void> _sortSheet() async {
    final m = await pickSort(context, sortMode);
    if (m == null) return;
    await saveSort(folder.path, m);
    _loadSiblings();
  }

  // Rotation / returning to the app can leave the video stopped: start it again (unless YOU paused it)
  @override
  void didChangeMetrics() => _resumeSoon();

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _resumeSoon();
  }

  void _resumeSoon() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !ready || _userPaused || switching) return;
      final val = v.value;
      if (val.hasError) {
        _switchTo(File(path), force: true); // the player broke: rebuild it at the saved position
      } else if (!val.isPlaying && !val.isCompleted) {
        v.play();
      }
    });
  }

  // Switch to another video of the SAME folder without leaving this page.
  // In strict mode this keeps the timer running (the StrictShell is never rebuilt).
  Future<void> _switchTo(File f, {bool force = false}) async {
    if (switching || (!force && f.path == path)) return;
    if (f.parent.path != folder.path) return; // never outside the folder
    switching = true;
    if (!v.value.hasError) setPos(path, v.value.position.inMilliseconds);
    await flushPos();
    final nv = VideoPlayerController.file(f);
    try {
      await nv.initialize();
      final p = await loadPos(f.path);
      final d = nv.value.duration.inMilliseconds;
      if (p > 5000 && p < d - 5000) await nv.seekTo(Duration(milliseconds: p));
      await nv.setPlaybackSpeed(speed);
      await nv.setVolume(vol);
      await nv.setLooping(loop);
      await nv.play();
    } catch (e) {
      nv.dispose();
      switching = false;
      leaving = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تشغيل الفيديو')));
      return;
    }
    if (!mounted) {
      nv.dispose();
      return;
    }
    final old = v;
    old.removeListener(_onTick);
    nv.addListener(_onTick);
    setState(() {
      v = nv;
      path = f.path;
      leaving = false;
      _lastSaved = -1;
      _userPaused = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    if (strict) ch.invokeMethod('setTarget', {'target': f.path}); // so a restart resumes THIS video
    switching = false;
    _poke();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    _flashT?.cancel();
    if (ready) setPos(path, v.value.position.inMilliseconds);
    flushPos();
    v.removeListener(_onTick);
    v.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (!strict) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!strict && !toStrict) WakelockPlus.disable();
    super.dispose();
  }

  void _onTick() {
    final val = v.value;
    if (!val.isInitialized) return;
    // remember the position every 5 seconds
    final s = val.position.inSeconds;
    if (s % 5 == 0 && s != _lastSaved) {
      _lastSaved = s;
      setPos(path, val.isCompleted ? 0 : val.position.inMilliseconds);
      if (s % 15 == 0) flushPos();
    }
    // Auto-play the next video of the folder when this one ends (normal mode only)
    if (strict || leaving || !val.isCompleted || loop) return;
    final n = nextFile;
    if (n != null) {
      leaving = true;
      _open(n);
    } else if (mounted && !showCtl) {
      setState(() => showCtl = true);
    }
  }

  void _open(File f) => _switchTo(f);

  void _poke() {
    if (!showCtl && mounted) setState(() => showCtl = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && v.value.isPlaying) setState(() => showCtl = false);
    });
  }

  void _say(String t, [Alignment at = Alignment.center]) {
    setState(() {
      flash = t;
      flashAt = at;
    });
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => flash = null);
    });
  }

  void _skip(int s) {
    var t = v.value.position + Duration(seconds: s);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.value.duration) t = v.value.duration;
    v.seekTo(t);
    _say(s > 0 ? '+$s ث' : '$s ث', s < 0 ? Alignment.centerLeft : Alignment.centerRight);
  }

  void _toggle() {
    final val = v.value;
    if (val.isCompleted) {
      _userPaused = false;
      v.seekTo(Duration.zero);
      v.play();
    } else if (val.isPlaying) {
      _userPaused = true;
      v.pause();
    } else {
      _userPaused = false;
      v.play();
    }
    _poke();
  }

  // Fullscreen button: landscape <-> portrait. Rotating the phone also works by itself.
  Future<void> _fullscreen() async {
    final land = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (!land) {
      fullscreen = true;
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      fullscreen = false;
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await Future.delayed(const Duration(milliseconds: 600));
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (mounted) setState(() {});
  }

  void _setSpeed(double s) {
    speed = s;
    v.setPlaybackSpeed(s);
    setState(() {});
  }

  Future<void> _speedSheet() async {
    final r = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('سرعة التشغيل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final s in _speeds)
            ListTile(
              title: Text(s == 1.0 ? 'عادي' : '${s}x'),
              trailing: s == speed ? const Icon(Icons.check, color: kAccent) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (r != null) _setSpeed(r);
  }

  void _toggleLoop() {
    loop = !loop;
    v.setLooping(loop);
    _say(loop ? 'تكرار الفيديو: تشغيل' : 'تكرار الفيديو: إيقاف');
  }

  void _toggleFit() {
    fit = fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    _say(fit == BoxFit.cover ? 'ملء الشاشة' : 'حجم أصلي');
  }

  void _drag(DragUpdateDetails d, double h) {
    final delta = -d.delta.dy / (h * .7);
    if (_dragLeft) {
      dim = (dim - delta).clamp(0.0, .75).toDouble();
      _say('السطوع ${((1 - dim / .75) * 100).round()}%', Alignment.topCenter);
    } else {
      vol = (vol + delta).clamp(0.0, 1.0).toDouble();
      v.setVolume(vol);
      _say('الصوت ${(vol * 100).round()}%', Alignment.topCenter);
    }
  }

  // Start strict mode: timer = video length (+ extra time chosen by the user)
  Future<void> startStrict() async {
    if (!await ensureLockReady(context)) return;
    if (!mounted) return;
    final extra = await confirmStrict(context, v.value.duration);
    if (extra == null) return;
    final end = DateTime.now().add(v.value.duration + Duration(minutes: extra)).millisecondsSinceEpoch;
    await ch.invokeMethod('startLock', {'end': end, 'type': 'local', 'target': path});
    if (!mounted) return;
    toStrict = true;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlayerPage(path: path, endMillis: end)));
  }

  // ---------- UI pieces ----------

  Widget _flashBubble() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
        child: Text(flash!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _topBtn(IconData i, VoidCallback f, {bool on = false, String? tip}) => IconButton(
        tooltip: tip,
        icon: Icon(i, color: on ? kAccent : Colors.white),
        onPressed: () {
          f();
          _poke();
        },
      );

  Widget _controls(bool fs) => AnimatedOpacity(
        opacity: showCtl ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !showCtl,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.black26, Colors.black87],
              ),
            ),
            child: Column(children: [
              Row(children: [
                if (!strict)
                  IconButton(
                    icon: Icon(fs ? Icons.arrow_back : Icons.keyboard_arrow_down, color: Colors.white),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                if (fs)
                  Expanded(
                    child: Text(titleOf(path),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  )
                else
                  const Spacer(),
                _topBtn(Icons.repeat, _toggleLoop, on: loop, tip: 'تكرار'),
                _topBtn(fit == BoxFit.cover ? Icons.fit_screen : Icons.aspect_ratio, _toggleFit, tip: 'حجم العرض'),
                TextButton(
                  onPressed: () {
                    _speedSheet();
                    _poke();
                  },
                  child: Text(speed == 1.0 ? '1x' : '${speed}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: v,
                  builder: (_, VideoPlayerValue val, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                          iconSize: 34,
                          color: Colors.white,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: prevFile == null ? null : () => _open(prevFile!)),
                    IconButton(iconSize: 38, color: Colors.white, icon: const Icon(Icons.replay_10), onPressed: () { _skip(-10); _poke(); }),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      iconSize: 46,
                      style: IconButton.styleFrom(backgroundColor: Colors.black45),
                      icon: Icon(val.isCompleted ? Icons.replay : (val.isPlaying ? Icons.pause : Icons.play_arrow), color: Colors.white),
                      onPressed: _toggle,
                    ),
                    const SizedBox(width: 12),
                    IconButton(iconSize: 38, color: Colors.white, icon: const Icon(Icons.forward_10), onPressed: () { _skip(10); _poke(); }),
                    IconButton(
                          iconSize: 34,
                          color: Colors.white,
                          icon: const Icon(Icons.skip_next),
                          onPressed: nextFile == null ? null : () => _open(nextFile!)),
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
                        GestureDetector(
                          onTap: () {
                            _fullscreen();
                            _poke();
                          },
                          child: Icon(fs ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 28),
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

  Widget _video(bool fs) => Directionality(
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
              onLongPressStart: (_) {
                v.setPlaybackSpeed(2.0);
                _say('2x', Alignment.topCenter);
              },
              onLongPressEnd: (_) => v.setPlaybackSpeed(speed),
              onVerticalDragStart: (d) => _dragLeft = d.localPosition.dx < cs.maxWidth / 2,
              onVerticalDragUpdate: (d) => _drag(d, cs.maxHeight),
              child: Stack(children: [
                Positioned.fill(
                  child: FittedBox(
                    fit: fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: v.value.size.width == 0 ? 16 : v.value.size.width,
                      height: v.value.size.height == 0 ? 9 : v.value.size.height,
                      child: VideoPlayer(v),
                    ),
                  ),
                ),
                if (dim > 0) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withOpacity(dim)))),
                if (flash != null)
                  Align(
                    alignment: flashAt,
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24), child: _flashBubble()),
                  ),
                Positioned.fill(child: _controls(fs)),
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
                          value: val.duration.inMilliseconds > 0 ? val.position.inMilliseconds / val.duration.inMilliseconds : 0,
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
    final cur = f.path == path;
    return InkWell(
      onTap: cur ? null : () => _open(f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Container(
            width: 120,
            height: 68,
            decoration: BoxDecoration(color: cur ? kAccent.withOpacity(.15) : kSurface, borderRadius: BorderRadius.circular(12)),
            child: Icon(cur ? Icons.equalizer : Icons.play_arrow_rounded, size: 32, color: cur ? kAccent : Colors.white70),
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

  Widget _info() {
    final folder = baseName(me.parent.path) == 'videos' ? 'الرئيسية' : baseName(me.parent.path);
    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(titleOf(path), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$folder  •  ${fmtDur(v.value.duration)}', style: const TextStyle(color: Colors.white60)),
      ),
      if (!strict)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: startStrict, icon: const Icon(Icons.lock, size: 18), label: const Text('الوضع الصارم')),
            ActionChip(avatar: const Icon(Icons.speed, size: 18), label: Text(speed == 1.0 ? 'السرعة' : '${speed}x'), onPressed: _speedSheet),
            ActionChip(avatar: const Icon(Icons.screen_rotation, size: 18), label: const Text('ملء الشاشة'), onPressed: _fullscreen),
          ]),
        ),
      if (siblings.length > 1) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
          child: Row(children: [
            Expanded(
              child: Text(strict ? 'فيديوهات هذا المجلد (التبديل داخله فقط)' : 'فيديوهات المجلد',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            IconButton(tooltip: 'ترتيب', icon: const Icon(Icons.sort), onPressed: _sortSheet),
          ]),
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
    final land = MediaQuery.orientationOf(c) == Orientation.landscape;
    // hide the system bars in landscape (normal mode; strict mode always hides them)
    if (!strict && land != _land) {
      _land = land;
      WidgetsBinding.instance.addPostFrameCallback((_) => SystemChrome.setEnabledSystemUIMode(
          land ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
    }
    final fs = land || fullscreen;
    // One keyed video widget used in both layouts: rotating moves it instead of rebuilding it
    final video = KeyedSubtree(key: _vKey, child: _video(fs));
    final body = fs
        ? video
        : Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: video),
            Expanded(child: _info()),
          ]);
    if (strict) return StrictShell(endMillis: widget.endMillis!, child: body);
    return PopScope(
      canPop: !fs,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && fs) _fullscreen();
      },
      child: Scaffold(backgroundColor: kBg, body: fs ? body : SafeArea(child: body)),
    );
  }
}
