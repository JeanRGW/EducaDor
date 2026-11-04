# 12 – Static-shell PWA reliability

## Build contract (required before publishing)

Keep the existing Flutter build command, then generate the custom worker:

```bash
flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json
node scripts/generate-shell-worker.mjs build/web
node --test scripts/pwa/*.test.mjs
```

CI, manual Pages deployment, and the README manual recipe run the Node generation
command **after every web build, before uploading artifacts or publishing `build/web`**.
Node standard library only; no npm install needed. Workflow changes do not dispatch
or deploy anything. Plain Flutter
output is still an online app, but its generated worker unregisters itself and does
not satisfy the offline contract. Never run another Flutter build between generation
and publication. Flutter's deprecated `--pwa-strategy` flag alone is insufficient.

`web/flutter_bootstrap.js` omits Flutter's `serviceWorkerSettings`, registers the
custom worker at the same path/scope, and selects the local CanvasKit build files.
Thus Flutter does not register/update its retiring worker over the custom worker.
The worker generator fails if the default registration settings return.

## Cache boundary and credentials

The build generator hashes the worker implementation plus sorted public build
filenames and bytes. It includes compiled JS/WASM, index, manifest, icons, local
fonts and CanvasKit. Cache names contain that digest. Installation fetches only this
manifest, anonymously (`credentials: omit`), refusing redirects and failed responses.
For Pages, it fetches the scope root instead of `index.html` and the extensionless
YouTube iframe player instead of its `player.html` build artifact. Both original and
canonical player URLs map to that single public cache entry only when the artifact is
in the manifest. Other redirects still fail installation. Installation failure deletes
the incomplete new cache and leaves the old worker.
No runtime response is ever written to CacheStorage.

Only exact same-origin manifest URLs without query/fragment, Authorization or Range
headers can use the static cache. Supabase, Auth, APIs, signed file links, YouTube,
public content covers and all other non-build responses bypass it. Build assets
must remain public artifacts, never user exports or personal files.

Navigation always uses the installed **static `index.html`**, independent of route,
query or fragment. It never fetches or stores the response to an invitation,
recovery or set-password URL. The browser still passes the original URL to the app
for normal routing/Auth; fragments are not visible to service workers. Cache keys
never contain credentials or routes. This worker does not log requests.

Logout leaves the public shell cache only; it does not introduce persistence of
personal data. Existing Supabase session persistence/logout remains the Auth
repository's responsibility; this worker never reads, writes or clears that storage.
There is no offline course, data, media, download or write queue support.

## Lifecycle and browser hint

No `skipWaiting`, `clients.claim`, controller-change reload or update polling:
new builds wait for old controlled tabs to close before activation. Then only old
`educador-static-shell-*` and Flutter's retired static cache names are removed.
Other app/Auth caches and storage are not touched. Users with an open tab continue
using a consistent old shell until all tabs close; no immediate-update promise.
The first online visit must finish installation; a subsequent navigation is controlled.
Offline before installation, evicted browser storage, denied workers, exhausted quota
or external runtime fonts/resources can still prevent a complete offline experience.

The reusable app banner listens only to `navigator.onLine` and online/offline events
using Dart SDK JS interop and a native no-op conditional implementation. It does not
interpret HTTP failures, RLS, Auth or server errors as offline. `onLine: true` is not
proof of internet reachability (captive portals and server outages remain ordinary
errors). Offline shell availability does not imply session restoration or API access.

## Headers

All routes default to revalidation (`no-cache`) with no-referrer, nosniff, HSTS (no
includeSubDomains/preload), and disabled unused camera/microphone/geolocation/
payment/USB capabilities. Invitation and set-password routes use `no-store`.
Mutable bootstrap, Flutter loader, main JS/WASM and worker entrypoints request
`no-store` for browsers and `Cloudflare-CDN-Cache-Control: no-store` for Cloudflare;
version uses no-cache. Cloudflare cache or browser TTL rules can override origin
headers, so verify the actual production responses after deployment. Cloudflare may
consume its targeted header rather than forward it. Unfingerprinted Flutter
assets/CanvasKit revalidate rather than the old immutable one-year rule, which could
mix generations. The worker's explicitly managed CacheStorage separately pins public
build versions.

CSP is **report-only**, not enforced: it is an initial audit policy including
Supabase HTTPS/WSS, YouTube frames/scripts, fonts and WASM. No report collector is
configured, so browser console violations are the audit source. Do not enforce it
until real authenticated learning flows, YouTube, webfonts, downloads and all render
backends have been verified. Local checks do not certify CDN Pages header behavior;
operators must verify actual response headers after an approved deployment.

## Local checks (no production login)

```bash
node --test scripts/pwa/*.test.mjs
flutter analyze
flutter test --concurrency=2
python3 scripts/pwa/serve.py build/web
```

The local-only server binds `127.0.0.1:8773`, emulates SPA fallback and `_headers`,
and suppresses access logs to avoid capturing bearer URLs. Browser checks should
use an isolated agent-browser session: install online, reload under control, disable
network and reload, inspect CacheStorage keys and test fake bearer paths/API requests.
Never use real credentials for these checks. Close all local tabs to test activation
of a changed build and old-version cache cleanup.

Verified locally (Linux headless Chrome, no login): cached shell reloaded offline with
the banner, a fake bearer invitation URL rendered through the sanitized shell with no
credential cache entries, and closing the last controlled tab activated the newer
build and removed orphan/retired caches while keeping the current one. Browser-only
limits remain: `onLine` can be true without reachability, external runtime fonts are
not cached, and CDN header behavior is unverified until an approved deploy.
