// Engine files and piece data are part of this distribution.
const ENGINES = /*MANIFEST*/;
const offlineFile = document.getElementById('standalone') !== null;
const assetCache = 'vesper-engine-v1';
const sharedThreads = !offlineFile && Boolean(ENGINES.multi) && window.crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined';
function decode64(text) {
  const s = atob(text.trim()), out = new Uint8Array(s.length);
  for (let i=0;i<s.length;i++) out[i]=s.charCodeAt(i);
  return out;
}
function prettySize(n) { return (n/1048576).toFixed(1).replace('.',',')+' МБ'; }
async function fetchTimed(path, signal, timeout = 25000) {
  const local = new AbortController();
  const stop = () => local.abort();
  signal?.throwIfAborted(); signal?.addEventListener('abort', stop, {once:true});
  const timer = setTimeout(stop,timeout);
  try {
    const response = await fetch(path,{signal:local.signal,credentials:'same-origin'});
    if (!response.ok) throw Error('HTTP '+response.status);
    return await response.arrayBuffer();
  } finally { clearTimeout(timer); signal?.removeEventListener('abort',stop); }
}
async function digest(buf) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',buf)),v=>v.toString(16).padStart(2,'0')).join('');
}
async function readPart(part,cache,signal) {
  if(offlineFile) return decode64(document.getElementById('part-'+part.id).textContent);
  const path='./engine/'+part.id+'.bin';
  if(cache) {
    const saved=await cache.match(path);
    if(saved) {
      const buf=await saved.arrayBuffer();
      if(buf.byteLength===part.size && await digest(buf)===part.id) return buf;
      await cache.delete(path);
    }
  }
  let failure;
  for(let attempt=0;attempt<2;attempt++) {
    signal.throwIfAborted();
    try {
      const buf=await fetchTimed(path,signal);
      if(buf.byteLength!==part.size || await digest(buf)!==part.id) throw Error('Неверный размер или контрольная сумма пакета');
      if(cache) {try{await cache.put(path,new Response(buf));}catch{ /* A full cache need not prevent play. */ }}
      return buf;
    } catch(e){failure=e;}
  }
  throw failure;
}
async function assemble(kind,signal,progress) {
  await offlinePreparation?.promise;
  signal.throwIfAborted();
  const spec=ENGINES[kind];let done=0,cache=null;
  if(!offlineFile && window.caches) {try{cache=await caches.open(assetCache)}catch{}}
  progress(0,spec.size);
  async function load(part){
    signal.throwIfAborted();const data=new Uint8Array(await readPart(part,cache,signal));done+=part.size;progress(done,spec.size);return data;
  }
  const first=await load(spec.parts[0]);
  if(kind==='lite')return offlineFile?first.buffer:new Blob([first],{type:'application/wasm'});
  const view=new DataView(first.buffer,first.byteOffset,first.byteLength);
  const out=new Uint8Array(view.getUint32(0,true)),count=view.getUint32(4,true),spans=[];
  let off=8,dest=0;
  for(let i=0;i<count;i++){
    const literal=view.getUint32(off,true),src=view.getUint32(off+4,true),length=view.getUint32(off+8,true);
    off+=12;out.set(first.subarray(off,off+literal),dest);off+=literal;dest+=literal;
    if(length)spans.push({src,dest,length});dest+=length;
  }
  let start=0;
  for(const part of spec.parts.slice(1)){
    const bytes=await load(part),end=start+bytes.length;
    for(const s of spans){
      const a=Math.max(start,s.src),b=Math.min(end,s.src+s.length);
      if(a<b)out.set(bytes.subarray(a-start,b-start),s.dest+a-s.src);
    }
    start=end;
  }
  signal.throwIfAborted();return offlineFile?out.buffer:new Blob([out],{type:'application/wasm'});
}
class LocalEngine {
  constructor(){this.generation=0;this.cancel();}
  cancel() {
    this.generation++;this.abort?.abort();this.worker?.terminate();this.worker=null;this.pending=null;
    clearTimeout(this.timer);this.kind=null;this.ready=false;this.options=new Map();
    for(const url of this.urls||[]) URL.revokeObjectURL(url);this.urls=[];
  }
  alarm(ms,callback){clearTimeout(this.timer);this.timer=setTimeout(callback,ms);}
  async run(job) {
    if(this.pending || (this.kind && this.kind!==job.kind)) this.cancel();
    this.pending=job;
    const generation=this.generation;
    const fail=e=>{
      if(generation!==this.generation)return;
      this.cancel();job.fail(e instanceof Error?e.message:String(e));
    };
    this.onFail=fail;
    const launch=()=>{
      const w=this.worker;this.phase='config';
      const options=[['Hash', job.hash],['Skill Level',20],['UCI_LimitStrength',false],['MultiPV',job.pv]];
      if(job.kind==='multi') options.unshift(['Threads',job.threads]);
      for(const [name,value] of options)if(this.options.get(name)!==value){
        w.postMessage('setoption name '+name+' value '+value);this.options.set(name,value);
      }
      w.postMessage('isready');
      this.alarm(20000,()=>fail('Нет подтверждения настроек. Повторите запуск или уменьшите хеш.'));
    };
    this.launch=launch;
    if(this.ready){launch();return;}
    this.kind=job.kind;this.abort=new AbortController();
    try {
      const binary=await assemble(job.kind,this.abort.signal,job.progress);
      if(generation!==this.generation)return;
      let wasm,glue;
      if(offlineFile){
        // A file: worker can have a distinct opaque origin in WebKit. Transfer the
        // ArrayBuffer directly, so no worker ever has to fetch a parent-owned blob URL.
        wasm='vesper:embedded';
        const prelude=`let receiveEngine;
const embedded=new Promise(resolve=>{receiveEngine=resolve;});
self.addEventListener('message',e=>{if(e.data?.vesperWasm){e.stopImmediatePropagation();receiveEngine(e.data.vesperWasm);}},true);
const originalFetch=self.fetch.bind(self);
self.fetch=(url,...options)=>String(url)==='vesper:embedded'?embedded.then(blob=>new Response(blob,{headers:{'Content-Type':'application/wasm'}})):originalFetch(url,...options);
self.addEventListener('unhandledrejection',e=>self.postMessage('vesper error '+String(e.reason)));
`;
        glue=URL.createObjectURL(new Blob([prelude,document.getElementById('glue-'+job.kind).textContent],{type:'text/javascript'}));this.urls.push(glue);
      }else{
        wasm=URL.createObjectURL(binary);this.urls.push(wasm);
        glue=new URL('./engine/'+job.kind+'.js',location.href).href;
      }
      const worker=new Worker(glue+'#'+encodeURIComponent(wasm));this.worker=worker;
      if(offlineFile)worker.postMessage({vesperWasm:binary},[binary]);
      this.phase='boot';job.status('Запуск нейросети…');
      worker.onerror=e=>this.onFail(new Error(e.message||'Браузер остановил движок.'));
      worker.onmessage=e=>this.receive(String(e.data));
      worker.postMessage('uci');this.alarm(35000,()=>fail('Движок не ответил. Повторите запуск или выберите Lite.'));
    }catch(e){fail(e);}
  }
  receive(line) {
    const job=this.pending;if(!job)return;
    if(line.startsWith('vesper error ')){this.onFail(new Error(line.slice(13)));return;}
    if(line==='uciok' && this.phase==='boot'){this.ready=true;this.launch();return;}
    if(line==='readyok' && this.phase==='config'){
      this.phase='search';this.worker.postMessage(job.position);
      this.worker.postMessage('go movetime '+job.ms);job.status('Расчёт…');
      this.alarm(job.ms+15000,()=>this.onFail(new Error('Расчёт прерван. Можно повторить позицию.')));return;
    }
    if(this.phase!=='search')return;
    if(line.startsWith('info depth ')){job.info(line);return;}
    if(line.startsWith('bestmove ')){
      clearTimeout(this.timer);this.pending=null;this.phase='idle';
      job.done(line.split(/\s+/)[1]);
    }
  }
}
