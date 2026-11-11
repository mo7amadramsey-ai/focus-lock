import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Root folder of all saved videos (subfolders = your subjects)
Future<Directory> videosRoot() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/videos');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

const videoExt = ['.mp4', '.webm', '.mkv', '.mov', '.m4v', '.3gp'];
bool isVideo(String p) => videoExt.any((e) => p.toLowerCase().endsWith(e));
String safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

// Root + every subfolder, at any depth
Future<List<Directory>> allFolders() async {
  final root = await videosRoot();
  return [root, ...root.listSync(recursive: true).whereType<Directory>()];
}

String folderLabel(Directory d, Directory root) {
  final rel = d.path.substring(root.path.length);
  return rel.isEmpty ? 'الرئيسية' : rel.substring(1);
}

// Small dialog that asks for a text (folder name)
Future<String?> askName(BuildContext c, String title) {
  final t = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: t, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, safeName(t.text).isEmpty ? null : safeName(t.text)),
            child: const Text('موافق')),
      ],
    ),
  );
}

// Pick a destination folder (or create a new one) - used when downloading / moving
Future<Directory?> chooseFolder(BuildContext c, {Directory? exclude}) async {
  final root = await videosRoot();
  final folders = (await allFolders()).where((f) => f.path != exclude?.path).toList();
  if (!c.mounted) return null;
  return showDialog<Directory>(
    context: c,
    builder: (ctx) => SimpleDialog(
      title: const Text('اختر المجلد'),
      children: [
        for (final f in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Row(children: [
              const Icon(Icons.folder, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(folderLabel(f, root))),
            ]),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final n = await askName(ctx, 'اسم المجلد الجديد');
            if (n == null) return;
            final d = Directory('${root.path}/$n');
            await d.create(recursive: true);
            if (ctx.mounted) Navigator.pop(ctx, d);
          },
          child: const Row(children: [Icon(Icons.create_new_folder, size: 20), SizedBox(width: 8), Text('مجلد جديد')]),
        ),
      ],
    ),
  );
}
