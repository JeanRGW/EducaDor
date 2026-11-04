# FCM client

## Configuration and release gates

Provide public `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, and, for web, `VAPID_PUBLIC_KEY` via Dart defines. Use the Firebase app ID/API key registered for the platform being built. These values are public client configuration, never a service-account credential. Values are checked for Firebase-format syntax and matching sender/platform; this cannot prove that a project exists or that credentials are valid. iOS and desktop are explicitly unsupported. No Firebase credentials are committed.

Provisioning a Firebase project, VAPID public key, Android application registration, service-account secrets, and deploying the backend require operator approval. The Firebase Admin sender is backend-only. PR18 supplies token/preferences RPCs, one-shot push claims and the backwards-compatible `issue-certificate` `{id, created}` response. Older hosted versions lacking `created` intentionally skip certificate push. The separate MFA change supplies `/account/security`. Integrate both before release.

FlutterFire web 4.3.1 registers the supplied `serviceWorkerScriptPath`; `/push/firebase-messaging-sw.js` has an isolated `/push/` scope, no fetch handler and never caches API, authentication, or bearer responses. It shows only generic text and opens the same-origin root, ignoring payload-provided URLs. Its query parameters contain only public Firebase configuration. FlutterFire web exposes a no-op `onTokenRefresh`, so the client calls `getToken` again on session/context synchronization and app resume; native uses token rotation callbacks. Permission is requested only through an explicit settings action. Logout attempts server removal while still authenticated, then deletes the local FCM token; a network failure may prevent remote cleanup, and exclusive token ownership is enforced by the backend. No system can guarantee immediate cleanup during offline sign-out.

Before release, verify real browser, installed PWA and Android permission, registration, token rotation, account switches, revocation, opt-out, foreground/background receipt and click behavior. Check Firebase worker SDK URL and report-only CSP in actual deployment; Android uses explicit `FirebaseOptions`, without a checked-in `google-services.json`. Push is best effort and never blocks content or certificate mutations on delivery failure. Sender limits and no retries apply; no inbox or durable queue is provided.

## Local evidence

The test suite uses fake messaging/storage transports and no Firebase network. Android debug APK built with no Firebase defines. Web release build and static-shell generation are exercised without Firebase defines. These builds do not demonstrate actual FCM delivery; no hosted configuration or deploy was performed.
