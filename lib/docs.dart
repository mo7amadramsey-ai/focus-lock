import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'channel.dart';
import 'theme.dart';

// Folder that holds every document (opened from Moodle, imported, or sent from Drive)
Future<Directory> docsRoot() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/documents');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

const docExt = ['.pdf', '.docx', '.pptx', '.xlsx', '.doc', '.ppt', '.xls', '.txt', '.png', '.jpg', '.jpeg', '.gif', '.webp'];
const _imgExt = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];

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

// ======================= Office parsing (runs in a background isolate) =======================

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String? _entry(Archive a, String name) {
  for (final f in a.files) {
    if (f.name == name) return utf8.decode(f.content as List<int>, allowMalformed: true);
  }
  return null;
}

final _wT = RegExp(r'<w:t(?:\s[^>]*)?>([^<]*)</w:t>|<w:tab\s*/>|<w:br[^>]*/>');
String _wText(String xml) {
  final b = StringBuffer();
  for (final m in _wT.allMatches(xml)) {
    final g = m.group(0)!;
    if (g.startsWith('<w:tab')) {
      b.write('\t');
    } else if (g.startsWith('<w:br')) {
      b.write('\n');
    } else {
      b.write(_unescape(m.group(1) ?? ''));
    }
  }
  return b.toString();
}

/// docx -> list of blocks {t: 'p'|'h'|'li'|'tbl', text, level, bold, rows}
List<Map<String, dynamic>> parseDocx(String path) {
  final a = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final xml = _entry(a, 'word/document.xml') ?? '';
  final out = <Map<String, dynamic>>[];
  final blk = RegExp(r'(<w:tbl>[\s\S]*?</w:tbl>)|(<w:p[ >][\s\S]*?</w:p>)');
  for (final m in blk.allMatches(xml)) {
    if (m.group(1) != null) {
      final rows = <List<String>>[];
      for (final r in RegExp(r'<w:tr[ >][\s\S]*?</w:tr>').allMatches(m.group(1)!)) {
        final cells = <String>[];
        for (final c in RegExp(r'<w:tc>[\s\S]*?</w:tc>').allMatches(r.group(0)!)) {
          cells.add(c.group(0)!.split('</w:p>').map(_wText).where((e) => e.isNotEmpty).join('\n'));
        }
        rows.add(cells);
      }
      if (rows.isNotEmpty) out.add({'t': 'tbl', 'rows': rows});
      continue;
    }
    final p = m.group(2)!;
    final text = _wText(p);
    if (text.trim().isEmpty) {
      out.add({'t': 'gap'});
      continue;
    }
    final style = RegExp(r'<w:pStyle w:val="([^"]+)"').firstMatch(p)?.group(1) ?? '';
    final low = style.toLowerCase();
    if (low.startsWith('heading') || low == 'title' || low.startsWith('عنوان')) {
      final lv = int.tryParse(RegExp(r'\d').firstMatch(style)?.group(0) ?? '1') ?? 1;
      out.add({'t': 'h', 'text': text, 'level': low == 'title' ? 0 : lv});
    } else if (p.contains('<w:numPr>')) {
      out.add({'t': 'li', 'text': text});
    } else {
      final bold = p.contains('<w:b/>') || RegExp(r'<w:b w:val="(1|true)"').hasMatch(p);
      out.add({'t': 'p', 'text': text, 'bold': bold});
    }
  }
  return out;
}

/// pptx -> list of slides (each is a list of paragraphs)
List<List<String>> parsePptx(String path) {
  final a = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final slides = a.files.where((x) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(x.name)).toList()
    ..sort((x, y) => _no(x.name).compareTo(_no(y.name)));
  final out = <List<String>>[];
  for (final s in slides) {
    final xml = utf8.decode(s.content as List<int>, allowMalformed: true);
    final paras = <String>[];
    for (final p in RegExp(r'<a:p>[\s\S]*?</a:p>|<a:p [\s\S]*?</a:p>').allMatches(xml)) {
      final t = RegExp(r'<a:t>([^<]*)</a:t>').allMatches(p.group(0)!).map((m) => _unescape(m.group(1)!)).join();
      if (t.trim().isNotEmpty) paras.add(t);
    }
    out.add(paras);
  }
  return out;
}

int _no(String name) => int.parse(RegExp(r'(\d+)\.xml$').firstMatch(name)!.group(1)!);

