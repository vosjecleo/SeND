import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
import {execFileSync} from 'node:child_process';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const source = process.env.VIDEO_FIXTURE || '.dart_tool/webcodecs/source.mp4';
const server = http.createServer(async (req,res) => {
  if (req.url === '/') { res.setHeader('Content-Type','text/html'); res.end('<!doctype html><script src="/video_processing.js"></script>'); return; }
  const allowed = {'/video_processing.js':'web/video_processing.js','/web-video/worker.js':'web/web-video/worker.js','/source.mp4':source};
  if (!allowed[req.url]) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type',req.url.endsWith('.mp4')?'video/mp4':'text/javascript');
  res.end(await fs.readFile(allowed[req.url]));
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const browser = await puppeteer.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try {
  const page = await browser.newPage(); const requests = [];
  page.on('request', r => requests.push(r.url()));
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const results = await page.evaluate(async () => {
    if (!sendWebVideoSupported()) throw new Error('This test browser lacks WebCodecs');
    const bytes = new Uint8Array(await (await fetch('/source.mp4')).arrayBuffer());
    const run = (edit, id) => sendWebVideoProcess(bytes,{jobId:id,optimize:true,preset:'balanced',edit},()=>{});
    const exported = await run({startMs:500,endMs:1500,turns:1,left:.25,top:0,width:.5,height:1,muted:true},1);
    if (exported.error) throw new Error(exported.error);
    const url = URL.createObjectURL(new Blob([exported.bytes],{type:'video/mp4'}));
    const video = document.createElement('video'); video.muted=true;
    const meta = new Promise((resolve,reject) => {video.onloadedmetadata=resolve;video.onerror=reject;});
    video.src=url; await meta;
    const result={width:video.videoWidth,height:video.videoHeight,duration:video.duration, size:exported.bytes.length};
    video.removeAttribute('src');video.load();URL.revokeObjectURL(url);
    const invalid = await run({width:2},2);
    if (!invalid.error) throw new Error('Invalid crop was exported');
    const pending = run({},3); sendWebVideoCancel(3); const canceled = await pending;
    if (!canceled.error?.includes('canceled')) throw new Error('Cancellation failed');
    const noEdit = await run({},4);
    if (!noEdit.bytes) throw new Error(noEdit.error || 'AAC audio was not preserved');
    const background = run({},5);
    Object.defineProperty(document,'hidden',{value:true,configurable:true});
    document.dispatchEvent(new Event('visibilitychange')); delete document.hidden;
    if (!(await background).error?.includes('Keep SeND open')) throw new Error('Background cancellation failed');
    return {result, output:Array.from(exported.bytes), audioOutput:Array.from(noEdit.bytes)};
  });
  assert.equal(results.result.width,48); assert.equal(results.result.height,160);
  assert(Math.abs(results.result.duration-1)<.15);assert(results.result.size>0);
  await fs.writeFile('.dart_tool/webcodecs/exported.mp4',new Uint8Array(results.output));
  await fs.writeFile('.dart_tool/webcodecs/exported-audio.mp4',new Uint8Array(results.audioOutput));
  const inspect = file => JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-of','json',file]));
  assert(!inspect('.dart_tool/webcodecs/exported.mp4').streams.some(s=>s.codec_type==='audio'));
  assert(inspect('.dart_tool/webcodecs/exported-audio.mp4').streams.some(s=>s.codec_type==='audio' && s.codec_name==='aac'));
  assert(requests.every(url => url.startsWith('blob:') || url.startsWith(`http://127.0.0.1:${server.address().port}/`)));
  console.log('WebCodecs export passed: real H.264 trim/crop/rotation, metadata, input validation, cancellation and no third-party requests.');
} finally {await browser.close();server.close();}
