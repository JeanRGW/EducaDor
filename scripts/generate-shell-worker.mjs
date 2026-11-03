import {createHash} from 'node:crypto';
import {readdir, readFile, writeFile} from 'node:fs/promises';
import {resolve, relative, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

// Only public, compiled shell artifacts. Never crawl runtime URLs or source config.
export function isShellAsset(path) {
  return ['index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
    'main.dart.wasm', 'main.dart.mjs', 'manifest.json', 'favicon.png', 'version.json'].includes(path) ||
    /^(assets|icons|canvaskit)\//.test(path) && !path.endsWith('.map');
}

export async function generate(directory) {
  const root = resolve(directory);
  const files = [];
  async function walk(dir) {
    for (const entry of await readdir(dir, {withFileTypes: true})) {
      const path = resolve(dir, entry.name);
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile()) {
        const name = relative(root, path).split(sep).join('/');
        if (isShellAsset(name)) files.push(name);
      }
    }
  }
  await walk(root);
  files.sort();
  for (const required of ['index.html', 'main.dart.js', 'flutter_bootstrap.js']) {
    if (!files.includes(required)) throw new Error(`Missing Flutter build artifact: ${required}`);
  }
  const bootstrap = await readFile(resolve(root, 'flutter_bootstrap.js'), 'utf8');
  if (/_flutter\.loader\.load\(\{\s*serviceWorkerSettings:/.test(bootstrap)) {
    throw new Error('Use web/flutter_bootstrap.js');
  }
  const hash = createHash('sha256');
  const template = await readFile(new URL('./pwa/shell-worker.js', import.meta.url), 'utf8');
  hash.update(template);
  for (const path of files) {
    hash.update(path + '\0');
    hash.update(await readFile(resolve(root, path)));
  }
  const version = hash.digest('hex');
  const source = template.replace('__VERSION__', JSON.stringify(version))
    .replace('__ASSETS__', JSON.stringify(files));
  await writeFile(resolve(root, 'flutter_service_worker.js'), source);
  console.log(`Static shell: ${files.length} files, version ${version.slice(0, 12)}`);
  return {version, files};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await generate(process.argv[2] ?? 'build/web');
}
