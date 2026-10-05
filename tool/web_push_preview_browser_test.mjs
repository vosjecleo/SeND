// Real IndexedDB + WebCrypto + WASM inside an actual service worker. Only
// generated accounts/keys and a locally substituted encrypted event are used.
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const fixture = JSON.parse(execFileSync('cargo', ['+nightly-2026-09-23', 'run', '--quiet', '--locked',
  '--manifest-path', 'tool/push-crypto/Cargo.toml', '--example', 'fixture'], {encoding: 'utf8'}));
const event = {room_id: '!room:test', event_id: '$test', sender: '@friend:test', type: 'm.room.encrypted',
  content: {algorithm: 'm.megolm.v1.aes-sha2', session_id: fixture.id, sender_key: 'sender-key', ciphertext: fixture.ciphertext}};
const server = http.createServer(async (req, res) => {
  try {
    if (req.url === '/') {
      res.setHeader('Content-Type', 'text/html');
      res.end('<script src="/push_preview_store.js"></script>'); return;
    }
    if (req.url === '/test-sw.js') {
      res.setHeader('Content-Type', 'application/javascript');
      res.end(`importScripts('/push_preview_store.js', '/push-crypto/send_push_crypto.js', '/push_preview.js');
        const originalFetch = fetch;
        self.fetch = (url, options) => String(url).startsWith('https://matrix.example/')
          ? Promise.resolve(new Response(JSON.stringify(${JSON.stringify(event)}))) : originalFetch(url, options);
        self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
        self.addEventListener('message', e => e.waitUntil((async () => {
          const result = await sendPushPreview(e.data);
          e.ports[0].postMessage(result);
        })()));`); return;
    }
    const path = new URL(req.url, 'http://localhost').pathname;
    if (!['/push_preview_store.js', '/push_preview.js', '/push-crypto/send_push_crypto.js', '/push-crypto/send_push_crypto_bg.wasm'].includes(path)) {
      res.writeHead(404); res.end(); return;
    }
    res.setHeader('Content-Type', path.endsWith('.wasm') ? 'application/wasm' : 'application/javascript');
    let source = await fs.readFile('web' + path);
    if (path === '/push_preview.js') {
      // Test-only diagnostics, with generated data, never enabled in the app.
      source = source.toString().replace('} catch (_) { return null; }',
        '} catch (error) { console.error(error.stack); return null; }');
    }
    res.end(source);
  } catch (_) { res.writeHead(500); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await puppeteer.launch({executablePath: process.env.CHROME_EXECUTABLE || '/usr/bin/chromium',
  headless: true, args: ['--no-sandbox']});
try {
  browser.on('targetcreated', async target => {
    if (target.type() === 'service_worker') {
      const worker = await target.worker();
      worker?.on('console', message => console.error(message.text()));
    }
  });
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const result = await page.evaluate(async fixture => {
    const state = {owner: 'test-device', user: '@me:test', homeserver: 'https://matrix.example', token: 'fake-token',
      expires: Date.now() + 60000, rooms: ['!room:test'], sessions: [{room: '!room:test', id: fixture.id,
        sender: '@friend:test', senderKey: 'sender-key', key: fixture.key}]};
    await sendPushPreviewStore.write(state);
    const stored = await sendPushPreviewStore.read();
    if (stored.token !== 'fake-token') throw Error('Encrypted storage roundtrip failed');
    const reg = await navigator.serviceWorker.register('/test-sw.js');
    await navigator.serviceWorker.ready;
    const ask = () => new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => reject(Error('Worker timed out')), 10000);
      channel.port1.onmessage = e => {clearTimeout(timer); resolve(e.data);};
      reg.active.postMessage({room_id: '!room:test', event_id: '$test'}, [channel.port2]);
    });
    const preview = await ask();
    const duplicate = await ask();
    await sendPushPreviewStore.write(null);
    const afterLogout = await ask();
    const active = await sendPushPreviewStore.active(stored.generation);
    await sendPushPreviewStore.write({...state, expires: Date.now() - 1});
    const expired = await ask();
    await sendPushPreviewStore.write(null);
    return {preview, duplicate, afterLogout, active, expired};
  }, fixture);
  assert.equal(result.preview?.body, 'Hello from encrypted push');
  assert.equal(result.preview?.title, '@friend:test');
  assert.equal(result.duplicate, null);
  assert.equal(result.afterLogout, null);
  assert.equal(result.expired, null);
  assert.equal(result.active, false);
  console.log('Real service-worker decryption/storage/replay/logout/expiry test passed.');
} finally { await browser.close(); server.close(); }
