// Debug: build a module list with the original and print ctx.services.petals.counts.
// usage: node dbg.mjs mod1,mod2,...,petals
import { pathToFileURL } from 'node:url';
import path from 'node:path';
const root = '/Users/ernest.lee/.hermes/cache/scratch/ssu';
await import(pathToFileURL(path.join(root, 'tools/dom-stubs.mjs')).href);
const THREE = await import(pathToFileURL(path.join(root, 'node_modules/three/build/three.module.js')).href);
const L = await import(pathToFileURL(path.join(root, 'src/world/layout.js')).href);
const { createContext } = await import(pathToFileURL(path.join(root, 'src/core/ctx.js')).href);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(58, 16 / 9, 0.1, 2500);
camera.position.set(0, 1.6, 30);
const sunDir = new THREE.Vector3(...L.SUN_DIR).normalize();
const quality = { name: 'high', pixelRatio: 1, msaa: 4, shadowMap: 4096, shadowSize: 75, petals: 1 };
const ctx = createContext({ scene, camera, renderer: null, audio: null, quality, sunDir });
ctx.sky = { sun: new THREE.DirectionalLight(), hemi: new THREE.HemisphereLight(), uniforms: {} };
globalThis.__dbg = [];
for (const name of process.argv[2].split(',')) {
  const mod = await import(pathToFileURL(path.join(root, `src/world/${name}.js`)).href);
  await mod.build(ctx);
}
console.log(JSON.stringify(ctx.services.petals.counts));
if (globalThis.__dbg.length) console.log(JSON.stringify(globalThis.__dbg.slice(0, 200)));
