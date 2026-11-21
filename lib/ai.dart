import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'study.dart';

/// The AI assistant: Google Gemini through its public REST API, with the student's own free key.
/// The key is kept in the device keystore. Chats (one per course + a general one) are saved only on this phone.
/// Only what the student writes, plus the course name / lecture titles / dates used as context, is sent to Google.
const kDefaultAiModel = 'gemini-3.8-flash';
const kAiKeyUrl = 'https://aistudio.google.com/apikey';

class AiMsg {
  final String role; // 'user' or 'model'
  final String text;
  final int at;
  final bool error;
  const AiMsg(this.role, this.text, this.at, {this.error = false});
  Map<String, dynamic> toJson() => {'r': role, 't': text, 'a': at, if (error) 'e': 1};
  factory AiMsg.fromJson(Map j) => AiMsg('${j['r']}', '${j['t']}', (j['a'] as num?)?.toInt() ?? 0, error: j['e'] == 1);
}

class AiError implements Exception {
  final int code;
  final String message;
  AiError(this.code, this.message);
}

class AiStore extends ChangeNotifier {
  static const _sec = FlutterSecureStorage();
  static const _keyName = 'ai_gemini_key';
  String model = kDefaultAiModel;
  String? _key;
  bool ready = false;
  final chats = <String, List<AiMsg>>{}; // course id ('' = general) -> messages
  final _busy = <String>{};
  Timer? _saveT;

  bool get hasKey => (_key ?? '').isNotEmpty;
  bool isBusy(String cid) => _busy.contains(cid);
  List<AiMsg> chat(String cid) => chats.putIfAbsent(cid, () => []);

  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/ai_chats.json');

