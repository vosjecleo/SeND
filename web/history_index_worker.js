/* Account-scoped metadata/text index. It never fetches media or network URLs. */
const databases = new Map();
const entryLimit = limit => 100000 * Math.max(1, Math.min(21, Math.ceil(limit / 100)));
const result = request => new Promise((resolve,reject) => { request.onsuccess=()=>resolve(request.result); request.onerror=()=>reject(request.error); });
const done = tx => new Promise((resolve,reject) => { tx.oncomplete=resolve; tx.onerror=tx.onabort=()=>reject(tx.error); });
async function open(account) {
  if (!/^[a-f0-9]{64}$/.test(account)) throw new Error('Invalid account');
  if (databases.has(account)) return databases.get(account);
  const request=indexedDB.open('send-history-'+account,1);
  request.onupgradeneeded=()=> {
    const db=request.result, events=db.createObjectStore('events',{keyPath:'id'});
    events.createIndex('roomTime',['room','time','id']);
    events.createIndex('time','time');
    db.createObjectStore('settings');
  };
  const db=await result(request); databases.set(account,db); return db;
}
async function walk(request, visit) {
  return new Promise((resolve,reject) => {
    request.onerror=()=>reject(request.error);
    request.onsuccess=()=> { const cursor=request.result; if (!cursor) return resolve();
      if(visit(cursor)===false) return resolve(); cursor.continue(); };
  });
}
async function stats(db) {
  const cached=await result(db.transaction('settings').objectStore('settings').get('totals'));
  if(cached) return cached;
  const tx=db.transaction('events'), store=tx.objectStore('events'); let bytes=0,entries=0;
  await walk(store.openCursor(),c=>{ bytes+=c.value.bytes; entries++; });
  return {bytes,entries};
}
async function trim(db,limit) {
  const totals=await stats(db), tx=db.transaction(['events','settings'],'readwrite'), finished=done(tx);
  await walk(tx.objectStore('events').index('time').openCursor(), c=> {
    if(totals.bytes<=limit*1048576 && totals.entries<=entryLimit(limit)) return false;
    totals.bytes-=c.value.bytes;totals.entries--;c.delete();
  }); tx.objectStore('settings').put(totals,'totals');await finished;
}
async function run(account,op,args={}) {
  const db=await open(account);
  if(op==='open') return true;
  if(op==='close') { db.close();databases.delete(account);return true; }
  if(op==='settings') return (await result(db.transaction('settings').objectStore('settings').get('config'))) || {};
  if(op==='scope') return (await result(db.transaction('settings').objectStore('settings').get('scope'))) || null;
  if(op==='setScope') {
    if(!['dms','groups','all'].includes(args.scope) || !Array.isArray(args.rooms)) throw new Error('Invalid scope');
    const allowed=new Set(args.rooms), tx=db.transaction(['events','settings'],'readwrite'),finished=done(tx),settings=tx.objectStore('settings');
    await walk(tx.objectStore('events').openCursor(),c=>{if(!allowed.has(c.value.room)) c.delete();});
    const config=await result(settings.get('config'));
    settings.put({...config,warning:0},'config');settings.put(args.scope,'scope');settings.delete('totals');settings.delete('historyDownload');
    await finished;return true;
  }
  if(op==='downloadState') return (await result(db.transaction('settings').objectStore('settings').get('historyDownload'))) || null;
  if(op==='saveDownloadState') {
    if(args.state && new TextEncoder().encode(JSON.stringify(args.state)).length > 3*1048576) throw new Error('History progress too large');
    const tx=db.transaction('settings','readwrite'),finished=done(tx),s=tx.objectStore('settings');
    if(args.state) s.put(args.state,'historyDownload'); else s.delete('historyDownload');
    await finished;return true;
  }
  if(op==='rows') {
    if(!Array.isArray(args.ids) || args.ids.length>200) throw new Error('Invalid result count');
    const s=db.transaction('events').objectStore('events');
    return (await Promise.all(args.ids.map(id=>result(s.get(id))))).filter(Boolean);
  }
  if(op==='stats') {const s=await stats(db), c=await result(db.transaction('settings').objectStore('settings').get('config'));return {...s,budgetBytes:s.bytes,warning:c?.warning||0};}
  if(op==='ackWarning') {const tx=db.transaction('settings','readwrite'),finished=done(tx),s=tx.objectStore('settings');const c=await result(s.get('config'));s.put({...c,warning:1},'config');await finished;return true;}
  if(op==='revision') return (await result(db.transaction('events').objectStore('events').get(args.id)))?.revision || null;
  if(op==='clear') { const tx=db.transaction(['events','settings'],'readwrite');const finished=done(tx);tx.objectStore('events').clear();const s=tx.objectStore('settings'),c=await result(s.get('config'));s.delete('historyDownload');s.put({...c,warning:0},'config');s.put({bytes:0,entries:0},'totals');await finished;return true; }
  if(op==='configure') {
    const tx=db.transaction(['events','settings'],'readwrite'), finished=done(tx);
    const prior=await result(tx.objectStore('settings').get('config'));
    tx.objectStore('settings').put({...args,prompted:true,warning:prior?.limit===args.limit ? prior.warning||0 : 0},'config');
    tx.objectStore('settings').delete('totals');
    if(!args.enabled) tx.objectStore('settings').delete('historyDownload');
    if(!args.enabled) await walk(tx.objectStore('events').openCursor(),c=> {
      if(!c.value.kind) c.delete(); else c.update({...c.value,body:'',tokens:[],bytes:512+JSON.stringify([c.value.id,c.value.room,c.value.sender]).length*3});
    });
    await finished;await trim(db,args.limit);return true;
  }
  if(op==='put') {
    const totals=await stats(db);
    const tx=db.transaction(['events','settings'],'readwrite'), finished=done(tx), store=tx.objectStore('events');
    for(const row of args.rows) {
      const old=await result(store.get(row.id));
      if(!row.deleted && old && (old.edited_at||0)>(row.edited_at||0)) continue;
      if(old) { totals.bytes-=old.bytes;totals.entries--; }
      if(row.deleted || (!args.text && !row.kind)) { store.delete(row.id);continue; }
      const body=args.text ? row.body||'' : '';
      const value={...row,body};value.bytes=512+new TextEncoder().encode(JSON.stringify(value)).length*3;
      totals.bytes+=value.bytes;totals.entries++;
      store.put(value);
    } const settings=tx.objectStore('settings'), config=await result(settings.get('config'));
    if(args.preserve && (totals.bytes>args.limit*1048576 || totals.entries>entryLimit(args.limit))) {
      tx.abort();try { await finished; } catch (_) {} return false;
    }
    if((totals.bytes>=args.limit*1048576*.8 || totals.entries>=entryLimit(args.limit)*.8) && !config?.warning)settings.put({...config,warning:2},'config');
    settings.put(totals,'totals');await finished;if(!args.preserve) await trim(db,args.limit);return true;
  }
  if(op==='query') {
    const tx=db.transaction('events'), store=tx.objectStore('events'), found=new Map();
    const terms=(args.terms||[]).map(t=>t.toLowerCase());
    const request=store.index('roomTime').openCursor(IDBKeyRange.bound([args.room,0,''],[args.room,Number.MAX_SAFE_INTEGER,'\uffff']),'prev');
    await walk(request,c=> {
      const row=c.value;
      if(row.room!==args.room || (args.before!=null && row.time>=args.before) || (args.after!=null && row.time<=args.after)) return;
      if(args.kind==='media' ? !['image','video'].includes(row.kind) : args.kind==='file' ? !['image','video','audio','file'].includes(row.kind) : args.kind && row.kind!==args.kind) return;
      if(args.sender && !row.sender.toLowerCase().includes(args.sender.toLowerCase())) return;
      if(!terms.every(t=>row.body.toLowerCase().includes(t))) return;
      found.set(row.id,{id:row.id,time:row.time});
      if(found.size>=args.offset+args.limit) return false;
    });
    return [...found.values()].sort((a,b)=>b.time-a.time || (a.id<b.id?1:a.id>b.id?-1:0))
      .slice(args.offset,args.offset+args.limit).map(r=>r.id);
  }
  throw new Error('Unknown operation');
}
let queue=Promise.resolve();
self.onmessage=({data})=> {
  queue=queue.catch(()=>{}).then(async()=> {
    try { const value=await run(data.account,data.op,data.args||{});postMessage({id:data.id,value}); }
    catch(_) { postMessage({id:data.id,error:true}); }
  });
};
