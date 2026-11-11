import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'theme.dart';
import 'web_fs.dart';

/// Unlocked preview of a Moodle video / embedded player: watch it normally
/// (with rotation + fullscreen) before deciding to start the strict mode.
class PreviewPage extends StatefulWidget {
  final String url;
  final String title;
  const PreviewPage({super.key, required this.url, this.title = 'معاينة'});
  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final WebViewController w;

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url.startsWith('https://') || r.url.startsWith('http://') || r.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..loadRequest(Uri.parse(widget.url));
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
            actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => w.reload())],
          ),
          body: FsWebView(w),
        ),
      );
}
