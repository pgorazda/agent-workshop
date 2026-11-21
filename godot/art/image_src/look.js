// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// The look: the palette, pixel text and icons, the sprite buffer, the penguin, the props and the room.
//
// The look is Agent Workshop's own, taken from the penguin's Krakow cap (the rogatywka) rather than from any product:
// Polish folk colours (whitewashed walls, a cobalt band with peacock-eye dots, painted flowers, a kilim rug),
// inspired by the painted flowers of Zalipie, folk painting from Lipnica Murowana, Boleslawiec pottery and kilims;
// pixel art at 480x270 drawn by code, two open pixel fonts (Tiny5, Silkscreen; SIL OFL 1.1) and a game-style
// activity log.

const P = {
  ink:'#1d2333', cream:'#f7f9fc', oat:'#dfe6ee', gray:'#9aa6b5', orange:'#d23c3c', blue:'#3a6fc4', green:'#3f9a5a',
  orangeDk:'#a82a32', orangeLt:'#ef7a74', blueDk:'#284f93', blueLt:'#9cc0ee', greenDk:'#2c7343', greenLt:'#7cc48e',
  wall:'#edf1f5', wallShade:'#e1e7ee', wainscot:'#2f5fa7', wainscotDk:'#234a85', wallTop:'#2a2f45', wallTopLt:'#454c68',
  floor:'#d6ab76', floor2:'#cfa36d', seam:'#b5885a', knot:'#a77b4f',
  woodLt:'#c08552', wood:'#9c6239', woodDk:'#6e3f25', woodXDk:'#48291a',
  stone:'#8f9bab', stoneDk:'#66717f', stoneLt:'#b6c0cc',
  fire1:'#fff3b0', fire2:'#ffc23d', fire3:'#ff7a2a',
  sky:'#1f2f5a', skyLt:'#33477e',
  crimson:'#c0283c', crimsonDk:'#861a2a', crimsonLt:'#e0495a', fur:'#3b2a22', furLt:'#5e4639',
  peng:'#2b2f3a', pengLt:'#454b5c', belly:'#f7f9fc', blush:'#f2a0a8', gold:'#f2c230', goldDk:'#c79a1c',
  paper:'#f1e3c0', paperDk:'#dfcb9b', red:'#e03a3a', teal:'#2a9d8f', dim:'#7d6a4f', hudLine:'#34405e',
  beak:'#f29b30', beakDk:'#c97516', navy:'#24345e',
};
const CORD = '#d97333'; // the hat-cord colour the director gives claude-code
const HC = { bg:'#1b2236', edge:'#34405e', edge2:'#283152', text:'#f7f9fc', dim:'#8b95a8', blue:'#9cc0ee', gold:'#f2c230', green:'#6fdc8c', red:'#ff6b6b', dot:'#3d4866' };
function onCanvas(w, h, fn) { const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d'); x.imageSmoothingEnabled = false; const old = g; g = x; try { fn(); } finally { g = old; } return c; }
function rgb(hex) { const n = parseInt(hex.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; }

// ---------------------------------------------------------------- pixel text and icons
const T1 = document.createElement('canvas'); T1.width = 480; T1.height = 24; const t1 = T1.getContext('2d', { willReadFrequently: true });
const textCache = new Map();
function text(str, x, y, color, font = 'Tiny5', size = 8) {
  const key = str + '|' + color + '|' + font + size;
  let c = textCache.get(key);
  if (!c) {
    t1.clearRect(0, 0, 480, 24); t1.font = `${size}px ${font}`; t1.textBaseline = 'top'; t1.fillStyle = '#fff'; t1.fillText(str, 2, 2);
    const w = Math.ceil(t1.measureText(str).width);
    const d = t1.getImageData(0, 0, w + 4, 24), [r, gg, b] = rgb(color);
    for (let i = 0; i < d.data.length; i += 4) { const on = d.data[i + 3] > 110; d.data[i] = r; d.data[i + 1] = gg; d.data[i + 2] = b; d.data[i + 3] = on ? 255 : 0; }
    c = document.createElement('canvas'); c.width = w + 4; c.height = 24; c.getContext('2d').putImageData(d, 0, 0); c.w = w;
    textCache.set(key, c);
  }
  g.drawImage(c, Math.round(x) - 2, Math.round(y) - 2);
  return c.w;
}
function textW(str, font = 'Tiny5', size = 8) { t1.font = `${size}px ${font}`; return Math.ceil(t1.measureText(str).width); }
const GL = { '✗': [['#...#', '.#.#.', '..#..', '.#.#.', '#...#'], 1] };
function glyph(ch, x, y, color) { const [rows, oy] = GL[ch]; rows.forEach((r, j) => [...r].forEach((c, i) => { if (c === '#') px(x + i, y + oy + j, color); })); return rows[0].length; }
function rich(segs, x, y) {
  for (const [str, color] of segs) {
    let run = '';
    const flush = () => { if (run) { x += text(run, x, y, color); run = ''; } };
    for (const ch of str) { if (GL[ch]) { flush(); x += glyph(ch, x, y, color) + 2; } else run += ch; }
    flush();
  }
  return x;
}
const MINI_STAR = ['.#.', '###', '.#.'];
// four-point sparkles, smallest to largest
const SPARK = [['#'], ['.#.', '###', '.#.'], ['..#..', '..#..', '#####', '..#..', '..#..'], ['...#...', '...#...', '..###..', '#######', '..###..', '...#...', '...#...']];
function bitmap(rows, x, y, color) { x = Math.round(x); y = Math.round(y); rows.forEach((r, j) => [...r].forEach((c, i) => { if (c === '#') px(x + i, y + j, color); })); }
// 7x7 activity icons, one per category
const ICON = {
  read: ['bbbbbb.', 'b....bw', 'b.ww.bw', 'b....bw', 'b.ww.bw', 'bbbbbbw', '.wwwwww'],
  search: ['.www...', 'w...w..', 'w...w..', 'w...w..', '.www...', '....nn.', '.....nn'],
  write: ['sssss..', 'sssss..', '..n....', '..n....', '..n....', '..n....', '..n....'],
  exec: ['...r...', '..rr...', '..rfr..', '.rffr..', '.rfyfr.', '.rfyyfr', '..rffr.'],
  delegate: ['...y...', '..yyy..', '.yyyyy.', '.yyyyy.', '.yyyyy.', 'yyyyyyy', '...y...'],
  think: ['...f...', '..fyf..', '...y...', '..ccc..', '..ccc..', '..ccc..', '.RRRRR.'],
  ask: ['..yyy..', '.y...y.', '.....y.', '...yy..', '...y...', '.......', '...y...'],
  star: ['...y...', '...y...', 'yyyyyyy', '.yyyyy.', '..yyy..', '.yy.yy.', '.y...y.'],
  web: ['.....ww', '....bbw', '...bbb.', '..bbb..', '.bbb...', '..n.n..', '.n...n.'],
  other: ['nnnnnnn', 'ns...sn', 'n.s.s.n', 'n..s..n', 'n.s.s.n', 'ns...sn', 'nnnnnnn'],
};
const ICOL = { b: '#6f9be0', w: '#f7f9fc', y: '#f2c230', r: '#ff6b6b', f: '#ffb03b', n: '#c08552', s: '#9aa6b5', c: '#f6ecd2', R: '#e0495a' };
function icon(name, x, y) { ICON[name].forEach((row, j) => [...row].forEach((c, i) => { if (c !== '.') px(x + i, y + j, ICOL[c]); })); }

// ---------------------------------------------------------------- sprite buffer
class Spr {
  constructor(w, h) { this.w = w; this.h = h; this.p = new Array(w * h).fill(null); }
  get(x, y) { return (x < 0 || y < 0 || x >= this.w || y >= this.h) ? null : this.p[y * this.w + x]; }
  set(x, y, c) { x = Math.floor(x); y = Math.floor(y); if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.p[y * this.w + x] = c; return this; }
  rect(x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c); return this; }
  ell(cx, cy, rx, ry, c, a = 0, clip = false) {
    const ca = Math.cos(a), sa = Math.sin(a), m = Math.ceil(Math.max(rx, ry)) + 1;
    for (let y = Math.floor(cy - m); y <= Math.ceil(cy + m); y++) for (let x = Math.floor(cx - m); x <= Math.ceil(cx + m); x++) {
      const px = x + 0.5 - cx, py = y + 0.5 - cy, u = (px * ca + py * sa) / rx, v = (-px * sa + py * ca) / ry;
      if (u * u + v * v <= 1 && (!clip || this.get(x, y) !== null)) this.set(x, y, c);
    }
    return this;
  }
  limb(cx, cy, rx, ry, a, fill, line) {
    const ca = Math.cos(a), sa = Math.sin(a), m = Math.ceil(Math.max(rx, ry)) + 1;
    const inside = (x, y) => { const px = x + 0.5 - cx, py = y + 0.5 - cy, u = (px * ca + py * sa) / rx, v = (-px * sa + py * ca) / ry; return u * u + v * v <= 1; };
    for (let y = Math.floor(cy - m); y <= Math.ceil(cy + m); y++) for (let x = Math.floor(cx - m); x <= Math.ceil(cx + m); x++) {
      if (!inside(x, y)) continue;
      this.set(x, y, (!inside(x + 1, y) || !inside(x - 1, y) || !inside(x, y + 1) || !inside(x, y - 1)) ? line : fill);
    }
    return this;
  }
  line(x0, y0, x1, y1, c) {
    x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1; let e = dx + dy;
    for (;;) { this.set(x0, y0, c); if (x0 === x1 && y0 === y1) break; const e2 = 2 * e; if (e2 >= dy) { e += dy; x0 += sx; } if (e2 <= dx) { e += dx; y0 += sy; } }
    return this;
  }
  stamp(o, ox, oy) { for (let y = 0; y < o.h; y++) for (let x = 0; x < o.w; x++) { const c = o.p[y * o.w + x]; if (c) this.set(ox + x, oy + y, c); } return this; }
  outline(c = P.ink) {
    const q = this.p.slice(), w = this.w, h = this.h;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      if (q[y * w + x] !== null) continue;
      if ((x > 0 && q[y * w + x - 1]) || (x < w - 1 && q[y * w + x + 1]) || (y > 0 && q[(y - 1) * w + x]) || (y < h - 1 && q[(y + 1) * w + x])) this.p[y * w + x] = c;
    }
    return this;
  }
  flipX() { const o = new Spr(this.w, this.h); for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) o.p[y * this.w + (this.w - 1 - x)] = this.p[y * this.w + x]; return o; }
  rotCCW() { const o = new Spr(this.h, this.w); for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) o.p[(this.w - 1 - x) * o.w + y] = this.p[y * this.w + x]; return o; }
  crop() {
    let x0 = this.w, y0 = this.h, x1 = -1, y1 = -1;
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) if (this.p[y * this.w + x]) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    const o = new Spr(x1 - x0 + 1, y1 - y0 + 1);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) o.p[(y - y0) * o.w + (x - x0)] = this.p[y * this.w + x];
    return o;
  }
  canvas() {
    const c = document.createElement('canvas'); c.width = this.w; c.height = this.h;
    const x = c.getContext('2d'), d = x.createImageData(this.w, this.h);
    for (let i = 0; i < this.p.length; i++) { const col = this.p[i]; if (!col) continue; const [r, gg, b] = rgb(col); d.data.set([r, gg, b, 255], i * 4); }
    x.putImageData(d, 0, 0); return c;
  }
}
const img = s => s instanceof Spr ? s.canvas() : s;
const draw = (s, x, y) => g.drawImage(img(s), Math.round(x), Math.round(y));
const drawAt = (s, cx, by) => { const c = img(s); draw(c, cx - Math.floor(c.width / 2), by - c.height); };

