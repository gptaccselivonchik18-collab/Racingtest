const $=id=>document.getElementById(id);
const icons={sliders:'M4 7h5m5 0h6M4 17h10m4 0h2M10 4v6m6 4v6',plus:'M12 5v14M5 12h14',undo:'M8 6 3 11l5 5M4 11h10a6 6 0 0 1 6 6v1',flip:'M4 9a8 8 0 0 1 13-4l3 3m0-5v5h-5M20 15a8 8 0 0 1-13 4l-3-3m0 5v-5h5',spark:'m12 2 2.4 6.9L21 12l-6.6 2.7L12 22l-2.4-7.3L3 12l6.6-3.1Z',pulse:'M2 13h4l3-7 4 13 3-9 2 3h4',book:'M4 4h6a3 3 0 0 1 2 1 3 3 0 0 1 2-1h6v15h-6a3 3 0 0 0-2 1 3 3 0 0 0-2-1H4zM12 5v14',first:'M5 5v14m12-14-7 7 7 7',last:'M19 5v14M7 5l7 7-7 7',back:'m15 5-7 7 7 7',next:'m9 5 7 7-7 7',cpu:'M6 6h12v12H6zM9 2v3m6-3v3M9 19v3m6-3v3M2 9h3m-3 6h3m14-6h3m-3 6h3M9 9h6v6H9z',user:'M12 12a4 4 0 1 0-.01 0M4 21a8 8 0 0 1 16 0',x:'m6 6 12 12M18 6 6 18'};
const icon=name=>'<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="'+icons[name]+'"/></svg>';
document.querySelectorAll('[data-icon]').forEach(e=>e.outerHTML=icon(e.dataset.icon));
const names={p:'пешка',n:'конь',b:'слон',r:'ладья',q:'ферзь',k:'король'};
const enNames={p:'pawn',n:'knight',b:'bishop',r:'rook',q:'queen',k:'king'};
const pieceSvg=(color,type)=>'<svg class="piece" viewBox="0 0 45 45" aria-hidden="true"><use href="#'+(color==='w'?'white':'black')+'-'+enNames[type]+'"/></svg>';
const START=new Chess().fen(), storageKey='vesper-game-1';
const defaultCfg={human:'w',mode:'play',net:'full',threads:1,hash:32,variations:3,preset:1};
let cfg={...defaultCfg}, start=START, moves=[], cursor=0, flipped=false, conclusion='', game=new Chess(), keys=[], sans=[], fens=[];
let selected=null,hintSquares=[],busy=null,retryKind=null,notice='',manualPause=false,claimIntent=false,fullDead=null;
let offlinePreparation, matchClock=null;
const runner=new LocalEngine(), deadCache=new Map();let displayed={};
const posKey=g=>g.fen().split(' ').slice(0,4).join(' ');
const colorName=c=>c==='w'?'Белые':'Чёрные';
const plural=(n,a,b,c)=>n%10===1&&n%100!==11?a:n%10>=2&&n%10<=4&&(n%100<12||n%100>14)?b:c;
function restore(){
 try {
  const s=JSON.parse(localStorage.getItem(storageKey)||'null');if(!s)return;
  const replay=new Chess(s.start);for(const m of s.moves) replay.move(m);
  start=s.start;moves=s.moves;cfg={...defaultCfg,...s.cfg};flipped=!!s.flipped;conclusion=s.conclusion||'';
  delete cfg.seconds;
  cfg.preset=paceIndex(cfg.preset);
  matchClock=cfg.mode==='play'?MatchClock.restore(s.clock,moves.length):null;
  cursor=Math.max(0,Math.min(moves.length,Number.isInteger(s.cursor)?s.cursor:moves.length));
 }catch{start=START;moves=[];cursor=0;cfg={...defaultCfg};conclusion='';matchClock=null;}
}
let storageWarn=false;
function save(){try{localStorage.setItem(storageKey,JSON.stringify({start,moves,cursor,cfg,flipped,conclusion,clock:matchClock?.export()}));}catch{storageWarn=true;}}
function reindex(){
 const b=new Chess(start); keys=[posKey(b)];sans=[];fens=[b.fen()];
 for(const m of moves){sans.push(b.move(m).san);keys.push(posKey(b));fens.push(b.fen());}
 game=new Chess(fens[cursor]);
}
function fenDead(fen){
 if(!fullDead)return false;
 if(deadCache.has(fen))return deadCache.get(fen);
 const bytes=new TextEncoder().encode(fen);
 new Uint8Array(fullDead.memory.buffer,fullDead.input(),bytes.length).set(bytes);
 const dead=Boolean(fullDead.dead(bytes.length));deadCache.set(fen,dead);return dead;
}
function result(){
 if(game.isCheckmate()) return 'Мат. '+(game.turn()==='w'?'Чёрные победили':'Белые победили');
 if(game.isStalemate())return 'Ничья · пат';
 if(game.isInsufficientMaterial()||fenDead(game.fen()))return 'Ничья · мёртвая позиция';
 if(keys.slice(0,cursor+1).filter(k=>k===keys[cursor]).length>=5)return 'Ничья · пятикратное повторение';
 if(Number(fens[cursor].split(' ')[4])>=150)return 'Ничья · 75 ходов';
 return cursor===moves.length?conclusion:'';
}
function claimReason(b=game, intended=false){
 const count=keys.slice(0,cursor+1).filter(k=>k===posKey(b)).length+(intended?1:0);
 if(count>=3)return 'троекратное повторение';
 if(Number(b.fen().split(' ')[4])>=100)return '50 ходов';
 return '';
}
function prefixClaims(){return Number(game.fen().split(' ')[4])>=99||new Set(keys.slice(0,cursor+1)).size<cursor+1;}
function canClaimNext(){if(!prefixClaims())return false;for(const m of game.moves({verbose:true})){game.move(m.lan);const reason=claimReason(game,true);game.undo();if(reason)return true;}return false;}
function resetAnalysis(){
 displayed={};hintSquares=[];$('score').textContent='—';$('fill').style.width='50%';
 $('lines').textContent='Посмотрите лучшие продолжения в этой позиции.';$('depth').textContent='Глубина —';$('speed').textContent='— узлов/с';
}
function invalidate(){matchClock?.pause();runner.cancel();busy=null;retryKind=null;claimIntent=false;manualPause=false;notice='';selected=null;resetAnalysis();}
function drawBoard(){
 const files=flipped?'hgfedcba':'abcdefgh', ranks=flipped?'12345678':'87654321';
 const possible=selected?game.moves({square:selected,verbose:true}):[];
 const previous=cursor?moves[cursor-1]:'',check=game.isCheck();const fragment=document.createDocumentFragment();
 for(let y=0;y<8;y++)for(let x=0;x<8;x++){
  const square=files[x]+ranks[y],p=game.get(square),btn=document.createElement('button');
  btn.className='sq '+((x+y)%2?'dark':'light');btn.dataset.sq=square;
  btn.setAttribute('aria-label',square+(p?' '+colorName(p.color)+' '+names[p.type]:''));
  if([previous.slice(0,2),previous.slice(2,4)].includes(square))btn.classList.add('past');
  if(selected===square)btn.classList.add('sel');
  if(hintSquares.includes(square))btn.classList.add('hinted');
  if(check&&p?.type==='k'&&p.color===game.turn())btn.classList.add('check');
  btn.innerHTML=(p?pieceSvg(p.color,p.type):'')+(x===0?'<span class="coord rank">'+ranks[y]+'</span>':'')+(y===7?'<span class="coord file">'+files[x]+'</span>':'');
  if(possible.some(m=>m.to===square))btn.insertAdjacentHTML('beforeend','<span class="dot '+(p?'capture':'')+'"></span>');
  fragment.append(btn);
 }
 $('board').replaceChildren(fragment);
}
function displayPlayer(id,col,outcome){
 const human=cfg.mode==='study'||cfg.human===col, turn=col===game.turn();
 const userTitle=cfg.mode==='study'?colorName(col):human?'Вы':'Stockfish 19';
 const label=outcome?'Конец партии':!turn?'':cursor!==moves.length?'Ход позиции':busy==='move'?'Думает…':'Ход '+(col==='w'?'белых':'чёрных');
 const time=matchClock?'<time class="match-clock" id="match-'+col+'" aria-label="Время '+(col==='w'?'белых':'чёрных')+'"></time>':'';
 $(id).innerHTML='<span class="avatar">'+icon(human?'user':'cpu')+'</span><span class="person"><strong>'+userTitle+'</strong><small>'+(cfg.mode==='study'?'Разбор':colorName(col))+'</small></span>'+time+(label?'<span class="tag '+(turn&&!outcome?'active':'')+'">'+label+'</span>':'');
}
function drawHistory(){
 const history=$('history');history.replaceChildren();let row=null;
 for(let i=0;i<sans.length;i++){
  const [,side,,,,num]=fens[i].split(' ');
  if(side==='w'||!row){row=document.createElement('div');row.className='moveline';const n=document.createElement('span');n.textContent=num+(side==='b'?'…':'.');row.append(n);if(side==='b')row.append(document.createElement('i'));history.append(row);}
  const b=document.createElement('button');b.textContent=sans[i];b.dataset.ply=i+1;if(cursor===i+1)b.className='current';row.append(b);
 }
 if(!sans.length)history.innerHTML='<p class="empty">Первый ход появится здесь.</p>';
 $('count').textContent=moves.length+' '+plural(moves.length,'полуход','полухода','полуходов');
 $('cursor').textContent=cursor===0?'Начало':cursor+' / '+moves.length;
 $('first').disabled=$('prev').disabled=!cursor;$('last').disabled=$('next').disabled=cursor===moves.length;
 const cur=history.querySelector('.current');if(cur)history.scrollTop=Math.max(0,cur.parentElement.offsetTop-history.offsetTop-history.clientHeight/2);
}
function kind(){return cfg.net==='lite'?'lite':sharedThreads&&cfg.threads>1?'multi':'full';}
function kindLabel(){return 'Stockfish 19 '+(cfg.net==='lite'?'Lite':'Full');}
function activePace(){return paceModes[matchClock?.preset??cfg.preset];}
function paintClock(){
 if(!matchClock)return;
 const times=matchClock.read();
 for(const side of ['w','b']){
  const display=$('match-'+side);
  if(!display)continue;
  const value=clockText(times[side]);
  if(display.textContent!==value)display.textContent=value;
  display.classList.toggle('is-running',matchClock.running===side);
  display.classList.toggle('is-low',matchClock.running===side&&times[side]<10000);
 }
}
function clockExpired(){
 if(!matchClock||cursor!==moves.length||!matchClock.running)return false;
 const side=matchClock.running;
 if(matchClock.read()[side]>0)return false;
 invalidate();
 matchClock.flagged=side;
 matchClock.remaining[side]=0;
 const winner=side==='w'?'b':'w';
 const hasOtherPiece=game.board().some(rank=>rank.some(piece=>piece?.color===winner&&piece.type!=='k'));
 conclusion=hasOtherPiece?'Время вышло. '+(winner==='w'?'Белые победили.':'Чёрные победили.')
                         :'Ничья · время вышло, у соперника один король';
 save();render();
 return true;
}
function prepareMatchClock(){
 busy='warmup';retryKind=null;render();
 runner.run({kind:kind(),hash:cfg.hash,threads:cfg.threads,pv:1,warmup:true,
  progress:(loaded,total)=>{$('engineState').textContent='Подготовка движка · '+Math.floor(100*loaded/total)+'%';},
  status:message=>{$('engineState').textContent=message;},
  fail:message=>{busy=null;retryKind='warmup';notice=message;render();},
  done:()=>{busy=null;notice='';scheduleMove();}
 });
}
function mountPace(){
 const legend=matchClock?'Темп новой партии':cfg.mode==='study'?'Темп разбора':'Темп партии';
 $('pace-preference').innerHTML=paceSlider('page-pace',cfg.preset,legend);
 connectPaceSlider('page-pace',index=>{cfg.preset=index;save();if(!matchClock&&!busy)render();});
}
function render(){
 const outcome=result(),live=cursor===moves.length;
 if(outcome)matchClock?.pause();
 $('modeName').textContent=cfg.mode==='study'?'РАЗБОР ЗА ОБЕ СТОРОНЫ':'ПАРТИЯ С ДВИЖКОМ';
 displayPlayer('ptop',flipped?'w':'b',outcome);displayPlayer('pbottom',flipped?'b':'w',outcome);
 paintClock();
 drawBoard();drawHistory();
 $('engineName').textContent=kindLabel()+' · '+(kind()==='multi'?cfg.threads:1)+' '+plural(kind()==='multi'?cfg.threads:1,'поток','потока','потоков');
 if(!busy&&!retryKind){
  const pace=activePace();
  $('engineState').textContent='Хеш '+cfg.hash+' МБ · '+pace.name+(matchClock?' · '+pace.minutes+' мин':'');
 }
 $('retry').hidden=!retryKind;
 $('message').textContent=notice||outcome||(!live?'Просмотр истории. Вернитесь к последнему ходу, чтобы играть.':game.isCheck()?'Шах. Защитите короля.':storageWarn?'Хранилище недоступно. Сохраните PGN перед закрытием.':'');
 $('undo').disabled=!moves.length&&!conclusion;
 $('hint').disabled=!!outcome||!!busy||(!live&&cfg.mode==='play'?false:cfg.mode==='play'&&cfg.human!==game.turn());
 $('analyze').disabled=!!outcome||busy==='move'||busy==='warmup';
 $('analyze').querySelector('span').textContent=busy?'Остановить разбор':'Разобрать позицию';
 $('claim').hidden=!!outcome||!live||(cfg.mode==='play'&&game.turn()!==cfg.human)||!prefixClaims()||(!claimReason()&&!canClaimNext());
}
function finishMove(uci){
 if(clockExpired())return;
 const m=game.move(uci);matchClock?.played();moves.push(m.lan);cursor=moves.length;sans.push(m.san);keys.push(posKey(game));fens.push(game.fen());conclusion='';selected=null;hintSquares=[];claimIntent=false;notice='';retryKind=null;
 resetAnalysis();save();render();scheduleMove();
}
function maybeMove(m){
 if(clockExpired())return;
 if(claimIntent){game.move(m.lan);const reason=claimReason(game,true);game.undo();
  if(!reason){notice='Этот ход не даёт права на ничью. Выберите другой ход или отмените заявление.';selected=null;render();return;}
  conclusion='Ничья · '+reason+' (заявлен '+m.san+')';claimIntent=false;notice='';save();render();return;
 }
 if(busy)invalidate();finishMove(m.lan);
}
function squareClick(s){
 if(clockExpired()||cursor!==moves.length||result()||busy==='warmup'||(matchClock&&!matchClock.running)||busy==='move'||(cfg.mode==='play'&&game.turn()!==cfg.human))return;
 if(selected){const list=game.moves({square:selected,verbose:true}).filter(m=>m.to===s);
  if(list.length>1){openDlg('Превращение пешки','<div class="choice">'+list.map(m=>'<button data-prom="'+m.promotion+'" aria-label="'+names[m.promotion]+'">'+pieceSvg(game.turn(),m.promotion)+'</button>').join('')+'</div>');$('dlg').onclick=e=>{const p=e.target.closest('[data-prom]');if(p){closeDlg();maybeMove(list.find(m=>m.promotion===p.dataset.prom));}};return;}
  if(list.length){maybeMove(list[0]);return;}
 }
 const p=game.get(s);selected=p?.color===game.turn()&&selected!==s?s:null;drawBoard();
}
function showPV(line,side){
 const depth=line.match(/\bdepth (\d+)/),score=line.match(/\bscore (cp|mate) (-?\d+)/),pv=line.match(/\bpv (.+)$/);
 if(!score||!pv||!depth)return;const idx=+(line.match(/\bmultipv (\d+)/)?.[1]||1);
 const value=Number(score[2])*(side==='w'?1:-1),isMate=score[1]==='mate';
 const fmt=isMate?'M'+(value>0?'+':'')+value:(value>0?'+':'')+(value/100).toFixed(2);
 const b=new Chess(fens[cursor]),seq=[];
 for(const m of pv[1].split(' ').slice(0,8)){
  try{const [,side,,,,num]=b.fen().split(' ');const move=b.move(m);seq.push((side==='w'?num+'. ':!seq.length?num+'… ':'')+move.san);}catch{break;}
 }
 displayed[idx]={fmt,seq};$('lines').replaceChildren();
 Object.keys(displayed).sort((a,b)=>a-b).forEach(k=>{const p=document.createElement('div');p.className='pv';const b=document.createElement('b');b.textContent=displayed[k].fmt;const s=document.createElement('span');s.textContent=displayed[k].seq.join(' ');p.append(b,s);$('lines').append(p);});
 if(idx===1){$('score').textContent=fmt;$('fill').style.width=(isMate?(value>0?98:2):50+47*Math.tanh(value/380))+'%';$('depth').textContent='Глубина '+depth[1];const n=line.match(/\bnps (\d+)/);if(n)$('speed').textContent=Number(n[1]).toLocaleString('ru-RU')+' узлов/с';}
}
function analyze(type){
 if(busy||result()||clockExpired())return;
 const fen=fens[cursor],side=game.turn();busy=type;retryKind=null;notice='';resetAnalysis();render();
 const line='position '+(start===START?'startpos':'fen '+start)+(cursor?' moves '+moves.slice(0,cursor).join(' '):'');
 runner.run({kind:kind(),hash:cfg.hash,threads:cfg.threads,pv:type==='analysis'?cfg.variations:1,ms:activePace().analysisMs,position:line,
 timeControl:type==='move'&&matchClock?()=>engineTime(matchClock.read(),side):null,
 progress:(d,t)=>{const msg='Подготовка '+kindLabel()+' · '+Math.floor(100*d/t)+'%';$('message').textContent=msg;$('engineState').textContent=prettySize(d)+' / '+prettySize(t);},
 status:s=>{$('engineState').textContent=s;$('message').textContent=s;},
 info:s=>showPV(s,side),
 fail:msg=>{if(type==='move'){if(clockExpired())return;matchClock?.pause();}busy=null;retryKind=type;notice='Расчёт остановлен. '+msg+' Позиция сохранена.';$('engineState').textContent=msg;render();},
 done:uci=>{busy=null;if(fens[cursor]!==fen||(type==='move'&&clockExpired()))return;
  const m=game.moves({verbose:true}).find(m=>m.lan===uci);
  if(!m){retryKind=type;notice='Движок не вернул допустимый ход.';render();return;}
  if(type==='move'){game.move(m.lan);const reason=claimReason(game,true);game.undo();if(reason){conclusion='Ничья · '+reason+' (заявлен '+m.san+')';save();render();}else finishMove(m.lan);}
  else{if(type==='hint'){hintSquares=[m.from,m.to];notice='Подсказка: '+m.san+' ('+m.from+'–'+m.to+').';}render();}
 }});
}
function scheduleMove(){queueMicrotask(()=>{
 if(!fullDead||document.hidden||manualPause||busy||retryKind||cfg.mode!=='play'||cursor!==moves.length||result())return;
 if(matchClock){
  if(!runner.ready){prepareMatchClock();return;}
  if(!matchClock.running){matchClock.resume(game.turn());render();}
 }
 if(game.turn()===cfg.human)return;
 const draw=claimReason();if(draw){conclusion='Ничья · '+draw;render();save();return;}analyze('move');
});}
function navigate(n){if(clockExpired())return;invalidate();cursor=Math.max(0,Math.min(moves.length,n));game=new Chess(fens[cursor]);save();render();scheduleMove();}
function closeDlg(){if($('dialog').open)$('dialog').close();}
function openDlg(title,html){$('dlgTitle').textContent=title;$('dlg').onclick=null;$('dlg').innerHTML=html;if(!$('dialog').open)$('dialog').showModal();}
function field(id,label,options,selected){return '<label class="field">'+label+'<select id="'+id+'">'+options.map(([v,t])=>'<option value="'+v+'" '+(String(v)===String(selected)?'selected':'')+'>'+t+'</option>').join('')+'</select></label>';}
function newGame(){
 let preset=cfg.preset;
 openDlg('Новая партия',field('mode','Режим',[['play','Против движка'],['study','Разбор за обе стороны']],cfg.mode)+field('side','Ваш цвет',[['w','Белые'],['b','Чёрные'],['random','Случайный']],cfg.human)+paceSlider('new-pace',preset)+'<p class="help">Текущую партию можно сохранить в разделе «Позиция и PGN».</p><button class="primary wide" id="begin">Начать партию</button>');
 connectPaceSlider('new-pace',index=>{preset=index;});
 $('begin').onclick=()=>{const s=$('side').value;invalidate();cfg.mode=$('mode').value;cfg.human=s==='random'?(Math.random()<.5?'w':'b'):s;start=START;moves=[];cursor=0;flipped=cfg.human==='b';conclusion='';cfg.preset=preset;matchClock=cfg.mode==='play'?new MatchClock(preset):null;reindex();save();closeDlg();mountPace();render();scheduleMove();};
}
function settings(){
 const maxThreads=sharedThreads?Math.min(8,navigator.hardwareConcurrency||2):1;
 openDlg('Настройки',field('net','Нейросеть',[['full','Full · полная сеть'],['lite','Lite · быстрый запуск']],cfg.net)+field('hash','Память для хеш-таблицы',[16,32,64,128,256].map(n=>[n,n+' МБ']),cfg.hash)+field('threads','Потоки Full',Array.from({length:maxThreads},(_,i)=>[i+1,String(i+1)]),Math.min(maxThreads,cfg.threads))+(!sharedThreads?'<p class="help">Сейчас доступен один поток. Несколько потоков требуют изолированной вкладки.</p>':'')+field('vars','Варианты в разборе',[1,2,3,4,5].map(n=>[n,String(n)]),cfg.variations)+'<button class="primary wide" id="apply">Применить</button><hr><p class="help">'+(offlineFile?'Обе сети включены в этот файл.':'Откройте игру с экрана «Домой». Выбранная сеть сохранится автоматически, пока есть интернет.')+'</p>'+(!offlineFile?'<button class="soft wide" id="offline">Сохранить для офлайна</button><p id="offstate" class="help" role="status"></p>':''));
 const applyConfig=()=>{invalidate();cfg.net=$('net').value;cfg.hash=+$('hash').value;cfg.threads=+$('threads').value;cfg.variations=+$('vars').value;save();render();scheduleMove();};
 $('apply').onclick=()=>{applyConfig();closeDlg();prepareStandalone();};
 if($('offline')){$('offline').onclick=()=>prepareOffline($('net').value==='lite'?'lite':sharedThreads&&+$('threads').value>1?'multi':'full');}
}
function dataTools(){
 openDlg('Позиция и PGN','<label class="field">Позиция FEN<textarea id="fen" spellcheck="false"></textarea></label><div class="actions"><button id="import" class="soft">Открыть для разбора</button></div><p class="help">Открытие FEN начнёт новую партию с заданной позиции.</p><button id="pgn" class="primary wide">Сохранить партию PGN</button><p id="io" class="help"></p>');$('fen').value=game.fen();
 $('import').onclick=()=>{try{const b=new Chess($('fen').value.trim());const enemy=b.turn()==='w'?'b':'w';const enemyKing=b.findPiece({color:enemy,type:'k'})[0];if(enemyKing&&b.isAttacked(enemyKing,b.turn()))throw Error();invalidate();cfg.mode='study';matchClock=null;start=b.fen();moves=[];cursor=0;conclusion='';reindex();save();closeDlg();mountPace();render();}catch{$('io').textContent='Некорректная позиция FEN.';}};
 $('pgn').onclick=()=>{const b=new Chess(start);for(const m of moves)b.move(m);const saved=cursor;cursor=moves.length;const old=game;game=b;const out=result();const score=b.isCheckmate()?(b.turn()==='w'?'0-1':'1-0'):matchClock?.flagged&&out&&!out.startsWith('Ничья')?(matchClock.flagged==='w'?'0-1':'1-0'):out?'1/2-1/2':'*';cursor=saved;game=old;
 b.setHeader('Event','Vesper Gambit');b.setHeader('White',cfg.mode==='study'?'White':cfg.human==='w'?'Player':'Stockfish 19');b.setHeader('Black',cfg.mode==='study'?'Black':cfg.human==='b'?'Player':'Stockfish 19');b.setHeader('Result',score);
 const url=URL.createObjectURL(new Blob([b.pgn()],{type:'application/x-chess-pgn'}));const a=document.createElement('a');a.href=url;a.download='vesper-gambit.pgn';a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);};
}
const standaloneApp=matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
function showOfflineStatus(message){
 for(const element of [$('offlineStatus'),$('offstate')]){
  if(element){element.hidden=false;element.textContent=message;}
 }
}
function prepareOffline(k){
 if(offlinePreparation){
  if(offlinePreparation.kind!==k)offlinePreparation.promise.then(()=>prepareOffline(k));
  return;
 }
 const button=$('offline');
 if(button)button.disabled=true;
 const promise=(async()=>{
  try{
   if(!('serviceWorker' in navigator)||!window.caches)throw Error('Откройте игру в Safari.');
   const existing=await navigator.serviceWorker.getRegistration();
   const reg=existing?.active?existing:await navigator.serviceWorker.register('./sw.js');
   let timeout;
   try{
    await Promise.race([navigator.serviceWorker.ready,new Promise((_,reject)=>{
     timeout=setTimeout(()=>reject(Error('Проверьте соединение и повторите.')),30000);
    })]);
   }finally{clearTimeout(timeout);}
   if(!reg.active)throw Error('Автономная оболочка недоступна.');
   const spec=ENGINES[k],cache=await caches.open(assetCache),signal=new AbortController().signal;
   if(!(await Promise.all(spec.parts.map(p=>cache.match('./engine/'+p.id+'.bin')))).every(Boolean)){
    let done=0;
    showOfflineStatus('Сохранение для офлайна · '+prettySize(spec.size));
    for(const part of spec.parts){
     await readPart(part,cache,signal);
     done+=part.size;
     showOfflineStatus('Сохранение для офлайна · '+prettySize(done)+' / '+prettySize(spec.size));
    }
    for(const part of spec.parts){
     if(!await cache.match('./engine/'+part.id+'.bin'))throw Error('Недостаточно свободного места.');
    }
   }
   await navigator.storage?.persist?.().catch(()=>false);
   showOfflineStatus('Готово к офлайн-игре · '+(k==='lite'?'Lite':'Full'));
  }catch(error){showOfflineStatus('Автономная копия не завершена. '+error.message);}
  finally{offlinePreparation=null;if(button)button.disabled=false;}
 })();
 offlinePreparation={kind:k,promise};
}
function prepareStandalone(){
 if(!offlineFile&&standaloneApp)prepareOffline(kind());
}
$('board').onclick=e=>{const b=e.target.closest('[data-sq]');if(b)squareClick(b.dataset.sq);};
setupBoardPreview();
$('new').onclick=newGame;$('settings').onclick=settings;$('data').onclick=dataTools;$('close').onclick=closeDlg;
$('flip').onclick=()=>{flipped=!flipped;save();render();};
$('undo').onclick=()=>{invalidate();if(conclusion){conclusion='';}else{let n=cursor<moves.length?cursor:Math.max(0,moves.length-1);if(cfg.mode==='play'&&n>0&&fens[n].split(' ')[1]!==cfg.human)n--;moves=moves.slice(0,n);cursor=n;}matchClock?.rewind(moves.length);reindex();save();render();scheduleMove();};
$('history').onclick=e=>{const b=e.target.closest('[data-ply]');if(b)navigate(+b.dataset.ply);};$('first').onclick=()=>navigate(0);$('prev').onclick=()=>navigate(cursor-1);$('next').onclick=()=>navigate(cursor+1);$('last').onclick=()=>navigate(moves.length);
$('hint').onclick=()=>analyze('hint');$('analyze').onclick=()=>{if(busy){invalidate();render();}else analyze('analysis');};
$('retry').onclick=()=>{const type=retryKind;retryKind=null;if(type==='warmup'||(type==='move'&&matchClock))scheduleMove();else analyze(type||'move');};
$('claim').onclick=()=>{const now=claimReason();if(now){invalidate();conclusion='Ничья · '+now;matchClock?.pause();save();}else{claimIntent=!claimIntent;notice=claimIntent?'Укажите ход, которым заявляете ничью. Повторное нажатие отменит заявление.':'';}render();};
$('about').onclick=()=>openDlg('Vesper Gambit','<p>Локальная шахматная студия на Stockfish 19 с нейросетью NNUE. В игре используется одна основная линия. В разборе можно сравнить до пяти продолжений.</p><p class="help">Движок Stockfish и порт Stockfish.js распространяются по GPLv3. Правила ходов — chess.js (BSD-2-Clause), проверка мёртвых позиций — CHA-Solver (MIT). Фигуры — Colin M. L. Burnett, GPL.</p><p class="help">Встроены распознавание доказанных мёртвых позиций и правила заявляемых и автоматических ничьих. Редкие недоказанные мёртвые позиции могут остаться в игре.</p><p><a href="https://github.com/nmrugg/stockfish.js/tree/v19.0.1" target="_blank" rel="noopener">Исходники Stockfish.js 19.0.1</a></p><p><a href="./Vesper-source.zip" download>Исходный код и лицензии приложения</a></p>');
document.addEventListener('visibilitychange',()=>{if(document.hidden){clockExpired();matchClock?.pause();if(busy){invalidate();render();}else runner.cancel();save();}else scheduleMove();});
if(!offlineFile&&'serviceWorker' in navigator)navigator.serviceWorker.register('./sw.js').catch(()=>{});
restore();reindex();mountPace();render();prepareStandalone();
setInterval(()=>{if(!document.hidden&&!clockExpired())paintClock();},100);
try{const bytes=decode64(document.getElementById('deadwasm').textContent);fullDead=new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;render();scheduleMove();}catch(e){notice='Модуль проверки позиции не запустился. Откройте приложение в современном Safari.';render();}

