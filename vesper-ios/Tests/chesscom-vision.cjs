const assert = require('node:assert/strict');
const {Chess} = require('../Vendor/resources/chess-rules.js');
const profile = require('../Resources/chesscom-profile.js');
const vision = require('../Resources/chesscom-vision.js');
const coach = require('../Resources/CoachVision.js');

const labels = game => game.board().flat().map(piece =>
    !piece ? '.' : piece.color === 'w' ? piece.type.toUpperCase() : piece.type);

function screenshot(game, {flipped=false, cell=39, x=9, y=152, highlights=[]}={}) {
    const width = x + cell * 8 + 13;
    const height = y + cell * 8 + 190;
    const data = new Uint8Array(width * height * 4).fill(37);
    const board = flipped ? labels(game).reverse() : labels(game);
    for (let i=0; i<64; i++) {
        const col=i%8, row=i>>3;
        const background = highlights.includes(i) ? [133,167,182] : (col+row)%2?profile.dark:profile.light;
        const shape=profile.templates[board[i]]?.[0];
        for(let v=0;v<cell;v++) for(let u=0;u<cell;u++){
            const sx=Math.floor((u/cell-.12)*14/.76), sy=Math.floor((v/cell-.12)*14/.76);
            const tone=sx>=0&&sx<14&&sy>=0&&sy<14&&shape?shape[sy*14+sx]:'0';
            const color=tone==='1'?[5,5,5]:tone==='2'?[253,253,253]:background;
            const at=((y+row*cell+v)*width+x+col*cell+u)*4;
            data.set(color,at);
        }
    }
    return {width,height,data};
}

for (const flipped of [false,true]) {
    const game=new Chess();
    const observe=coach.create(Chess,profile,'w');
    const opened=screenshot(game,{flipped});
    assert.deepEqual(vision.readFrame(opened,profile).labels,flipped?labels(game).reverse():labels(game));
    assert.equal(observe(opened).status,'checking');
    assert.equal(observe(opened).moveLine,'');
    game.move('e4');
    game.move('e5');
    const after=screenshot(game,{flipped,cell:46,x:17,y:91,highlights:[12,28]});
    assert.equal(observe(after).status,'checking');
    assert.equal(observe(after).moveLine,'e2e4 e7e5');
    assert.equal(observe({...after,data:new Uint8Array(after.data.length)}).status,'uncertain');
    game.move('Nf3');
    const shifted=screenshot(game,{flipped,cell:41,x:6,y:117});
    assert.equal(observe(shifted).status,'checking');
    assert.equal(observe(shifted).ply,3);
    assert.equal(observe(shifted).moveLine,null);
}

const tracker=vision.track(Chess);
const reference=new Chess();
for(const move of ['e4','e5']) reference.move(move);
const strip={moves:['e2e4','e7e5','f2f4','e5f4'],selected:2};
assert.deepEqual(tracker.history(labels(reference),strip),{reviewing:true});
assert.equal(tracker.history(labels(new Chess()),strip),null);
assert.deepEqual(tracker.history(labels(reference),{moves:strip.moves.slice(0,2),selected:2}),
    {moves:['e2e4','e7e5'],reverse:false});
console.log('Automatic geometry, both orientations, highlights, skipped frame, resize, occlusion and history review passed.');
