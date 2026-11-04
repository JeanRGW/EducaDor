import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

for (const [platform, file] of [
  ['web', '../config/staging.public.json'],
  ['android', '../config/staging.android.public.json'],
]) {
  test(`${platform} release config contains only public platform-specific inputs`, () => {
    const config = JSON.parse(readFileSync(new URL(file, import.meta.url), 'utf8'));
    const keys = [
      'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'FIREBASE_API_KEY', 'FIREBASE_APP_ID',
      'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID',
      ...(platform === 'web' ? ['VAPID_PUBLIC_KEY'] : []),
    ];
    assert.deepEqual(Object.keys(config).sort(), keys.sort());
    assert.equal(config.SUPABASE_URL, 'https://lrlqmkamgncdgppyqnvu.supabase.co');
    assert.match(config.SUPABASE_ANON_KEY, /^sb_publishable_/);
    assert.match(config.FIREBASE_API_KEY, /^AIza[\w-]{35}$/);
    assert.equal(config.FIREBASE_PROJECT_ID, 'educador-rgw');
    assert.equal(config.FIREBASE_MESSAGING_SENDER_ID, '256869499626');
    assert.match(config.FIREBASE_APP_ID, new RegExp(`^1:256869499626:${platform}:[a-f0-9]{10,64}$`));
    if (platform === 'web') assert.match(config.VAPID_PUBLIC_KEY, /^B[A-Za-z0-9_-]{86}$/);
  });
}
