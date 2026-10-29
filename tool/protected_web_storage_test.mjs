import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
const {default:puppeteer}=await import(process.env.PUPPETEER_MODULE||'puppeteer-core');
const server=http.createServer(async(req,res)=>{
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/local_vault.js"></script><script src="/probe.js"></script>');return;}
  const file=req.url==='/local_vault.js'?'web/local_vault.js':req.url==='/probe.js'?'.dart_tool/protected_web_storage_probe.js':null;
  if(!file){res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type','application/javascript');res.end(await fs.readFile(file));
});
await new Promise(r=>server.listen(Number(process.env.PORT||0),'127.0.0.1',r));
const remote=process.env.CHROME_REMOTE_URL;
const browser=remote?await puppeteer.connect({browserURL:remote}):await puppeteer.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
let page;
try {
  page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    for(const [name,stores] of [['send-vault-probe',['values','other']],['send-sdk-probe',['box_client']]]){
      const req=indexedDB.open(name,11);req.onupgradeneeded=()=>{for(const store of stores)req.result.createObjectStore(store);};
      const db=await request(req),tx=db.transaction(stores,'readwrite');
      if(name==='send-vault-probe')tx.objectStore('values').put({body:'legacy secret'},'!room:test');
      else {tx.objectStore('box_client').put('11','version');tx.objectStore('box_client').put('legacy-token-fixture','token');}
      await new Promise((r,j)=>{tx.oncomplete=r;tx.onerror=j;});db.close();
    }
  });
  assert.equal(await page.evaluate(()=>sendProtectedProbe()),true);
  assert.equal(await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    const name='send-mixed-marker-probe',dataset='matrix:'+name;
    await sendVaultBind(dataset,null);
    const sealed=await sendVaultSeal(dataset,'values','z-encrypted',{key:'fixture',value:{body:'retained'}});
    const req=indexedDB.open(name,1101);req.onupgradeneeded=()=>{
      req.result.createObjectStore('values');req.result.createObjectStore('send_encryption_v1');
    };
    const db=await request(req),tx=db.transaction('values','readwrite');
    tx.objectStore('values').put({body:'plain retained'},'a-plain');tx.objectStore('values').put(sealed,'z-encrypted');
    await new Promise((r,j)=>{tx.oncomplete=r;tx.onabort=j;});db.close();
    const keyDb=await request(indexedDB.open('send-local-vault-keys-v1'));
    const drop=keyDb.transaction('keys','readwrite');drop.objectStore('keys').delete(dataset);
    await new Promise((r,j)=>{drop.oncomplete=r;drop.onabort=j;});
    if(await sendProtectedMixedMarkerProbe()!==false)return false;
    const recreated=await request(keyDb.transaction('keys').objectStore('keys').get(dataset));
    keyDb.close();
    const check=await request(indexedDB.open(name));
    const plain=await request(check.transaction('values').objectStore('values').get('a-plain'));
    check.close();return recreated===undefined&&plain.body==='plain retained'&&plain.sendEncrypted===undefined;
  }),true);
  assert.equal(await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    const name='send-index-upgrade-probe', dataset='matrix:'+name;
    const keyId=await sendVaultBind(dataset,null);
    const rows=[];
    for(const key of ['!legacy:test|one','!legacy:test|two']){
      const hidden=await sendVaultHash(dataset,'values',key);
      rows.push([hidden,await sendVaultSeal(dataset,'values',hidden,{key,value:{body:'retained secret'}})]);
    }
    const req=indexedDB.open(name,1101);
    req.onupgradeneeded=()=>{req.result.createObjectStore('values');req.result.createObjectStore('send_encryption_v1');};
    const db=await request(req), tx=db.transaction(['values','send_encryption_v1'],'readwrite');
    for(const [key,value] of rows)tx.objectStore('values').put(value,key);
    tx.objectStore('send_encryption_v1').put(keyId,'key');tx.objectStore('send_encryption_v1').put(true,'migrated');
    await new Promise((r,j)=>{tx.oncomplete=r;tx.onabort=j;});db.close();
    const original=IDBObjectStore.prototype.put;
    let aborted=false;
    IDBObjectStore.prototype.put=function(...args){
      if(this.name==='values__keys_v1'&&!aborted){aborted=true;this.transaction.abort();}
      return original.apply(this,args);
    };
    try{if(await sendProtectedIndexUpgradeProbe()!==false||!aborted)return false;}
    finally{IDBObjectStore.prototype.put=original;}
    return await sendProtectedIndexUpgradeProbe()===true && await sendProtectedIndexUpgradeProbe()===true;
  }),true);
  assert.equal(await page.evaluate(async()=>{
    const original=IDBObjectStore.prototype.put;
    let aborted=false;
    IDBObjectStore.prototype.put=function(...args){
      if(this.name==='box_events'&&!aborted){aborted=true;this.transaction.abort();}
      return original.apply(this,args);
    };
    try{return await sendProtectedImportFailureProbe()===true&&aborted;}
    finally{IDBObjectStore.prototype.put=original;}
  }),true);
  const protectedResult=await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    for(const name of ['send-vault-probe','send-sdk-probe']){
      const db=await request(indexedDB.open(name));
      for(const store of Array.from(db.objectStoreNames).filter(n=>n!=='send_encryption_v1')){
        const rows=await request(db.transaction(store).objectStore(store).getAll());
        if(rows.some(row=>(store.endsWith('__keys_v1')?row.sealed:row).sendEncrypted!==1))return false;
        const keys=await request(db.transaction(store).objectStore(store).getAllKeys());
        if(keys.some(key=>!/^\w{64}$/.test(key)))return false;
      }
      db.close();
    }
    return true;
  });
  assert.equal(protectedResult,true);
  assert.equal(await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    const commit=tx=>new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onerror=tx.onabort=reject;});
    const db=await request(indexedDB.open('send-vault-probe'));
    const marker=await request(db.transaction('send_encryption_v1').objectStore('send_encryption_v1').get('key'));
    for(const invalid of ['',123]){
      let update=db.transaction('send_encryption_v1','readwrite'),saved=commit(update);
      update.objectStore('send_encryption_v1').put(invalid,'key');await saved;
      if(await sendProtectedProbeRead())return false;
    }
    let restore=db.transaction('send_encryption_v1','readwrite'),restored=commit(restore);
    restore.objectStore('send_encryption_v1').put(marker,'key');await restored;
    if(!await sendProtectedProbeRead())return false;
    const store=db.transaction('values').objectStore('values'),keys=await request(store.getAllKeys());
    const key=keys[0],original=await request(db.transaction('values').objectStore('values').get(key));
    let tx=db.transaction('values','readwrite'),saved=commit(tx);
    const damaged=structuredClone(original);damaged.cipher[0]^=1;tx.objectStore('values').put(damaged,key);await saved;
    if(await sendProtectedProbeRead())return false;
    tx=db.transaction('values','readwrite');saved=commit(tx);tx.objectStore('values').put(original,key);await saved;
    if(!await sendProtectedProbeRead())return false;
    const keyDb=await request(indexedDB.open('send-local-vault-keys-v1'));
    tx=keyDb.transaction('keys','readwrite');saved=commit(tx);tx.objectStore('keys').delete('matrix:send-vault-probe');await saved;
    if(await sendProtectedProbeRead())return false;
    const count=await request(db.transaction('values').objectStore('values').count());
    db.close();keyDb.close();return count===1;
  }),true);
  console.log('Protected web storage: migration, complete non-destructive dumps, invalid/aborted import recovery, sessions, receipts, nested transactions, rollback, isolation, reopen and encrypted opaque records passed.');
}finally{
  if(remote){
    if(page){
      await page.evaluate(async()=>{
        const request=r=>new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
        const names=['send-vault-probe','send-sdk-probe','send-index-upgrade-probe','send-mixed-marker-probe'];
        for(const name of names)await request(indexedDB.deleteDatabase(name));
        const db=await request(indexedDB.open('send-local-vault-keys-v1'));
        if(db.objectStoreNames.contains('keys')){
          const tx=db.transaction('keys','readwrite');
          for(const name of names)tx.objectStore('keys').delete('matrix:'+name);
          await new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onabort=reject;});
        }
        db.close();
      });
      await page.close();
    }
    browser.disconnect();
  }else await browser.close();
  server.close();
}
