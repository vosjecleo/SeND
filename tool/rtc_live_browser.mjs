const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const browser = await puppeteer.launch({executablePath: '/usr/bin/chromium',
  headless: true, args: ['--no-sandbox', '--use-fake-ui-for-media-stream',
    '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required']});
let stopping = false;
process.once('SIGTERM', () => {stopping = true;});
try {
  const page = await browser.newPage();
  await page.goto(process.argv[2], {waitUntil: 'domcontentloaded'});
  // The Dart probe performs cleanup before publishing its finished marker.
  const origin = new URL(process.argv[2]);
  const nonce = origin.searchParams.get('nonce');
  const deadline = Date.now() + 15 * 60 * 1000;
  while (!stopping && Date.now() < deadline) {
    try {
      const r = await fetch(`${origin.origin}/probe/stop?nonce=${nonce}`,
        {signal: AbortSignal.timeout(3000)});
      if ((await r.json()).stop) {
        // The parent waits for Dart cleanup before sending SIGTERM.
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    } catch {break;}
    await new Promise(resolve => setTimeout(resolve, 250));
  }
} finally {await browser.close();}
