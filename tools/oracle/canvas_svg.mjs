// Every keyed canvas texture the original draws, re-emitted as a vector SVG 1.1 file for the Slug
// pipeline (SVG -> ThorVG -> slughorn atlas -> Godot shader). No bitmaps: the 2D-canvas calls are
// recorded as they happen (paths, transforms, clips, paints, text), replayed as SVG paths, then the
// SVG is rasterized back in the same browser and scored against the real canvas pixels.
// Repeated primitives are instanced: runs of consecutive fills/strokes become <use> elements of prototype
// <symbol>s (data-stamp-kind rect|ellipse|path|stroke) placed by affine matrices; see the stamping block in
// emitCanvas() and manifest.stamping for the exact rules.
// usage: node tools/oracle/canvas_svg.mjs --chrome <path> [--root <original>] [--only environment,station,plaza,sakura] [--out <dir>]
//   --root   the original's checkout, with npm ci run (default: the workspace's 3-interactor/sakuragaoka-station-upstream)
//   --out    default: addons/sakuragaoka_station/slug/svg/ ; writes <key>.svg per keyed texture + manifest.json
//   --keys   optional comma list: only emit these keys (debugging)
//   --mae / --cov  failure thresholds (default 0.02 / 0.99, see FAIL below)
//   --ablate text|tiny  deliberately drop text or tiny (<=16 px2) fills, to see what the score does when content is missing
//   --no-stamp / --stamp-min N  disable stamping (instancing) / change the minimum run length (default 8: below it,
//                  runs save little; 32 -> 8 saved 4.3k curves on the port keys, 8 -> 4 only 0.7k for 32 more runs)
//   --png <dir>    also write <key>.real.png / <key>.svg.png, and labelled contact sheets <out>/oracle-sheet-NN.png
//                  (12 keys per sheet: real | SVG | |diff| x4, labelled with residual, floors and excess; failing keys first, then
//                  worst residual-minus-floor)
//   --sheet-copy <dir>  also copy each sheet to <dir>/oracle-canvas-vs-svg-NN.png, numbering after the highest existing NN
//   --no-font-gate skip the second pass that preloads the webfonts before the page draws
//   --no-floors    skip the floor measurement (second page load, raster-floor scenes)
// Text is converted to outlines with opentype.js (fetched once from jsdelivr) and the TTF subsets of the
// Google Fonts families that index.html loads (fetched with text=<the characters drawn>); both are
// cached under <os tmp>/sakuragaoka-canvas-svg-cache. Glyph positions come from the browser's own
// measureText, so layout matches the canvas; glyph shapes come from the same font files the page loads.
// Glyph contours are emitted as the font has them, never reoriented, with fill-rule="nonzero" stated on
// every text path (downstream normalises windings with a boolean union).
// Exit code 1 when any key fails verification; per-key scores, counts and dropped ops are in manifest.json.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const outDir = path.resolve(args.out || path.join(here, '../../addons/sakuragaoka_station/slug/svg'));
const STAMP = !args['no-stamp'], STAMP_MIN = Number(args['stamp-min'] || 8), STAMP_EPS = 0.01; // stamp fit tolerance, device px
const ABLATE = args.ablate || ''; // sensitivity check of the score: drop all text / all tiny fills
const onlyKeys = args.keys ? new Set(args.keys.split(',')) : null;
// FAIL: a key fails when its alpha-weighted linear-RGB MAE exceeds MAE_MAX or its 1px-tolerant alpha
// coverage agreement drops below COV_MIN. Rationale in the manifest's "thresholds" entry.
const MAE_MAX = Number(args.mae || 0.02), COV_MIN = Number(args.cov || 0.99);
const puppeteer = createRequire(path.join(root, 'package.json'))('puppeteer-core');
const CACHE = path.join(os.tmpdir(), 'sakuragaoka-canvas-svg-cache');
fs.mkdirSync(CACHE, { recursive: true });

// ------------------------------------------------------------------ page-side recorder
// Installed before any page script. Wraps CanvasRenderingContext2D (and the OffscreenCanvas one) so
// every canvas keeps a display list: path geometry is stored in device space (the CTM is applied when
// each segment is added, exactly as the canvas does), draws snapshot paint/alpha/composite/clip/CTM.
// The real methods are always called first, so the page renders as before.
function installRecorder() {
  const PI2 = Math.PI * 2;
  const recs = new Map(); const byId = [];
  const grads = new WeakMap();
  const CR = window.__cr = { recs, byId, off: false, allow: new Set(), errors: [], texts: new Set() };
  const recording = (ctx) => ctx !== scratch && (!CR.off || CR.allow.has(ctx.canvas));
  let nextClip = 1;
  const ap = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const inv = (m) => { const det = m[0] * m[3] - m[1] * m[2]; if (!det) return null; const a = m[3] / det, b = -m[1] / det, c = -m[2] / det, d = m[0] / det; return [a, b, c, d, -(a * m[4] + c * m[5]), -(b * m[4] + d * m[5])]; };
  const fin = (a) => { for (const v of a) if (typeof v === 'number' && !Number.isFinite(v)) return false; return true; };
  let scratch = null;
  const S = () => scratch || (scratch = document.createElement('canvas').getContext('2d'));
  const parseColor = (v) => {
    if (typeof v !== 'string') return null;
    let m = /^#([0-9a-f]{6})$/i.exec(v); if (m) return [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16), 1];
    m = /^rgba?\(([^)]+)\)$/i.exec(v); if (m) { const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
    m = /^color\(srgb ([^)]+)\)$/i.exec(v); if (m) { const p = m[1].split(/[ /]+/).filter(Boolean).map(Number); return [p[0] * 255, p[1] * 255, p[2] * 255, p.length > 3 ? p[3] : 1]; }
    const s = S(); s.fillStyle = '#000'; s.fillStyle = v; const n = s.fillStyle; return n !== v ? parseColor(n) : null;
  };
  const normColor = (v) => { const s = S(); s.fillStyle = '#000'; s.fillStyle = v; return parseColor(s.fillStyle); };

  const getT = CanvasRenderingContext2D.prototype.getTransform;
  const origMeasure = CanvasRenderingContext2D.prototype.measureText;
  const rec = (ctx) => {
    const c = ctx.canvas; let r = recs.get(c);
    if (!r) { r = { id: byId.length, canvas: c, items: [], path: [], cur: null, start: null, clip: null, stack: [], ops: {}, unsup: {} }; recs.set(c, r); byId.push(r); }
    return r;
  };
  const T = (ctx) => { const m = getT.call(ctx); return [m.a, m.b, m.c, m.d, m.e, m.f]; };
  const bump = (o, k, n = 1) => { o[k] = (o[k] || 0) + n; };
  CR.bump = bump;

  // ---- path building (device space)
  const moveTo = (r, p) => { r.path.push(['M', p[0], p[1]]); r.cur = p; r.start = p; };
  const lineTo = (r, p) => { if (!r.cur) return moveTo(r, p); r.path.push(['L', p[0], p[1]]); r.cur = p; };
  const ellipseArc = (r, m, cx, cy, rx, ry, rot, a0, sweep) => {
    const cr = Math.cos(rot), sr = Math.sin(rot);
    const P = (t) => { const x = rx * Math.cos(t), y = ry * Math.sin(t); return [cx + x * cr - y * sr, cy + x * sr + y * cr]; };
    const D = (t) => { const x = -rx * Math.sin(t), y = ry * Math.cos(t); return [x * cr - y * sr, x * sr + y * cr]; };
    const p0 = ap(m, ...P(a0));
    if (r.cur) { if (Math.hypot(p0[0] - r.cur[0], p0[1] - r.cur[1]) > 1e-6) lineTo(r, p0); } else moveTo(r, p0);
    if (!sweep) return;
    const n = Math.max(1, Math.ceil(Math.abs(sweep) / (Math.PI / 2) - 1e-9)), h = sweep / n, k = 4 / 3 * Math.tan(h / 4);
    for (let i = 0; i < n; i++) {
      const t0 = a0 + i * h, t1 = t0 + h, q0 = P(t0), d0 = D(t0), q1 = P(t1), d1 = D(t1);
      const c1 = ap(m, q0[0] + k * d0[0], q0[1] + k * d0[1]), c2 = ap(m, q1[0] - k * d1[0], q1[1] - k * d1[1]), e = ap(m, q1[0], q1[1]);
      r.path.push(['C', c1[0], c1[1], c2[0], c2[1], e[0], e[1]]); r.cur = e;
    }
  };
  const sweepOf = (a0, a1, ccw) => {
    let s = a1 - a0;
    if (!ccw) { if (s >= PI2) return PI2; s %= PI2; if (s < 0) s += PI2; return s; }
    if (-s >= PI2) return -PI2; s %= PI2; if (s > 0) s -= PI2; return s;
  };
  const P = {
    beginPath(r) { r.path = []; r.cur = r.start = null; },
    moveTo(r, m, x, y) { moveTo(r, ap(m, x, y)); },
    lineTo(r, m, x, y) { lineTo(r, ap(m, x, y)); },
    closePath(r) { if (r.cur && r.path.length) { r.path.push(['Z']); r.cur = r.start; } },
    quadraticCurveTo(r, m, x1, y1, x, y) { const c = ap(m, x1, y1); if (!r.cur) moveTo(r, c); const e = ap(m, x, y); r.path.push(['Q', c[0], c[1], e[0], e[1]]); r.cur = e; },
    bezierCurveTo(r, m, x1, y1, x2, y2, x, y) { const c1 = ap(m, x1, y1); if (!r.cur) moveTo(r, c1); const c2 = ap(m, x2, y2), e = ap(m, x, y); r.path.push(['C', c1[0], c1[1], c2[0], c2[1], e[0], e[1]]); r.cur = e; },
    arc(r, m, x, y, rad, a0, a1, ccw) { ellipseArc(r, m, x, y, rad, rad, 0, a0, sweepOf(a0, a1, !!ccw)); },
    ellipse(r, m, x, y, rx, ry, rot, a0, a1, ccw) { ellipseArc(r, m, x, y, rx, ry, rot, a0, sweepOf(a0, a1, !!ccw)); },
    rect(r, m, x, y, w, h) { moveTo(r, ap(m, x, y)); lineTo(r, ap(m, x + w, y)); lineTo(r, ap(m, x + w, y + h)); lineTo(r, ap(m, x, y + h)); P.closePath(r); moveTo(r, ap(m, x, y)); },
    arcTo(r, m, x1, y1, x2, y2, rad) {
      if (!r.cur) return moveTo(r, ap(m, x1, y1));
      const im = inv(m); if (!im) return;
      const [x0, y0] = ap(im, r.cur[0], r.cur[1]);
      const v1x = x0 - x1, v1y = y0 - y1, v2x = x2 - x1, v2y = y2 - y1, l1 = Math.hypot(v1x, v1y), l2 = Math.hypot(v2x, v2y);
      const cross = v1x * v2y - v1y * v2x;
      if (!rad || !l1 || !l2 || Math.abs(cross) <= 1e-9 * l1 * l2) return lineTo(r, ap(m, x1, y1));
      const u1x = v1x / l1, u1y = v1y / l1, u2x = v2x / l2, u2y = v2y / l2;
      const ang = Math.acos(Math.max(-1, Math.min(1, u1x * u2x + u1y * u2y)));
      const dist = rad / Math.tan(ang / 2);
      const bx = u1x + u2x, by = u1y + u2y, bl = Math.hypot(bx, by), cd = rad / Math.sin(ang / 2);
      const cx = x1 + bx / bl * cd, cy = y1 + by / bl * cd;
      const t1x = x1 + u1x * dist, t1y = y1 + u1y * dist, t2x = x1 + u2x * dist, t2y = y1 + u2y * dist;
      const a0 = Math.atan2(t1y - cy, t1x - cx), a1 = Math.atan2(t2y - cy, t2x - cx);
      let sw = a1 - a0; while (sw > Math.PI) sw -= PI2; while (sw < -Math.PI) sw += PI2;
      ellipseArc(r, m, cx, cy, rad, rad, 0, a0, sw);
    },
    roundRect(r, m, x, y, w, h, radii) {
      let list = radii === undefined ? [0] : Array.isArray(radii) ? radii : [radii];
      list = list.map(v => typeof v === 'number' ? { x: v, y: v } : { x: (v && v.x) || 0, y: (v && v.y) || 0 });
      let ul, ur, lr, ll;
      if (list.length === 1) ul = ur = lr = ll = list[0];
      else if (list.length === 2) { ul = lr = list[0]; ur = ll = list[1]; }
      else if (list.length === 3) { ul = list[0]; ur = ll = list[1]; lr = list[2]; }
      else[ul, ur, lr, ll] = list;
      ul = { ...ul }; ur = { ...ur }; lr = { ...lr }; ll = { ...ll };
      if (w < 0) { x += w; w = -w; [ul, ur] = [ur, ul]; [ll, lr] = [lr, ll]; }
      if (h < 0) { y += h; h = -h; [ul, ll] = [ll, ul]; [ur, lr] = [lr, ur]; }
      const top = ul.x + ur.x, right = ur.y + lr.y, bottom = lr.x + ll.x, left = ul.y + ll.y;
      const sc = Math.min(top ? w / top : Infinity, right ? h / right : Infinity, bottom ? w / bottom : Infinity, left ? h / left : Infinity);
      if (sc < 1) for (const c of [ul, ur, lr, ll]) { c.x *= sc; c.y *= sc; }
      moveTo(r, ap(m, x + ul.x, y));
      lineTo(r, ap(m, x + w - ur.x, y));
      if (ur.x && ur.y) ellipseArc(r, m, x + w - ur.x, y + ur.y, ur.x, ur.y, 0, -Math.PI / 2, Math.PI / 2);
      lineTo(r, ap(m, x + w, y + h - lr.y));
      if (lr.x && lr.y) ellipseArc(r, m, x + w - lr.x, y + h - lr.y, lr.x, lr.y, 0, 0, Math.PI / 2);
      lineTo(r, ap(m, x + ll.x, y + h));
      if (ll.x && ll.y) ellipseArc(r, m, x + ll.x, y + h - ll.y, ll.x, ll.y, 0, Math.PI / 2, Math.PI / 2);
      lineTo(r, ap(m, x, y + ul.y));
      if (ul.x && ul.y) ellipseArc(r, m, x + ul.x, y + ul.y, ul.x, ul.y, 0, Math.PI, Math.PI / 2);
      P.closePath(r); moveTo(r, ap(m, x, y));
    },
  };

  // ---- paints / state snapshots
  const paint = (r, v) => {
    if (typeof v === 'string') return { t: 'c', c: parseColor(v) };
    const g = grads.get(v); if (g) return { t: 'g', type: g.type, a: g.a.slice(), stops: g.stops.map(s => s.slice()) };
    bump(r.unsup, 'pattern'); return { t: 'p' };
  };
  const common = (ctx, r) => {
    const o = { m: T(ctx), alpha: ctx.globalAlpha, clip: r.clip, rg: window.__rngCalls || 0 };
    const comp = ctx.globalCompositeOperation; if (comp !== 'source-over') o.comp = comp;
    const f = ctx.filter; if (f && f !== 'none') o.filter = f;
    const sc = parseColor(ctx.shadowColor);
    if (sc && sc[3] > 0 && (ctx.shadowBlur || ctx.shadowOffsetX || ctx.shadowOffsetY)) o.shadow = [ctx.shadowColor, ctx.shadowBlur, ctx.shadowOffsetX, ctx.shadowOffsetY];
    return o;
  };
  const strokeState = (ctx) => ({ lw: ctx.lineWidth, cap: ctx.lineCap, join: ctx.lineJoin, miter: ctx.miterLimit, dash: ctx.getLineDash(), dashOff: ctx.lineDashOffset });
  const rectPoly = (m, x, y, w, h) => { const a = ap(m, x, y), b = ap(m, x + w, y), c = ap(m, x + w, y + h), d = ap(m, x, y + h); return [['M', ...a], ['L', ...b], ['L', ...c], ['L', ...d], ['Z']]; };

  // ---- text: layout measured by the browser at call time (font may change later)
  const textItem = (ctx, r, stroke, text, x, y, maxW) => {
    text = String(text).replace(/[\t\n\f\r]/g, ' ');
    const s = S(); const font = ctx.font;
    s.font = font; s.letterSpacing = ctx.letterSpacing || '0px'; s.textAlign = 'left';
    try { s.fontKerning = ctx.fontKerning; } catch (e) { }
    const mt = origMeasure;
    s.textBaseline = ctx.textBaseline; const fB = mt.call(s, text);
    s.textBaseline = 'alphabetic'; const fA = mt.call(s, text);
    const W = fA.width;
    const yA = y + (fA.fontBoundingBoxAscent - fB.fontBoundingBoxAscent);
    let sx = 1; if (maxW !== undefined && Number.isFinite(maxW) && W > maxW) sx = maxW > 0 ? maxW / W : 0;
    const align = ctx.textAlign, rtl = ctx.direction === 'rtl';
    const k = align === 'center' ? 0.5 : (align === 'right' || (align === 'end' && !rtl) || (align === 'start' && rtl)) ? 1 : 0;
    const x0 = x - k * W * sx;
    const chars = []; let pre = '';
    for (const ch of Array.from(text)) { chars.push([ch, pre ? mt.call(s, pre).width : 0]); pre += ch; }
    CR.texts.add(font + '\u0001' + text);
    let ready = true; try { ready = document.fonts.check(font, text); } catch (e) { }
    return { k: 'text', stroke, font, chars, x0, yA, sx, w: W, ready, paint: paint(r, stroke ? ctx.strokeStyle : ctx.fillStyle), ...(stroke ? strokeState(ctx) : {}), ...common(ctx, r) };
  };

  const D = {
    fill(ctx, r, a) { if (a[0] instanceof Path2D) { bump(r.unsup, 'Path2D'); return; } r.items.push({ k: 'fill', d: r.path.slice(), rule: a[0] === 'evenodd' ? 'evenodd' : 'nonzero', paint: paint(r, ctx.fillStyle), ...common(ctx, r) }); },
    stroke(ctx, r, a) { if (a[0] instanceof Path2D) { bump(r.unsup, 'Path2D'); return; } r.items.push({ k: 'stroke', d: r.path.slice(), paint: paint(r, ctx.strokeStyle), ...strokeState(ctx), ...common(ctx, r) }); },
    fillRect(ctx, r, [x, y, w, h]) { if (!w || !h) return; const c = common(ctx, r); r.items.push({ k: 'fill', rect: true, d: rectPoly(c.m, x, y, w, h), rule: 'nonzero', paint: paint(r, ctx.fillStyle), ...c }); },
    strokeRect(ctx, r, [x, y, w, h]) { if (!w && !h) return; const c = common(ctx, r); r.items.push({ k: 'stroke', d: rectPoly(c.m, x, y, w, h), paint: paint(r, ctx.strokeStyle), ...strokeState(ctx), ...c }); },
    clearRect(ctx, r, [x, y, w, h]) { if (!w || !h) return; const m = T(ctx); r.items.push({ k: 'clear', d: rectPoly(m, x, y, w, h), m, clip: r.clip, rg: window.__rngCalls || 0 }); },
    fillText(ctx, r, [t, x, y, mw]) { r.items.push(textItem(ctx, r, false, t, x, y, mw)); },
    strokeText(ctx, r, [t, x, y, mw]) { r.items.push(textItem(ctx, r, true, t, x, y, mw)); },
    clip(ctx, r, a) { if (a[0] instanceof Path2D) { bump(r.unsup, 'Path2D'); return; } r.clip = { id: nextClip++, d: r.path.slice(), rule: a[0] === 'evenodd' ? 'evenodd' : 'nonzero', parent: r.clip }; },
    save(ctx, r) { r.stack.push(r.clip); },
    restore(ctx, r) { if (r.stack.length) r.clip = r.stack.pop(); },
    reset(ctx, r) { r.items.push({ k: 'reset', rg: window.__rngCalls || 0 }); r.path = []; r.cur = r.start = null; r.clip = null; r.stack = []; },
    drawImage(ctx, r, a) {
      const img = a[0]; const src = recs.get(img);
      const isCanvas = (typeof HTMLCanvasElement !== 'undefined' && img instanceof HTMLCanvasElement) || (typeof OffscreenCanvas !== 'undefined' && img instanceof OffscreenCanvas);
      if (!isCanvas) { bump(r.unsup, 'drawImage:raster'); r.items.push({ k: 'raster', what: 'drawImage', rg: window.__rngCalls || 0 }); return; }
      if (img === ctx.canvas) { bump(r.unsup, 'drawImage:self'); return; }
      const W = img.width, H = img.height; let sx = 0, sy = 0, sw = W, sh = H, dx, dy, dw, dh;
      if (a.length >= 9) [, sx, sy, sw, sh, dx, dy, dw, dh] = a; else if (a.length >= 5) { [, dx, dy, dw, dh] = a; } else { [, dx, dy] = a; dw = W; dh = H; }
      if (!src) return; // a never-drawn canvas is transparent
      r.items.push({ k: 'image', src: src.id, n: src.items.length, W, H, sx, sy, sw, sh, dx, dy, dw, dh, ...common(ctx, r) });
    },
    putImageData(ctx, r) { bump(r.unsup, 'putImageData'); r.items.push({ k: 'raster', what: 'putImageData', rg: window.__rngCalls || 0 }); },
  };

  const wrap = (proto, name, fn) => {
    const orig = proto[name]; if (typeof orig !== 'function') return;
    proto[name] = function (...a) {
      const res = orig.apply(this, a);
      if (recording(this)) { try { const r = rec(this); bump(r.ops, name); fn(this, r, a); } catch (e) { CR.errors.push(name + ': ' + e.message); } }
      return res;
    };
  };
  for (const proto of [window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype, window.OffscreenCanvasRenderingContext2D && OffscreenCanvasRenderingContext2D.prototype].filter(Boolean)) {
    for (const n of ['moveTo', 'lineTo', 'quadraticCurveTo', 'bezierCurveTo', 'arc', 'ellipse', 'rect', 'arcTo', 'roundRect'])
      wrap(proto, n, (ctx, r, a) => { if (!fin(a.slice(0, 8))) return; P[n](r, T(ctx), ...a); });
    wrap(proto, 'beginPath', (ctx, r) => P.beginPath(r));
    wrap(proto, 'closePath', (ctx, r) => P.closePath(r));
    for (const n of Object.keys(D)) wrap(proto, n, (ctx, r, a) => { if (/Rect$|Text$/.test(n) && !fin(a.slice(n.endsWith('Text') ? 1 : 0))) return; D[n](ctx, r, a); });
    for (const n of ['translate', 'rotate', 'scale', 'transform', 'setTransform', 'resetTransform', 'measureText', 'getImageData', 'createLinearGradient', 'createRadialGradient', 'createConicGradient', 'createPattern', 'setLineDash'])
      wrap(proto, n, () => { });
    // gradients: remember their definition
    for (const [n, type] of [['createLinearGradient', 'linear'], ['createRadialGradient', 'radial'], ['createConicGradient', 'conic']]) {
      const o = proto[n]; if (!o) continue;
      proto[n] = function (...a) { const g = o.apply(this, a); grads.set(g, { type, a, stops: [] }); return g; };
    }
    // count property writes the census cares about (read back at draw time; these only feed the op tally)
    for (const n of ['filter', 'globalCompositeOperation', 'globalAlpha', 'font', 'lineWidth', 'lineCap', 'lineJoin', 'shadowBlur']) {
      const d = Object.getOwnPropertyDescriptor(proto, n); if (!d || !d.set) continue;
      Object.defineProperty(proto, n, { ...d, set(v) { d.set.call(this, v); if (recording(this)) bump(rec(this).ops, n); } });
    }
  }
  const addStop = CanvasGradient.prototype.addColorStop;
  CanvasGradient.prototype.addColorStop = function (off, col) { addStop.call(this, off, col); const g = grads.get(this); if (g) g.stops.push([off, normColor(col)]); };
  // resizing a canvas resets its bitmap and context state
  for (const C of [window.HTMLCanvasElement, window.OffscreenCanvas].filter(Boolean)) for (const n of ['width', 'height']) {
    const d = Object.getOwnPropertyDescriptor(C.prototype, n); if (!d || !d.set) continue;
    Object.defineProperty(C.prototype, n, { ...d, set(v) { d.set.call(this, v); const r = recs.get(this); if (r) { r.items.push({ k: 'reset', rg: window.__rngCalls || 0 }); r.path = []; r.cur = r.start = null; r.clip = null; r.stack = []; } } });
  }

  // export: the display lists of the given canvases and everything they drawImage from
  CR.export = (ids) => {
    const out = {}; const clips = {};
    const addClip = (c) => { while (c && !clips[c.id]) { clips[c.id] = { d: c.d, rule: c.rule, parent: c.parent ? c.parent.id : 0 }; c = c.parent; } };
    const todo = [...ids];
    while (todo.length) {
      const id = todo.pop(); if (out[id]) continue; const r = byId[id];
      out[id] = { w: r.canvas.width, h: r.canvas.height, ops: r.ops, unsup: r.unsup, items: r.items.map(it => { if (it.clip) addClip(it.clip); if (it.k === 'image') todo.push(it.src); return it.clip ? { ...it, clip: it.clip.id } : { ...it, clip: 0 }; }) };
    }
    return JSON.stringify({ canvases: out, clips });
  };
  CR.rec = rec;
}

