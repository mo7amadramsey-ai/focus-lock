import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'player_page.dart';

// Lists downloaded videos stored in the app folder
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<File> files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/videos');
    if (await dir.exists()) {
      files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('الفيديوهات المحملة')),
        body: files.isEmpty
            ? const Center(child: Text('لا توجد فيديوهات بعد'))
            : ListView(
                children: [
                  for (final f in files)
                    ListTile(
                      leading: const Icon(Icons.play_circle),
                      title: Text(f.uri.pathSegments.last.replaceAll('.mp4', '')),
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => PlayerPage(path: f.path))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await f.delete();
                          _load();
                        },
                      ),
                    ),
                ],
              ),
      );
}