// ---------------------------------------------------------------- canvas pixel helpers
function px(x, y, c) { g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), 1, 1); }
function fill(x, y, w, h, c) { g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), w, h); }
// One fillRect for each run of pixels in a row: the same pixels, with the same blend, as one pixel at a time. Drawn
// one pixel at a time, the glows of the fire and the lamp took 140,000 fillRect calls a frame when the camera
// showed many rooms.
function pxEll(cx, cy, rx, ry, col, alpha = 1) {
  if (rx <= 0 || ry <= 0) return;
  g.save(); g.globalAlpha = alpha; g.fillStyle = col;
  const x0 = Math.floor(cx - rx), x1 = Math.ceil(cx + rx);
  for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++) {
    let run = null;
    for (let x = x0; x <= x1 + 1; x++) {
      const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry, inside = x <= x1 && dx * dx + dy * dy <= 1;
      if (inside && run === null) run = x;
      else if (!inside && run !== null) { g.fillRect(run, y, x - run, 1); run = null; }
    }
  }
  g.restore();
}
function pxLine(x0, y0, x1, y1, c) { x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
  const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1; let e = dx + dy;
  for (;;) { px(x0, y0, c); if (x0 === x1 && y0 === y1) break; const e2 = 2 * e; if (e2 >= dy) { e += dy; x0 += sx; } if (e2 <= dx) { e += dx; y0 += sy; } } }
