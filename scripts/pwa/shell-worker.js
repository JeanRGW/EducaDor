// Generated with a build-specific manifest; never add runtime responses to CacheStorage.
const CACHE_PREFIX = 'educador-static-shell-';
const CACHE_NAME = CACHE_PREFIX + __VERSION__;
const ASSETS = __ASSETS__;
const BASE = new URL(self.registration.scope);
// Pages redirects these two build files to canonical URLs. Fetch those directly;
// never follow redirects, and only create aliases for files in the manifest.
const canonicalPath = path => path === 'index.html' ? './' :
  path === 'assets/packages/youtube_player_iframe/assets/player.html' ? path.slice(0, -5) : path;
const INDEX = new URL('./', BASE).href;
const STATIC_URLS = new Map(ASSETS.flatMap(path => {
  const key = new URL(canonicalPath(path), BASE).href;
  return [[new URL(path, BASE).href, key], [key, key]];
}));

function route(request) {
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== BASE.origin ||
      !url.pathname.startsWith(BASE.pathname) ||
      request.headers.has('authorization') || request.headers.has('range')) return null;
  // All navigations receive the same public build artifact, never the response
  // to a bearer URL. Fragments aren't exposed to workers by browsers.
  if (request.mode === 'navigate') return INDEX;
  if (url.search || url.hash || url.username || url.password) return null;
  return STATIC_URLS.get(url.href) ?? null;
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    try {
      for (const path of ASSETS) {
        const url = new URL(canonicalPath(path), BASE).href;
        const response = await fetch(new Request(url, {
          credentials: 'omit', cache: 'reload', redirect: 'error',
        }));
        if (!response.ok || response.type === 'opaque') throw new Error('Shell install failed');
        await cache.put(url, response);
      }
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
    // Deliberately wait for old tabs to close. No forced activation or reload.
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME) await caches.delete(name);
      // Flutter's retired static caches; never touch Auth/application storage.
      if (['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'].includes(name)) {
        await caches.delete(name);
      }
    }
  })());
});

self.addEventListener('fetch', event => {
  const key = route(event.request);
  if (!key) return;
  event.respondWith((async () => {
    const cached = await (await caches.open(CACHE_NAME)).match(key);
    if (cached) return cached;
    // A missing shell entry must never trigger a request carrying navigation credentials.
    return fetch(new Request(key, {
      credentials: 'omit', cache: 'no-cache', redirect: 'error',
    }));
  })());
});
