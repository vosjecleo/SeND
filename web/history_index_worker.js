/* Account-scoped, encrypted SQLite search. No media/network URLs are fetched. */
importScripts('local_vault.js', 'history_sql_worker.dart.js');
const request = req => new Promise((resolve,reject)=>{
  req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);
});
const done=tx=>new Promise((resolve,reject)=>{
  tx.oncomplete=resolve;tx.onerror=tx.onabort=()=>reject(tx.error);
});
// One owner of the IndexedDB-backed SQLite VFS. A second tab must not overwrite
// another worker's cached pages. Terminating this worker releases the lock.
const ownership=new Promise((resolve,reject)=>{
  if(!navigator.locks){reject(new Error('Protected search needs browser storage locks'));return;}
  navigator.locks.request('send-encrypted-search-worker-v1',{ifAvailable:true},lock=>{
    if(!lock){reject(new Error('Search storage is already open in another SeND tab'));return;}
    resolve();return new Promise(()=>{});
  }).catch(reject);
});
const opened=new Set();
async function legacy(account) {
  return new Promise((resolve,reject)=>{
    const req=indexedDB.open('send-history-'+account);
    let absent=false;
    req.onupgradeneeded=()=>{absent=true;req.transaction.abort();};
    req.onsuccess=()=>resolve(req.result);
    req.onerror=()=>absent?resolve(null):reject(req.error);
    req.onblocked=()=>reject(new Error('Close other SeND tabs to upgrade search storage'));
  });
}
async function migrate(account) {
  if(opened.has(account))return;
  const db=await legacy(account);
  if(db) {
    try {
      await sendHistorySqlRun(account,'migrationBudget',{});
      const settings=Object.fromEntries(await Promise.all(
        ['config','scope','historyDownload','historyGaps'].map(async key=>[key,
          await request(db.transaction('settings').objectStore('settings').get(key))])));
      let after;
      while(true) {
        const store=db.transaction('events').objectStore('events');
        const rows=await request(store.getAll(after===undefined?null:IDBKeyRange.lowerBound(after,true),100));
        if(!rows.length)break;
        if(!await sendHistorySqlRun(account,'put',{rows,text:true,limit:2048,preserve:true}))
          throw new Error('Not enough space to migrate search history. Existing data was kept.');
        // Verify every imported identity before discarding any plaintext source.
        const verified=await sendHistorySqlRun(account,'rows',{ids:rows.map(row=>row.id)});
        if(verified.length!==rows.length)throw new Error('Search migration verification failed');
        after=rows[rows.length-1].id;
      }
      await sendHistorySqlRun(account,'migrationSettings',{...settings.config,scope:settings.scope});
      for(const [slot,state] of [[1,settings.historyDownload],[2,settings.historyGaps]])
        if(state)await sendHistorySqlRun(account,'saveDownloadState',{slot,state});
      // Flush encrypted pages before removing the old plaintext database.
      await sendHistorySqlRun(account,'close',{});
    } finally {db.close();}
    await new Promise((resolve,reject)=>{
      const req=indexedDB.deleteDatabase('send-history-'+account);
      req.onsuccess=resolve;req.onerror=()=>reject(req.error);
      req.onblocked=()=>reject(new Error('Close other SeND tabs to finish upgrading search storage'));
    });
  }
  opened.add(account);
}
let queue=Promise.resolve();
self.onmessage=({data})=>{
  queue=queue.catch(()=>{}).then(async()=>{
    try {
      await ownership;
      if(!/^[a-f0-9]{64}$/.test(data.account))throw new Error('Invalid account');
      await migrate(data.account);
      const value=await sendHistorySqlRun(data.account,data.op,data.args||{});
      postMessage({id:data.id,value});
    } catch(error) {postMessage({id:data.id,error:true,stage:data.op+':'+globalThis.sendHistorySqlStage,code:typeof error?.name==='string'?error.name:'StorageError'});}
  });
};
