import 'package:flutter/material.dart';
import 'channel.dart';

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
