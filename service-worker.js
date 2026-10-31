const CACHE='divinity-site-v3-save-recovery';
const ASSETS=['./','./index.html','./play.html','./guide.html','./privacy.html','./manifest.webmanifest','./favicon.svg'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',event=>{const req=event.request;if(req.method!=='GET'||new URL(req.url).origin!==self.location.origin)return;event.respondWith(fetch(req).then(resp=>{if(resp.ok){const copy=resp.clone();caches.open(CACHE).then(cache=>cache.put(req,copy)).catch(()=>{})}return resp}).catch(()=>caches.match(req).then(cached=>cached||caches.match('./index.html'))))});
