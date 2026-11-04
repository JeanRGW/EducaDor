import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../../web/push/firebase-messaging-sw.js', import.meta.url), 'utf8');

test('worker only shows generic content and opens a fixed same-origin location', async () => {
  const handlers = {};
  let background;
  let notification;
  let displays = 0;
  let opened;
  const context = {
    URL, Object,
    importScripts() {},
    firebase: { initializeApp() {}, messaging: () => ({onBackgroundMessage: fn => background = fn}) },
    self: { location: {href: 'https://example.test/push/firebase-messaging-sw.js?projectId=p', origin: 'https://example.test'}, registration: {showNotification: (title, options) => { displays++; notification = {title, options}; }}, addEventListener: (name, fn) => handlers[name] = fn },
    clients: {matchAll: async () => [], openWindow: url => {opened = url;}},
  };
  vm.runInNewContext(source, context);
  // Backend FCM payload has notification + data; Firebase displays it first.
  context.self.registration.showNotification('Nova trilha disponível', {body: 'Uma trilha está disponível para você.'});
  await background({notification: {title: 'Nova trilha disponível', body: 'Uma trilha está disponível para você.'}, data: {event: 'course_available', course_id: 'id'}});
  assert.equal(displays, 1);
  await background({data: {url: 'https://evil.test', title: 'private'}});
  assert.equal(displays, 2);
  assert.equal(notification.title, 'EducaDor');
  assert.equal(notification.options.body, 'Há uma atualização no aplicativo.');
  let promise;
  handlers.notificationclick({notification: {close() {}}, waitUntil: p => promise = p});
  await promise;
  assert.equal(opened, '/');
  assert.equal(handlers.fetch, undefined);
});
