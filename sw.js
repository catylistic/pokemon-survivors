// Pokémon Survivors offline support.
// The game itself is fetched fresh when you're online (so updates show up right away) and
// served from the cache when you're not. Sprites, Pokémon data and the font are cached as
// they're used. Leaderboard, cloud save and visit counts always go straight to the network.
const CORE = 'core-v1', ASSETS = 'assets-v1', MAX_ASSETS = 4000;
const CORE_FILES = ['./', 'index.html', 'three.module.min.js', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png'];
const ASSET_HOSTS = ['raw.githubusercontent.com', 'pokeapi.co', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CORE).then(c => c.addAll(CORE_FILES)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CORE && k !== ASSETS).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET') return;
  if (url.origin === location.origin) {
    // the page and its files: network first, cache as the fallback
    e.respondWith(fetch(req).then(r => {
      if (r.ok) { const copy = r.clone(); caches.open(CORE).then(c => c.put(req.mode === 'navigate' ? 'index.html' : req, copy)); }
      return r;
    }).catch(() => caches.match(req.mode === 'navigate' ? 'index.html' : req, { ignoreSearch: true })));
    return;
  }
  if (ASSET_HOSTS.includes(url.hostname)) e.respondWith(asset(req));
  // anything else (leaderboard, cloud save, stats) isn't touched
});

// sprites and data never change, so the cache wins; fetched in CORS mode so images
// from <img> tags are stored as normal (not opaque, quota-hungry) responses
async function asset(req) {
  const cache = await caches.open(ASSETS);
  const hit = await cache.match(req.url);
  if (hit) return hit;
  const r = await fetch(req.url, { mode: 'cors', credentials: 'omit' });
  if (r.ok) { await cache.put(req.url, r.clone()); trimSoon(cache); }
  return r;
}
let trimT = null;
function trimSoon(cache) {
  clearTimeout(trimT);
  trimT = setTimeout(async () => { const keys = await cache.keys(); for (const k of keys.slice(0, Math.max(0, keys.length - MAX_ASSETS))) await cache.delete(k); }, 5000);
}

// the page can ask for a list of sprites to be saved ahead of time (for offline play)
self.addEventListener('message', e => {
  if (!e.data || e.data.type !== 'prefetch') return;
  const port = e.ports[0], urls = e.data.urls.filter(u => ASSET_HOSTS.includes(new URL(u).hostname));
  e.waitUntil((async () => {
    const cache = await caches.open(ASSETS);
    let done = 0, failed = 0, i = 0;
    const worker = async () => {
      while (i < urls.length) {
        const u = urls[i++];
        try { if (!(await cache.match(u))) { const r = await fetch(u, { mode: 'cors', credentials: 'omit' }); if (r.ok) await cache.put(u, r); else failed++; } }
        catch { failed++; }
        if (++done % 10 === 0 || done === urls.length) port.postMessage({ done, total: urls.length, failed });
      }
    };
    await Promise.all([worker(), worker(), worker(), worker(), worker(), worker()]);
    port.postMessage({ done: urls.length, total: urls.length, failed, finished: true });
  })());
});
