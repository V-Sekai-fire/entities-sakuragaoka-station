// The chart's canvas texture (calib-chart24) through canvas_svg.mjs, unedited, run on a shadow checkout that adds calib_world.js.
// node tools/oracle/calib_svg.mjs --out <dir> [--root <dir>] [--chrome <path>]; writes <dir>/calib-chart24.svg
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { makeShadowRoot, removeShadowRoot } from './shadow_root.mjs';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
const out = path.resolve(args.out || 'shots/calib/svg');
const shadow = makeShadowRoot(root, 'sakuragaoka-calib-root', {
  'src/world/calib.js': path.join(here, 'calib_world.js'),
  'calib_scene.json': path.join(here, 'calib_scene.json'),
  'chart24.json': path.join(here, '..', 'calib', 'chart24.json'),
});

const CHROME = args.chrome || ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(p => fs.existsSync(p));
fs.mkdirSync(out, { recursive: true });
const r = spawnSync(process.execPath, [path.join(here, 'canvas_svg.mjs'), '--root', shadow, '--only', 'calib', '--keys', 'calib-chart24', '--out', out, '--chrome', CHROME],
  { stdio: 'inherit' });
removeShadowRoot(shadow);
const svg = path.join(out, 'calib-chart24.svg');
console.log(fs.existsSync(svg) ? `calib_svg: wrote ${svg}` : 'calib_svg: FAIL no calib-chart24.svg');
process.exitCode = r.status || (fs.existsSync(svg) ? 0 : 1);
