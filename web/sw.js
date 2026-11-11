// Service worker do Notemusic: faz o app abrir e funcionar SEM internet depois da primeira visita
// e cumpre o requisito de "app instalável" dos navegadores.
//
// Estratégia: rede primeiro, cache como reserva. Com internet o app é sempre a versão mais
// nova (e a checagem de versão do app continua valendo); sem internet usa o que ficou guardado.
// A API (/api/*) e o arquivo de versão nunca passam pelo cache.
'use strict';

const CACHE = 'notemusic-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const k of await caches.keys()) {
        if (k !== CACHE) await caches.delete(k);
      }
      await self.clients.claim();
    })(),
  );
});

function cacheable(url) {
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname;
  return !(p.startsWith('/api/') || p === '/build-id.txt' || p.endsWith('/sw.js'));
}

async function guardar(cache, req, res) {
  try {
    if (res && res.status === 200 && res.type === 'basic') await cache.put(req, res.clone());
  } catch (_) {
    /* sem espaço ou resposta parcial: ignora */
  }
}

async function redePrimeiro(req) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req);
    await guardar(cache, req, res);
    return res;
  } catch (err) {
    const hit =
      (await cache.match(req, { ignoreSearch: true })) ||
      (req.mode === 'navigate' ? (await cache.match('/')) || (await cache.match('/index.html')) : undefined);
    if (hit) return hit;
    throw err;
  }
}

// ---- Notificações de aula (Web Push) ----
// O servidor manda { kind: 'lesson', role, start, who } 15 min antes da aula; o texto é montado
// aqui, com a hora no fuso do aparelho.
self.addEventListener('push', (event) => {
  let d = {};
  try {
    d = event.data ? event.data.json() : {};
  } catch (_) {
    d = {};
  }
  // Aviso do administrador (bug grave): só texto curto vindo do nosso servidor.
  if (d.kind === 'admin') {
    const body = typeof d.body === 'string' ? d.body.slice(0, 140) : 'Há um aviso no painel.';
    event.waitUntil(
      self.registration.showNotification('Notemusic · painel', {
        body,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: `admin-${typeof d.tag === 'string' ? d.tag.slice(0, 20) : 'x'}`,
        data: { url: '/admin.html' },
      }),
    );
    return;
  }
  if (d.kind !== 'lesson' || !Number.isFinite(Number(d.start))) return;
  const hhmm = new Date(Number(d.start)).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  const who = typeof d.who === 'string' && d.who ? ` com ${d.who.slice(0, 40)}` : '';
  event.waitUntil(
    self.registration.showNotification('Aula em 15 minutos', {
      body: `Aula${who} às ${hhmm}`,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: `aula-${d.start}`, // a mesma aula não empilha avisos
      renotify: false,
      requireInteraction: false,
      data: { url: '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of all) {
        if ('focus' in c) return c.focus();
      }
      return self.clients.openWindow((event.notification.data && event.notification.data.url) || '/');
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (!cacheable(url)) return;
  event.respondWith(redePrimeiro(req));
});

// A página manda a lista de tudo o que já carregou; guardamos para o modo sem internet
// funcionar já na primeira vez (sem esperar uma segunda visita).
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (!Array.isArray(data.precache)) return;
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      for (const raw of data.precache) {
        try {
          const url = new URL(raw);
          if (!cacheable(url)) continue;
          if (await cache.match(url.href, { ignoreSearch: false })) continue;
          const res = await fetch(url.href);
          await guardar(cache, url.href, res);
        } catch (_) {
          /* esse arquivo fica para depois */
        }
      }
    })(),
  );
});
