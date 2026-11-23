const assert = require('node:assert/strict');
const {Chess} = require('../Vendor/resources/chess-rules.js');
const {makeBoardTracker} = require('../Resources/BoardTracker.js');
const patterns = new Map();
for (const [index, key] of [...'pnbrqk'].flatMap(piece => ['w'+piece,'b'+piece]).entries()) {
    patterns.set(key, Array.from({length: 144}, (_, i) =>
        (i * 19 + index * 47 + i * index * 3) % 101 < 36 ? (index % 2 ? 1 : 2) : 0));
}
patterns.set('.', new Array(144).fill(0));
function frame(game, whiteAtBottom) {
    const files = whiteAtBottom ? 'abcdefgh' : 'hgfedcba';
    const ranks = whiteAtBottom ? '87654321' : '12345678';
    return [...ranks].flatMap(rank => [...files].map(file => {
        const piece = game.get(file + rank);
        return patterns.get(piece ? piece.color + piece.type : '.').slice();
    }));
}
function play(sequence, orientation, ownColor) {
    const game = new Chess();
    const tracker = makeBoardTracker(Chess, frame(game, orientation), orientation, ownColor);
    assert.equal(tracker.observe(frame(game, orientation)).status, 'checking');
    assert.equal(tracker.observe(frame(game, orientation)).moveLine, ownColor === 'w' ? '' : null);
    const seen = [];
    for (const san of sequence) {
        const move = game.move(san);
        seen.push(move.lan);
        assert.equal(tracker.observe(frame(game, orientation)).status, 'checking');
        const state = tracker.observe(frame(game, orientation));
        assert.equal(state.ply, seen.length);
        assert.equal(state.moveLine, game.turn() === ownColor ? seen.join(' ') : null);
    }
    const covered = frame(game, orientation).map(() => new Array(144).fill(2));
    assert.equal(tracker.observe(covered).status, 'uncertain');
}
play(['e4','e5','Nf3','Nc6','Bc4','Nf6','O-O'], true, 'b');
play(['e4','h5','e5','d5','exd6','Nf6'], false, 'w');
play(['a4','h5','a5','h4','a6','h3','axb7','hxg2','bxa8=Q'], true, 'w');
const fast = new Chess();
const tracking = makeBoardTracker(Chess, frame(fast,true), true, 'w');
fast.move('e4');
fast.move('e5');
assert.equal(tracking.observe(frame(fast,true)).status,'checking');
assert.equal(tracking.observe(frame(fast,true)).moveLine,'e2e4 e7e5');
console.log('Both orientations, initial white hint, turn changes, castling, en passant, promotion and occlusion passed.');
require('./chesscom-vision.cjs');
