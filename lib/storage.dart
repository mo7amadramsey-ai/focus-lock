import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'channel.dart';

// Public folder on the phone's storage: survives uninstalling the app and is visible in any file manager.
//   /storage/emulated/0/FocusLock/videos     (subfolders = subjects)
//   /storage/emulated/0/FocusLock/documents
const publicRoot = '/storage/emulated/0/FocusLock';

// "All files access" (Android 11+) / storage permission (older): needed to use the public folder
Future<bool> hasAllFiles() async {
  try {
    return await ch.invokeMethod<bool>('hasAllFiles') ?? false;
  } catch (_) {
    return false;
  }
}

// Moves what the older versions kept inside the app (deleted on uninstall) to the public folder
Future<void> _migrate(Directory from, Directory to) async {
  try {
    if (!await from.exists()) return;
    var failed = false;
    for (final e in from.listSync(recursive: true).whereType<File>()) {
      final rel = e.path.substring(from.path.length + 1);
      final dest = File('${to.path}/$rel');
      try {
        if (dest.existsSync()) continue; // never overwrite
        await dest.parent.create(recursive: true);
        try {
          await e.rename(dest.path);
        } catch (_) {
          await e.copy(dest.path); // rename fails across storage volumes
          await e.delete();
        }
      } catch (_) {
        failed = true;
      }
    }
    if (!failed) await from.delete(recursive: true);
  } catch (_) {}
}

/// `name` = 'videos' or 'documents'. Public folder when the permission is granted, else the private app folder.
Future<Directory> dataDir(String name) async {
  final priv = Directory('${(await getApplicationDocumentsDirectory()).path}/$name');
  if (await hasAllFiles()) {
    final pub = Directory('$publicRoot/$name');
    try {
      if (!await pub.exists()) await pub.create(recursive: true);
      await _migrate(priv, pub);
      return pub;
    } catch (_) {} // could not create it: fall back to the private folder
  }
  if (!await priv.exists()) await priv.create(recursive: true);
  return priv;
}

// Root folder of all saved videos (subfolders = your subjects)
Future<Directory> videosRoot() => dataDir('videos');

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

// ---- Resume positions (where you stopped in each video) ----
final _pos = <String, int>{};
bool _posLoaded = false;

Future<File> _posFile() async => File('${(await getApplicationSupportDirectory()).path}/positions.json');

Future<int> loadPos(String path) async {
  if (!_posLoaded) {
    try {
      final f = await _posFile();
      if (await f.exists()) {
        (jsonDecode(await f.readAsString()) as Map).forEach((k, v) => _pos[k as String] = (v as num).toInt());
      }
    } catch (_) {}
    _posLoaded = true;
  }
  return _pos[path] ?? 0;
}

void setPos(String path, int ms) => _pos[path] = ms;

Future<void> flushPos() async {
  try {
    await (await _posFile()).writeAsString(jsonEncode(_pos));
  } catch (_) {}
}

// ---- Sorting (per folder, remembered) ----
enum SortMode { nameAsc, nameDesc, dateNew, dateOld, sizeBig, sizeSmall }

const sortLabels = {
  SortMode.nameAsc: 'الاسم (أ - ي / 1 2 3)',
  SortMode.nameDesc: 'الاسم (عكسي)',
  SortMode.dateNew: 'التاريخ (الأحدث أولاً)',
  SortMode.dateOld: 'التاريخ (الأقدم أولاً)',
  SortMode.sizeBig: 'الحجم (الأكبر أولاً)',
  SortMode.sizeSmall: 'الحجم (الأصغر أولاً)',
};

String entityName(FileSystemEntity e) => e.path.split('/').where((x) => x.isNotEmpty).last;

// "2" comes before "10" (natural order), so numbered lectures sort correctly
int naturalCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length - rb.length;
}

List<T> sortEntities<T extends FileSystemEntity>(List<T> list, SortMode m) {
  int byName(T a, T b) => naturalCompare(entityName(a), entityName(b));
  DateTime date(T e) {
    try {
      return e.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int size(T e) {
    try {
      return e.statSync().size;
    } catch (_) {
      return 0;
    }
  }

  final l = [...list];
  switch (m) {
    case SortMode.nameAsc:
      l.sort(byName);
    case SortMode.nameDesc:
      l.sort((a, b) => byName(b, a));
    case SortMode.dateNew:
      l.sort((a, b) => date(b).compareTo(date(a)));
    case SortMode.dateOld:
      l.sort((a, b) => date(a).compareTo(date(b)));
    case SortMode.sizeBig:
      l.sort((a, b) => size(b).compareTo(size(a)));
    case SortMode.sizeSmall:
      l.sort((a, b) => size(a).compareTo(size(b)));
  }
  return l;
}

Future<File> _sortFile() async => File('${(await getApplicationSupportDirectory()).path}/sort.json');

Future<SortMode> loadSort(String folder) async {
  try {
    final f = await _sortFile();
    if (await f.exists()) {
      final i = (jsonDecode(await f.readAsString()) as Map)[folder];
      if (i is int && i >= 0 && i < SortMode.values.length) return SortMode.values[i];
    }
  } catch (_) {}
  return SortMode.nameAsc;
}

Future<void> saveSort(String folder, SortMode m) async {
  try {
    final f = await _sortFile();
    final map = await f.exists() ? Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map) : <String, dynamic>{};
    map[folder] = m.index;
    await f.writeAsString(jsonEncode(map));
  } catch (_) {}
}

// Bottom sheet to choose the sorting
Future<SortMode?> pickSort(BuildContext c, SortMode current) => showModalBottomSheet<SortMode>(
      context: c,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ترتيب الملفات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final m in SortMode.values)
            ListTile(
              title: Text(sortLabels[m]!),
              trailing: m == current ? const Icon(Icons.check, color: Color(0xFFFF3B3B)) : null,
              onTap: () => Navigator.pop(ctx, m),
            ),
        ]),
      ),
    );
