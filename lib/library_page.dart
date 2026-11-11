import 'dart:io';
import 'package:flutter/material.dart';
import 'downloads.dart';
import 'player_page.dart';
import 'storage.dart';
import 'theme.dart';

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
  SortMode mode = SortMode.nameAsc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    dir = widget.dir ?? await videosRoot();
    mode = await loadSort(dir!.path);
    final all = dir!.listSync();
    // folders first, then videos; each group in the chosen order (name / date / size)
    final folders = sortEntities(all.whereType<Directory>().toList(), mode == SortMode.sizeBig || mode == SortMode.sizeSmall ? SortMode.nameAsc : mode);
    final files = sortEntities(all.whereType<File>().where((f) => isVideo(f.path)).toList(), mode);
    items = [...folders, ...files];
    if (mounted) setState(() {});
  }

  String nameOf(FileSystemEntity e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last;

  Future<void> changeSort() async {
    final m = await pickSort(context, mode);
    if (m == null) return;
    await saveSort(dir!.path, m);
    _load();
  }

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
        appBar: AppBar(
          title: Text(widget.dir == null ? 'الفيديوهات المحملة' : nameOf(widget.dir!)),
          actions: [
            IconButton(tooltip: 'ترتيب', icon: const Icon(Icons.sort), onPressed: changeSort),
            const DownloadsButton(),
          ],
        ),
        floatingActionButton:
            FloatingActionButton(onPressed: newFolder, child: const Icon(Icons.create_new_folder)),
        body: items.isEmpty
            ? const Center(child: Text('فارغ'))
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final e in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                    leading: Icon(e is Directory ? Icons.folder : Icons.play_circle, color: kAccent, size: 30),
                    subtitle: e is File
                        ? Text('#${items.whereType<File>().toList().indexOf(e) + 1}  •  ${(e.lengthSync() / 1048576).toStringAsFixed(1)} MB',
                            style: const TextStyle(color: Colors.white54))
                        : null,
                    title: Text(e is File ? nameOf(e).replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '') : nameOf(e)),
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
                  ),
              ]),
      );
}
