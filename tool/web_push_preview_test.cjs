const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function runtime() {
  const data = {room_id: '!room:test', event_id: '$event'};
  const state = {user: '@me:test', homeserver: 'https://matrix.example', token: 'synthetic-token',
    rooms: [data.room_id], generation: 'generation', sessions: [{room: data.room_id,
      id: 'session', senderKey: 'sender-key', sender: '@friend:test', key: 'key'}]};
  const event = {event_id: data.event_id, room_id: data.room_id, sender: '@friend:test', type: 'm.room.encrypted',
    content: {algorithm: 'm.megolm.v1.aes-sha2', session_id: 'session', sender_key: 'sender-key', ciphertext: 'encrypted'}};
  const decrypted = {index: 1, event: {type: 'm.room.message', content: {msgtype: 'm.text', body: 'hello'}}};
  const requests = [];
  const wasm = async () => {};
  wasm.decrypt_notification = () => JSON.stringify(decrypted);
  const context = {URL, TextDecoder, TextEncoder, Uint8Array, AbortController, setTimeout, clearTimeout,
    sendPushPreviewStore: {read: async () => state, claim: async () => true},
    importScripts() {}, wasm_bindgen: wasm,
    fetch: async (url, options) => {requests.push({url, options}); return new Response(JSON.stringify(event));},
  };
  vm.runInNewContext(fs.readFileSync('web/push_preview.js', 'utf8'), context);
  return {data, state, event, decrypted, context, requests, run: () => context.sendPushPreview(data)};
}
test('decrypts only matching room/session/sender and uses bounded authenticated fetch', async () => {
  const r = runtime();
  assert.equal((await r.run()).body, 'hello');
  assert.equal(r.requests[0].options.headers.Authorization, 'Bearer synthetic-token');
  assert.equal(r.requests[0].options.redirect, 'error');
  assert.equal(r.requests[0].options.cache, 'no-store');
  assert.ok(!r.requests[0].url.includes('synthetic-token'));
  for (const mutate of [r => r.event.room_id = '!other:test', r => r.event.sender = '@forged:test',
    r => r.event.event_id = '$wrong', r => r.event.content.session_id = 'wrong',
    r => r.event.content.sender_key = 'wrong', r => r.state.rooms = [],
    r => r.state.homeserver = 'http://matrix.example', r => r.state.sessions = []]) {
    const other = runtime(); mutate(other); assert.equal(await other.run(), null);
  }
});
test('no credentials or key => generic; network, crypto and storage failure => generic', async () => {
  for (const mutate of [r => r.context.sendPushPreviewStore.read = async () => null,
    r => r.context.sendPushPreviewStore.read = async () => {throw Error('storage');},
    r => r.context.fetch = async () => {throw Error('network');},
    r => r.context.wasm_bindgen.decrypt_notification = () => {throw Error('bad key');},
    r => r.context.sendPushPreviewStore.claim = async () => false]) {
    const r = runtime(); mutate(r); assert.equal(await r.run(), null);
  }
});
test('spoilers, HTML, edits and attachments cannot leak unwanted text', async () => {
  const r = runtime();
  r.decrypted.event.content.body = 'hello ||hidden||';
  assert.equal((await r.run()).body, 'hello [spoiler]');
  r.decrypted.event.content.formatted_body = '<span data-mx-spoiler>secret</span>';
  assert.equal(await r.run(), null);
  delete r.decrypted.event.content.formatted_body;
  r.decrypted.event.content.msgtype = 'm.image';
  assert.equal((await r.run()).body, 'Sent an image');
  r.decrypted.event.content['m.relates_to'] = {rel_type: 'm.replace'};
  assert.equal(await r.run(), null);
});
test('hung fetch returns generic within the worker budget', async () => {
  const r = runtime(); let signal;
  r.context.fetch = (_, options) => {signal = options.signal; return new Promise(() => {});};
  assert.equal(await r.run(), null);
  assert.equal(signal.aborted, true);
});
test('worker falls back visibly if previews throw or opt-in was revoked', async () => {
  for (const fail of [true, false]) {
    const listeners = {}, shown = [];
    const context = {importScripts() {}, sendPushPreview: async () => {
      if (fail) throw Error('preview failed');
      return {title: 'private', body: 'private', generation: 'old'};
    }, sendPushPreviewStore: {active: async () => false}, self: {
      addEventListener: (name, fn) => listeners[name] = fn,
      registration: {showNotification: async (...args) => shown.push(args)},
    }};
    vm.runInNewContext(fs.readFileSync('web/sw.js', 'utf8'), context);
    let work;
    listeners.push({data: {json: () => ({room_id: '!room:test', event_id: '$event'})}, waitUntil: p => work = p});
    await work;
    assert.equal(shown.length, 1);
    assert.equal(shown[0][1].body, 'New activity in a conversation');
  }
});