int _col(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c >= 65 && c <= 90) {
      n = n * 26 + (c - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

/// xlsx -> list of sheets {name, rows: List<List<String>>}
List<Map<String, dynamic>> parseXlsx(String path) {
  final a = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final shared = <String>[];
  final ss = _entry(a, 'xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in RegExp(r'<si>[\s\S]*?</si>').allMatches(ss)) {
      shared.add(RegExp(r'<t(?:\s[^>]*)?>([^<]*)</t>').allMatches(si.group(0)!).map((m) => _unescape(m.group(1)!)).join());
    }
  }
  final names = RegExp(r'<sheet [^>]*name="([^"]*)"')
      .allMatches(_entry(a, 'xl/workbook.xml') ?? '')
      .map((m) => _unescape(m.group(1)!))
      .toList();
  final files = a.files.where((x) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(x.name)).toList()
    ..sort((x, y) => _no(x.name).compareTo(_no(y.name)));
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < files.length; i++) {
    final xml = utf8.decode(files[i].content as List<int>, allowMalformed: true);
    final rows = <List<String>>[];
    var maxCols = 0;
    for (final r in RegExp(r'<row[ >][\s\S]*?</row>').allMatches(xml)) {
      if (rows.length >= 1000) break;
      final row = <String>[];
      for (final c in RegExp(r'<c ([^>]*?)(?:/>|>([\s\S]*?)</c>)').allMatches(r.group(0)!)) {
        final attrs = c.group(1)!;
        final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs)?.group(1) ?? 'A';
        final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1) ?? '';
        final body = c.group(2) ?? '';
        var val = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1) ?? '';
        if (type == 's') {
          final ix = int.tryParse(val) ?? -1;
          val = ix >= 0 && ix < shared.length ? shared[ix] : '';
        } else if (type == 'inlineStr') {
          val = RegExp(r'<t(?:\s[^>]*)?>([^<]*)</t>').allMatches(body).map((m) => _unescape(m.group(1)!)).join();
        } else if (type == 'b') {
          val = val == '1' ? 'TRUE' : 'FALSE';
        } else {
          val = _unescape(val);
        }
        final ci = _col(ref);
        if (ci > 60) continue;
        while (row.length <= ci) {
          row.add('');
        }
        row[ci] = val;
      }
      if (row.length > maxCols) maxCols = row.length;
      rows.add(row);
    }
    for (final r in rows) {
      while (r.length < maxCols) {
        r.add('');
      }
    }
    out.add({'name': i < names.length ? names[i] : 'ورقة ${i + 1}', 'rows': rows});
  }
  return out;
}

TextDirection _dirOf(String s) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(s.length > 40 ? s.substring(0, 40) : s) ? TextDirection.rtl : TextDirection.ltr;

Widget _txt(String s, {TextStyle? style, bool selectable = true}) => Directionality(
      textDirection: _dirOf(s),
      child: selectable
          ? SelectableText(s, style: style, textAlign: TextAlign.start)
          : Text(s, style: style, textAlign: TextAlign.start),
    );

// ======================= Viewer =======================

/// In-app viewer: PDF, images, text, Word, Excel, PowerPoint
class DocViewerPage extends StatefulWidget {
  final String path;
  const DocViewerPage({super.key, required this.path});
  @override
  State<DocViewerPage> createState() => _DocViewerPageState();
}

class _DocViewerPageState extends State<DocViewerPage> {
  PdfControllerPinch? pdf;
  late final String ext = extOf(widget.path);
  Future<dynamic>? parsed;
  int sheet = 0;
  double zoom = 1.0;

  @override
  void initState() {
    super.initState();
    if (ext == '.pdf') {
      pdf = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
    } else if (ext == '.docx') {
      parsed = compute(parseDocx, widget.path);
    } else if (ext == '.pptx') {
      parsed = compute(parsePptx, widget.path);
    } else if (ext == '.xlsx') {
      parsed = compute(parseXlsx, widget.path);
    } else if (ext == '.txt') {
      parsed = File(widget.path).readAsString();
    }
  }

  @override
  void dispose() {
    pdf?.dispose();
    super.dispose();
  }

