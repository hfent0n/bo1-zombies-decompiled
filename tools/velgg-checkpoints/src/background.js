// vel.gg Checkpoints service worker: reads one of the extension's own files for content.js when the page's
// cross-origin rules (vel.gg sends COEP require-corp) stop content.js fetching it. Only paths under mod/ are served.
chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg?.type !== 'read-file' || typeof msg.path !== 'string' || !/^mod\/[a-z0-9_/.-]+$/.test(msg.path) || msg.path.includes('..')) return;
  if (!sender.url?.startsWith('https://vel.gg/')) return;
  fetch(chrome.runtime.getURL(msg.path))
    .then(response => { if (!response.ok) throw new Error('HTTP ' + response.status); return response.arrayBuffer(); })
    .then(buffer => {
      const bytes = new Uint8Array(buffer);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      reply({ base64: btoa(binary) });
    })
    .catch(error => reply({ error: String(error?.message ?? error) }));
  return true; // reply comes later
});
