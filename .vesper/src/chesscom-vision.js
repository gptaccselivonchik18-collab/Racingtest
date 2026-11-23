const chessComVision = (() => {
    const matching = (a, b) => a.every((piece, i) => piece === b[i]);
    const flatten = game => game.board().flatMap(rank => rank.map(piece =>
        piece ? (piece.color === 'w' ? piece.type.toUpperCase() : piece.type) : '.'));

    function findBoard(frame, profile, previousTop) {
        const {data, width, height} = frame;
        const cell = width / 8;
        if (cell < 22 || width >= height) return null;
        const maxTop = height - width;
        const palette = [profile.light, profile.dark];

        function matchesPalette(x, y, color) {
            const index = (Math.floor(y) * width + Math.floor(x)) * 4;
            return Math.max(Math.abs(data[index] - color[0]), Math.abs(data[index+1] - color[1]),
                            Math.abs(data[index+2] - color[2])) <= 19;
        }
        function score(top) {
            if (top < 0 || top > maxTop) return 0;
            let count = 0;
            for (let row = 0; row < 8; row++) {
                for (let col = 0; col < 8; col++) {
                    const color = palette[(row+col)%2];
                    for (const y of [0.05, 0.95]) {
                        const x = (col + (col === 0 ? 0.86 : 0.14)) * cell;
                        if (matchesPalette(x, top+(row+y)*cell, color)) count++;
                    }
                }
            }
            return count;
        }
        function align(roughTop) {
            let top = roughTop, best = 0, center = 0, count = 0;
            const radius = Math.max(2, Math.ceil(cell * 0.13));
            for (let y=roughTop-radius; y<=roughTop+radius; y++) {
                const value = score(y);
                if (value > best) {
                    best = value;
                    center = y;
                    count = 1;
                } else if (value === best) {
                    center += y;
                    count++;
                }
            }
            if (count) top = Math.round(center / count);
            return best >= 109 ? {top, cell, score: best} : null;
        }
        const fast = align(Number.isFinite(previousTop) ? previousTop : Math.round(height * profile.yRatio));
        if (fast) return fast;

        let bestTop = 0, bestScore = 0;
        for (let y=0; y<=maxTop; y+=Math.max(2, Math.floor(cell/9))) {
            const value = score(y);
            if (value > bestScore) { bestScore = value; bestTop = y; }
        }
        return bestScore >= 96 ? align(bestTop) : null;
    }

    function readFrame(frame, profile, previousTop) {
        const grid = findBoard(frame, profile, previousTop);
        if (!grid) return null;
        const {top, cell} = grid;
        const {data, width} = frame;
        const labels = [];
        for (let row = 0; row < 8; row++) {
            for (let col = 0; col < 8; col++) {
                const signature = [];
                let ink = 0;
                for (let y=0; y<14; y++) {
                    for (let x=0; x<14; x++) {
                        const px = Math.floor((col + 0.12 + 0.76*(x+0.5)/14)*cell);
                        const py = Math.floor(top + (row + 0.12 + 0.76*(y+0.5)/14)*cell);
                        const i = (py*width + px)*4, r=data[i], g=data[i+1], b=data[i+2];
                        const v = Math.max(r,g,b)<82 ? '1' : Math.min(r,g,b)>233 ? '2' : '0';
                        signature.push(v);
                        if (v!=='0') ink++;
                    }
                }
                if (ink <= 9) {
                    labels.push('.');
                    continue;
                }
                const ranked = Object.entries(profile.templates).map(([label, samples]) => {
                    const score = Math.min(...samples.map(sample => {
                        let diff = 0;
                        for (let i=0; i<signature.length; i++) if(signature[i]!==sample[i]) diff++;
                        return diff;
                    }));
                    return {label,score};
                }).sort((a,b)=>a.score-b.score);
                labels.push(ranked[0].score <= 47 && ranked[1].score-ranked[0].score >= 4 ? ranked[0].label : '?');
            }
        }
        return {top, labels};
    }

    function track(Chess) {
        const game = new Chess();
        let flipped = null;
        function findMove(observed) {
            const matches = [];
            for (const move of game.moves({verbose:true})) {
                game.move(move);
                if (matching(flatten(game), observed)) matches.push(move);
                game.undo();
            }
            return matches.length === 1 ? matches[0] : null;
        }
        function update(labels) {
            if (labels.includes('?')) return null;
            const current = flatten(game);
            const orientations = flipped === null ? [false, true] : [flipped, !flipped];
            for (const reverse of orientations) {
                const squares = reverse ? labels.slice().reverse() : labels;
                if (matching(current, squares)) {
                    const changed = flipped !== reverse;
                    flipped = reverse;
                    return {changed};
                }
            }
            for (const reverse of orientations) {
                const squares = reverse ? labels.slice().reverse() : labels;
                const move = findMove(squares);
                if (!move) continue;
                game.move(move);
                flipped = reverse;
                return {changed: true, san: move.san};
            }
            return null;
        }
        return {game, update, get flipped(){return flipped;}};
    }
    return {readFrame, track};
})();
if (typeof module !== 'undefined') module.exports = chessComVision;
