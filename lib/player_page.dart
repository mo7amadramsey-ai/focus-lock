import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'channel.dart';
import 'lock_setup.dart';
import 'strict_shell.dart';

/// Local video player. endMillis == null -> normal preview with a "start strict"
/// button. endMillis != null -> strict mode (timer = video length, set at start).
class PlayerPage extends StatefulWidget {
  final String path;
  final int? endMillis;
  const PlayerPage({super.key, required this.path, this.endMillis});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController v;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    v = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (widget.endMillis != null) v.play(); // strict: start immediately
        if (mounted) setState(() => ready = true);
      });
  }

  @override
  void dispose() {
    v.dispose();
    super.dispose();
  }

  void seek(int s) {
    final t = v.value.position + Duration(seconds: s);
    v.seekTo(t < Duration.zero ? Duration.zero : t);
  }

  // Start strict mode: timer = full video duration, from now
  Future<void> startStrict() async {
    if (!await ensureLockReady(context)) return; // strong lock must be enabled first
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
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => PlayerPage(path: widget.path, endMillis: end)));
  }

  Widget controls() => ValueListenableBuilder(
        valueListenable: v,
        builder: (_, VideoPlayerValue val, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(iconSize: 40, icon: const Icon(Icons.replay_10), onPressed: () => seek(-10)),
          IconButton(
            iconSize: 56,
            icon: Icon(val.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => val.isPlaying ? v.pause() : v.play(),
          ),
          IconButton(iconSize: 40, icon: const Icon(Icons.forward_10), onPressed: () => seek(10)),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final body = Column(children: [
      Expanded(child: Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)))),
      controls(),
      if (widget.endMillis == null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
              onPressed: startStrict, icon: const Icon(Icons.lock), label: const Text('ابدأ الوضع الصارم')),
        ),
    ]);
    if (widget.endMillis != null) return StrictShell(endMillis: widget.endMillis!, child: body);
    return Scaffold(appBar: AppBar(), body: body);
  }
}
