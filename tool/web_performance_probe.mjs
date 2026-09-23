// Read-only build-100 diagnostics. Credentials arrive over stdin, never argv,
// environment, source, console logs or trace files. Uses disposable profiles.
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
import {createInterface} from 'node:readline';
import {readFileSync, readdirSync} from 'node:fs';

const mode = process.argv[2] || 'chromium';
const firefox = mode !== 'chromium';
const executablePath = mode === 'chromium' ? '/usr/bin/chromium' : mode === 'firefox' ? '/usr/bin/firefox' : '/usr/bin/librewolf';
const browser = await puppeteer.launch({
  executablePath, browser: firefox ? 'firefox' : 'chrome', headless: false,
  defaultViewport: {width: 1280, height: 800, ...(process.env.PERF_DPR ? {deviceScaleFactor:Number(process.env.PERF_DPR)} : {})},
  args: firefox ? ['--remote-allow-system-access'] : ['--no-sandbox'],
  ...(firefox ? {extraPrefsFirefox: {
    'webgl.disabled': false,
    'privacy.resistFingerprinting': mode === 'librewolf-rfp',
    'privacy.fingerprintingProtection': mode === 'librewolf',
    ...(process.env.PERF_WEBGL_ALLOW === '1' ? {'permissions.default.webgl': 1} : {}),
  }} : {}),
});
const page = await browser.newPage();
let sync = {responses: 0, joinedRooms: 0, stateEvents: 0, timelineEvents: 0, accountDataEvents: 0};
let errors = 0;
let credentialsSubmitted = false;
page.on('pageerror', error => {
  errors++;
  if (!credentialsSubmitted && process.env.PERF_SEMANTICS === '0') console.log(JSON.stringify({startupError: error.message.slice(0,500)}));
});
page.on('console', message => {
  // Record only fixed rendering diagnostics, never arbitrary SDK logs.
  if (message.text().includes('Falling back to CPU-only rendering')) console.log(JSON.stringify({rendererWarning:'Flutter CPU-only fallback'}));
});
page.on('response', async response => {
  if (!new URL(response.url()).pathname.endsWith('/sync')) return;
  try {
    const data = await response.json();
    sync.responses++;
    const rooms = Object.values(data.rooms?.join || {});
    sync.joinedRooms = Math.max(sync.joinedRooms, rooms.length);
    sync.stateEvents += rooms.reduce((n,r) => n + (r.state?.events?.length || 0), 0);
    sync.timelineEvents += rooms.reduce((n,r) => n + (r.timeline?.events?.length || 0), 0);
    sync.accountDataEvents += data.account_data?.events?.length || 0;
  } catch { /* No raw HTTP errors, credentials or Matrix payloads in logs. */ }
});
await page.evaluateOnNewDocument(() => {
  window.__perfLongTasks = [];
  try { new PerformanceObserver(list => {
    for (const item of list.getEntries()) window.__perfLongTasks.push(item.duration);
  }).observe({type: 'longtask', buffered: true}); } catch {}
});
await page.goto(process.env.PERF_URL || 'https://chat.deltie.net/', {waitUntil: 'domcontentloaded'});
if (process.env.PERF_SEMANTICS !== '0') {
  await page.waitForSelector('flutter-view', {timeout: 60000});
  await page.waitForSelector('flt-semantics-placeholder', {timeout: 60000});
  await page.$eval('flt-semantics-placeholder', node => node.click());
}
console.log(JSON.stringify({ready: mode, browser: await browser.version()}));

