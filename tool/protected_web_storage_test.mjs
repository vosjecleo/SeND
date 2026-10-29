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
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await puppeteer.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try {
  const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}/`);
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
  const protectedResult=await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    for(const name of ['send-vault-probe','send-sdk-probe']){
      const db=await request(indexedDB.open(name));
      for(const store of Array.from(db.objectStoreNames).filter(n=>n!=='send_encryption_v1')){
        const rows=await request(db.transaction(store).objectStore(store).getAll());
        if(rows.some(row=>row.sendEncrypted!==1))return false;
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
  console.log('Protected web storage: legacy migration, SDK session, nested transactions, rollback, isolation, read-own-writes, reopen and encrypted opaque records passed.');
}finally{await browser.close();server.close();}
