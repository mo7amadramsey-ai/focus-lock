import 'package:flutter/material.dart';
import 'downloads.dart';
import 'storage.dart';
import 'study.dart';

/// Downloads the YouTube lecture videos of one course in order into a folder, two at a time.
/// (Downloads run while the app is open, like the other downloads.)
Future<void> downloadCourseVideos(BuildContext c, String cid) async {
  final seen = <String>{};
  final vids = study.links.where((l) => l.cid == cid && ytId(l) != null && seen.add(ytId(l)!)).toList();
  if (vids.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لا توجد فيديوهات يوتيوب في هذه المادة')));
    return;
  }
  final dir = await chooseFolder(c);
  if (dir == null || !c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('بدأ تنزيل ${vids.length} فيديو بالترتيب، تابعها من زر التنزيلات')));
  for (final l in vids) {
    while (dl.activeCount >= 2) {
      await Future.delayed(const Duration(seconds: 2));
    }
    final n = nextNumber(dir, pending: dl.pendingNumbers(dir));
    dl.start(l.url, dir, name: l.title, number: n);
  }
}