// ------------------------------------------------------------------ serve + record
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };
// RNG hook for the procedural/authored tag of stamp runs: the served (in-memory, never on disk) source of
// the original's seeded generator mulberry32 (ctx.rng) and its coordinate-hash noise (hash2, hash3) gets a
// call counter; values are unchanged. The recorder stamps the counter on every draw.
const RNG_COUNT = 'globalThis.__rngCalls = (globalThis.__rngCalls || 0) + 1; ';
const RNG_HOOKS = {
  '/src/core/ctx.js': ['const r = () => { a |= 0;', `const r = () => { ${RNG_COUNT}a |= 0;`],
  '/src/world/environment/common.js': ['export function hash2(ix, iz, seed = 0) {', `export function hash2(ix, iz, seed = 0) { ${RNG_COUNT}`],
  '/src/world/lib/foliage.js': ['function hash3(x, y, z, s) {', `function hash3(x, y, z, s) { ${RNG_COUNT}`],
};
const rngHooked = new Map();
const injectRng = (p, src, [from, to]) => { const ok = src.includes(from); if (!rngHooked.has(p)) rngHooked.set(p, ok); return ok ? src.replace(from, to) : src; };

// font gate: on the recording pass the entry module is held back until the page has loaded every
// webfont face the canvases will draw with (found by a first pass), so canvas text is drawn with the
// fonts index.html asks for instead of whatever system fallback wins the load race.
let gate = null;
const server = http.createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
  if (gate && p === '/src/main.js') await Promise.race([gate.promise, new Promise(r => setTimeout(r, 60000))]);
  fs.readFile(path.join(root, p), (err, data) => {
    if (err) { res.writeHead(404); return res.end(); }
    const inj = RNG_HOOKS[p];
    if (inj) data = injectRng(p, data.toString(), inj);
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' }); res.end(data);
  });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const ANGLE = { darwin: 'metal', win32: 'd3d11' }[process.platform] || 'vulkan';
