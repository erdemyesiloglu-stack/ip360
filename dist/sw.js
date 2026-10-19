const CACHE = 'akis-shell-v5';
const SHELL = ['./', './index.html', './style.css', './app.js', './core.js', './storage.js', './icon.svg', './icon-192.png', './icon-512.png', './manifest.webmanifest'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('akis-shell-') && k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // Never cache provider traffic, credentials, streams or arbitrary URLs.
  const allowed = SHELL.map(p => new URL(p, self.registration.scope).href);
  if (e.request.method !== 'GET' || url.search || !allowed.includes(url.href)) return;
  e.respondWith(fetch(e.request).then(response => {
    if (response.ok && !response.redirected && response.headers.get('content-type')?.includes(url.pathname.endsWith('.js') ? 'javascript' : url.pathname.endsWith('.css') ? 'css' : url.pathname.endsWith('.svg') ? 'svg' : url.pathname.endsWith('.webmanifest') ? 'json' : 'html')) {
      const copy = response.clone(); caches.open(CACHE).then(cache => cache.put(e.request, copy));
    }
    return response;
  }).catch(() => caches.match(e.request).then(cached => cached || Response.error())));
});
