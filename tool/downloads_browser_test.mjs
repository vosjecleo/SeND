import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');

const files = {
  windows: [{name: 'SeND-0.9.42+134-windows-x64-setup.exe', size: 1048576}],
  linux: [{name: 'SeND-0.9.42+134-linux-appimage-x86_64.AppImage', size: 2097152}],
  android: [{name: 'SeND-0.9.42+134-android-arm64-v8a.apk', size: 3145728}],
};
const fixture = () => ({
  version: '0.9.42', build: 134, stable_version: '0.9.42', stable_build: 134,
  platforms: Object.fromEntries(Object.entries(files).map(([system, assets]) => [system, {latest: assets, stable: assets}])),
});
let manifest = fixture(), fail = false;
const server = http.createServer(async (req, res) => {
  const pathname = new URL(req.url, 'http://localhost').pathname;
  if (pathname === '/SeND/releases.json') {
    res.writeHead(fail ? 503 : 200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify(manifest));
  } else if (pathname === '/SeND/' || pathname === '/SeND/downloads.js') {
    const script = pathname.endsWith('.js');
    res.setHeader('Content-Type', script ? 'text/javascript' : 'text/html');
    res.end(await fs.readFile(`server/website/${script ? 'downloads.js' : 'index.html'}`));
  } else { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await puppeteer.launch({executablePath: process.env.CHROME_EXECUTABLE || '/usr/bin/chromium', headless: true, args: ['--no-sandbox']});
try {
  const page = await browser.newPage();
  const requests = []; page.on('request', req => requests.push(req.url()));
  async function open() { await page.goto(`${base}/SeND/`, {waitUntil: 'networkidle0'}); }
  await open();
  let labels = await page.$$eval('.download-body h3', elements => elements.map(e => e.textContent));
  assert.deepEqual(labels, Array(3).fill(['Stable: version 0.9.42 build 134', 'Latest: version 0.9.42 build 134']).flat());
  assert.equal(await page.$eval('#release-channels', e => e.innerText), 'Stable: version 0.9.42 build 134\nLatest: version 0.9.42 build 134');
  assert.equal((await page.$eval('.download-body a', e => e.href)), `${base}/SeND/SeND-0.9.42%2B134-windows-x64-setup.exe`);
  manifest.stable_version = '0.9.41'; manifest.stable_build = 132;
  await open();
  assert.equal(await page.$eval('.download-body h3', e => e.textContent), 'Stable: version 0.9.41 build 132');
  assert.match(await page.$eval('#release-channels', e => e.innerText), /Latest: version 0\.9\.42 build 134/);
  delete manifest.stable_version; delete manifest.stable_build;
  for (const platform of Object.values(manifest.platforms)) platform.stable = [];
  await open();
  assert.equal(await page.$eval('#release-channels span', e => e.textContent), 'Stable: not published yet');
  assert.equal((await page.$$('.download-body h3')).length, 3);
  manifest = fixture(); manifest.stable_version = '<img src=x onerror=alert(1)>';
  manifest.stable_build = -1;
  await open();
  assert.equal((await page.$$('#release-channels img')).length, 0);
  assert.equal(await page.$eval('.download-body h3', e => e.textContent), 'Stable');
  fail = true; await open();
  assert.equal(await page.$eval('#release-error', e => e.hidden), false);
  assert.equal(await page.$eval('#release-channels', e => e.textContent), 'Release versions unavailable.');
  assert(requests.every(url => url.startsWith(base)));
  console.log('Download page: both channels, independent versions, empty Stable, unsafe metadata and failed fetch passed. No external requests.');
} finally {
  await browser.close(); await new Promise(resolve => server.close(resolve));
}
