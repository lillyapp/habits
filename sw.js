// =====================================================
// Service Worker – Consistency / Habits PWA
// =====================================================

// -----------------------------------------------------
// Cache Setup
// -----------------------------------------------------
const CACHE_NAME = "consistency-cache-v1";

const ASSETS = [
  "/habits/",
  "/habits/index.html",
  "/habits/manifest.json",
  "/habits/image.png"
];

// -----------------------------------------------------
// Install
// -----------------------------------------------------
self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

// -----------------------------------------------------
// Activate
// -----------------------------------------------------
self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

// -----------------------------------------------------
// Message (skipWaiting)
// -----------------------------------------------------
self.addEventListener("message", event => {
  if (event.data?.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

// -----------------------------------------------------
// PUSH EVENT
// -----------------------------------------------------
self.addEventListener("push", event => {
  let data = {};

  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = {};
  }

  const title = data.title || "Hinweis";
  const body  = data.body  || "";

  const options = {
    body,
    icon: "/habits/image.png",
    badge: "/habits/image.png",
    data: {
      url: data.url || "/habits/",
      type: data.type || "generic"
    }
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

// -----------------------------------------------------
// NOTIFICATION CLICK
// -----------------------------------------------------
self.addEventListener("notificationclick", event => {
  event.notification.close();

  const targetUrl = event.notification.data?.url || "/habits/";

  event.waitUntil(
    clients.matchAll({
      type: "window",
      includeUncontrolled: true
    }).then(clientList => {
      for (const client of clientList) {
        if (client.url.includes("/habits/")) {
          return client.focus();
        }
      }
      return clients.openWindow(targetUrl);
    })
  );
});

// -----------------------------------------------------
// FETCH STRATEGY
// - Network-first for HTML / navigation
// - Cache-first for static assets
// -----------------------------------------------------
self.addEventListener("fetch", event => {
  const req = event.request;
  const url = new URL(req.url);

  // Network-first for HTML
  if (
    req.mode === "navigate" ||
    (req.method === "GET" &&
      req.headers.get("accept")?.includes("text/html"))
  ) {
    event.respondWith((async () => {
      try {
        const networkResp = await fetch(req);
        const cache = await caches.open(CACHE_NAME);
        cache.put(req, networkResp.clone());
        return networkResp;
      } catch {
        const cached = await caches.match(req);
        return cached || new Response("Offline", { status: 503 });
      }
    })());
    return;
  }

  // Cache-first for other assets
  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;

      return fetch(req).then(networkResp => {
        if (
          req.method === "GET" &&
          url.origin === location.origin &&
          /\.(js|css|png|jpg|svg|json)$/.test(url.pathname)
        ) {
          caches.open(CACHE_NAME).then(cache =>
            cache.put(req, networkResp.clone())
          );
        }
        return networkResp;
      }).catch(() => caches.match("/habits/"));
    })
  );
});
