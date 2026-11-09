import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

test('recovery email keeps the single-use token in a fixed app fragment without tracking resources', () => {
  const html = readFileSync(new URL('../supabase/templates/recovery.html', import.meta.url), 'utf8');
  assert.match(html, /lang="pt-BR"/);
  assert.match(html, /href="https:\/\/app\.educador\.rgw\.app\/recover\/complete#token_hash=\{\{ \.TokenHash \}\}"/);
  assert.doesNotMatch(html, /\?token_hash|ConfirmationURL|<script|<img|<link|<iframe/i);
  assert.match(html, /duas etapas/);
});
