// -----------------------------------------------------
// Cache Setup (optional)
// -----------------------------------------------------
const CACHE_NAME = "consistency-cache-v1";
const ASSETS = [
  "/habits/",
  "/habits/index.html",
  "/habits/manifest.json"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
});

// Clean up old caches and take control of clients on activation
self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

// Allow the page to tell the SW to activate immediately
self.addEventListener('message', event => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

// -----------------------------------------------------
// HANDLE PUSH EVENTS
// -----------------------------------------------------
self.addEventListener("push", event => {
  let data = {};

  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: "Hinweis", body: "" };
  }

  const title = data.title || "Hinweis";
  const body  = data.body  || "";

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      data: {
        url: "/habits/" // Ziel beim Tap
      }
    })
  );
});

// -----------------------------------------------------
// Notification Click → öffne App / fokussiere App
// -----------------------------------------------------
self.addEventListener("notificationclick", event => {
  event.notification.close();

  const targetUrl = event.notification.data?.url || "/habits/";

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true })
      .then(wins => {
        for (const win of wins) {
          if (win.url.includes("/habits/")) {
            return win.focus();
          }
        }
        return clients.openWindow(targetUrl);
      })
  );
});

// -----------------------------------------------------
// Fetch handler
// - Network-first for navigation/HTML (ensures index.html updates propagate)
// - Cache-first for other static assets
// -----------------------------------------------------
self.addEventListener("fetch", event => {
  const req = event.request;
  const url = new URL(req.url);

  // Network-first for navigations / HTML
  if (req.mode === 'navigate' || (req.method === 'GET' && req.headers.get('accept') && req.headers.get('accept').includes('text/html'))) {
    event.respondWith((async () => {
      try {
        const networkResponse = await fetch(req);
        const cache = await caches.open(CACHE_NAME);
        cache.put(req, networkResponse.clone());
        return networkResponse;
      } catch (err) {
        const cached = await caches.match(req);
        return cached || new Response('Offline', { status: 503, statusText: 'Service Unavailable' });
      }
    })());
    return;
  }

  // For other requests use cache-first, then network
  event.respondWith(
    caches.match(req).then(cached => cached || fetch(req).then(networkResp => {
      // Cache some same-origin static assets for offline use
      if (req.method === 'GET' && url.origin === location.origin && (ASSETS.includes(url.pathname) || /\.(js|css|png|jpg|svg|json)$/.test(url.pathname))) {
        caches.open(CACHE_NAME).then(cache => cache.put(req, networkResp.clone()));
      }
      return networkResp;
    }).catch(() => caches.match('/habits/')))
  );
});
self.addEventListener("push", event => {
  const data = event.data.json();

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "https://github.com/lillyapp/habits/blob/main/3FC2E555-7142-43BE-83DE-E5ED7A123793.png",
      badge: "https://github.com/lillyapp/habits/blob/main/3FC2E555-7142-43BE-83DE-E5ED7A123793.png"
    })
  );
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow("/")
  );
});
