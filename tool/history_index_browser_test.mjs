import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
const {default:puppeteer}=await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const server=http.createServer(async(req,res)=>{
  if(req.url==='/') {res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/history_index.js"></script>');return;}
  if(['/history_index.js','/history_index_worker.js','/local_vault.js','/history_sql_worker.dart.js','/sqlite3mc.wasm'].includes(req.url)) {
    res.setHeader('Content-Type',req.url.endsWith('.wasm')?'application/wasm':'application/javascript');res.end(await fs.readFile('web'+req.url));return;
  }
  res.writeHead(404);res.end();
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await puppeteer.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try {
  const page=await browser.newPage();
  const requests=[];page.on('request',r=>requests.push(r.url()));
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    const account='c'.repeat(64),req=indexedDB.open('send-history-'+account,1);
    req.onupgradeneeded=()=>{req.result.createObjectStore('events',{keyPath:'id'});req.result.createObjectStore('settings');};
    const db=await request(req),tx=db.transaction(['events','settings'],'readwrite');
    for(let i=0;i<241;i++)tx.objectStore('events').put({id:'legacy-'+String(i).padStart(3,'0'),room:'!legacy:test',time:i,
      kind:'image',sender:'@legacy:test',body:'legacy migration secret',bytes:900});
    tx.objectStore('settings').put({enabled:true,prompted:true,limit:16},'config');
    tx.objectStore('settings').put('dms','scope');
    tx.objectStore('settings').put({cursor:'migration-cursor'},'historyDownload');
    await new Promise((r,j)=>{tx.oncomplete=r;tx.onerror=j;});db.close();
    const call=(op,args)=>sendHistoryIndexCall(account,op,args);
    await call('open');
    if((await call('stats')).entries!==241||(await call('settings')).limit!==16||(await call('scope'))!=='dms'||
       (await call('downloadState')).cursor!=='migration-cursor')throw new Error('Legacy history migration lost data/settings');
    const ids=await call('query',{room:'!legacy:test',terms:['migration secret'],offset:0,limit:50});
    if(ids.length!==50)throw new Error('Migrated history did not search');
    await call('close');
    if((await indexedDB.databases()).some(db=>db.name==='send-history-'+account))throw new Error('Plaintext source survived verified migration');
  });
  const results=await page.evaluate(async()=>{
    const account='a'.repeat(64),call=(op,args)=>window.sendHistoryIndexCall(account,op,args);
    const row=(id,body,kind='',time=1)=>({id,body,kind,time,room:'!r:test',sender:'@a:test'});
    const query=(args={})=>call('query',{room:'!r:test',terms:[],limit:50,offset:0,...args});
    await call('open');
    await call('put',{rows:[row('text','secret'),row('image','secret','image')],text:false,limit:16});
    const mediaOnly=await query(),noText=await query({terms:['secret']});
    await call('configure',{enabled:true,limit:16});
    await call('put',{rows:[row('text','hello distant world'),row('new','world hello','',2)],text:true,limit:16});
    const words=await query({terms:['hello','world']});
    if((await query({terms:['hello world']})).length) throw new Error('Phrase search accepted separated/reversed words');
    await call('put',{rows:[row('text','changed'),{...row('new',''),deleted:true}],text:true,limit:16});
    const edited=await query({terms:['changed']}),redacted=await query({terms:['world']});
    const isolated=await window.sendHistoryIndexCall('b'.repeat(64),'query',{room:'!r:test',terms:[],limit:50,offset:0});
    await call('close');await call('open');
    const reopened=await query({terms:['changed']});
    await call('configure',{enabled:false,limit:16});
    const disabled=await query();
    await call('clear');
    const empty=await call('stats');
    if(empty.bytes<0||empty.bytes>1048576)throw new Error('Unexpected empty SQLite overhead');
    delete empty.bytes;
    await call('put',{rows:[{...row('upper','','file'),sender:'@Alice:test'},{...row('lower','','audio'),sender:'@alice:test'},row('picture','','image')],text:false,limit:16});
    const documents=await query({kind:'document'}),selectedSender=await query({sender:'@Alice:test'});
    if(documents.sort().join(',')!=='lower,upper'||selectedSender.join(',')!=='upper')throw new Error('Catalog type or selected member filter failed');
    await call('clear');
    await call('put',{rows:Array.from({length:120},(_,i)=>row(String(i).padStart(3,'0'),'','image',42)),text:false,limit:16});
    const pages=[...await query(),...await query({offset:50}),...await query({offset:100})];
    await call('configure',{enabled:true,limit:16});
    for(let page=0;page<3;page++)await call('put',{rows:Array.from({length:100},(_,i)=>({
      ...row('pressure-'+page+'-'+i,'','image'),sender:'@'+'x'.repeat(10000)+':test'})),text:true,limit:16});
    const warning=(await call('stats')).warning;
    await call('ackWarning');await call('close');await call('open');
    const acknowledged=(await call('stats')).warning;
    await call('clear');const clearedWarning=(await call('stats')).warning;
    const assertAccepted=await call('put',{rows:[row('kept','x'.repeat(1000000))],text:true,limit:16,preserve:true});
    if(!assertAccepted)throw new Error('Bounded history page did not fit');
    const quotaAccepted=await call('put',{rows:[row('reject','z'.repeat(4000000))],text:true,limit:16,preserve:true});
    const quotaIds=await query(), storedRows=await call('rows',{ids:['kept']});
    await call('saveDownloadState',{state:{version:1,rooms:['!r:test'],position:0,cursor:'opaque'}});
    await call('saveDownloadState',{slot:2,state:{gap:'independent'}});
    await call('close');await call('open');const savedCursor=(await call('downloadState')).cursor;
    await call('saveDownloadState',{state:null});const resetJob=await call('downloadState');
    const assertGap=(await call('downloadState',{slot:2})).gap;
    if(assertGap!=='independent')throw new Error('Manual reset erased gap progress');
    await call('put',{rows:[{...row('excluded','server text','video'),room:'!server:test'}],text:true,limit:16});
    await call('setScope',{scope:'dms',rooms:['!r:test']});
    if(await call('downloadState',{slot:2})!==null)throw new Error('Scope change retained gap progress');
    const scoped=await call('query',{room:'!server:test',terms:[],limit:50,offset:0});
    if(scoped.length) throw new Error('Excluded room survived scope pruning');
    await call('configure',{enabled:true,limit:25});await call('close');await call('open');
    if(await call('scope')!=='dms') throw new Error('Scope did not survive settings/reopen');
    return {mediaOnly,noText,words,edited,redacted,isolated,reopened,disabled,empty,unique:new Set(pages).size,warning,acknowledged,clearedWarning,quotaAccepted,quotaIds,storedBodyLength:storedRows[0].body.length,savedCursor,resetJob};
  });
  assert.deepEqual(results,{mediaOnly:['image'],noText:[],words:['new','text'],edited:['text'],redacted:[],isolated:[],reopened:['text'],disabled:['image'],empty:{entries:0,budgetBytes:0,warning:0},unique:120,warning:2,acknowledged:1,clearedWarning:0,quotaAccepted:false,quotaIds:['kept'],storedBodyLength:1000000,savedCursor:'opaque',resetJob:null});
  assert(requests.every(url=>url.startsWith(`http://127.0.0.1:${server.address().port}/`)));
  assert.equal(await page.evaluate(async()=>{
    const request=req=>new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
    const db=await request(indexedDB.open('send-history-encrypted-v1'));
    const blocks=await request(db.transaction('blocks').objectStore('blocks').getAll());
    db.close();
    for(const block of blocks){
      const text=new TextDecoder().decode(new Uint8Array(block));
      if(text.includes('SQLite format 3')||text.includes('legacy migration secret')||text.includes('x'.repeat(32)))return false;
    }
    const account='a'.repeat(64);
    await sendHistoryIndexCall(account,'close');
    const keys=await request(indexedDB.open('send-local-vault-keys-v1'));
    const tx=keys.transaction('keys','readwrite');tx.objectStore('keys').delete('history:'+account);
    await new Promise((r,j)=>{tx.oncomplete=r;tx.onerror=j;});keys.close();
    try{await sendHistoryIndexCall(account,'open');return false;}catch(_){return true;}
  }),true);
  console.log('Browser index: metadata-only mode, opt-in, terms, edits, redactions, account isolation, restart, opt-out and clearing passed. No media/network requests.');
} finally {await browser.close();server.close();}
