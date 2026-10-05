/* Bounded, read-only notification decryption; no /sync, key requests or backup
 * recovery here. A fresh/rotated Megolm key requires opening the main app.
 */
(() => {
  'use strict';
  let cryptoReady;
  async function loadCrypto() {
    if (!cryptoReady) cryptoReady = (async () => {
      await wasm_bindgen({module_or_path: '/push-crypto/send_push_crypto_bg.wasm'});
      return wasm_bindgen;
    })().catch(error => {cryptoReady = null; throw error;});
    return cryptoReady;
  }
  const clean = value => typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, ' ').trim().slice(0, 180) : '';
  async function fetchEvent(state, room, event, signal) {
    const server = new URL(state.homeserver);
    if (server.protocol !== 'https:' || server.username || server.password) throw new Error('Unsafe server');
    const url = new URL('/_matrix/client/v3/rooms/' + encodeURIComponent(room) + '/event/' + encodeURIComponent(event), server);
    const response = await fetch(url.href, {headers: {Authorization: 'Bearer ' + state.token},
      signal, credentials: 'omit', redirect: 'error', cache: 'no-store', referrerPolicy: 'no-referrer'});
    if (!response.ok || Number(response.headers.get('content-length')) > 196608) throw new Error('Event unavailable');
    const reader = response.body.getReader();
    const chunks = []; let size = 0;
    try {
      for (;;) {
        const {value, done} = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 196608) throw new Error('Event too large');
        chunks.push(value);
      }
    } finally { await reader.cancel(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(bytes));
  }
  async function preview(data, signal) {
    const state = await sendPushPreviewStore.read();
    if (!state || data.test || typeof data.event_id !== 'string' || !data.event_id ||
        data.event_id.length > 1024 || !state.rooms.includes(data.room_id)) return null;
    const event = await fetchEvent(state, data.room_id, data.event_id, signal);
    if (event.event_id !== data.event_id || event.room_id !== data.room_id ||
        event.sender === state.user || event.type !== 'm.room.encrypted' ||
        event.content?.algorithm !== 'm.megolm.v1.aes-sha2' || event.unsigned?.redacted_because) return null;
    const session = state.sessions.find(s => s.room === data.room_id && s.id === event.content.session_id &&
      s.senderKey === event.content.sender_key && s.sender === event.sender);
    if (!session) return null;
    const crypto = await loadCrypto();
    if (signal.aborted) return null;
    const decrypted = JSON.parse(crypto.decrypt_notification(session.key, event.content.ciphertext, session.id, session.room));
    const content = decrypted.event.content;
    if (decrypted.event.type !== 'm.room.message' || !content || content['m.relates_to']?.rel_type === 'm.replace') return null;
    // Spoilers must never be revealed on a lock screen. Do not render HTML.
    const body = ['m.text', 'm.notice', 'm.emote'].includes(content.msgtype)
      ? clean((content.body || '').replace(/\|\|[\s\S]*?\|\|/g, '[spoiler]'))
      : ({'m.image': 'Sent an image', 'm.video': 'Sent a video', 'm.audio': 'Sent audio', 'm.file': 'Sent a file'}[content.msgtype] || 'New message');
    if (!body || content.formatted_body?.includes('data-mx-spoiler') || signal.aborted) return null;
    if (!await sendPushPreviewStore.claim(state.generation, session.id, decrypted.index)) return null;
    return {title: clean(session.name) || clean(event.sender) || 'SeND', body, generation: state.generation};
  }
  globalThis.sendPushPreview = async data => {
    const controller = new AbortController();
    let timer;
    try {
      return await Promise.race([preview(data, controller.signal), new Promise(resolve => {
        timer = setTimeout(() => {controller.abort(); resolve(null);}, 3500);
      })]);
    } catch (_) { return null; }
    finally { clearTimeout(timer); controller.abort(); }
  };
})();
