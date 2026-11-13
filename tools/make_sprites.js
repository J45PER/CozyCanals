// Designs the game's sprite set and renders it to assets/sprites/*.png.
//
//   node tools/make_sprites.js            (needs Playwright with Chromium)
//
// Each sprite is built as layered SVG in the game's isometric projection,
// given a hand-painted finish with SVG filters, and rasterised at 3x. The
// manifest (sprites.json) records each sprite's size and anchor: the point
// in the image that sits on the centre of its map cell, at ground level.
//
// To use your own artwork, replace any PNG with one of the same name. If the
// size or anchor differs, edit its entry in sprites.json (units are game
// pixels at 1x zoom; the PNG is `scale` times larger).

const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const OUT = path.join(__dirname, "..", "assets", "sprites");
const SCALE = 3;
const HW = 36, HH = 18;          // half a map cell on screen, in game pixels

// --- Small helpers -----------------------------------------------------------

/** Cell coordinates (a cell spans 0..1) and height -> sprite coordinates. */
const P = (x, y, z = 0) => [(x - y) * HW, (x + y - 1) * HH - z];

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
const toHex = (rgb) => "#" + rgb.map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")).join("");
const mix = (a, b, t) => toHex(hex(a).map((v, i) => v + (hex(b)[i] - v) * t));
const dark = (c, t) => mix(c, "#1d1712", t);
const light = (c, t) => mix(c, "#fff6e0", t);
const f2 = (n) => Math.round(n * 100) / 100;

const C = {
  honey: "#dcc48f", white: "#efe7d4", brick: "#b0604a", stone: "#bfb49b", cream: "#f3ead2", tar: "#3d3632",
  slate: "#5c6570", thatch: "#c6a25a", tile: "#a9553c", teal: "#4a968c", rust: "#9a5a3f",
  timber: "#3a2f27", wood: "#8a6a45", glass: "#f7e6a0", glassDay: "#b9d9de", frame: "#f6f0e0",
  leafD: "#4c7742", leafM: "#6a9a50", leafL: "#8dbb66", pineD: "#39624a", pineL: "#56855a",
  trunk: "#6b5138", grass: "#8fb066", shadow: "#20301a",
};

// --- Sprite canvas -----------------------------------------------------------

