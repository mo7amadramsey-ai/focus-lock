import 'dart:io';
import 'package:flutter/material.dart';
import 'player_page.dart';
import 'storage.dart';

// Folder browser for downloaded videos. Open a folder = same page with that directory.
class LibraryPage extends StatefulWidget {
  final Directory? dir; // null = root
  const LibraryPage({super.key, this.dir});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Directory? dir;
  List<FileSystemEntity> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    dir = widget.dir ?? await videosRoot();
    final list = dir!.listSync();
    // folders first, then files, alphabetical
    list.sort((a, b) {
      final fa = a is Directory ? 0 : 1, fb = b is Directory ? 0 : 1;
      return fa != fb ? fa - fb : a.path.compareTo(b.path);
    });
    items = list.where((e) => e is Directory || isVideo(e.path)).toList();
    if (mounted) setState(() {});
  }

  String nameOf(FileSystemEntity e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last;

  Future<void> newFolder() async {
    final n = await askName(context, 'اسم المجلد (المادة)');
    if (n == null) return;
    await Directory('${dir!.path}/$n').create();
    _load();
  }

  Future<void> delete(FileSystemEntity e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('حذف "${nameOf(e)}"؟'),
        content: Text(e is Directory ? 'سيُحذف المجلد وكل ما بداخله.' : 'سيُحذف الفيديو نهائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await e.delete(recursive: true);
    _load();
  }

  Future<void> move(File f) async {
    final to = await chooseFolder(context, exclude: dir);
    if (to == null) return;
    await f.rename('${to.path}/${nameOf(f)}');
    _load();
  }

  Future<void> rename(FileSystemEntity e) async {
    final n = await askName(context, 'الاسم الجديد');
    if (n == null) return;
    final ext = e is File && nameOf(e).contains('.') ? '.${nameOf(e).split('.').last}' : '';
    await e.rename('${e.parent.path}/$n$ext');
    _load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(widget.dir == null ? 'الفيديوهات المحملة' : nameOf(widget.dir!))),
        floatingActionButton:
            FloatingActionButton(onPressed: newFolder, child: const Icon(Icons.create_new_folder)),
        body: items.isEmpty
            ? const Center(child: Text('فارغ'))
            : ListView(children: [
                for (final e in items)
                  ListTile(
                    leading: Icon(e is Directory ? Icons.folder : Icons.play_circle),
                    title: Text(nameOf(e).replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), e is File ? '' : '$0')),
                    onTap: () async {
                      if (e is Directory) {
                        await Navigator.push(c, MaterialPageRoute(builder: (_) => LibraryPage(dir: e)));
                      } else {
                        await Navigator.push(c, MaterialPageRoute(builder: (_) => PlayerPage(path: e.path)));
                      }
                      _load();
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'move') move(e as File);
                        if (v == 'rename') rename(e);
                        if (v == 'delete') delete(e);
                      },
                      itemBuilder: (_) => [
                        if (e is File) const PopupMenuItem(value: 'move', child: Text('نقل إلى مجلد')),
                        const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
              ]),
      );
}
