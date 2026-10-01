// The in-view charts in the original: unedited shot.mjs on a shadow checkout that adds calib_world.js and the placements.
// node tools/oracle/calib_inview.mjs --placements <placements.json> --out <prefix> [--runs 2] [--root <dir>] [--chrome <path>]
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { makeShadowRoot, removeShadowRoot } from './shadow_root.mjs';

const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1'; args[k] = v; } }
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root || path.join(here, '../../../../3-interactor/sakuragaoka-station-upstream'));
if (!args.placements || !args.out) { console.log('usage: node tools/oracle/calib_inview.mjs --placements <placements.json> --out <prefix> [--runs 2]'); process.exit(2); }
const placements = JSON.parse(fs.readFileSync(args.placements, 'utf8'));
const out = path.resolve(args.out);
const runs = Number(args.runs || 1);
const modules = (placements.modules || ['environment', 'station', 'plaza', 'sakura']).concat(['calib']).join(',');
const scene = { w: placements.w || 1920, h: placements.h || 1080, note: 'in-view charts (tools/chart_in_view.gd)', tiles: [], views: placements.views };

const shadow = makeShadowRoot(root, 'sakuragaoka-calib-inview-root', {
  'src/world/calib.js': path.join(here, 'calib_world.js'),
  'calib_scene.json': { text: JSON.stringify(scene) },
  'chart24.json': path.join(here, '..', 'calib', 'chart24.json'),
});
let status = 0;
try {
  for (let r = 1; r <= runs; r++) {
    const prefix = r === 1 ? out : `${out}${r}`;
    console.log(`calib_inview: run ${r} -> ${prefix}_<i>.png (--only ${modules})`);
    const a = [path.join(here, 'shot.mjs'), '--root', shadow, '--hammersley', placements.hammersley, '--w', String(scene.w), '--h', String(scene.h),
      '--only', modules, '--q', placements.quality || 'high', '--out', prefix];
    if (args.chrome) a.push('--chrome', args.chrome);
    const res = spawnSync(process.execPath, a, { stdio: 'inherit' });
    if (res.status) status = res.status;
  }
} finally {
  removeShadowRoot(shadow);
}
process.exitCode = status;
