'use strict';

// Retirement only. Keep this script at BOTH old same-origin script URLs.
// Do not skip waiting or claim clients: old tabs must finish with their existing
// worker, cached audio and Range implementation before this worker activates.
const script = new URL(self.location.href);
const scope = new URL(self.registration.scope);
const allowedOrigins = new Set([
  'https://sincioco.com',
  'https://sinstar.sincioco.com',
  'https://black-tree-0f54e0110.1.azurestaticapps.net'
]);
const allowedScopes = new Set(['/BookOne/', '/sinstar/novel/']);
if (scope.protocol !== 'https:' || scope.origin !== script.origin ||
    !allowedOrigins.has(scope.origin) || !allowedScopes.has(scope.pathname) || scope.search || scope.hash ||
    script.pathname !== scope.pathname + 'sw.js' || script.search || script.hash) {
  throw new Error('Book worker retirement refused outside the approved scope.');
}

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const shellPrefix = 'sin-star-shell-' + encodeURIComponent(scope.pathname) + '-';
    try {
      const names = await caches.keys();
      await Promise.all(names.filter((name) => name.startsWith(shellPrefix))
        .map((name) => caches.delete(name)));
    } finally {
      // Only this registration. Never clear audio, localStorage, IndexedDB,
      // unrelated caches, another path's registration, or another origin.
      await self.registration.unregister();
    }
  })());
});

// No fetch handler: after natural activation, subsequent requests use network.
