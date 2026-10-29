(() => {
  const worker = new Worker('history_index_worker.js');
  let sequence = 0;
  const pending = new Map();
  worker.onmessage = ({data}) => {
    const job = pending.get(data.id); if (!job) return;
    pending.delete(data.id); clearTimeout(job.timer);
    if (data.error) job.reject(new Error('Local index operation failed'+(data.stage?' ('+data.stage+')':'')));
    else job.resolve(data.value);
  };
  worker.onerror = () => { for (const job of pending.values()) { clearTimeout(job.timer); job.reject(new Error('Local index unavailable')); } pending.clear(); };
  window.sendHistoryIndexCall = (account, op, args) => new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('Local index timed out')); }, 60000);
    pending.set(id, {resolve, reject, timer}); worker.postMessage({id, account, op, args});
  });
})();
