// Served as /flutter_service_worker.js (copied there by the build script).
//
// Earlier releases installed a caching service worker. Browsers that still
// have it keep showing an old copy of the app after a deploy. This worker
// replaces it: it takes over at once, deletes every cache the old one made,
// removes itself, and reloads the open tabs so they load the current build
// from the network. Browsers that never had the old worker never fetch this.
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      } catch (e) { /* nothing to clear */ }
      try {
        await self.registration.unregister();
      } catch (e) { /* already gone */ }
      const clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach(function (client) {
        try { client.navigate(client.url); } catch (e) { /* tab closed */ }
      });
    })()
  );
});
