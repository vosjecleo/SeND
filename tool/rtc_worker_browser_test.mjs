import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import {execFileSync} from 'node:child_process';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');

execFileSync('dart', ['compile', 'js', 'tool/rtc_worker_probe.dart',
  '-o', '.dart_tool/rtc_worker_probe.js', '-m'], {stdio: 'pipe'});
const server = http.createServer(async (request, response) => {
  if (request.url === '/') {
    response.setHeader('Content-Type', 'text/html'); response.end('<!doctype html><title>RTC crypto fixture</title>');
  } else if (request.url === '/worker.js') {
    response.setHeader('Content-Type', 'application/javascript');
    response.end(await fs.readFile('.dart_tool/rtc_worker_probe.js'));
  } else { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await puppeteer.launch({executablePath: process.env.CHROME_EXECUTABLE || '/usr/bin/chromium',
  headless: true, args: ['--no-sandbox']});
try {
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const results = await page.evaluate(async () => {
    const worker = new Worker('/worker.js');
    const run = algorithm => new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(Error('RTC worker timed out')), 10000);
      worker.onmessage = event => {clearTimeout(timer); resolve(event.data);};
      worker.postMessage({algorithm});
    });
    try { return [await run(1), await run(0)]; }
    finally { worker.terminate(); }
  });
  const secret = Buffer.from(Array.from({length: 32}, (_, i) => i));
  const salt = Buffer.from('LKFrameEncryptionKey');
  const hkdf = Buffer.from(crypto.hkdfSync('sha256', secret, salt, Buffer.alloc(128), 16));
  // This is also the public vector observed in the real native m150 probe.
  assert.equal(hkdf.toString('hex'), '6d0dd7b3d6f4efde47ab9a9e15abde76');
  const pbkdf = crypto.pbkdf2Sync(secret, salt, 100000, 16, 'sha256');
  for (const [index, key] of [hkdf, pbkdf].entries()) {
    const cipher = crypto.createCipheriv('aes-128-gcm', key, Buffer.alloc(12));
    const expected = Buffer.concat([cipher.update('MatrixRTC interoperability'), cipher.final(), cipher.getAuthTag()]);
    assert.equal(results[index].error, undefined);
    assert.equal(results[index].index, 255);
    assert.equal(results[index].algorithm, index === 0 ? 'HKDF' : 'PBKDF2');
    assert.equal(results[index].cipher, expected.toString('hex'));
  }
  console.log('RTC worker HKDF/native public vector, PBKDF2 compatibility and key index 255 passed.');
} finally { await browser.close(); server.close(); }
