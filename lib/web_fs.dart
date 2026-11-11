import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

// A normal mobile Chrome identity: lets Google sign-in work and gives the full YouTube site
const kChromeUA =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Mobile Safari/537.36';

/// true while a web video is fullscreen (so back buttons know what to do)
final webFullscreen = ValueNotifier<bool>(false);

/// WebView that supports fullscreen video with automatic landscape rotation.
class FsWebView extends StatefulWidget {
  final WebViewController controller;
  final bool strict; // strict pages keep the immersive bars after leaving fullscreen
  const FsWebView(this.controller, {super.key, this.strict = false});
  @override
  State<FsWebView> createState() => _FsWebViewState();
}

class _FsWebViewState extends State<FsWebView> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.platform;
    if (p is AndroidWebViewController) {
      p.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget w, void Function() onHidden) => _show(w),
        onHideCustomWidget: _hide,
      );
    }
  }

  void _show(Widget w) {
    if (!mounted) return;
    _entry?.remove();
    _entry = OverlayEntry(builder: (_) => Positioned.fill(child: ColoredBox(color: Colors.black, child: w)));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    webFullscreen.value = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
    webFullscreen.value = false;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(widget.strict ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    if (_entry != null) _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => PopScope(
        canPop: !webFullscreen.value,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && webFullscreen.value) {
            widget.controller.runJavaScript('document.exitFullscreen && document.exitFullscreen();');
          }
        },
        child: WebViewWidget(controller: widget.controller),
      );
}
