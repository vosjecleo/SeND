// Run as a DevTools Sources snippet on the affected page. This observes a
// 30-second window; it does not change Matrix state or read request bodies,
// storage, DOM content, credentials, or message data. Only aggregates are kept.
(() => {
  'use strict';
  const slot = '__deltiecordPerformanceProbe';
  window[slot]?.stop();
  const started = performance.now();
  const stats = {
    longTasks: {count: 0, totalMs: 0, maxMs: 0},
    frames: {count: 0, over34Ms: 0, over50Ms: 0, maxMs: 0},
    heartbeat: {count: 0, over50Ms: 0, maxDelayMs: 0},
    requests: {},
    support: {},
  };
  const observers = [];
  let previousFrame;
  let animation;
  let finished = false;
  let result;
  let hiddenDuringSample = document.visibilityState !== 'visible';
  const visibility = () => {
    hiddenDuringSample ||= document.visibilityState !== 'visible';
  };
  document.addEventListener('visibilitychange', visibility);

  function recordLongTasks(entries) {
    for (const entry of entries) {
      stats.longTasks.count++;
      stats.longTasks.totalMs += entry.duration;
      stats.longTasks.maxMs = Math.max(stats.longTasks.maxMs, entry.duration);
    }
  }

  function recordResources(entries) {
    for (const entry of entries) {
      // Classify paths in memory. Never retain/export URLs: Matrix paths and
      // query strings can contain account/room IDs or other private values.
      let path;
      try { path = new URL(entry.name, location.href).pathname; }
      catch { continue; }
      let kind = 'other';
      if (/\/_matrix\/client\/[^/]+\/sync$/.test(path)) kind = 'sync';
      else if (/\/_matrix\/client\/[^/]+\/room_keys\/keys(?:\/|$)/.test(path)) kind = 'backupKeys';
      else if (/\/_matrix\/client\/[^/]+\/room_keys\/version(?:\/|$)/.test(path)) kind = 'backupVersion';
      else if (/\/_matrix\/client\/[^/]+\/keys\//.test(path)) kind = 'deviceKeys';
      else if (/\/_matrix\/client\/[^/]+\/user\/[^/]+\/account_data\//.test(path)) kind = 'accountData';
      else if (/\/_matrix\/(?:media\/|client\/[^/]+\/media\/)/.test(path)) kind = 'media';
      const count = stats.requests[kind] ||= {count: 0, totalDurationMs: 0, maxDurationMs: 0};
      count.count++;
      count.totalDurationMs += entry.duration;
      count.maxDurationMs = Math.max(count.maxDurationMs, entry.duration);
    }
  }

  function observe(type, collect) {
    try {
      if (!PerformanceObserver.supportedEntryTypes.includes(type)) throw new Error();
      const observer = new PerformanceObserver(list => collect(list.getEntries()));
      observer.observe({type, buffered: false});
      observers.push({observer, collect});
      stats.support[type] = true;
    } catch { stats.support[type] = false; }
  }
  observe('longtask', recordLongTasks);
  observe('resource', recordResources);

  function frame(now) {
    if (previousFrame !== undefined) {
      const duration = now - previousFrame;
      stats.frames.count++;
      if (duration > 34) stats.frames.over34Ms++;
      if (duration > 50) stats.frames.over50Ms++;
      stats.frames.maxMs = Math.max(stats.frames.maxMs, duration);
    }
    previousFrame = now;
    animation = requestAnimationFrame(frame);
  }
  animation = requestAnimationFrame(frame);
  let lastBeat = performance.now();
  const heartbeat = setInterval(() => {
    const now = performance.now();
    const delay = Math.max(0, now - lastBeat - 100);
    stats.heartbeat.count++;
    if (delay > 50) stats.heartbeat.over50Ms++;
    stats.heartbeat.maxDelayMs = Math.max(stats.heartbeat.maxDelayMs, delay);
    lastBeat = now;
  }, 100);
  const deadline = setTimeout(stop, 30000);

  function stop() {
    if (finished) return result;
    finished = true;
    clearTimeout(deadline);
    clearInterval(heartbeat);
    cancelAnimationFrame(animation);
    document.removeEventListener('visibilitychange', visibility);
    for (const {observer, collect} of observers) {
      collect(observer.takeRecords());
      observer.disconnect();
    }
    // Snapshot rather than logging a live object that could mutate afterward.
    result = JSON.parse(JSON.stringify({
      elapsedMs: performance.now() - started,
      hiddenDuringSample,
      ...stats,
    }, (_key, value) => typeof value === 'number' ? Math.round(value) : value));
    console.log('Deltiecord aggregate performance sample', JSON.stringify(result));
    return result;
  }
  window[slot] = {stop};
  console.log('Deltiecord performance sampling started (30 seconds; aggregates only).');
})();
