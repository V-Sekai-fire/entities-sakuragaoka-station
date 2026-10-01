// A temp-dir mirror of the original's checkout (junctions and copies) with files laid over it, so the checkout is never edited.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function link(src, dst) {
  if (fs.statSync(src).isDirectory()) fs.symlinkSync(src, dst, 'junction');
  else fs.copyFileSync(src, dst);
}

// extras: { 'relative/path': source file | { text } }
export function makeShadowRoot(root, name, extras) {
  const shadow = path.join(os.tmpdir(), name);
  removeShadowRoot(shadow);
  const dirs = new Set();
  for (const rel of Object.keys(extras)) {
    const parts = rel.split('/');
    for (let i = 1; i < parts.length; i++) dirs.add(parts.slice(0, i).join('/'));
  }
  const mirror = (rel) => {
    const src = path.join(root, rel), dst = path.join(shadow, rel);
    fs.mkdirSync(dst, { recursive: true });
    for (const e of fs.readdirSync(src)) {
      const r = rel ? `${rel}/${e}` : e;
      if (dirs.has(r)) mirror(r);
      else if (!(r in extras)) link(path.join(src, e), path.join(dst, e));
    }
  };
  mirror('');
  for (const [rel, v] of Object.entries(extras)) {
    const dst = path.join(shadow, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    if (typeof v === 'string') fs.copyFileSync(v, dst);
    else fs.writeFileSync(dst, v.text);
  }
  return shadow;
}

export function removeShadowRoot(shadow) {
  fs.rmSync(shadow, { recursive: true, force: true });
}
