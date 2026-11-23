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

    let pending, agreement = 0, stable = 0;
    const moves = [];
    function observe(frame) {
        if (!frame || frame.length !== 64 || game.isGameOver()) return {status: 'paused'};
        const costs = frame.map(cell => {
            const result = Object.create(null);
            for (const [name, samples] of templates) {
                result[name] = Math.min(...samples.map(template => distance(cell, template)));
            }
            return result;
        });
        const score = labels => {
            const distances = labels.map((name, i) => costs[i][name]);
            return {
                total: distances.reduce((sum, cost) => sum + cost, 0),
                worst: Math.max(...distances)
            };
        };
        const ranked = [{move: null, ...score(position)}];
        for (const move of game.moves({verbose: true})) {
            game.move(move);
            ranked.push({move, ...score(boardLabels())});
            game.undo();
        }
        ranked.sort((a, b) => a.total - b.total);
        const [best, second] = ranked;
        if (best.worst > 0.24 || (second && second.total - best.total < 0.06)) {
            pending = undefined;
            agreement = stable = 0;
            return {status: 'uncertain'};
        }

        if (best.move) {
            stable = 0;
            if (pending !== best.move.lan) {
                pending = best.move.lan;
                agreement = 1;
                return {status: 'checking'};
            }
            if (++agreement < 2) return {status: 'checking'};
            const move = game.move(best.move);
            moves.push(move.lan);
            position = boardLabels();
            pending = undefined;
            agreement = 0;
            stable = 2;
        } else {
            pending = undefined;
            agreement = 0;
            stable++;
        }
        if (stable < 2) return {status: 'checking'};
        if (game.isGameOver()) return {status: 'ended', ply: moves.length};
        return {
            status: 'tracking', ply: moves.length, turn: game.turn(),
            moveLine: game.turn() === userColor ? moves.join(' ') : null
        };
    }
    return {observe};
}

if (typeof module !== 'undefined') module.exports = {makeBoardTracker};
