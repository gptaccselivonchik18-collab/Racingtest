// Reads the horizontal Chess.com move strip below the checkerboard.
const moveStrip = (() => {
  const bitCounts = Array.from({length:4096}, (_, n) => n.toString(2).replace(/0/g,'').length);
  const glyphs = typeof moveGlyphs !== 'undefined' ? moveGlyphs : require('./MoveGlyphs.js');
  function parser(ink, right, top, bottom, [left, end]) {
      const samples = new Map();
      const scores = new Map();
      function sample(x0, x1) {
        const key = x0*right+x1;
        if (samples.has(key)) return samples.get(key);
        let minX=x1, maxX=x0-1, minY=bottom, maxY=top-1;
        for (let y=top; y<bottom; y++) for (let x=x0; x<x1; x++) {
          if (!ink[y*right+x]) continue;
          minX=Math.min(minX,x); maxX=Math.max(maxX,x);
          minY=Math.min(minY,y); maxY=Math.max(maxY,y);
        }
        const w=maxX-minX+1, h=maxY-minY+1;
        const shape = w > 0 && h > 0 ? {
          ratio:w/h, h,
          rows:Array.from({length:16}, (_, y) => {
            const offset=(minY+Math.floor((y+.5)*h/16))*right+minX;
            let row=0;
            for (let x=0; x<12; x++) row |= ink[offset+Math.floor((x+.5)*w/12)] << x;
            return row;
          })
        } : null;
        samples.set(key,shape);
        return shape;
      }
      function score(char, x0, x1) {
        const key=char+x0+':'+x1;
        if (scores.has(key)) return scores.get(key);
        const shape=sample(x0,x1);
        let best=Infinity;
        if (shape && (char === '.' || char === '-' || shape.h >= (bottom-top)*.25)) {
          for (const [ratio, rows] of glyphs[char] || []) {
            const proportions=Math.abs(Math.log(ratio/shape.ratio));
            if (proportions > .75) continue;
            const difference=rows.reduce((sum,row,i)=>sum+bitCounts[row^shape.rows[i]],0)/192;
            best=Math.min(best,difference+proportions*.14);
          }
        }
        scores.set(key,best);
        return best;
      }
      return text => {
        if (text.length * 2 > end-left+2) return Infinity;
        let state=new Map([[left,0]]);
        for (const char of text) {
          const next=new Map();
          for (const [offset, cost] of state) {
            for (let x=offset+1; x<=Math.min(end,offset+(bottom-top)*1.7+5); x++) {
              const value=score(char,offset,x);
              if (value > .34) continue;
              const total=cost+value;
              if (total < (next.get(x) ?? Infinity)) next.set(x,total);
            }
          }
          if (!next.size) return Infinity;
          state=next;
        }
        return (state.get(end) ?? Infinity)/text.length;
      };
    }

  function read(frame, grid, Chess, known = []) {
    const right = frame.width;
    const cell = grid.step;
    const start = Math.max(0, Math.floor(grid.y + 8.2 * cell));
    const end = Math.min(frame.height, Math.ceil(grid.y + 10.9 * cell));
    const left = Math.max(0, Math.round(grid.x + .8 * cell));
    const last = Math.min(right, Math.round(grid.x + 7.2 * cell));
    if (start >= end) return null;
    const ink = new Uint8Array(right * (end - start));
    const rows = [];
    const pixel = (x,y) => {
      const i = (y * right + x) * 4;
      return Math.max(frame.data[i],frame.data[i+1],frame.data[i+2]);
    };
    for (let y=start; y<end; y++) {
      let count=0;
      for (let x=left; x<last; x++) {
        const bright=pixel(x,y)>132;
        ink[(y-start)*right+x]=bright;
        count+=bright;
      }
      if (count>=4 && count<(last-left)*.6) rows.push(y-start);
    }
    for (let i=0; i<rows.length;) {
      const top=rows[i++];
      let bottom=top+1;
      while (i<rows.length && rows[i]<=bottom) bottom=rows[i++]+1;
      const height=bottom-top;
      if (height<5 || height>cell*.31) continue;
      const groups=[];
      for (let x=left; x<last; x++) {
        let marked=false;
        for (let y=top;y<bottom;y++) if (ink[y*right+x]) {marked=true;break;}
        if (!marked) continue;
        const group=groups.at(-1);
        if (group && x-group[1]<=Math.max(3,height*.65)) group[1]=x+1;
        else groups.push([x,x+1]);
      }
      if (groups.length<2) continue;
      const readers=groups.map(group=>parser(ink,right,top,bottom,group));
      let selected=-1;
      for (let index=0; index<groups.length; index++) {
        const [a,b]=groups[index];
        for (let y=bottom+1;y<Math.min(end-start,bottom+Math.max(4,height*.9));y++) {
          let line=0;
          for(let x=a;x<b;x++) if(pixel(x,start+y)>113) line++;
          if (line>Math.max(5,(b-a)*.8)) {selected=index;break;}
        }
      }
      const knownTurn=Math.floor(known.length/2)+1;
      const numbered=[...new Set([1,knownTurn-2,knownTurn-1,knownTurn])].filter(n=>n>0);
      for(let index=0;index<groups.length-1;index++){
        const number=numbered.find(n=>readers[index](n+'.')<.22);
        if (!number) continue;
        const game=new Chess();
        const moves=known.slice(0,(number-1)*2);
        for(const move of moves) game.move(move);
        let marker=-1, read=0, turn=number, needNumber=false;
        for(let token=index+1;token<groups.length;token++){
          const score=readers[token];
          if(needNumber){
            if(score((turn+1)+'.')>=.25) break;
            turn++;
            needNumber=false;
            continue;
          }
          const ranked=game.moves({verbose:true}).map(move=>({
            move, score:Math.min(score(move.san),score(move.san.replace(/[+#]$/,''))+.018)
          })).sort((a,b)=>a.score-b.score);
          const [best,next]=ranked;
          if(!best || best.score>.23 || next && next.score-best.score<.017 ||
            moves.length<known.length && known[moves.length]!==best.move.lan) break;
          game.move(best.move);
          moves.push(best.move.lan);
          needNumber=game.turn()==='w';
          read++;
          if(token===selected) marker=moves.length;
        }
        if(read>0 && moves.length>=known.length && (selected<0 || marker>=0))
          return {moves, selected:marker};
      }
    }
    return null;
  }
  return {read};
})();
if (typeof module !== 'undefined') module.exports = moveStrip;
