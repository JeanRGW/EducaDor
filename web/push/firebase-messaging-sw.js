/* Messaging has its own /push/ scope and never intercepts application requests. */
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');
const config = Object.fromEntries(new URL(self.location.href).searchParams);
firebase.initializeApp(config);
const messaging = firebase.messaging();
messaging.onBackgroundMessage(() => self.registration.showNotification('EducaDor', {
  body: 'Há uma atualização no aplicativo.',
  tag: 'educador-update',
}));
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.matchAll({type: 'window', includeUncontrolled: true}).then(windows => {
    const existing = windows.find(window => new URL(window.url).origin === self.location.origin);
    return existing ? existing.focus() : clients.openWindow('/');
  }));
});
