import 'dart:io';
import 'package:flutter/material.dart';
import 'downloads.dart';
import 'storage.dart';
import 'study.dart';

bool _courseDownloading = false;

/// Downloads the YouTube lecture videos of a course into one folder, in the course order, one at a time:
/// 001 - first lecture, 002 - second lecture ...
/// If you already have some lectures, a new lecture that comes BEFORE them takes its place (e.g. 001) and the
/// old ones move up by one (the shift is done by the downloader when each file is saved).
Future<void> downloadCourseVideos(BuildContext c, String cid) async {
  if (_courseDownloading) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('تنزيل مادة آخر يعمل الآن')));
    return;
  }
  final seen = <String>{};
  final vids = study.links.where((l) => l.cid == cid && ytId(l) != null && seen.add(ytId(l)!)).toList();
  if (vids.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لا توجد فيديوهات يوتيوب في هذه المادة')));
    return;
  }
  final dir = await chooseFolder(c);
  if (dir == null || !c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('بدأ تنزيل ${vids.length} فيديو بترتيب المادة. أبقِ التطبيق مفتوحاً وتابعها من التنزيلات')));
  _courseDownloading = true;
  try {
    for (final v in vids) {
      // what is already in the folder (by title), to give this lecture its place in the order
      final have = <String>{
        for (final f in dir.listSync().whereType<File>())
          if (isVideo(f.path)) titlePart(entityName(f)).toLowerCase()
      };
      final mine = safeName(v.title).toLowerCase();
      if (have.contains(mine)) continue;
      var before = 0;
      for (final o in vids) {
        if (o == v) break;
        if (have.contains(safeName(o.title).toLowerCase())) before++;
      }
      final n = before + 1;
      if (!dl.start(v.url, dir, name: v.title, number: n)) continue;
      final task = dl.tasks.first;
      // one at a time, so the numbering stays in order
      while (task.active) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  } finally {
    _courseDownloading = false;
  }
}
