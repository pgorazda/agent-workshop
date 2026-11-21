// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// Runs in the baker page, after base.js, look.js and effects_src.js (tools/render-art.mjs loads them in a browser).
// bakeAll(spec) calls the drawing code of look.js for each picture in the variant table (variants.js) and gives back
// the pixels. It packs nothing and writes no file: the tool does that, in a fixed order.
//
// It adds no drawing of its own. Two things differ from the mockup, and both are checked:
//  1. A room is drawn with the text and the plate of its sign left out. The art code draws the sign, because the
//     letter of an arena changes. bakeAll draws the full room too, and fails if the baked room plus the sign is not
//     the same picture, pixel for pixel.
//  2. A letter of the pixel font is drawn by text() of look.js, one character at a time.

function bytesToBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function pixelsOf(canvas) {
  const data = canvas.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, canvas.width, canvas.height).data;
  return new Uint8Array(data.buffer, data.byteOffset, data.length);
}

function sprite(name, canvas, notes) {
  const rgba = pixelsOf(canvas);
  let partial = 0;
  for (let i = 3; i < rgba.length; i += 4) if (rgba[i] !== 0 && rgba[i] !== 255) partial++;
  if (partial) notes.push(`${name}: ${partial} pixels with a partial alpha value`);
  return { name, w: canvas.width, h: canvas.height, rgba: bytesToBase64(rgba) };
}

// ---------------------------------------------------------------- the sign of a room (look.js, lines 423 and 424)

/** Where the sign draws its text and its plate. The same arithmetic as room() in look.js. */
function signLayout(letter) {
  if (!letter) {
    const w = textW('AGENT WORKSHOP', 'Silk', 8);
    return { solo: true, text_x: Math.round(62 - w / 2), text_y: 15, text_w: w };
  }
  const w = textW('ARENA', 'Silk', 8), lw = textW(letter, 'Silk', 8), bw = Math.max(11, lw + 6), x = Math.round(62 - (w + 4 + bw) / 2);
  return { solo: false, text_x: x, text_y: 15, text_w: w, plate_x: x + w + 4, plate_y: 14, plate_w: bw, plate_h: 11, letter_x: x + w + 4 + Math.floor((bw - lw) / 2), letter_y: 16, letter_w: lw };
}

function drawSign(rug, letter) {
  const l = signLayout(letter);
  if (l.solo) text('AGENT WORKSHOP', l.text_x, l.text_y, P.cream, 'Silk', 8);
  else { text('ARENA', l.text_x, l.text_y, P.cream, 'Silk', 8); box(l.plate_x, l.plate_y, l.plate_w, l.plate_h, rug, P.ink, false); text(letter, l.letter_x, l.letter_y, P.cream, 'Silk', 8); }
}

/** A room with an empty sign board. room() calls text() and box() only for the sign, so both are switched off. */
function blankRoom(rug) {
  const realText = window.text, realBox = window.box;
  window.text = () => 0;
  window.box = () => {};
  try { return onCanvas(480, 232, () => room({ rug, letter: 'X' })); } finally { window.text = realText; window.box = realBox; }
}

function sameCanvas(a, b) {
  const p = pixelsOf(a), q = pixelsOf(b);
  if (p.length !== q.length) return false;
  for (let i = 0; i < p.length; i++) if (p[i] !== q[i]) return false;
  return true;
}

// ---------------------------------------------------------------- builders

const BUILDERS = {
  workbench: () => img(workbench()), mapTable: () => img(mapTable()), forge: () => img(forge()), coalBucket: () => img(coalBucket()),
  oddJobs: () => img(oddJobs()), telescope: () => img(telescope()), helperDesk: () => img(helperDesk()), chairBack: () => img(chairBack()),
  chairFront: () => img(chairFront()), lamp: () => img(lamp()), signPost: () => img(signPost()), plant: () => img(plant()),
  pegboard: () => img(pegboard()), cloud: () => img(cloud()), miniCloud: () => img(miniCloud()),
  // as the old mockup builds it: the bookshelf with a plant on top, drawn with the random numbers of seed 5
  shelf: () => { const rnd = mulberry32(5); return onCanvas(38, 60 + 12, () => { draw(bookshelf(rnd), 0, 12); draw(plant(), 19, 0); }); },
  candle: (wax) => candleSpr(wax),
  icon: (name) => onCanvas(7, 7, () => icon(name, 0, 0)),
  spark: (i) => onCanvas(SPARK[i].length, SPARK[i].length, () => bitmap(SPARK[i], 0, 0, '#ffffff')),
  miniStar: () => onCanvas(3, 3, () => bitmap(MINI_STAR, 0, 0, '#ffffff')),
  flame: (i) => flameC(i),
};

