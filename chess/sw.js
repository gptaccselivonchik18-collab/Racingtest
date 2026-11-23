const SHELL='vesper-chess-shell-68a89ea3eefb15';
const ROOT=new URL('./',self.location.href);
const shell=['index.html','engine/full.js','engine/lite.js','engine/multi.js','icon-192.png','icon-512.png','manifest.webmanifest'];
self.addEventListener('install',event=>event.waitUntil((async()=>{
 const cache=await caches.open(SHELL);
 for(const name of shell){
  const url=new URL(name,ROOT);
  const r=await fetch(new Request(url,{cache:'reload',credentials:'same-origin'}));
  if(!r.ok||r.redirected)throw Error('Offline shell unavailable');
  if(name==='index.html'&&!(await r.clone().text()).includes('vesper-game-1'))throw Error('Unexpected document');
  await cache.put(url,r);
 }
 await self.skipWaiting();
})()));
self.addEventListener('activate',e=>e.waitUntil((async()=>{
 for(const name of await caches.keys())if(name.startsWith('vesper-chess-shell-')&&name!==SHELL)await caches.delete(name);
 await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
 const req=event.request,url=new URL(req.url);if(req.method!=='GET'||url.origin!==ROOT.origin)return;
 const rel=url.pathname.slice(ROOT.pathname.length);
 if(!url.pathname.startsWith(ROOT.pathname)||!(shell.includes(rel)||rel===''))return;
 event.respondWith((async()=>{
  const key=rel||'index.html',c=await caches.open(SHELL);
  const r=await c.match(new URL(key,ROOT))||await fetch(req);
  const h=new Headers(r.headers);h.set('Cross-Origin-Opener-Policy','same-origin');h.set('Cross-Origin-Embedder-Policy','require-corp');h.set('Cross-Origin-Resource-Policy','same-origin');
  return new Response(r.body,{status:r.status,headers:h});
 })());
});
