// No callback credentials are saved to localStorage, logs or the page body.
(() => {
  const callback = location.href;
  history.replaceState(null, '', location.pathname);
  const channel = new BroadcastChannel('deltiecord-auth');
  channel.postMessage(callback);
  setTimeout(() => { channel.close(); window.close(); }, 250);
})();
