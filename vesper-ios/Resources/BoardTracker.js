// Calibrates from the standard initial position with the selected board orientation.
function makeBoardTracker(Chess, initial, whiteAtBottom, userColor) {
    const game = new Chess();
    const files = whiteAtBottom ? 'abcdefgh' : 'hgfedcba';
    const ranks = whiteAtBottom ? '87654321' : '12345678';
    const squares = [...ranks].flatMap(rank => [...files].map(file => file + rank));
    const label = piece => piece ? piece.color + piece.type : '.';
    const boardLabels = () => squares.map(square => label(game.get(square)));
    const templates = new Map();

    function distance(a, b) {
        let mismatch = 0;
        for (let i = 0; i < a.length; i++) {
            if (a[i] === b[i]) continue;
            mismatch += a[i] === 0 || b[i] === 0 ? 1 : 0.6;
        }
        return mismatch / a.length;
    }

    let position = boardLabels();
    if (!Array.isArray(initial) || initial.length !== 64 ||
        initial.some(cell => !Array.isArray(cell) || cell.length !== 144)) {
        throw Error('Некорректная область калибровки.');
    }
    for (let i = 0; i < 64; i++) {
        const fill = initial[i].filter(Boolean).length / 144;
        if (position[i] === '.' ? fill > 0.16 : fill < 0.045 || fill > 0.88) {
            throw Error('Выделите всю доску в начальной позиции без подсветки и открытых меню.');
        }
        const name = position[i];
        if (!templates.has(name)) templates.set(name, []);
        const samples = templates.get(name);
        if (!samples.some(value => distance(value, initial[i]) < 0.016)) samples.push(initial[i]);
    }

    let pending, stable = 0;
    const moves = [];
    const key = () => game.fen().split(' ').slice(0,4).join(' ');
    const positions = new Map([[key(),1]]);
    const finished = () => game.isCheckmate() || game.isStalemate() ||
        game.isInsufficientMaterial() || Number(game.fen().split(' ')[4]) >= 150 ||
        positions.get(key()) >= 5;
    function observe(frame) {
        if (!frame || frame.length !== 64) return {status: 'uncertain'};
        if (finished()) return {status: 'ended', ply: moves.length};
        const costs = frame.map(cell => {
            const result = Object.create(null);
            for (const [name, samples] of templates) {
                result[name] = Math.min(...samples.map(template => distance(cell, template)));
            }
            return result;
        });
        const score = labels => {
            const distances = labels.map((name, i) => costs[i][name]);
            const changed = distances.filter((_,i)=>labels[i]!==position[i]);
            return {
                total: distances.reduce((sum, cost) => sum + cost, 0),
                worst: Math.max(...distances),
                changed: changed.length ? Math.max(...changed) : 0
            };
        };
        const ranked = [{line: [], ...score(position)}];
        const two = [];
        for (const move of game.moves({verbose: true})) {
            game.move(move);
            const labels=boardLabels();
            ranked.push({line:[move.lan], ...score(labels)});
            // Of the squares already changed by this side, all surviving
            // pieces must still be in place after the opponent's reply.
            const viable=labels.every((label,i)=>label===position[i] || label==='.' ||
                costs[i][label]<=.22 || Object.keys(costs[i]).some(name=>
                    name[0]===game.turn() && costs[i][name]<=.22));
            if (viable) two.push(move);
            game.undo();
        }
        ranked.sort((a, b) => a.total - b.total);
        let [best, second] = ranked;
        if (best.worst > .24 || best.changed > .19 || (second && second.total - best.total < .06)) {
            const recovered=[];
            for(const first of two){
                game.move(first);
                for(const reply of game.moves({verbose:true})){
                    game.move(reply);
                    const grade=score(boardLabels());
                    if(grade.worst<=.24 && grade.changed<=.16)
                        recovered.push({line:[first.lan,reply.lan],...grade});
                    game.undo();
                }
                game.undo();
            }
            recovered.sort((a,b)=>a.total-b.total);
            [best,second]=recovered;
        }
        if (!best || (second && second.total - best.total < .06)) {
            pending = undefined;
            stable = 0;
            return {status: 'uncertain'};
        }

        if (best.line.length) {
            stable = 0;
            const sequence=best.line.join(' ');
            if (pending !== sequence) {
                pending = sequence;
                return {status: 'checking'};
            }
            for(const lan of best.line){
                game.move(lan);
                moves.push(lan);
                positions.set(key(),(positions.get(key())||0)+1);
            }
            position = boardLabels();
            pending = undefined;
            stable = 2;
        } else {
            pending = undefined;
            stable++;
        }
        if (stable < 2) return {status: 'checking'};
        if (finished()) return {status: 'ended', ply: moves.length};
        return {
            status: 'tracking', ply: moves.length, turn: game.turn(),
            pieces: position.filter(name=>name!=='.').length,
            moveLine: game.turn() === userColor ? moves.join(' ') : null
        };
    }
    return {observe};
}

if (typeof module !== 'undefined') module.exports = {makeBoardTracker};
