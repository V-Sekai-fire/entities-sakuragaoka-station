// The engine-floor calibration tiles rendered by the original (three.js): the original's own page
// and modules (main.js, core/materials.js, core/sky.js, core/renderer.js) with one extra world
// module, calib_world.js, served at /src/world/calib.js and built through ?only=calib. Each tile of
// calib_scene.json is captured at its camera with its post stages (window.__post).
// usage:
//   node tools/oracle/calib.mjs --out shots/calib/three [--root <original checkout>] [--chrome <path>] [--q high]
//   files: <out>_<tile id>.png
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const puppeteer = createRequire(path.join(root, 'package.json'))('puppeteer-core');
const scene = JSON.parse(fs.readFileSync(path.join(here, 'calib_scene.json'), 'utf8'));
const W = scene.w, H = scene.h;
const out = path.resolve(args.out || 'shots/calib/three');
fs.mkdirSync(path.dirname(out), { recursive: true });

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };
const OVERRIDES = { '/src/world/calib.js': path.join(here, 'calib_world.js'), '/calib_scene.json': path.join(here, 'calib_scene.json') };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
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
  protocolTimeout: 300000,
});
const logs = [];
try {
  const page = await browser.newPage();
  page.on('console', (m) => { const t = m.type(); if (t === 'error' || t === 'warning' || t === 'warn') logs.push(`[console.${t}] ${m.text()}`); });
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  const t0 = scene.tiles[0];
  const q = new URLSearchParams({ shot: '1', w: String(W), h: String(H), t: '0', q: args.q || 'high', only: 'calib', cam: t0.cam.join(',') });
  await page.goto(`http://127.0.0.1:${port}/index.html?${q}`, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
  const errors = await page.evaluate(() => window.__errors);
  if (errors && errors.length) throw new Error('module errors: ' + JSON.stringify(errors).slice(0, 2000));
  for (const t of scene.tiles) {
    await page.evaluate((post) => { window.__post = post; }, t.post);
    await page.evaluate((v) => window.__setCam(v[0], v[1], v[2], v[3], v[4]), t.cam);
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))))));
    const file = `${out}_${t.id}.png`;
    await page.screenshot({ path: file });
    console.log(`saved ${file}  ${t.id}  cam=[${t.cam}]  post=${JSON.stringify(t.post)}`);
  }
  console.log('gpu:', await page.evaluate(() => { try { const gl = document.getElementById('scene').getContext('webgl2'); const d = gl.getExtension('WEBGL_debug_renderer_info'); return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown'; } catch (e) { return 'n/a'; } }));
} catch (e) {
  console.log('CALIB FAILED:', e.message);
  process.exitCode = 1;
} finally {
  if (logs.length) { console.log('PAGE LOGS:'); for (const l of logs.slice(0, 40)) console.log(' ', l.slice(0, 400)); }
  await browser.close();
  server.close();
}
