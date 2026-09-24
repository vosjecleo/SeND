// Exercise keyboard-close repair without requiring an iPhone or app account.
import vm from 'node:vm';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const events = {};
const viewportEvents = {};
let pending;
let repairs = 0;
const viewport = {height: 800, scale: 1, addEventListener: (name, fn) => viewportEvents[name] = fn};
const document = {body: {scrollTop: 150}, documentElement: {scrollTop: 150},
  addEventListener: (name, fn) => events[name] = fn};
const window = {visualViewport: viewport, addEventListener: (name, fn) => events[name] = fn,
  scrollTo: () => repairs++, dispatchEvent: () => {}};
vm.runInNewContext(fs.readFileSync('web/browser_bridge.js', 'utf8'), {
  window, document, navigator: {userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 5},
  setTimeout: fn => {pending = fn;}, clearTimeout: () => {}, Event: class {},
});
const resize = (height, scale = 1) => {
  viewport.height = height; viewport.scale = scale; viewportEvents.resize(); pending();
};
resize(480); // keyboard opens
assert.equal(repairs, 0);
resize(450); // accessory row / keyboard changes
assert.equal(repairs, 0);
resize(800); // keyboard dismisses
assert.equal(repairs, 1);
assert.equal(document.body.scrollTop, 0);
resize(800); // no perpetual repaint loop
assert.equal(repairs, 1);
resize(400, 2); // preserve pinch zoom
assert.equal(repairs, 1);
console.log('PASS: keyboard-close-only viewport repair; typing/zoom unaffected.');
