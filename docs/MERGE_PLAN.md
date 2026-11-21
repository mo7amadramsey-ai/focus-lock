# خطة دمج «المرشد» (almurshid) داخل Focus Lock

آخر تحديث: 2026-11-21 (report-12). الفرع: `feature/murshid-merge`.

## القرار المعماري
- **Focus Lock هو المستودع الرسمي الوحيد.** معرّف التطبيق `com.mohammed.focus_lock` ومفتاح التوقيع نفسه، فيتحدّث فوق النسخة المثبتة بلا حذف.
- مستودع `almurshid` يُؤرشف بعد اكتمال المرحلة 2. سجل قراراته وتقاريره منسوخ في `docs/murshid/` (لم يُعدَّل منه شيء).
- **الهوية البصرية مستقلة:** «Obsidian & Ember» (رماد دافئ + جمرة برتقالية + ذهبي + نعناعي، وقرص خزنة كعنصر مميّز). لا تنسخ هوية ALMULZIM (Midnight Intelligence) ولا ألوانها.
- العمل على فرع ويُدمج بعد تجربة APK الفرع على الهاتف. فرع غير `main` لا ينشر Release (عُدّل `build.yml`).

## جدول المطابقة (تم التحقق بالبحث في الكود)
| الميزة | المرشد | Focus Lock | الحالة |
|---|---|---|---|
| زاحف المودل ومواعيد التسليم | `lib/crawler/*` | `moodle_page.dart`, `study.dart` | موجود (تنفيذ موازٍ) |
| الخطة الذكية وتحذير العجز | `planner.dart` | `study.dart` (PlanDay/PlanResult) | موجود |
| التقويم، المتابعة، التذكيرات | `pages/calendar_page`, `follow_page`, `alerts.dart` | `calendar_tab`, `follow_tab`, `Notifier.kt` | موجود |
| قفل التطبيق بالبصمة | `app_lock.dart` | `app_lock.dart` | موجود |
| القفل الصارم | `LockService.kt`, `strict_page` | `LockService.kt`, `strict_shell`, `lock_modes` | موجود (أغنى: أنواع القفل) |
| التنزيلات والمكتبة والمشغّل | `media/*`, `viewer/*` | `downloads`, `library_page`, `player_page`, `link_open` | موجود |
| نسخ احتياطي واستعادة وحذف | `data_panel.dart` | `settings_page.dart` | موجود |
| **مرشد ذكاء اصطناعي بأي مزوّد** | `ai.dart`, `pages/mentor_page.dart` | لا يوجد | **ناقص** |
| **اختبارات وحدة (12 ملفاً)** | `test/*` | لا يوجد | **ناقص** |
| شرح حدود الختم الدراسي | `strict_info.dart` | لا يوجد | ناقص (صغير) |

## المرحلة 1 — أُنجزت في هذا الفرع
1. هوية بصرية جديدة: `lib/theme.dart` (رموز + خط IBM Plex Sans Arabic) تُعيد تلوين كل الشاشات القائمة تلقائياً.
2. `lib/design/focus_dial.dart`: قرص الخزنة (60 علامة تُضيء عند جاهزية القفل، ضغطه = الفعل الرئيسي).
3. `lib/home/home_page.dart`: رئيسية جديدة (قرص + «غرف التركيز» + مخطط الختم الصارم).
4. نقل سجل قرارات المرشد إلى `docs/murshid/`.

## المرحلة 2 — المقترحة (بالترتيب)
1. بنية مجلدات احترافية: `lib/core`, `lib/features/{lock,study,media,mentor,moodle}`, `lib/design`.
2. نقل `ai.dart` (مزوّدون: Gemini, Groq, OpenAI, Anthropic, عنوان مخصص) + شاشة المرشد بتصميم Focus Lock، ومفتاح الذكاء في Keystore.
3. نقل اختبارات المرشد وتكييفها مع `study.dart`، وإضافة `flutter analyze` و`flutter test` إلى CI.
4. إعادة تصميم بقية الشاشات (الدراسة، المودل، المشغّل) على نفس اللغة البصرية.
5. أرشفة مستودع `almurshid`.