function cpuTree() {
  const processes = new Map();
  for (const name of readdirSync('/proc').filter(x => /^\d+$/.test(x))) {
    try {
      const raw = readFileSync(`/proc/${name}/stat`, 'utf8');
      const fields = raw.slice(raw.lastIndexOf(')') + 2).split(' ');
      processes.set(Number(name), {parent: Number(fields[1]), ticks: Number(fields[11]) + Number(fields[12])});
    } catch {}
  }
  const descendants = new Set([browser.process().pid]);
  for (let changed = true; changed;) {
    changed = false;
    for (const [pid,p] of processes) if (descendants.has(p.parent) && !descendants.has(pid)) {descendants.add(pid); changed = true;}
  }
  return [...descendants].reduce((n,pid) => n + (processes.get(pid)?.ticks || 0), 0);
}
async function inspect() {
  return page.evaluate(() => ({
    fields: [...document.querySelectorAll('input,textarea')].map(n => ({tag:n.tagName, label:n.getAttribute('aria-label'), type:n.type})),
    buttons: [...document.querySelectorAll('[role=button]')].map(n => n.getAttribute('aria-label') || n.textContent).filter(Boolean).slice(0,40),
    text: document.querySelector('flt-semantics-host')?.textContent?.slice(0,1000),
  }));
}
async function click(text) {
  const success = await page.evaluate(text => {
    const node = [...document.querySelectorAll('[role=button]')].find(n => (n.getAttribute('aria-label') || n.textContent)?.trim() === text);
    if (!node) return false;
    node.click(); return true;
  }, text);
  if (!success) throw new Error('Button not found');
}
async function fill(label, value) {
  const node = await page.$(`input[aria-label=${JSON.stringify(label)}],textarea[aria-label=${JSON.stringify(label)}]`);
  if (!node) throw new Error('Field not found');
  await node.click();
  await page.keyboard.down('Control'); await page.keyboard.press('KeyA'); await page.keyboard.up('Control');
  await page.keyboard.type(value);
}
async function sample(scroll = false) {
  await page.bringToFront();
  const before = cpuTree(), start = performance.now();
  const frames = page.evaluate(() => new Promise(resolve => {
    const intervals = []; let previous; const started = performance.now();
    window.__perfLongTasks.length = 0;
    function frame(now) {
      if (previous != null) intervals.push(now - previous); previous = now;
      if (performance.now() - started < 6000) { requestAnimationFrame(frame); return; }
      intervals.sort((a,b) => a-b);
      resolve({frames: intervals.length, p50: intervals[Math.floor(intervals.length*.5)], p95: intervals[Math.floor(intervals.length*.95)], max: intervals.at(-1), longTasks: window.__perfLongTasks.length, longTaskMs: window.__perfLongTasks.reduce((a,b)=>a+b,0)});
    } requestAnimationFrame(frame);
  }));
  if (scroll) {
    const bounds = await page.evaluate(() => ({w: innerWidth,h:innerHeight}));
    await page.mouse.move(bounds.w/2,bounds.h/2);
    for (let i=0;i<20;i++) { await page.mouse.wheel({deltaY:i%2 ? -300 : 300}); await new Promise(r=>setTimeout(r,200)); }
  }
  const measured = await frames;
  const elapsed = performance.now()-start;
  return {...measured, elapsedMs: Math.round(elapsed), cpuPercentOneCore: Math.round((cpuTree()-before)*10/elapsed*100), sync: {...sync}, errors};
}
const lines = createInterface({input: process.stdin});
try {
  for await (const line of lines) {
    try {
      const command = JSON.parse(line);
      if (command.op === 'close') break;
      let result;
      if (command.op === 'inspect') result = await inspect();
      if (command.op === 'fill') { await fill(command.label, command.value); result = {filled: command.label}; }
      if (command.op === 'click') { await click(command.text); result = {clicked: command.text}; }
      if (command.op === 'login') {
        credentialsSubmitted = true;
        await fill('Username or Matrix ID', command.username);
        await fill('Password', command.password);
        await click('Sign in'); result = {submitted: true};
      }
      if (command.op === 'recover') { await fill('Recovery key or passphrase', command.key); await click('Recover & verify'); result = {submitted: true}; }
      if (command.op === 'sample') result = await sample(command.scroll);
      if (command.op === 'aggregateStart') {
        await page.evaluate(readFileSync(new URL('./web_runtime_probe.js', import.meta.url), 'utf8'));
        result = {started: true};
      }
      if (command.op === 'aggregateStop') result = await page.evaluate(() => window.__deltiecordPerformanceProbe?.stop());
      if (command.op === 'gpu') result = await page.evaluate(() => {
        const failures = [];
        function context(kind) {
          const canvas = document.createElement('canvas');
          canvas.addEventListener('webglcontextcreationerror', e => failures.push(e.statusMessage));
          return canvas.getContext(kind);
        }
        const gl2 = context('webgl2');
        const gl = gl2 || context('webgl');
        const ext = gl?.getExtension('WEBGL_debug_renderer_info');
        return {failures, webgl2: !!gl2, webgl:!!gl, renderer: ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl?.getParameter(gl.RENDERER), vendor: ext ? gl.getParameter(ext.UNMASKED_VENDOR_WEBGL) : gl?.getParameter(gl.VENDOR), dpr: devicePixelRatio, isolated: crossOriginIsolated, visibility: document.visibilityState};
      });
      if (command.op === 'startup') result = await page.evaluate(() => ({title:document.title,body:document.body.innerText.slice(0,600),flutterView:!!document.querySelector('flutter-view'),canvases:document.querySelectorAll('canvas').length}));
      if (command.op === 'support' && firefox) {
        const support = await browser.newPage();
        try {
          await support.goto('about:support', {waitUntil:'domcontentloaded',timeout:15000});
          result = await support.evaluate(() => document.getElementById('graphics-tbody')?.innerText || document.getElementById('graphics-info')?.innerText || [...document.querySelectorAll('table')].map(t=>t.id));
        } finally { await support.close(); await page.bringToFront(); }
      }
      if (command.op === 'cdp' && !firefox) {
        const session = await page.createCDPSession();
        await session.send('Performance.enable');
        const before = await session.send('Performance.getMetrics');
        const measured = await sample(command.scroll);
        const after = await session.send('Performance.getMetrics');
        result = {...measured, metrics: Object.fromEntries(after.metrics.filter(m=>['TaskDuration','ScriptDuration','LayoutDuration','RecalcStyleDuration','JSHeapUsedSize'].includes(m.name)).map(m=>[m.name, m.name==='JSHeapUsedSize' ? m.value : m.value - (before.metrics.find(b=>b.name===m.name)?.value||0)]))};
        await session.detach();
      }
      if (command.op === 'front') { await page.bringToFront(); result={front:true}; }
      if (command.op === 'buttons') result = await page.evaluate(() => [...document.querySelectorAll('[role=button]')].map(n=>n.getAttribute('aria-label') || n.textContent).filter(Boolean));
      if (command.op === 'viewport') { await page.setViewport({width:command.width,height:command.height, ...(process.env.PERF_DPR ? {deviceScaleFactor:Number(process.env.PERF_DPR)} : {})}); result = {resized:true}; }
      if (command.op === 'screenshot') { await page.screenshot({path: `/tmp/deltiecord-perf-${mode}.png`}); result = {saved:true}; }
      if (command.op === 'reload') { await page.reload(); await page.waitForSelector('flt-semantics-placeholder'); await page.$eval('flt-semantics-placeholder', node=>node.click()); result = {reloaded:true}; }
      console.log(JSON.stringify({op:command.op, result}));
      delete command.password; delete command.key; delete command.value;
    } catch { console.log(JSON.stringify({error:'Probe operation failed; no private details recorded'})); }
  }
} finally { lines.close(); process.stdin.pause(); await browser.close(); }