function box(x, y, w, h, fillC, line, shadow = true) {
  x = Math.round(x); y = Math.round(y);
  if (shadow) { g.save(); g.globalAlpha = 0.22; fill(x + 1, y + h, w - 2, 1, P.ink); g.restore(); }
  fill(x + 1, y, w - 2, 1, line); fill(x + 1, y + h - 1, w - 2, 1, line); fill(x, y + 1, 1, h - 2, line); fill(x + w - 1, y + 1, 1, h - 2, line);
  fill(x + 1, y + 1, w - 2, h - 2, fillC);
}

// ---------------------------------------------------------------- the penguin
// Designed on a grid where the penguin's centre is x=14 and its feet touch y=34, then scaled (helpers are smaller).
function penguin(o = {}) {
  const s = o.s ?? 1, dir = o.dir ?? 'front', pose = o.pose ?? 'idle', cord = o.cord ?? CORD, hasCap = o.cap ?? true, capOnly = o.capOnly ?? false, blink = o.blink ?? false;
  const sp = new Spr(48, 50), cx = 24, fy = 44;
  const X = v => cx + (v - 14) * s, Y = v => fy + (v - 34) * s, R = v => v * s;
  const p = (x, y, c) => sp.set(Math.floor(X(x)), Math.floor(Y(y)), c);
  const rect = (x, y, w, h, c) => { const x0 = Math.floor(X(x)), y0 = Math.floor(Y(y)); const x1 = Math.max(x0 + 1, Math.round(X(x + w))), y1 = Math.max(y0 + 1, Math.round(Y(y + h))); sp.rect(x0, y0, x1 - x0, y1 - y0, c); };
  const limb = (x, y, rx, ry, a) => sp.limb(X(x), Y(y), R(rx), R(ry), a, P.peng, P.ink);
  const side = dir === 'side', front = dir === 'front', back = dir === 'back';

  if (hasCap && s >= 0.8) { // ribbons hang behind the head, so they go down first
    const m = back || side, cols = [P.blue, P.gold, P.green, P.crimsonLt], len = capOnly ? [5, 6, 5, 6] : [12, 15, 11, 13];
    cols.forEach((c, k) => { for (let j = 0; j < len[k]; j++) { const x = 21.5 + k + (j > 6 ? 1 : 0) + (j > 11 ? 1 : 0); p(m ? 27 - x : x + (side ? 1 : 0), 12 + j, c); } });
  }
  if (!capOnly) {
    if (side) { sp.ell(X(13.4), Y(26.6), R(7), R(7.8), P.peng); sp.ell(X(14.6), Y(17.6), R(5.9), R(6), P.peng); }
    else { sp.ell(X(14), Y(26.6), R(7.6), R(7.8), P.peng); sp.ell(X(14), Y(17.6), R(6.6), R(6), P.peng); }
    if (front) {
      sp.ell(X(14), Y(27.6), R(5), R(6), P.belly, 0, true);
      sp.ell(X(11.9), Y(18.3), R(2.6), R(2.9), P.belly, 0, true); sp.ell(X(16.1), Y(18.3), R(2.6), R(2.9), P.belly, 0, true);
    }
    if (side) { sp.ell(X(17.2), Y(27.6), R(4.1), R(5.8), P.belly, 0, true); sp.ell(X(18.4), Y(18.3), R(2.5), R(2.9), P.belly, 0, true); }
    if (side) { p(11, 13, P.pengLt); p(12, 12.5, P.pengLt); p(10, 14, P.pengLt); } else { p(10, 13, P.pengLt); p(11, 12.5, P.pengLt); p(9, 14, P.pengLt); }
    if (back) rect(13, 32, 2, 1.5, P.pengLt);

    // feet
    if (front || back) {
      const fc = front ? P.beak : P.beakDk, fh = front ? 1.6 : 1, base = front ? 33 : 33.6;
      rect(9, base - (pose === 'walk' ? 1 : 0), 3, fh, fc); rect(16, base - (pose === 'walk2' ? 1 : 0), 3, fh, fc);
    }
    if (side) {
      if (pose === 'walk') { rect(16, 33, 4, 1.6, P.beak); rect(8, 32.2, 3.5, 1.6, P.beakDk); }
      else if (pose === 'walk2') { rect(9.5, 33, 4, 1.6, P.beak); rect(15, 32.2, 3.5, 1.6, P.beakDk); }
      else { rect(14, 33, 4.5, 1.6, P.beak); rect(10, 33, 3, 1.6, P.beakDk); }
    }

    // flippers
    if (front || back) {
      let L = [6.4, 26.4, 2, 5, 0.25], Rr = [21.6, 26.4, 2, 5, -0.25];
      switch (pose) {
        case 'walk': L = [6.1, 26, 2, 5, 0.5]; break;
        case 'walk2': Rr = [21.9, 26, 2, 5, -0.5]; break;
        case 'cheer': L = [5.6, 19, 2, 5, -0.55]; Rr = [22.4, 19, 2, 5, 0.55]; break;
        case 'cheer2': L = [5, 17.4, 2, 5, -0.95]; Rr = [23, 17.4, 2, 5, 0.95]; break;
        case 'wave': Rr = [23, 18.5, 2, 5, 0.75]; break;
        case 'wave2': Rr = [23.4, 17.4, 2, 5, 1.15]; break;
        case 'waveL': L = [5, 18.5, 2, 5, -0.75]; break;
        case 'waveL2': L = [4.6, 17.4, 2, 5, -1.15]; break;
        case 'think': Rr = [18.8, 23, 1.8, 4.2, 0.95]; break;
        case 'flop': L = [5.2, 22, 2, 5, -1.05]; Rr = [22.8, 22, 2, 5, 1.05]; break;
        case 'hammer': Rr = [22.4, 18.6, 2, 5, 0.55]; break;
        case 'hammer2': Rr = [21.4, 23.5, 2, 5, -0.15]; break;
      }
      limb(...L); limb(...Rr);
    } else {
      const F = {
        shovel: [17.6, 24.6, 2, 4.8, -1.05], shovel2: [15.6, 26, 2, 4.8, -0.45], walk: [11.6, 25.6, 2, 5, -0.35], walk2: [12.8, 25.6, 2, 5, 0.3],
        browse: [17.4, 25.4, 2, 4.6, -0.6], browse2: [17.8, 24.4, 2, 4.6, -0.98], read: [17.2, 24.4, 2, 4.6, -1.0], read2: [17.2, 24.4, 2, 4.6, -1.0],
        peer: [17.4, 21.6, 1.8, 4.2, -1.45], tap: [18.4, 24.2, 2, 4.6, -1.3], tap2: [18, 25.8, 2, 4.6, -0.7],
      }[pose] || [13, 25.6, 2, 5, 0.15];
      limb(...F);
    }

    // face
    if (front) {
      if (pose === 'cheer' || pose === 'cheer2') { p(10, 18, P.ink); p(11, 17, P.ink); p(12, 18, P.ink); p(15, 18, P.ink); p(16, 17, P.ink); p(17, 18, P.ink); }
      else if (pose === 'flop') { for (const ex of [11, 16]) { p(ex - 1, 16.5, P.ink); p(ex + 1, 16.5, P.ink); p(ex, 17.5, P.ink); p(ex - 1, 18.5, P.ink); p(ex + 1, 18.5, P.ink); } }
      else if (blink) { p(10, 18.3, P.ink); p(11, 18.3, P.ink); p(16, 18.3, P.ink); p(17, 18.3, P.ink); }
      else if (pose === 'think') { p(11, 16.3, P.ink); p(11, 17.3, P.ink); p(16, 16.3, P.ink); p(16, 17.3, P.ink); }
      else { p(11, 17.3, P.ink); p(11, 18.3, P.ink); p(16, 17.3, P.ink); p(16, 18.3, P.ink); }
      if (['cheer', 'cheer2', 'wave', 'wave2', 'waveL', 'waveL2', 'flop'].includes(pose)) { rect(13, 19, 2, 1, P.beak); rect(13, 20, 2, 1, P.crimsonDk); rect(13, 21, 2, 1, P.beak); }
      else { rect(13, 19, 2, 1, P.beak); rect(13, 20, 2, 1, P.beakDk); }
      p(9, 20.3, P.blush); p(18, 20.3, P.blush);
    }
    if (side) {
      if (blink) { p(18, 18.3, P.ink); p(19, 18.3, P.ink); } else { p(18.5, 17.3, P.ink); p(18.5, 18.3, P.ink); }
      rect(20, 19, 3, 1, P.beak); rect(20, 20, 2, 1, P.beakDk); p(17, 20.3, P.blush);
    }

    // held things
    if (pose === 'shovel') {
      sp.line(X(14.5), Y(27.5), X(27), Y(21), P.woodDk); sp.line(X(14.5), Y(26.5), X(27), Y(20), P.wood);
      rect(26.5, 19, 5, 1, P.stoneLt); rect(26.5, 20, 5.5, 1.5, P.stone); rect(27.5, 21.4, 4.5, 1, P.stoneDk);
      p(27.5, 18, P.fire3); p(28.5, 17.6, P.fire2); p(29.5, 18, P.fire1); p(30.5, 18.2, P.fire3);
    }
    if (pose === 'shovel2') {
      sp.line(X(10), Y(30.5), X(21.5), Y(27), P.woodDk); sp.line(X(10), Y(29.5), X(21.5), Y(26), P.wood);
      rect(21, 25, 5, 1, P.stoneLt); rect(21, 26, 5.5, 1.5, P.stone); p(22, 24.2, P.woodXDk); p(23, 24, P.woodXDk); p(24, 24.2, P.woodXDk); p(25, 24.4, P.woodXDk);
    }
    if (pose === 'read' || pose === 'read2') {
      rect(19.5, 19, 7, 5, P.paper); rect(22.5, 19, 1, 5, P.paperDk); rect(19.5, 24, 7, 1, P.beak);
      if (pose === 'read2') rect(23.5, 16.5, 2, 2.5, P.cream);
    }
    if (pose === 'hammer') { sp.line(X(23.5), Y(15), X(25), Y(9), P.woodDk); rect(23, 6, 5, 3, P.stone); rect(23, 6, 5, 1, P.stoneLt); }
    if (pose === 'hammer2') { sp.line(X(21), Y(20), X(23), Y(16), P.woodDk); rect(20.5, 13.5, 5, 3, P.stone); rect(20.5, 13.5, 5, 1, P.stoneLt); }
  }

  if (hasCap) capOn(sp, X, Y, p, rect, side ? 1 : 0, back, cord);
  sp.outline();
  if (hasCap) capTrim(sp, X, Y, p, side ? 1 : 0, back);
  return sp;
}
function capOn(sp, X, Y, p, rect, dx, mirror, cord) {
  const r = (x, y, w, h, c) => rect(mirror ? 28 - x - w : x + dx, y, w, h, c);
  r(7, 11, 14, 3, P.fur); for (let x = 7; x < 21; x++) for (let y = 11; y < 14; y++) if ((x + y * 2) % 3 === 0) r(x, y, 1, 1, P.furLt);
  r(8, 10, 12, 1, cord);
  r(8, 9, 12, 1, P.crimsonDk); r(7, 8, 14, 1, P.crimson); r(6, 7, 16, 1, P.crimson); r(5, 6, 18, 1, P.crimson);
  r(5, 5, 18, 1, P.crimsonLt);
  r(5, 4, 2, 1, P.crimsonLt); r(21, 4, 2, 1, P.crimsonLt); r(5, 3, 1, 1, P.crimsonLt); r(22, 3, 1, 1, P.crimsonLt);
  r(18, 7, 3, 3, P.crimsonDk); r(19, 6, 3, 1, P.crimsonDk);
  for (const [tx, ty] of [[2, 1], [4.5, -1.2], [7.5, -2]]) { r(tx - 1, ty - 1, 3, 3, P.teal); r(tx, ty, 1, 1, P.blue); r(tx, ty - 1, 1, 1, P.gold); }
}
function capTrim(sp, X, Y, p, dx, mirror) {
  const pp = (x, y, c) => p(mirror ? 27 - x : x + dx, y, c);
  for (const [tx, ty] of [[2, 1], [4.5, -1.2], [7.5, -2]]) { const n = 8; for (let i = 1; i < n; i++) { const t = i / n; pp(tx + (8.5 - tx) * t, ty + 1.6 + (8 - ty - 1.6) * t, P.greenDk); } }
}
const pcache = new Map();
function pengC(o, flip = false) { const k = JSON.stringify(o) + flip; if (!pcache.has(k)) { let s = penguin(o); if (flip) s = s.flipX(); pcache.set(k, s.canvas()); } return pcache.get(k); }
function shadow(x, y, rx, ry = 2.4) { pxEll(x, y, rx, ry, P.ink, 0.16); }

