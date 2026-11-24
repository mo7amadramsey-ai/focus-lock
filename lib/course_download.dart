import 'dart:io';
import 'package:flutter/material.dart';
import 'downloads.dart';
import 'flavor.dart';
import 'links_page.dart';
import 'storage.dart';
import 'study.dart';
import 'docs.dart';
import 'theme.dart';

bool _courseDownloading = false;

/// Folder name for a course (safe for file systems, not too long)
String courseFolderName(String cid) {
  var n = safeName(study.courses[cid] ?? 'مادة $cid').replaceAll(RegExp(r'\s+'), ' ');
  if (n.length > 60) n = n.substring(0, 60).trim();
  return n.isEmpty ? 'مادة $cid' : n;
}

/// A course's documents (PDF / Word / ...) that live on Moodle, without repeats
List<MoodleLink> courseDocs(String cid) {
  final seen = <String>{};
  return study.links.where((l) => l.cid == cid && (l.group == 'pdf' || l.group == 'doc') && seen.add(l.url)).toList();
}

String _docFileName(MoodleLink l) {
  final path = Uri.decodeFull(Uri.tryParse(l.url)?.path ?? '');
  final ext = extOf(path).isEmpty ? '.pdf' : extOf(path);
  var base = safeName(l.title.isEmpty ? path.split('/').last : l.title);
  if (base.toLowerCase().endsWith(ext.toLowerCase())) base = base.substring(0, base.length - ext.length);
  if (base.length > 80) base = base.substring(0, 80).trim();
  return '${base.isEmpty ? 'document' : base}$ext';
}

/// Downloads documents into [dir] (skips files that are already there), three at a time
Future<int> downloadDocsInto(Directory dir, List<MoodleLink> docs) async {
  var started = 0;
  final taken = <String>{for (final f in dir.listSync().whereType<File>()) entityName(f).toLowerCase()};
  for (final l in docs) {
    final name = _docFileName(l);
    if (!taken.add(name.toLowerCase())) continue;
    while (dl.activeCount >= 3) {
      await Future.delayed(const Duration(seconds: 1));
    }
    if (dl.startFile(l.url, dir, name: name)) started++;
  }
  return started;
}

/// Downloads the YouTube lecture videos in the course order, one at a time, so the numbering stays right:
/// 001 - first lecture, 002 - second lecture ... A new lecture that comes BEFORE the ones you already have takes
/// its place and the old ones move up by one (the downloader does the shift when each file is saved).
Future<void> downloadVideosInto(Directory dir, List<MoodleLink> vids, String? quality) async {
  for (final v in vids) {
    final have = <String>{
      for (final f in dir.listSync().whereType<File>())
        if (isVideo(f.path)) titlePart(entityName(f)).toLowerCase()
    };
    if (have.contains(safeName(v.title).toLowerCase())) continue;
    var before = 0;
    for (final o in vids) {
      if (o == v) break;
      if (have.contains(safeName(o.title).toLowerCase())) before++;
    }
    if (!dl.start(v.url, dir, name: v.title, number: before + 1, quality: quality)) continue;
    final task = dl.tasks.first;
    while (task.active) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}

const _qualities = <String?, String>{null: 'الأعلى', '720p': '720p', '480p': '480p', '360p': '360p', 'audio': 'صوت فقط'};

/// One box: what to download from this course. The folders are created by themselves (named after the course);
/// you only confirm (and may rename). Runs in the background, even if you leave the screen or the app.
Future<void> downloadCourse(BuildContext c, String cid) async {
  if (_courseDownloading) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('تنزيل مادة آخر يعمل الآن')));
    return;
  }
  final seen = <String>{};
  final vids = kPlay ? <MoodleLink>[] : study.links.where((l) => l.cid == cid && ytId(l) != null && seen.add(ytId(l)!)).toList();
  final docs = courseDocs(cid);
  if (vids.isEmpty && docs.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لا توجد فيديوهات يوتيوب أو ملفات PDF في هذه المادة')));
    return;
  }
  final name = TextEditingController(text: courseFolderName(cid));
  var wantVideos = vids.isNotEmpty, wantDocs = docs.isNotEmpty;
  String? quality;
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('تنزيل المادة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تُنشأ المجلدات تلقائياً وتُرتَّب الحلقات 001 · 002 · 003. أكّد أو غيّر الاسم:', style: TextStyle(color: kMuted, height: 1.5)),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المجلد')),
            const SizedBox(height: 6),
            if (vids.isNotEmpty)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: wantVideos,
                onChanged: (v) => set(() => wantVideos = v ?? false),
                title: Text('الفيديوهات (${vids.length}) ← مجلد الفيديوهات'),
              ),
            if (docs.isNotEmpty)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: wantDocs,
                onChanged: (v) => set(() => wantDocs = v ?? false),
                title: Text('ملفات PDF والمستندات (${docs.length}) ← مجلد المستندات'),
              ),
            if (vids.isNotEmpty && wantVideos) ...[
              const SizedBox(height: 6),
              const Text('جودة الفيديو', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, children: [
                for (final q in _qualities.entries)
                  ChoiceChip(label: Text(q.value), selected: quality == q.key, onSelected: (_) => set(() => quality = q.key)),
              ]),
              Text('إن لم تتوفر الجودة المختارة لفيديو معين يُنزَّل الأقرب لها.', style: TextStyle(color: kMuted, fontSize: 12)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: (wantVideos || wantDocs) ? () => Navigator.pop(ctx, true) : null, child: const Text('تأكيد وابدأ')),
        ],
      ),
    ),
  );
  if (ok != true || !c.mounted) return;
  final folder = safeName(name.text.trim().isEmpty ? courseFolderName(cid) : name.text.trim());
  _courseDownloading = true;
  try {
    Directory? vdir, ddir;
    if (wantVideos) vdir = await Directory('${(await videosRoot()).path}/$folder').create(recursive: true);
    if (wantDocs) ddir = await Directory('${(await docsRoot()).path}/$folder').create(recursive: true);
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('بدأ التنزيل في «$folder». يستمر في الخلفية، وتتابعه من التنزيلات')));
    }
    if (ddir != null) await downloadDocsInto(ddir, docs);
    if (vdir != null) await downloadVideosInto(vdir, vids, quality);
  } finally {
    _courseDownloading = false;
  }
}

/// After a Moodle sync: PDFs that are new since the last sync are saved by themselves into
/// Documents/<course name>/ (no questions; they show in the downloads list). The first sync downloads nothing:
/// use «تنزيل المادة» for the old files.
Future<void> autoDownloadNewDocs(List<MoodleLink> fresh) async {
  if (!study.autoPdf) return;
  final byCourse = <String, List<MoodleLink>>{};
  for (final l in fresh) {
    if ((l.group == 'pdf' || l.group == 'doc') && isMoodleHost(Uri.tryParse(l.url)?.host ?? '')) {
      byCourse.putIfAbsent(l.cid, () => []).add(l);
    }
  }
  for (final e in byCourse.entries) {
    try {
      final dir = await Directory('${(await docsRoot()).path}/${courseFolderName(e.key)}').create(recursive: true);
      await downloadDocsInto(dir, e.value);
    } catch (_) {}
  }
}
