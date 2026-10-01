// The original's live cameras and sun at given views, for tools/sun_locate.gd --analyze, served as
// tools/oracle/shot.mjs serves it. Per view: meta.json (camera matrices, the sun light and its shadow
// settings), beauty_<i>.png (shot.mjs's render), noshadow_<i>.png (shadow intensity 0) and
// geo_<i>.f32 (world normal and view depth, float32 RGBA, rows from the bottom).
//   node tools/oracle/sun_cams.mjs --hammersley 8@-1,-11.4 --w 1920 --h 1080 --only environment,station,plaza,sakura --out <dir>
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
const out = path.resolve(args.out || 'shots/sun_cams');
fs.mkdirSync(out, { recursive: true });

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
  protocolTimeout: 600000,
});
const logs = [];
const frames = (page) => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r)))));
try {
  const page = await browser.newPage();
  page.on('console', (m) => { const t = m.type(); if (t === 'error' || t === 'warning' || t === 'warn') logs.push(`[console.${t}] ${m.text()}`); });
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  const q = new URLSearchParams({ shot: '1', w: String(W), h: String(H), t: String(args.t || 0), q: args.q || 'high' });
  if (args.only) q.set('only', args.only);
  q.set('cam', cams[0]);
  await page.goto(`http://127.0.0.1:${port}/index.html?${q}`, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction('window.__ready === true', { timeout: 280000, polling: 250 });
  await page.evaluate((W, H) => {
    const THREE = window.THREE;
    window.__geoRT = new THREE.WebGLRenderTarget(W, H, { type: THREE.FloatType, format: THREE.RGBAFormat, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, samples: 0, depthBuffer: true });
    window.__geoMat = new THREE.ShaderMaterial({
      vertexShader: `
        #include <common>
        #include <skinning_pars_vertex>
        varying vec3 vNw; varying float vD;
        void main(){
          #include <beginnormal_vertex>
          #include <skinbase_vertex>
          #include <skinnormal_vertex>
          #include <defaultnormal_vertex>
          #include <begin_vertex>
          #include <skinning_vertex>
          #include <project_vertex>
          vNw = inverseTransformDirection(transformedNormal, viewMatrix);
          vD = -mvPosition.z;
        }`,
      fragmentShader: `
        varying vec3 vNw; varying float vD;
        void main(){ vec3 n = normalize(vNw); if (!gl_FrontFacing) n = -n; gl_FragColor = vec4(n, vD); }`,
      side: THREE.DoubleSide,
    });
  }, W, H);
  const info = await page.evaluate(() => ({ revision: window.THREE.REVISION, errors: window.__errors, stats: window.__stats }));
  const meta = { revision: info.revision, size: [W, H], cams, views: [], only: args.only || null, q: args.q || 'high', t: Number(args.t || 0) };
  for (let i = 0; i < cams.length; i++) {
    const v = cams[i].split(',').map(Number);
    await page.evaluate((v) => { if (v.length === 4) window.__setCam(v[0], null, v[1], v[2], v[3]); else window.__setCam(v[0], v[1], v[2], v[3], v[4]); }, v);
    await frames(page);
    await page.screenshot({ path: path.join(out, `beauty_${i}.png`) });
    const vm = await page.evaluate(() => {
      const c = window.__ctx, cam = c.camera, sky = c.sky, sun = sky.sun, sh = sun.shadow, p = c.playerObj;
      const v3 = (a) => [a.x, a.y, a.z];
      return {
        position: v3(cam.position), rotation: [cam.rotation.x, cam.rotation.y, cam.rotation.z, cam.rotation.order],
        matrixWorld: Array.from(cam.matrixWorld.elements), projectionMatrix: Array.from(cam.projectionMatrix.elements),
        fov: cam.fov, aspect: cam.aspect, near: cam.near, far: cam.far, zoom: cam.zoom, filmOffset: cam.filmOffset, view: cam.view,
        feet: v3(p.pos), eye: p.eye,
        sunDir: v3(c.sunDir), sunPosition: v3(sun.position), sunTarget: v3(sun.target.position),
        sunColor: sun.color.getHexString(), sunIntensity: sun.intensity, castShadow: sun.castShadow,
        shadow: { left: sh.camera.left, right: sh.camera.right, top: sh.camera.top, bottom: sh.camera.bottom, near: sh.camera.near, far: sh.camera.far,
          mapSize: [sh.mapSize.x, sh.mapSize.y], bias: sh.bias, normalBias: sh.normalBias, radius: sh.radius, intensity: sh.intensity,
          matrix: Array.from(sh.matrix.elements), cameraMatrixWorld: Array.from(sh.camera.matrixWorld.elements) },
        shadowMapType: c.renderer.shadowMap.type, PCFSoftShadowMap: window.THREE.PCFSoftShadowMap,
        hemi: { sky: sky.hemi.color.getHexString(), ground: sky.hemi.groundColor.getHexString(), intensity: sky.hemi.intensity },
      };
    });
    meta.views.push(vm);
    await page.evaluate(() => { window.__ctx.sky.sun.shadow.intensity = 0; });
    await frames(page);
    await page.screenshot({ path: path.join(out, `noshadow_${i}.png`) });
    await page.evaluate(() => { window.__ctx.sky.sun.shadow.intensity = 1; });
    const rows = 120;
    const fd = fs.openSync(path.join(out, `geo_${i}.f32`), 'w');
    await page.evaluate(() => {
      const c = window.__ctx, r = c.renderer, s = c.scene, cam = c.camera;
      const vis = c.sky.mesh.visible; c.sky.mesh.visible = false;
      const bg = s.background, fog = s.fog; s.background = null; s.fog = null;
      cam.layers.enableAll();
      s.overrideMaterial = window.__geoMat;
      const auto = r.shadowMap.autoUpdate; r.shadowMap.autoUpdate = false;
      r.setRenderTarget(window.__geoRT); r.setClearColor(0x000000, 0); r.clear(); r.render(s, cam); r.setRenderTarget(null);
      s.overrideMaterial = null; s.background = bg; s.fog = fog; c.sky.mesh.visible = vis; r.shadowMap.autoUpdate = auto;
    });
    for (let y0 = 0; y0 < H; y0 += rows) {
      const h = Math.min(rows, H - y0);
      const b64 = await page.evaluate((y0, h, W) => {
        const buf = new Float32Array(W * h * 4);
        window.__ctx.renderer.readRenderTargetPixels(window.__geoRT, 0, y0, W, h, buf);
        const u8 = new Uint8Array(buf.buffer); let s = '';
        for (let k = 0; k < u8.length; k += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(k, k + 0x8000));
        return btoa(s);
      }, y0, h, W);
      fs.writeSync(fd, Buffer.from(b64, 'base64'));
    }
    fs.closeSync(fd);
    console.log(`view ${i} cam=[${cams[i]}] eye=(${vm.position.map(x => x.toFixed(4)).join(', ')}) sun light travels ${['x', 'y', 'z'].map((_, k) => (vm.sunTarget[k] - vm.sunPosition[k]).toFixed(3)).join(',')}`);
  }
  fs.writeFileSync(path.join(out, 'meta.json'), JSON.stringify(meta, null, 1));
  console.log('three r' + info.revision, 'module stats:', JSON.stringify(info.stats.modules));
  if (info.errors && info.errors.length) { console.log('MODULE ERRORS:'); for (const e of info.errors) console.log(` - [${e.module}] ${e.message.split('\n').slice(0, 6).join('\n   ')}`); process.exitCode = 1; }
} catch (e) {
  console.log('SUN_CAMS FAILED:', e.message);
  process.exitCode = 1;
} finally {
  if (logs.length) { console.log('PAGE LOGS:'); for (const l of logs.slice(0, 60)) console.log(' ', l.slice(0, 600)); }
  await browser.close();
  server.close();
}
