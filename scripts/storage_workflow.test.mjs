import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
const functionsJob = workflow.split('\n  scripts-and-functions:\n')[1];
const commands = [...functionsJob.matchAll(/^\s+run: (deno .+)$/gm)].map((match) => match[1]);

test('CI keeps non-SDK function suites permissionless and excludes only SDK signing', () => {
  const unit = commands.find((command) => command.startsWith('deno test supabase/functions/'));
  assert.equal(unit, 'deno test supabase/functions/ --ignore=supabase/functions/storage-upload-url/signing_test.ts');
  assert.doesNotMatch(unit, /--allow-|(?:^|\s)-A(?:\s|$)/);
  const source = readFileSync(new URL('../supabase/functions/storage-upload-url/storage_test.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /storage_s3|@aws-sdk|signing_test/);
});

test('CI runs SDK signing separately with scoped frozen lock and only documented permissions', () => {
  const sdk = commands.find((command) => command.startsWith('deno test --frozen'));
  assert.equal(sdk, "deno test --frozen --config supabase/functions/storage-upload-url/deno.json '--allow-env=AWS_*,SMITHY_*,HOME,USERPROFILE,HOMEPATH,HOMEDRIVE,_X_AMZN_TRACE_ID' --allow-sys=osRelease supabase/functions/storage-upload-url/signing_test.ts");
  assert.doesNotMatch(functionsJob, /--allow-(?:all|net|read|write|run|ffi)|(?:^|\s)-A(?:\s|$)/);
  const checklist = readFileSync(new URL('../stack/11-storage-verification.md', import.meta.url), 'utf8');
  assert.ok(checklist.includes(sdk));
  for (const target of ['upload', 'download']) {
    assert.ok(functionsJob.includes(`deno check --frozen --config supabase/functions/storage-${target}-url/deno.json supabase/functions/storage-${target}-url/index.ts`));
  }
});
