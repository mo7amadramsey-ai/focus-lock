import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'browser_page.dart';
import 'downloads.dart';
import 'storage.dart';
import 'theme.dart';

const _moodleOrigin = 'https://moodle.ucas.edu.ps/';

String watchUrl(String id) => 'https://m.youtube.com/watch?v=$id';

/// Page that plays a YouTube video in an iframe. The base URL gives the player a real
/// origin/referrer (YouTube refuses embeds that have none).
String embedHtml(String id) => '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="https://www.youtube.com/embed/$id?playsinline=1&rel=0"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
 referrerpolicy="strict-origin-when-cross-origin"></iframe>
</body></html>
''';

const embedBaseUrl = _moodleOrigin;

// Returns the id of the first embedded YouTube video on the page ('' if none)
const _findYoutubeIdJs = r'''
(function(){
  var r = '';
  document.querySelectorAll('iframe').forEach(function(f){
    if (r) return;
    var s = f.src || f.getAttribute('data-src') || '';
    var m = s.match(/youtube(?:-nocookie)?\.com\/embed\/([\w-]{11})/);
    if (m) r = m[1];
  });
  return r;
})()
''';

Future<String?> pageYoutubeId(WebViewController w) async {
  try {
    final r = await w.runJavaScriptReturningResult(_findYoutubeIdJs);
    final id = r.toString().replaceAll('"', '').trim();
    return id.length == 11 ? id : null;
  } catch (_) {
    return null;
  }
}

void openOnYoutube(BuildContext c, String id) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => BrowserPage(initialUrl: watchUrl(id))));

/// Same flow as the download button of the YouTube browser: folder -> name/number -> downloads list.
Future<void> downloadYoutubeVideo(BuildContext context, String id, {String? title}) async {
  final dir = await chooseFolder(context);
  if (dir == null || !context.mounted) return;
  final r = await askNameNumber(context,
      title: 'اسم الفيديو ورقمه',
      initialName: safeName(title ?? ''),
      initialNumber: nextNumber(dir, pending: dl.pendingNumbers(dir)));
  if (r == null || !context.mounted) return;
  final started = dl.start('https://www.youtube.com/watch?v=$id', dir,
      name: r.name.isEmpty ? null : r.name, number: r.number);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(started ? 'أُضيف إلى التحميلات' : 'هذا الفيديو يُحمَّل إلى هذا المجلد بالفعل'),
    action: SnackBarAction(
      label: 'عرض',
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
    ),
  ));
}

/// Side "watermark": tapping it opens the video on YouTube.
class WatchOnYoutubeBadge extends StatelessWidget {
  final VoidCallback onTap;
  const WatchOnYoutubeBadge({super.key, required this.onTap});
  @override
  Widget build(BuildContext c) => Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.smart_display, color: kAccent, size: 20),
              SizedBox(width: 6),
              Text('المشاهدة عبر يوتيوب', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
