// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// Made from a file of the JavaScript mockup (removed, see the git history), so that look.js can run in the baker page
// (see tools/render-art.mjs). It is the only copy now.

// Shared set-up for the art code: the canvas and the seeded random numbers.

const CV = document.getElementById('c'), MAIN = CV.getContext('2d');
MAIN.imageSmoothingEnabled = false;
let g = MAIN;
function mulberry32(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
// what is drawn over every frame after the scene (the sound switch, from player.js). The recorder reads the
// finished frame from the canvas (record.mjs), so live playback does not encode a PNG for each frame.
const OVERLAYS = [];
// work that a scene does once the fonts are loaded, before the first frame (session.js runs it): for example,
// caches that would otherwise be filled in the middle of playback and make it stall
const WARMUPS = [];
function frameDone() { g = MAIN; for (const f of OVERLAYS) f(); }
