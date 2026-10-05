/* Device-only preview snapshots. Never touches the Matrix SDK database.
 * WebCrypto protects records at rest, not against same-origin script compromise.
 * No plaintext messages are stored. The non-extractable key stays in IndexedDB.
 */
(() => {
  'use strict';
  const request = req => new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(new Error('Preview storage unavailable'));
  });
  async function database() {
    const open = indexedDB.open('send-push-previews-v1', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('private');
    return request(open);
  }
  async function transaction(mode, action) {
    const db = await database();
    try {
      const tx = db.transaction('private', mode);
      const done = new Promise((resolve, reject) => {
        tx.oncomplete = resolve;
        tx.onabort = tx.onerror = () => reject(new Error('Preview storage unavailable'));
      });
      const value = await action(tx.objectStore('private'));
      await done;
      return value;
    } finally { db.close(); }
  }
  let writes = Promise.resolve();
  function serial(action) {
    const result = writes.then(action);
    writes = result.catch(() => {});
    return result;
  }
  const store = {
    write: value => serial(async () => {
      if (!value) {
        await transaction('readwrite', s => request(s.clear()));
        return;
      }
      const old = await transaction('readonly', s => request(s.get('state')));
      const same = old?.owner === value.owner;
      const key = same ? old.key : await crypto.subtle.generateKey(
        {name: 'AES-GCM', length: 256}, false, ['encrypt', 'decrypt']);
      const id = same ? old.id : crypto.randomUUID();
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const cipher = await crypto.subtle.encrypt({name: 'AES-GCM', iv}, key,
        new TextEncoder().encode(JSON.stringify(value)));
      await transaction('readwrite', async s => {
        if (!same) await request(s.clear());
        await request(s.put({owner: value.owner, id, key, iv, cipher}, 'state'));
      });
    }),
    read: async () => {
      const state = await transaction('readonly', s => request(s.get('state')));
      if (!state) return null;
      const plain = await crypto.subtle.decrypt({name: 'AES-GCM', iv: state.iv}, state.key, state.cipher);
      const value = JSON.parse(new TextDecoder().decode(plain));
      if (value.expires < Date.now()) return null;
      return {...value, generation: state.id};
    },
    active: async generation => (await transaction('readonly', s => request(s.get('state'))))?.id === generation,
    // No plaintext: remember only the highest authenticated index per session.
    // Duplicate/older pushes must not replace a newer preview or replay a message.
    claim: (generation, session, index) => transaction('readwrite', async s => {
      const state = await request(s.get('state'));
      if (state?.id !== generation) return false;
      const key = 'seen:' + session;
      const previous = await request(s.get(key));
      if (previous !== undefined && previous >= index) return false;
      await request(s.put(index, key));
      return true;
    }),
  };
  globalThis.sendPushPreviewStore = store;
  globalThis.sendWritePushPreview = json => store.write(json ? JSON.parse(json) : null);
})();
