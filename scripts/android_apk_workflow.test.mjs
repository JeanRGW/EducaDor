import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = readFileSync(
  new URL('../.github/workflows/android-apk.yml', import.meta.url),
  'utf8',
);

test('APK workflow is manual-only and defaults to arm64-v8a', () => {
  assert.match(workflow, /^on:\n  workflow_dispatch:$/m);
  assert.doesNotMatch(workflow, /^  (push|pull_request|schedule):/m);
  assert.match(workflow, /^        type: choice$/m);
  assert.match(workflow, /^        default: arm64-v8a$/m);
  assert.match(workflow, /^          - arm64-v8a$/m);
});

test('APK workflow uses pinned tooling and the Android Firebase config', () => {
  assert.match(workflow, /actions\/checkout@[0-9a-f]{40} # v4/);
  assert.match(workflow, /actions\/setup-java@[0-9a-f]{40} # v4\.8\.0/);
  assert.match(workflow, /distribution: temurin/);
  assert.match(workflow, /java-version: '17'/);
  assert.match(workflow, /subosito\/flutter-action@[0-9a-f]{40} # v2/);
  assert.match(workflow, /flutter-version: '3\.47\.5'/);
  assert.match(workflow, /flutter pub get --enforce-lockfile/);
  assert.match(
    workflow,
    /--dart-define-from-file=config\/staging\.android\.public\.json/,
  );
  assert.doesNotMatch(workflow, /staging\.public\.json(?!['\n])/);
});

test('APK workflow maps the ABI and uploads the split artifact', () => {
  assert.match(workflow, /--split-per-abi/);
  assert.match(workflow, /arm64-v8a\) target=android-arm64/);
  assert.match(workflow, /armeabi-v7a\) target=android-arm/);
  assert.match(workflow, /x86_64\) target=android-x64/);
  assert.match(workflow, /actions\/upload-artifact@[0-9a-f]{40} # v4\.6\.2/);
  assert.match(
    workflow,
    /path: build\/app\/outputs\/flutter-apk\/app-\$\{\{ inputs\.abi \}\}-release\.apk/,
  );
  assert.match(workflow, /if-no-files-found: error/);
  assert.match(workflow, /sha256sum "\$apk"/);
  assert.doesNotMatch(workflow, /secrets\./);
});
