import fs from 'node:fs/promises';
import http from 'node:http';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const server = http.createServer(async (req, res) => {
  if (req.url === '/') {
    res.setHeader('Content-Type', 'text/html');
    res.end('<script src="/vault.js"></script><script src="/benchmark.js"></script>');
    return;
  }
  const file = req.url === '/vault.js' ? 'web/local_vault.js' :
    req.url === '/benchmark.js' ? (process.env.BENCHMARK_SCRIPT || '.dart_tool/protected_web_storage_benchmark.js') : null;
  if (!file) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type', 'application/javascript');
  res.end(await fs.readFile(file));
});
await new Promise(resolve => server.listen(Number(process.env.PORT || 0), '127.0.0.1', resolve));
const remote = process.env.CHROME_REMOTE_URL;
const browser = remote ? await puppeteer.connect({browserURL: remote}) : await puppeteer.launch({executablePath: process.env.CHROME_EXECUTABLE || '/usr/bin/chromium', headless: true, args: ['--no-sandbox']});
let page;
try {
  page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.evaluate(() => new Promise((resolve, reject) => {
    const request = indexedDB.deleteDatabase('send-storage-benchmark');
    request.onsuccess = resolve; request.onerror = () => reject(request.error);
  }));
  if (process.env.CPU_THROTTLE) await page.emulateCPUThrottling(Number(process.env.CPU_THROTTLE));
  await page.evaluate(() => {
    const open = sendVaultOpen;
    window.benchmarkOpened = 0;
    window.benchmarkOpenedBytes = 0;
    window.sendVaultOpen = async (...args) => {
      window.benchmarkOpened++;
      const value = await open(...args);
      window.benchmarkOpenedBytes += JSON.stringify(value).length;
      return value;
    };
  });
  console.log(JSON.parse(await page.evaluate(count => sendStorageBenchmark(count), Number(process.env.ROWS || 10000))));
  console.log(await page.evaluate(() => ({decryptedRecords: benchmarkOpened, decryptedBytes: benchmarkOpenedBytes})));
  console.log({cpuThrottle: process.env.CPU_THROTTLE || 1});
} finally {
  if (remote) {
    if (page) {
      await page.evaluate(async () => {
        await new Promise((resolve, reject) => {
          const r = indexedDB.deleteDatabase('send-storage-benchmark');
          r.onsuccess = resolve; r.onerror = () => reject(r.error);
        });
        const db = await new Promise((resolve, reject) => {
          const r = indexedDB.open('send-local-vault-keys-v1');
          r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
        });
        const tx = db.transaction('keys', 'readwrite');
        tx.objectStore('keys').delete('matrix:send-storage-benchmark');
        await new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onabort = reject; });
        db.close();
      });
      await page.close();
    }
    browser.disconnect();
  } else { await browser.close(); }
  server.close();
}
