const coachVision = (() => {
    const vision = typeof chessComVision !== 'undefined' ? chessComVision : require('./chesscom-vision.js');
    const strip = typeof moveStrip !== 'undefined' ? moveStrip : require('./MoveStrip.js');

    function create(Chess, profile, player) {
        const tracker = vision.track(Chess);
        let grid, candidate, lastStrip = null, stripKey, uncertain = 0;
        let current = [];
        const seen = new Map([[tracker.game.fen().split(' ').slice(0,4).join(' '),1]]);
        function readStrip(frame, board) {
            const bottom = Math.round(board.y + board.step * 8);
            let hash = 2166136261;
            for (let y = bottom + 2; y < Math.min(frame.height, bottom + board.step * 3); y+=3)
                for (let x=3;x<frame.width-3;x+=3) {
                    const i=(y*frame.width+x)*4;
                    const bright=Math.max(frame.data[i],frame.data[i+1],frame.data[i+2])>113;
                    hash=Math.imul(hash^Number(bright),16777619);
                }
            const key = [frame.width, frame.height, bottom, current.length, hash].join(',');
            if (key !== stripKey) {
                lastStrip = strip.read(frame,board,Chess,current);
                stripKey = key;
            }
            return lastStrip;
        }
        return function observe(frame) {
            const hit = vision.readFrame(frame, profile, grid);
            if (!hit) { candidate = undefined; return {status:'uncertain'}; }
            grid = hit.grid;
            let plan = tracker.propose(hit.labels);
            if (!plan || current.length < 4 || uncertain) {
                const read = readStrip(frame,grid);
                const fromHistory = read && tracker.history(hit.labels,read);
                if (fromHistory?.reviewing) {
                    candidate = undefined;
                    return {status:'reviewing'};
                }
                if (fromHistory && (!plan || fromHistory.moves.length>plan.moves.length)) plan = fromHistory;
            }
            if (!plan) { candidate = undefined; uncertain++; return {status:'uncertain'}; }
            uncertain = 0;
            const key = plan.reverse + ':' + plan.moves.join(' ');
            if (key !== candidate && (plan.moves.length || tracker.flipped !== plan.reverse)) {
                candidate = key;
                return {status:'checking'};
            }
            candidate = undefined;
            for (const move of plan.moves) {
                tracker.game.move(move);
                const position = tracker.game.fen().split(' ').slice(0,4).join(' ');
                seen.set(position,(seen.get(position)||0)+1);
            }
            tracker.accept({moves:[],reverse:plan.reverse});
            current.push(...plan.moves);
            const game=tracker.game, fen=game.fen().split(' ');
            const ended=game.isCheckmate()||game.isStalemate()||game.isInsufficientMaterial()||
                Number(fen[4])>=150||seen.get(fen.slice(0,4).join(' '))>=5;
            return {status:ended?'ended':'tracking',ply:current.length,turn:game.turn(),
                pieces:game.board().flat().filter(Boolean).length,
                moveLine:!ended&&game.turn()===player?current.join(' '):null};
        };
    }

    function native(Chess, profile, player) {
        const observe = create(Chess, profile, player);
        const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        const table = new Uint8Array(128);
        for (let i=0;i<alphabet.length;i++) table[alphabet.charCodeAt(i)]=i;
        return (encoded,width,height) => {
            const data = new Uint8Array(width*height*4);
            for (let i=0,j=0;i<encoded.length;i+=4,j+=3) {
                const a=table[encoded.charCodeAt(i)], b=table[encoded.charCodeAt(i+1)];
                const c=table[encoded.charCodeAt(i+2)], d=table[encoded.charCodeAt(i+3)];
                data[j]=(a<<2)|(b>>4); data[j+1]=(b<<4)|(c>>2); data[j+2]=(c<<6)|d;
            }
            return observe({width,height,data});
        };
    }
    return {create,native};
})();
if (typeof module !== 'undefined') module.exports = coachVision;
