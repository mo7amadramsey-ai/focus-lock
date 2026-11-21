import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'links_page.dart';
import 'preview_page.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// Personal follow-up: assignments / quizzes with their status, and what was uploaded (log of every sync).
class FollowTab extends StatelessWidget {
  const FollowTab({super.key});

  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty && study.manual.isEmpty) return emptyStudy(c);
    final ag = study.agenda();
    final open = ag.where((a) => !a.done).toList();
    final fin = ag.where((a) => a.done).toList().reversed.take(10).toList();
    final byDay = <String, List<FeedItem>>{};
    for (final f in study.feed.take(120)) {
      byDay.putIfAbsent(dayKey(f.at), () => []).add(f);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('الواجبات والاختبارات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (study.tasks.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('لم تُقرأ واجبات من المودل بعد. أعد «استخراج الروابط» من صفحة المودل، أو أضف مواعيدك يدوياً من التقويم.',
              style: TextStyle(color: kMuted, height: 1.5)),
        ),
      for (final a in open)
        InkWell(
          onTap: a.url == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => PreviewPage(url: a.url!, title: a.title))),
          child: agendaTile(a),
        ),
      if (fin.isNotEmpty) ...[
        Padding(padding: EdgeInsets.only(top: 12), child: Text('منجز', style: TextStyle(color: kMuted))),
        for (final a in fin) agendaTile(a),
      ],
      const Divider(height: 28),
      const Text('ما رُفع حديثاً', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (byDay.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('لا جديد بعد. عند كل مزامنة للمودل تظهر هنا العناصر الجديدة.', style: TextStyle(color: kMuted)),
        ),
      for (final e in byDay.entries) ...[
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(dayLabel(e.value.first.at), style: TextStyle(color: kAccent))),
        for (final f in e.value)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(groupIcon(f.kind == 'yt' || f.kind == 'pdf' || f.kind == 'doc' || f.kind == 'video' || f.kind == 'file' ? f.kind : 'ext')),
            title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(study.courses[f.cid] ?? '', style: TextStyle(color: kMuted)),
            onTap: () {
              if (f.kind == 'yt') {
                Navigator.push(c, MaterialPageRoute(builder: (_) => PreviewPage(url: f.url, title: f.title, youtubeId: null)));
              } else {
                Clipboard.setData(ClipboardData(text: f.url));
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('نُسخ الرابط، وتجده في صفحة روابط المودل')));
              }
            },
          ),
      ],
    ]);
  }
}
