/* Local-record encryption, not a defence against compromised same-origin code.
 * AES-GCM/HMAC are provided by WebCrypto. Keys are non-extractable CryptoKeys.
 * Plaintext is never persisted by this module. Dataset markers prevent missing
 * keys being replaced with fresh keys over an existing encrypted database.
 */
(() => {
  'use strict';
  const keys = new Map();
  const request = req => new Promise((resolve,reject) => {
    req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(new Error('Protected storage unavailable'));
  });
  const done = tx => new Promise((resolve,reject)=>{
    tx.oncomplete=resolve;tx.onerror=tx.onabort=()=>reject(new Error('Protected storage unavailable'));
  });
  async function keyStore() {
    const req=indexedDB.open('send-local-vault-keys-v1',1);
    req.onupgradeneeded=()=>req.result.createObjectStore('keys');
    return request(req);
  }
  async function bind(dataset, expected) {
    if(typeof dataset!=='string'||dataset.length>256)throw new Error('Invalid protected store');
    const db=await keyStore();
    try {
      let value=await request(db.transaction('keys').objectStore('keys').get(dataset));
      if(!value) {
        if(expected)throw new Error('Local encryption key missing. Existing data was kept.');
        const candidate={id:crypto.randomUUID(),
          cipher:await crypto.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']),
          hash:await crypto.subtle.generateKey({name:'HMAC',hash:'SHA-256',length:256},false,['sign'])};
        // Generate outside the transaction, then recheck atomically for another
        // window/worker that might have created the same dataset first.
        const tx=db.transaction('keys','readwrite'), finished=done(tx),store=tx.objectStore('keys');
        value=await request(store.get(dataset));
        if(!value){value=candidate;store.put(value,dataset);} await finished;
      }
      if(expected&&expected!==value.id)throw new Error('Local encryption key mismatch. Existing data was kept.');
      if(value.cipher.extractable||value.hash.extractable)throw new Error('Unprotected local key');
      keys.set(dataset,value);return value.id;
    } finally {db.close();}
  }
  function key(dataset) {const result=keys.get(dataset);if(!result)throw new Error('Protected store not opened');return result;}
  const context=(dataset,store,id)=>new TextEncoder().encode(JSON.stringify([dataset,store,id]));
  async function hash(dataset,store,id) {
    const bytes=await crypto.subtle.sign('HMAC',key(dataset).hash,context(dataset,store,id));
    return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
  }
  async function seal(dataset,store,id,value) {
    const iv=crypto.getRandomValues(new Uint8Array(12));
    const cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:context(dataset,store,id)},key(dataset).cipher,
      new TextEncoder().encode(JSON.stringify(value)));
    return {sendEncrypted:1,iv,cipher:new Uint8Array(cipher)};
  }
  async function open(dataset,store,id,value) {
    const bytes=v=>Array.isArray(v)||ArrayBuffer.isView(v);
    if(!value||value.sendEncrypted!==1||!bytes(value.iv)||value.iv.length!==12||!bytes(value.cipher))
      throw new Error('Invalid encrypted record. Existing data was kept.');
    const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv:new Uint8Array(value.iv),additionalData:context(dataset,store,id)},
      key(dataset).cipher,new Uint8Array(value.cipher));
    return JSON.parse(new TextDecoder().decode(plain));
  }
  globalThis.sendLocalVault={bind,hash,seal,open};
  globalThis.sendVaultBind=bind;
  globalThis.sendVaultHash=hash;
  globalThis.sendVaultSeal=seal;
  globalThis.sendVaultOpen=open;
  globalThis.sendBrowserStorageInfo=async(persist)=>{
    const storage=navigator.storage;
    if(!storage?.estimate)return {};
    const estimate=await storage.estimate();
    const persistent=persist&&storage.persist?await storage.persist():await storage.persisted?.();
    return {usage:estimate.usage||0,quota:estimate.quota||0,persistent:!!persistent};
  };
  // The SQLite password is wrapped by a non-extractable browser key. Its
  // expected key ID is kept separately so losing keys cannot reset a database.
  globalThis.sendHistorySqlKey=async(account,existing)=>{
    const dataset='history:'+account, req=indexedDB.open('send-history-protection-v1',1);
    req.onupgradeneeded=()=>req.result.createObjectStore('accounts');
    const db=await request(req);
    try {
      let marker=await request(db.transaction('accounts').objectStore('accounts').get(account));
      if(!marker&&existing)throw new Error('Local encryption key missing. Existing data was kept.');
      const id=await bind(dataset,marker?.id);
      if(!marker){
        const password=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
        marker={id,wrapped:await seal(dataset,'password',account,password)};
        const tx=db.transaction('accounts','readwrite'),finished=done(tx);
        tx.objectStore('accounts').put(marker,account);await finished;
      }
      return await open(dataset,'password',account,marker.wrapped);
    } finally {db.close();}
  };
})();
