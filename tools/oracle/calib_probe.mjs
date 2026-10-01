// The original's shadow probes of chart_in_view.gd's candidate placements, so a chart goes only where both engines agree.
// node tools/oracle/calib_probe.mjs --candidates <candidates.json> --out <candidates_original.json> [--root <dir>] [--chrome <path>] [--godot <exe>] [--keep <dir>]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import os from 'node:os';
import zlib from 'node:zlib';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const puppeteer = createRequire(path.join(root, 'package.json'))('puppeteer-core');
if (!args.candidates || !args.out) { console.log('usage: node tools/oracle/calib_probe.mjs --candidates <candidates.json> --out <file>'); process.exit(2); }
const cand = JSON.parse(fs.readFileSync(args.candidates, 'utf8'));
const W = cand.w || 1920, H = cand.h || 1080;
const views = cand.views.map((v) => ({ view: v.view, cam: v.cam, cands: v.check.map((c) => ({ id: c.id, pos: c.pos, yaw: c.yaw, pitch: c.pitch, px: c.px, box: c.probe_box })) }));
const scene = { w: W, h: H, note: 'in-view placement probes (tools/oracle/calib_probe.mjs)', tiles: [], probe: { margin: cand.probe_margin, views } };
const modules = (cand.modules || ['environment', 'station', 'plaza', 'sakura']).concat(['calib']).join(',');

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };
const OVERRIDES = { '/src/world/calib.js': path.join(here, 'calib_world.js'), '/chart24.json': path.join(here, '../calib/chart24.json') };
const sceneText = JSON.stringify(scene);
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
  if (p === '/calib_scene.json') { res.writeHead(200, { 'Content-Type': TYPES['.json'], 'Cache-Control': 'no-store' }); return res.end(sceneText); }
  const f = OVERRIDES[p] || path.join(root, p);
  fs.readFile(f, (err, data) => { if (err) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); res.end(data); });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const CHROME = args.chrome || ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(p => fs.existsSync(p));
const ANGLE = { darwin: 'metal', win32: 'd3d11' }[process.platform] || 'vulkan';
const browser = await puppeteer.launch({
  executablePath: CHROME, headless: true,
  args: [`--use-angle=${ANGLE}`, '--enable-gpu', '--ignore-gpu-blocklist', '--enable-webgl', '--disable-gpu-sandbox', '--no-first-run', '--disable-extensions', `--window-size=${W},${H}`],
  defaultViewport: { width: W, height: H, deviceScaleFactor: 1 },
  protocolTimeout: 600000,
});
const overlaps = (a, b) => a[0] - 4 < b[0] + b[2] && b[0] - 4 < a[0] + a[2] && a[1] - 4 < b[1] + b[3] && b[1] - 4 < a[1] + a[3];
const logs = [];
try {
  const page = await browser.newPage();
  page.on('console', (m) => { const t = m.type(); if (t === 'error' || t === 'warning' || t === 'warn') logs.push(`[console.${t}] ${m.text()}`); });
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  const q = new URLSearchParams({ shot: '1', w: String(W), h: String(H), t: '0', q: cand.quality || 'high', only: modules, cam: views[0].cam.join(',') });
  await page.goto(`http://127.0.0.1:${port}/index.html?${q}`, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
  const errors = await page.evaluate(() => window.__errors);
  if (errors && errors.length) throw new Error('module errors: ' + JSON.stringify(errors).slice(0, 2000));
  await page.evaluate(() => { window.__post = { outline: 0, bloom: 0, grade: 0, leak: 0, vignette: 0, dither: 0 }; });
  const result = { note: 'the original\'s shadow probes of the port\'s candidate placements', views: [] };
  const tmp = args.keep ? path.resolve(args.keep) : fs.mkdtempSync(path.join(os.tmpdir(), 'calib-probe-'));
  fs.mkdirSync(tmp, { recursive: true });
  const plan = [];
  for (const v of views) {
    await page.evaluate((c) => window.__setCam(c[0], null, c[1], c[2], c[3]), v.cam);
    const passes = [];
    for (const c of v.cands) {
      const p = passes.find((ps) => ps.every((o) => !overlaps(o.box, c.box)));
      if (p) p.push(c); else passes.push([c]);
    }
    const reads = [];
    for (const ps of passes) {
      const ids = ps.map((c) => c.id);
      await page.evaluate((ids) => window.__probeShow(ids), ids);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))))));
      const r = await page.evaluate((ids) => window.__probeRead(ids), ids);
      const file = `view${v.view}-pass${reads.length}`;
      fs.writeFileSync(path.join(tmp, file + '.zst'), zlib.zstdCompressSync(Buffer.from(r.frame, 'base64')));
      fs.writeFileSync(path.join(tmp, file + '.f64'), Buffer.from(r.quads, 'base64'));
      reads.push({ file, w: r.w, h: r.h, ids: r.ids, on: r.on });
    }
    await page.evaluate(() => window.__probeShow([]));
    plan.push({ v, passes: passes.length, reads });
  }
  fs.writeFileSync(path.join(tmp, 'passes.json'), JSON.stringify(plan.flatMap((p) => p.reads.map(({ file, w, h }) => ({ file, w, h })))));
  const g = spawnSync(args.godot || 'godot', ['--headless', '--path', path.resolve(here, '../..'), '--script', 'res://tools/oracle/probe_read.gd', '--',
    `--passes=${path.join(tmp, 'passes.json')}`, `--out=${path.join(tmp, 'reads.json')}`], { encoding: 'utf8', maxBuffer: 64 << 20 });
  for (const l of `${g.stdout || ''}${g.stderr || ''}`.split(/\r?\n/)) if (/probe_read/.test(l)) console.log(l);
  if (g.status !== 0) throw new Error(`probe_read.gd exited ${g.status}${g.error ? ': ' + g.error.message : ''}`);
  const counts = JSON.parse(fs.readFileSync(path.join(tmp, 'reads.json'), 'utf8'));
  for (const { v, passes, reads } of plan) {
    const states = {};
    for (const r of reads) {
      let k = 0;
      r.ids.forEach((id, i) => {
        if (!r.on[i]) { states[id] = { state: 'offscreen' }; return; }
        const [n, hidden, lo, hi] = counts[r.file].slice(k * 4, k * 4 + 4);
        k++;
        states[id] = { state: n === 0 ? 'offscreen' : hidden > 0 ? 'hidden' : lo >= 250 ? 'lit' : hi <= 5 ? 'shadow' : 'mixed', pixels: n, hidden, att_min: lo / 255, att_max: hi / 255 };
      });
    }
    const tally = {};
    for (const s of Object.values(states)) tally[s.state] = (tally[s.state] || 0) + 1;
    console.log(`calib_probe: view ${v.view}: ${v.cands.length} candidates in ${passes} passes: ${JSON.stringify(tally)}`);
    result.views.push({ view: v.view, states });
  }
  if (!args.keep) fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
  fs.writeFileSync(args.out, JSON.stringify(result, null, 1));
  console.log('calib_probe: saved', args.out);
} catch (e) {
  console.log('CALIB PROBE FAILED:', e.message);
  process.exitCode = 1;
} finally {
  if (logs.length) { console.log('PAGE LOGS:'); for (const l of logs.slice(0, 20)) console.log(' ', l.slice(0, 300)); }
  await browser.close();
  server.close();
}
