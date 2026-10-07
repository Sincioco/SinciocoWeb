'use strict';

// Ask EXISTING book registrations to check their retirement script. Never create
// registrations, force activation, reload tabs, or touch reader/browser storage.
(async () => {
  if (!('serviceWorker' in navigator) || location.protocol !== 'https:') return;
  const origins = new Set(['https://sincioco.com', 'https://sinstar.sincioco.com',
    'https://black-tree-0f54e0110.1.azurestaticapps.net']);
  if (!origins.has(location.origin)) return;
  const paths = new Set(['/BookOne/', '/sinstar/novel/']);
  try {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map(async (registration) => {
      const scope = new URL(registration.scope);
      if (scope.origin !== location.origin || !paths.has(scope.pathname) || scope.search || scope.hash) return;
      const expectedScript = new URL('sw.js', scope).href;
      const workers = [registration.active, registration.waiting, registration.installing].filter(Boolean);
      if (!workers.length || workers.some((worker) => worker.scriptURL !== expectedScript)) return;
      try { await registration.update(); } catch (_) { /* Offline: leave existing data and registration alone. */ }
    }));
  } catch (_) { /* Restricted storage: the direct full-reader link remains usable. */ }
})();