function setupBoardPreview(){
 const button=$('board-preview');
 if(!HTMLCanvasElement.prototype.captureStream||typeof MediaRecorder==='undefined')return;
 const mimeType=['video/mp4','video/webm'].find(type=>MediaRecorder.isTypeSupported(type));
 if(!mimeType)return;
 const mode='picture-in-picture';
 const dialog=$('dialog');
 let generation=0,videoUrl;
 dialog.addEventListener('close',()=>{
  generation++;
  if(videoUrl){URL.revokeObjectURL(videoUrl);videoUrl=null;}
 });
 button.hidden=false;
 button.onclick=async()=>{
  const request=++generation;
  openDlg('Плавающий просмотр',
   '<video id="preview-video" aria-label="Видео текущей позиции" playsinline muted loop controls hidden style="width:100%;aspect-ratio:1;background:#331c2a;border-radius:9px"></video>'+
   '<p class="help" id="preview-status" role="status">Готовлю снимок позиции…</p>'+
   '<button class="primary wide" id="preview-float" hidden>Открыть поверх других приложений</button>');
  const video=$('preview-video'),status=$('preview-status'),float=$('preview-float');
  try{
   const image=new Image();
   image.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(boardPreviewSvg());
   await image.decode();
   if(request!==generation)return;
   const clip=await recordBoardPreview(image,mimeType);
   if(request!==generation)return;
   videoUrl=URL.createObjectURL(clip);
   video.addEventListener('error',()=>{status.textContent='Браузер не смог воспроизвести снимок.';});
   video.addEventListener('loadeddata',()=>{
    video.hidden=false;
    const supported=typeof video.webkitSupportsPresentationMode==='function'
     ?video.webkitSupportsPresentationMode(mode)
     :document.pictureInPictureEnabled&&typeof video.requestPictureInPicture==='function';
    float.hidden=!supported;
    status.textContent=supported
     ?'В окне будет снимок этой позиции. Для нового снимка откройте просмотр снова.'
     :'Если вы открыли игру с иконки, попробуйте открыть её в Safari.';
   },{once:true});
   video.src=videoUrl;
   float.onclick=()=>{
    video.play().catch(()=>{});
    try{
     if(typeof video.webkitSetPresentationMode==='function'){
      video.webkitSetPresentationMode(mode);
     }else{
      video.requestPictureInPicture().catch(()=>{status.textContent='Запустите видео и нажмите кнопку снова.';});
     }
    }catch{status.textContent='Запустите видео и нажмите кнопку снова.';}
   };
  }catch{
   if(request===generation)status.textContent='Не удалось подготовить видео позиции в этом браузере.';
  }
 };
}