// ---------------------------------------------------------------- props
function itemSpr(w, h, fn) { const s = new Spr(w, h); fn(s); return s.outline(); }
function plant() { return itemSpr(12, 14, s => { s.ell(4, 4, 3, 3, P.green); s.ell(7.5, 3.5, 3, 3, P.greenLt); s.ell(6, 6.5, 3.5, 2.5, P.green); s.set(5, 3, P.greenLt); s.rect(3, 8, 7, 5, P.orange); s.rect(3, 8, 7, 1, P.orangeDk); }); }
function workbench() {
  const s = new Spr(70, 36);
  s.rect(1, 1, 68, 11, P.woodLt); s.rect(1, 4, 68, 1, '#c79670'); s.rect(1, 8, 68, 1, '#c79670');
  s.rect(1, 12, 68, 12, P.wood); s.rect(1, 12, 68, 1, P.woodDk);
  for (const dx of [6, 40]) { s.rect(dx, 15, 22, 7, P.woodLt); s.rect(dx, 21, 22, 1, P.woodDk); s.rect(dx + 9, 18, 4, 1, P.woodDk); }
  s.rect(3, 24, 5, 11, P.woodDk); s.rect(62, 24, 5, 11, P.woodDk); s.rect(8, 30, 54, 2, P.woodDk);
  s.outline();
  s.stamp(itemSpr(18, 11, t => { t.rect(1, 1, 16, 8, P.paper); t.rect(1, 8, 16, 1, P.paperDk);
    [[3, 2, 4, P.orange], [8, 2, 5, P.ink], [3, 4, 2, P.blue], [6, 4, 8, P.ink], [5, 6, 4, P.green], [10, 6, 4, P.orange]].forEach(([x, y, w, c]) => t.rect(x, y, w, 1, c)); }), 23, 0);
  s.stamp(itemSpr(9, 9, t => { t.rect(1, 1, 5, 6, P.orange); t.rect(1, 1, 5, 1, P.orangeLt); t.set(6, 3, P.orange); t.set(7, 4, P.orange); t.set(6, 5, P.orange); }), 6, 1);
  s.stamp(itemSpr(12, 8, t => { t.rect(1, 1, 10, 6, P.paper); t.rect(1, 1, 10, 1, P.paperDk); }), 48, 1);
  return s;
}
function pegboard() {
  return itemSpr(56, 24, s => {
    s.rect(1, 1, 54, 22, P.woodLt);
    for (let y = 4; y < 22; y += 4) for (let x = 4; x < 54; x += 4) s.set(x, y, '#b88a63');
    s.line(6, 5, 6, 18, P.woodDk); s.rect(4, 4, 5, 3, P.stone);
    s.rect(13, 5, 12, 6, P.stoneLt); s.rect(13, 10, 12, 1, P.stoneDk); for (let x = 13; x < 25; x += 2) s.set(x, 11, P.stoneDk); s.rect(24, 4, 4, 7, P.orange);
    s.line(33, 4, 33, 18, P.stone); s.rect(31, 4, 5, 3, P.stone); s.set(33, 4, P.woodLt);
    s.rect(40, 4, 3, 16, P.gold); for (let y = 6; y < 20; y += 2) s.set(40, y, P.goldDk);
    s.ell(49, 10, 3.5, 3.5, P.blue); s.ell(49, 10, 1.5, 1.5, P.woodLt);
  });
}
function mapTable() {
  const s = new Spr(48, 32);
  s.rect(1, 1, 46, 14, P.woodDk); s.rect(3, 2, 42, 11, P.paper);
  s.ell(13, 7, 6.5, 3.6, P.greenLt, 0, true); s.ell(30, 6, 5, 3, P.greenLt, 0, true); s.ell(37, 10, 4, 2.2, P.greenLt, 0, true); s.ell(22, 10.5, 3, 1.6, P.blueLt, 0, true);
  [[9, 9], [12, 10], [15, 10], [18, 9], [21, 8], [24, 7], [27, 7], [30, 8], [33, 9]].forEach(([x, y]) => s.set(x, y, P.orangeDk));
  s.set(35, 8, P.red); s.set(37, 10, P.red); s.set(36, 9, P.red); s.set(35, 10, P.red); s.set(37, 8, P.red);
  s.rect(2, 15, 44, 4, P.wood); s.rect(2, 15, 44, 1, P.woodDk);
  s.rect(4, 19, 3, 12, P.woodDk); s.rect(41, 19, 3, 12, P.woodDk);
  s.outline();
  s.stamp(itemSpr(12, 12, t => { t.ell(4.5, 4.5, 3.6, 3.6, P.gold); t.ell(4.5, 4.5, 2.2, 2.2, '#cfe1ef'); t.set(3, 3, P.cream); t.line(7, 7, 10, 10, P.woodDk); }), 4, 1);
  return s;
}
function forge() {
  const s = new Spr(46, 52);
  s.rect(12, 0, 22, 12, P.stone); s.rect(2, 14, 42, 32, P.stone);
  for (let y = 3; y < 46; y += 5) { if (y > 11 && y < 15) continue; const x0 = y < 12 ? 12 : 2, x1 = y < 12 ? 34 : 44; s.rect(x0, y, x1 - x0, 1, P.stoneDk); const off = ((y / 5) | 0) % 2 ? 0 : 5; for (let x = x0 + off; x < x1; x += 10) s.rect(x, y + 1, 1, 4, P.stoneDk); }
  s.rect(0, 11, 46, 4, P.stoneLt); s.rect(0, 14, 46, 1, P.stoneDk);
  s.ell(23, 30, 11, 9, P.woodXDk); s.rect(12, 30, 22, 14, P.woodXDk);
  s.ell(23, 35, 9, 8, P.fire3, 0, true); s.rect(14, 35, 18, 9, P.fire3);
  s.ell(23, 38, 7, 6, P.fire2); s.ell(23, 41, 5, 3.5, P.fire1);
  s.rect(13, 42, 20, 2, P.woodXDk); [15, 18, 22, 25, 29].forEach(x => s.set(x, 42, P.fire3));
  s.rect(1, 46, 44, 5, P.stoneDk);
  return s.outline();
}
function coalBucket() { return itemSpr(14, 13, s => { s.rect(1, 4, 12, 8, P.stoneDk); s.rect(2, 11, 10, 1, P.ink); s.ell(7, 4, 6, 2.5, P.woodXDk); s.set(5, 3, P.fire3); s.set(8, 4, P.fire2); s.rect(1, 6, 12, 1, P.stone); }); }
function bookshelf(rnd) {
  const s = new Spr(38, 60);
  s.rect(1, 4, 36, 55, P.woodDk); s.rect(3, 6, 32, 50, P.woodXDk);
  const cols = [P.orange, P.blue, P.green, P.cream, P.crimson, P.gold, P.gray, P.orangeDk, P.blueDk, P.greenDk, P.paper, P.teal];
  [[6, 17], [19, 30], [32, 43], [45, 55]].forEach(([t, b]) => {
    let x = 3;
    while (x < 34) { const w = 2 + (rnd() * 2.2 | 0), h = (b - t) - (rnd() * 3.5 | 0), c = cols[rnd() * cols.length | 0];
      const ww = Math.min(w, 35 - x); s.rect(x, b - h, ww, h, c); s.rect(x, b - h + 1, 1, 1, P.cream); x += ww; if (rnd() < 0.08) x += 3; }
    s.rect(1, b, 36, 2, P.wood);
  });
  s.rect(0, 1, 38, 4, P.wood); s.rect(0, 1, 38, 1, P.woodLt);
  return s.outline();
}
function telescope() {
  const s = new Spr(34, 48);
  s.line(16, 25, 5, 46, P.woodDk); s.line(17, 25, 6, 46, P.woodDk); s.line(16, 25, 16, 46, P.wood); s.line(17, 25, 28, 46, P.woodDk); s.line(18, 25, 29, 46, P.woodDk);
  s.rect(14, 22, 5, 5, P.stoneDk);
  for (let i = 0; i <= 40; i++) { const t = i / 40; s.ell(7 + t * 19, 31 - t * 24, 2.4 + t * 0.8, 2.4 + t * 0.8, P.gold); }
  for (const t of [0.35, 0.7]) s.ell(7 + t * 19, 31 - t * 24, 3.2, 3.2, P.goldDk, 0, true);
  s.ell(26.5, 6.5, 3.8, 3.8, P.stoneLt); s.ell(26.8, 6.2, 2, 2, P.blueLt); s.rect(4, 31, 3, 3, P.stoneDk);
  return s.outline();
}
function helperDesk() {
  const s = new Spr(46, 30);
  s.rect(1, 1, 44, 10, P.woodLt); s.rect(1, 5, 44, 1, '#c79670');
  s.rect(1, 11, 44, 16, P.wood); s.rect(1, 11, 44, 1, P.woodDk);
  s.rect(5, 14, 16, 10, '#a3734d'); s.rect(25, 14, 16, 10, '#a3734d');
  s.rect(1, 27, 44, 2, P.woodDk);
  s.outline();
  s.stamp(itemSpr(12, 10, t => { t.ell(6, 6, 4.2, 3.6, P.gold); t.rect(1, 6, 10, 2, P.goldDk); t.rect(5, 1, 2, 2, P.goldDk); t.set(4, 4, P.cream); }), 28, -1);
  s.stamp(itemSpr(14, 9, t => { t.rect(1, 3, 11, 5, P.paperDk); t.rect(2, 2, 11, 5, P.paper); t.rect(4, 4, 6, 1, P.dim); }), 6, 0);
  return s;
}
function chairBack() { return itemSpr(42, 32, s => { s.ell(21, 11, 16, 10, P.green); s.rect(5, 11, 32, 20, P.green); s.rect(7, 4, 28, 1, P.greenLt);
  [[13, 10], [21, 8], [29, 10], [17, 16], [25, 16]].forEach(([x, y]) => s.set(x, y, P.greenDk)); }); }