function penguinCanvas(s) {
  const spr = penguin(s.opts);
  if (s.piece === 'flop-body') return spr.rotCCW().crop().canvas();
  if (s.piece === 'cap') return spr.crop().canvas();
  return spr.canvas();
}

// ---------------------------------------------------------------- the app icon

/**
 * The head and the cap of the penguin on a rounded square. The penguin comes from penguin() of look.js, unchanged. The
 * art pixels are made bigger by whole numbers with no smoothing, so the file keeps hard edges.
 */
function appIconCanvas(icon, cordColor) {
  const art = new Spr(icon.cells, icon.cells), n = icon.cells, r = icon.corner;
  art.rect(0, 0, n, n, icon.background);
  for (let y = 0; y < r; y++) for (let x = 0; x < r; x++) {
    const dx = r - 0.5 - x, dy = r - 0.5 - y;
    if (dx * dx + dy * dy > r * r) { for (const [cx, cy] of [[x, y], [n - 1 - x, y], [x, n - 1 - y], [n - 1 - x, n - 1 - y]]) art.p[cy * n + cx] = null; }
  }
  const peng = penguin({ dir: 'front', pose: 'idle', cord: cordColor });
  const f = icon.from;
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    const c = peng.get(f.x + x, f.y + y);
    if (c) art.set(icon.at.x + x, icon.at.y + y, c);
  }
  const small = art.canvas(), big = document.createElement('canvas');
  big.width = big.height = n * icon.scale;
  const ctx = big.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(small, 0, 0, big.width, big.height);
  return big;
}

// ---------------------------------------------------------------- the pixel fonts

/**
 * Draws each character with text() and cuts the pixels out. The cell of a glyph is as wide as its advance and as
 * high as the highest and lowest ink of the whole font, so that the client can draw all glyphs on the same line.
 */
function bakeFont(font, chars, notes) {
  const O = 20, W = 64, H = 64; // the pen position inside the drawing canvas
  const drawn = [];
  let y0 = Infinity, y1 = -Infinity;
  for (const ch of chars) {
    let adv = 0;
    const canvas = onCanvas(W, H, () => { adv = text(ch, O, O, '#ffffff', font.family, font.size); });
    const px = pixelsOf(canvas);
    let ink = 0, x0g = Infinity, x1g = -Infinity;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      if (px[(y * W + x) * 4 + 3] === 0) continue;
      ink++; x0g = Math.min(x0g, x - O); x1g = Math.max(x1g, x - O); y0 = Math.min(y0, y - O); y1 = Math.max(y1, y - O);
    }
    if (ink && (x0g < 0 || x1g >= adv)) notes.push(`${font.id} "${ch}": ink from x=${x0g} to x=${x1g}, advance ${adv}: the cell cuts it`);
    if (!ink && ch !== ' ') notes.push(`${font.id} "${ch}" (U+${ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')}): no ink, the font has no glyph`);
    drawn.push({ ch, adv, px });
  }
  const h = y1 - y0 + 1;
  const glyphs = drawn.map(({ ch, adv, px }) => {
    const cell = new Uint8Array(adv * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < adv; x++) {
      const from = ((y0 + y + O) * W + (x + O)) * 4;
      cell.set(px.subarray(from, from + 4), (y * adv + x) * 4);
    }
    const canvas = document.createElement('canvas');
    canvas.width = adv; canvas.height = h;
    canvas.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(cell.buffer), adv, h), 0, 0);
    return { ch, adv, rgba: bytesToBase64(cell), canvas };
  });
  return { id: font.id, oy: y0, h, glyphs };
}

/**
 * Draws a text twice: with text() of look.js, and from the glyph cells, one after the other, as the client does.
 * Gives the number of pixels that text() draws and the cells do not (extra), and the opposite (missing).
 *
 * "extra" is not zero in every browser. text() draws a whole string with one fillText call, and the edges of two
 * neighbour letters, which are lighter than the threshold alone, can add up to ink in the one pixel gap between the
 * letters. Chrome on Windows does this; the mockup's own preview images have clean gaps, as the cells have.
 * "missing" must be zero: a pixel of a cell that text() does not draw would be a wrong glyph or a wrong place.
 * text() cuts a string at 476 pixels, so a longer string is not checked.
 */
