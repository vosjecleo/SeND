'use strict';
// No Matrix credentials, plaintext chat history, or authenticated responses are
// cached in this worker. Flutter/IndexedDB own offline session data.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('push', event => event.waitUntil((async () => {
  let data;
  try { data = event.data.json(); } catch (_) { return; }
  if (!data || typeof data.room_id !== 'string' || data.room_id.length > 1024) return;
  const isTest = data.test === true;
  // Safari requires a visible notification for EVERY delivered push. The
  // gateway suppresses sends while a foreground lease is alive; never silently
  // consume one here, even if the user reopened the app during delivery.
  await self.registration.showNotification('SeND', {
    body: isTest ? 'Test notification received. Web Push is working on this device.' : 'New activity in a conversation',
    icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png',
    tag: isTest ? 'send-push-test' : data.room_id, renotify: true,
    data: {room_id: data.room_id, event_id: typeof data.event_id === 'string' ? data.event_id.slice(0, 1024) : ''},
  });
})()));
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const data = event.notification.data;
    const target = data.room_id ? '/?room=' + encodeURIComponent(data.room_id) + '&event=' + encodeURIComponent(data.event_id || '') : '/';
    for (const client of await self.clients.matchAll({type: 'window', includeUncontrolled: true})) {
      await client.focus();
      if (data.room_id) client.postMessage({type: 'deltiecord-open-room', ...data});
      return;
    }
    await self.clients.openWindow(target);
  })());
});
