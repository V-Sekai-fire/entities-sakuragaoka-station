// Headless GPU screenshots of the three.js original, the renders a port is compared with. From the
// original's tools/shot.mjs (Kenton-GMI/sakuragaoka-station 4112f57, MIT), serving the checkout at --root.
// usage:
//   node tools/oracle/shot.mjs --chrome <path> --hammersley 8@-1,-11.4 --out shots/original [--only environment,plaza]
//   --root   the original's checkout, with npm ci run (default: the workspace's 3-interactor/sakuragaoka-station-upstream)
//   --chrome path to a Chrome, chrome-headless-shell or Edge binary (default: the Windows install paths)
//   --only   comma list of world modules to build (omit = full scene)
//   --cams   ';'-separated cameras. 4 numbers = walking eye at ground (x,z,yawDeg,pitchDeg);
//            5 numbers = free camera (x,y,z,yawDeg,pitchDeg). yaw 0 = north(-Z), 90 = west, 180 = south, -90 = east.
//   --hammersley n@x,z  n walking eyes at (x,z) at the sphere Hammersley sequence's angles (remapped); replaces --cams
//   --t      simulation time in seconds (animations are fast-forwarded deterministically)
//   --out    output path prefix, relative to the working directory; files are <out>_0.png, <out>_1.png, ...
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const root = path.resolve(args.root || path.join(path.dirname(fileURLToPath(import.meta.url)), '../../../../3-interactor/sakuragaoka-station-upstream'));
const puppeteer = createRequire(path.join(root, 'package.json'))('puppeteer-core');
const W = Number(args.w || 1280), H = Number(args.h || 720);
function radicalInverse2(n) { let v = 0, f = 0.5; while (n > 0) { v += (n & 1) * f; n >>= 1; f *= 0.5; } return v; }
// sphere_hammersley_sequence(i, n, remap=True): [azimuth, elevation] in degrees
function sphereHammersley(i, n) {
  let u = i / n; const v = radicalInverse2(i);
  u = u < 0.25 ? 2 * u : (2 / 3) * u + 1 / 3;
  return [v * 360, (Math.acos(1 - 2 * u) - Math.PI / 2) * 180 / Math.PI];
}
let cams = (args.cams || '1.6,34,4,2').split(';').map(s => s.trim()).filter(Boolean);
if (args.hammersley) {
  const [n, at] = args.hammersley.split('@'); const [hx, hz] = at.split(',').map(Number);
  cams = Array.from({ length: Number(n) }, (_, i) => { const [az, el] = sphereHammersley(i, Number(n)); return `${hx},${hz},${az.toFixed(4)},${Math.max(-85, Math.min(85, el)).toFixed(4)}`; });
}
const out = path.resolve(args.out || 'shots/shot');
fs.mkdirSync(path.dirname(out), { recursive: true });

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
  const f = path.join(root, p);
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
  page.on('requestfailed', (r) => logs.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`));
  const q = new URLSearchParams({ shot: '1', w: String(W), h: String(H), t: String(args.t || 0), q: args.q || 'high' });
  if (args.only) q.set('only', args.only);
  if (args.batch) q.set('batch', args.batch);
  q.set('cam', cams[0]);
  await page.goto(`http://127.0.0.1:${port}/index.html?${q}`, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
  const info = await page.evaluate(() => ({ errors: window.__errors, stats: window.__stats, gl: (() => { try { const gl = document.getElementById('scene').getContext('webgl2'); const d = gl.getExtension('WEBGL_debug_renderer_info'); return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown'; } catch (e) { return 'n/a'; } })() }));
  for (let i = 0; i < cams.length; i++) {
    const v = cams[i].split(',').map(Number);
    await page.evaluate((v) => { if (v.length === 4) window.__setCam(v[0], null, v[1], v[2], v[3]); else window.__setCam(v[0], v[1], v[2], v[3], v[4]); }, v);
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r)))));
    const file = `${out}_${i}.png`;
    await page.screenshot({ path: file });
    const st = await page.evaluate(() => ({ calls: window.__stats.calls, triangles: window.__stats.triangles }));
    console.log(`saved ${path.relative(process.cwd(), file)}  cam=[${cams[i]}]  calls=${st.calls} tris=${st.triangles}`);
  }
  console.log('gpu:', info.gl);
  console.log('module stats:', JSON.stringify(info.stats.modules), 'batch:', JSON.stringify(info.stats.batch));
  if (info.errors && info.errors.length) { console.log('MODULE ERRORS:'); for (const e of info.errors) console.log(` - [${e.module}] ${e.message.split('\n').slice(0, 6).join('\n   ')}`); process.exitCode = 1; }
} catch (e) {
  console.log('SHOT FAILED:', e.message);
  process.exitCode = 1;
} finally {
  if (logs.length) { console.log('PAGE LOGS:'); for (const l of logs.slice(0, 60)) console.log(' ', l.slice(0, 600)); }
  await browser.close();
  server.close();
}
