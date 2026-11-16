// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// The sound of Agent Workshop, made by code with Web Audio: no audio files. Four original tunes in the manner of
// Polish folk dances, on chiptune instruments:
//   krakowiak  the dance of the Krakow region: 2/4, lively, short-long-short syncopation; square-wave melody,
//              plucked bass, offbeat chords and a frame drum
//   kujawiak   slow and lyrical, 3/4, in A minor; a soft melody with vibrato over held chords
//   oberek     fast and whirling, 3/8, in D with a lydian G sharp; a thin fiddle-like pulse, the accent on the third beat
//   goralski   the highlands (Podhale): 2/4 in G lydian, with the raised fourth; a bowed open-fifth drone,
//              offbeat fiddle chords, phrases of five bars, and a stomp instead of a drum
// The event sounds: a hammer's tink, the desk bell, a flop, a chime when an agent asks for approval, and a
// fanfare when a turn is finished.
//
// The same code plays live (an AudioContext) and renders a clip's sound track (an OfflineAudioContext); noise is
// seeded, so a render is the same every time.
(function soundArt() {
const NOTE = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const midi = s => { const m = /^([A-G])(#?)(\d)$/.exec(s); return 12 * (+m[3] + 1) + NOTE[m[1]] + (m[2] ? 1 : 0); };
const hz = m => 440 * 2 ** ((m - 69) / 12);
const bar = s => s.split(' ').map(x => { const [n, d] = x.split(':'); return [n === '-' ? null : midi(n), +d]; });
// chords: the bass root, and the notes of the chord in the middle register
const CHORD = {
  G: [43, [59, 62, 67]], C: [48, [55, 60, 64]], D: [50, [57, 62, 66]], A: [45, [57, 61, 64]],
  a: [45, [57, 60, 64]], E: [40, [56, 59, 64]], d: [38, [57, 62, 65]], F: [41, [57, 60, 65]],
};

// ---------------------------------------------------------------- instruments
const cache = new WeakMap();
function kit(ctx) {
  if (cache.has(ctx)) return cache.get(ctx);
  const n = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate), d = n.getChannelData(0), r = mulberry32(11);
  for (let i = 0; i < d.length; i++) d[i] = r() * 2 - 1;
  const pulse = duty => { const re = new Float32Array(33), im = new Float32Array(33); for (let k = 1; k < 33; k++) re[k] = (2 / (k * Math.PI)) * Math.sin(k * Math.PI * duty); return ctx.createPeriodicWave(re, im); };
  const k = { noise: n, pulse25: pulse(0.25), pulse12: pulse(0.125) };
  cache.set(ctx, k); return k;
}
function tone(ctx, out, wave, f, at, dur, vol, { attack = 0.004, decay = 0.07, sustain = 0.55, release = 0.04, cutoff = 0, slide = 0, vibrato = 0 } = {}) {
  const o = ctx.createOscillator(), env = ctx.createGain();
  if (wave.startsWith('pulse')) o.setPeriodicWave(kit(ctx)[wave]); else o.type = wave;
  o.frequency.setValueAtTime(f, at);
  if (slide) o.frequency.exponentialRampToValueAtTime(f * slide, at + dur);
  if (vibrato) {   // a gentle vibrato that comes in after the attack, in cents
    const lfo = ctx.createOscillator(), depth = ctx.createGain();
    lfo.frequency.value = 5.2; depth.gain.setValueAtTime(0, at); depth.gain.linearRampToValueAtTime(f * (2 ** (vibrato / 1200) - 1), at + Math.min(0.25, dur));
    lfo.connect(depth).connect(o.frequency); lfo.start(at); lfo.stop(at + dur + release + 0.02);
  }
  decay = Math.min(decay, Math.max(0.001, dur - attack));
  env.gain.setValueAtTime(0, at); env.gain.linearRampToValueAtTime(vol, at + attack); env.gain.linearRampToValueAtTime(vol * sustain, at + attack + decay);
  env.gain.setValueAtTime(vol * sustain, at + dur); env.gain.linearRampToValueAtTime(0, at + dur + release);
  let node = o;
  if (cutoff) { const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = cutoff; o.connect(lp); node = lp; }
  node.connect(env).connect(out); o.start(at); o.stop(at + dur + release + 0.02);
}
function noise(ctx, out, at, dur, vol, band, q = 1.2) {
  const s = ctx.createBufferSource(), bp = ctx.createBiquadFilter(), env = ctx.createGain();
  s.buffer = kit(ctx).noise; bp.type = 'bandpass'; bp.frequency.value = band; bp.Q.value = q;
  env.gain.setValueAtTime(vol, at); env.gain.exponentialRampToValueAtTime(0.001, at + dur);
  s.connect(bp).connect(env).connect(out); s.start(at, (at * 7.31) % 0.5); s.stop(at + dur + 0.02);
}
function dum(ctx, out, at, vol) {   // the frame drum: a low thump that drops in pitch
  const o = ctx.createOscillator(), env = ctx.createGain();
  o.type = 'sine'; o.frequency.setValueAtTime(150, at); o.frequency.exponentialRampToValueAtTime(55, at + 0.12);
  env.gain.setValueAtTime(vol, at); env.gain.exponentialRampToValueAtTime(0.001, at + 0.28);
  o.connect(env).connect(out); o.start(at); o.stop(at + 0.3);
}
const pluck = (ctx, out, m, at, dur, vol = 0.5) => tone(ctx, out, 'triangle', hz(m), at, dur, vol, { decay: 0.2, sustain: 0.25 });
const stab = (ctx, out, notes, at, dur, vol, cutoff = 2200) => { for (const n of notes) tone(ctx, out, 'square', hz(n), at, dur, vol, { cutoff }); };

// ---------------------------------------------------------------- the tunes
// A tune: its metre (beats a bar, units a beat), its tempo, the melody (note:units, a bar per string), a chord
// a beat, the lead's sound for each time round, and its accompaniment for one bar (and for the intro).
const per = (sections, chords) => sections.flat().map(bar);
const TUNES = {
  krakowiak: {
    about: 'lively, 2/4', bpm: 138, beats: 2, perBeat: 2, intro: 2,
    melody: (() => {
      const A = ['D5:1 G5:2 D5:1', 'B4:1 G4:1 B4:1 D5:1', 'E5:1 C5:2 E5:1', 'D5:1 B4:1 A4:2', 'D5:1 G5:2 D5:1', 'B4:1 D5:1 G5:1 F#5:1', 'E5:1 C5:1 A4:1 F#4:1'];
      const B = ['F#5:1 A5:2 F#5:1', 'E5:1 D5:1 E5:1 F#5:1', 'G5:1 E5:2 C5:1', 'D5:1 B4:1 D5:2', 'F#5:1 A5:2 F#5:1', 'G5:1 F#5:1 E5:1 D5:1', 'C5:1 E5:1 A4:1 F#4:1'];
      return per([A, 'A4:1 F#4:1 D4:2', A, 'G4:1 B4:1 G4:2', B, 'A4:1 D5:1 F#5:2', B, 'G4:1 B4:1 G4:2']);
    })(),
    chords: (() => { const A = ['GG', 'GG', 'CC', 'DD', 'GG', 'GG', 'CD'], B = ['DD', 'DD', 'CC', 'GG', 'DD', 'GG', 'CD']; return [...A, 'DD', ...A, 'GG', ...B, 'DD', ...B, 'GG']; })(),
    lead: round => ({ wave: round % 2 ? 'pulse25' : 'square', vol: 0.22, gate: 0.86, cutoff: 3200 }),
    groove(ctx, out, chords, at, u, fill) {
      const FIFTH = { G: 50, C: 43, D: 45 };
      [...chords].forEach((c, beat) => {
        pluck(ctx, out, beat === 0 ? CHORD[c][0] : FIFTH[c], at + beat * 2 * u, u * 1.6);
        stab(ctx, out, { G: [59, 62, 67], C: [60, 64, 67], D: [62, 66, 69] }[c], at + (beat * 2 + 1) * u, u * 0.45, 0.045);
      });
      dum(ctx, out, at, 0.7); noise(ctx, out, at + u, 0.05, 0.22, 2600); dum(ctx, out, at + 2 * u, 0.35);
      if (fill) { noise(ctx, out, at + 3 * u, 0.04, 0.2, 3000); noise(ctx, out, at + 3.5 * u, 0.05, 0.28, 3000); } else noise(ctx, out, at + 3 * u, 0.06, 0.3, 2600);
    },
    introBar(ctx, out, at, u, last) { pluck(ctx, out, 43, at, u * 1.6); pluck(ctx, out, 50, at + 2 * u, u * 1.6); this.groove(ctx, out, '', at, u, last); },
  },
  kujawiak: {
    about: 'calm, 3/4', bpm: 84, beats: 3, perBeat: 2, intro: 1, level: 2.5,
    melody: per([
      ['E5:3 D5:1 C5:2', 'B4:2 C5:2 A4:2', 'C5:3 B4:1 A4:2', 'G#4:4 E4:2', 'E5:3 F5:1 E5:2', 'D5:2 C5:2 B4:2', 'C5:2 B4:2 G#4:2', 'A4:6'],
      ['G5:3 F5:1 E5:2', 'D5:2 E5:2 C5:2', 'F5:3 E5:1 D5:2', 'E5:4 C5:2', 'A5:3 G5:1 F5:2', 'E5:2 D5:2 C5:2', 'B4:2 D5:2 G#4:2', 'A4:6'],
    ]),
    chords: ['aaa', 'aaa', 'aaa', 'EEE', 'aaa', 'ddd', 'EEE', 'aaa', 'CCC', 'CCC', 'ddd', 'CCC', 'FFF', 'CCC', 'EEE', 'aaa'],
    lead: round => (round % 2 ? { wave: 'pulse25', vol: 0.16, gate: 0.95, cutoff: 1800, vibrato: 12 } : { wave: 'triangle', vol: 0.3, gate: 0.95, vibrato: 14 }),
    groove(ctx, out, chords, at, u) {
      const [root, notes] = CHORD[chords[0]], barLen = 6 * u;
      tone(ctx, out, 'triangle', hz(root), at, barLen * 0.7, 0.45, { attack: 0.01, decay: 0.4, sustain: 0.35, release: 0.3 });
      for (const n of notes) tone(ctx, out, 'triangle', hz(n), at, barLen * 0.92, 0.05, { attack: 0.18, decay: 0.3, sustain: 0.8, release: 0.25 });
      dum(ctx, out, at, 0.3); noise(ctx, out, at + 4 * u, 0.08, 0.1, 2200);
    },
    introBar(ctx, out, at, u) { this.groove(ctx, out, 'aaa', at, u); },
  },
  oberek: {
    about: 'fast, 3/8', bpm: 192, beats: 3, perBeat: 2, intro: 2, level: 2.5,
    melody: (() => {
      const A = ['A5:1 F#5:1 D5:1 F#5:1 A5:2', 'B5:1 A5:1 G#5:1 A5:1 F#5:2', 'E5:1 F#5:1 G5:1 E5:1 C#5:2', 'D5:2 A4:2 D5:2',
        'A5:1 F#5:1 D5:1 F#5:1 A5:2', 'B5:1 C#6:1 D6:1 B5:1 A5:2', 'G5:1 F#5:1 E5:1 C#5:1 A4:2', 'D5:4 -:2'];
      const B = ['F#5:2 G#5:1 A5:1 B5:2', 'A5:2 F#5:1 E5:1 D5:2', 'E5:2 F#5:1 G5:1 A5:2', 'G5:2 E5:1 C#5:1 A4:2',
        'F#5:2 G#5:1 A5:1 B5:2', 'D6:2 B5:1 A5:1 F#5:2', 'G5:1 E5:1 C#5:1 E5:1 A4:2', 'D5:4 -:2'];
      return per([A, A, B, B]);
    })(),
    chords: (() => { const A = ['DDD', 'DDD', 'AAA', 'DDD', 'DDD', 'GGG', 'AAA', 'DDD'], B = ['DDD', 'DDD', 'AAA', 'AAA', 'DDD', 'GGG', 'AAA', 'DDD']; return [...A, ...A, ...B, ...B]; })(),
    lead: round => ({ wave: round % 2 ? 'square' : 'pulse12', vol: round % 2 ? 0.2 : 0.27, gate: 0.8, cutoff: 3600 }),
    groove(ctx, out, chords, at, u) {
      const [root, notes] = CHORD[chords[0] || 'D'];
      pluck(ctx, out, root, at, u * 1.6, 0.55);
      stab(ctx, out, notes, at + 2 * u, u * 0.5, 0.04); stab(ctx, out, notes, at + 4 * u, u * 0.6, 0.06);   // the accent on the third beat
      dum(ctx, out, at, 0.6); noise(ctx, out, at + 2 * u, 0.04, 0.15, 2800); noise(ctx, out, at + 4 * u, 0.06, 0.3, 2600);
    },
    introBar(ctx, out, at, u) { this.groove(ctx, out, 'DDD', at, u); },
  },
  goralski: {
    label: 'góralski', about: 'highland', bpm: 120, beats: 2, perBeat: 2, intro: 2, level: 4.5,
    melody: (() => {
      const A = ['D5:1 E5:1 F#5:1 E5:1', 'D5:1 C#5:1 B4:1 A4:1', 'B4:1 C#5:1 D5:2', 'E5:1 C#5:1 A4:1 B4:1', 'G4:4'];
      const B = ['G5:1 F#5:1 E5:1 G5:1', 'F#5:1 E5:1 C#5:1 E5:1', 'D5:1 C#5:1 B4:1 D5:1', 'C#5:1 A4:1 B4:1 C#5:1', 'D5:2 G4:2'];
      return per([A, A, B, B]);
    })(),
    chords: (() => { const P = ['GG', 'AA', 'GG', 'AA', 'GG']; return [...P, ...P, ...P, ...P]; })(),
    lead: round => ({ wave: round % 2 ? 'square' : 'pulse12', vol: round % 2 ? 0.2 : 0.28, gate: 0.9, cutoff: round % 2 ? 2600 : 4000, vibrato: 9 }),
    groove(ctx, out, chords, at, u) {
      const barLen = 4 * u;
      for (const n of [43, 50]) tone(ctx, out, 'sawtooth', hz(n), at, barLen * 0.96, 0.07, { attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.06, cutoff: 700 });   // the drone, bowed again each bar
      [...(chords || 'GG')].forEach((c, beat) => stab(ctx, out, { G: [59, 62, 67], A: [57, 61, 64] }[c], at + (beat * 2 + 1) * u, u * 0.6, 0.05, 2400));
      dum(ctx, out, at, 0.35);
    },
    introBar(ctx, out, at, u) { this.groove(ctx, out, 'GG', at, u); },
  },
};
const unitOf = t => 60 / t.bpm / t.perBeat;
const barOf = name => { const t = TUNES[name]; return t ? unitOf(t) * t.beats * t.perBeat : 1; };
// schedules the music of a tune whose time lies in [from, to); music time `from` sounds at the context's time `when`
function music(ctx, out, from, to, when, name = 'krakowiak') {
  const tune = TUNES[name]; if (!tune) return;
  if (tune.level) { const lift = ctx.createGain(); lift.gain.value = 10 ** (tune.level / 20); lift.connect(out); out = lift; }   // in dB, to even out the tunes
  const u = unitOf(tune), BAR = barOf(name);
  for (let b = Math.max(0, Math.floor(from / BAR)); b * BAR < to; b++) {
    const t = b * BAR; if (t < from) continue;
    const at = when + (t - from);
    if (b < tune.intro) { tune.introBar(ctx, out, at, u, b === tune.intro - 1); continue; }
    const k = b - tune.intro, i = k % tune.melody.length, round = Math.floor(k / tune.melody.length), lead = tune.lead(round);
    let e = 0;
    for (const [n, d] of tune.melody[i]) {
      if (n != null) tone(ctx, out, lead.wave, hz(n), at + e * u, d * u * lead.gate, lead.vol, { cutoff: lead.cutoff, vibrato: d >= 2 ? lead.vibrato : 0 });
      e += d;
    }
    tune.groove(ctx, out, tune.chords[i], at, u, i % 8 === 7);
  }
}

// ---------------------------------------------------------------- the event sounds
const EFFECTS = {
  tink: (ctx, out, at) => { tone(ctx, out, 'triangle', 1760, at, 0.03, 0.35, { decay: 0.02, sustain: 0.3, release: 0.09 }); tone(ctx, out, 'sine', 2637, at, 0.02, 0.18, { release: 0.06 }); },
  bell: (ctx, out, at) => { for (const [m, v] of [[1, 0.35], [2.76, 0.16], [5.4, 0.08]]) tone(ctx, out, 'sine', 1318 * m, at, 0.02, v, { decay: 0.01, sustain: 1, release: 0.9 }); },
  flop: (ctx, out, at) => { tone(ctx, out, 'square', 330, at, 0.32, 0.18, { slide: 0.3, cutoff: 1400, decay: 0.1, sustain: 0.7, release: 0.06 }); dum(ctx, out, at + 0.3, 0.8); noise(ctx, out, at + 0.3, 0.12, 0.25, 600, 0.8); },
  chime: (ctx, out, at) => { tone(ctx, out, 'triangle', hz(81), at, 0.12, 0.4, { release: 0.15 }); tone(ctx, out, 'triangle', hz(86), at + 0.14, 0.2, 0.4, { release: 0.3 }); },
  fanfare: (ctx, out, at) => {
    [79, 83, 86, 91].forEach((n, i) => tone(ctx, out, 'square', hz(n), at + i * 0.09, 0.08, 0.16, { cutoff: 4000 }));
    for (const n of [79, 83, 86]) tone(ctx, out, 'square', hz(n), at + 0.4, 0.45, 0.1, { cutoff: 3000, sustain: 0.8, release: 0.25 });
  },
};
function effect(ctx, out, name, at) { EFFECTS[name]?.(ctx, out, at); }

// the mix: music under the event sounds, through a gentle limiter
function mixer(ctx, dest = ctx.destination) {
  const limit = ctx.createDynamicsCompressor(); limit.threshold.value = -10; limit.ratio.value = 6; limit.connect(dest);
  const musicOut = ctx.createGain(), sfxOut = ctx.createGain();
  musicOut.gain.value = 0.45; sfxOut.gain.value = 0.75;
  musicOut.connect(limit); sfxOut.connect(limit);
  return { music: musicOut, sfx: sfxOut, out: limit };
}
// the whole sound track of a clip, as a 16-bit mono WAV in base64: a tune (or none), and an effect for each cue
// (unless the event sounds are off)
async function render(duration, cues, { tune = 'krakowiak', events = true } = {}, rate = 44100) {
  const ctx = new OfflineAudioContext(1, Math.ceil(duration * rate), rate), mix = mixer(ctx);
  // schedule four seconds at a time, half a second ahead: with every note of a long clip in the graph at once,
  // rendering slows down with the square of the length
  const CHUNK = 4, part = from => {
    const to = Math.min(duration, from + CHUNK);
    music(ctx, mix.music, from, to, from, tune);
    if (events) for (const c of cues) if (c.t >= from && c.t < to) effect(ctx, mix.sfx, c.name, c.t);
  };
  part(0);
  for (let from = CHUNK; from < duration; from += CHUNK) ctx.suspend(from - 0.5).then(() => { part(from); ctx.resume(); });
  const pcm = (await ctx.startRendering()).getChannelData(0);
  const buf = new ArrayBuffer(44 + pcm.length * 2), v = new DataView(buf), str = (o, s) => [...s].forEach((ch, i) => v.setUint8(o + i, ch.charCodeAt(0)));
  str(0, 'RIFF'); v.setUint32(4, 36 + pcm.length * 2, true); str(8, 'WAVE'); str(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); str(36, 'data'); v.setUint32(40, pcm.length * 2, true);
  for (let i = 0; i < pcm.length; i++) v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, pcm[i])) * 32767, true);
  let bin = ''; const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
const LIST = Object.entries(TUNES).map(([name, t]) => ({ name, label: t.label ?? name, about: t.about }));
window.SoundArt = { music, effect, mixer, render, barOf, TUNES: LIST };
})();