class Sprite {
  constructor(name, seed = 1) {
    this.name = name;
    this.back = [];           // drawn without the paint filter (shadows)
    this.els = [];
    this.defs = [];
    this.box = [Infinity, Infinity, -Infinity, -Infinity];
    this.smoke = null;
    this.rand = rng(seed * 7919 + name.length * 131);
    this.n = 0;
  }
  grow(x, y, pad = 0) {
    const b = this.box;
    b[0] = Math.min(b[0], x - pad); b[1] = Math.min(b[1], y - pad);
    b[2] = Math.max(b[2], x + pad); b[3] = Math.max(b[3], y + pad);
  }
  attrs(fill, o = {}) {
    const stroke = o.stroke === undefined ? dark(fill, 0.38) : o.stroke;
    let s = ` fill="${fill}"`;
    if (stroke) s += ` stroke="${stroke}" stroke-width="${o.sw ?? 0.45}" stroke-linejoin="round" stroke-linecap="round"`;
    if (o.opacity !== undefined) s += ` opacity="${o.opacity}"`;
    return s;
  }
  poly(pts, fill, o = {}) {
    pts.forEach((p) => this.grow(p[0], p[1], 1));
    this.els.push(`<polygon points="${pts.map((p) => f2(p[0]) + "," + f2(p[1])).join(" ")}"${this.attrs(fill, o)}/>`);
  }
  line(a, b, stroke, sw = 0.6, o = {}) {
    this.grow(a[0], a[1], sw); this.grow(b[0], b[1], sw);
    this.els.push(`<line x1="${f2(a[0])}" y1="${f2(a[1])}" x2="${f2(b[0])}" y2="${f2(b[1])}" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round"${o.opacity !== undefined ? ` opacity="${o.opacity}"` : ""}/>`);
  }
  curve(pts, stroke, sw = 0.6, o = {}) {
    pts.forEach((p) => this.grow(p[0], p[1], sw));
    const d = "M" + pts.map((p) => f2(p[0]) + " " + f2(p[1])).join(" L");
    this.els.push(`<path d="${d}" fill="none" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round"${o.opacity !== undefined ? ` opacity="${o.opacity}"` : ""}/>`);
  }
  oval(c, rx, ry, fill, o = {}) {
    this.grow(c[0] - rx, c[1] - ry, 1); this.grow(c[0] + rx, c[1] + ry, 1);
    this.els.push(`<ellipse cx="${f2(c[0])}" cy="${f2(c[1])}" rx="${f2(rx)}" ry="${f2(ry)}"${this.attrs(fill, o)}/>`);
  }
  /** Soft ground shadow under the object; x, y in cell coordinates. */
  shadow(x, y, rx, ry, strength = 0.3) {
    const c = P(x, y);
    this.grow(c[0] - rx - 3, c[1] - ry - 3); this.grow(c[0] + rx + 3, c[1] + ry + 3);
    this.back.push(`<ellipse cx="${f2(c[0])}" cy="${f2(c[1])}" rx="${f2(rx)}" ry="${f2(ry)}" fill="${C.shadow}" opacity="${strength}" filter="url(#blur)"/>`);
  }
  /** Two-stop gradient; returns a fill reference. */
  grad(a, b, x1 = 0, y1 = 0, x2 = 0, y2 = 1) {
    const id = `g${this.n++}`;
    this.defs.push(`<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`);
    return `url(#${id})`;
  }
  radial(a, b, cx = 0.62, cy = 0.3) {
    const id = `g${this.n++}`;
    this.defs.push(`<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="0.75"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></radialGradient>`);
    return `url(#${id})`;
  }
  svg() {
    const pad = 2;
    const x = Math.floor(this.box[0] - pad), y = Math.floor(this.box[1] - pad);
    const w = Math.ceil(this.box[2] + pad) - x, h = Math.ceil(this.box[3] + pad) - y;
    this.meta = { w, h, ax: -x, ay: -y };
    if (this.smoke) this.meta.smoke = [f2(this.smoke[0]), f2(this.smoke[1])];
    const seed = 1 + (this.name.length * 7 + this.name.charCodeAt(0)) % 40;
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${w * SCALE}" height="${h * SCALE}" viewBox="${x} ${y} ${w} ${h}">
<defs>
<filter id="blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="1.6"/></filter>
<filter id="paint" x="-4%" y="-4%" width="108%" height="108%" color-interpolation-filters="sRGB">
  <feTurbulence type="fractalNoise" baseFrequency="0.11" numOctaves="2" seed="${seed}" result="wob"/>
  <feDisplacementMap in="SourceGraphic" in2="wob" scale="0.9" xChannelSelector="R" yChannelSelector="G" result="ink"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.42" numOctaves="3" seed="${seed + 5}" result="grain"/>
  <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0.22  0 0 0 0 0.17  0 0 0 0 0.1  0.7 0 0 0 -0.3" result="speck"/>
  <feComposite in="speck" in2="ink" operator="in" result="specks"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="2" seed="${seed + 9}" result="wash"/>
  <feColorMatrix in="wash" type="matrix" values="0 0 0 0 1  0 0 0 0 0.97  0 0 0 0 0.86  0 0.5 0 0 -0.2" result="bloom"/>
  <feComposite in="bloom" in2="ink" operator="in" result="blooms"/>
  <feMerge><feMergeNode in="ink"/><feMergeNode in="blooms"/><feMergeNode in="specks"/></feMerge>
</filter>
${this.defs.join("\n")}
</defs>
${this.back.join("\n")}
<g filter="url(#paint)">
${this.els.join("\n")}
</g>
</svg>`;
  }
}

// --- Building kit ------------------------------------------------------------

// Coordinates on the two walls that face the camera.
const onL = (y) => (u, z) => P(u, y, z);   // wall along x at depth y (faces lower left)
const onR = (x) => (v, z) => P(x, v, z);   // wall along y at depth x (faces lower right)

function panel(s, f, a0, a1, z0, z1, fill, o) {
  s.poly([f(a0, z0), f(a1, z0), f(a1, z1), f(a0, z1)], fill, o);
}

function wallTexture(s, f, a0, a1, z0, z1, kind, base) {
  if (kind === "brick") {
    for (let z = z0 + 1.6; z < z1 - 0.5; z += 1.7) s.line(f(a0, z), f(a1, z), dark(base, 0.3), 0.22, { opacity: 0.55 });
    for (let i = 0; i < (a1 - a0) * (z1 - z0) * 1.6; i++) {
      const a = a0 + s.rand() * (a1 - a0 - 0.05), z = z0 + Math.floor(s.rand() * ((z1 - z0) / 1.7)) * 1.7;
      panel(s, f, a, a + 0.035, z + 0.2, Math.min(z + 1.5, z1), s.rand() > 0.5 ? dark(base, 0.16) : light(base, 0.14), { stroke: null, opacity: 0.6 });
    }
  } else if (kind === "stone") {
    for (let i = 0; i < (a1 - a0) * (z1 - z0) * 1.5; i++) {
      const a = a0 + s.rand() * (a1 - a0 - 0.06), z = z0 + s.rand() * (z1 - z0 - 2);
      panel(s, f, a, a + 0.03 + s.rand() * 0.03, z, z + 1 + s.rand(), s.rand() > 0.5 ? dark(base, 0.14) : light(base, 0.16), { stroke: dark(base, 0.3), sw: 0.15, opacity: 0.7 });
    }
  } else if (kind === "board") {
    for (let a = a0 + 0.045; a < a1 - 0.01; a += 0.045) s.line(f(a, z0), f(a, z1), dark(base, 0.45), 0.25, { opacity: 0.7 });
  } else if (kind === "timber") {
    const mid = z0 + (z1 - z0) * 0.5;
    s.line(f(a0, mid), f(a1, mid), C.timber, 0.9);
    const n = Math.max(2, Math.round((a1 - a0) / 0.14));
    for (let i = 0; i <= n; i++) s.line(f(a0 + (a1 - a0) * i / n, mid), f(a0 + (a1 - a0) * i / n, z1), C.timber, 0.8);
    for (let i = 0; i < n; i += 2) s.line(f(a0 + (a1 - a0) * i / n, mid), f(a0 + (a1 - a0) * (i + 1) / n, z1), C.timber, 0.6);
  }
}

function windowAt(s, f, a, z, o = {}) {
  const w = o.w ?? 0.085, h = o.h ?? 5.2, glass = o.glass ?? C.glass;
  panel(s, f, a - 0.012, a + w + 0.012, z - 0.9, z + h + 0.6, C.frame, { sw: 0.3 });
  panel(s, f, a, a + w, z, z + h, s.grad(light(glass, 0.3), dark(glass, 0.12)), { sw: 0.25, stroke: dark(glass, 0.5) });
  s.line(f(a + w / 2, z), f(a + w / 2, z + h), C.frame, 0.35);
  if (h > 4) s.line(f(a, z + h * 0.55), f(a + w, z + h * 0.55), C.frame, 0.35);
  if (o.box) {
    panel(s, f, a - 0.01, a + w + 0.01, z - 1.6, z - 0.6, C.wood, { sw: 0.2 });
    for (let i = 0; i < 4; i++) s.oval(f(a + w * (i + 0.5) / 4, z - 0.3), 0.9, 0.8, ["#e2604e", "#f1c84b", "#e98bb0", "#f6f0e0"][i], { stroke: null });
  }
}

function doorAt(s, f, a, col, o = {}) {
  const w = o.w ?? 0.1, h = o.h ?? 8.2;
  panel(s, f, a - 0.012, a + w + 0.012, 0, h + 0.8, C.frame, { sw: 0.3 });
  panel(s, f, a, a + w, 0, h, s.grad(light(col, 0.12), dark(col, 0.18)), { sw: 0.3 });
  s.oval(f(a + w * 0.78, h * 0.48), 0.45, 0.45, "#d9b25a", { stroke: null });
  if (o.step !== false) panel(s, f, a - 0.02, a + w + 0.02, -0.2, 0.7, C.stone, { sw: 0.2 });
}

function chimney(s, x, y, z0, z1, col = C.brick, smoke = true) {
  const e = 0.038;
  s.poly([P(x - e, y + e, z0), P(x + e, y + e, z0), P(x + e, y + e, z1), P(x - e, y + e, z1)], dark(col, 0.2));
  s.poly([P(x + e, y - e, z0), P(x + e, y + e, z0), P(x + e, y + e, z1), P(x + e, y - e, z1)], col);
  s.poly([P(x - e, y - e, z1), P(x + e, y - e, z1), P(x + e, y + e, z1), P(x - e, y + e, z1)], dark(col, 0.35));
  for (const d of [-0.016, 0.016]) s.oval(P(x + d, y - d, z1 + 1.6), 1.1, 1.7, "#c98f5f", { sw: 0.25 });
  if (smoke) s.smoke = P(x, y, z1 + 4);
}

function roofTexture(s, at, kind, base) {
  // `at(u, v)` maps the roof plane: u along the eaves, v from eaves (0) to ridge (1).
  if (kind === "thatch") {
    for (let i = 0; i < 46; i++) {
      const u = s.rand(), v = s.rand() * 0.85;
      s.line(at(u, v), at(u + (s.rand() - 0.5) * 0.02, v + 0.12), s.rand() > 0.5 ? dark(base, 0.22) : light(base, 0.25), 0.3, { opacity: 0.75 });
    }
    s.curve([at(0, 0.03), at(0.25, 0.0), at(0.5, 0.03), at(0.75, 0.0), at(1, 0.03)], dark(base, 0.35), 0.7);
  } else {
    const rows = kind === "tile" ? 7 : 6;
    for (let r = 1; r < rows; r++) s.line(at(0, r / rows), at(1, r / rows), dark(base, 0.32), 0.25, { opacity: 0.7 });
    for (let i = 0; i < 26; i++) {
      const u = s.rand() * 0.94, r = Math.floor(s.rand() * rows);
      s.poly([at(u, r / rows), at(u + 0.06, r / rows), at(u + 0.06, (r + 1) / rows), at(u, (r + 1) / rows)],
        s.rand() > 0.5 ? dark(base, 0.13) : light(base, 0.13), { stroke: null, opacity: 0.55 });
    }
  }
}

/**
 * A pitched-roof building. o: x0,y0,x1,y1 footprint; wh wall height; rh roof
 * height; ridge "x" or "y"; wall, wallTex; roof, roofTex; hip (true for a
 * hipped roof, ridge "x" only).
 */
function shell(s, o) {
  const { x0, y0, x1, y1, wh, rh } = o;
  const L = onL(y1), R = onR(x1);
  const wallL = s.grad(dark(o.wall, 0.1), dark(o.wall, 0.26));
  const wallR = s.grad(light(o.wall, 0.08), dark(o.wall, 0.08));
  panel(s, L, x0, x1, 0, wh, wallL);
  panel(s, R, y0, y1, 0, wh, wallR);
  wallTexture(s, L, x0, x1, 0, wh, o.wallTex, dark(o.wall, 0.18));
  wallTexture(s, R, y0, y1, 0, wh, o.wallTex, o.wall);
  // A darker plinth grounds the building.
  panel(s, L, x0, x1, 0, 1.1, dark(o.wall, 0.4), { stroke: null, opacity: 0.5 });
  panel(s, R, y0, y1, 0, 1.1, dark(o.wall, 0.3), { stroke: null, opacity: 0.5 });
  return { L, R };
}

function roof(s, o) {
  const { x0, y0, x1, y1, wh, rh } = o;
  const top = wh + rh, e = 0.05, drop = 1.8;
  const front = s.grad(light(o.roof, 0.14), dark(o.roof, 0.1));
  if (o.hip) {
    const ym = (y0 + y1) / 2, inset = Math.min((x1 - x0) * 0.28, (y1 - y0) / 2);
    s.poly([P(x0 - e, y0 - e, wh - drop), P(x1 + e, y0 - e, wh - drop), P(x1 - inset, ym, top), P(x0 + inset, ym, top)], dark(o.roof, 0.3));
    const atL = (u, v) => P((x0 - e) + (x1 - x0 + 2 * e) * u + ((x0 + inset) - (x0 - e) + ((x1 - inset) - (x1 + e) - ((x0 + inset) - (x0 - e))) * u) * v, y1 + e + (ym - y1 - e) * v, wh - drop + (top - wh + drop) * v);
    s.poly([P(x0 - e, y1 + e, wh - drop), P(x1 + e, y1 + e, wh - drop), P(x1 - inset, ym, top), P(x0 + inset, ym, top)], dark(o.roof, 0.1));
    roofTexture(s, atL, o.roofTex, dark(o.roof, 0.1));
    s.poly([P(x1 + e, y0 - e, wh - drop), P(x1 + e, y1 + e, wh - drop), P(x1 - inset, ym, top)], front);
    s.line(P(x0 + inset, ym, top), P(x1 - inset, ym, top), dark(o.roof, 0.45), 0.9);
    s.line(P(x1 - inset, ym, top), P(x1 + e, y1 + e, wh - drop), dark(o.roof, 0.4), 0.6);
    return;
  }
  if (o.ridge === "x") {
    const ym = (y0 + y1) / 2;
    s.poly([P(x0 - e, y0 - e, wh - drop), P(x1 + e, y0 - e, wh - drop), P(x1 + e, ym, top), P(x0 - e, ym, top)], dark(o.roof, 0.32));
    s.poly([P(x1, y0, wh), P(x1, y1, wh), P(x1, ym, top - 0.6)], s.grad(light(o.wall, 0.08), dark(o.wall, 0.05)));
    if (o.wallTex === "timber") { s.line(P(x1, ym, wh), P(x1, ym, top - 1), C.timber, 0.7); s.line(P(x1, y0 + 0.04, wh), P(x1, y1 - 0.04, wh), C.timber, 0.9); }
    const at = (u, v) => P(x0 - e + (x1 - x0 + 2 * e) * u, y1 + e + (ym - y1 - e) * v, wh - drop + (top - wh + drop) * v);
    s.poly([at(0, 0), at(1, 0), at(1, 1), at(0, 1)], s.grad(dark(o.roof, 0.02), dark(o.roof, 0.2)));
    roofTexture(s, at, o.roofTex, dark(o.roof, 0.1));
    s.line(at(1, 0), at(1, 1), light(o.roof, 0.2), 0.7);
    s.line(at(0, 1), at(1, 1), dark(o.roof, 0.45), 1.0);
  } else {
    const xm = (x0 + x1) / 2;
    s.poly([P(x0 - e, y0 - e, wh - drop), P(x0 - e, y1 + e, wh - drop), P(xm, y1 + e, top), P(xm, y0 - e, top)], dark(o.roof, 0.32));
    s.poly([P(x0, y1, wh), P(x1, y1, wh), P(xm, y1, top - 0.6)], s.grad(dark(o.wall, 0.1), dark(o.wall, 0.24)));
    if (o.wallTex === "timber") { s.line(P(xm, y1, wh), P(xm, y1, top - 1), C.timber, 0.7); s.line(P(x0 + 0.04, y1, wh), P(x1 - 0.04, y1, wh), C.timber, 0.9); }
    const at = (u, v) => P(x1 + e + (xm - x1 - e) * v, y0 - e + (y1 - y0 + 2 * e) * u, wh - drop + (top - wh + drop) * v);
    s.poly([at(0, 0), at(1, 0), at(1, 1), at(0, 1)], front);
    roofTexture(s, at, o.roofTex, o.roof);
    s.line(at(1, 0), at(1, 1), dark(o.roof, 0.3), 0.7);
    s.line(at(0, 1), at(1, 1), dark(o.roof, 0.45), 1.0);
  }
}

function plot(s, rx = 27, ry = 13.5, col = "#9fbb72") {
  s.oval(P(0.5, 0.5), rx, ry, col, { stroke: null, opacity: 0.38 });
}

function flowers(s, x0, x1, y, n = 6) {
  s.poly([P(x0, y), P(x1, y), P(x1, y + 0.07), P(x0, y + 0.07)], "#6f9450", { sw: 0.2 });
  const cols = ["#e98bb0", "#f1c84b", "#f6f0e0", "#c58ad6", "#e2604e"];
  for (let i = 0; i < n; i++) s.oval(P(x0 + (x1 - x0) * (i + 0.5) / n, y + 0.035, 1.6), 1.2, 1.1, cols[Math.floor(s.rand() * cols.length)], { stroke: null });
}

function bush(s, x, y, r = 3.4, col = C.leafM) {
  const c = P(x, y, r * 0.7);
  s.oval([c[0] - r * 0.5, c[1] + 0.6], r, r * 0.8, dark(col, 0.12), { sw: 0.3 });
  s.oval([c[0] + r * 0.5, c[1]], r, r * 0.85, s.radial(light(col, 0.25), col), { sw: 0.3 });
}

function table(s, x, y, parasol) {
  s.line(P(x, y), P(x, y, 3.8), C.timber, 0.5);
  s.oval(P(x, y, 3.8), 3.6, 1.8, C.frame, { sw: 0.3 });
  for (const d of [-0.07, 0.07]) s.oval(P(x + d, y - d * 0.4, 1.6), 1.2, 0.8, C.wood, { sw: 0.25 });
  if (parasol) {
    s.line(P(x, y, 3.8), P(x, y, 12), C.timber, 0.5);
    const c = P(x, y, 11);
    s.poly([[c[0] - 8, c[1] + 1.5], [c[0], c[1] - 5], [c[0] + 8, c[1] + 1.5], [c[0], c[1] + 4]], parasol, { sw: 0.35 });
    s.poly([[c[0], c[1] - 5], [c[0] + 8, c[1] + 1.5], [c[0], c[1] + 4]], light(parasol, 0.25), { sw: 0.3 });
    s.line([c[0], c[1] - 5], [c[0], c[1] + 4], dark(parasol, 0.3), 0.3);
  }
}

function hangingSign(s, x, y, col = "#2d5443") {
  s.line(P(x, y), P(x, y, 19), C.timber, 1.0);
  const c = P(x, y, 18.5);
  s.line(c, [c[0] - 8, c[1]], C.timber, 0.7);
  s.poly([[c[0] - 8.5, c[1] + 1], [c[0] - 1.5, c[1] + 1], [c[0] - 1.5, c[1] + 9], [c[0] - 8.5, c[1] + 9]], col, { sw: 0.4 });
  s.oval([c[0] - 5, c[1] + 5], 2.1, 2.1, "#f1c84b", { sw: 0.25 });
}

function awning(s, f, a0, a1, z, colA, colB = C.frame, out = 0.13) {
  // `f` is a wall; the awning slopes out and down from height z.
  const n = Math.max(4, Math.round((a1 - a0) / 0.07));
  const g = (a, t) => { const p = f(a, z - t * 3.6); const q = f === null ? p : p; return [p[0] + (f.side === "R" ? 1 : -1) * out * HW * t, p[1] + out * HH * t]; };
  for (let i = 0; i < n; i++) {
    const a = a0 + (a1 - a0) * i / n, b = a0 + (a1 - a0) * (i + 1) / n;
    s.poly([g(a, 0), g(b, 0), g(b, 1), g(a, 1)], i % 2 === 0 ? colA : colB, { sw: 0.25 });
  }
}
const wallL = (y) => Object.assign(onL(y), { side: "L" });
const wallR = (x) => Object.assign(onR(x), { side: "R" });

// --- Buildings ---------------------------------------------------------------

const B = {};

function cottage(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s);
    s.shadow(0.64, 0.68, 23, 10);
    const d = Object.assign({ x0: 0.24, y0: 0.3, x1: 0.76, y1: 0.7, wh: 12, rh: 11, ridge: "y", wallTex: "stone" }, o);
    shell(s, d);
    const L = onL(d.y1), R = onR(d.x1);
    doorAt(s, L, 0.455, d.door);
    windowAt(s, L, 0.29, 4, { box: o.boxes });
    windowAt(s, L, 0.63, 4, { box: o.boxes });
    windowAt(s, R, d.y0 + 0.14, 4.4);
    if (d.wh > 15) { windowAt(s, L, 0.3, 11.5, { h: 4 }); windowAt(s, L, 0.62, 11.5, { h: 4 }); windowAt(s, R, d.y0 + 0.14, 11.5, { h: 4 }); }
    roof(s, d);
    chimney(s, d.ridge === "y" ? 0.5 : 0.36, d.ridge === "y" ? 0.38 : 0.5, d.wh + d.rh * 0.45, d.wh + d.rh + 4);
    if (o.porch) {
      s.poly([P(0.42, 0.7, 9.5), P(0.6, 0.7, 9.5), P(0.6, 0.82, 8), P(0.42, 0.82, 8)], d.roof, { sw: 0.35 });
      s.line(P(0.43, 0.81), P(0.43, 0.81, 8), C.frame, 0.6); s.line(P(0.59, 0.81), P(0.59, 0.81, 8), C.frame, 0.6);
    }
    flowers(s, 0.24, 0.43, 0.715); flowers(s, 0.585, 0.76, 0.715);
    if (o.rose) for (let i = 0; i < 7; i++) s.oval(L(0.6 + s.rand() * 0.03, 1 + i * 1.6), 1.1, 1.0, i % 2 ? "#d8607a" : "#6f9450", { stroke: null });
    bush(s, 0.84, 0.86, 3.2);
    return s;
  };
}
cottage("cottage_a", { seed: 1, wall: C.honey, roof: C.thatch, roofTex: "thatch", door: "#5d7f9a", boxes: true });
cottage("cottage_b", { seed: 2, wall: C.white, wallTex: "plain", roof: C.thatch, roofTex: "thatch", door: "#5f8a5a", ridge: "x", rose: true, x0: 0.2, x1: 0.8, y0: 0.32, y1: 0.68 });
cottage("cottage_c", { seed: 3, wall: C.stone, roof: C.slate, roofTex: "slate", door: "#a8493a", porch: true });
cottage("cottage_d", { seed: 4, wall: "#bd6f55", wallTex: "brick", roof: C.tile, roofTex: "tile", door: "#2d5443", wh: 17, rh: 9, ridge: "x", x0: 0.27, x1: 0.73, y0: 0.32, y1: 0.68, boxes: true });

function terrace(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s, 31, 15);
    s.shadow(0.62, 0.7, 30, 11);
    const d = Object.assign({ x0: 0.08, y0: 0.34, x1: 0.92, y1: 0.66, wh: 16, rh: 9, ridge: "x" }, o);
    shell(s, d);
    const L = onL(d.y1), R = onR(d.x1);
    const doors = ["#a8493a", "#2f5d7a", "#3f7a55"];
    for (let i = 0; i < 3; i++) {
      const a = d.x0 + 0.02 + i * 0.28;
      doorAt(s, L, a + 0.02, doors[i], { w: 0.08, h: 7.4 });
      windowAt(s, L, a + 0.14, 2.6, { w: 0.08 });
      windowAt(s, L, a + 0.03, 10.4, { w: 0.07, h: 4.2 });
      windowAt(s, L, a + 0.15, 10.4, { w: 0.07, h: 4.2 });
      if (i > 0) s.line(L(a - 0.005, 0), L(a - 0.005, d.wh), dark(d.wall, 0.45), 0.4);
    }
    windowAt(s, R, d.y0 + 0.11, 3, { w: 0.08 }); windowAt(s, R, d.y0 + 0.11, 10.4, { w: 0.08, h: 4.2 });
    roof(s, d);
    for (let i = 0; i < 3; i++) chimney(s, d.x0 + 0.13 + i * 0.28, 0.48, d.wh + 5, d.wh + d.rh + 4, C.brick, i === 1);
    return s;
  };
}
terrace("terrace_a", { seed: 5, wall: "#b96a52", wallTex: "brick", roof: C.slate, roofTex: "slate" });
terrace("terrace_b", { seed: 6, wall: C.stone, wallTex: "stone", roof: C.tile, roofTex: "tile" });

function shop(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s);
    s.shadow(0.64, 0.68, 24, 10);
    const d = Object.assign({ x0: 0.22, y0: 0.26, x1: 0.78, y1: 0.68, wh: 17, rh: 9, ridge: "x" }, o);
    shell(s, d);
    const L = wallL(d.y1), R = wallR(d.x1);
    // Shopfront: fascia board, big window and a striped awning.
    panel(s, L, d.x0 + 0.02, d.x1 - 0.02, 8.6, 10.6, o.fascia, { sw: 0.3 });
    panel(s, L, d.x0 + 0.1, d.x1 - 0.1, 9.1, 10.1, C.frame, { stroke: null, opacity: 0.85 });
    doorAt(s, L, 0.62, o.fascia, { w: 0.1, h: 7.6 });
    panel(s, L, 0.27, 0.58, 1.6, 8, C.frame, { sw: 0.3 });
    panel(s, L, 0.285, 0.565, 2.3, 7.5, s.grad("#d6ecee", "#9cc4c9"), { sw: 0.25, stroke: "#55777c" });
    for (const a of [0.38, 0.47]) s.line(L(a, 2.3), L(a, 7.5), C.frame, 0.35);
    for (let i = 0; i < 5; i++) s.oval(L(0.31 + i * 0.055, 3.3), 1.3, 1.2, o.goods[i % o.goods.length], { stroke: null });
    awning(s, L, 0.25, 0.6, 8.6, o.stripe);
    windowAt(s, L, 0.3, 11.6, { h: 4 }); windowAt(s, L, 0.58, 11.6, { h: 4 });
    windowAt(s, R, d.y0 + 0.08, 3.5); windowAt(s, R, d.y0 + 0.24, 3.5); windowAt(s, R, d.y0 + 0.16, 11.6, { h: 4 });
    roof(s, d);
    chimney(s, 0.34, 0.47, d.wh + 4, d.wh + d.rh + 4);
    if (o.postbox) {
      const c = P(0.86, 0.84);
      s.poly([[c[0] - 2, c[1]], [c[0] + 2, c[1]], [c[0] + 2, c[1] - 9], [c[0] - 2, c[1] - 9]], "#c0392b", { sw: 0.35 });
      s.oval([c[0], c[1] - 9], 2.4, 1.3, "#d9483a", { sw: 0.3 });
      s.line([c[0] - 1.1, c[1] - 6.5], [c[0] + 1.1, c[1] - 6.5], "#1d1712", 0.5);
    } else {
      for (const [x, y] of [[0.84, 0.8], [0.9, 0.86]]) { s.poly([P(x - 0.03, y + 0.03, 0), P(x + 0.03, y + 0.03, 0), P(x + 0.03, y + 0.03, 3.4), P(x - 0.03, y + 0.03, 3.4)], C.wood, { sw: 0.3 }); s.oval(P(x, y, 3.8), 2.4, 1.3, "#d8a45a", { sw: 0.3 }); }
    }
    return s;
  };
}
shop("shop_a", { seed: 7, wall: C.cream, wallTex: "plain", roof: C.slate, roofTex: "slate", fascia: "#2d5443", stripe: "#3f7a55", goods: ["#e2604e", "#f1c84b", "#7fae5a"], postbox: true });
shop("shop_b", { seed: 8, wall: "#bd6f55", wallTex: "brick", roof: C.tile, roofTex: "tile", fascia: "#7a4a2a", stripe: "#c98f3f", goods: ["#d8a45a", "#c98f5f", "#e6c27a"] });

B.cafe_a = () => {
  const s = new Sprite("cafe_a", 9);
  plot(s);
  s.shadow(0.62, 0.64, 23, 10);
  const d = { x0: 0.26, y0: 0.24, x1: 0.74, y1: 0.64, wh: 12, rh: 8, ridge: "x", hip: true, wall: C.cream, wallTex: "plain", roof: C.teal, roofTex: "slate" };
  shell(s, d);
  const L = wallL(d.y1), R = wallR(d.x1);
  doorAt(s, L, 0.31, "#6b5138", { h: 7.6 });
  panel(s, L, 0.45, 0.71, 2.6, 8.8, C.frame, { sw: 0.3 });
  panel(s, L, 0.465, 0.695, 3.3, 8.2, s.grad("#d6ecee", "#9cc4c9"), { sw: 0.25, stroke: "#55777c" });
  s.line(L(0.58, 3.3), L(0.58, 8.2), C.frame, 0.35);
  windowAt(s, R, 0.36, 3.6, { w: 0.14, glass: C.glassDay });
  roof(s, d);
  awning(s, L, 0.26, 0.74, 11.4, "#d4604c");
  table(s, 0.34, 0.9, "#d4604c"); table(s, 0.62, 0.92, null); table(s, 0.9, 0.68, "#f1c84b");
  return s;
};

B.cafe_b = () => {
  const s = new Sprite("cafe_b", 10);
  plot(s);
  s.shadow(0.56, 0.58, 18, 8);
  const d = { x0: 0.3, y0: 0.26, x1: 0.66, y1: 0.56, wh: 10, rh: 6, ridge: "y", wall: "#7fa7a0", wallTex: "board", roof: "#e9dfc6", roofTex: "slate" };
  shell(s, d);
  const L = wallL(d.y1), R = wallR(d.x1);
  // Serving hatch with a counter, and bunting along the eaves.
  panel(s, R, 0.31, 0.51, 3.6, 8.4, "#2f3b3a", { sw: 0.3 });
  panel(s, R, 0.29, 0.53, 3.0, 3.9, C.wood, { sw: 0.3 });
  doorAt(s, L, 0.42, "#f3ead2", { h: 7.4, w: 0.09 });
  roof(s, d);
  awning(s, R, 0.28, 0.54, 9.4, "#e98bb0", C.frame, 0.1);
  const flags = ["#e2604e", "#f1c84b", "#5f9fb0", "#7fae5a"];
  for (let i = 0; i < 8; i++) { const p = L(0.31 + i * 0.045, 9.6 - Math.sin(i / 7 * Math.PI) * 1.2); s.poly([[p[0] - 1, p[1]], [p[0] + 1, p[1]], [p[0], p[1] + 2.2]], flags[i % 4], { sw: 0.15 }); }
  table(s, 0.3, 0.86, "#5f9fb0"); table(s, 0.6, 0.9, "#e2604e"); table(s, 0.88, 0.62, null);
  bush(s, 0.14, 0.6, 3);
  return s;
};

function pub(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s, 31, 15);
    s.shadow(0.66, 0.7, 30, 12);
    const d = Object.assign({ x0: 0.14, y0: 0.24, x1: 0.84, y1: 0.68, wh: 17, rh: 11, ridge: "x" }, o);
    shell(s, d);
    const L = wallL(d.y1), R = wallR(d.x1);
    if (o.upperTimber) {
      panel(s, L, d.x0, d.x1, 9, d.wh, s.grad(dark(C.white, 0.08), dark(C.white, 0.2)), { sw: 0.3 });
      panel(s, R, d.y0, d.y1, 9, d.wh, C.white, { sw: 0.3 });
      wallTexture(s, L, d.x0, d.x1, 9 - (d.wh - 9), d.wh, "timber");
      wallTexture(s, R, d.y0, d.y1, 9 - (d.wh - 9), d.wh, "timber");
    }
    doorAt(s, L, 0.44, o.door, { w: 0.11 });
    windowAt(s, L, 0.2, 2.6, { w: 0.13, box: true }); windowAt(s, L, 0.64, 2.6, { w: 0.13, box: true });
    if (d.wh > 14) { for (const a of [0.2, 0.44, 0.66]) windowAt(s, L, a, 11, { w: 0.1, h: 4.4 }); windowAt(s, R, d.y0 + 0.27, 11, { h: 4.4 }); }
    windowAt(s, R, d.y0 + 0.09, 3); windowAt(s, R, d.y0 + 0.27, 3);
    // Hanging baskets either side of the door.
    for (const a of [0.41, 0.585]) { s.oval(L(a, 8.2), 1.8, 1.3, "#6f9450", { sw: 0.2 }); s.oval(L(a, 9), 1.1, 0.9, "#e2604e", { stroke: null }); s.oval(L(a + 0.012, 8.6), 0.9, 0.8, "#f1c84b", { stroke: null }); }
    roof(s, d);
    chimney(s, 0.28, 0.42, d.wh + 6, d.wh + d.rh + 4.5);
    chimney(s, 0.7, 0.42, d.wh + 6, d.wh + d.rh + 3.5, C.brick, false);
    hangingSign(s, 0.94, 0.86, o.sign);
    table(s, 0.3, 0.9, o.parasol); table(s, 0.58, 0.93, null);
    return s;
  };
}
pub("pub_a", { seed: 11, wall: C.white, wallTex: "plain", upperTimber: true, roof: C.slate, roofTex: "slate", door: "#2d5443", sign: "#2d5443", parasol: "#d4604c" });
pub("pub_b", { seed: 12, wall: "#b96a52", wallTex: "brick", roof: C.tile, roofTex: "tile", hip: true, door: "#1f2f44", sign: "#1f2f44", parasol: "#3f7a55" });
pub("pub_c", { seed: 13, wall: C.white, wallTex: "plain", roof: C.thatch, roofTex: "thatch", wh: 12, rh: 13, door: "#7a2f2f", sign: "#7a2f2f", parasol: "#f1c84b" });

B.boatyard_a = () => {
  const s = new Sprite("boatyard_a", 14);
  plot(s, 31, 15, "#b9ad8c");
  s.shadow(0.6, 0.6, 28, 11);
  const d = { x0: 0.12, y0: 0.14, x1: 0.62, y1: 0.58, wh: 14, rh: 9, ridge: "y", wall: C.tar, wallTex: "board", roof: C.rust, roofTex: "slate" };
  shell(s, d);
  const L = wallL(d.y1), R = wallR(d.x1);
  // Big sliding doors, half open on a dark interior.
  panel(s, L, 0.2, 0.54, 0, 11, "#1b1816", { sw: 0.3 });
  panel(s, L, 0.2, 0.36, 0, 11, C.wood, { sw: 0.3 });
  for (const a of [0.24, 0.28, 0.32]) s.line(L(a, 0), L(a, 11), dark(C.wood, 0.4), 0.25);
  windowAt(s, R, 0.24, 6, { w: 0.2, h: 3.4, glass: C.glassDay });
  roof(s, d);
  // A hull on the stocks, a timber stack and a hand crane.
  const hull = [P(0.66, 0.9, 2), P(0.98, 0.72, 2), P(1.0, 0.66, 4.6), P(0.94, 0.62, 5), P(0.66, 0.78, 5), P(0.6, 0.84, 4.6)];
  s.poly(hull, "#7a5a3c", { sw: 0.4 });
  for (let i = 1; i < 5; i++) s.line(P(0.66 + i * 0.065, 0.9 - i * 0.036, 2.2), P(0.66 + i * 0.065, 0.8 - i * 0.036, 4.9), dark("#7a5a3c", 0.4), 0.3);
  for (const t of [0.7, 0.9]) s.line(P(t, 0.98 - t * 0.14), P(t, 0.92 - t * 0.14, 2), C.timber, 0.8);
  for (let i = 0; i < 3; i++) s.poly([P(0.1, 0.8 + i * 0.03, i * 1.2), P(0.36, 0.8 + i * 0.03, i * 1.2), P(0.36, 0.8 + i * 0.03, i * 1.2 + 1.2), P(0.1, 0.8 + i * 0.03, i * 1.2 + 1.2)], light(C.wood, 0.2 + i * 0.08), { sw: 0.25 });
  s.line(P(0.82, 0.4), P(0.82, 0.4, 20), C.timber, 1.3);
  s.line(P(0.82, 0.4, 19), P(1.0, 0.56, 24), C.timber, 1.0);
  s.line(P(0.82, 0.4, 8), P(0.94, 0.5, 21.5), C.timber, 0.6);
  s.line(P(1.0, 0.56, 24), P(1.0, 0.56, 12), "#2b2623", 0.35);
  s.oval(P(1.0, 0.56, 11), 1.2, 1.6, "#2b2623", { stroke: null });
  return s;
};

B.boatyard_b = () => {
  const s = new Sprite("boatyard_b", 15);
  plot(s, 31, 15, "#b9ad8c");
  s.shadow(0.62, 0.66, 29, 11);
  const d = { x0: 0.14, y0: 0.2, x1: 0.8, y1: 0.6, wh: 19, rh: 8, ridge: "x", wall: "#a9614b", wallTex: "brick", roof: C.slate, roofTex: "slate" };
  shell(s, d);
  const L = wallL(d.y1), R = wallR(d.x1);
  // Canal warehouse: loading doors on each floor, a hoist beam and a canopy.
  panel(s, L, 0.4, 0.54, 0, 8, "#4a3b2e", { sw: 0.3 }); panel(s, L, 0.4, 0.54, 10.4, 17, "#4a3b2e", { sw: 0.3 });
  for (const a of [0.2, 0.64]) { windowAt(s, L, a, 2.4, { glass: C.glassDay, h: 4.4 }); windowAt(s, L, a, 11, { glass: C.glassDay, h: 4.4 }); }
  windowAt(s, R, 0.28, 3, { glass: C.glassDay }); windowAt(s, R, 0.28, 11, { glass: C.glassDay });
  roof(s, d);
  s.line(L(0.47, 18), [L(0.47, 18)[0] - 6, L(0.47, 18)[1] + 3], C.timber, 1.0);
  s.line([L(0.47, 18)[0] - 5, L(0.47, 18)[1] + 3], [L(0.47, 18)[0] - 5, L(0.47, 18)[1] + 12], "#2b2623", 0.3);
  awning(s, L, 0.16, 0.78, 9.6, "#6b6f6a", "#7d817b", 0.16);
  for (const [x, y, c] of [[0.24, 0.84, "#8a6a45"], [0.34, 0.9, "#7a5a3c"], [0.3, 0.8, "#9a7a52"]]) {
    s.poly([P(x - 0.04, y + 0.04, 0), P(x + 0.04, y + 0.04, 0), P(x + 0.04, y + 0.04, 4.6), P(x - 0.04, y + 0.04, 4.6)], dark(c, 0.15), { sw: 0.3 });
    s.poly([P(x + 0.04, y - 0.04, 0), P(x + 0.04, y + 0.04, 0), P(x + 0.04, y + 0.04, 4.6), P(x + 0.04, y - 0.04, 4.6)], c, { sw: 0.3 });
    s.poly([P(x - 0.04, y - 0.04, 4.6), P(x + 0.04, y - 0.04, 4.6), P(x + 0.04, y + 0.04, 4.6), P(x - 0.04, y + 0.04, 4.6)], light(c, 0.2), { sw: 0.3 });
  }
  for (const [x, y] of [[0.62, 0.88], [0.72, 0.92]]) { s.oval(P(x, y, 2.2), 2.6, 3.2, "#7a5a3c", { sw: 0.35 }); s.oval(P(x, y, 5), 2.4, 1.3, "#9a7a52", { sw: 0.3 }); s.line(P(x - 0.035, y, 2.6), P(x + 0.035, y, 2.6), "#2b2623", 0.4); }
  return s;
};

function windmill(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s);
    s.shadow(0.6, 0.6, 20, 9);
    // Tapering round tower.
    const base = P(0.5, 0.5), r0 = 13.5, r1 = 8, h = 36;
    const body = [];
    for (let i = 0; i <= 12; i++) { const a = Math.PI * i / 12; body.push([base[0] + Math.cos(a) * r0, base[1] + Math.sin(a) * r0 * 0.5]); }
    for (let i = 12; i >= 0; i--) { const a = Math.PI * i / 12; body.push([base[0] + Math.cos(a) * r1, base[1] - h + Math.sin(a) * r1 * 0.5]); }
    s.poly(body, s.grad(dark(o.wall, 0.28), light(o.wall, 0.1), 0, 0, 1, 0), { sw: 0.5 });
    if (o.brick) for (let z = 2; z < h; z += 2) { const t = z / h, r = r0 + (r1 - r0) * t; const row = []; for (let i = 0; i <= 10; i++) { const a = Math.PI * i / 10; row.push([base[0] + Math.cos(a) * r, base[1] - z + Math.sin(a) * r * 0.5]); } s.curve(row, dark(o.wall, 0.4), 0.2, { opacity: 0.5 }); }
    for (const [dx, z] of [[-3, 5], [3.5, 15], [-2, 25]]) { s.poly([[base[0] + dx - 1.6, base[1] - z + 6], [base[0] + dx + 1.6, base[1] - z + 6.5], [base[0] + dx + 1.6, base[1] - z + 1.5], [base[0] + dx - 1.6, base[1] - z + 1]], dx === -3 && z === 5 ? "#5a4632" : "#2f3b44", { sw: 0.3 }); }
    // Gallery and cap.
    s.oval([base[0], base[1] - h], r1 + 1.5, (r1 + 1.5) * 0.5, dark(o.cap, 0.2), { sw: 0.4 });
    const cap = [[base[0] - r1 - 1, base[1] - h], [base[0] - r1 + 1, base[1] - h - 6], [base[0], base[1] - h - 10], [base[0] + r1 - 1, base[1] - h - 6], [base[0] + r1 + 1, base[1] - h]];
    s.poly(cap, s.grad(dark(o.cap, 0.2), light(o.cap, 0.15), 0, 0, 1, 0), { sw: 0.5 });
    // Sails on the camera side.
    const hub = [base[0] + 6, base[1] - h - 2];
    for (let k = 0; k < 4; k++) {
      const a = 0.5 + k * Math.PI / 2, ux = Math.cos(a), uy = Math.sin(a), nx = -uy, ny = ux;
      const p = (t, w) => [hub[0] + ux * t + nx * w, hub[1] + (uy * t + ny * w) * 0.92];
      s.line(p(0, 0), p(27, 0), C.timber, 0.9);
      s.poly([p(6, 0.6), p(26, 0.6), p(26, 5.5), p(6, 5.5)], "#f3ecd8", { sw: 0.35, opacity: 0.92 });
      for (let t = 9; t < 26; t += 3.4) s.line(p(t, 0.6), p(t, 5.5), "#8a7a66", 0.3);
      s.line(p(6, 3), p(26, 3), "#8a7a66", 0.3);
    }
    s.oval(hub, 2, 2, C.timber, { sw: 0.3 });
    bush(s, 0.18, 0.72, 3.2); bush(s, 0.86, 0.8, 2.8);
    return s;
  };
}
windmill("windmill_a", { seed: 16, wall: "#efe7d4", cap: "#3d3632" });
windmill("windmill_b", { seed: 17, wall: "#b0604a", cap: "#efe7d4", brick: true });

function church(name, o) {
  B[name] = () => {
    const s = new Sprite(name, o.seed);
    plot(s, 31, 15);
    s.shadow(0.64, 0.68, 30, 12);
    const wall = o.wall;
    const nave = { x0: 0.38, y0: 0.32, x1: 0.9, y1: 0.66, wh: 14, rh: 11, ridge: "x", wall, wallTex: "stone", roof: C.slate, roofTex: "slate" };
    shell(s, nave);
    const L = onL(0.66), R = onR(0.9);
    for (const a of [0.46, 0.61, 0.76]) {
      panel(s, L, a, a + 0.065, 3, 9.6, s.grad("#6f8fb0", "#33506e"), { sw: 0.3, stroke: dark(wall, 0.5) });
      s.oval(L(a + 0.0325, 9.6), 1.9, 2.3, "#5d7fa3", { sw: 0.3, stroke: dark(wall, 0.5) });
      s.line(L(a + 0.0325, 3), L(a + 0.0325, 11), dark(wall, 0.5), 0.3);
    }
    panel(s, R, 0.43, 0.55, 4, 11.5, s.grad("#c9a0b8", "#5d7fa3"), { sw: 0.3, stroke: dark(wall, 0.5) });
    s.oval(R(0.49, 11.5), 3.0, 2.6, "#d8b46a", { sw: 0.3, stroke: dark(wall, 0.5) });
    roof(s, nave);
    // Tower.
    const th = o.spire ? 30 : 34;
    const tw = { x0: 0.12, y0: 0.34, x1: 0.4, y1: 0.64, wh: th, rh: 0, wall: dark(wall, 0.04), wallTex: "stone" };
    shell(s, tw);
    const TL = onL(0.64), TR = onR(0.4);
    doorAt(s, TL, 0.215, "#5a4632", { w: 0.09, h: 7.6, step: false });
    s.oval(TL(0.26, 7.6), 2.2, 2.4, "#5a4632", { sw: 0.3 });
    panel(s, TL, 0.225, 0.295, th - 12, th - 5, "#2f343b", { sw: 0.3 }); panel(s, TR, 0.455, 0.525, th - 12, th - 5, "#2f343b", { sw: 0.3 });
    s.oval(TL(0.26, th - 17), 2.5, 2.5, C.frame, { sw: 0.4, stroke: C.timber });
    s.line(TL(0.26, th - 17), TL(0.26, th - 15.4), C.timber, 0.4); s.line(TL(0.26, th - 17), TL(0.275, th - 17.4), C.timber, 0.4);
    s.poly([P(0.12, 0.34, th), P(0.4, 0.34, th), P(0.4, 0.64, th), P(0.12, 0.64, th)], dark(wall, 0.22), { sw: 0.4 });
    if (o.spire) {
      const tip = P(0.26, 0.49, th + 30);
      s.poly([P(0.13, 0.63, th), P(0.39, 0.63, th), tip], dark("#6a7a6a", 0.15), { sw: 0.4 });
      s.poly([P(0.39, 0.35, th), P(0.39, 0.63, th), tip], light("#6a7a6a", 0.12), { sw: 0.4 });
      s.line(tip, [tip[0], tip[1] - 4], "#d9b25a", 0.6); s.line([tip[0] - 1.5, tip[1] - 2.6], [tip[0] + 1.5, tip[1] - 2.6], "#d9b25a", 0.6);
    } else {
      for (const [x, y] of [[0.12, 0.34], [0.34, 0.34], [0.12, 0.58], [0.34, 0.58], [0.23, 0.58], [0.34, 0.46]]) {
        s.poly([P(x, y + 0.06, th), P(x + 0.06, y + 0.06, th), P(x + 0.06, y + 0.06, th + 3.4), P(x, y + 0.06, th + 3.4)], dark(wall, 0.16), { sw: 0.3 });
        s.poly([P(x + 0.06, y, th), P(x + 0.06, y + 0.06, th), P(x + 0.06, y + 0.06, th + 3.4), P(x + 0.06, y, th + 3.4)], wall, { sw: 0.3 });
      }
      s.line(P(0.26, 0.49, th), P(0.26, 0.49, th + 9), C.timber, 0.5);
      s.poly([P(0.26, 0.49, th + 9), P(0.26, 0.49, th + 6), [P(0.26, 0.49, th + 7.5)[0] + 5, P(0.26, 0.49, th + 7.5)[1]]], "#c0392b", { sw: 0.2 });
    }
    // Churchyard.
    for (const [x, y] of [[0.5, 0.82], [0.62, 0.87], [0.74, 0.8], [0.84, 0.88]]) { const g = P(x, y); s.poly([[g[0] - 1.7, g[1]], [g[0] + 1.7, g[1]], [g[0] + 1.7, g[1] - 4], [g[0], g[1] - 5.4], [g[0] - 1.7, g[1] - 4]], "#a9a89f", { sw: 0.3 }); }
    pineShape(s, 0.16, 0.88, 0.7, "#35523d");
    return s;
  };
}
church("church_a", { seed: 18, wall: "#cdbf9f" });
church("church_b", { seed: 19, wall: "#b9b4a4", spire: true });

function haybale(s, x, y) {
  const q = P(x, y);
  s.poly([[q[0] - 5, q[1] - 8], [q[0] + 4, q[1] - 6], [q[0] + 4, q[1] + 1], [q[0] - 5, q[1] - 1]], "#cdb163", { sw: 0.35 });
  s.oval([q[0] + 4, q[1] - 2.5], 3, 4, "#e2c877", { sw: 0.35 });
  s.oval([q[0] + 4, q[1] - 2.5], 1.2, 1.7, "#c9ac5e", { stroke: null });
}

function fence(s, a, b, n = 4) {
  for (const z of [2, 4]) s.line(P(a[0], a[1], z), P(b[0], b[1], z), "#8a6a45", 0.5);
  for (let i = 0; i < n; i++) { const t = i / (n - 1); s.line(P(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), P(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 5.4), "#6b5138", 0.8); }
}

B.farm_a = () => {
  const s = new Sprite("farm_a", 20);
  plot(s, 31, 15, "#b4b07c");
  s.shadow(0.62, 0.7, 30, 12);
  const barn = { x0: 0.1, y0: 0.14, x1: 0.56, y1: 0.52, wh: 15, rh: 10, ridge: "y", wall: C.tar, wallTex: "board", roof: C.tile, roofTex: "tile" };
  shell(s, barn);
  const BL = onL(0.52);
  panel(s, BL, 0.24, 0.42, 0, 11, "#7a5a3c", { sw: 0.3 });
  s.line(BL(0.33, 0), BL(0.33, 11), C.tar, 0.4); s.line(BL(0.24, 0), BL(0.33, 11), C.tar, 0.3); s.line(BL(0.42, 0), BL(0.33, 11), C.tar, 0.3);
  roof(s, barn);
  const house = { x0: 0.56, y0: 0.42, x1: 0.92, y1: 0.74, wh: 12, rh: 9, ridge: "x", wall: "#bd6f55", wallTex: "brick", roof: C.slate, roofTex: "slate" };
  shell(s, house);
  const L = onL(0.74), R = onR(0.92);
  doorAt(s, L, 0.7, C.frame, { w: 0.08, h: 7.6 });
  windowAt(s, L, 0.6, 3.6, { w: 0.07 }); windowAt(s, L, 0.82, 3.6, { w: 0.07 }); windowAt(s, R, 0.53, 3.8);
  roof(s, house);
  chimney(s, 0.66, 0.52, 16, 24);
  haybale(s, 0.22, 0.8); haybale(s, 0.38, 0.88);
  fence(s, [0.06, 0.6], [0.06, 0.96]);
  return s;
};

B.farm_b = () => {
  const s = new Sprite("farm_b", 21);
  plot(s, 31, 15, "#b4b07c");
  s.shadow(0.62, 0.7, 30, 12);
  const barn = { x0: 0.08, y0: 0.2, x1: 0.7, y1: 0.52, wh: 12, rh: 9, ridge: "x", wall: C.stone, wallTex: "stone", roof: C.tile, roofTex: "tile" };
  shell(s, barn);
  const L = onL(0.52), R = onR(0.7);
  for (const a of [0.14, 0.34, 0.54]) { panel(s, L, a, a + 0.11, 0, 8.4, "#2b2623", { sw: 0.3 }); panel(s, L, a, a + 0.055, 0, 4.4, "#7a5a3c", { sw: 0.25 }); }
  windowAt(s, R, 0.31, 4, { glass: C.glassDay });
  roof(s, barn);
  // Open Dutch barn stacked with hay.
  const dx0 = 0.6, dy0 = 0.62, dx1 = 0.94, dy1 = 0.9;
  for (const [x, y] of [[dx0, dy1], [dx1, dy1], [dx1, dy0]]) s.line(P(x, y), P(x, y, 13), C.timber, 0.9);
  s.poly([P(dx0 + 0.02, dy1 - 0.02, 0), P(dx1 - 0.02, dy1 - 0.02, 0), P(dx1 - 0.02, dy1 - 0.02, 9), P(dx0 + 0.02, dy1 - 0.02, 9)], "#cdb163", { sw: 0.3 });
  s.poly([P(dx1 - 0.02, dy0 + 0.02, 0), P(dx1 - 0.02, dy1 - 0.02, 0), P(dx1 - 0.02, dy1 - 0.02, 9), P(dx1 - 0.02, dy0 + 0.02, 9)], "#e2c877", { sw: 0.3 });
  for (let z = 3; z < 9; z += 3) { s.line(P(dx0 + 0.02, dy1 - 0.02, z), P(dx1 - 0.02, dy1 - 0.02, z), "#a98f48", 0.3); s.line(P(dx1 - 0.02, dy0 + 0.02, z), P(dx1 - 0.02, dy1 - 0.02, z), "#a98f48", 0.3); }
  const arc = [];
  for (let i = 0; i <= 8; i++) { const t = i / 8; arc.push(P(dx0 - 0.03 + (dx1 - dx0 + 0.06) * t, dy1 + 0.03, 13 + Math.sin(t * Math.PI) * 5)); }
  const arcBack = arc.map((p, i) => { const t = i / 8; return P(dx0 - 0.03 + (dx1 - dx0 + 0.06) * t, dy0 - 0.03, 13 + Math.sin(t * Math.PI) * 5); });
  s.poly(arc.concat(arcBack.reverse()), s.grad(light(C.rust, 0.2), dark(C.rust, 0.1)), { sw: 0.4 });
  s.poly(arc.concat([P(dx1 + 0.03, dy1 + 0.03, 13), P(dx0 - 0.03, dy1 + 0.03, 13)]), dark(C.rust, 0.25), { sw: 0.4 });
  fence(s, [0.08, 0.62], [0.08, 0.96]); fence(s, [0.08, 0.96], [0.5, 0.96]);
  haybale(s, 0.3, 0.78);
  return s;
};

B.manor_a = () => {
  const s = new Sprite("manor_a", 22);
  plot(s, 31, 15);
  s.shadow(0.64, 0.7, 31, 12);
  const d = { x0: 0.1, y0: 0.24, x1: 0.9, y1: 0.66, wh: 21, rh: 9, ridge: "x", hip: true, wall: C.honey, wallTex: "stone", roof: C.slate, roofTex: "slate" };
  shell(s, d);
  const L = onL(d.y1), R = onR(d.x1);
  for (const a of [0.15, 0.28, 0.63, 0.76]) { windowAt(s, L, a, 2.8, { w: 0.075, h: 5.6 }); windowAt(s, L, a, 12.6, { w: 0.075, h: 5.2 }); }
  windowAt(s, L, 0.462, 12.6, { w: 0.075, h: 5.2 });
  for (const v of [0.31, 0.47]) { windowAt(s, R, v, 2.8, { w: 0.075, h: 5.6 }); windowAt(s, R, v, 12.6, { w: 0.075, h: 5.2 }); }
  s.line(L(d.x0, 10.4), L(d.x1, 10.4), light(d.wall, 0.3), 0.7); s.line(R(d.y0, 10.4), R(d.y1, 10.4), light(d.wall, 0.4), 0.7);
  doorAt(s, L, 0.45, "#1f2f44", { w: 0.1, h: 8 });
  // Portico.
  s.poly([P(0.4, 0.66, 10), P(0.6, 0.66, 10), P(0.6, 0.78, 10), P(0.4, 0.78, 10)], C.frame, { sw: 0.35 });
  s.poly([P(0.4, 0.78, 10), P(0.6, 0.78, 10), P(0.5, 0.78, 13.5)], C.frame, { sw: 0.35 });
  for (const a of [0.41, 0.59]) s.line(P(a, 0.77), P(a, 0.77, 10), C.frame, 1.3);
  roof(s, d);
  chimney(s, 0.26, 0.44, 25, 34); chimney(s, 0.74, 0.44, 25, 34, C.brick, false);
  for (const x of [0.22, 0.34, 0.66, 0.78]) { const c = P(x, 0.88, 4); s.oval(c, 2.6, 4.2, s.radial("#6f9450", "#4c7742"), { sw: 0.3 }); }
  s.poly([P(0.44, 0.78), P(0.56, 0.78), P(0.56, 1.0), P(0.44, 1.0)], "#e2cfa3", { sw: 0.25 });
  return s;
};

// --- Trees, rocks and animals --------------------------------------------------

const T = {};

function canopy(s, c, r, cols, n = 9) {
  const [d, m, l] = cols;
  const blobs = [];
  for (let i = 0; i < n; i++) {
    const a = s.rand() * Math.PI * 2, t = Math.sqrt(s.rand()) * 0.62;
    blobs.push([c[0] + Math.cos(a) * r * t, c[1] + Math.sin(a) * r * t * 0.78, r * (0.42 + s.rand() * 0.24)]);
  }
  blobs.sort((a, b) => b[1] - a[1]);
  blobs.forEach((b) => s.oval([b[0] - r * 0.08, b[1] + r * 0.1], b[2], b[2] * 0.92, d, { sw: 0.4 }));
  blobs.forEach((b) => s.oval([b[0], b[1]], b[2] * 0.94, b[2] * 0.86, s.radial(l, m), { stroke: null }));
  for (let i = 0; i < n * 3; i++) {
    const a = s.rand() * Math.PI * 2, t = Math.sqrt(s.rand()) * 0.85;
    const p = [c[0] + Math.cos(a) * r * t, c[1] + Math.sin(a) * r * t * 0.8];
    const up = p[1] < c[1] && p[0] > c[0] - r * 0.3;
    s.oval(p, 1.3 + s.rand(), 0.9 + s.rand() * 0.6, up ? light(l, 0.25) : dark(m, 0.2), { stroke: null, opacity: 0.55 });
  }
}

function oak(name, seed, size, cols) {
  T[name] = () => {
    const s = new Sprite(name, seed);
    s.shadow(0.56, 0.56, 15 * size, 7 * size);
    const b = P(0.5, 0.5);
    s.poly([[b[0] - 2.2 * size, b[1]], [b[0] + 2.2 * size, b[1]], [b[0] + 1.4 * size, b[1] - 15 * size], [b[0] - 1.4 * size, b[1] - 15 * size]], s.grad(light(C.trunk, 0.1), dark(C.trunk, 0.25), 1, 0, 0, 0), { sw: 0.4 });
    s.line([b[0], b[1] - 10 * size], [b[0] - 5 * size, b[1] - 17 * size], C.trunk, 1.1 * size);
    s.line([b[0], b[1] - 11 * size], [b[0] + 5 * size, b[1] - 18 * size], C.trunk, 1.0 * size);
    canopy(s, [b[0], b[1] - 25 * size], 14 * size, cols, 9);
    return s;
  };
}
oak("oak_a", 31, 1.0, [C.leafD, C.leafM, C.leafL]);
oak("oak_b", 32, 0.86, ["#557f3d", "#7aa24a", "#a1c35f"]);
oak("oak_c", 33, 1.12, ["#466f45", "#5f9152", "#84b46a"]);
oak("oak_d", 34, 0.72, ["#5a7d40", "#84a551", "#adc86a"]);

function pineShape(s, x, y, size, col = C.pineD) {
  const b = P(x, y);
  s.poly([[b[0] - 1.3, b[1]], [b[0] + 1.3, b[1]], [b[0] + 1, b[1] - 7], [b[0] - 1, b[1] - 7]], C.trunk, { sw: 0.3 });
  for (let j = 0; j < 4; j++) {
    const top = b[1] - 5 - j * 7.5 * size, half = (10.5 - j * 2.2) * size, hgt = 13 * size;
    const pts = [[b[0], top - hgt]];
    for (let i = 0; i <= 6; i++) pts.push([b[0] + half - (2 * half) * i / 6, top + (i % 2 ? -1.6 : 0)]);
    s.poly(pts, s.grad(light(col, 0.12 + j * 0.05), dark(col, 0.1), 1, 0, 0, 0), { sw: 0.4 });
  }
}
T.pine_a = () => { const s = new Sprite("pine_a", 35); s.shadow(0.55, 0.55, 9, 4.5); pineShape(s, 0.5, 0.5, 1.0); return s; };
T.pine_b = () => { const s = new Sprite("pine_b", 36); s.shadow(0.55, 0.55, 8, 4); pineShape(s, 0.5, 0.5, 0.8, "#42704f"); return s; };

T.poplar_a = () => {
  const s = new Sprite("poplar_a", 37);
  s.shadow(0.55, 0.55, 8, 4);
  const b = P(0.5, 0.5);
  s.poly([[b[0] - 1.2, b[1]], [b[0] + 1.2, b[1]], [b[0] + 0.9, b[1] - 9], [b[0] - 0.9, b[1] - 9]], C.trunk, { sw: 0.3 });
  s.oval([b[0] - 0.6, b[1] - 24], 6.2, 18, "#4f7a3c", { sw: 0.45 });
  s.oval([b[0] + 0.8, b[1] - 25], 5, 16.5, s.radial("#93bd62", "#628f45"), { stroke: null });
  for (let i = 0; i < 16; i++) s.oval([b[0] + (s.rand() - 0.5) * 7, b[1] - 9 - s.rand() * 30], 1, 1.8, s.rand() > 0.5 ? "#a9cc74" : "#4f7a3c", { stroke: null, opacity: 0.5 });
  return s;
};

T.willow_a = () => {
  const s = new Sprite("willow_a", 38);
  s.shadow(0.56, 0.56, 16, 7.5);
  const b = P(0.5, 0.5);
  s.poly([[b[0] - 2, b[1]], [b[0] + 2, b[1]], [b[0] + 1.2, b[1] - 13], [b[0] - 1.2, b[1] - 13]], dark(C.trunk, 0.1), { sw: 0.4 });
  canopy(s, [b[0], b[1] - 22], 13, ["#6f8f3f", "#8fae4e", "#b4cc68"], 7);
  for (let i = 0; i < 22; i++) {
    const a = Math.PI * (0.05 + 0.9 * s.rand()), x = b[0] + Math.cos(a) * 14, top = b[1] - 22 + Math.sin(a) * 4, len = 9 + s.rand() * 7;
    s.curve([[x * 0.92 + b[0] * 0.08, top - 5], [x, top], [x + (s.rand() - 0.5) * 1.5, top + len]], s.rand() > 0.5 ? "#a9c462" : "#7d9c46", 0.7, { opacity: 0.9 });
  }
  return s;
};

T.birch_a = () => {
  const s = new Sprite("birch_a", 39);
  s.shadow(0.55, 0.55, 10, 5);
  const b = P(0.5, 0.5);
  s.poly([[b[0] - 1.2, b[1]], [b[0] + 1.2, b[1]], [b[0] + 0.7, b[1] - 22], [b[0] - 0.7, b[1] - 22]], "#ece6d6", { sw: 0.35 });
  for (const z of [4, 9, 13, 18]) s.line([b[0] - 0.9, b[1] - z], [b[0] + 0.5, b[1] - z - 0.5], "#3a332c", 0.5);
  canopy(s, [b[0], b[1] - 26], 9.5, ["#7a9a4a", "#9cba5c", "#c3d779"], 7);
  return s;
};

T.bush_a = () => { const s = new Sprite("bush_a", 40); s.shadow(0.52, 0.54, 8, 4); bush(s, 0.44, 0.5, 4.4); bush(s, 0.58, 0.54, 3.6, "#7aa24a"); return s; };

function rock(name, seed, flip) {
  T[name] = () => {
    const s = new Sprite(name, seed);
    s.shadow(0.54, 0.6, 17, 7);
    const p = P(0.5, 0.56), f = flip ? -1 : 1;
    const q = (x, y) => [p[0] + x * f, p[1] + y];
    s.poly([q(-15, 3), q(-11, -9), q(-2, -16), q(9, -9), q(15, 3), q(4, 8), q(-8, 7)], s.grad("#b3afa2", "#85827a"), { sw: 0.5 });
    s.poly([q(-11, -9), q(-2, -16), q(9, -9), q(0, -4)], "#c9c5b8", { sw: 0.35 });
    s.poly([q(0, -4), q(9, -9), q(15, 3), q(4, 8)], "#9b978c", { sw: 0.35 });
    s.oval(q(-9, 5), 5, 2.4, "#7f9a5c", { sw: 0.25 });
    s.oval(q(6, -9), 2.4, 1.2, "#8aa364", { stroke: null, opacity: 0.8 });
    return s;
  };
}
rock("rock_a", 41, false); rock("rock_b", 42, true);

function sheep(name, seed, face) {
  T[name] = () => {
    const s = new Sprite(name, seed);
    s.shadow(0.52, 0.56, 7, 3, 0.25);
    const p = P(0.5, 0.5, 4);
    for (const dx of [-3, 3]) s.line([p[0] + dx, p[1] + 1], [p[0] + dx, p[1] + 4.2], "#2f2a27", 0.9);
    for (const [dx, dy, r] of [[-2.6, 0, 3], [2.2, 0.2, 3], [0, -1.6, 3.3], [0, 1, 3]]) s.oval([p[0] + dx, p[1] + dy], r, r * 0.82, s.radial("#fffaf0", "#e6dfcd"), { sw: 0.35, stroke: "#b9b09b" });
    s.oval([p[0] + 5.2 * face, p[1] - 1.4], 2.1, 1.9, "#3b3432", { sw: 0.2 });
    s.oval([p[0] + 4.2 * face, p[1] - 3.1], 0.9, 0.6, "#3b3432", { stroke: null });
    return s;
  };
}
sheep("sheep_a", 43, 1); sheep("sheep_b", 44, -1);

function cow(name, seed, face) {
  T[name] = () => {
    const s = new Sprite(name, seed);
    s.shadow(0.52, 0.56, 9, 3.6, 0.25);
    const p = P(0.5, 0.5, 5.4);
    for (const dx of [-5, -2.5, 3, 5.4]) s.line([p[0] + dx, p[1] + 1.5], [p[0] + dx, p[1] + 5.6], "#2f2a27", 1.0);
    s.oval(p, 7.4, 4.2, s.radial("#fbf7ee", "#e3dccb"), { sw: 0.4, stroke: "#a39a86" });
    s.oval([p[0] - 2.4 * face, p[1] - 1.4], 3, 2.2, "#2f2b29", { stroke: null });
    s.oval([p[0] + 2.8 * face, p[1] + 1], 2.1, 1.7, "#2f2b29", { stroke: null });
    s.oval([p[0] + 8.4 * face, p[1] - 2.4], 2.6, 2.3, "#2f2b29", { sw: 0.25 });
    s.oval([p[0] + 9.8 * face, p[1] - 1.4], 1.4, 1.1, "#e8b7a8", { stroke: null });
    s.line([p[0] - 7.2 * face, p[1] - 1], [p[0] - 8.6 * face, p[1] + 3], "#2f2a27", 0.5);
    return s;
  };
}
cow("cow_a", 45, 1); cow("cow_b", 46, -1);

T.haybale_a = () => { const s = new Sprite("haybale_a", 47); s.shadow(0.53, 0.56, 7, 3, 0.25); haybale(s, 0.5, 0.5); return s; };

// --- Narrowboats ---------------------------------------------------------------

const LIVERIES = [
  { cabin: "#2f5a48", band: "#a8402f", roof: "#e6d6a4", panel: "#a8402f" },
  { cabin: "#2c4466", band: "#c79a3a", roof: "#ebdfbc", panel: "#c79a3a" },
  { cabin: "#7a2f2f", band: "#2d5443", roof: "#e8d8aa", panel: "#2d5443" },
  { cabin: "#3b4148", band: "#a8402f", roof: "#ddd5bd", panel: "#d9b25a" },
];
const BOAT_DIRS = 16;

function boat(livery, index) {
  const L = LIVERIES[livery];
  const s = new Sprite(`boat_${livery}_${String(index).padStart(2, "0")}`, 60 + livery);
  const ang = (Math.PI * 2 * index) / BOAT_DIRS;
  const dir = [Math.cos(ang), Math.sin(ang)], perp = [-dir[1], dir[0]];
  // Boat coordinates: l along the hull, w across it, z up; centred on the cell centre.
  const at = (l, w, z) => P(0.5 + dir[0] * l + perp[0] * w, 0.5 + dir[1] * l + perp[1] * w, z);
  const prism = (pts, z0, z1, side, top) => {
    const world = pts.map(([l, w]) => [dir[0] * l + perp[0] * w, dir[1] * l + perp[1] * w]);
    const edges = world.map((a, i) => { const b = world[(i + 1) % world.length]; return { a: pts[i], b: pts[(i + 1) % pts.length], depth: a[0] + a[1] + b[0] + b[1], wa: a, wb: b }; });
    edges.sort((m, n) => m.depth - n.depth);
    for (const e of edges) {
      if (Math.abs((e.wb[0] - e.wb[1]) - (e.wa[0] - e.wa[1])) * HW < 0.4) continue;
      const len = Math.hypot(e.wb[0] - e.wa[0], e.wb[1] - e.wa[1]) || 1;
      const lum = Math.abs((e.wb[0] - e.wa[0]) / len);
      s.poly([at(e.a[0], e.a[1], z0), at(e.b[0], e.b[1], z0), at(e.b[0], e.b[1], z1), at(e.a[0], e.a[1], z1)], dark(side, 0.28 * lum), { sw: 0.3 });
    }
    s.poly(pts.map(([l, w]) => at(l, w, z1)), top, { sw: 0.3 });
  };
  const w = 0.056;
  const hull = [[-0.54, -w * 0.5], [-0.5, -w], [0.36, -w], [0.47, -w * 0.55], [0.53, 0], [0.47, w * 0.55], [0.36, w], [-0.5, w], [-0.54, w * 0.5]];
  prism(hull, 0, 2.3, "#1c1f1e", "#1c1f1e");
  prism(hull, 2.3, 3.3, L.band, "#8a7a66");
  const cw = 0.045;
  prism([[-0.37, -cw], [0.29, -cw], [0.29, cw], [-0.37, cw]], 3.3, 7, L.cabin, L.roof);
  // Livery on the cabin side that faces the camera.
  const side = perp[0] + perp[1] > 0 ? cw : -cw;
  if (Math.abs(dir[0] - dir[1]) > 0.3) {
    s.poly([at(-0.355, side, 3.9), at(-0.2, side, 3.9), at(-0.2, side, 6.4), at(-0.355, side, 6.4)], L.panel, { sw: 0.2 });
    s.line(at(-0.33, side, 5.15), at(-0.225, side, 5.15), L.roof, 0.35);
    for (let j = 0; j < 4; j++) { const l = -0.14 + j * 0.105; s.poly([at(l, side, 4.5), at(l + 0.06, side, 4.5), at(l + 0.06, side, 6.2), at(l, side, 6.2)], "#cfe3e6", { sw: 0.25, stroke: "#3d4a4c" }); }
    s.line(at(-0.37, side, 6.7), at(0.29, side, 6.7), L.roof, 0.3);
  }
  // Roof: pole, plank, flower tubs, water can and the stove chimney.
  s.line(at(-0.1, 0.018, 7.4), at(0.25, 0.018, 7.4), "#6b5138", 0.45);
  s.line(at(-0.04, -0.02, 7.4), at(0.2, -0.02, 7.4), "#b08a5c", 0.7);
  for (const [l, c] of [[0.2, "#d9534a"], [0.08, "#f1c84b"], [-0.02, "#e98bb0"]]) { s.oval(at(l, 0.0, 7.6), 1.5, 1.0, "#6f9450", { stroke: null }); s.oval(at(l, 0.0, 8.2), 1.0, 0.8, c, { stroke: null }); }
  const st = at(-0.27, 0, 7);
  s.line(st, [st[0], st[1] - 3.8], "#1c1f1e", 1.2);
  s.line([st[0], st[1] - 2.9], [st[0], st[1] - 3.8], "#d9a441", 1.2);
  // Bow fender, tiller and the steerer.
  s.oval(at(0.545, 0, 2.6), 1.5, 1.3, "#3a332c", { sw: 0.2 });
  s.line(at(-0.535, 0, 4.7), at(-0.43, 0.02, 5.1), "#b9884a", 0.6);
  const feet = at(-0.435, 0, 3.3);
  s.line(feet, [feet[0], feet[1] - 2], "#2f3b52", 1.6);
  s.line([feet[0], feet[1] - 2], [feet[0], feet[1] - 4.2], "#3d6a8a", 1.9);
  s.oval([feet[0], feet[1] - 5.4], 1.25, 1.3, "#f1c9a5", { sw: 0.2 });
  s.line([feet[0] - 1.3, feet[1] - 6.2], [feet[0] + 1.3, feet[1] - 6.2], "#5a4632", 0.8);
  return s;
}

// --- Render ------------------------------------------------------------------

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const makers = [...Object.values(B), ...Object.values(T)];
  for (let l = 0; l < LIVERIES.length; l++) for (let i = 0; i < BOAT_DIRS; i++) makers.push(() => boat(l, i));

  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const manifest = { scale: SCALE, boat_directions: BOAT_DIRS, sprites: {} };
  for (const make of makers) {
    const s = make();
    const svg = s.svg();
    await page.setViewportSize({ width: s.meta.w * SCALE, height: s.meta.h * SCALE });
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.screenshot({ path: path.join(OUT, s.name + ".png"), omitBackground: true });
    manifest.sprites[s.name] = s.meta;
  }
  fs.writeFileSync(path.join(OUT, "sprites.json"), JSON.stringify(manifest, null, 1) + "\n");

  // Contact sheet for reviewing the set at a glance.
  const names = Object.keys(manifest.sprites).filter((n) => !n.startsWith("boat_") || n.endsWith("_02") || n.endsWith("_05") || n.endsWith("_08") || n.endsWith("_14"));
  const cells = names.map((n) => `<figure><img src="data:image/png;base64,${fs.readFileSync(path.join(OUT, n + ".png")).toString("base64")}" style="height:${Math.min(170, manifest.sprites[n].h * 2.2)}px"><figcaption>${n}</figcaption></figure>`).join("");
  await page.setViewportSize({ width: 1500, height: 900 });
  await page.setContent(`<html><body style="margin:0;padding:16px;background:#9fbc72;font:12px Georgia;color:#33281f">
    <div style="display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end">${cells}</div>
    <style>figure{margin:0;text-align:center} figcaption{margin-top:2px}</style></body></html>`);
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(__dirname, "..", "docs", "sprites.png"), fullPage: true });
  await browser.close();
  console.log(`${Object.keys(manifest.sprites).length} sprites written to ${OUT}`);
})();
