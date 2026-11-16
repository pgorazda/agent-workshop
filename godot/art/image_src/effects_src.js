// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// The few sprites that the JavaScript mockup (removed, see the git history) made next to its frame code: the thought
// cloud, the candle and its flame. The blocks below are copies of that code, line for line. This file is the only copy now.

// ---- copy from the old mockup: the thought cloud
function cloud() { return itemSpr(52, 32, s => { for (const [x, y, rx, ry] of [[12, 18, 8, 7], [22, 11, 9, 8], [34, 11, 9, 8], [42, 19, 7, 7], [26, 20, 16, 8]]) s.ell(x, y, rx, ry, P.cream); }); }

// ---- copy from the old mockup: the candle
const WAX = '#f6ecd2', WAXSH = '#e0cfa6', WAXTOP = '#fffaf0';
const FLAMES = [
  ['..o..', '..o..', '.oyo.', '.oyo.', 'oywyo', '.owo.'],
  ['.o...', '.oo..', '.oyo.', 'oyyo.', 'oywyo', '.owo.'],
  ['...o.', '..oo.', '.oyo.', '.oyyo', 'oywyo', '.owo.'],
  ['.....', '..o..', '.oyo.', '.oyo.', 'oywyo', '.owo.'],
];
const FLICKER = [0, 1, 0, 2, 3, 0, 2, 1, 0, 3];
const candleCache = new Map();
function candleSpr(wax) {
  if (candleCache.has(wax)) return candleCache.get(wax);
  const s = new Spr(19, wax + 8), cx = 7, top = 2, dy = top + wax;
  s.ell(cx + 0.5, dy + 1.2, 6.5, 1.9, P.orange); s.rect(cx - 5, dy + 2, 12, 1, P.orangeDk);
  s.ell(cx + 8.5, dy - 0.2, 2.2, 2.2, P.orange); s.p[(dy - 1) * s.w + cx + 8] = null; s.p[dy * s.w + cx + 8] = null;
  for (const x of [cx - 3, cx, cx + 3]) s.set(x, dy + 1, P.cream);
  s.rect(cx - 2, top, 5, wax, WAX); s.rect(cx + 2, top, 1, wax, WAXSH); s.rect(cx - 2, top, 5, 1, WAXTOP);
  s.set(cx - 3, top + 1, WAX); s.set(cx - 3, top + 2, WAX); s.set(cx - 2, top + 3, WAXTOP);
  s.outline(); s.set(cx, 0, P.ink); s.set(cx, 1, P.ink);
  const c = s.canvas(); candleCache.set(wax, c); return c;
}

// ---- not a copy: the flame of candleInCloud (from the old mockup) drawn into a small canvas, one for each frame
function flameC(f) {
  return onCanvas(5, 6, () => FLAMES[f].forEach((row, j) => [...row].forEach((ch, i) => { if (ch !== '.') px(i, j, { o: P.fire3, y: P.fire2, w: P.fire1 }[ch]); })));
}

// ---- not a copy: the small cloud of a penguin that thinks where it stands (MINICLOUD in the old mockup)
function miniCloud() { return itemSpr(40, 28, s => { for (const [x, y, rx, ry] of [[10, 15, 8, 7], [19, 9, 8, 7], [29, 10, 8, 7], [32, 17, 6, 6], [20, 17, 13, 7]]) s.ell(x, y, rx, ry, P.cream); }); }
