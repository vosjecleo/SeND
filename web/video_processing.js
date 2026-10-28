/* Same-origin WebCodecs worker. Imported media never goes to a server. */
(() => {
  let active = null;
  const workerUrl = new URL('web-video/worker.js', document.currentScript.src);
  window.sendWebVideoSupported = () => !!(window.isSecureContext && window.Worker && window.VideoEncoder && window.VideoDecoder);
  window.sendWebVideoCancel = id => { if (active?.id === id) active.cancel(); };
  window.sendWebVideoProcess = (bytes, options, progress) => new Promise((resolve, reject) => {
    if (!window.sendWebVideoSupported()) return reject(new Error('This browser can\'t encode videos. Choose Original.'));
    if (active) return reject(new Error('Another video is being prepared.'));
    const worker = new Worker(workerUrl, {type: 'module'});
    let closed = false;
    const hidden = () => { if (document.hidden) finish(null, 'Video export stopped. Keep SeND open and try again.'); };
    const cleanup = () => { clearTimeout(timeout); document.removeEventListener('visibilitychange', hidden); worker.terminate(); if (active?.worker === worker) active = null; };
    const finish = (result, error) => { if (closed) return; closed = true; cleanup(); resolve(error ? {error} : result); };
    const timeout = setTimeout(() => finish(null, 'Export timed out. Choose Original or a shorter clip.'), 10 * 60 * 1000);
    active = {worker, id: options.jobId, cancel: () => finish(null, 'Video preparation canceled.')};
    document.addEventListener('visibilitychange', hidden);
    worker.onmessage = ({data}) => {
      if (typeof data.progress === 'number') { progress(data.progress); return; }
      if (data.error) finish(null, data.error); else if (data.result) finish(data.result);
    };
    worker.onerror = () => finish(null, 'Couldn\'t process the video. Retry or choose Original.');
    try { worker.postMessage({blob: new Blob([bytes]), options}); }
    catch (_) { finish(null, 'Couldn\'t process the video. Choose Original.'); }
  });
})();
