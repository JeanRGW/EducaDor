import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../../web/push/firebase-messaging-sw.js', import.meta.url), 'utf8');

test('SDK notification displays once and the earlier safe click handler wins', async () => {
  const handlers = {};
  let background;
  const notifications = [];
  const opened = [];
  let sdkClicks = 0;
  const self = {
    location: {href: 'https://example.test/push/firebase-messaging-sw.js?projectId=p', origin: 'https://example.test'},
    registration: {showNotification: (title, options) => notifications.push({title, options})},
    addEventListener: (name, fn) => (handlers[name] ??= []).push(fn),
  };
  const context = {
    URL, Object, self,
    importScripts(url) {
      if (url.includes('firebase-messaging-compat')) {
        self.addEventListener('notificationclick', event => {
          sdkClicks++;
          event.stopImmediatePropagation();
        });
      }
    },
    firebase: {initializeApp() {}, messaging: () => ({onBackgroundMessage: fn => background = fn})},
    clients: {matchAll: async () => [], openWindow: url => opened.push(url)},
  };
  vm.runInNewContext(source, context);
  const payload = {
    notification: {title: 'Nova trilha disponível', body: 'Uma trilha está disponível para você.'},
    data: {event: 'course_available', course_id: 'id', url: 'https://evil.test'},
  };
  // Firebase displays the backend's notification payload before the callback.
  self.registration.showNotification(payload.notification.title, {body: payload.notification.body, data: payload.data});
  await background(payload);
  assert.equal(notifications.length, 1);
  let stopped = false;
  let promise;
  let closed = false;
  const event = {
    notification: {...notifications[0], close() { closed = true; }},
    stopImmediatePropagation() { stopped = true; },
    waitUntil(p) { promise = p; },
  };
  for (const handler of handlers.notificationclick) {
    if (stopped) break;
    handler(event);
  }
  await promise;
  assert.equal(closed, true);
  assert.equal(sdkClicks, 0);
  assert.deepEqual(opened, ['/']);
  await background({data: {url: 'https://evil.test'}});
  assert.equal(notifications.length, 2);
  assert.equal(notifications[1].title, 'EducaDor');
  assert.equal(notifications[1].options.body, 'Há uma atualização no aplicativo.');
  assert.equal(handlers.fetch, undefined);
});