function boardPreviewSvg(){
 const cells=Array.from($('board').children,(cell,index)=>{
  const x=index%8,y=Math.floor(index/8);
  const fill=getComputedStyle(cell).backgroundColor;
  const id=cell.querySelector('svg.piece use')?.getAttribute('href')?.slice(1);
  const figure=id?document.getElementById(id)?.cloneNode(true):null;
  figure?.removeAttribute('id');
  const square=cell.dataset.sq;
  return '<g transform="translate('+x*60+' '+y*60+')">'+
   '<rect width="60" height="60" fill="'+fill+'"/>'+
   (cell.classList.contains('past')?'<rect width="60" height="60" fill="#e9c850" opacity=".47"/>':'')+
   (figure?'<g transform="translate(4 4) scale(1.15)">'+figure.outerHTML+'</g>':'')+
   '<g fill="#331c2a" font-family="sans-serif" font-size="11" font-weight="bold">'+
   (x===0?'<text x="3" y="12">'+square[1]+'</text>':'')+
   (y===7?'<text x="50" y="57">'+square[0]+'</text>':'')+'</g></g>';
 });
 return '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="480" viewBox="0 0 480 480">'+cells.join('')+'</svg>';
}

function recordBoardPreview(image,mimeType){
 const canvas=document.createElement('canvas');
 canvas.width=canvas.height=480;
 const context=canvas.getContext('2d');
 if(!context)throw Error('Canvas unavailable');
 const draw=()=>context.drawImage(image,0,0,480,480);
 draw();
 const stream=canvas.captureStream(15);
 return new Promise((resolve,reject)=>{
  let paintTimer,stopTimer,deadline;
  const cleanup=()=>{
   clearInterval(paintTimer);clearTimeout(stopTimer);clearTimeout(deadline);
   for(const track of stream.getTracks())track.stop();
  };
  try{
   const recorder=new MediaRecorder(stream,{mimeType,videoBitsPerSecond:400000});
   const chunks=[];
   recorder.ondataavailable=event=>{if(event.data.size)chunks.push(event.data);};
   recorder.onerror=event=>{cleanup();reject(event.error);};
   recorder.onstop=()=>{
    cleanup();
    if(chunks.length)resolve(new Blob(chunks,{type:recorder.mimeType||mimeType}));
    else reject(Error('Empty video'));
   };
   recorder.start();
   paintTimer=setInterval(draw,65);
   stopTimer=setTimeout(()=>{if(recorder.state!=='inactive')recorder.stop();},1050);
   deadline=setTimeout(()=>{cleanup();reject(Error('Video encoding timed out'));},6000);
  }catch(error){cleanup();reject(error);}
 });
}
