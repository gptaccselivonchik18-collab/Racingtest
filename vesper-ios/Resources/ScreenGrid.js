const screenGrid = (() => {
'use strict';

const colorDistance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
const pixel = (image, x, y) => {
  const i = (Math.floor(y) * image.width + Math.floor(x)) * 4;
  return [image.data[i], image.data[i + 1], image.data[i + 2]];
};
const median = values => values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
const medianColor = colors => [0, 1, 2].map(i => median(colors.map(color => color[i])));

function runs(image, horizontal, coordinate) {
  const limit = horizontal ? image.width : image.height;
  const sample = offset => horizontal ? pixel(image, offset, coordinate) : pixel(image, coordinate, offset);
  const result = [];
  let start = 0;
  let reference = sample(0);
  for (let i = 1; i <= limit; i++) {
    const next = i < limit ? sample(i) : null;
    if (next && colorDistance(reference, next) < 23) continue;
    result.push({start, end: i, color: reference});
    if (next) reference = next;
    start = i;
  }
  return result;
}

function strips(image, horizontal, coordinate) {
  const line = runs(image, horizontal, coordinate).filter(run=>run.end-run.start>2);
  for (let i=1; i<line.length; i++) {
    const before=line[i-1], after=line[i];
    // A scaled screen capture can insert one or two interpolated pixels at an edge.
    if (after.start-before.end<=3) before.end=after.start=Math.round((before.end+after.start)/2);
  }
  const result = [];
  for (let i = 0; i + 7 < line.length; i++) {
    const group = line.slice(i, i + 8);
    const width = (group[7].end - group[0].start) / 8;
    if (width < 12 || !group.every((run,k) => Math.abs(run.end-run.start-width) < width*.09+2 &&
        (!k || run.start===group[k-1].end))) continue;
    const parity = [0, 1].map(k => medianColor(group.filter((_, i) => i % 2 === k).map(run => run.color)));
    if (colorDistance(...parity) < 32 || group.filter((run, k) => colorDistance(run.color, parity[k % 2]) < 27).length < 6) continue;
    result.push({start: group[0].start, size: width});
  }
  return result;
}

function background(image, board, column, row) {
  const colors = [];
  for (const a of [.12, .20, .80, .88]) {
    for (const b of [.12, .20, .80, .88]) {
      if ((a < .5) !== (b < .5) || (a === .12 || a === .88) || (b === .12 || b === .88))
        colors.push(pixel(image, board.x + (column + a) * board.step, board.y + (row + b) * board.step));
    }
  }
  return medianColor(colors);
}

function backgrounds(image, board) {
  return Array.from({length: 64}, (_, i) => background(image, board, i % 8, i >> 3));
}

function paletteOf(colors) {
  return [0, 1].map(parity => medianColor(colors.filter((_, i) => ((i % 8 + (i >> 3)) & 1) === parity)));
}

function edgeEvidence(image, board, colors) {
  let matches = 0;
  let count = 0;
  for (let i = 0; i < 8; i++) {
    for (const edge of ['top', 'bottom', 'left', 'right']) {
      const vertical = edge === 'left' || edge === 'right';
      const near = edge === 'top' || edge === 'left';
      const offset = Math.min(5, Math.max(2, Math.round(board.step * .04)));
      const tile = vertical ? i * 8 + (near ? 0 : 7) : (near ? 0 : 56) + i;
      for (const fraction of [.24, .76]) {
        const u = (vertical ? board.y : board.x) + (i + fraction) * board.step;
        const edgeAt = (vertical ? board.x : board.y) + (near ? 0 : 8 * board.step);
        const a = edgeAt + (near ? offset : -offset);
        const b = edgeAt + (near ? -offset : offset);
        const x = vertical ? b : u, y = vertical ? u : b;
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
        const inside = vertical ? pixel(image, a, u) : pixel(image, u, a);
        const outside = pixel(image, x, y);
        count++;
        if (colorDistance(inside, colors[tile]) < 37 && colorDistance(outside, inside) >= 26) matches++;
      }
    }
  }
  return count ? matches / count : 1;
}

function detectBoard(image) {
  const matches = [];
  const seen = new Set();
  for (let y = 0; y < image.height; y += Math.max(1, Math.floor(image.height / 150))) {
    for (const horizontal of strips(image, true, y)) {
      const key = horizontal.start + ',' + Math.round(horizontal.size * 4);
      if (seen.has(key)) continue;
      seen.add(key);
      for (const offset of [.04, .96, 1.04, 1.96, 3.04, 4.96, 6.04, 7.96, .15, .85, 3.12, 4.88]) {
        const x = horizontal.start + horizontal.size * offset;
        for (const vertical of strips(image, false, x)) {
          if (Math.abs(vertical.size - horizontal.size) > Math.max(1, horizontal.size * .018)) continue;
          // A horizontal span is visited only once. Other grids at that
          // same X and size are separate candidates even on different rows.
          const board = {x: horizontal.start, y: vertical.start, step: horizontal.size};
          if (board.y + 8 * board.step > image.height + 1) continue;
          const colors = backgrounds(image, board);
          const palette = paletteOf(colors);
          if (colorDistance(...palette) < 32) continue;
          const good = colors.filter((color, i) => colorDistance(color, palette[(i % 8 + (i >> 3)) & 1]) < 26).length;
          const edges = edgeEvidence(image, board, colors);
          if (good >= 38 && edges >= .45 && gridAligned(image, board, colors, true) && gridAligned(image, board, colors, false))
            matches.push({...board, score: good + 8 * edges});
        }
      }
    }
  }
  matches.sort((a, b) => b.score - a.score || b.step - a.step);
  const best = matches[0];
  if (!best) throw Error('Доска 8×8 не найдена. Включите в область все клетки и немного места вокруг.');
  if (matches.some(board => board.score > best.score - 4 &&
      Math.hypot(board.x - best.x, board.y - best.y) > best.step * .5))
    throw Error('Найдено несколько досок. Выделите только одну.');
  return {x: best.x, y: best.y, step: best.step};
}

// Test the internal grid directly. A selected piece may change the colour
// of many cells at once while leaving all the cell boundaries in place.
function gridAligned(image, board, colors, vertical) {
  const margin = Math.min(5, Math.max(2, board.step * .055));
  let matched = 0, usable = 0;
  for (let lane = 0; lane < 8; lane++) {
    let laneHits = 0, laneUsable = 0;
    for (let edge = 1; edge < 8; edge++) {
      const index = vertical ? lane * 8 + edge : edge * 8 + lane;
      const left = colors[index - (vertical ? 1 : 8)], right = colors[index];
      if (colorDistance(left, right) < 30) continue;
      laneUsable++;
      const boundary = (vertical ? board.x : board.y) + edge * board.step;
      const found = [.14, .86, .5].some(f => {
        const cross = (vertical ? board.y : board.x) + (lane + f) * board.step;
        const a = vertical ? pixel(image, boundary - margin, cross) : pixel(image, cross, boundary - margin);
        const b = vertical ? pixel(image, boundary + margin, cross) : pixel(image, cross, boundary + margin);
        return colorDistance(a, left) < 42 && colorDistance(b, right) < 42 &&
          colorDistance(a, right) > colorDistance(a, left) + 12 &&
          colorDistance(b, left) > colorDistance(b, right) + 12;
      });
      if (found) laneHits++;
    }
    if ((lane === 0 || lane === 7) && laneHits < 2) {
      // A uniformly painted outer rank/file has no divisions to sample.
      // Confirm its outside edge instead; a translated board can leave a
      // similarly uniform band of window background at the old location.
      const near = lane === 0;
      const boundary = (vertical ? board.y : board.x) + (near ? 0 : 8 * board.step);
      const outside = boundary + (near ? -margin : margin);
      if (laneUsable >= 2 || outside < 0 || outside >= (vertical ? image.height : image.width)) return false;
      let edgeHits = 0;
      for (let tile = 0; tile < 8; tile++) {
        const cross = (vertical ? board.x : board.y) + (tile + .5) * board.step;
        const inside = boundary + (near ? margin : -margin);
        const a = vertical ? pixel(image, cross, inside) : pixel(image, inside, cross);
        const b = vertical ? pixel(image, cross, outside) : pixel(image, outside, cross);
        const tileColor = colors[vertical ? lane * 8 + tile : tile * 8 + lane];
        if (colorDistance(a, tileColor) < 42 && colorDistance(a, b) >= 30) edgeHits++;
      }
      if (edgeHits < 6) return false;
    }
    matched += laneHits;
    usable += laneUsable;
  }
  return matched >= 23 && matched >= .70 * usable;
}


function find(frame, previous) {
  if (previous && previous.width === frame.width && previous.height === frame.height) {
    const colors = backgrounds(frame, previous);
    if (colorDistance(...paletteOf(colors)) >= 32 &&
        gridAligned(frame, previous, colors, true) && gridAligned(frame, previous, colors, false) &&
        edgeEvidence(frame, previous, colors) >= .4) return previous;
  }
  try { return {...detectBoard(frame), width: frame.width, height: frame.height}; }
  catch { return null; }
}
return {find};
})();
if (typeof module !== 'undefined') module.exports = screenGrid;
