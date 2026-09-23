import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('./web_runtime_probe.js', import.meta.url), 'utf8');
let now = 0;
let raf;
let beat;
let deadline;
let disconnected = 0;
const observers = [];
const output = [];
class Observer {
  static supportedEntryTypes = ['resource', 'longtask'];
  constructor(callback) { this.callback = callback; observers.push(this); }
  observe({type}) { this.type = type; }
  takeRecords() { return []; }
  disconnect() { disconnected++; }
}
const context = vm.createContext({
  window: {}, URL, PerformanceObserver: Observer,
  performance: {now: () => now},
  document: {visibilityState: 'visible', addEventListener() {}, removeEventListener() {}},
  location: {href: 'https://example.invalid/'},
  requestAnimationFrame: callback => { raf = callback; return 1; },
  cancelAnimationFrame() {},
  setInterval: callback => { beat = callback; return 2; },
  clearInterval() {},
  setTimeout: callback => { deadline = callback; return 3; },
  clearTimeout() {},
  console: {log: (...args) => output.push(args)},
});
vm.runInContext(source, context);
const resource = observers.find(observer => observer.type === 'resource');
resource.callback({getEntries: () => [{
  name: 'https://example.invalid/_matrix/client/v3/room_keys/keys/PRIVATE_ROOM?access_token=PRIVATE_TOKEN',
  duration: 240,
}]});
const longtask = observers.find(observer => observer.type === 'longtask');
longtask.callback({getEntries: () => [{duration: 200}]});
raf(0);
raf(200);
now = 500;
beat();
deadline();
const sample = context.window.__deltiecordPerformanceProbe.stop();
assert.equal(sample.requests.backupKeys.count, 1);
assert.equal(sample.frames.over50Ms, 1);
assert.equal(sample.heartbeat.maxDelayMs, 400);
assert.equal(sample.longTasks.maxMs, 200);
assert.equal(disconnected, 2);
assert.doesNotMatch(JSON.stringify(output), /PRIVATE_|example\.invalid/);
assert.equal(output.length, 2, 'stop must be idempotent');

Observer.supportedEntryTypes = ['resource'];
vm.runInContext(source, context);
const unsupported = context.window.__deltiecordPerformanceProbe.stop();
assert.equal(unsupported.support.longtask, false);
assert.equal(unsupported.support.resource, true);
console.log('web_runtime_probe: aggregate, privacy, cleanup and unsupported-API checks passed');
