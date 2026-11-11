import 'package:flutter/material.dart';
import 'channel.dart';
import 'theme.dart';

/// true while a strict session screen is on (used by the app lock)
final strictActive = ValueNotifier<bool>(false);

/// Returns true when the strong lock is available (accessibility service on,
/// or Device Owner). Otherwise explains how to enable it and returns false.
Future<bool> ensureLockReady(BuildContext c) async {
  final owner = await ch.invokeMethod<bool>('isDeviceOwner') ?? false;
  final acc = await ch.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
  if (owner || acc) return true;
  if (!c.mounted) return false;
  final go = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('تفعيل القفل الصارم'),
      content: const Text(
        'فعّل خدمة "Focus Lock" من إعدادات إمكانية الوصول (مرة واحدة فقط).\n\n'
        'إذا كانت الخيارات رمادية: اذهب إلى معلومات التطبيق ← ⋮ ← السماح بالإعدادات المقيدة، ثم ارجع وفعّلها.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقاً')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('فتح الإعدادات')),
      ],
    ),
  );
  if (go == true) await ch.invokeMethod('openAccessibilitySettings');
  return false;
}

String fmtMinutes(int m) {
  if (m < 60) return '$m دقيقة';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h ساعة' : '$h ساعة و$r دقيقة';
}

/// Asks for a number of minutes
Future<int?> askMinutes(BuildContext c) {
  final t = TextEditingController();
  return showDialog<int>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: const Text('عدد الدقائق'),
      content: TextField(
        controller: t,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'مثال: 45'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(t.text.trim());
            Navigator.pop(ctx, n != null && n > 0 && n <= 600 ? n : null);
          },
          child: const Text('موافق'),
        ),
      ],
    ),
  );
}

Widget _sheetGrip() => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
      ),
    );

/// Before starting: lock length = video length + optional extra time.
/// Returns the extra minutes (0 = none) or null when cancelled.
Future<int?> confirmStrict(BuildContext c, Duration base) {
  var extra = 0;
  return showModalBottomSheet<int>(
    context: c,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final total = base.inMinutes + (base.inSeconds % 60 > 0 ? 1 : 0) + extra;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetGrip(),
            const Text('بدء الوضع الصارم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('مدة الفيديو ${fmtMinutes(base.inMinutes)}. يُقفل الهاتف بهذه المدة على الأقل، ويمكنك إضافة وقت إضافي للمراجعة والتوقف.',
                style: const TextStyle(color: Colors.white60, height: 1.5)),
            const SizedBox(height: 16),
            const Text('وقت إضافي', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [0, 15, 30, 60])
                ChoiceChip(
                  label: Text(m == 0 ? 'بدون' : '+$m د'),
                  selected: extra == m,
                  onSelected: (_) => set(() => extra = m),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: Text([0, 15, 30, 60].contains(extra) ? 'مخصص' : '+$extra د'),
                onPressed: () async {
                  final n = await askMinutes(ctx);
                  if (n != null) set(() => extra = n);
                },
              ),
            ]),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.lock_clock, color: kAccent),
                const SizedBox(width: 10),
                Expanded(child: Text('مدة القفل الكلية: ${fmtMinutes(total)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(ctx, extra), child: const Text('ابدأ التركيز'))),
            ]),
          ]),
        );
      },
    ),
  );
}

/// Extension picker. Returns minutes to add, -1 = continue without lock, null = dismissed.
Future<int?> pickExtension(BuildContext c, {required bool expired}) {
  return showModalBottomSheet<int>(
    context: c,
    isDismissible: !expired,
    enableDrag: !expired,
    builder: (ctx) => PopScope(
      canPop: !expired,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sheetGrip(),
        Row(children: [
          Icon(expired ? Icons.timer_off : Icons.add_alarm, color: kAccent),
          const SizedBox(width: 10),
          Text(expired ? 'انتهى وقت التركيز' : 'تمديد وقت القفل',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        Text(
          expired
              ? 'لم يُغلق الفيديو. هل تريد تمديد فترة التركيز لتكمل المشاهدة؟'
              : 'أضف وقتاً إلى القفل الحالي. التمديد فقط، ولا يمكن تقصير القفل.',
          style: const TextStyle(color: Colors.white60, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in [15, 30, 60, 90])
            ActionChip(label: Text('+${fmtMinutes(m)}'), onPressed: () => Navigator.pop(ctx, m)),
          ActionChip(
            avatar: const Icon(Icons.edit, size: 16),
            label: const Text('مخصص'),
            onPressed: () async {
              final n = await askMinutes(ctx);
              if (n != null && ctx.mounted) Navigator.pop(ctx, n);
            },
          ),
        ]),
        if (expired) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('متابعة بدون قفل')),
          ),
        ],
      ]),
    )),
  );
}