const browser = await puppeteer.launch({ executablePath: args.chrome, headless: true, args: [`--use-angle=${ANGLE}`, '--enable-gpu', '--ignore-gpu-blocklist', '--no-first-run'], protocolTimeout: 600000 });
let failed = 0;
try {
  const open = async (texts) => {
    const page = await browser.newPage();
    page.on('pageerror', e => console.warn('page error:', e.message));
    await page.evaluateOnNewDocument(() => {
      const set = Map.prototype.set;
      window.__texKeys = [];
      Map.prototype.set = function (k, v) { if (typeof k === 'string' && v && v.isTexture) window.__texKeys.push([k, v]); return set.call(this, k, v); };
    });
    await page.evaluateOnNewDocument(installRecorder);
    if (texts) {
      let release; gate = { promise: new Promise(r => { release = r; }) };
      await page.exposeFunction('__releaseMain', (info) => { console.log(`font gate: ${info}`); release(); });
      await page.evaluateOnNewDocument((texts) => {
        const tick = () => {
          const link = document.querySelector('link[rel=stylesheet][href*="fonts.googleapis"]');
          if (!link || !link.sheet) return setTimeout(tick, 10);
          Promise.all(texts.map(([f, t]) => document.fonts.load(f, t).then(l => l.length, () => 0)))
            .then(n => window.__releaseMain(`${texts.length} font/text pairs, ${n.reduce((a, b) => a + b, 0)} faces loaded`));
        };
        tick();
      }, texts);
    }
    const q = new URLSearchParams({ shot: '1', w: '64', h: '64', t: '0' });
    if (args.only) q.set('only', args.only);
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html?${q}`, { waitUntil: 'load', timeout: 180000 });
    await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
    await page.evaluate(() => { window.__cr.off = true; });
    gate = null;
    return page;
  };
  let page = await open(null), gateTexts = null;
  if (!args['no-font-gate']) {
    gateTexts = await page.evaluate(() => [...window.__cr.texts].map(s => { const i = s.indexOf('\u0001'); return [s.slice(0, i), s.slice(i + 1)]; }));
    await page.close();
    page = await open(gateTexts);
  }
  const RNG_OK = rngHooked.size > 0 && [...rngHooked.values()].every(Boolean);
  if (rngHooked.size) console.log(`rng hook: ${[...rngHooked].map(([p, ok]) => `${p} ${ok ? 'counted' : 'NOT FOUND'}`).join(', ')}`);

  // keyed textures -> canvas ids (also used on the second load that measures the canvas floor)
  const collectKeyed = (pg) => pg.evaluate((only) => {
    const CR = window.__cr; const res = []; const seen = new Set();
    window.__texByKey = new Map();
    for (const [key, t] of window.__texKeys) {
      if (seen.has(key)) continue; seen.add(key);
      if (only && !only.includes(key)) continue;
      const img = t.image; const r = img && CR.recs.get(img);
      window.__texByKey.set(key, t);
      res.push({ key, id: r ? r.id : -1, w: img ? img.width : 0, h: img ? img.height : 0, kind: img ? img.constructor.name : 'none' });
    }
    return { res, errors: CR.errors.slice(0, 20), nerr: CR.errors.length };
  }, onlyKeys ? [...onlyKeys] : null);
  const keyed = await collectKeyed(page);
  if (keyed.nerr) console.warn(`recorder errors: ${keyed.nerr}`, keyed.errors);
  const ids = keyed.res.filter(k => k.id >= 0).map(k => k.id);
  const dump = JSON.parse(await page.evaluate((ids) => window.__cr.export(ids), ids));
  const { canvases, clips } = dump;

  // ---------------------------------------------------------------- fonts for text outlines
  const indexHtml = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const GOOGLE = {}; // family -> available weights
  for (const m of indexHtml.matchAll(/fonts\.googleapis\.com\/css2\?([^"']+)/g))
    for (const part of m[1].replace(/&amp;/g, '&').split('&')) {
      if (!part.startsWith('family=')) continue;
      const [fam, spec] = decodeURIComponent(part.slice(7).replace(/\+/g, ' ')).split(':');
      GOOGLE[fam] = spec && spec.startsWith('wght@') ? spec.slice(5).split(';').map(Number) : [400];
    }
  const parseFont = (f) => {
    // canvas font serialisation: [style] [variant] [weight] [stretch] size[/lh] family-list
    const m = /^(.*?)(\d*\.?\d+)px(?:\/\S+)?\s+(.+)$/.exec(f); if (!m) return null;
    let weight = 400, style = 'normal';
    for (const t of m[1].trim().split(/\s+/)) { if (/^\d+$/.test(t)) weight = +t; else if (t === 'bold') weight = 700; else if (t === 'italic' || t === 'oblique') style = t; }
    const fams = m[3].split(',').map(s => s.trim().replace(/^["']|["']$/g, ''));
    return { size: +m[2], weight, style, fams };
  };
  const matchWeight = (avail, w) => {
    if (avail.includes(w)) return w;
    const lo = avail.filter(a => a < w).sort((a, b) => b - a), hi = avail.filter(a => a > w).sort((a, b) => a - b);
    if (w >= 400 && w <= 500) { const mid = avail.filter(a => a > w && a <= 500).sort((a, b) => a - b); return mid[0] ?? lo[0] ?? hi[0]; }
    return w < 400 ? (lo[0] ?? hi[0]) : (hi[0] ?? lo[0]);
  };
  const cached = async (name, fetcher) => { const f = path.join(CACHE, name); if (fs.existsSync(f)) return fs.readFileSync(f); const b = await fetcher(); fs.writeFileSync(f, b); return b; };
  const get = async (url, headers = {}) => { const r = await fetch(url, { headers }); if (!r.ok) throw new Error(`${r.status} ${url}`); return Buffer.from(await r.arrayBuffer()); };
  const otFile = path.join(CACHE, 'opentype-1.3.4.module.js');
  await cached('opentype-1.3.4.module.js', () => get('https://cdn.jsdelivr.net/npm/opentype.js@1.3.4/dist/opentype.module.js'));
  const opentype = (await import(pathToFileURL(otFile).href)).default;
  const FONTS = new Map(), fontChars = new Map(); // "fam|weight" -> [opentype.Font], chars already fetched
  // fetch the TTF subsets (Google Fonts text=) holding every character the given canvases draw as text
  const ensureFonts = async (canvList) => {
    const need = new Map(); // "fam|weight" -> Set(chars)
    for (const c of canvList) for (const it of c.items) if (it.k === 'text') {
      const pf = it.pf || (it.pf = parseFont(it.font)); if (!pf) continue;
      // a stack with no webfont (e.g. plain 'serif') is drawn with a system font; outline it with the nearest webfont
      if (!pf.fams.some(f => GOOGLE[f])) { const sub = pf.fams.includes('serif') && GOOGLE['Noto Serif JP'] ? 'Noto Serif JP' : 'Noto Sans JP'; if (GOOGLE[sub]) { pf.fams.push(sub); pf.substitute = sub; } }
      for (const fam of pf.fams) if (GOOGLE[fam]) {
        const k = fam + '|' + matchWeight(GOOGLE[fam], pf.weight), have = fontChars.get(k);
        for (const [ch] of it.chars) if (!have || !have.has(ch)) { if (!need.has(k)) need.set(k, new Set()); need.get(k).add(ch); }
      }
    }
    for (const [k, set] of need) {
      const [fam, w] = k.split('|'); const chars = [...set].sort();
      if (!FONTS.has(k)) { FONTS.set(k, []); fontChars.set(k, new Set()); }
      for (let i = 0; i < chars.length; i += 150) {
        const text = chars.slice(i, i + 150).join('');
        const h = crypto.createHash('sha1').update(k + text).digest('hex').slice(0, 16);
        const buf = await cached(`font-${h}.ttf`, async () => {
          const css = (await get(`https://fonts.googleapis.com/css2?family=${encodeURIComponent(fam).replace(/%20/g, '+')}:wght@${w}&text=${encodeURIComponent(text)}`, { 'User-Agent': 'curl/8' })).toString();
          const u = /url\((https:[^)]+)\)\s*format\('truetype'\)/.exec(css); if (!u) throw new Error('no truetype in google css for ' + k);
          return get(u[1]);
        });
        FONTS.get(k).push(opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)));
        for (const ch of text) fontChars.get(k).add(ch);
      }
    }
  };
  await ensureFonts(Object.values(canvases));
  const glyphFor = (pf, ch) => {
    for (const fam of pf.fams) {
      if (!GOOGLE[fam]) continue;
      const w = matchWeight(GOOGLE[fam], pf.weight);
      for (const f of FONTS.get(fam + '|' + w) || []) { const g = f.charToGlyph(ch); if (g && g.index > 0) return { g, f, w }; }
    }
    return null;
  };

  // ---------------------------------------------------------------- SVG emission
  const fmt = (v) => { const r = Math.round(v * 100) / 100; return Object.is(r, -0) ? '0' : String(r); };
  const ident = (m) => m[0] === 1 && m[1] === 0 && m[2] === 0 && m[3] === 1 && m[4] === 0 && m[5] === 0;
  const mstr = (m) => `matrix(${m.map(fmt).join(' ')})`;
  const mstrPrecise = (m) => `matrix(${m.map(v => String(Math.round(v * 1e6) / 1e6)).join(' ')})`;
  const mul = (a, b) => [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3], a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5]];
  const invert = (m) => { const det = m[0] * m[3] - m[1] * m[2]; if (!det || !Number.isFinite(det)) return null; const a = m[3] / det, b = -m[1] / det, c = -m[2] / det, d = m[0] / det; return [a, b, c, d, -(a * m[4] + c * m[5]), -(b * m[4] + d * m[5])]; };
  const apply = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const xform = (segs, m) => segs.map(s => { if (s[0] === 'Z') return s; const o = [s[0]]; for (let i = 1; i < s.length; i += 2) o.push(...apply(m, s[i], s[i + 1])); return o; });
  const hex = (c) => '#' + c.slice(0, 3).map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
  const similarity = (m) => { const s1 = m[0] * m[0] + m[1] * m[1], s2 = m[2] * m[2] + m[3] * m[3]; return Math.abs(s1 - s2) <= 1e-6 * Math.max(s1, s2) && Math.abs(m[0] * m[2] + m[1] * m[3]) <= 1e-6 * Math.max(s1, s2) ? Math.sqrt(s1) : 0; };

  function emitCanvas(cid, n, prefix, stats, opts = {}) {
    const cv = canvases[cid]; const W = cv.w, H = cv.h;
    const defs = []; const defIds = new Map(); let seq = 0;
    const U = (k, c = 1) => { stats.unsup[k] = (stats.unsup[k] || 0) + c; };
    for (const [k, v] of Object.entries(cv.unsup)) if (k !== 'pattern') U(k, v); // pattern counted at use
    const def = (keyStr, make) => { let id = defIds.get(keyStr); if (!id) { id = `${prefix}${seq++}`; defIds.set(keyStr, id); defs.push(make(id)); } return id; };
    // path data + curve tally
    const dstr = (segs, count = true) => {
      let out = '', open = false, sx = 0, sy = 0, cx = 0, cy = 0, pendingM = null, lines = 0, quads = 0, cubics = 0;
      for (const s of segs) {
        const t = s[0];
        if (t === 'M') { pendingM = [s[1], s[2]]; sx = cx = s[1]; sy = cy = s[2]; open = false; continue; }
        if (t === 'Z') { if (open) { out += 'Z'; if (Math.hypot(cx - sx, cy - sy) > 1e-3) lines++; cx = sx; cy = sy; open = false; pendingM = [sx, sy]; } continue; }
        if (pendingM) { out += `M${fmt(pendingM[0])} ${fmt(pendingM[1])}`; pendingM = null; open = true; }
        if (t === 'L') { if (fmt(s[1]) === fmt(cx) && fmt(s[2]) === fmt(cy)) continue; out += `L${fmt(s[1])} ${fmt(s[2])}`; lines++; }
        else if (t === 'Q') { out += `Q${fmt(s[1])} ${fmt(s[2])} ${fmt(s[3])} ${fmt(s[4])}`; quads++; }
        else if (t === 'C') { out += `C${fmt(s[1])} ${fmt(s[2])} ${fmt(s[3])} ${fmt(s[4])} ${fmt(s[5])} ${fmt(s[6])}`; cubics++; }
        cx = s[s.length - 2]; cy = s[s.length - 1];
      }
      if (count) { stats.lines += lines; stats.quads += quads; stats.cubics += cubics; }
      return out;
    };
    const bbox = (segs) => { let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity; for (const s of segs) for (let i = 1; i < s.length; i += 2) { x0 = Math.min(x0, s[i]); x1 = Math.max(x1, s[i]); y0 = Math.min(y0, s[i + 1]); y1 = Math.max(y1, s[i + 1]); } return [x0, y0, x1, y1]; };
    const clipId = (cl) => def('clip' + cl, (id) => { const c = clips[cl]; stats.paths++; return `<clipPath id="${id}" clipPathUnits="userSpaceOnUse"><path d="${dstr(c.d)}"${c.rule === 'evenodd' ? ' clip-rule="evenodd"' : ''}/></clipPath>`; });
    const chainOf = (cl) => { const ch = []; while (cl) { ch.unshift(cl); cl = clips[cl].parent; } return ch; };
    const gradId = (p, gm) => { const body = gradBody(p, gm); return def(body('X'), body); };
    // gradient element builder: (id) => xml, with gm as gradientTransform (canvas user space -> element space)
    const gradBody = (p, gm) => {
      const stops = p.stops.slice().sort((a, b) => a[0] - b[0]);
      const st = stops.map(([o, c]) => `<stop offset="${fmt(o)}" stop-color="${hex(c)}"${c[3] < 1 ? ` stop-opacity="${fmt(c[3])}"` : ''}/>`);
      const gt = gm && !ident(gm) ? ` gradientTransform="${mstrPrecise(gm)}"` : '';
      let body;
      if (p.type === 'linear') { const [x1, y1, x2, y2] = p.a; body = (id) => `<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${fmt(x1)}" y1="${fmt(y1)}" x2="${fmt(x2)}" y2="${fmt(y2)}"${gt}>${st.join('')}</linearGradient>`; }
      else {
        const [x0, y0, r0, x1, y1, r1] = p.a; let ss = stops;
        // canvas radial = two circles; concentric with r0>0 -> remap stops onto [r0/r1, 1]; otherwise focal point
        const conc = Math.hypot(x1 - x0, y1 - y0) < 1e-6;
        if (r0 > 0 && r1 > 0) {
          if (conc && r0 < r1) ss = stops.map(([o, c]) => [r0 / r1 + o * (1 - r0 / r1), c]);
          else U('radialGradient:focal-radius');
        }
        const stx = ss.map(([o, c]) => `<stop offset="${fmt(o)}" stop-color="${hex(c)}"${c[3] < 1 ? ` stop-opacity="${fmt(c[3])}"` : ''}/>`);
        const foc = conc ? '' : ` fx="${fmt(x0)}" fy="${fmt(y0)}"`;
        body = (id) => `<radialGradient id="${id}" gradientUnits="userSpaceOnUse" cx="${fmt(x1)}" cy="${fmt(y1)}" r="${fmt(Math.max(r1, 1e-3))}"${foc}${gt}>${stx.join('')}</radialGradient>`;
      }
      return body;
    };
    // paint -> [attrValue, opacity] ; gm = gradient transform (canvas user space -> element space)
    const paintAttr = (p, alpha, gm) => {
      if (p.t === 'c') return p.c ? [hex(p.c), p.c[3] * alpha] : null;
      if (p.t === 'g') {
        if (!p.stops.length) return null;
        if (p.type === 'conic') { U('conicGradient:mean'); const c = [0, 1, 2, 3].map(i => p.stops.reduce((s, x) => s + x[1][i], 0) / p.stops.length); return [hex(c), c[3] * alpha]; }
        return [`url(#${gradId(p, gm)})`, alpha];
      }
      U('pattern'); return null;
    };
    const out = []; // nodes: {clip, xml} or {clip, merge:{...}}
    const pushEl = (clip, xml) => { out.push({ clip, xml }); };
    const render = (list) => {
      let s = ''; let open = [];
      for (const nd of list) {
        const ch = nd.clip ? chainOf(nd.clip) : [];
        let i = 0; while (i < open.length && i < ch.length && open[i] === ch[i]) i++;
        while (open.length > i) { s += '</g>'; open.pop(); }
        for (; i < ch.length; i++) { s += `<g clip-path="url(#${clipId(ch[i])})">`; open.push(ch[i]); stats.groups++; }
        if (nd.merge) { const mg = nd.merge; s += `<path d="${mg.d.join('')}" fill="${mg.fill}"${mg.op < 0.999 ? ` fill-opacity="${fmt3(mg.op)}"` : ''}/>`; stats.paths++; }
        else s += nd.xml;
      }
      while (open.length) { s += '</g>'; open.pop(); }
      return s;
    };
    const fmt3 = (v) => String(Math.round(v * 1000) / 1000);
    const BIG = Math.max(W, H) * 4 + 100;
    const bigRect = `M${-BIG} ${-BIG}L${BIG} ${-BIG}L${BIG} ${BIG}L${-BIG} ${BIG}Z`;
    // remove `segs` (device space) from everything drawn so far; frac = removed fraction (1 = erase)
    const erase = (segs, rule, clip, frac) => {
      const inner = render(out); out.length = 0; if (!inner) return;
      if (rule !== 'evenodd' && segs.filter(s => s[0] === 'M').length > 1) U('erase:complement-approx');
      const kids = [`<path d="${bigRect}${dstr(segs)}" clip-rule="evenodd"/>`];
      for (const cl of chainOf(clip)) kids.push(`<path d="${bigRect}${dstr(clips[cl].d)}" clip-rule="evenodd"/>`);
      const id = `${prefix}${seq++}`; defs.push(`<clipPath id="${id}" clipPathUnits="userSpaceOnUse">${kids.join('')}</clipPath>`); stats.paths += kids.length;
      out.push({ clip: 0, xml: `<g clip-path="url(#${id})">${inner}</g>` }); stats.groups++;
      if (frac < 0.999 && inner.length > 400000) { U('erase:partial-too-large->' + (frac >= 0.5 ? 'full' : 'dropped')); if (frac < 0.5) { out.length = 0; out.push({ clip: 0, xml: inner }); } }
      else if (frac < 0.999) {
        const id2 = `${prefix}${seq++}`; defs.push(`<clipPath id="${id2}" clipPathUnits="userSpaceOnUse"><path d="${dstr(segs)}"${rule === 'evenodd' ? ' clip-rule="evenodd"' : ''}/></clipPath>`); stats.paths++;
        out.push({ clip, xml: `<g clip-path="url(#${id2})" opacity="${fmt3(1 - frac)}">${inner}</g>` }); stats.groups++;
        stats.dupBytes += inner.length;
      }
    };
    const coversCanvas = (segs) => { const [x0, y0, x1, y1] = bbox(segs); return x0 <= 0.01 && y0 <= 0.01 && x1 >= W - 0.01 && y1 >= H - 0.01 && segs.length === 5 && isAxisRect(segs); };
    const isAxisRect = (segs) => { const p = segs.filter(s => s[0] !== 'Z'); if (p.length !== 4) return false; for (let i = 0; i < 4; i++) { const a = p[i], b = p[(i + 1) % 4]; if (Math.abs(a[1] - b[1]) > 1e-6 && Math.abs(a[2] - b[2]) > 1e-6) return false; } return true; };

    const items = cv.items.slice(0, n).filter(it => {
      if (ABLATE === 'text' && it.k === 'text') return false;
      if (ABLATE === 'tiny' && it.k === 'fill') { const bb = bbox(it.d); if ((bb[2] - bb[0]) * (bb[3] - bb[1]) <= 16) return false; }
      return true;
    });

    // ---- stamping (instancing). A run is a stretch of consecutive stampable draws; every draw in it becomes
    // a <use> of a prototype <symbol>, placed by one affine matrix. Runs mix prototypes and end only at a draw
    // that cannot be stamped, so paint order stays exactly the canvas's.
    //  fill protos:   rect (unit square), ellipse (unit circle; only arcs that close exactly), path (first
    //                 instance normalised to its bbox). An instance joins a proto when every point of its path
    //                 is the proto's image under one affine map within STAMP_EPS device px.
    //  stroke protos: the first instance's user-space centreline scaled uniformly into a unit box, with
    //                 fill="none" and the stroke geometry. Canvas strokes are computed in user space and then
    //                 mapped by the CTM, so an instance joins only when its stroked OUTLINE (offset samples
    //                 along every segment, join points, cap points) is the proto outline's affine image within
    //                 STAMP_EPS. Dashed strokes are not stamped.
    //  paint:         solid or linear/radial gradient, on the <use> only. A gradient is expressed in the proto
    //                 frame (gradientTransform = inverse(instance) x canvas CTM); instances whose proto-frame
    //                 gradient field is identical share one gradient element.
    const runAt = new Map(), inRun = new Set();
    const protos = [], bySig = new Map();
    const flat = (segs) => { const o = []; for (const x of segs) for (let i = 1; i < x.length; i += 2) o.push(x[i], x[i + 1]); return o; };
    const mapPts = (m, P) => { const o = new Array(P.length); for (let i = 0; i < P.length; i += 2) { o[i] = m[0] * P[i] + m[2] * P[i + 1] + m[4]; o[i + 1] = m[1] * P[i] + m[3] * P[i + 1] + m[5]; } return o; };
    const fit = (P, Q, idx) => { // affine taking proto pts P onto instance pts Q, solved on 3 anchors, verified on all
      if (P.length !== Q.length) return null;
      const [i0, i1, i2] = idx;
      const px1 = P[2 * i1] - P[2 * i0], py1 = P[2 * i1 + 1] - P[2 * i0 + 1], px2 = P[2 * i2] - P[2 * i0], py2 = P[2 * i2 + 1] - P[2 * i0 + 1];
      const qx1 = Q[2 * i1] - Q[2 * i0], qy1 = Q[2 * i1 + 1] - Q[2 * i0 + 1], qx2 = Q[2 * i2] - Q[2 * i0], qy2 = Q[2 * i2 + 1] - Q[2 * i0 + 1];
      const det = px1 * py2 - px2 * py1; if (Math.abs(det) < 1e-12) return null;
      const a = (qx1 * py2 - qx2 * py1) / det, c = (qx2 * px1 - qx1 * px2) / det, b = (qy1 * py2 - qy2 * py1) / det, d = (qy2 * px1 - qy1 * px2) / det;
      const m = [a, b, c, d, Q[2 * i0] - a * P[2 * i0] - c * P[2 * i0 + 1], Q[2 * i0 + 1] - b * P[2 * i0] - d * P[2 * i0 + 1]];
      for (let i = 0; i < P.length; i += 2) if (Math.abs(m[0] * P[i] + m[2] * P[i + 1] + m[4] - Q[i]) > STAMP_EPS || Math.abs(m[1] * P[i] + m[3] * P[i + 1] + m[5] - Q[i + 1]) > STAMP_EPS) return null;
      return m;
    };
    const anchors = (P) => { // three well-spread, non-collinear points
      const n = P.length / 2; let i1 = 0, best = -1;
      for (let i = 1; i < n; i++) { const dd = (P[2 * i] - P[0]) ** 2 + (P[2 * i + 1] - P[1]) ** 2; if (dd > best) { best = dd; i1 = i; } }
      let i2 = 0; best = -1;
      for (let i = 1; i < n; i++) { const cr = Math.abs((P[2 * i1] - P[0]) * (P[2 * i + 1] - P[1]) - (P[2 * i1 + 1] - P[1]) * (P[2 * i] - P[0])); if (cr > best) { best = cr; i2 = i; } }
      return best > 1e-9 ? [0, i1, i2] : null;
    };
    const K4 = 4 / 3 * Math.tan(Math.PI / 8);
    const PROTO = {
      rect: [['M', 0, 0], ['L', 1, 0], ['L', 1, 1], ['L', 0, 1], ['Z']],
      ellipse: [['M', 1, 0], ['C', 1, K4, K4, 1, 0, 1], ['C', -K4, 1, -1, K4, -1, 0], ['C', -1, -K4, -K4, -1, 0, -1], ['C', K4, -1, 1, -K4, 1, 0], ['Z']],
    };
    const PFLAT = { rect: flat(PROTO.rect), ellipse: flat(PROTO.ellipse) };
    const segCurves = (segs) => { let c = 0, sx = 0, sy = 0, cx = 0, cy = 0; for (const x of segs) { if (x[0] === 'M') { sx = cx = x[1]; sy = cy = x[2]; continue; } if (x[0] === 'Z') { if (Math.hypot(cx - sx, cy - sy) > 1e-9) c++; cx = sx; cy = sy; continue; } c += x[0] === 'C' ? 2 : 1; cx = x[x.length - 2]; cy = x[x.length - 1]; } return c; };
    const addProto = (pr) => { pr.n = protos.length; pr.curves = segCurves(pr.segs); protos.push(pr); if (!bySig.has(pr.sig)) bySig.set(pr.sig, []); bySig.get(pr.sig).push(pr); return pr; };
    const canon = {};
    const canonProto = (kind) => canon[kind] || (canon[kind] = addProto({ kind, sig: kind, segs: PROTO[kind], P: PFLAT[kind], rule: 'nonzero' }));
    const candidates = (sig) => { const l = bySig.get(sig); return l ? l.slice(-256).reverse() : []; };
    const live = (it) => !it.comp && !it.filter && !it.shadow;
    const paintOk = (p) => p.t === 'c' ? !!p.c : p.t === 'g' && p.stops.length > 0 && (p.type === 'linear' ? (p.a[0] !== p.a[2] || p.a[1] !== p.a[3]) : p.type === 'radial' && p.a[5] > 0);
    const opacityOf = (p, alpha) => (p.t === 'c' ? p.c[3] : 1) * alpha;
    const cleanSegs = (d) => { const segs = []; for (let i = 0; i < d.length; i++) { const x = d[i]; if (x[0] === 'M' && (i + 1 >= d.length || d[i + 1][0] === 'M')) continue; segs.push(x); } return segs; };
    const drawing = (x) => x[0] !== 'M' && x[0] !== 'Z';
    const nonsingular = (m) => Math.abs(m[0] * m[3] - m[1] * m[2]) > 1e-12;
    const SKIP = { skip: true }; // paints nothing: neither an instance nor a run break

    // stroke outline samples in the path's own frame. flip mirrors the left/right order, so a reflected
    // instance can still be matched point for point.
    const strokeSamples = (segs, w, cap, join, miter, flip) => {
      const hw = w / 2, sg = flip ? -1 : 1, out = [];
      const subs = []; let cur = null, last = null;
      for (const x of segs) {
        if (x[0] === 'M') { last = [x[1], x[2]]; cur = { start: last, segs: [], closed: false }; subs.push(cur); continue; }
        if (x[0] === 'Z') { if (cur) { cur.closed = true; last = cur.start; } cur = null; continue; }
        if (!last) return null;
        if (!cur) { cur = { start: last, segs: [], closed: false }; subs.push(cur); }
        const pts = [last]; for (let i = 1; i < x.length; i += 2) pts.push([x[i], x[i + 1]]);
        last = pts[pts.length - 1]; cur.segs.push(pts);
      }
      let ext = 0; for (const x of segs) for (let i = 1; i < x.length; i++) ext = Math.max(ext, Math.abs(x[i]));
      const tiny = 1e-9 * (1 + ext);
      const same = (a, b) => Math.abs(a[0] - b[0]) <= tiny && Math.abs(a[1] - b[1]) <= tiny;
      const ev = (p, t) => {
        const u = 1 - t;
        if (p.length === 2) return [[u * p[0][0] + t * p[1][0], u * p[0][1] + t * p[1][1]], [p[1][0] - p[0][0], p[1][1] - p[0][1]]];
        if (p.length === 3) return [[u * u * p[0][0] + 2 * u * t * p[1][0] + t * t * p[2][0], u * u * p[0][1] + 2 * u * t * p[1][1] + t * t * p[2][1]],
          [2 * u * (p[1][0] - p[0][0]) + 2 * t * (p[2][0] - p[1][0]), 2 * u * (p[1][1] - p[0][1]) + 2 * t * (p[2][1] - p[1][1])]];
        return [[u * u * u * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t * t * t * p[3][0], u * u * u * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t * t * t * p[3][1]],
          [3 * u * u * (p[1][0] - p[0][0]) + 6 * u * t * (p[2][0] - p[1][0]) + 3 * t * t * (p[3][0] - p[2][0]), 3 * u * u * (p[1][1] - p[0][1]) + 6 * u * t * (p[2][1] - p[1][1]) + 3 * t * t * (p[3][1] - p[2][1])]];
      };
      const unit = (d) => { const l = Math.hypot(d[0], d[1]); return l > tiny ? [d[0] / l, d[1] / l] : null; };
      const dirAt = (p, t) => unit(ev(p, t)[1]) || unit([ev(p, Math.min(1, t + 1e-3))[0][0] - ev(p, Math.max(0, t - 1e-3))[0][0], ev(p, Math.min(1, t + 1e-3))[0][1] - ev(p, Math.max(0, t - 1e-3))[0][1]]) || unit([p[p.length - 1][0] - p[0][0], p[p.length - 1][1] - p[0][1]]);
      const joinPts = (c, a, b) => { // geometric (flip-independent) join points, ordered incoming -> outgoing
        const cr = a[0] * b[1] - a[1] * b[0], dt = a[0] * b[0] + a[1] * b[1];
        if (Math.abs(cr) < 1e-9 && dt > 0) return;
        const na = [-a[1], a[0]], nb = [-b[1], b[0]], sd = cr > 0 ? -1 : 1;
        if (join === 'round') {
          const a0 = Math.atan2(sd * na[1], sd * na[0]); let sw = Math.atan2(sd * nb[1], sd * nb[0]) - a0;
          while (sw > Math.PI) sw -= 2 * Math.PI; while (sw <= -Math.PI) sw += 2 * Math.PI;
          for (let i = 1; i <= 3; i++) { const t = a0 + sw * i / 4; out.push(c[0] + hw * Math.cos(t), c[1] + hw * Math.sin(t)); }
        } else if (join === 'miter') {
          const den = 1 + na[0] * nb[0] + na[1] * nb[1];
          if (den > 1e-12 && Math.sqrt(2 / den) <= miter) out.push(c[0] + sd * hw * (na[0] + nb[0]) / den, c[1] + sd * hw * (na[1] + nb[1]) / den);
        }
      };
      const capPts = (c, T, outward) => {
        const o = [T[0] * outward, T[1] * outward], n = [-T[1] * sg, T[0] * sg];
        if (cap === 'square') out.push(c[0] + hw * (n[0] + o[0]), c[1] + hw * (n[1] + o[1]), c[0] + hw * (-n[0] + o[0]), c[1] + hw * (-n[1] + o[1]));
        else if (cap === 'round') for (let k = 1; k <= 5; k++) { const f = k * Math.PI / 6; out.push(c[0] + hw * (Math.cos(f) * n[0] + Math.sin(f) * o[0]), c[1] + hw * (Math.cos(f) * n[1] + Math.sin(f) * o[1])); }
      };
      for (const sp of subs) {
        // canvas prunes zero-length segments and subpaths with no lines before stroking
        const S = sp.segs.filter(p => !p.every(q => same(q, p[0])));
        if (sp.closed) { const e = S.length ? S[S.length - 1][S[S.length - 1].length - 1] : null; if (e && !same(e, sp.start)) S.push([e, sp.start]); }
        if (!S.length) continue;
        for (const p of S) {
          const n = p.length === 2 ? 1 : 6;
          for (let j = 0; j <= n; j++) {
            const t = j / n, c = ev(p, t)[0], d = dirAt(p, t); if (!d) return null;
            const nx = -d[1] * sg * hw, ny = d[0] * sg * hw;
            out.push(c[0] + nx, c[1] + ny, c[0] - nx, c[1] - ny);
          }
        }
        const nj = sp.closed ? S.length : S.length - 1;
        for (let k = 0; k < nj; k++) { const A = S[k], B = S[(k + 1) % S.length], a = dirAt(A, 1), b = dirAt(B, 0); if (!a || !b) return null; joinPts(A[A.length - 1], a, b); }
        if (!sp.closed) { const L = S[S.length - 1], a = dirAt(S[0], 0), b = dirAt(L, 1); if (!a || !b) return null; capPts(S[0][0], a, -1); capPts(L[L.length - 1], b, 1); }
      }
      return out;
    };

    const fillInstance = (it) => {
      if (!live(it) || !paintOk(it.paint)) return null;
      if (!(opacityOf(it.paint, it.alpha) > 0)) return SKIP;
      const segs = cleanSegs(it.d); if (!segs.some(drawing)) return SKIP;
      if (segs.length > 400) return null;
      const types = segs.map(x => x[0]).join(''), Q = flat(segs);
      let m = null, proto = null;
      if (types === 'MLLLZ' && it.rule === 'nonzero' && (m = fit(PFLAT.rect, Q, [0, 1, 3]))) proto = canonProto('rect');
      else if ((types === 'MCCCCZ' || types === 'MCCCC') && Math.hypot(Q[Q.length - 2] - Q[0], Q[Q.length - 1] - Q[1]) <= 1e-6 * (1 + Math.abs(Q[0]) + Math.abs(Q[1])) &&
        (m = fit(PFLAT.ellipse.slice(0, Q.length), Q, [0, 3, 6]))) proto = canonProto('ellipse');
      else {
        // a full ellipse only when exactly closed: arc(.., 0, 6.28) leaves a gap and stays 'path' kind
        const sig = 'f:' + it.rule + ':' + types;
        for (const pr of candidates(sig)) if ((m = fit(pr.P, Q, pr.anchors))) { proto = pr; break; }
        if (!proto) {
          const bb = bbox(segs), w = bb[2] - bb[0], h = bb[3] - bb[1];
          if (!(w > 1e-6 && h > 1e-6)) return SKIP; // zero-area fill paints nothing
          const segsN = segs.map(x => x[0] === 'Z' ? x : [x[0], ...x.slice(1).map((v, i) => i % 2 ? (v - bb[1]) / h : (v - bb[0]) / w)]);
          const P = flat(segsN), an = anchors(P); if (!an) return SKIP;
          proto = addProto({ kind: 'path', sig, segs: segsN, P, anchors: an, rule: it.rule }); m = [w, 0, 0, h, bb[0], bb[1]];
        }
      }
      return nonsingular(m) ? { proto, m } : SKIP;
    };

    const strokeInstance = (it) => {
      if (!live(it) || !paintOk(it.paint) || (it.dash && it.dash.length)) return null;
      if (!(it.lw > 0) || !(opacityOf(it.paint, it.alpha) > 0)) return SKIP;
      const Ci = invert(it.m); if (!Ci) return null;
      const u = xform(cleanSegs(it.d), Ci);
      if (!u.some(drawing)) return SKIP;
      if (u.length > 400) return null;
      const types = u.map(x => x[0]).join('');
      const sig = `s:${types}:${it.cap}:${it.join}:${it.join === 'miter' ? fmt3(it.miter) : ''}`;
      const S0 = strokeSamples(u, it.lw, it.cap, it.join, it.miter, false);
      if (!S0) return null; if (!S0.length) return SKIP;
      const Q = mapPts(it.m, S0); let Qf;
      for (const pr of candidates(sig)) {
        let m = fit(pr.P, Q, pr.anchors);
        if (!m) { if (Qf === undefined) { const S1 = strokeSamples(u, it.lw, it.cap, it.join, it.miter, true); Qf = S1 ? mapPts(it.m, S1) : null; } if (Qf) m = fit(pr.P, Qf, pr.anchors); }
        if (m && nonsingular(m)) return { proto: pr, m };
      }
      const bb = bbox(u), D = Math.max(bb[2] - bb[0], bb[3] - bb[1]); if (!(D > 1e-9)) return null;
      const segsN = xform(u, [1 / D, 0, 0, 1 / D, -bb[0] / D, -bb[1] / D]), st = { s: it.lw / D, cap: it.cap, join: it.join, miter: it.miter };
      const P = strokeSamples(segsN, st.s, st.cap, st.join, st.miter, false), an = P && P.length ? anchors(P) : null; if (!an) return null;
      return { proto: addProto({ kind: 'stroke', sig, segs: segsN, P, anchors: an, stroke: st }), m: mul(it.m, [D, 0, 0, D, bb[0], bb[1]]) };
    };

    if (opts.stamp ?? STAMP) {
      // rng hook: did the page call its seeded rng / noise since the previous draw on this canvas?
      let lastRg = 0; const rgOf = items.map(it => (lastRg = it.rg ?? lastRg));
      const rngNew = rgOf.map((g, i) => i > 0 && g > rgOf[i - 1]);
      let run = null;
      const close = () => {
        if (run && run.members.length >= STAMP_MIN) {
          // keep a run only when it re-uses prototypes (expanded curves > curves of its distinct protos)
          let exp = 0; const uniq = new Map();
          for (const mb of run.members) { exp += mb.proto.curves; uniq.set(mb.proto, mb.proto.curves); }
          let cost = 0; for (const c of uniq.values()) cost += c;
          if (exp > cost) { runAt.set(run.idxs[0], run); for (const i of run.idxs) inRun.add(i); }
        }
        run = null;
      };
      items.forEach((it, idx) => {
        const inst = it.k === 'fill' ? fillInstance(it) : it.k === 'stroke' ? strokeInstance(it) : null;
        if (!inst) return close();
        if (run && run.clip !== it.clip) close();
        if (!run) run = { clip: it.clip, members: [], idxs: [] };
        run.idxs.push(idx);
        if (!inst.skip) run.members.push({ idx, it, proto: inst.proto, m: inst.m, rngNew: rngNew[idx] });
      });
      close();
    }

    const f6 = (v) => { const r = Math.round(v * 1e6) / 1e6; return Object.is(r, -0) ? '0' : String(r); };
    const protoD = (segs) => segs.map(x => x[0] === 'Z' ? 'Z' : x[0] + x.slice(1).map(f6).join(' ')).join('');
    const symbolXml = (id, pr) => {
      if (pr.kind === 'stroke') {
        const st = pr.stroke; let a = ` fill="none" stroke-width="${+st.s.toPrecision(7)}"`;
        if (st.cap !== 'butt') a += ` stroke-linecap="${st.cap}"`;
        if (st.join !== 'miter') a += ` stroke-linejoin="${st.join}"`; else a += ` stroke-miterlimit="${fmt3(st.miter)}"`;
        return `<symbol id="${id}" data-stamp-kind="stroke" overflow="visible"><path d="${protoD(pr.segs)}"${a}/></symbol>`;
      }
      return `<symbol id="${id}" data-stamp-kind="${pr.kind}" overflow="visible"><path d="${protoD(pr.segs)}"${pr.rule === 'evenodd' ? ' fill-rule="evenodd"' : ''}/></symbol>`;
    };
    // canonical key of a gradient field in the proto frame (G maps canvas user space -> proto frame)
    const r6 = (v) => String(Math.round(v * 1e6) / 1e6);
    const stopKey = (stops) => stops.slice().sort((a, b) => a[0] - b[0]).map(([o, c]) => r6(o) + ':' + c.map(v => r6(v)).join(',')).join(';');
    const gradFieldKey = (p, G) => {
      if (p.type === 'linear') {
        const Gi = invert(G); if (!Gi) return null;
        const [x0, y0, x1, y1] = p.a, dx = x1 - x0, dy = y1 - y0, L2 = dx * dx + dy * dy, ux = dx / L2, uy = dy / L2;
        return ['L', ux * Gi[0] + uy * Gi[1], ux * Gi[2] + uy * Gi[3], ux * (Gi[4] - x0) + uy * (Gi[5] - y0)].map(v => typeof v === 'number' ? r6(v) : v).join(',');
      }
      const [x0, y0, r0, x1, y1, r1] = p.a, E = mul(G, [r1, 0, 0, r1, x1, y1]);
      if (Math.hypot(x1 - x0, y1 - y0) <= 1e-9 * (1 + r1)) return ['R', E[0] * E[0] + E[2] * E[2], E[0] * E[1] + E[2] * E[3], E[1] * E[1] + E[3] * E[3], E[4], E[5], r0 / r1].map(v => typeof v === 'number' ? r6(v) : v).join(',');
      return ['F', ...E, (x0 - x1) / r1, (y0 - y1) / r1, r0 / r1].map(v => typeof v === 'number' ? r6(v) : v).join(',');
    };
    const useXml = (mb) => {
      const pr = mb.proto, it = mb.it, id = def('proto:' + pr.n, (id) => symbolXml(id, pr));
      let paint, op;
      if (it.paint.t === 'c') { paint = hex(it.paint.c); op = it.paint.c[3] * it.alpha; }
      else {
        const G = mul(invert(mb.m), it.m), fk = gradFieldKey(it.paint, G);
        const key = 'sgrad:' + fk + '|' + stopKey(it.paint.stops);
        const gid = def(key, gradBody(it.paint, G)); paint = `url(#${gid})`; op = it.alpha;
        stats.stampGradIds.add(gid); stats.stampGradUses++;
        // what sharing would give if a common stop-alpha factor moved into fill-opacity (reported only)
        const amax = Math.max(...it.paint.stops.map(s => s[1][3])); stats.stampGradAlphaFactored.add(fk + '|' + stopKey(it.paint.stops.map(([o, c]) => [o, [c[0], c[1], c[2], amax > 0 ? c[3] / amax : 0]])));
      }
      const ref = `href="#${id}" xlink:href="#${id}"`;
      const pa = pr.kind === 'stroke' ? `stroke="${paint}"${op < 0.999 ? ` stroke-opacity="${fmt3(op)}"` : ''}` : `fill="${paint}"${op < 0.999 ? ` fill-opacity="${fmt3(op)}"` : ''}`;
      let info = stats.protoInfo.get(id);
      if (!info) { info = { id, kind: pr.kind, curves: pr.curves, uses: 0 }; if (pr.kind === 'stroke') Object.assign(info, { sig: pr.sig.split(':')[1], cap: pr.stroke.cap, join: pr.stroke.join, lw: [Infinity, -Infinity], paints: new Set() }); stats.protoInfo.set(id, info); }
      info.uses++; stats.uses++; stats.stampCurvesExpanded += pr.curves;
      if (pr.kind === 'stroke') { info.lw[0] = Math.min(info.lw[0], it.lw); info.lw[1] = Math.max(info.lw[1], it.lw); if (info.paints.size < 6) info.paints.add(paint + (op < 0.999 ? '@' + fmt3(op) : '')); }
      else { const bb = bbox(it.d); if ((bb[2] - bb[0]) * (bb[3] - bb[1]) <= 16) { if (it.rect) stats.tinyRects++; else stats.tinyShapes++; } }
      return `<use ${ref} transform="${mstrPrecise(mb.m)}" ${pa}/>`;
    };
    // A run under a clip chain of axis-aligned rectangles: instances lying >= 1 px inside the clip are
    // unaffected by it (antialiasing included), so they are emitted unclipped and stay liftable as stamp
    // layers downstream; the run is split into consecutive inside / touching segments, keeping paint order.
    const clipRect = (cl) => { let x0 = -Infinity, y0 = -Infinity, x1 = Infinity, y1 = Infinity; for (const c of chainOf(cl)) { const segs = cleanSegs(clips[c].d); if (segs.length !== 5 || !isAxisRect(segs)) return null; const b = bbox(segs); x0 = Math.max(x0, b[0]); y0 = Math.max(y0, b[1]); x1 = Math.min(x1, b[2]); y1 = Math.min(y1, b[3]); } return [x0, y0, x1, y1]; };
    const sigmaMax = (m) => { const s = (m[0] * m[0] + m[1] * m[1] + m[2] * m[2] + m[3] * m[3]) / 2, t = Math.hypot((m[0] * m[0] + m[1] * m[1] - m[2] * m[2] - m[3] * m[3]) / 2, m[0] * m[2] + m[1] * m[3]); return Math.sqrt(s + t); };
    const drawBox = (it) => { const b = bbox(cleanSegs(it.d)); if (it.k !== 'stroke') return b; const e = it.lw / 2 * sigmaMax(it.m) * (it.join === 'miter' ? Math.max(1.5, it.miter) : 1.5); return [b[0] - e, b[1] - e, b[2] + e, b[3] + e]; };
    const emitRun = (r) => {
      const cr = r.clip ? clipRect(r.clip) : null;
      const inside = (mb) => { if (!cr) return false; const b = drawBox(mb.it); return b[0] >= cr[0] + 1 && b[1] >= cr[1] + 1 && b[2] <= cr[2] - 1 && b[3] <= cr[3] - 1; };
      const segs = [];
      for (const mb of r.members) { const free = !r.clip || inside(mb); const last = segs[segs.length - 1]; if (last && last.free === free) last.members.push(mb); else segs.push({ free, members: [mb] }); }
      for (const sg of segs) {
        const k = stats.runSeq++;
        let xml = `<g data-stamp-run="${k}">`; const kinds = {}, ids = new Set();
        for (const mb of sg.members) { xml += useXml(mb); ids.add(mb.proto.n); kinds[mb.proto.kind] = (kinds[mb.proto.kind] || 0) + 1; }
        xml += '</g>';
        // procedural vs authored. Elements = stretches of instances between rng events: an element is rng-driven
        // when the page's seeded rng/noise ran since the previous draw (wrapDraw copies share their element).
        // Placement regularity (instances sharing x/y origins, as grids and rows do) is the cross-check.
        const ms = sg.members, n = ms.length;
        const rngEl = ms.filter(mb => mb.rngNew).length, elements = rngEl + (ms[0].rngNew ? 0 : 1), share = rngEl / elements;
        // regularity of the instance origins (0.5 px bins): observed distinct x / y positions against the count
        // expected for uniform random placement over the same range; ~0 for scatter, ~1 for rows and grids
        const axisReg = (vals) => {
          const q = vals.map(v => Math.round(v * 2)), lo = Math.min(...q), M = Math.max(...q) - lo + 1, obs = new Set(q).size;
          const expect = M * (1 - Math.pow(1 - 1 / M, vals.length));
          return expect > 1 ? Math.max(0, Math.min(1, 1 - (obs - 1) / (expect - 1))) : 1;
        };
        const reg = (list) => list.length > 1 ? (axisReg(list.map(mb => mb.m[4])) + axisReg(list.map(mb => mb.m[5]))) / 2 : 1;
        const regularity = reg(ms);
        const byRng = RNG_OK, source = byRng ? (share >= 0.5 ? 'procedural' : 'authored') : (regularity < 0.3 ? 'procedural' : 'authored');
        const amb = [];
        if (byRng && share > 0.15 && share < 0.85) amb.push(`mixed rng share ${share.toFixed(2)}`);
        if (source === 'procedural' && regularity >= 0.6 && n >= 8) amb.push(`rng-driven but regular placement ${regularity.toFixed(2)}`);
        if (source === 'procedural') { // a regular sub-population (e.g. tile outlines) inside an rng-driven run
          const byProto = new Map(); for (const mb of ms) { if (!byProto.has(mb.proto)) byProto.set(mb.proto, []); byProto.get(mb.proto).push(mb); }
          for (const [pr, list] of byProto) if (list.length >= 8 && list.length < n) { const rg = reg(list); if (rg >= 0.8 && !list.some(mb => mb.rngNew)) amb.push(`regular, rng-free sub-grid: ${list.length} ${pr.kind} instances (regularity ${rg.toFixed(2)})`); }
        }
        if (source === 'authored' && byRng && regularity < 0.2 && n >= 32) amb.push(`no rng but irregular placement ${regularity.toFixed(2)}`);
        stats.runs.push({ run: k, instances: n, protos: ids.size, kinds, ...(r.clip ? { clipped: !sg.free } : {}),
          source, rng_share: +share.toFixed(3), regularity: +regularity.toFixed(3), ...(amb.length ? { ambiguous: amb.join('; ') } : {}) });
        stats.groups++;
        out.push({ clip: sg.free ? 0 : r.clip, xml });
      }
    };

    for (const [idx, it] of items.entries()) {
      if (runAt.has(idx)) { emitRun(runAt.get(idx)); continue; }
      if (inRun.has(idx)) continue;
      if (it.k === 'reset') { out.length = 0; continue; }
      if (it.k === 'raster') { continue; }
      if (it.k === 'clear') { if (!it.clip && coversCanvas(it.d)) out.length = 0; else erase(it.d, 'nonzero', it.clip, 1); continue; }
      if (it.shadow) U('shadow');
      if (it.filter) U('filter:' + it.filter.replace(/\(.*$/, ''));
      let alpha = it.alpha;
      let p = it.paint;
      if (it.comp) {
        if (it.comp === 'destination-out') {
          if (it.k === 'fill' && p.t === 'c' && p.c) { erase(it.d, it.rule, it.clip, p.c[3] * alpha); U('globalCompositeOperation:destination-out->clip'); }
          else U('globalCompositeOperation:destination-out:dropped');
          continue;
        }
        if (it.comp === 'multiply' && p.t === 'c' && p.c && Math.abs(p.c[0] - p.c[1]) < 1 && Math.abs(p.c[1] - p.c[2]) < 1) {
          // multiply by grey v over opaque content == black at alpha (1 - v)
          p = { t: 'c', c: [0, 0, 0, (1 - p.c[0] / 255) * p.c[3]] }; U('globalCompositeOperation:multiply->black-alpha');
        } else U('globalCompositeOperation:' + it.comp + ':as-source-over');
      }
      if (it.k === 'fill') {
        if (!it.d.some(s => s[0] !== 'M' && s[0] !== 'Z')) continue;
        const pa = paintAttr(p, alpha, it.m); if (!pa || pa[1] <= 0) continue;
        if (it.rect && p.t === 'c' && it.rule === 'nonzero') {
          // fillRect: normalise winding, merge runs of same-paint rects (exact when opaque or disjoint)
          let segs = it.d; const pts = segs.filter(s => s[0] !== 'Z');
          let area = 0; for (let i = 0; i < 4; i++) { const a = pts[i], b = pts[(i + 1) % 4]; area += a[1] * b[2] - b[1] * a[2]; }
          if (area < 0) segs = [pts[0], ['L', pts[3][1], pts[3][2]], ['L', pts[2][1], pts[2][2]], ['L', pts[1][1], pts[1][2]], ['Z']].map((s, i) => i === 0 ? ['M', s[1], s[2]] : s);
          if (Math.abs(area) / 2 <= 4) stats.tinyRects++;
          const bb = bbox(segs); const last = out[out.length - 1];
          const axis = isAxisRect(segs);
          if (last && last.merge && last.clip === it.clip && last.merge.fill === pa[0] && Math.abs(last.merge.op - pa[1]) < 1e-4 &&
            (pa[1] >= 0.999 || (axis && last.merge.axis && !last.merge.boxes.some(b => b[0] < bb[2] - 1e-6 && bb[0] < b[2] - 1e-6 && b[1] < bb[3] - 1e-6 && bb[1] < b[3] - 1e-6)))) {
            last.merge.d.push(dstr(segs)); if (last.merge.boxes.length < 4000) last.merge.boxes.push(bb); else last.merge.axis = pa[1] >= 0.999 && last.merge.axis; stats.merged++;
          } else out.push({ clip: it.clip, merge: { fill: pa[0], op: pa[1], d: [dstr(segs)], boxes: [bb], axis } });
          continue;
        }
        const op = pa[1];
        { const bb = bbox(it.d); if ((bb[2] - bb[0]) * (bb[3] - bb[1]) <= 16) stats.tinyShapes++; }
        pushEl(it.clip, `<path d="${dstr(it.d)}" fill="${pa[0]}"${op < 0.999 ? ` fill-opacity="${fmt3(op)}"` : ''}${it.rule === 'evenodd' ? ' fill-rule="evenodd"' : ''}/>`); stats.paths++;
        continue;
      }
      if (it.k === 'stroke' || (it.k === 'text' && it.stroke)) {
        if (!(it.lw > 0)) continue;
        const s = similarity(it.m); const im = invert(it.m); if (!im && !s) continue;
        let segs = it.k === 'text' ? textSegs(it, U) : it.d;
        if (!segs || !segs.some(x => x[0] !== 'M' && x[0] !== 'Z')) continue;
        const bake = s > 0; const k = bake ? s : 1;
        const pa = paintAttr(p, alpha, bake ? it.m : null); if (!pa || pa[1] <= 0) continue;
        if (!bake) segs = xform(segs, im);
        let a = ` stroke="${pa[0]}" stroke-width="${fmt3(it.lw * k)}"`;
        if (pa[1] < 0.999) a += ` stroke-opacity="${fmt3(pa[1])}"`;
        if (it.cap !== 'butt') a += ` stroke-linecap="${it.cap}"`;
        if (it.join !== 'miter') a += ` stroke-linejoin="${it.join}"`; else a += ` stroke-miterlimit="${fmt3(it.miter)}"`;
        if (it.dash && it.dash.length) { a += ` stroke-dasharray="${it.dash.map(v => fmt3(v * k)).join(' ')}"`; if (it.dashOff) a += ` stroke-dashoffset="${fmt3(it.dashOff * k)}"`; }
        pushEl(it.clip, `<path d="${dstr(segs)}" fill="none"${a}${bake ? '' : ` transform="${mstrPrecise(it.m)}"`}/>`); stats.paths++;
        continue;
      }
      if (it.k === 'text') {
        const segs = textSegs(it, U); if (!segs || !segs.length) continue;
        const pa = paintAttr(p, alpha, it.m); if (!pa || pa[1] <= 0) continue;
        let extra = '';
        if (it.synth) {
          // Skia fake bold: outline grown by textSize * (1/24 .. 1/32) in total stroke width
          const sz = it.pf.size, ratio = sz <= 9 ? 1 / 24 : sz >= 36 ? 1 / 32 : 1 / 24 + (1 / 32 - 1 / 24) * (sz - 9) / 27;
          const s = similarity(it.m) || Math.sqrt(Math.abs(it.m[0] * it.m[3] - it.m[1] * it.m[2]));
          extra = ` stroke="${pa[0]}" stroke-width="${fmt3(sz * ratio * s)}" stroke-linejoin="round"${pa[1] < 0.999 ? ` stroke-opacity="${fmt3(pa[1])}"` : ''}`; U('text:synthetic-bold');
        }
        pushEl(it.clip, `<path d="${dstr(segs)}" fill="${pa[0]}"${pa[1] < 0.999 ? ` fill-opacity="${fmt3(pa[1])}"` : ''} fill-rule="nonzero"${extra}/>`); stats.paths++;
        continue;
      }
      if (it.k === 'image') {
        const src = canvases[it.src]; if (!src || !it.sw || !it.sh) continue;
        const inner = emitCanvas(it.src, it.n, `${prefix}i${seq++}_`, stats, opts);
        if (!inner.body) continue;
        defs.push(...inner.defs);
        const Tm = mul(it.m, [it.dw / it.sw, 0, 0, it.dh / it.sh, it.dx - it.sx * it.dw / it.sw, it.dy - it.sy * it.dh / it.sh]);
        const x0 = Math.max(0, Math.min(it.sx, it.sx + it.sw)), y0 = Math.max(0, Math.min(it.sy, it.sy + it.sh)), x1 = Math.min(it.W, Math.max(it.sx, it.sx + it.sw)), y1 = Math.min(it.H, Math.max(it.sy, it.sy + it.sh));
        if (x1 <= x0 || y1 <= y0) continue;
        const cid2 = `${prefix}${seq++}`; defs.push(`<clipPath id="${cid2}" clipPathUnits="userSpaceOnUse"><path d="M${fmt(x0)} ${fmt(y0)}H${fmt(x1)}V${fmt(y1)}H${fmt(x0)}Z"/></clipPath>`); stats.paths++; stats.lines += 4;
        pushEl(it.clip, `<g transform="${mstrPrecise(Tm)}"${alpha < 0.999 ? ` opacity="${fmt3(alpha)}"` : ''}><g clip-path="url(#${cid2})">${inner.body}</g></g>`); stats.groups += 2; stats.inlined++;
        continue;
      }
    }
    return { body: render(out), defs, W, H };
  }

  // text -> outline segments in device space
  function textSegs(it, U) {
    const pf = it.pf; if (!pf) { U('text:unparsed-font'); return null; }
    if (!it.ready) U('text:webfont-not-loaded-at-draw');
    if (pf.substitute) U('text:system-font->' + pf.substitute);
    if (pf.style !== 'normal') U('text:synthetic-italic-ignored');
    const segs = [];
    let synth = false;
    for (const [ch, adv] of it.chars) {
      if (/\s/.test(ch)) continue;
      const gf = glyphFor(pf, ch);
      if (!gf) { U('text:missing-glyph'); continue; }
      if (pf.weight >= 600 && gf.w < 600) synth = true;
      const gx = it.x0 + adv * it.sx;
      // Chrome draws canvas text with its baseline snapped to a whole device pixel when the CTM is axis-aligned
      let yb = it.yA; if (!it.m[1] && !it.m[2] && it.m[3]) yb = (Math.round(it.m[3] * it.yA + it.m[5]) - it.m[5]) / it.m[3];
      const local = [it.sx, 0, 0, 1, gx, yb];
      const m = mul(it.m, local);
      for (const c of gf.g.getPath(0, 0, pf.size).commands) {
        if (c.type === 'M') segs.push(['M', ...apply(m, c.x, c.y)]);
        else if (c.type === 'L') segs.push(['L', ...apply(m, c.x, c.y)]);
        else if (c.type === 'Q') segs.push(['Q', ...apply(m, c.x1, c.y1), ...apply(m, c.x, c.y)]);
        else if (c.type === 'C') segs.push(['C', ...apply(m, c.x1, c.y1), ...apply(m, c.x2, c.y2), ...apply(m, c.x, c.y)]);
        else if (c.type === 'Z') segs.push(['Z']);
      }
    }
    it.synth = synth;
    return segs;
  }

  const safe = (k) => { const s = k.replace(/[^A-Za-z0-9._-]+/g, '_'); return s.length > 80 || s !== k ? s.slice(0, 60) + '-' + crypto.createHash('sha1').update(k).digest('hex').slice(0, 8) : s; };
  const freshStats = () => ({ paths: 0, groups: 0, lines: 0, quads: 0, cubics: 0, tinyRects: 0, tinyShapes: 0, merged: 0, runs: [], runSeq: 0, uses: 0, stampCurvesExpanded: 0,
    protoInfo: new Map(), stampGradIds: new Set(), stampGradUses: 0, stampGradAlphaFactored: new Set(), inlined: 0, dupBytes: 0, unsup: {} });
  const wrapSvg = (em) => `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="${em.W}" height="${em.H}" viewBox="0 0 ${em.W} ${em.H}">` +
    (em.defs.length ? `<defs>${em.defs.join('')}</defs>` : '') + em.body + '</svg>\n';
  const results = [];
  for (const kk of keyed.res) {
    const stats = freshStats();
    if (kk.id < 0) { results.push({ ...kk, file: null, error: `texture image is ${kk.kind}, not a recorded canvas` }); continue; }
    const cv = canvases[kk.id];
    const em = emitCanvas(kk.id, cv.items.length, 'p', stats);
    const svg = wrapSvg(em);
    const ops = cv.ops;
    results.push({ ...kk, file: safe(kk.key) + '.svg', svg, stats, ops });
  }

  // ---------------------------------------------------------------- metric: ONE implementation, injected into the pages
  // A = reference RGBA, B = candidate RGBA (getImageData, unpremultiplied), both w x h.
  //  mae      alpha-weighted mean |linear RGB| difference (weight = max alpha of the two pixels)
  //  cov1px   share of alpha>=0.5 pixels in either image with a covered pixel within 1 px in the other
  function scoreRGBA(A, B, w, h) {
    let LIN = scoreRGBA.LIN;
    if (!LIN) { LIN = scoreRGBA.LIN = new Float32Array(256); for (let i = 0; i < 256; i++) { const c = i / 255; LIN[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); } }
    let sw = 0, se = 0, ae = 0, inter = 0, uni = 0;
    for (let p = 0; p < A.length; p += 4) {
      const aa = A[p + 3] / 255, ab = B[p + 3] / 255, wgt = Math.max(aa, ab);
      ae += Math.abs(aa - ab);
      const ia = aa >= 0.5, ib = ab >= 0.5; if (ia || ib) { uni++; if (ia && ib) inter++; }
      if (!wgt) continue;
      const e = (Math.abs(LIN[A[p]] - LIN[B[p]]) + Math.abs(LIN[A[p + 1]] - LIN[B[p + 1]]) + Math.abs(LIN[A[p + 2]] - LIN[B[p + 2]])) / 3;
      sw += wgt; se += wgt * e;
    }
    const n = A.length / 4;
    const cov = (D) => { const m = new Uint8Array(w * h); for (let i = 0; i < w * h; i++) m[i] = D[i * 4 + 3] >= 128 ? 1 : 0; return m; };
    const ca = cov(A), cb = cov(B);
    const near = (m, x, y) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const xx = x + dx, yy = y + dy; if (xx >= 0 && yy >= 0 && xx < w && yy < h && m[yy * w + xx]) return true; } return false; };
    let na = 0, nb = 0, ma = 0, mb = 0;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const i = y * w + x; if (ca[i]) { na++; if (cb[i] || near(cb, x, y)) ma++; } if (cb[i]) { nb++; if (ca[i] || near(ca, x, y)) mb++; } }
    // sw / se (weight and weighted-error sums) let a floor be expressed in a key's own units: se_floor / sw_key
    return { mae: sw ? se / sw : 0, alphaMae: ae / n, iou: uni ? inter / uni : 1, cov1px: na + nb ? (ma + mb) / (na + nb) : 1, sw, se };
  }
  const installHelpers = (pg) => pg.evaluate((src) => {
    window.__score = eval('(' + src + ')');
    window.__hash = async (u8) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', u8))).map(b => b.toString(16).padStart(2, '0')).join('');
    // CPU-backed canvas: the GPU path rounds translucent fills differently depending on the SVG's structure
    // (+-3/255 on 0.3-alpha fills), which is renderer noise, not a difference in the SVG
    window.__svgRaster = async (svg, w, h) => {
      const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' })); const img = new Image(); img.src = url;
      try { await img.decode(); } catch (e) { URL.revokeObjectURL(url); return null; }
      const oc = document.createElement('canvas'); oc.width = w; oc.height = h; const og = oc.getContext('2d', { willReadFrequently: true });
      og.drawImage(img, 0, 0, w, h); URL.revokeObjectURL(url);
      return { canvas: oc, data: og.getImageData(0, 0, w, h).data };
    };
    window.__b64 = (u8) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); };
    window.__unb64 = (b) => { const s = atob(b); const u = new Uint8ClampedArray(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i); return u; };
  }, scoreRGBA.toString());

  // ---------------------------------------------------------------- verify: rasterize SVG, compare with the real canvas
  await installHelpers(page);
  const scores = {};
  const todo = results.filter(r => r.svg);
  for (let i = 0; i < todo.length; i += 20) {
    const batch = todo.slice(i, i + 20).map(r => [r.key, r.svg]);
    Object.assign(scores, await page.evaluate(async (batch, png) => {
      const res = {};
      for (const [key, svg] of batch) {
        const c = window.__texByKey.get(key).image, w = c.width, h = c.height;
        const A = c.getContext('2d').getImageData(0, 0, w, h).data;
        const r = await window.__svgRaster(svg, w, h); if (!r) { res[key] = { error: 'svg decode failed' }; continue; }
        res[key] = { ...window.__score(A, r.data, w, h), hashReal: await window.__hash(A), hashSvg: await window.__hash(r.data) };
        if (png) res[key].png = [c.toDataURL('image/png'), r.canvas.toDataURL('image/png')];
      }
      return res;
    }, batch, !!args.png));
  }

  // ---------------------------------------------------------------- floors: rung 0 of the residual ladder
  //  (a) canvas floor  the real canvas against itself: a second, independent page load (same URL, seed, t=0,
  //                    font gate), each keyed canvas compared with the first load's
  //  (b) svg floor     the SVG raster against itself: the same SVG rasterized independently in the second page
  //  (c) raster floor  content both paths draw identically, drawn through the canvas API vs the same content
  //                    as SVG (recorded by this recorder, emitted by this emitter, rasterized like the residual):
  //                    the key's own pixel-aligned solid rects, full circles/ellipses (native arc) and text runs
  //                    (fillText); a key with none gets a generic scene of its size (four pixel-aligned rects,
  //                    one circle, one text run). Same metric throughout; byte-identical pixels score exactly 0.
  const floors = {};
  const ZERO = { mae: 0, alphaMae: 0, iou: 1, cov1px: 1 };
  if (!args['no-floors']) {
    const cleanG = (d) => d.filter((x, i) => !(x[0] === 'M' && (i + 1 >= d.length || d[i + 1][0] === 'M')));
    const isInt = (v) => Math.abs(v - Math.round(v)) < 1e-6;
    const floorOps = (cv) => {
      const ops = [], backdrops = []; let nr = 0, ne = 0, nt = 0, nb = 0;
      for (const it of cv.items) {
        // clips are ignored: both sides draw the same unclipped content, which is all the floor needs
        if (it.comp || it.filter || it.shadow || !it.paint || it.paint.t !== 'c' || !it.paint.c) continue;
        if (it.k === 'fill') {
          const segs = cleanG(it.d), types = segs.map(x => x[0]).join('');
          if (it.rect && types === 'MLLLZ') {
            const p = segs.slice(0, 4), xs = p.map(q => q[1]), ys = p.map(q => q[2]);
            const axis = p.every((q, i) => { const r = p[(i + 1) % 4]; return Math.abs(q[1] - r[1]) < 1e-6 || Math.abs(q[2] - r[2]) < 1e-6; });
            if (axis && [...xs, ...ys].every(isInt)) { ops.push({ t: 'rect', x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys), c: it.paint.c, a: it.alpha }); nr++; }
          } else if (types === 'MCCCC' || types === 'MCCCCZ') {
            const P0 = [segs[0][1], segs[0][2]], P1 = [segs[1][5], segs[1][6]], P2 = [segs[2][5], segs[2][6]], E = [segs[4][5], segs[4][6]];
            if (Math.hypot(E[0] - P0[0], E[1] - P0[1]) <= 1e-6 * (1 + Math.abs(P0[0]) + Math.abs(P0[1]))) {
              const cx = (P0[0] + P2[0]) / 2, cy = (P0[1] + P2[1]) / 2;
              ops.push({ t: 'ell', m: [P0[0] - cx, P0[1] - cy, P1[0] - cx, P1[1] - cy, cx, cy], c: it.paint.c, a: it.alpha }); ne++;
            }
          }
        } else if (it.k === 'text' && !it.stroke) {
          ops.push({ t: 'text', m: it.m, font: it.font, text: it.chars.map(c => c[0]).join(''), x: it.x0, y: it.yA, maxW: it.sx < 1 ? it.w * it.sx : 0, c: it.paint.c, a: it.alpha }); nt++;
          // glyph blending depends on what is under the text: give the run a pixel-aligned backdrop in the colour
          // of the latest opaque solid fill that covers it (signs draw text on rounded or path backgrounds,
          // which are not floor content themselves)
          const size = (/(\d*\.?\d+)px/.exec(it.font) || [0, 16])[1] * 1;
          const pts = [[it.x0, it.yA - size * 1.1], [it.x0 + it.w * it.sx, it.yA - size * 1.1], [it.x0, it.yA + size * 0.35], [it.x0 + it.w * it.sx, it.yA + size * 0.35]]
            .map(([x, y]) => [it.m[0] * x + it.m[2] * y + it.m[4], it.m[1] * x + it.m[3] * y + it.m[5]]);
          const tb = [Math.min(...pts.map(p => p[0])), Math.min(...pts.map(p => p[1])), Math.max(...pts.map(p => p[0])), Math.max(...pts.map(p => p[1]))];
          for (let j = cv.items.indexOf(it) - 1; j >= 0; j--) {
            const b = cv.items[j]; if (b.k !== 'fill' || b.comp || !b.paint || b.paint.t !== 'c' || !b.paint.c || b.paint.c[3] * b.alpha < 0.999) continue;
            const bx = b.d.filter(x => x[0] !== 'Z'); const xs = bx.flatMap(x => x.filter((v, i) => i % 2 === 1)), ys = bx.flatMap(x => x.filter((v, i) => i > 0 && i % 2 === 0));
            if (Math.min(...xs) <= tb[0] && Math.min(...ys) <= tb[1] && Math.max(...xs) >= tb[2] && Math.max(...ys) >= tb[3]) {
              const x0 = Math.floor(tb[0]) - 2, y0 = Math.floor(tb[1]) - 2; backdrops.push({ t: 'rect', x: x0, y: y0, w: Math.ceil(tb[2]) + 2 - x0, h: Math.ceil(tb[3]) + 2 - y0, c: b.paint.c, a: 1 }); nb++;
              break;
            }
          }
        }
      }
      return { ops: [...backdrops, ...ops], scene: `own: ${nr} rects, ${ne} circles/ellipses, ${nt} text runs` + (nb ? ` (${nb} on backdrops)` : '') };
    };
    const genericOps = (w, h) => {
      const ops = [], hw = Math.floor(w / 2), hh = Math.floor(h / 2), cols = [[214, 206, 190, 1], [120, 140, 170, 1], [200, 90, 110, 1], [90, 130, 90, 1]];
      [[0, 0, hw, hh], [hw, 0, w - hw, hh], [0, hh, hw, h - hh], [hw, hh, w - hw, h - hh]].forEach(([x, y, ww, hh2], i) => ops.push({ t: 'rect', x, y, w: ww, h: hh2, c: cols[i], a: 1 }));
      const r = Math.min(w, h) * 0.3; ops.push({ t: 'ell', m: [r, 0, 0, r, w / 2, h / 2], c: [250, 245, 235, 1], a: 1 });
      ops.push({ t: 'text', m: [1, 0, 0, 1, 0, 0], font: `700 ${Math.max(10, Math.round(Math.min(w, h) / 8))}px "Noto Sans JP", sans-serif`, text: '桜ヶ丘 Sakuragaoka', x: Math.round(w * 0.08), y: Math.round(h * 0.62), maxW: 0, c: [40, 40, 60, 1], a: 1 });
      return { ops, scene: 'generic: 4 pixel-aligned rects, 1 circle, 1 text run' };
    };
    const live = keyed.res.filter(k => k.id >= 0 && scores[k.key] && !scores[k.key].error);
    const scenes = {}, specs = live.map(k => { const f = floorOps(canvases[k.id]), s = f.ops.length ? f : genericOps(k.w, k.h); scenes[k.key] = s.scene; return [k.key, k.w, k.h, s.ops]; });
    const fr = await page.evaluate(async (specs) => {
      const CR = window.__cr; window.__floorCanvas = new Map(); const ids = {};
      for (const [key, w, h, ops] of specs) {
        const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d');
        CR.allow.add(c);
        for (const op of ops) {
          g.save(); g.globalAlpha = op.a; g.fillStyle = `rgba(${op.c[0]},${op.c[1]},${op.c[2]},${op.c[3]})`;
          if (op.t === 'rect') { g.setTransform(1, 0, 0, 1, 0, 0); g.fillRect(op.x, op.y, op.w, op.h); }
          else if (op.t === 'ell') { g.setTransform(...op.m); g.beginPath(); g.arc(0, 0, 1, 0, Math.PI * 2); g.fill(); }
          else {
            try { await document.fonts.load(op.font, op.text); } catch (e) { }
            g.setTransform(...op.m); g.font = op.font; g.textAlign = 'left'; g.textBaseline = 'alphabetic';
            if (op.maxW) g.fillText(op.text, op.x, op.y, op.maxW); else g.fillText(op.text, op.x, op.y);
          }
          g.restore();
        }
        CR.allow.delete(c);
        const r = CR.recs.get(c); if (r) ids[key] = r.id;
        window.__floorCanvas.set(key, c);
      }
      return { ids, dump: CR.export(Object.values(ids)) };
    }, specs);
    const fd = JSON.parse(fr.dump); Object.assign(canvases, fd.canvases); Object.assign(clips, fd.clips);
    await ensureFonts(Object.values(fd.canvases));
    const floorSvgs = Object.entries(fr.ids).map(([key, id]) => [key, wrapSvg(emitCanvas(id, canvases[id].items.length, 'f', freshStats(), { stamp: false }))]);
    const rasterFloor = {};
    for (let i = 0; i < floorSvgs.length; i += 20) Object.assign(rasterFloor, await page.evaluate(async (batch) => {
      const res = {};
      for (const [key, svg] of batch) {
        const c = window.__floorCanvas.get(key), w = c.width, h = c.height, A = c.getContext('2d').getImageData(0, 0, w, h).data;
        const r = await window.__svgRaster(svg, w, h); res[key] = r ? window.__score(A, r.data, w, h) : { error: 'svg decode failed' };
        window.__floorCanvas.delete(key);
      }
      return res;
    }, floorSvgs.slice(i, i + 20)));

    // (a) + (b): an independent second load; exact hashes first, pixels move between pages only on a mismatch
    const page2 = await open(gateTexts);
    await installHelpers(page2);
    await collectKeyed(page2);
    const h2 = {};
    for (let i = 0; i < todo.length; i += 20) Object.assign(h2, await page2.evaluate(async (batch) => {
      const res = {};
      for (const [key, svg] of batch) {
        const t = window.__texByKey.get(key); if (!t || !t.image) { res[key] = null; continue; }
        const c = t.image, w = c.width, h = c.height, A = c.getContext('2d').getImageData(0, 0, w, h).data;
        const r = await window.__svgRaster(svg, w, h);
        res[key] = { w, h, hashReal: await window.__hash(A), hashSvg: r ? await window.__hash(r.data) : null };
      }
      return res;
    }, todo.slice(i, i + 20).map(r => [r.key, r.svg])));
    for (const r of todo) {
      const s1 = scores[r.key], s2 = h2[r.key];
      if (!s1 || s1.error || !s2 || s2.w !== r.w || s2.h !== r.h) { floors[r.key] = { canvas: { error: 'missing or resized on the second load' }, svg: { error: 'n/a' }, raster: rasterFloor[r.key] || { error: 'n/a' }, scene: scenes[r.key] }; continue; }
      let canvas = { ...ZERO, identical: true }, svgF = { ...ZERO, identical: true };
      if (s2.hashReal !== s1.hashReal) {
        const b = await page2.evaluate((key) => { const c = window.__texByKey.get(key).image; return window.__b64(c.getContext('2d').getImageData(0, 0, c.width, c.height).data); }, r.key);
        canvas = { ...await page.evaluate((key, b) => { const c = window.__texByKey.get(key).image; return window.__score(c.getContext('2d').getImageData(0, 0, c.width, c.height).data, window.__unb64(b), c.width, c.height); }, r.key, b), identical: false };
      }
      if (s2.hashSvg !== s1.hashSvg) {
        const b = s2.hashSvg ? await page2.evaluate(async (svg, w, h) => { const x = await window.__svgRaster(svg, w, h); return x && window.__b64(x.data); }, r.svg, r.w, r.h) : null;
        svgF = b ? { ...await page.evaluate(async (svg, w, h, b, h1) => { const x = await window.__svgRaster(svg, w, h); return { ...window.__score(x.data, window.__unb64(b), w, h), page1_reraster_same: (await window.__hash(x.data)) === h1 }; }, r.svg, r.w, r.h, b, s1.hashSvg), identical: false } : { error: 'svg decode failed on the second load' };
      }
      floors[r.key] = { canvas, svg: svgF, raster: rasterFloor[r.key] || { error: 'no floor scene' }, scene: scenes[r.key] };
    }
    await page2.close();
  }

  // ---------------------------------------------------------------- write
  if (args.png) { fs.mkdirSync(args.png, { recursive: true }); for (const r of todo) { const sc = scores[r.key]; if (!sc || !sc.png) continue; for (const [i, tag] of [[0, 'real'], [1, 'svg']]) fs.writeFileSync(path.join(args.png, r.file.replace(/[.]svg$/, `.${tag}.png`)), Buffer.from(sc.png[i].split(',')[1], 'base64')); } }
  fs.mkdirSync(outDir, { recursive: true });
  if (!onlyKeys) for (const f of fs.readdirSync(outDir)) if (f.endsWith('.svg')) fs.unlinkSync(path.join(outDir, f));
  const manifest = {
    generated_by: 'tools/oracle/canvas_svg.mjs', only: args.only || null,
    thresholds: {
      mae: MAE_MAX, cov_1px: COV_MIN,
      why: [
        'mae = alpha-weighted mean |linear RGB| difference between the real canvas and this SVG, rasterized by the same browser on a CPU-backed canvas. On the 120 port keys correct output scores median 0.0032, p90 0.0083, worst 0.0172 (plaza-bag-logo: small text; Skia draws canvas glyph masks with a contrast/gamma boost, 3-12% heavier in alpha than the true outline). Dropping the text (--ablate text) scores median 0.0665 and fails 52 of the 53 text keys, so 0.02 sits above antialiasing, text gamma and gradient dithering and below missing content.',
        'Scoring raster: the CPU raster dithers gradients and the GPU-drawn originals do not, which adds up to ~0.006 on gradient-heavy keys, equally for stamped and unstamped SVGs. The GPU raster is not used because its rounding of translucent fills depends on the SVG structure (+-3/255 at alpha 0.3 between <use> and plain paths), which would bias the stamping comparison.',
        'Known blind spot: dropping low-contrast speckle loops (--ablate tiny) only raises mae to at most 0.018, so it passes. Acceptable for this purpose; noise_flag marks those keys.',
        'cov_1px = share of alpha>=0.5 pixels in either image that have a covered pixel within 1px in the other image. Strict IoU is reported but not gated, because transparent text-only keys score 0.85-0.95 on it purely from the glyph-mask boost. 0.99 fails missing or shifted shapes: with the text dropped, the three transparent text keys score 0, 0.70 and 0.76.',
      ],
    },
    floors: args['no-floors'] ? null : {
      canvas: 'the real canvas against itself: an independent second page load (same URL, seed, t=0, font gate); 0 when byte-identical',
      svg: 'the SVG raster against itself: the same SVG rasterized in the second page (CPU-backed canvas); 0 when byte-identical',
      raster: 'canvas API vs SVG on content both draw identically, taken from the key itself: its pixel-aligned solid rects, full circles/ellipses (native arc) and text runs (fillText), recorded and emitted by this tool; generic scene (4 pixel-aligned rects, 1 circle, 1 text run) for a key with none',
      metric: 'the residual metric (alpha-weighted mean |linear RGB|, coverage within 1 px); no blur, masks or threshold changes',
      units: 'mae is normalised by the weight of the floor scene itself; mae_in_key = the weighted error of the floor divided by the residual weight of the key, the unit the residual is in',
      excess: 'residual mae minus the largest floor mae_in_key',
    },
    run_source: STAMP ? {
      method: RNG_OK ? 'rng hook: the served source of mulberry32 (ctx.rng), hash2 and hash3 counts calls; every draw records the count' : 'placement regularity (rng hook not installed)',
      rule: 'elements = stretches of a run between rng events (rng called since the previous draw on that canvas); procedural when >= half of the elements are rng-driven, else authored. ambiguous: rng share 0.15-0.85, rng-driven with regular placement (>= 0.6, >= 8 instances), no rng with irregular placement (< 0.2, >= 32 instances), or a procedural run holding a regular, rng-free sub-grid of one prototype (>= 8 instances, regularity >= 0.8)',
      regularity: 'per axis 1 - (observed distinct origins - 1) / (expected distinct for uniform random placement over the same range - 1), origins in 0.5 px bins, averaged over x and y: ~0 scatter, ~1 rows/grids',
    } : null,
    stamping: STAMP ? {
      min_run: STAMP_MIN, fit_tolerance_px: STAMP_EPS,
      runs: 'consecutive stampable draws (solid or linear/radial-gradient fills, non-dashed strokes, no composite/filter/shadow, same clip); a run mixes prototypes, ends at any other draw (paint order is exact), and is kept only with >= min_run instances and at least one reused prototype',
      prototypes: 'fill: rect = unit square, ellipse = unit circle (exactly closed arcs only), path = first instance normalised to its bbox; stroke: first instance user-space centreline scaled uniformly into a unit box, fill="none", stroke-width/cap/join/miterlimit in that frame',
      matching: 'fill: every path point within fit_tolerance_px under one affine map; stroke: the stroked OUTLINE (offsets along each segment, join points, cap points; canvas strokes in user space, then the CTM) within fit_tolerance_px, mirrored order tried for reflections',
      paint: 'fill/fill-opacity or stroke/stroke-opacity on the <use> only; gradients in the prototype frame (gradientTransform = inverse(instance) x canvas CTM), shared when the proto-frame gradient field and stops are identical',
      references: '<use href="#id" xlink:href="#id">',
      curves_after: 'non-stamped curves + each prototype once per key (stroke curves counted along the centreline)',
    } : null,
    keys: {},
  };
  let totalBytes = 0;
  // floors in key units: the floor scene's weighted error over THIS key's weight (residual = se_key / sw_key), so
  // residual - floor = (error not explained by the floor content) / sw_key; mae alone is normalised by the scene's own weight
  const inKey = (x, sc) => (x && !x.error && sc && sc.sw ? (x.se || 0) / sc.sw : 0);
  const fmtF = (x, sc) => !x || x.error ? (x || { error: 'n/a' }) : { mae: +x.mae.toFixed(5), mae_in_key: +inKey(x, sc).toFixed(5), cov_1px: +x.cov1px.toFixed(5), ...(x.identical !== undefined ? { identical: x.identical } : {}), ...(x.page1_reraster_same !== undefined ? { page1_reraster_same: x.page1_reraster_same } : {}) };
  const floorMax = (fl, sc) => Math.max(...[fl.canvas, fl.svg, fl.raster].map(x => inKey(x, sc)));
  const srcCount = (runs) => { const o = { procedural: { runs: 0, instances: 0 }, authored: { runs: 0, instances: 0 }, ambiguous: [] }; for (const r of runs) { o[r.source].runs++; o[r.source].instances += r.instances; if (r.ambiguous) o.ambiguous.push({ run: r.run, source: r.source, instances: r.instances, why: r.ambiguous }); } return o; };
  for (const r of results) {
    if (!r.svg) { manifest.keys[r.key] = { error: r.error, width: r.w, height: r.h }; failed++; continue; }
    fs.writeFileSync(path.join(outDir, r.file), r.svg);
    const bytes = Buffer.byteLength(r.svg); totalBytes += bytes;
    const sc = scores[r.key] || { error: 'not scored' };
    const pass = !sc.error && sc.mae <= MAE_MAX && sc.cov1px >= COV_MIN;
    if (!pass) failed++;
    const st = r.stats, fl = floors[r.key];
    const plainCurves = st.lines + st.quads + 2 * st.cubics;
    const protoList = [...st.protoInfo.values()], byKind = {};
    for (const p of protoList) byKind[p.kind] = (byKind[p.kind] || 0) + 1;
    manifest.keys[r.key] = {
      file: r.file, width: r.w, height: r.h, bytes,
      elements: st.paths + st.groups, paths: st.paths, groups: st.groups,
      segments: { lines: st.lines, quads: st.quads, cubics: st.cubics },
      curves_approx: plainCurves + st.stampCurvesExpanded,
      // before: every stamped instance expanded; after: each prototype counted once per key
      curves_before: plainCurves + st.stampCurvesExpanded,
      curves_after: plainCurves + protoList.reduce((s, p) => s + p.curves, 0),
      gradients: (r.svg.match(/<(linear|radial)Gradient /g) || []).length,
      stamp: st.uses ? {
        runs: st.runs, uses: st.uses,
        protos: { total: protoList.length, by_kind: byKind, singletons: protoList.filter(p => p.uses === 1).length },
        stroke_protos: protoList.filter(p => p.kind === 'stroke').map(p => ({ id: p.id, centreline: p.sig, cap: p.cap, join: p.join, uses: p.uses, curves: p.curves, line_width: [+p.lw[0].toFixed(3), +p.lw[1].toFixed(3)], paints: [...p.paints] })),
        gradients: { stamped_defs: st.stampGradIds.size, stamped_uses: st.stampGradUses, defs_if_alpha_factored: st.stampGradAlphaFactored.size },
        sources: srcCount(st.runs),
      } : undefined,
      tiny_rects: st.tinyRects, tiny_shapes: st.tinyShapes,
      noise_flag: st.tinyRects + st.tinyShapes > 500 ? `pixel-noise loop: ${st.tinyRects} fills <= 4 px2 from fillRect, ${st.tinyShapes} path fills with bbox <= 16 px2` : undefined,
      unsupported: st.unsup,
      canvas_ops: r.ops,
      score: sc.error ? sc : { mae: +sc.mae.toFixed(5), alpha_mae: +sc.alphaMae.toFixed(5), iou: +sc.iou.toFixed(5), cov_1px: +sc.cov1px.toFixed(5) },
      pass,
      residual: sc.error ? undefined : { mae: +sc.mae.toFixed(5), cov_1px: +sc.cov1px.toFixed(5) },
      floors: fl ? { canvas: fmtF(fl.canvas, sc), svg: fmtF(fl.svg, sc), raster: { ...fmtF(fl.raster, sc), scene: fl.scene } } : undefined,
      excess: fl && !sc.error ? +(sc.mae - floorMax(fl, sc)).toFixed(5) : undefined,
    };
  }
  const live = Object.values(manifest.keys).filter(e => e.residual && e.floors);
  const mean = (a) => a.length ? +(a.reduce((x, y) => x + y, 0) / a.length).toFixed(5) : null;
  const median = (a) => { if (!a.length) return null; const b = a.slice().sort((x, y) => x - y); return +b[b.length >> 1].toFixed(5); };
  const col = (g) => live.map(g).filter(v => typeof v === 'number');
  manifest.summary = { keys: results.length, failed, total_bytes: totalBytes,
    floors: live.length ? {
      keys: live.length,
      canvas: { mean: mean(col(e => e.floors.canvas.mae_in_key)), median: median(col(e => e.floors.canvas.mae_in_key)), identical_keys: live.filter(e => e.floors.canvas.identical).length },
      svg: { mean: mean(col(e => e.floors.svg.mae_in_key)), median: median(col(e => e.floors.svg.mae_in_key)), identical_keys: live.filter(e => e.floors.svg.identical).length },
      raster: { mean: mean(col(e => e.floors.raster.mae_in_key)), median: median(col(e => e.floors.raster.mae_in_key)), scene_normalised_mean: mean(col(e => e.floors.raster.mae)), own_content_keys: live.filter(e => /^own/.test(e.floors.raster.scene || '')).length },
      residual: { mean: mean(col(e => e.residual.mae)), median: median(col(e => e.residual.mae)) },
      excess: { mean: mean(col(e => e.excess)), median: median(col(e => e.excess)) },
    } : undefined,
    run_sources: (() => { const o = { procedural: { runs: 0, instances: 0 }, authored: { runs: 0, instances: 0 }, ambiguous_runs: 0 }; for (const e of Object.values(manifest.keys)) if (e.stamp) { for (const t of ['procedural', 'authored']) { o[t].runs += e.stamp.sources[t].runs; o[t].instances += e.stamp.sources[t].instances; } o.ambiguous_runs += e.stamp.sources.ambiguous.length; } return o; })(),
  };
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 1) + '\n');
  console.log(`canvas svg: ${results.length} keyed textures, ${failed} failed, ${(totalBytes / 1024).toFixed(0)} KiB -> ${path.relative(process.cwd(), outDir)}`);

  // ---------------------------------------------------------------- contact sheets (with --png): one row per key,
  // real canvas | SVG rasterized by Edge | |diff| x4, labelled; failing, pixel-noise and stamping-priority keys first
  if (args.png) {
    const PRIORITY = ['sakura-speck4', 'st-gravel', 'plaza-notice', 'sakura-blossom-atlas', 'sakura-bark-old', 'env-shrub2', 'plaza-tiles', 'plaza-circle'];
    const keys = Object.keys(manifest.keys).filter(k => scores[k] && scores[k].png && manifest.keys[k].score && !manifest.keys[k].score.error);
    // flagged first: failing or near a threshold (colour error > 75% of the limit, coverage < 0.995)
    const near = (k) => { const e = manifest.keys[k]; return e.score.mae > 0.75 * MAE_MAX || e.score.cov_1px < 0.995; };
    const rank = (k) => { const e = manifest.keys[k]; return !e.pass || near(k) ? 0 : e.noise_flag ? 1 : PRIORITY.includes(k) ? 2 : 3; };
    // with floors measured: failing keys first, then worst residual-minus-floor (excess) first
    if (Object.keys(floors).length) keys.sort((a, b) => (manifest.keys[a].pass - manifest.keys[b].pass) || (manifest.keys[b].excess ?? 0) - (manifest.keys[a].excess ?? 0));
    else keys.sort((a, b) => rank(a) - rank(b) || (rank(a) === 2 ? PRIORITY.indexOf(a) - PRIORITY.indexOf(b) : 0) || manifest.keys[b].score.mae - manifest.keys[a].score.mae);
    const f4 = (x) => (x && !x.error ? x.mae_in_key.toFixed(4) : 'n/a');
    const rows = keys.map(k => {
      const e = manifest.keys[k], s = e.stamp;
      return {
        title: `${k}   ${e.width}x${e.height}   ${e.pass ? (near(k) ? 'PASS (near limit)' : 'PASS') : 'FAIL'}${e.noise_flag ? '   pixel-noise' : ''}`,
        info: `residual ${e.score.mae.toFixed(4)}   coverage(1px) ${e.score.cov_1px.toFixed(4)}   IoU ${e.score.iou.toFixed(3)}` +
          (e.floors ? `   floors: canvas ${f4(e.floors.canvas)}  svg ${f4(e.floors.svg)}  raster ${f4(e.floors.raster)}   excess ${(e.excess ?? 0).toFixed(4)}` : ''),
        info2: (s ? `stamp ${s.runs.length} runs (${s.sources.procedural.runs} procedural / ${s.sources.authored.runs} authored), ${s.uses} inst, ${s.protos.total} protos   curves ${e.curves_before} -> ${e.curves_after}` : `no stamp runs   curves ${e.curves_before}`) +
          (e.floors ? `   floor scene ${(e.floors.raster.scene || 'n/a').replace(/own: (\d+) rects, (\d+) circles\/ellipses, (\d+) text runs/, 'own $1 rects $2 ellipses $3 text').replace(/generic:.*/, 'generic')}` : ''),
        fail: !e.pass || near(k), real: scores[k].png[0], svg: scores[k].png[1],
      };
    });
    const sheets = await page.evaluate(async (rows, per, cell) => {
      const load = (s) => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = s; });
      const LABEL = 56, GAP = 10, HEAD = 34, PAD = 10, W = PAD * 2 + cell * 3 + GAP * 2;
      const out = [];
      for (let p = 0; p < rows.length; p += per) {
        const pg = rows.slice(p, p + per);
        const c = document.createElement('canvas'); c.width = W; c.height = HEAD + pg.length * (LABEL + cell + GAP) + PAD;
        const g = c.getContext('2d');
        g.fillStyle = '#1d1e22'; g.fillRect(0, 0, c.width, c.height);
        g.textBaseline = 'middle'; g.font = 'bold 14px "Segoe UI", Arial, sans-serif'; g.fillStyle = '#e6e6e6';
        ['real canvas', 'SVG (rasterized in Edge)', '|real - SVG| x4 (max channel)'].forEach((t, i) => g.fillText(t, PAD + i * (cell + GAP), HEAD / 2));
        let y = HEAD;
        for (const r of pg) {
          g.font = 'bold 13px "Segoe UI", Arial, sans-serif'; g.fillStyle = r.fail ? '#ff7070' : '#f2f2f2'; g.fillText(r.title, PAD, y + 11);
          g.font = '12px "Segoe UI", Arial, sans-serif'; g.fillStyle = r.fail ? '#ffb0b0' : '#aebccc'; g.fillText(r.info, PAD, y + 28); g.fillStyle = '#8f9bab'; g.fillText(r.info2, PAD, y + 44);
          y += LABEL;
          const A = await load(r.real), B = await load(r.svg), w = A.width, h = A.height, sc = Math.min(cell / w, cell / h), dw = w * sc, dh = h * sc;
          const t = document.createElement('canvas'); t.width = w; t.height = h; const tg = t.getContext('2d');
          tg.drawImage(A, 0, 0); const da = tg.getImageData(0, 0, w, h).data; tg.clearRect(0, 0, w, h); tg.drawImage(B, 0, 0); const db = tg.getImageData(0, 0, w, h).data;
          const D = tg.createImageData(w, h);
          for (let i = 0; i < da.length; i += 4) { let m = 0; for (let k = 0; k < 4; k++) m = Math.max(m, Math.abs(da[i + k] - db[i + k])); const v = Math.min(255, m * 4); D.data[i] = v; D.data[i + 1] = v * 0.4; D.data[i + 2] = 0; D.data[i + 3] = 255; }
          tg.putImageData(D, 0, 0);
          [A, B, t].forEach((img, i) => {
            const x = PAD + i * (cell + GAP);
            if (i < 2) for (let cy = 0; cy < cell; cy += 16) for (let cx = 0; cx < cell; cx += 16) { g.fillStyle = ((cx + cy) / 16) % 2 ? '#8f8f8f' : '#bdbdbd'; g.fillRect(x + cx, y + cy, 16, 16); }
            else { g.fillStyle = '#000'; g.fillRect(x, y, cell, cell); }
            g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
            g.drawImage(img, x + (cell - dw) / 2, y + (cell - dh) / 2, dw, dh);
          });
          y += cell + GAP;
        }
        out.push(c.toDataURL('image/png'));
      }
      return out;
    }, rows, 12, 256);
    if (!onlyKeys) for (const f of fs.readdirSync(outDir)) if (/^oracle-sheet-\d+\.png$/.test(f)) fs.unlinkSync(path.join(outDir, f));
    const written = sheets.map((u, i) => { const f = path.join(outDir, `oracle-sheet-${String(i + 1).padStart(2, '0')}.png`); fs.writeFileSync(f, Buffer.from(u.split(',')[1], 'base64')); return f; });
    console.log(`contact sheets: ${written.length} (${rows.length} keys, 12 per sheet) -> ${path.relative(process.cwd(), outDir)}${path.sep}oracle-sheet-NN.png`);
    if (args['sheet-copy']) { // copies never overwrite: numbering continues after the highest existing NN
      const dir = path.resolve(args['sheet-copy']); fs.mkdirSync(dir, { recursive: true });
      let nn = Math.max(0, ...fs.readdirSync(dir).map(f => /^oracle-canvas-vs-svg-(\d+)\.png$/.exec(f)).filter(Boolean).map(m => +m[1]));
      for (const f of written) { let dst; do { nn++; dst = path.join(dir, `oracle-canvas-vs-svg-${String(nn).padStart(2, '0')}.png`); } while (fs.existsSync(dst)); fs.copyFileSync(f, dst); console.log(`sheet copy: ${dst}`); }
    }
  }
} finally {
  await browser.close();
  server.close();
}
process.exitCode = failed ? 1 : 0;
