const CACHE = "bereia-shell-05675516-53244982c5d7d2bc";
const PATHS = ["/bereia-web-preview/index.html","/bereia-web-preview/assets/Account-BcFvvg12.js","/bereia-web-preview/assets/Bibles-5zxpwwcx.js","/bereia-web-preview/assets/Editor-Cf8l9Htb.css","/bereia-web-preview/assets/Editor-TOi190rx.js","/bereia-web-preview/assets/HymnsPage-CwUC3EXs.js","/bereia-web-preview/assets/HymnsPage-DhIwni0J.css","/bereia-web-preview/assets/LibraryPage-DtARWjYY.js","/bereia-web-preview/assets/ManuscriptCopies-_ybY8Mq2.js","/bereia-web-preview/assets/SearchPage-BY1WoSDU.js","/bereia-web-preview/assets/bookAI.worker-B0QgB4S4.js","/bereia-web-preview/assets/citations-Mop3s38h.js","/bereia-web-preview/assets/dist-DUv6x2D9.js","/bereia-web-preview/assets/dm-sans-latin-400-normal-BwCSEQnW.woff","/bereia-web-preview/assets/dm-sans-latin-400-normal-CW0RaeGs.woff2","/bereia-web-preview/assets/dm-sans-latin-500-normal-B9HHJjqV.woff2","/bereia-web-preview/assets/dm-sans-latin-500-normal-Dr3UlScf.woff","/bereia-web-preview/assets/dm-sans-latin-600-normal-Aqo67rzb.woff2","/bereia-web-preview/assets/dm-sans-latin-600-normal-BmdmIIQ2.woff","/bereia-web-preview/assets/index-DYT9bVKc.css","/bereia-web-preview/assets/index-r6ijU1Mr.js","/bereia-web-preview/assets/lib-BlydbgXm.js","/bereia-web-preview/assets/libre-caslon-display-latin-400-normal-BbfEE5V2.woff","/bereia-web-preview/assets/libre-caslon-display-latin-400-normal-n_DgBRfq.woff2","/bereia-web-preview/assets/mediaHash.worker-OQHa0dMZ.js","/bereia-web-preview/assets/ort-wasm-simd-threaded.jsep-B0T3yYHD.wasm","/bereia-web-preview/assets/ort-wasm-simd-threaded.jsep-B0TxsgQ-.mjs","/bereia-web-preview/assets/search-CaFXnlU_.js","/bereia-web-preview/assets/transformers.web-CeiwzlfN.js","/bereia-web-preview/assets/ui-BMylVIvG.js","/bereia-web-preview/assets/workHymns-DwTEm3jV.js"];
const BASE = "/bereia-web-preview/";
const CACHE_PREFIX = "bereia-shell-05675516-";
self.addEventListener("install", event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(PATHS))));
// No skipWaiting: a new version waits until the old windows have closed.
self.addEventListener("activate", event => event.waitUntil((async () => {
  for (const key of await caches.keys()) if (key.startsWith(CACHE_PREFIX) && key !== CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener("fetch", event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;
  if (request.mode === "navigate") {
    if (url.pathname !== BASE && url.pathname !== BASE + "index.html") return;
    event.respondWith((async () => {
      const cached = await (await caches.open(CACHE)).match(BASE + "index.html");
      return cached || fetch(request);
    })());
  } else if (!url.search && PATHS.includes(url.pathname)) {
    event.respondWith((async () => (await (await caches.open(CACHE)).match(url.pathname)) || fetch(request))());
  }
});