  Widget _unsupported() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.description_outlined, size: 56, color: Colors.white38),
            const SizedBox(height: 14),
            Text(
              ext == '.doc' || ext == '.xls' || ext == '.ppt'
                  ? 'الصيغة القديمة ($ext) لا تُعرض داخل التطبيق. احفظ الملف بصيغة docx أو xlsx أو pptx، أو افتحه من Google Drive.'
                  : 'لا تتوفر معاينة لهذا النوع من الملفات.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => ch.invokeMethod('openDrive'),
              icon: const Icon(Icons.add_to_drive),
              label: const Text('فتح Google Drive'),
            ),
          ]),
        ),
      );

  Widget _docx(List blocks) => ListView(padding: const EdgeInsets.all(18), children: [
        for (final b in blocks.cast<Map>())
          switch (b['t']) {
            'gap' => const SizedBox(height: 8),
            'h' => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: _txt(b['text'], style: TextStyle(fontSize: b['level'] == 0 ? 26 : (b['level'] == 1 ? 22 : 19), fontWeight: FontWeight.w800, height: 1.5)),
              ),
            'li' => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _txt('•  ${b['text']}', style: TextStyle(fontSize: 16 * zoom, height: 1.7)),
              ),
            'tbl' => _grid((b['rows'] as List).map((r) => (r as List).cast<String>()).toList(), header: true),
            _ => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _txt(b['text'], style: TextStyle(fontSize: 16 * zoom, height: 1.7, fontWeight: b['bold'] == true ? FontWeight.w700 : null)),
              ),
          },
      ]);

  Widget _grid(List<List<String>> rows, {bool header = false}) {
    if (rows.isEmpty) return const SizedBox();
    final cols = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: kOutline), borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(130),
            border: TableBorder.all(color: kOutline),
            children: [
              for (var i = 0; i < rows.length; i++)
                TableRow(
                  decoration: BoxDecoration(color: header && i == 0 ? kSurface2 : null),
                  children: [
                    for (var j = 0; j < cols; j++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: _txt(j < rows[i].length ? rows[i][j] : '',
                            style: TextStyle(fontSize: 13.5, fontWeight: header && i == 0 ? FontWeight.w700 : null),
                            selectable: false),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pptx(List slides) => ListView(padding: const EdgeInsets.all(14), children: [
        for (var i = 0; i < slides.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: cardBox(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: kAccent.withOpacity(.2), borderRadius: BorderRadius.circular(12)),
                  child: Text('شريحة ${i + 1}', style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 10),
              if ((slides[i] as List).isEmpty)
                const Text('(شريحة بلا نص)', style: TextStyle(color: Colors.white38))
              else ...[
                _txt((slides[i] as List).first, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.5)),
                for (final p in (slides[i] as List).skip(1))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _txt('•  $p', style: const TextStyle(fontSize: 15.5, height: 1.6)),
                  ),
              ],
            ]),
          ),
      ]);

  Widget _xlsx(List sheets) {
    if (sheets.isEmpty) return const Center(child: Text('الملف فارغ'));
    final cur = sheets[sheet.clamp(0, sheets.length - 1)] as Map;
    final rows = (cur['rows'] as List).map((r) => (r as List).cast<String>()).toList();
    final cols = rows.isEmpty ? 0 : rows.first.length;
    return Column(children: [
      if (sheets.length > 1)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (var i = 0; i < sheets.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text('${(sheets[i] as Map)['name']}'),
                  selected: i == sheet,
                  onSelected: (_) => setState(() => sheet = i),
                ),
              ),
          ]),
        ),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('الورقة فارغة'))
            : Directionality(
                textDirection: TextDirection.ltr,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 46 + cols * 120.0,
                    child: ListView.builder(
                      itemExtent: 40,
                      itemCount: rows.length,
                      itemBuilder: (_, i) => Row(children: [
                        Container(
                          width: 46,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: kSurface2, border: Border(bottom: BorderSide(color: kOutline), right: BorderSide(color: kOutline))),
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        ),
                        for (final v in rows[i])
                          Container(
                            width: 120,
                            height: 40,
                            alignment: AlignmentDirectional.centerStart,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: i == 0 ? kSurface2 : null,
                              border: const Border(bottom: BorderSide(color: kOutline), right: BorderSide(color: kOutline)),
                            ),
                            child: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: i == 0 ? FontWeight.w700 : null)),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _body() {
    if (pdf != null) return PdfViewPinch(controller: pdf!);
    if (_imgExt.contains(ext)) {
      return InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(widget.path))));
    }
    if (parsed == null) return _unsupported();
    return FutureBuilder(
      future: parsed,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: kAccent));
        if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذّر قراءة الملف\n${s.error}', textAlign: TextAlign.center)));
        final d = s.data;
        if (ext == '.txt') return SingleChildScrollView(padding: const EdgeInsets.all(18), child: _txt(d as String, style: TextStyle(fontSize: 16 * zoom, height: 1.7)));
        if (ext == '.docx') return _docx(d as List);
        if (ext == '.pptx') return _pptx(d as List);
        return _xlsx(d as List);
      },
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: Text(baseName(widget.path), style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (ext == '.docx' || ext == '.txt') ...[
              IconButton(icon: const Icon(Icons.text_decrease), onPressed: () => setState(() => zoom = (zoom - .1).clamp(.7, 2.0))),
              IconButton(icon: const Icon(Icons.text_increase), onPressed: () => setState(() => zoom = (zoom + .1).clamp(.7, 2.0))),
            ],
          ],
        ),
        body: _body(),
      );
}