function textDifference(font, baked, str) {
  const W = 600, H = 64, O = 20;
  const reference = onCanvas(W, H, () => { text(str, O, O, '#ffffff', font.family, font.size); });
  const mine = document.createElement('canvas');
  mine.width = W; mine.height = H;
  const ctx = mine.getContext('2d');
  const cells = new Map(baked.glyphs.map((gl) => [gl.ch, gl]));
  let pen = O;
  for (const ch of str) {
    const gl = cells.get(ch) ?? cells.get('?');
    ctx.drawImage(gl.canvas, pen, O + baked.oy);
    pen += gl.adv;
  }
  const p = pixelsOf(reference), q = pixelsOf(mine);
  let missing = 0, extra = 0;
  for (let i = 3; i < p.length; i += 4) { if (q[i] !== 0 && p[i] === 0) missing++; if (p[i] !== 0 && q[i] === 0) extra++; }
  return { missing, extra };
}

// ---------------------------------------------------------------- everything

async function bakeAll(spec) {
  const notes = [];
  if (JSON.stringify(Object.keys(ICON)) !== JSON.stringify(spec.iconNames)) throw new Error('the icon names of look.js differ from the variant table');
  if (SPARK.length !== spec.sparkCount || FLAMES.length !== spec.flameCount) throw new Error('the number of sparks or flames differs from the variant table');
  for (const f of spec.fonts) await document.fonts.load(`${f.size}px ${f.family}`, spec.chars);
  for (const f of spec.fonts) if (!document.fonts.check(`${f.size}px ${f.family}`, spec.chars)) throw new Error(`the font ${f.family} is not loaded`);

  const out = { sprites: [], fonts: [], widths: [], signs: [], notes, checked: {} };

  for (const s of spec.penguins) out.sprites.push(sprite(s.name, penguinCanvas(s), notes));
  for (const s of spec.props) out.sprites.push(sprite(s.name, BUILDERS[s.build](s.arg), notes));
  for (const s of spec.effects) out.sprites.push(sprite(s.name, BUILDERS[s.build](s.arg), notes));

  out.sprites.push(sprite(spec.appIcon.name, appIconCanvas(spec.appIcon, spec.appIcon.cordColor), notes));

  // rooms, and the check of the sign
  const letters = [null, ...spec.signNames];
  let signChecks = 0;
  for (const r of spec.rooms) {
    const blank = blankRoom(r.rug);
    out.sprites.push(sprite(r.name, blank, notes));
    for (const letter of letters) {
      const full = onCanvas(480, 232, () => room(letter ? { rug: r.rug, letter } : { rug: r.rug }));
      const composed = onCanvas(480, 232, () => { g.drawImage(blank, 0, 0); drawSign(r.rug, letter); });
      if (!sameCanvas(full, composed)) throw new Error(`${r.name}, sign "${letter ?? 'AGENT WORKSHOP'}": the baked room plus the sign differs from room()`);
      signChecks++;
    }
  }
  out.checked.signs = signChecks;
  for (const letter of letters) out.signs.push({ name: letter, ...signLayout(letter) });

  for (const f of spec.fonts) out.fonts.push(bakeFont(f, [...spec.chars], notes));

  // the width of each text: from the mockup's textW(), and from the sum of the advances of the glyphs
  for (const f of spec.fonts) {
    const adv = new Map(out.fonts.find((x) => x.id === f.id).glyphs.map((gl) => [gl.ch, gl.adv]));
    for (const str of spec.widthStrings) {
      out.widths.push({ font: f.id, text: str, js: textW(str, f.family, f.size), sum: [...str].reduce((a, ch) => a + (adv.get(ch) ?? adv.get('?')), 0) });
    }
  }

  // the glyph atlas against text(): the same pixels for every text of the table that text() can draw
  out.checked.texts = 0;
  out.checked.extraPixels = 0;
  out.checked.textsNotChecked = [];
  for (const f of spec.fonts) {
    const baked = out.fonts.find((x) => x.id === f.id);
    for (const str of spec.widthStrings) {
      if (textW(str, f.family, f.size) > 470) { out.checked.textsNotChecked.push(`${f.id}: ${str}`); continue; }
      const { missing, extra } = textDifference(f, baked, str);
      const ascii = /^[ -~]*$/.test(str);
      if (missing && ascii) throw new Error(`${f.id}: "${str}": ${missing} pixels of the glyph cells are not in the output of text()`);
      if (missing) notes.push(`${f.id}: "${str}" differs from text() (${missing} pixels missing): the font has fractional advances for these letters`);
      else out.checked.texts++;
      out.checked.extraPixels += extra;
    }
  }
  for (const f of out.fonts) for (const gl of f.glyphs) delete gl.canvas;
  return out;
}
