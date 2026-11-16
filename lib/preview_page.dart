import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'browser_page.dart';
import 'downloads.dart';
import 'theme.dart';
import 'web_fs.dart';
import 'yt_embed.dart';

/// Unlocked preview of a Moodle video / embedded player: watch it normally
/// (with rotation + fullscreen) before deciding to start the strict mode.
/// If the page holds a YouTube video, a side "watch on YouTube" badge and a download button appear.
class PreviewPage extends StatefulWidget {
  final String url;
  final String title;
  final String? youtubeId; // play this YouTube video directly inside the preview
  const PreviewPage({super.key, required this.url, this.title = 'معاينة', this.youtubeId});
  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final WebViewController w;
  late final ValueNotifier<String?> ytId = ValueNotifier(widget.youtubeId);

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          // YouTube's own "Watch on YouTube" link -> our in-app YouTube browser
          if (isYoutube(r.url) && (r.url.contains('/watch') || Uri.tryParse(r.url)?.host == 'youtu.be')) {
            final id = VideoId.parseVideoId(r.url);
            if (id != null && mounted) openOnYoutube(context, id);
            return NavigationDecision.prevent;
          }
          return r.url.startsWith('https://') || r.url.startsWith('http://') || r.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageFinished: (_) => _detect(),
      ));
    final id = widget.youtubeId;
    if (id != null) {
      w.loadHtmlString(embedHtml(id), baseUrl: embedBaseUrl);
    } else {
      w.loadRequest(Uri.parse(widget.url));
    }
  }

  // Look for a YouTube video in the page (the player may appear a moment after load)
  Future<void> _detect() async {
    if (widget.youtubeId != null) return;
    for (var i = 0; i < 3 && mounted && ytId.value == null; i++) {
      ytId.value = await pageYoutubeId(w);
      if (ytId.value == null) await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  void dispose() {
    ytId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || webFullscreen.value) return;
          if (await w.canGoBack()) {
            w.goBack();
          } else if (mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(children: [
              const Icon(Icons.visibility, color: kAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
            ]),
            actions: [
              ValueListenableBuilder<String?>(
                valueListenable: ytId,
                builder: (_, id, __) => id == null
                    ? const SizedBox.shrink()
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const DownloadsButton(),
                        IconButton(
                          tooltip: 'تحميل الفيديو',
                          icon: const Icon(Icons.file_download_outlined),
                          onPressed: () => downloadYoutubeVideo(c, id, title: widget.title == 'معاينة' ? null : widget.title),
                        ),
                      ]),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => w.reload()),
            ],
          ),
          body: Stack(children: [
            Positioned.fill(child: FsWebView(w)),
            ValueListenableBuilder<String?>(
              valueListenable: ytId,
              builder: (_, id, __) => id == null
                  ? const SizedBox.shrink()
                  : Positioned(
                      right: 0,
                      top: 56,
                      child: WatchOnYoutubeBadge(onTap: () => openOnYoutube(c, id)),
                    ),
            ),
          ]),
        ),
      );
}
