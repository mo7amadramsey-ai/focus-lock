import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'theme.dart';

// Folder that holds every document opened from Moodle
Future<Directory> docsRoot() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/documents');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

const docExt = ['.pdf', '.docx', '.pptx', '.xlsx', '.doc', '.ppt', '.xls', '.txt', '.png', '.jpg', '.jpeg', '.gif', '.webp'];

String extOf(String p) {
  final i = p.lastIndexOf('.');
  final s = p.lastIndexOf('/');
  return i > s ? p.substring(i).toLowerCase() : '';
}

bool isDocPath(String p) => docExt.contains(extOf(p));
String baseName(String p) => p.split('/').last;

// File extension guessed from the HTTP content-type
String extFromContentType(String ct) {
  final t = ct.toLowerCase();
  if (t.contains('application/pdf')) return '.pdf';
  if (t.contains('image/png')) return '.png';
  if (t.contains('image/jpeg')) return '.jpg';
  if (t.contains('image/gif')) return '.gif';
  if (t.contains('image/webp')) return '.webp';
  if (t.contains('text/plain')) return '.txt';
  if (t.contains('wordprocessingml')) return '.docx';
  if (t.contains('presentationml')) return '.pptx';
  if (t.contains('spreadsheetml')) return '.xlsx';
  if (t.contains('msword')) return '.doc';
  if (t.contains('ms-powerpoint')) return '.ppt';
  if (t.contains('ms-excel')) return '.xls';
  return '';
}

// ---- Text preview of docx / pptx (they are zip files full of XML) ----
String _xmlText(String xml, String paraEnd) {
  var s = xml.replaceAll(paraEnd, '\n').replaceAll('<w:tab/>', '\t').replaceAll(RegExp(r'<w:br\s*/>'), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  return s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

int _slideNo(String name) => int.parse(RegExp(r'(\d+)\.xml$').firstMatch(name)!.group(1)!);

Future<String> extractOffice(File f) async {
  final arch = ZipDecoder().decodeBytes(await f.readAsBytes());
  String read(ArchiveFile a) => utf8.decode(a.content as List<int>, allowMalformed: true);
  if (extOf(f.path) == '.docx') {
    final a = arch.files.where((x) => x.name == 'word/document.xml').toList();
    return a.isEmpty ? '' : _xmlText(read(a.first), '</w:p>').trim();
  }
  final slides = arch.files.where((x) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(x.name)).toList()
    ..sort((a, b) => _slideNo(a.name).compareTo(_slideNo(b.name)));
  final out = StringBuffer();
  for (final s in slides) {
    out.writeln('━━ شريحة ${_slideNo(s.name)} ━━');
    out.writeln(_xmlText(read(s), '</a:p>').trim());
    out.writeln();
  }
  return out.toString().trim();
}

/// In-app viewer: PDF, images, text, docx/pptx (text preview)
class DocViewerPage extends StatefulWidget {
  final String path;
  const DocViewerPage({super.key, required this.path});
  @override
  State<DocViewerPage> createState() => _DocViewerPageState();
}

class _DocViewerPageState extends State<DocViewerPage> {
  PdfControllerPinch? pdf;
  String? text;
  bool loading = false;
  late final String ext = extOf(widget.path);

  @override
  void initState() {
    super.initState();
    if (ext == '.pdf') {
      pdf = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
    } else if (ext == '.txt' || ext == '.docx' || ext == '.pptx') {
      loading = true;
      _loadText();
    }
  }

  Future<void> _loadText() async {
    String t;
    try {
      final f = File(widget.path);
      t = ext == '.txt' ? await f.readAsString() : await extractOffice(f);
      if (t.isEmpty) t = 'لا يوجد نص قابل للعرض في هذا الملف.';
    } catch (e) {
      t = 'تعذّر قراءة الملف: $e';
    }
    if (mounted) setState(() {
          text = t;
          loading = false;
        });
  }

  @override
  void dispose() {
    pdf?.dispose();
    super.dispose();
  }

  Widget _body() {
    if (pdf != null) return PdfViewPinch(controller: pdf!);
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
      return InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(widget.path))));
    }
    if (loading) return const Center(child: CircularProgressIndicator(color: kAccent));
    if (text != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text!, style: const TextStyle(fontSize: 16, height: 1.7)),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('لا تتوفر معاينة داخل التطبيق لهذا النوع من الملفات.', textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(baseName(widget.path), style: const TextStyle(fontSize: 16))),
        body: _body(),
      );
}

/// List of saved documents
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  List<File> files = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await docsRoot();
    final l = d.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) {
      setState(() {
        files = l;
        loaded = true;
      });
    }
  }

  IconData _icon(String ext) {
    if (ext == '.pdf') return Icons.picture_as_pdf;
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) return Icons.image;
    if (ext == '.pptx' || ext == '.ppt') return Icons.slideshow;
    if (ext == '.xlsx' || ext == '.xls') return Icons.table_chart;
    return Icons.description;
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('حذف "${baseName(f.path)}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await f.delete();
    _load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('المستندات')),
        body: !loaded
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : files.isEmpty
                ? const Center(child: Text('لا توجد مستندات بعد. افتح رابط مستند داخل المودل وسيُحفظ هنا.'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final f in files)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: Icon(_icon(extOf(f.path)), color: kAccent, size: 30),
                          title: Text(baseName(f.path), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB',
                              style: const TextStyle(color: Colors.white54)),
                          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => DocViewerPage(path: f.path))),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(f)),
                        ),
                      ),
                  ]),
      );
}
