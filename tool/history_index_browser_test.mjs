import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
const {default:puppeteer}=await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const server=http.createServer(async(req,res)=>{
  if(req.url==='/') {res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/history_index.js"></script>');return;}
  if(['/history_index.js','/history_index_worker.js'].includes(req.url)) {
    res.setHeader('Content-Type','application/javascript');res.end(await fs.readFile('web'+req.url));return;
  }
  res.writeHead(404);res.end();
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await puppeteer.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try {
  const page=await browser.newPage();
  const requests=[];page.on('request',r=>requests.push(r.url()));
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
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
    await call('put',{rows:[row('text','changed'),{...row('new',''),deleted:true}],text:true,limit:16});
    const edited=await query({terms:['changed']}),redacted=await query({terms:['world']});
    const isolated=await window.sendHistoryIndexCall('b'.repeat(64),'query',{room:'!r:test',terms:[],limit:50,offset:0});
    await call('close');await call('open');
    const reopened=await query({terms:['changed']});
    await call('configure',{enabled:false,limit:16});
    const disabled=await query();
    await call('clear');
    const empty=await call('stats');
    await call('put',{rows:Array.from({length:120},(_,i)=>row(String(i).padStart(3,'0'),'','image',42)),text:false,limit:16});
    const pages=[...await query(),...await query({offset:50}),...await query({offset:100})];
    await call('configure',{enabled:true,limit:16});
    await call('put',{rows:[row('large','x'.repeat(5000000))],text:true,limit:16});
    const warning=(await call('stats')).warning;
    await call('ackWarning');await call('close');await call('open');
    const acknowledged=(await call('stats')).warning;
    await call('clear');const clearedWarning=(await call('stats')).warning;
    await call('put',{rows:[row('kept','x'.repeat(4000000))],text:true,limit:16,preserve:true});
    const quotaAccepted=await call('put',{rows:[row('reject','z'.repeat(2000000))],text:true,limit:16,preserve:true});
    const quotaIds=await query(), storedRows=await call('rows',{ids:['kept']});
    await call('saveDownloadState',{state:{version:1,rooms:['!r:test'],position:0,cursor:'opaque'}});
    await call('close');await call('open');const savedCursor=(await call('downloadState')).cursor;
    await call('saveDownloadState',{state:null});const resetJob=await call('downloadState');
    await call('put',{rows:[{...row('excluded','server text','video'),room:'!server:test'}],text:true,limit:16});
    await call('setScope',{scope:'dms',rooms:['!r:test']});
    const scoped=await call('query',{room:'!server:test',terms:[],limit:50,offset:0});
    if(scoped.length) throw new Error('Excluded room survived scope pruning');
    await call('configure',{enabled:true,limit:25});await call('close');await call('open');
    if(await call('scope')!=='dms') throw new Error('Scope did not survive settings/reopen');
    return {mediaOnly,noText,words,edited,redacted,isolated,reopened,disabled,empty,unique:new Set(pages).size,warning,acknowledged,clearedWarning,quotaAccepted,quotaIds,storedBodyLength:storedRows[0].body.length,savedCursor,resetJob};
  });
  assert.deepEqual(results,{mediaOnly:['image'],noText:[],words:['new','text'],edited:['text'],redacted:[],isolated:[],reopened:['text'],disabled:['image'],empty:{bytes:0,entries:0,budgetBytes:0,warning:0},unique:120,warning:2,acknowledged:1,clearedWarning:0,quotaAccepted:false,quotaIds:['kept'],storedBodyLength:4000000,savedCursor:'opaque',resetJob:null});
  assert(requests.every(url=>url.startsWith(`http://127.0.0.1:${server.address().port}/`)));
  console.log('Browser index: metadata-only mode, opt-in, terms, edits, redactions, account isolation, restart, opt-out and clearing passed. No media/network requests.');
} finally {await browser.close();server.close();}
