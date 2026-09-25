const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function browser() {
  const listeners = {}, requests = [];
  const registration = {active: {}, pushManager: {getSubscription: async () => ({})}};
  const document = {visibilityState: 'visible', addEventListener: (name, fn) => {listeners[name] = fn;}};
  const window = {addEventListener: (name, fn) => {
    const previous = listeners[name];
    listeners[name] = (...args) => {previous?.(...args); fn(...args);};
  }, Notification: {}, PushManager: {}};
  const context = {window, document, navigator: {userAgent: 'test', serviceWorker: {getRegistration: async () => registration, ready: Promise.resolve(registration)}},
    fetch: async (url, options) => {requests.push({url, ...options}); return {ok: true};},
    Notification: {permission: 'granted'}, matchMedia: () => ({matches: true}),
    setInterval: () => 1, clearInterval: () => {}, Uint8Array, atob,
  };
  vm.runInNewContext(fs.readFileSync('web/browser_bridge.js', 'utf8'), context);
  return {window, document, listeners, requests, context, registration};
}
test('pagehide clears foreground lease even before visibility changes', () => {
  const b = browser(); b.window.deltiePushLease('capability');
  assert.equal(JSON.parse(b.requests.at(-1).body).visible, true);
  b.listeners.pagehide({persisted: false});
  assert.equal(JSON.parse(b.requests.at(-1).body).visible, false);
});
test('visibility event objects cannot masquerade as forced hidden state', () => {
  const b = browser(); b.window.deltiePushLease('capability');
  b.listeners.visibilitychange({type: 'visibilitychange'});
  assert.equal(JSON.parse(b.requests.at(-1).body).visible, true);
  b.document.visibilityState = 'hidden'; b.listeners.visibilitychange({});
  assert.equal(JSON.parse(b.requests.at(-1).body).visible, false);
});
test('diagnostics expose booleans, never a push endpoint or capability', async () => {
  const b = browser(); b.window.deltiePushLease('private-capability');
  const result = await b.window.deltiePushDiagnostics();
  assert.deepEqual(JSON.parse(result), {homeScreen: true, permission: 'granted', worker: true, subscribed: true, registered: true});
  assert.ok(!result.includes('private-capability'));
});
test('test push requires an existing registration', async () => {
  const b = browser(); await assert.rejects(b.window.deltieTestPush());
  assert.equal(b.requests.length, 0);
  b.window.deltiePushLease('capability'); await b.window.deltieTestPush();
  assert.equal(b.requests.at(-1).url, '/api/push/test');
});
test('Matrix pusher uses the mandatory standard gateway path', () => {
  assert.match(fs.readFileSync('lib/services/browser_push.dart', 'utf8'), /resolve\('\/_matrix\/push\/v1\/notify'\)/);
  assert.match(fs.readFileSync('server/chat-nginx.conf', 'utf8'), /location = \/_matrix\/push\/v1\/notify/);
});
test('re-enabling notifications replaces a subscription signed by an old VAPID key', async () => {
  const b = browser(); let unsubscribed = false, subscribed = false;
  b.context.Notification.requestPermission = async () => 'granted';
  b.context.fetch = async () => ({ok: true, json: async () => ({public_key: btoa('new-key')})});
  b.registration.pushManager.getSubscription = async () => ({
    options: {applicationServerKey: Uint8Array.from([1, 2, 3]).buffer},
    unsubscribe: async () => {unsubscribed = true;},
  });
  b.registration.pushManager.subscribe = async options => {
    subscribed = true; assert.equal(options.userVisibleOnly, true);
    return {toJSON: () => ({endpoint: 'example'})};
  };
  await b.window.deltieSubscribePush();
  assert.ok(unsubscribed && subscribed);
});
test('worker visibly displays both normal and explicit test pushes', async () => {
  const listeners = {}, shown = [];
  const self = {addEventListener: (name, fn) => {listeners[name] = fn;}, registration: {showNotification: async (...args) => shown.push(args)}};
  vm.runInNewContext(fs.readFileSync('web/sw.js', 'utf8'), {self});
  for (const payload of [{room_id: '!room:example', event_id: '$event'}, {test: true, room_id: '', event_id: ''}]) {
    let work;
    listeners.push({data: {json: () => payload}, waitUntil: promise => {work = promise;}});
    await work;
  }
  assert.equal(shown.length, 2);
  assert.equal(shown[0][1].tag, '!room:example');
  assert.equal(shown[1][1].tag, 'send-push-test');
  assert.match(shown[1][1].body, /Test notification received/);
});
