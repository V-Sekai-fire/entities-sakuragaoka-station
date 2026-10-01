// The calibration chart through the port's texture pipeline's first stage: the original page draws
// the keyed canvas texture calib-chart24 (calib_world.js: fillRect per patch in its sRGB 8-bit
// colour, through the original's ctx.tex.draw) and canvas_svg.mjs records it and emits its SVG,
// exactly as it does the station's textures. canvas_svg.mjs serves the original's checkout, which
// has no calibration module, so this builds a shadow root in the OS temp directory that links every
// entry of the checkout (directory junctions, file copies) and adds src/world/calib.js,
// calib_scene.json and chart24.json; the checkout itself is not touched, nor is canvas_svg.mjs.
// usage:
//   node tools/oracle/calib_svg.mjs --out <dir> [--root <original checkout>] [--chrome <path>]
//   writes <dir>/calib-chart24.svg (+ canvas_svg.mjs' manifest.json)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const out = path.resolve(args.out || 'shots/calib/svg');
const shadow = path.join(os.tmpdir(), 'sakuragaoka-calib-root');

function link(src, dst) {
  if (fs.statSync(src).isDirectory()) fs.symlinkSync(src, dst, 'junction');
  else fs.copyFileSync(src, dst);
}
function mirror(srcDir, dstDir, keep) {
  fs.mkdirSync(dstDir, { recursive: true });
  for (const e of fs.readdirSync(srcDir)) if (!keep.has(e)) link(path.join(srcDir, e), path.join(dstDir, e));
}

fs.rmSync(shadow, { recursive: true, force: true });
mirror(root, shadow, new Set(['src']));
mirror(path.join(root, 'src'), path.join(shadow, 'src'), new Set(['world']));
mirror(path.join(root, 'src', 'world'), path.join(shadow, 'src', 'world'), new Set());
fs.copyFileSync(path.join(here, 'calib_world.js'), path.join(shadow, 'src', 'world', 'calib.js'));
fs.copyFileSync(path.join(here, 'calib_scene.json'), path.join(shadow, 'calib_scene.json'));
fs.copyFileSync(path.join(here, '..', 'calib', 'chart24.json'), path.join(shadow, 'chart24.json'));

const CHROME = args.chrome || ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(p => fs.existsSync(p));
fs.mkdirSync(out, { recursive: true });
const r = spawnSync(process.execPath, [path.join(here, 'canvas_svg.mjs'), '--root', shadow, '--only', 'calib', '--keys', 'calib-chart24', '--out', out, '--chrome', CHROME],
  { stdio: 'inherit' });
fs.rmSync(shadow, { recursive: true, force: true });
const svg = path.join(out, 'calib-chart24.svg');
console.log(fs.existsSync(svg) ? `calib_svg: wrote ${svg}` : 'calib_svg: FAIL no calib-chart24.svg');
process.exitCode = r.status || (fs.existsSync(svg) ? 0 : 1);