function chairFront() { return itemSpr(42, 20, s => { s.ell(6, 6, 5.5, 5, P.green); s.rect(1, 6, 10, 9, P.green); s.ell(36, 6, 5.5, 5, P.green); s.rect(31, 6, 10, 9, P.green);
  s.rect(3, 2, 6, 1, P.greenLt); s.rect(33, 2, 6, 1, P.greenLt); s.rect(10, 9, 22, 6, P.greenLt); s.rect(1, 15, 40, 2, P.greenDk); s.rect(3, 17, 3, 2, P.woodDk); s.rect(36, 17, 3, 2, P.woodDk); }); }
function lamp() { return itemSpr(18, 48, s => { s.rect(8, 9, 2, 34, P.woodDk); s.ell(9, 44, 6, 2, P.woodDk);
  for (let y = 0; y < 9; y++) { const w = 6 + Math.round(y * 0.9); s.rect(9 - Math.floor(w / 2), y + 1, w, 1, y > 6 ? P.orange : P.paper); } }); }
function signPost() { return itemSpr(26, 44, s => { s.rect(11, 12, 4, 30, P.woodDk); s.rect(11, 12, 1, 30, P.wood);
  s.rect(1, 1, 24, 13, P.woodLt); s.rect(1, 13, 24, 1, P.wood); s.set(3, 3, P.stoneDk); s.set(22, 3, P.stoneDk); s.ell(13, 42, 6, 2, P.stoneDk); }); }
