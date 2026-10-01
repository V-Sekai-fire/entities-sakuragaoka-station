// The mean colour of every keyed canvas texture the original draws, read from its real canvases in a
// headless browser: per key, the alpha-weighted mean in linear RGB and the mean alpha. The port
// colours the surfaces it cannot draw yet by these.
// usage: node tools/oracle/texture_means.mjs --chrome <path> [--root <original>] [--only environment,station,plaza,sakura] [--out <json>]
//   --root  the original's checkout, with npm ci run (default: the workspace's 3-interactor/sakuragaoka-station-upstream)
//   --out   default: addons/sakuragaoka_station/core/texture_means.json, made with the --only above
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const puppeteer = createRequire(path.join(root, 'package.json'))('puppeteer-core');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
  fs.readFile(path.join(root, p), (err, data) => { if (err) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' }); res.end(data); });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const ANGLE = { darwin: 'metal', win32: 'd3d11' }[process.platform] || 'vulkan';
const browser = await puppeteer.launch({ executablePath: args.chrome, headless: true, args: [`--use-angle=${ANGLE}`, '--enable-gpu', '--ignore-gpu-blocklist', '--no-first-run'], protocolTimeout: 300000 });
try {
  const page = await browser.newPage();
  // textures.js keeps keyed textures in a private Map; record each (key, texture) as it is cached
  await page.evaluateOnNewDocument(() => {
    const set = Map.prototype.set;
    window.__texKeys = [];
    Map.prototype.set = function (k, v) { if (typeof k === 'string' && v && v.isTexture) window.__texKeys.push([k, v]); return set.call(this, k, v); };
  });
  const q = new URLSearchParams({ shot: '1', w: '64', h: '64', t: '0' });
  if (args.only) q.set('only', args.only);
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?${q}`, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
  const means = await page.evaluate(() => {
    const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    const out = {};
    for (const [key, t] of window.__texKeys) {
      const img = t.image; if (!img || !img.width) continue;
      let g = img.getContext ? img.getContext('2d') : null;
      if (!g) { const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; g = c.getContext('2d'); g.drawImage(img, 0, 0); }
      const d = g.getImageData(0, 0, img.width, img.height).data;
      let r = 0, gg = 0, b = 0, a = 0;
      for (let i = 0; i < d.length; i += 4) { const w = d[i + 3] / 255; r += lin(d[i]) * w; gg += lin(d[i + 1]) * w; b += lin(d[i + 2]) * w; a += w; }
      const n = d.length / 4;
      out[key] = a > 0 ? [r / a, gg / a, b / a, a / n].map(x => Number(x.toFixed(5))) : [0, 0, 0, 0];
    }
    return out;
  });
  const file = path.resolve(args.out || path.join(here, '../../addons/sakuragaoka_station/core/texture_means.json'));
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(means, null, 1) + '\n');
  console.log(`texture means: ${Object.keys(means).length} keyed textures -> ${path.relative(process.cwd(), file)}`);
} finally {
  await browser.close();
  server.close();
}
