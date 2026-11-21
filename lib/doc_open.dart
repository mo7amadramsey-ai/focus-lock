import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'channel.dart';
import 'docs.dart';
import 'storage.dart';
import 'study.dart';

/// Opens a Moodle document (PDF / Word / PowerPoint / Excel) inside the app:
/// downloads it with the saved Moodle login session, then shows it in the in-app viewer.
Future<void> openMoodleDocument(BuildContext c, String url) async {
  final nav = Navigator.of(c);
  final msg = ScaffoldMessenger.of(c);
  showDialog<void>(context: c, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
  var spinnerOpen = true;
  void closeSpinner() {
    if (spinnerOpen && nav.mounted) nav.pop();
    spinnerOpen = false;
  }

  final client = HttpClient();
  try {
    var u = Uri.parse(url);
    HttpClientResponse? res;
    for (var hop = 0; hop < 6; hop++) {
      final req = await client.getUrl(u);
      req.followRedirects = false;
      req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36');
      if (isMoodleHost(u.host)) {
        final ck = await cookiesFor(u.toString());
        if (ck.isNotEmpty) req.headers.set('Cookie', ck);
      }
      res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value('location');
        await res.drain<void>();
        if (loc == null) throw Exception('توجيه بلا عنوان');
        u = u.resolve(loc);
        continue;
      }
      break;
    }
    if (res == null || res.statusCode != 200) throw Exception('HTTP ${res?.statusCode}');
    if ((res.headers.contentType?.mimeType ?? '') == 'text/html') {
      throw Exception('انتهت جلسة المودل. اضغط «مزامنة» لتسجيل الدخول من جديد');
    }
    final cd = res.headers.value('content-disposition') ?? '';
    final fn = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?', caseSensitive: false).firstMatch(cd)?.group(1);
    var name = safeName(fn != null ? Uri.decodeComponent(fn) : Uri.decodeComponent(u.pathSegments.isEmpty ? 'document' : u.pathSegments.last));
    if (name.isEmpty) name = 'document';
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await res.pipe(f.openWrite());
    closeSpinner();
    if (nav.mounted) nav.push(MaterialPageRoute(builder: (_) => DocViewerPage(path: f.path)));
  } catch (e) {
    closeSpinner();
    msg.showSnackBar(SnackBar(content: Text('تعذّر فتح المستند: ${e.toString().replaceFirst('Exception: ', '')}')));
  } finally {
    client.close();
  }
}
