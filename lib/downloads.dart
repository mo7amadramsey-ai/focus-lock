import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'storage.dart';
import 'theme.dart';

enum DlState { preparing, running, done, failed, cancelled }

class _Cancelled implements Exception {}

/// One download (like one row in SnapTube's downloads list)
class DlTask {
  final int id;
  final String url;
  final Directory dir;
  String title;
  DlState state = DlState.preparing;
  int got = 0, total = 0;
  String? error;
  bool cancelRequested = false;
  DlTask(this.id, this.url, this.dir, this.title);

  bool get active => state == DlState.preparing || state == DlState.running;
  double? get progress => total > 0 ? (got / total).clamp(0.0, 1.0).toDouble() : null;
}

/// Runs any number of downloads at the same time and tells the UI when something changes.
/// (They keep running while the app is open; closing the app stops them.)
class DownloadManager extends ChangeNotifier {
  final tasks = <DlTask>[];
  int _next = 1;

  int get activeCount => tasks.where((t) => t.active).length;

  /// Returns false if this video is already downloading to the same folder.
  bool start(String url, Directory dir) {
    final vid = VideoId.parseVideoId(url);
    final dup = tasks.any((t) => t.active && t.dir.path == dir.path && VideoId.parseVideoId(t.url) == vid);
    if (dup) return false;
    final t = DlTask(_next++, url, dir, 'جاري التحضير...');
    tasks.insert(0, t); // newest on top
    notifyListeners();
    _run(t);
    return true;
  }

  void cancel(DlTask t) {
    if (!t.active) return;
    t.cancelRequested = true; // the download loop notices and stops
  }

  void retry(DlTask t) {
    tasks.remove(t);
    start(t.url, t.dir);
  }

  void remove(DlTask t) {
    if (t.active) return;
    tasks.remove(t);
    notifyListeners();
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.active);
    notifyListeners();
  }

  Future<void> _run(DlTask t) async {
    final yt = YoutubeExplode();
    IOSink? sink;
    File? part;
    try {
      final id = VideoId(t.url);
      final video = await yt.videos.get(id);
      t.title = video.title;
      notifyListeners();
      if (t.cancelRequested) throw _Cancelled();
      final manifest = await yt.videos.streamsClient.getManifest(id);
      final info = manifest.muxed.withHighestBitrate(); // video + audio in one file
      t.total = info.size.totalBytes;
      t.state = DlState.running;
      notifyListeners();

      // Never overwrite an existing video: add (2), (3)...
      final safe = safeName(video.title);
      var target = File('${t.dir.path}/$safe.mp4');
      for (var n = 2; target.existsSync(); n++) {
        target = File('${t.dir.path}/$safe ($n).mp4');
      }
      part = File('${target.path}.part'); // not listed as a video until finished
      sink = part.openWrite();

      final clock = Stopwatch()..start();
      await for (final chunk in yt.videos.streamsClient.get(info)) {
        if (t.cancelRequested) throw _Cancelled();
        sink.add(chunk);
        t.got += chunk.length;
        if (clock.elapsedMilliseconds > 250) {
          clock.reset();
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await part.rename(target.path);
      t.state = DlState.done;
    } on _Cancelled {
      t.state = DlState.cancelled;
      await _cleanup(sink, part);
    } catch (e) {
      t.state = DlState.failed;
      t.error = e.toString();
      await _cleanup(sink, part);
    } finally {
      yt.close();
      notifyListeners();
    }
  }

  Future<void> _cleanup(IOSink? sink, File? part) async {
    try {
      await sink?.close();
      if (part != null && await part.exists()) await part.delete();
    } catch (_) {}
  }
}

final dl = DownloadManager();

String _mb(int b) => (b / 1048576).toStringAsFixed(1);

/// The downloads list: every current and finished download, with progress.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  String _folder(DlTask t) {
    final n = entityName(t.dir);
    return n == 'videos' ? 'الرئيسية' : n;
  }

  Widget _card(BuildContext c, DlTask t) {
    final statusText = switch (t.state) {
      DlState.preparing => 'جاري التحضير...',
      DlState.running => '${((t.progress ?? 0) * 100).toStringAsFixed(0)}%  •  ${_mb(t.got)} / ${_mb(t.total)} MB',
      DlState.done => 'تم التحميل  •  ${_mb(t.total)} MB',
      DlState.failed => 'فشل التحميل',
      DlState.cancelled => 'أُلغي',
    };
    final color = switch (t.state) {
      DlState.done => Colors.greenAccent,
      DlState.failed || DlState.cancelled => Colors.orangeAccent,
      _ => Colors.white60,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('إلى: ${_folder(t)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (t.active) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: t.progress, color: kAccent, backgroundColor: Colors.white12, minHeight: 4),
            ],
            const SizedBox(height: 6),
            Text(statusText, style: TextStyle(color: color, fontSize: 12)),
          ]),
        ),
        if (t.active)
          IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.close), onPressed: () => dl.cancel(t))
        else ...[
          if (t.state != DlState.done)
            IconButton(tooltip: 'إعادة المحاولة', icon: const Icon(Icons.refresh), onPressed: () => dl.retry(t)),
          IconButton(tooltip: 'إزالة من القائمة', icon: const Icon(Icons.delete_outline), onPressed: () => dl.remove(t)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: dl,
        builder: (_, __) => Scaffold(
          appBar: AppBar(
            title: const Text('التحميلات'),
            actions: [
              if (dl.tasks.any((t) => !t.active))
                TextButton(onPressed: dl.clearFinished, child: const Text('مسح المنتهية')),
            ],
          ),
          body: dl.tasks.isEmpty
              ? const Center(child: Text('لا توجد تحميلات', style: TextStyle(color: Colors.white54)))
              : ListView(padding: const EdgeInsets.all(12), children: [for (final t in dl.tasks) _card(c, t)]),
        ),
      );
}

/// App-bar button: opens the downloads list and shows how many are running.
class DownloadsButton extends StatelessWidget {
  const DownloadsButton({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: dl,
        builder: (_, __) => IconButton(
          tooltip: 'التحميلات',
          icon: Badge(
            isLabelVisible: dl.activeCount > 0,
            label: Text('${dl.activeCount}'),
            child: const Icon(Icons.download),
          ),
          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const DownloadsPage())),
        ),
      );
}
