import 'package:flutter/material.dart';
import 'calendar_tab.dart';
import 'courses_page.dart';
import 'docs.dart';
import 'downloads.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'lock_ctl.dart';
import 'lock_modes.dart';
import 'notebook_tab.dart';
import 'settings_page.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// The app: five tabs at the bottom, settings in the top bar.
/// Home - Courses (your Moodle in a simple interface) - Plan - Library - Notebook
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int i = 0;

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: lock,
        builder: (_, __) => PopScope(
          // the back button never closes the app while the strict mode runs
          canPop: i == 0 && !lock.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && i != 0) setState(() => i = 0);
          },
          child: Scaffold(
            body: IndexedStack(index: i, children: const [HomePage(), CoursesPage(), PlanPage(), LibraryHubPage(), NotesPage()]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => i = v),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
                NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'المواد'),
                NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'الخطة'),
                NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: 'المكتبة'),
                NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note_rounded), label: 'الدفتر'),
              ],
            ),
          ),
        ),
      );
}

/// Top bar shared by the tabs: title, the strict-mode button and the settings
AppBar topBar(BuildContext c, String title, {List<Widget> extra = const []}) => AppBar(
      title: Text(title),
      actions: [
        ...extra,
        AnimatedBuilder(
          animation: lock,
          builder: (_, __) => IconButton(
            tooltip: 'الوضع الصارم',
            icon: Icon(lock.active ? Icons.lock_rounded : Icons.lock_outline_rounded, color: lock.active ? kAccent : null),
            onPressed: () => startAppLock(c),
          ),
        ),
        IconButton(
          tooltip: 'الإعدادات',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const StudySettingsPage())),
        ),
        const SizedBox(width: 4),
      ],
    );

// ---------------- plan = plan + calendar ----------------
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool cal = false;

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: topBar(c, 'الخطة'),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: false, label: Text('الخطة')), ButtonSegment(value: true, label: Text('التقويم'))],
                selected: {cal},
                onSelectionChanged: (s) => setState(() => cal = s.first),
              ),
            ),
          ),
          Expanded(child: AnimatedBuilder(animation: study, builder: (_, __) => cal ? const CalendarTab() : const PlanTab())),
        ]),
      );
}

// ---------------- library = downloaded videos + documents ----------------
class LibraryHubPage extends StatelessWidget {
  const LibraryHubPage({super.key});

  Widget _big(BuildContext c, IconData i, String t, String s, Widget page) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: kAccent.withOpacity(.14), borderRadius: BorderRadius.circular(16)),
                child: Icon(i, color: kAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(s, style: TextStyle(color: kMuted)),
                ]),
              ),
              Icon(Icons.chevron_left, color: kMuted),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: topBar(c, 'المكتبة', extra: const [DownloadsButton()]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _big(c, Icons.video_library_rounded, 'الفيديوهات', 'المحمّلة، مرتبة 001 · 002 · 003', const LibraryPage()),
          _big(c, Icons.description_rounded, 'المستندات', 'PDF وWord وExcel وPowerPoint', const DocsPage()),
          const SizedBox(height: 8),
          Text('لتنزيل مادة كاملة: المواد ← اختر المادة ← أيقونة التنزيل.', style: TextStyle(color: kMuted, height: 1.6)),
        ]),
      );
}

// ---------------- notebook ----------------
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: topBar(c, 'الدفتر'),
        body: AnimatedBuilder(animation: study, builder: (_, __) => const NotebookTab()),
      );
}
