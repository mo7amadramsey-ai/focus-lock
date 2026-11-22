#!/usr/bin/env python3
"""Turns the app manifest into the Google Play one: removes the restricted permissions and the lock components
(accessibility service, device admin). Usage: play_manifest.py android/app/src/main/AndroidManifest.xml"""
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
for perm in ['MANAGE_EXTERNAL_STORAGE', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'ANSWER_PHONE_CALLS',
             'READ_PHONE_STATE', 'HIDE_OVERLAY_WINDOWS']:
    s = re.sub(r'\s*<uses-permission[^>]*android\.permission\.%s"[^>]*/>' % perm, '', s)
s = re.sub(r'\s*<receiver\b[^>]*FocusAdmin[^>]*>.*?</receiver>', '', s, flags=re.S)
s = re.sub(r'\s*<service\b[^>]*LockService[^>]*>.*?</service>', '', s, flags=re.S)
s = s.replace('android:requestLegacyExternalStorage="true"', '')
open(p, 'w', encoding='utf-8').write(s)
left = [x for x in ['MANAGE_EXTERNAL_STORAGE', 'ANSWER_PHONE_CALLS', 'READ_PHONE_STATE', 'HIDE_OVERLAY_WINDOWS',
                    'BIND_ACCESSIBILITY_SERVICE', 'BIND_DEVICE_ADMIN'] if x in s]
if left:
    sys.exit('Play manifest still contains: %s' % left)
print('Play manifest OK')
