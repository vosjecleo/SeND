/* Browser-only capabilities; Matrix tokens and decrypted room state stay in Dart. */
(() => {
  'use strict';
  let releaseLock;
  let pushkey;
  let heartbeatTimer;
  // iOS can leave the layout viewport panned after dismissing its keyboard,
  // while Flutter still paints in layout-viewport coordinates. Restore only
  // after the keyboard closes, never while typing or pinch-zooming.
  const viewport = window.visualViewport;
  const appleTouch = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (appleTouch && viewport) {
    let baseline = viewport.height;
    let keyboardOpen = false;
    let repairTimer;
    const repairViewport = () => {
      clearTimeout(repairTimer);
      repairTimer = setTimeout(() => {
        if (Math.abs(viewport.scale - 1) > 0.01) return;
        baseline = Math.max(baseline, viewport.height);
        const open = baseline - viewport.height > 100;
        const closed = keyboardOpen && !open;
        keyboardOpen = open;
        if (closed) {
          window.scrollTo(0, 0);
          document.documentElement.scrollTop = 0;
          if (document.body) document.body.scrollTop = 0;
          window.dispatchEvent(new Event('resize'));
        }
      }, 120);
    };
    viewport.addEventListener('resize', repairViewport);
    viewport.addEventListener('scroll', repairViewport);
    document.addEventListener('focusout', repairViewport);
    window.addEventListener('orientationchange', () => {
      baseline = 0;
      keyboardOpen = false;
      repairViewport();
    });
  }
  window.deltieFetchMedia = async (url, token, maximum) => {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 30000);
    try {
      const response = await fetch(url, {signal: abort.signal, redirect: 'error',
        credentials: 'omit', referrerPolicy: 'no-referrer',
        headers: token ? {Authorization: 'Bearer ' + token} : {}});
      if (!response.ok || Number(response.headers.get('Content-Length')) > maximum || !response.body) {
        throw new Error('Media is unavailable or exceeds the browser playback limit.');
      }
      const reader = response.body.getReader();
      const chunks = [];
      let length = 0;
      while (true) {
        const {value, done} = await reader.read();
        if (done) break;
        length += value.length;
        if (length > maximum) { await reader.cancel(); throw new Error('Media exceeds the browser playback limit.'); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      return bytes;
    } finally { clearTimeout(timer); abort.abort(); }
  };
  const heartbeat = () => {
    if (!pushkey) return;
    fetch('/api/push/visibility', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({pushkey, visible: document.visibilityState === 'visible'}),
      keepalive: true, cache: 'no-store',
    }).catch(() => {});
  };
  window.deltiePushLease = key => {
    pushkey = key;
    clearInterval(heartbeatTimer);
    if (key) heartbeatTimer = setInterval(heartbeat, 30000);
    heartbeat();
  };
  document.addEventListener('visibilitychange', heartbeat);
  window.deltieBrowserStart = async () => {
    if (!window.isSecureContext || !navigator.locks) return false;
    const acquired = new Promise(resolve => {
      navigator.locks.request('deltiecord-matrix-session', {ifAvailable: true}, lock => {
        resolve(!!lock);
        return lock ? new Promise(release => { releaseLock = release; }) : undefined;
      }).catch(() => resolve(false));
    });
    if (!(await acquired)) return false;
    // Best effort: the browser may decline persistent storage. The SDK still
    // uses IndexedDB; users must retain their Matrix recovery key independently.
    navigator.storage?.persist?.().catch(() => {});
    await navigator.serviceWorker.register('/sw.js', {scope: '/'});
    return true;
  };
  // bfcache restoration must reload before opening another IndexedDB writer.
  window.addEventListener('pagehide', () => releaseLock?.());
  window.addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
  window.deltieSubscribePush = async () => {
    // Call this directly from a button; Safari requires user activation.
    if (!('Notification' in window) || !('PushManager' in window)) {
      throw new Error('Install Deltiecord to your Home Screen to enable notifications on supported iOS versions.');
    }
    if (await Notification.requestPermission() !== 'granted') {
      throw new Error('Notification permission was not granted.');
    }
    const response = await fetch('/api/push/config', {cache: 'no-store'});
    if (!response.ok) throw new Error('Push service unavailable.');
    const config = await response.json();
    const raw = atob(config.public_key.replace(/-/g, '+').replace(/_/g, '/'));
    const key = Uint8Array.from(raw, c => c.charCodeAt(0));
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription() ||
      await registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: key});
    return JSON.stringify(subscription.toJSON());
  };
  window.deltieClearNotifications = async roomId => {
    const registration = await navigator.serviceWorker.ready;
    if (!registration.getNotifications) return;
    for (const notification of await registration.getNotifications()) {
      if (!roomId || notification.data?.room_id === roomId) notification.close();
    }
  };
  window.deltieDisablePush = async () => {
    const oldKey = pushkey;
    window.deltiePushLease('');
    try {
      if (oldKey) await fetch('/api/push/unsubscribe', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({pushkey: oldKey}), keepalive: true,
      });
    } finally {
      // Network failure must not retain a working subscription after logout.
      const registration = await navigator.serviceWorker.ready;
      if (registration.pushManager) await (await registration.pushManager.getSubscription())?.unsubscribe();
      await window.deltieClearNotifications('');
    }
  };
})();
