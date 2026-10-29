// The oracle a port of the world generation is checked against: per module, right after build(ctx)
// (t = 0, no update ran), its triangles, vertices, bounds, vertex centroid and meshes by colour.
// A module's numbers depend on what was built before it (sakura reads houses' garden spots when
// houses ran), so every build names its module list and runs in a fresh node process.
//
// usage: node tools/reference.mjs [--out=reference.json] [--seed=N] [--drop-lot=ID]
//          [--build=name:mod1,mod2,...]...
// With no --build it writes "town" (every module, main.js order) and "dev" (the ported set).
// --seed=N re-keys every named stream as "N:key" (seed 1 keeps the original keys).
// --drop-lot=ID removes a main-street lot from the layout contract before any module loads.
import { pathToFileURL, fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => {
  const i = a.indexOf('='); return i < 0 ? [a.slice(2), true] : [a.slice(2, i), a.slice(i + 1)];
}));
const builds = process.argv.slice(2).filter(a => a.startsWith('--build=')).map(a => a.slice(8));
const seed = Number(args.seed ?? 1);

if (args.one) {
  await import('./dom-stubs.mjs');
  console.log(JSON.stringify(await buildOnce(String(args.one).split(','), seed, args['drop-lot'] || null)));
} else {
  const MODULES = ['environment', 'street', 'poles', 'railway', 'station', 'plaza', 'shopsA', 'shopsB',
    'houses', 'sakura', 'trains', 'crossing', 'props', 'vehicles', 'characters', 'petals']; // main.js order
  const plan = builds.length ? builds.map(b => b.split(':')) :
    [['town', MODULES.join(',')], ['dev', 'environment,station,plaza,sakura']];
  const extra = [...(args.seed ? ['--seed=' + seed] : []), ...(args['drop-lot'] ? ['--drop-lot=' + args['drop-lot']] : [])];
  const out = {
    generator: 'tools/reference.mjs',
    source: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root }).toString().trim(),
    three: (await import('three')).REVISION,
    seed, t: 0, dropLot: args['drop-lot'] || null,
    rng: rngVectors(),
    builds: {},
  };
  for (const [name, mods] of plan) {
    const json = execFileSync(process.execPath, [fileURLToPath(import.meta.url), '--one=' + mods, ...extra],
      { cwd: root, maxBuffer: 1 << 26, stdio: ['ignore', 'pipe', 'ignore'] }).toString();
    out.builds[name] = JSON.parse(json.trim().split('\n').pop());
  }
  const file = path.resolve(root, args.out || 'reference.json');
  writeFileSync(file, JSON.stringify(out, null, 1) + '\n');
  for (const [name, b] of Object.entries(out.builds)) {
    for (const m of b.modules) {
      const s = b.stats[m];
      console.log(`${name.padEnd(5)} ${m.padEnd(11)} ${s.ok ? 'ok  ' : 'FAIL'} tris ${String(s.triangles).padStart(8)}  meshes ${String(s.meshes).padStart(5)}  bounds ${s.bounds ? JSON.stringify(s.bounds) : '-'}`);
    }
  }
  console.log('wrote ' + path.relative(process.cwd(), file));
}

function rngVectors() {
  // mulberry32 exactly as src/core/ctx.js, for the port's RNG check
  const m32 = (s) => {
    let a = (typeof s === 'string' ? [...s].reduce((h, c) => (Math.imul(h ^ c.charCodeAt(0), 16777619)) >>> 0, 2166136261) : s) >>> 0;
    return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  };
  const v = (s) => { const r = m32(s); return Array.from({ length: 16 }, r); };
  return { 1: v(1), 'env-far': v('env-far'), '2:env-far': v('2:env-far') };
}

async function buildOnce(names, seed, dropLot) {
  const THREE = await import('three');
  const L = await import(pathToFileURL(path.join(root, 'src/world/layout.js')).href);
  if (dropLot) {
    const i = L.LOTS.findIndex(l => l.id === dropLot);
    if (i < 0) throw new Error('no lot ' + dropLot);
    L.LOTS.splice(i, 1);
  }
  const { createContext, mulberry32 } = await import(pathToFileURL(path.join(root, 'src/core/ctx.js')).href);
  const { createAudio } = await import(pathToFileURL(path.join(root, 'src/core/audio.js')).href);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(58, 16 / 9, 0.1, 2500);
  camera.position.set(0, 1.6, 30);
  const sunDir = new THREE.Vector3(...L.SUN_DIR).normalize();
  let audio; try { audio = createAudio(); } catch { audio = null; }
  const quality = { name: 'high', pixelRatio: 1, msaa: 4, shadowMap: 4096, shadowSize: 75, petals: 1 };
  const ctx = createContext({ scene, camera, renderer: null, audio, quality, sunDir });
  ctx.sky = { sun: new THREE.DirectionalLight(), hemi: new THREE.HemisphereLight(), uniforms: {} };
  if (seed !== 1) ctx.rng = (k) => mulberry32(`${seed}:${k}`);

  const stats = {};
  for (const name of names) {
    const before = new Set(); scene.traverse(o => before.add(o));
    let err = null;
    try {
      const mod = await import(pathToFileURL(path.join(root, `src/world/${name}.js`)).href);
      await mod.build(ctx);
    } catch (e) { err = String(e && e.stack || e).split('\n').slice(0, 3).join(' | '); }
    scene.updateMatrixWorld(true);
    const added = []; scene.traverse(o => { if (!before.has(o)) added.push(o); });
    let tris = 0, meshes = 0, inst = 0, instances = 0, verts = 0;
    const box = new THREE.Box3(), tb = new THREE.Box3(), sum = new THREE.Vector3(), p = new THREE.Vector3();
    const byColour = {};
    for (const o of added) {
      if (!o.isMesh && !o.isLine && !o.isPoints) continue;
      meshes++;
      if (o.isInstancedMesh) { inst++; instances += o.count; }
      const g = o.geometry;
      if (g && g.attributes.position) tris += (g.index ? g.index.count / 3 : g.attributes.position.count / 3) * (o.isInstancedMesh ? o.count : 1);
      for (const m of (Array.isArray(o.material) ? o.material : [o.material])) {
        if (!m) continue;
        const k = m.color ? '#' + m.color.getHexString() : m.type;
        byColour[k] = (byColour[k] || 0) + 1;
      }
      if (g && g.attributes.position && !o.isInstancedMesh && o.name !== 'wires') {
        if (!g.boundingBox) g.computeBoundingBox();
        if (!g.boundingBox.isEmpty() && Number.isFinite(g.boundingBox.min.x)) { tb.copy(g.boundingBox).applyMatrix4(o.matrixWorld); box.union(tb); }
        const a = g.attributes.position;
        for (let i = 0; i < a.count; i++) { p.fromBufferAttribute(a, i).applyMatrix4(o.matrixWorld); sum.add(p); }
        verts += a.count;
      }
    }
    const r4 = (v) => Math.round(v * 1e4) / 1e4;
    stats[name] = {
      ok: !err, error: err, triangles: Math.round(tris * 1000) / 1000, meshes, instancedMeshes: inst, instances, vertices: verts,
      bounds: box.isEmpty() ? null : { min: box.min.toArray().map(r4), max: box.max.toArray().map(r4) },
      centroid: verts ? sum.divideScalar(verts).toArray().map(r4) : null,
      byColour: Object.fromEntries(Object.entries(byColour).sort()),
    };
  }
  return { modules: names, stats };
}
