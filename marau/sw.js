/* Service worker for the trip page. It lives at /roadbook/marau/sw.js, so it only controls that folder.

   Two caches, with names of their own so they do not collide with the roadbook on the same domain:
   - SHELL: the page, the manifest, the icons, the libraries and the fonts. Its name carries the
     version; when publishing a change, bump VERSION and the old cache is deleted on activation.
   - MAP: OpenFreeMap style, tiles, labels and icons. No version, so the downloaded map survives
     page updates. */

const VERSION = "v8";
const SHELL = "marau-shell-" + VERSION;
const MAP = "marau-map";

const PRECACHE = [
  "./",
  "manifest.webmanifest", "icon-192.png", "icon-512.png", "icon-maskable-512.png", "icon-180.png",
  "https://cdn.jsdelivr.net/npm/maplibre-gl@4.7.1/dist/maplibre-gl.js",
  "https://cdn.jsdelivr.net/npm/maplibre-gl@4.7.1/dist/maplibre-gl.css",
  "https://fonts.googleapis.com/css2?family=Archivo+Narrow:wght@500;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap"
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL);
    /* One by one: if the CDN fails on one item, the rest is still stored */
    await Promise.all(PRECACHE.map((url) =>
      fetch(url, { cache: "reload" })
        .then((r) => r.ok ? cache.put(url, r) : null)
        .catch(() => null)
    ));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    /* Drops every cache of this page that is not current: older shells and caches left by
       earlier names. Matching on "marau" keeps the roadbook's caches on this domain untouched. */
    const names = await caches.keys();
    await Promise.all(names
      .filter((n) => n.includes("marau") && n !== SHELL && n !== MAP)
      .map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

/* Network first, with a short timeout: a weak signal must not stall opening the page */
async function networkFirst(request, cacheName, timeoutMs) {
  const cache = await caches.open(cacheName);
  try {
    const response = await Promise.race([
      fetch(request),
      new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), timeoutMs))
    ]);
    if (response.ok) cache.put(new URL("./", self.registration.scope).href, response.clone());
    return response;
  } catch (e) {
    const cached = await cache.match(request, { ignoreSearch: true }) ||
                   await cache.match(new URL("./", self.registration.scope).href);
    if (cached) return cached;
    throw e;
  }
}

/* Cache first: what does not change, or must stay consistent with the map already downloaded */
async function cacheFirst(request, cacheName) {
  /* Looks in every cache of the page: the fonts may have come through the download button */
  const cached = await caches.match(request, { ignoreVary: true });
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok || response.type === "opaque") (await caches.open(cacheName)).put(request, response.clone());
  return response;
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);

  if (request.mode === "navigate" && url.href.startsWith(self.registration.scope)) {
    event.respondWith(networkFirst(request, SHELL, 4000));
    return;
  }
  /* The folder's manifest and icons: served from the version cache, so the installed app opens without signal */
  if (url.href.startsWith(self.registration.scope)) {
    event.respondWith(cacheFirst(request, SHELL));
    return;
  }
  /* Style, tilejson, tiles, labels and icons: all from the same place and the same version,
     so the offline map never asks for tiles from a version that was not downloaded */
  if (url.hostname === "tiles.openfreemap.org") {
    event.respondWith(cacheFirst(request, MAP));
    return;
  }
  if (url.hostname === "cdn.jsdelivr.net" || url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
    event.respondWith(cacheFirst(request, SHELL));
    return;
  }
  /* OSRM and the rest pass straight through: the page handles the lack of signal */
});