  Future<void> load() async {
    if (ready) return;
    try {
      _key = await _sec.read(key: _keyName);
    } catch (_) {}
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        final m = '${j['model'] ?? ''}'.trim();
        model = m.isEmpty ? kDefaultAiModel : m;
        final c = (j['chats'] as Map?) ?? {};
        for (final e in c.entries) {
          chats['${e.key}'] = [for (final m in (e.value as List)) AiMsg.fromJson(m as Map)];
        }
      }
    } catch (_) {}
    ready = true;
    notifyListeners();
  }

  void _saveSoon() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'model': model,
        'chats': {
          for (final e in chats.entries) e.key: [for (final m in e.value) m.toJson()]
        },
      }));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<void> setKey(String k) async {
    final v = k.trim();
    _key = v;
    try {
      if (v.isEmpty) {
        await _sec.delete(key: _keyName);
      } else {
        await _sec.write(key: _keyName, value: v);
      }
    } catch (_) {}
    notifyListeners();
  }

  void setModel(String m) {
    final v = m.trim();
    model = v.isEmpty ? kDefaultAiModel : v;
    _saveSoon();
    notifyListeners();
  }

  void clearChat(String cid) {
    chats.remove(cid);
    _saveSoon();
    notifyListeners();
  }

  void clearAll() {
    chats.clear();
    _saveSoon();
    notifyListeners();
  }

  /// The instructions that make each course's assistant specialised: its name, chapters, lectures, dates and how well the student answers
  String systemFor(String cid) {
    final b = StringBuffer();
    if (cid.isEmpty) {
      b.writeln('أنت مساعد دراسي شخصي لطالب جامعي. أجب بالعربية الواضحة (مع بقاء مصطلحات المادة بالإنجليزية عند الحاجة)، باختصار ودقة، وبخطوات عند الشرح. لا تخترع معلومات، وإن لم تكن متأكداً فقل ذلك.');
      final names = study.courses.values.take(30).join('، ');
      if (names.isNotEmpty) b.writeln('مواد الطالب: $names');
      return b.toString();
    }
    final name = study.courses[cid] ?? cid;
    b.writeln('أنت مدرّس خصوصي متخصص في مادة «$name» لطالب جامعي. ركّز على هذه المادة وحدها، وأجب بالعربية الواضحة مع بقاء المصطلحات العلمية بالإنجليزية، باختصار ودقة وبخطوات عند الشرح.');
    b.writeln('اشرح بالأمثلة، واسأل الطالب أسئلة قصيرة للتأكد من فهمه عندما يناسب ذلك. لا تخترع معلومات عن محتوى المحاضرات؛ إن لم تكن متأكداً فقل ذلك واقترح أن يراجع المحاضرة.');
    final ch = study.chaptersOf(cid).take(40).toList();
    if (ch.isNotEmpty) b.writeln('فصول المادة / أسابيعها: ${ch.join('، ')}');
    final lec = study.links.where((l) => l.cid == cid && (l.group == 'yt' || l.group == 'video' || l.group == 'pdf' || l.group == 'doc')).map((l) => l.title).take(60).toList();
    if (lec.isNotEmpty) b.writeln('محاضرات ومواد المادة: ${lec.join(' | ')}');
    final now = DateTime.now();
    final next = study.agenda().where((a) => a.cid == cid && !a.done && a.when.isAfter(now)).take(8).map((a) => '${a.title} (${a.isExam ? 'اختبار' : 'موعد'} ${a.when.day}/${a.when.month})').toList();
    if (next.isNotEmpty) b.writeln('المواعيد القادمة: ${next.join('، ')}');
    final u = study.understandingCourse(cid);
    if (u != null) b.writeln('نسبة إجابات الطالب الصحيحة في هذه المادة: ${(u * 100).round()}%.');
    return b.toString();
  }

  Future<void> send(String cid, String text) async {
    final t = text.trim();
    if (t.isEmpty || isBusy(cid) || !hasKey) return;
    final list = chat(cid);
    list.add(AiMsg('user', t, DateTime.now().millisecondsSinceEpoch));
    _busy.add(cid);
    notifyListeners();
    _saveSoon();
    try {
      final reply = await _call(cid, list.where((m) => !m.error).toList());
      list.add(AiMsg('model', reply, DateTime.now().millisecondsSinceEpoch));
    } catch (e) {
      list.add(AiMsg('model', _explain(e), DateTime.now().millisecondsSinceEpoch, error: true));
    } finally {
      _busy.remove(cid);
      notifyListeners();
      _saveSoon();
    }
  }

  Future<String> _call(String cid, List<AiMsg> hist) async {
    final h = hist.length > 24 ? hist.sublist(hist.length - 24) : hist;
    var start = 0;
    while (start < h.length && h[start].role != 'user') {
      start++;
    }
    final contents = [
      for (final m in h.skip(start))
        {
          'role': m.role,
          'parts': [
            {'text': m.text}
          ]
        }
    ];
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemFor(cid)}
        ]
      },
      'contents': contents,
      'generationConfig': {'temperature': 0.5},
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final url = 'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(model.trim())}:generateContent';
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set('content-type', 'application/json; charset=utf-8');
      req.headers.set('x-goog-api-key', _key ?? '');
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final txt = await res.transform(utf8.decoder).join();
      Map? j;
      try {
        j = jsonDecode(txt) as Map;
      } catch (_) {}
      if (res.statusCode != 200) {
        final err = j?['error'];
        throw AiError(res.statusCode, err is Map ? '${err['message'] ?? txt}' : txt);
      }
      final cands = j?['candidates'];
      final content = (cands is List && cands.isNotEmpty) ? (cands.first as Map)['content'] : null;
      final parts = content is Map ? content['parts'] : null;
      final out = parts is List ? parts.map((p) => p is Map ? '${p['text'] ?? ''}' : '').join() : '';
      if (out.trim().isEmpty) throw AiError(0, 'لم يرجع الذكاء ردّاً (ربما حُجب المحتوى). أعد صياغة السؤال.');
      return out.trim();
    } finally {
      client.close(force: true);
    }
  }

  String _explain(Object e) {
    if (e is AiError) {
      final m = e.message.toLowerCase();
      if (e.code == 400 && m.contains('api key')) return 'المفتاح غير صالح. افتح الإعدادات (أيقونة الضبط) والصق مفتاحاً صحيحاً.';
      if (e.code == 401 || e.code == 403) return 'رفضت Google المفتاح أو لا صلاحية له. تأكد من المفتاح من Google AI Studio.';
      if (e.code == 404) return 'اسم الموديل «$model» غير موجود عند Google. غيّره من الإعدادات (مثال: gemini-2.5-flash).';
      if (e.code == 429) return 'استُهلكت الحصة المجانية مؤقتاً. انتظر قليلاً ثم أعد المحاولة.';
      return e.code == 0 ? e.message : 'خطأ من الخدمة (${e.code}): ${e.message}';
    }
    if (e is SocketException) return 'لا يوجد اتصال بالإنترنت.';
    if (e is TimeoutException) return 'انتهت مهلة الاتصال. أعد المحاولة.';
    return 'تعذّر الاتصال بالذكاء الاصطناعي.';
  }
}

final ai = AiStore();