// ======================= Documents list =======================

/// List of saved documents: search, filter by type, import, and Google Drive shortcut
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  List<File> files = [];
  bool loaded = false;
  String filter = 'all', query = '';

  static const _filters = {
    'all': 'الكل',
    'pdf': 'PDF',
    'word': 'Word',
    'excel': 'Excel',
    'ppt': 'PowerPoint',
    'img': 'صور',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await docsRoot();
    final l = d.listSync().whereType<File>().toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) {
      setState(() {
        files = l;
        loaded = true;
      });
    }
  }

  String _kind(String ext) {
    if (ext == '.pdf') return 'pdf';
    if (ext == '.docx' || ext == '.doc') return 'word';
    if (ext == '.xlsx' || ext == '.xls') return 'excel';
    if (ext == '.pptx' || ext == '.ppt') return 'ppt';
    if (_imgExt.contains(ext)) return 'img';
    return 'other';
  }

  (IconData, Color) _look(String ext) => switch (_kind(ext)) {
        'pdf' => (Icons.picture_as_pdf, const Color(0xFFFF5252)),
        'word' => (Icons.description, const Color(0xFF448AFF)),
        'excel' => (Icons.table_chart, const Color(0xFF4CAF50)),
        'ppt' => (Icons.slideshow, const Color(0xFFFF9800)),
        'img' => (Icons.image, const Color(0xFFAB47BC)),
        _ => (Icons.insert_drive_file, Colors.white54),
      };

  Future<void> _openDrive() async {
    bool ok = false;
    try {
      ok = (await ch.invokeMethod('openDrive')) == true;
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تطبيق Google Drive غير مثبّت على الهاتف')));
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: docExt.map((e) => e.substring(1)).toList(),
    );
    if (r == null) return;
    final root = await docsRoot();
    var n = 0;
    for (final f in r.files) {
      if (f.path == null) continue;
      var name = baseName(f.path!);
      var out = File('${root.path}/$name');
      var k = 1;
      while (await out.exists()) {
        final dot = name.lastIndexOf('.');
        out = File('${root.path}/${dot > 0 ? name.substring(0, dot) : name} ($k)${dot > 0 ? name.substring(dot) : ''}');
        k++;
      }
      await File(f.path!).copy(out.path);
      n++;
    }
    await _load();
    if (mounted && n > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $n ملف')));
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

  String _size(File f) {
    final b = f.lengthSync();
    return b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext c) {
    final shown = files.where((f) {
      final e = extOf(f.path);
      if (filter != 'all' && _kind(e) != filter) return false;
      return query.isEmpty || baseName(f.path).toLowerCase().contains(query.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستندات'),
        actions: [
          IconButton(tooltip: 'فتح Google Drive', icon: const Icon(Icons.add_to_drive), onPressed: _openDrive),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.upload_file),
        label: const Text('استيراد ملف'),
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.folder_open, size: 64, color: Colors.white24),
                      const SizedBox(height: 14),
                      const Text('لا توجد مستندات بعد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                        'استورد ملفاً من هاتفك، أو افتح Google Drive واختر "فتح باستخدام Focus Lock"، أو افتح رابط مستند داخل المودل.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.6),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(onPressed: _openDrive, icon: const Icon(Icons.add_to_drive), label: const Text('فتح Google Drive')),
                    ]),
                  ),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(hintText: 'ابحث عن مستند', prefixIcon: Icon(Icons.search), isDense: true),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      for (final e in _filters.entries)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(label: Text(e.value), selected: filter == e.key, onSelected: (_) => setState(() => filter = e.key)),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
                        for (final f in shown)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: cardBox(),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(color: _look(extOf(f.path)).$2.withOpacity(.15), borderRadius: BorderRadius.circular(14)),
                                child: Icon(_look(extOf(f.path)).$1, color: _look(extOf(f.path)).$2),
                              ),
                              title: Text(baseName(f.path), maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${extOf(f.path).replaceAll('.', '').toUpperCase()}  •  ${_size(f)}', style: const TextStyle(color: Colors.white54)),
                              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => DocViewerPage(path: f.path))),
                              trailing: IconButton(icon: const Icon(Icons.delete_outline), color: Colors.white54, onPressed: () => _delete(f)),
                            ),
                          ),
                        if (shown.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا نتائج'))),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
