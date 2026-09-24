// Run against tool/serve_web.py. All remote requests are intercepted; no real
// credentials, account creation, or third-party network traffic are involved.
import assert from 'node:assert/strict';
const {default: puppeteer} = await import(process.env.PUPPETEER_MODULE || 'puppeteer-core');
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_EXECUTABLE || '/usr/bin/chromium',
  headless: true, args: ['--no-sandbox'],
});
try {
  const page = await browser.newPage();
  await page.setViewport({width: 1100, height: 900});
  const logins = [];
  let registrations = 0;
  let leaked = false;
  await page.setRequestInterception(true);
  page.on('request', req => {
    const url = new URL(req.url());
    if (url.origin === 'http://127.0.0.1:8139') {
      if (req.method() === 'POST') leaked = true;
      return req.continue();
    }
    const headers = {'access-control-allow-origin': '*',
      'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS'};
    const respond = (status, body) => req.respond({status, headers,
      contentType: 'application/json', body: JSON.stringify(body)});
    if (req.method() === 'OPTIONS') return respond(204, {});
    if (url.pathname.endsWith('/versions')) return respond(200, {versions: ['v1.11']});
    if (url.pathname.endsWith('/login') && req.method() === 'GET') {
      return respond(200, {flows: [{type: 'm.login.password'}]});
    }
    if (url.pathname.endsWith('/login') && req.method() === 'POST') {
      logins.push(JSON.parse(req.postData()));
      return respond(403, {errcode: 'M_FORBIDDEN', error: 'Synthetic rejection'});
    }
    if (url.pathname.endsWith('/register')) registrations++;
    return respond(404, {});
  });
  await page.goto('http://127.0.0.1:8139/');
  await page.waitForSelector('#deltiecord-password', {visible: true, timeout: 60000});
  const attributes = await page.$eval('#deltiecord-login', form => ({
    method: form.method,
    user: form.querySelector('[name=username]').autocomplete,
    password: form.querySelector('[name=password]').autocomplete,
    type: form.querySelector('[name=password]').type,
    labelled: [...form.querySelectorAll('input')].every(n => n.labels.length === 1),
  }));
  assert.deepEqual(attributes, {method: 'post', user: 'username',
    password: 'current-password', type: 'password', labelled: true});
  const fill = (values) => page.evaluate(values => {
    for (const [id, value] of Object.entries(values)) {
      document.getElementById(`deltiecord-${id}`).value = value;
    }
  }, values);
  // Deliberately no input/change events: manager extensions may omit them.
  await fill({username: 'synthetic-autofill', password: 'not-a-real-password'});
  await page.click('#deltiecord-login button');
  for (let n = 0; n < 100 && !logins.length; n++) await new Promise(r => setTimeout(r, 100));
  assert.equal(logins[0]?.identifier?.user, 'synthetic-autofill');
  assert.equal(logins[0]?.password, 'not-a-real-password');
  await page.waitForFunction(() => !document.querySelector('#deltiecord-login button').disabled);
  await page.$eval('flt-semantics-placeholder', node => node.click());
  const toggle = await page.waitForSelector('::-p-text(Create a deltie.net account)');
  // Enabling Flutter semantics can relayout the platform-view form. Wait for
  // the semantic button geometry to settle before generating a pointer event.
  await new Promise(resolve => setTimeout(resolve, 500));
  console.log('Registration toggle geometry', await toggle.evaluate(node => {
    const r = node.getBoundingClientRect();
    return {x:r.x,y:r.y,width:r.width,height:r.height,
      hit:document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.outerHTML.slice(0,1000)};
  }));
  await toggle.click();
  try {
    await page.waitForFunction(() => document.querySelector('#deltiecord-password').autocomplete === 'new-password');
  } catch (error) {
    await page.screenshot({path:'web-autofill-failure.png'});
    console.log('Mode switch state', await page.evaluate(() => ({
      forms:document.querySelectorAll('#deltiecord-login').length,
      modes:[...document.querySelectorAll('#deltiecord-password')].map(n => n.autocomplete),
      buttons:[...document.querySelectorAll('[role=button]')].map(n=>({
        label:n.getAttribute('aria-label'),text:n.textContent,rect:n.getBoundingClientRect().toJSON(),
      })),
    })));
    throw error;
  }
  assert.equal(await page.$eval('#deltiecord-password', n => n.value), '');
  await fill({username: 'test', password: 'new-password', 'password-confirmation': 'wrong'});
  await page.click('#deltiecord-login button');
  assert.equal(await page.$eval('#deltiecord-password-confirmation', n => n.validity.customError), true);
  assert.equal(registrations, 0);
  // Correcting a previous validation error must permit a retry. Use an invalid
  // username to exercise revalidation without creating an account.
  await fill({username: 'Invalid name', 'password-confirmation': 'new-password'});
  await page.click('#deltiecord-login button');
  assert.equal(await page.$eval('#deltiecord-password-confirmation', n => n.validity.customError), false);
  assert.equal(await page.$eval('#deltiecord-username', n => n.validity.customError), true);
  assert.equal(registrations, 0);
  await (await page.waitForSelector('::-p-text(I already have an account)')).click();
  await page.waitForFunction(() => document.querySelector('#deltiecord-password').autocomplete === 'current-password');
  assert.equal(await page.$eval('#deltiecord-password', n => n.value), '');
  await page.setViewport({width: 390, height: 844});
  await page.waitForFunction(() => [...document.querySelectorAll('#deltiecord-login input')]
    .filter(n => !n.disabled).every(n => {
      const r = n.getBoundingClientRect(); return r.left >= 0 && r.right <= 390;
    }));
  assert.equal(leaked, false);
  console.log('PASS: browser autofill, Matrix handoff, retry, registration validation, mode reset, mobile layout, and no native HTTP submission.');
} finally {
  await browser.close();
}
