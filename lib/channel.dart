import 'package:flutter/services.dart';

// Same channel name as in MainActivity.kt
const ch = MethodChannel('focus_lock');

/// Cookies of the logged-in Moodle WebView session for [url] (native CookieManager, HttpOnly included)
Future<String> cookiesFor(String url) async {
  try {
    return (await ch.invokeMethod<String>('getCookies', {'url': url})) ?? '';
  } catch (_) {
    return '';
  }
}
