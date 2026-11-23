const chessComVision = (() => {
    const geometry = typeof screenGrid !== 'undefined' ? screenGrid : require('./ScreenGrid.js');
    const flatten = game => game.board().flatMap(rank => rank.map(piece =>
        piece ? (piece.color === 'w' ? piece.type.toUpperCase() : piece.type) : '.'));
    const arrangement = fen => fen.split(' ')[0].replace(/\//g,'').replace(/[1-8]/g,fill=>'.'.repeat(+fill)).split('');

    function readFrame(frame, profile, previous) {
        const grid = geometry.find(frame, previous);
        if (!grid) return null;
        const {x: left, y: top, step: cell} = grid;
        const {data, width} = frame;
        const labels = [];
        for (let row = 0; row < 8; row++) {
            for (let col = 0; col < 8; col++) {
                const signature = [];
                let ink = 0;
                for (let y = 0; y < 14; y++) {
                    for (let x = 0; x < 14; x++) {
                        const px = Math.floor(left + (col + 0.12 + 0.76*(x+0.5)/14)*cell);
                        const py = Math.floor(top + (row + 0.12 + 0.76*(y+0.5)/14)*cell);
                        const i = (py*width + px)*4, r=data[i], g=data[i+1], b=data[i+2];
                        const value = Math.max(r,g,b)<82 ? '1' : Math.min(r,g,b)>233 ? '2' : '0';
                        signature.push(value);
                        if (value !== '0') ink++;
                    }
                }
                if (ink <= 9) { labels.push('.'); continue; }
                const ranked = Object.entries(profile.templates).map(([label, samples]) => {
                    const score = Math.min(...samples.map(sample => {
                        let diff = 0;
                        for (let i=0; i<signature.length; i++) if(signature[i]!==sample[i]) diff++;
                        return diff;
                    }));
                    return {label,score};
                }).sort((a,b)=>a.score-b.score);
                labels.push(ranked[0].score <= 49 && ranked[1].score-ranked[0].score >= 4 ? ranked[0].label : '?');
            }
        }
        return {grid, labels};
    }

    function track(Chess) {
        let game = new Chess(), flipped = null;
        const onBoard = (labels, flip) => flip ? labels.slice().reverse() : labels;
        const orientations = () => flipped === null ? [false,true] : [flipped,!flipped];

        function agrees(expected, observed, starting) {
            let unknown = 0;
            for (let i=0; i<expected.length; i++) {
                if (expected[i] === observed[i]) continue;
                // A covered or uncertain changed square never proves a move.
                if (observed[i] !== '?' || expected[i] !== starting[i] || ++unknown > 2) return false;
            }
            return true;
        }

        function propose(labels) {
            const current=flatten(game);
            const views=orientations().map(reverse=>({reverse, observed:onBoard(labels,reverse)}));
            for (const {reverse,observed} of views)
                if (agrees(current,observed,current)) return {moves:[],reverse};
            const one=[], two=[];
            const candidates=game.moves({verbose:true});
            for (const first of candidates) {
                const next=new Chess(first.after);
                const after=arrangement(first.after);
                for (const {reverse,observed} of views) {
                    if (agrees(after,observed,current)) {
                        one.push({moves:[first.lan],reverse});
                        continue;
                    }
                    // The reply can capture existing pieces, but cannot move any
                    // surviving piece of the first side to a different square.
                    const white=game.turn()==='w';
                    const survivors=observed.every((p,i)=>p==='?'||p==='.'||
                        ((p===p.toUpperCase())!==white)||p===after[i]);
                    if (!survivors || two.length>1) continue;
                    for(const second of next.moves({verbose:true})) {
                        const end=arrangement(second.after);
                        if(agrees(end,observed,current)) two.push({moves:[first.lan,second.lan],reverse});
                        if(two.length>1)break;
                    }
                }
            }
            return one.length===1 ? one[0] : one.length===0&&two.length===1 ? two[0] : null;
        }

        function history(labels, read) {
            const boardPly=read.selected>=0?read.selected:read.moves.length;
            const restored=new Chess();
            for(const move of read.moves.slice(0,boardPly)) restored.move(move);
            const expected=flatten(restored);
            const matching=orientations().filter(reverse=>agrees(expected,onBoard(labels,reverse),expected));
            if(matching.length!==1) return null;
            if(boardPly<read.moves.length) return {reviewing:true};
            const previous=game.history({verbose:true}).map(move=>move.lan);
            if(boardPly<previous.length || previous.some((move,i)=>read.moves[i]!==move)) return null;
            return {moves:read.moves.slice(previous.length), reverse:matching[0]};
        }

        function accept(plan) {
            for (const move of plan.moves) game.move(move);
            flipped=plan.reverse;
        }
        return {get game(){return game;}, propose, history, accept, get flipped(){return flipped;}};
    }
    return {readFrame, track};
})();
if (typeof module !== 'undefined') module.exports = chessComVision;