function oddJobs() {
  const s = new Spr(50, 38);
  const crate = (x, y, w, h) => { s.rect(x, y, w, h, P.woodLt); s.rect(x, y, w, 2, P.wood); s.rect(x, y + h - 2, w, 2, P.wood); s.rect(x, y, 2, h, P.wood); s.rect(x + w - 2, y, 2, h, P.wood); s.line(x + 2, y + h - 3, x + w - 3, y + 2, P.wood); };
  crate(2, 18, 20, 18); crate(5, 4, 15, 14);
  s.rect(26, 15, 14, 21, P.wood); s.ell(33, 15, 7, 2.5, P.woodDk); s.rect(26, 19, 14, 2, P.stoneDk); s.rect(26, 30, 14, 2, P.stoneDk); s.rect(29, 17, 2, 18, P.woodLt);
  s.rect(38, 28, 11, 8, P.red); s.rect(38, 28, 11, 1, P.orangeLt); s.rect(41, 26, 5, 2, P.stoneDk);
  return s.outline();
}

// ---------------------------------------------------------------- room (drawn once)
// opt.rug is the kilim's colour and opt.letter the arena's letter on the sign (the arenas scene, arenas.js)
function room(opt = {}) {
  const rnd = mulberry32(11), rugC = opt.rug ?? P.orange;
  fill(6, 44, 468, 182, P.floor);
  for (let y = 44; y < 226; y += 9) {
    let x = 6 - Math.floor(rnd() * 40);
    while (x < 474) {
      const len = 34 + Math.floor(rnd() * 44);
      fill(Math.max(6, x), y, Math.min(x + len, 474) - Math.max(6, x), 8, rnd() < 0.5 ? P.floor : P.floor2);
      if (x > 6) fill(x, y, 1, 8, P.seam);
      if (rnd() < 0.35) fill(Math.max(8, x + 6 + Math.floor(rnd() * (len - 12))), y + 2 + Math.floor(rnd() * 4), 2, 1, P.knot);
      x += len;
    }
    fill(6, y + 8, 468, 1, P.seam);
  }
  g.save(); g.globalAlpha = 0.12; fill(6, 44, 468, 4, P.wallTop); fill(6, 48, 468, 2, P.wallTop); fill(6, 44, 3, 182, P.wallTop); fill(471, 44, 3, 182, P.wallTop); g.restore();
  fill(0, 0, 480, 44, P.wall);
  for (let i = 0; i < 260; i++) px(6 + rnd() * 468, 5 + rnd() * 26, P.wallShade);
  // cobalt band with peacock-eye dots, like Boleslawiec pottery
  fill(0, 31, 480, 11, P.wainscot); fill(0, 31, 480, 1, P.wainscotDk); fill(0, 41, 480, 1, P.wainscotDk);
  for (let x = 8; x < 480; x += 14) { px(x, 34, P.cream); px(x - 1, 35, P.cream); px(x + 1, 35, P.cream); px(x, 36, P.cream); px(x, 35, P.gold); px(x, 38, P.greenLt); px(x + 7, 33, P.blueLt); px(x + 7, 36, P.cream); px(x + 7, 39, P.blueLt); }
  fill(0, 42, 480, 2, P.woodDk);
  fill(0, 0, 480, 4, P.wallTop);
  for (const [wx, moon] of [[118, true], [296, false]]) {
    fill(wx - 1, 9, 30, 21, P.woodDk); fill(wx, 10, 28, 19, P.woodLt); fill(wx + 2, 12, 24, 15, P.sky); fill(wx + 2, 21, 24, 6, P.skyLt);
    const r2 = mulberry32(wx); for (let i = 0; i < 7; i++) px(wx + 3 + r2() * 22, 13 + r2() * 9, P.cream);
    if (moon) { pxEll(wx + 20, 16, 3, 3, P.cream); pxEll(wx + 21.5, 15, 2.6, 2.6, P.sky); }
    fill(wx + 13, 10, 2, 19, P.woodLt); fill(wx, 19, 28, 1, P.woodLt);
    fill(wx - 3, 29, 34, 2, P.woodLt); fill(wx - 3, 31, 34, 1, P.woodDk);
  }
  fill(17, 12, 90, 15, P.woodXDk); fill(18, 13, 88, 13, P.woodDk); px(20, 15, P.gold); px(103, 15, P.gold);
  if (!opt.letter) text('AGENT WORKSHOP', Math.round(62 - textW('AGENT WORKSHOP', 'Silk', 8) / 2), 15, P.cream, 'Silk', 8);
  else { const w = textW('ARENA', 'Silk', 8), lw = textW(opt.letter, 'Silk', 8), bw = Math.max(11, lw + 6), x = Math.round(62 - (w + 4 + bw) / 2); text('ARENA', x, 15, P.cream, 'Silk', 8); box(x + w + 4, 14, bw, 11, rugC, P.ink, false); text(opt.letter, x + w + 4 + Math.floor((bw - lw) / 2), 16, P.cream, 'Silk', 8); }
  pxEll(178, 19, 7, 7, P.ink); pxEll(178, 19, 6, 6, P.cream); fill(178, 14, 1, 5, P.ink); fill(178, 19, 4, 1, P.ink); px(178, 19, P.orange);
  // flowers painted on the whitewash, Zalipie style
  const flower = (x, y, pet, mid) => { pxEll(x - 4, y + 5, 2.4, 1.2, P.green); pxEll(x + 4, y + 5, 2.4, 1.2, P.green); fill(x, y + 3, 1, 5, P.greenDk); pxEll(x, y, 3.6, 3.4, pet); pxEll(x, y, 1.6, 1.5, mid); px(x - 1, y - 2, P.cream); };
  const bud = (x, y, c) => { pxEll(x, y, 1.6, 1.6, c); px(x, y + 2, P.green); };
  [[162, 20, P.orange, P.gold], [198, 18, P.blue, P.gold], [282, 20, P.orange, P.gold], [346, 17, P.gold, P.orange], [366, 22, P.blue, P.cream], [418, 18, P.orange, P.gold]].forEach(([x, y, a, b]) => flower(x, y, a, b));
  [[154, 26, P.blue], [167, 11, P.gold], [190, 26, P.orange], [206, 12, P.orange], [290, 12, P.blue], [274, 27, P.gold], [356, 27, P.orange], [376, 12, P.orange], [424, 26, P.blue], [412, 10, P.gold]].forEach(([x, y, c]) => bud(x, y, c));
  draw(pegboard(), 212, 7);
  fill(383, 4, 24, 40, P.stone); for (let y = 8; y < 42; y += 5) { fill(383, y, 24, 1, P.stoneDk); fill(y % 10 ? 390 : 397, y + 1, 1, 4, P.stoneDk); } fill(382, 4, 1, 38, P.ink); fill(407, 4, 1, 38, P.ink);
  fill(428, 26, 36, 2, P.woodDk); draw(plant(), 430, 13); draw(plant(), 446, 13);
  const cols = [P.orange, P.cream, P.blue, P.green, P.gold];
  for (let x = 6, k = 0; x < 474; x += 9, k++) { const yy = 4 + Math.round(2 * Math.sin(Math.PI * ((x - 6) % 78) / 78)); px(x, yy, P.ink);
    if (x > 380 && x < 410) continue; for (let j = 0; j < 5; j++) fill(x + 1 + Math.floor(j / 2), yy + 1 + j, Math.max(1, 5 - j * 1), 1, cols[k % 5]); }
  for (let x = 6; x < 474; x++) { const yy = 4 + Math.round(2 * Math.sin(Math.PI * ((x - 6) % 78) / 78)); px(x, yy, P.wallTopLt); }
  // a kilim rug: navy border with a gold zigzag, red field, a chain of diamonds
  const cx = 240, cy = 146, w = 112, h = 48, x0 = cx - w / 2, y0 = cy - h / 2;
  fill(x0, y0 + 1, w, h - 2, P.ink); fill(x0 + 1, y0, w - 2, h, P.ink);
  fill(x0 + 1, y0 + 1, w - 2, h - 2, P.navy);
  fill(x0 + 7, y0 + 7, w - 14, h - 14, rugC);
  for (let x = x0 + 3; x < x0 + w - 3; x++) { const k = (x - x0) % 6, d = k < 3 ? k : 6 - k; px(x, y0 + 2 + d, P.gold); px(x, y0 + h - 3 - d, P.gold); }
  for (let y = y0 + 6; y < y0 + h - 6; y++) { const k = (y - y0) % 6, d = k < 3 ? k : 6 - k; px(x0 + 2 + d, y, P.gold); px(x0 + w - 3 - d, y, P.gold); }
  const diamond = (dx, ry, col) => { for (let yy = -ry; yy <= ry; yy++) { const hw = Math.round((ry - Math.abs(yy)) * 1.6); fill(cx + dx - hw, cy + yy, hw * 2 + 1, 1, col); } };
  for (const dx of [-32, 0, 32]) { const big = dx === 0; diamond(dx, big ? 12 : 8, P.navy); diamond(dx, big ? 9 : 6, P.gold); diamond(dx, big ? 6 : 4, P.cream); diamond(dx, big ? 3 : 2, rugC); }
  for (const [dx, dy] of [[-46, -11], [46, -11], [-46, 11], [46, 11]]) { px(cx + dx, cy + dy, P.cream); px(cx + dx - 1, cy + dy, P.gold); px(cx + dx + 1, cy + dy, P.gold); px(cx + dx, cy + dy - 1, P.gold); px(cx + dx, cy + dy + 1, P.gold); }
  for (let y = y0 + 3; y < y0 + h - 3; y += 2) { px(x0 - 1, y, P.cream); px(x0 + w, y, P.cream); }
  fill(0, 0, 6, 232, P.wallTop); fill(474, 0, 6, 232, P.wallTop); fill(5, 4, 1, 222, P.wallTopLt); fill(474, 4, 1, 222, P.wallTopLt);
  fill(0, 226, 480, 6, P.wallTop); fill(6, 226, 468, 1, P.wallTopLt);
  fill(306, 226, 34, 6, P.floor); fill(306, 226, 1, 6, P.wallTopLt); fill(339, 226, 1, 6, P.wallTopLt);
  fill(310, 219, 26, 9, P.greenDk); fill(311, 220, 24, 7, P.green); for (let x = 312; x < 334; x += 2) px(x, 223, P.greenDk);
}
