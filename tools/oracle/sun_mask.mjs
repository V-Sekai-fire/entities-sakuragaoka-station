// The original's own sun visibility per pixel at given views, served as tools/oracle/shot.mjs serves it:
// every lit material's fragment ends in three's getShadowMask() (the factor its sun light is multiplied
// by), over the shadow map the colour pass just drew. Per view mask_<i>.f32, float32 RGBA rows from
// the bottom: a receiver writes (v, v, v, 1), a mesh that does not receive (0, 1, 0, 1), a transparent
// one (1, 0, 0, 1), the background (0, 0, 1, 1). --shift moves the snapped shadow box by that many
// texels along both light-space axes, the original against itself at another texel phase.
//   node tools/oracle/sun_mask.mjs --hammersley 8@-1,-11.4 --w 1920 --h 1080 --only environment,station,plaza,sakura
//       --out <dir> [--angle d3d11|vulkan] [--shift 0.5]
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
const SHIFT = Number(args.shift || 0);
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
const out = path.resolve(args.out || 'shots/sun_mask');
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
const ANGLE = args.angle || { darwin: 'metal', win32: 'd3d11' }[process.platform] || 'vulkan';
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
  const census = await page.evaluate((W, H, SHIFT) => {
    const THREE = window.THREE, c = window.__ctx, sky = c.sky;
    window.__maskRT = new THREE.WebGLRenderTarget(W, H, { type: THREE.FloatType, format: THREE.RGBAFormat, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, samples: 0, depthBuffer: true });
    if (SHIFT) {
      const S = sky.sun.shadow.camera.right, ms = sky.sun.shadow.mapSize.x, texel = 2 * S / ms;
      const sd = c.sunDir.clone().normalize();
      const lx = new THREE.Vector3().crossVectors(sd, new THREE.Vector3(0, 1, 0)).normalize();
      const ly = new THREE.Vector3().crossVectors(lx, sd).normalize();
      const off = lx.multiplyScalar(SHIFT * texel).addScaledVector(ly, SHIFT * texel);
      const upd = sky.update;
      sky.update = (t, cam) => { upd(t, cam); sky.sun.position.add(off); sky.sun.target.position.add(off); sky.sun.target.updateMatrixWorld(); };
    }
    const MASK = `
#include <shadowmask_pars_fragment>
vec4 sunMaskOut() {
#if defined( USE_SHADOWMAP ) && NUM_DIR_LIGHT_SHADOWS > 0
	return receiveShadow ? vec4( vec3( getShadowMask() ), 1.0 ) : vec4( 0.0, 1.0, 0.0, 1.0 );
#else
	return vec4( 0.0, 1.0, 0.0, 1.0 );
#endif
}`;
    const n = { materials: 0, lit: 0, unlit: 0, transparent: 0, receivers_unlit: 0 };
    const seen = new Map();
    const patch = (m, receives) => {
      if (seen.has(m)) { if (receives && seen.get(m) === 'unlit') n.receivers_unlit++; return; }
      n.materials++;
      const before = m.onBeforeCompile, key = m.customProgramCacheKey;
      const transparent = m.transparent && (m.opacity < 1 || m.blending !== THREE.NormalBlending || m.depthWrite === false);
      let kind = 'unlit';
      m.onBeforeCompile = function (shader, r) {
        if (before) before.call(this, shader, r);
        let fs = shader.fragmentShader;
        const lit = fs.includes('#include <shadowmap_pars_fragment>') && fs.includes('#include <lights_pars_begin>');
        const outc = transparent ? 'vec4( 1.0, 0.0, 0.0, 1.0 )' : lit ? 'sunMaskOut()' : 'vec4( 0.0, 1.0, 0.0, 1.0 )';
        if (lit && !transparent) fs = fs.replace('#include <shadowmap_pars_fragment>', '#include <shadowmap_pars_fragment>' + MASK);
        const end = fs.lastIndexOf('}');
        shader.fragmentShader = fs.slice(0, end) + `\tgl_FragColor = ${outc};\n` + fs.slice(end);
      };
      m.customProgramCacheKey = function () { return (key ? key.call(this) : '') + '|sunmask'; };
      m.needsUpdate = true;
      kind = transparent ? 'transparent' : (m.isMeshToonMaterial || m.isMeshLambertMaterial || m.isMeshStandardMaterial || m.isMeshPhongMaterial || m.isShadowMaterial || (m.isShaderMaterial && m.lights)) ? 'lit' : 'unlit';
      n[kind]++;
      if (receives && kind === 'unlit') n.receivers_unlit++;
      seen.set(m, kind);
    };
    c.scene.traverse((o) => {
      if (!(o.isMesh || o.isLine || o.isPoints || o.isSprite) || o === sky.mesh) return;
      for (const m of (Array.isArray(o.material) ? o.material : [o.material])) if (m) patch(m, o.receiveShadow);
    });
    return n;
  }, W, H, SHIFT);
  const info = await page.evaluate(() => ({ revision: window.THREE.REVISION, errors: window.__errors }));
  const meta = { revision: info.revision, size: [W, H], cams, angle: ANGLE, shift_texels: SHIFT, census, views: [], only: args.only || null, q: args.q || 'high', t: Number(args.t || 0) };
  for (let i = 0; i < cams.length; i++) {
    const v = cams[i].split(',').map(Number);
    await page.evaluate((v) => { if (v.length === 4) window.__setCam(v[0], null, v[1], v[2], v[3]); else window.__setCam(v[0], v[1], v[2], v[3], v[4]); }, v);
    await frames(page);
    const vm = await page.evaluate(() => {
      const c = window.__ctx, r = c.renderer, s = c.scene, cam = c.camera, sky = c.sky, sh = sky.sun.shadow;
      const vis = sky.mesh.visible; sky.mesh.visible = false;
      const bg = s.background, fog = s.fog; s.background = null; s.fog = null;
      cam.layers.enableAll();
      const auto = r.shadowMap.autoUpdate; r.shadowMap.autoUpdate = false;
      r.setRenderTarget(window.__maskRT); r.setClearColor(0x0000ff, 1); r.clear(); r.render(s, cam); r.setRenderTarget(null);
      s.background = bg; s.fog = fog; sky.mesh.visible = vis; r.shadowMap.autoUpdate = auto;
      const v3 = (a) => [a.x, a.y, a.z];
      return { position: v3(cam.position), matrixWorld: Array.from(cam.matrixWorld.elements), projectionMatrix: Array.from(cam.projectionMatrix.elements),
        sunPosition: v3(sky.sun.position), sunTarget: v3(sky.sun.target.position), shadowMatrix: Array.from(sh.matrix.elements) };
    });
    meta.views.push(vm);
    const rows = 120;
    const fd = fs.openSync(path.join(out, `mask_${i}.f32`), 'w');
    for (let y0 = 0; y0 < H; y0 += rows) {
      const h = Math.min(rows, H - y0);
      const b64 = await page.evaluate((y0, h, W) => {
        const buf = new Float32Array(W * h * 4);
        window.__ctx.renderer.readRenderTargetPixels(window.__maskRT, 0, y0, W, h, buf);
        const u8 = new Uint8Array(buf.buffer); let s = '';
        for (let k = 0; k < u8.length; k += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(k, k + 0x8000));
        return btoa(s);
      }, y0, h, W);
      fs.writeSync(fd, Buffer.from(b64, 'base64'));
    }
    fs.closeSync(fd);
    console.log(`view ${i} cam=[${cams[i]}] eye=(${vm.position.map(x => x.toFixed(4)).join(', ')}) shadow target=(${vm.sunTarget.map(x => x.toFixed(4)).join(', ')})`);
  }
  fs.writeFileSync(path.join(out, 'meta.json'), JSON.stringify(meta, null, 1));
  console.log('three r' + info.revision, 'angle', ANGLE, 'shift', SHIFT, 'materials', JSON.stringify(census));
  if (info.errors && info.errors.length) { console.log('MODULE ERRORS:'); for (const e of info.errors) console.log(` - [${e.module}] ${e.message.split('\n').slice(0, 6).join('\n   ')}`); process.exitCode = 1; }
} catch (e) {
  console.log('SUN_MASK FAILED:', e.message);
  process.exitCode = 1;
} finally {
  if (logs.length) { console.log('PAGE LOGS:'); for (const l of logs.slice(0, 60)) console.log(' ', l.slice(0, 600)); }
  await browser.close();
  server.close();
}
