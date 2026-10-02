// Engine-floor calibration world for the original (three.js), loaded by the original's own page
// as ?only=calib: tools/oracle/calib.mjs serves this file at /src/world/calib.js, so main.js builds
// it with ctx.mat (core/materials.js), lights and fogs it with core/sky.js and renders it through
// core/renderer.js, exactly as it does the station. The tiles come from calib_scene.json (the same
// file tools/engine_floor.gd builds the port's side from).
//
// Charts (tools/calib/chart24.json, served at /chart24.json): a tile's "charts" are 24-patch charts
// laid out as chart24.svg (690 x 470 px canvas, 100 px patches, 10 px gaps, 20 px margin, #1a1a1a
// ground), "px" metres a canvas pixel, facing +Z turned by "yaw" then "pitch" (YXZ), each patch its own unlit
// (ctx.mat.emissive) or toon (ctx.mat.toon, paint 0) material. The same chart is also drawn as a
// keyed canvas texture, calib-chart24, with fillRect in the patches' sRGB 8-bit colours, through the
// original's ctx.tex.draw: a tile's "textured" quad shows it (three.js's own texture path), and
// tools/oracle/calib_svg.mjs records it with canvas_svg.mjs for the port's texture path.
// Tiles with "engines" not naming "three" are the port's alone and are skipped here.
//
// Post stages: window.__post = {outline, bloom, grade, leak, vignette, dither} (0/1 each) switches
// the composite's stages for the next frames. Nothing in core/ is edited: renderer.render is
// wrapped, and when the pipeline draws its composite pass the quad is drawn with a copy of the
// composite shader whose grading and dither lines sit behind uniforms (the other stages already
// have one: uOutline, uBloom, uGlow, uLeak, uVignette). All on = the original pipeline.
import * as THREE from 'three';

const deg = THREE.MathUtils.degToRad;

function geometry(o) {
  const a = o.args;
  switch (o.geo) {
    case 'plane': return new THREE.PlaneGeometry(a[0], a[1]);
    case 'sphere': return new THREE.SphereGeometry(a[0], a[1], a[2]);
    case 'cylinder': return new THREE.CylinderGeometry(a[0], a[1], a[2], a[3]);
    case 'box': return new THREE.BoxGeometry(a[0], a[1], a[2]);
  }
  throw new Error('calib: unknown geometry ' + o.geo);
}

function material(ctx, m) {
  if (m.kind === 'emissive') return ctx.mat.emissive(m.color, m.intensity ?? 1.0);
  return ctx.mat.toon(m.color, { paint: m.paint ?? 0.05 });
}

/** A grid of flat unlit triangles, one mesh per colour (see calib_scene.json "grid"). */
function grid(ctx, g, origin) {
  const byColour = new Map();
  for (let c = 0; c < g.cols; c++) {
    for (let r = 0; r < g.rows; r++) {
      const x = g.x0 + c * g.cell, y = g.y0 + r * g.cell;
      const p00 = [x, y], p10 = [x + g.cell, y], p11 = [x + g.cell, y + g.cell], p01 = [x, y + g.cell];
      const tris = (c + r) % 2 === 0 ? [[p00, p10, p11], [p00, p11, p01]] : [[p00, p10, p01], [p10, p11, p01]];
      tris.forEach((t, k) => {
        const col = g.colors[(c * 7 + r * 3 + k) % g.colors.length];
        if (!byColour.has(col)) byColour.set(col, []);
        const arr = byColour.get(col);
        for (const p of t) arr.push(origin[0] + p[0], origin[1] + p[1], origin[2] + g.z);
      });
    }
  }
  for (const [col, pos] of byColour) {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    const nor = new Float32Array(pos.length);
    for (let i = 0; i < nor.length; i += 3) nor[i + 2] = 1;
    geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    const mesh = new THREE.Mesh(geo, ctx.mat.emissive(col, 1.0));
    mesh.name = 'calib-grid-' + col;
    ctx.addStatic(mesh);
  }
}

function hookPost(renderer) {
  const variants = new WeakMap();
  const orig = renderer.render.bind(renderer);
  renderer.render = (scene, camera) => {
    const quad = scene && scene.children && scene.children[0];
    const m = quad && quad.material;
    const P = window.__post;
    if (!P || !m || !m.uniforms || !m.uniforms.uOutline || !m.fragmentShader) return orig(scene, camera);
    let v = variants.get(m);
    if (!v) {
      let fs = m.fragmentShader;
      const a = fs.indexOf('        // ---------- exposure / tone'), b = fs.indexOf('        // ---------- light leak');
      const dither = 'outc += (hash(vUv * uRes + fract(uTime)) - 0.5) / 255.0;';
      if (a < 0 || b < 0 || fs.indexOf(dither) < 0) throw new Error('calib: the composite shader changed; cannot switch its stages');
      fs = fs.slice(0, a) + '        if (uGrade > 0.5) {\n' + fs.slice(a, b) + '        }\n' + fs.slice(b);
      fs = fs.replace(dither, 'if (uDither > 0.5) ' + dither);
      fs = fs.replace('uniform vec3 uLine;', 'uniform vec3 uLine; uniform float uGrade, uDither;');
      v = new THREE.ShaderMaterial({ uniforms: m.uniforms, vertexShader: m.vertexShader, fragmentShader: fs, depthTest: false, depthWrite: false });
      m.uniforms.uGrade = { value: 1 }; m.uniforms.uDither = { value: 1 };
      v.userData.defaults = { uOutline: m.uniforms.uOutline.value, uBloom: m.uniforms.uBloom.value, uGlow: m.uniforms.uGlow.value, uVignette: m.uniforms.uVignette.value };
      variants.set(m, v);
    }
    const u = m.uniforms, d = v.userData.defaults;
    u.uOutline.value = P.outline ? d.uOutline : 0;
    u.uBloom.value = P.bloom ? d.uBloom : 0;
    u.uGlow.value = P.bloom ? d.uGlow : 0;
    u.uVignette.value = P.vignette ? d.uVignette : 0;
    if (!P.leak) u.uLeak.value = 0;   // the pipeline sets its own value every frame before this pass
    u.uGrade.value = P.grade ? 1 : 0;
    u.uDither.value = P.dither ? 1 : 0;
    quad.material = v;
    try { return orig(scene, camera); } finally { quad.material = m; }
  };
}

const hex = (c) => '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');

/** The chart's canvas: fillRect per patch in its srgb8 colour, as chart24.svg draws it. */
function drawChart(g, chart) {
  g.fillStyle = '#1a1a1a';
  g.fillRect(0, 0, 690, 470);
  for (const p of chart.patches) {
    g.fillStyle = hex(p.srgb8);
    g.fillRect(20 + p.col * 110, 20 + p.row * 110, 100, 100);
  }
}

/** A chart as quads: the ground 5 mm behind, a patch per material. */
function chartMeshes(ctx, chart, c) {
  const grp = new THREE.Group();
  grp.position.set(c.pos[0], c.pos[1], c.pos[2]);
  grp.rotation.set(deg(c.pitch || 0), deg(c.yaw), 0, 'YXZ');
  const px = c.px;
  const colours = chart.patches.map((p) => hex(p.srgb8));
  if (c.swap) { const a = c.swap[0] - 1, b = c.swap[1] - 1; [colours[a], colours[b]] = [colours[b], colours[a]]; }
  const mat = (col) => (c.mat === 'toon' ? ctx.mat.toon(col, { paint: 0 }) : ctx.mat.emissive(col, 1.0));
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(690 * px, 470 * px), mat('#1a1a1a'));
  ground.position.z = -0.005;
  grp.add(ground);
  chart.patches.forEach((p, i) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(100 * px, 100 * px), mat(colours[i]));
    const cx = 20 + p.col * 110 + 50, cy = 20 + p.row * 110 + 50;
    m.position.set((cx - 345) * px, (235 - cy) * px, 0);
    grp.add(m);
  });
  grp.traverse((o) => { if (o.isMesh) { o.receiveShadow = !!c.receive; o.castShadow = false; o.name = 'calib-chart-' + (c.name || ''); } });
  return grp;
}

export async function build(ctx) {
  const scene = await (await fetch('/calib_scene.json', { cache: 'no-store' })).json();
  const chart = await (await fetch('/chart24.json', { cache: 'no-store' })).json();
  // the keyed canvas texture, drawn even when no tile shows it (canvas_svg.mjs records it)
  const chartTex = ctx.tex.draw(690, 470, (g) => drawChart(g, chart), { key: 'calib-chart24' });
  for (const t of scene.tiles) {
    if (t.engines && !t.engines.includes('three')) continue;
    for (const c of t.charts || []) ctx.addStatic(chartMeshes(ctx, chart, c));
    if (t.textured) {
      const q = new THREE.Mesh(new THREE.PlaneGeometry(690 * t.textured.px, 470 * t.textured.px), ctx.mat.emissive('#ffffff', 1.0, { map: chartTex }));
      q.position.set(t.textured.pos[0], t.textured.pos[1], t.textured.pos[2]);
      q.rotation.set(0, deg(t.textured.yaw), 0);
      q.name = 'calib-chart-texture';
      ctx.addStatic(q);
    }
    if (t.grid) grid(ctx, t.grid, [0, 0, 0]);
    for (const o of t.objects) {
      const mesh = new THREE.Mesh(geometry(o), material(ctx, o.mat));
      mesh.position.set(o.pos[0], o.pos[1], o.pos[2]);
      mesh.rotation.set(deg(o.rot[0]), deg(o.rot[1]), deg(o.rot[2]));
      mesh.castShadow = !!o.cast;
      mesh.receiveShadow = !!o.receive;
      mesh.name = 'calib-' + t.id + '-' + o.geo;
      ctx.addStatic(mesh);
    }
  }
  if (scene.views) inViewCharts(ctx, chart, scene.views);
  if (scene.probe) shadowProbes(ctx, scene.probe);
  for (const root of scene.hide ? [ctx.staticRoot, ctx.dynamicRoot] : []) root.traverse((o) => { if (scene.hide.some((h) => (o.name || '').startsWith(h))) o.visible = false; });
  if (ctx.renderer) hookPost(ctx.renderer);
  window.__calib = scene;
}

// Shadow probes for calib_probe.mjs: a black ShadowMaterial quad over a magenta one reads magenta in sun, black in shadow.
// __probeShow(ids) shows those probes; __probeRead(ids) classifies each as lit, shadow, mixed, hidden or offscreen.
function shadowProbes(ctx, probe) {
  const screenMat = new THREE.MeshBasicMaterial({ color: 0xff00ff, fog: false });
  const shadowMat = new THREE.ShadowMaterial({ color: 0x000000, opacity: 1, fog: false, depthWrite: false });
  const all = new Map();
  for (const v of probe.views) for (const c of v.cands) {
    const w = 690 * c.px * probe.margin, h = 470 * c.px * probe.margin;
    const g = new THREE.Group();
    g.position.set(c.pos[0], c.pos[1], c.pos[2]);
    g.rotation.set(deg(c.pitch || 0), deg(c.yaw), 0, 'YXZ');
    const back = new THREE.Mesh(new THREE.PlaneGeometry(w, h), screenMat);
    back.castShadow = false; back.receiveShadow = false;
    const front = new THREE.Mesh(new THREE.PlaneGeometry(w, h), shadowMat);
    front.position.z = 0.001; front.castShadow = false; front.receiveShadow = true;
    g.add(back, front);
    ctx.noBatch(g); ctx.noOutline(g);
    g.visible = false;
    ctx.addStatic(g);
    all.set(c.id, { g, w, h });
  }
  window.__probeShow = (ids) => { const on = new Set(ids); for (const [id, p] of all) p.g.visible = on.has(id); };
  window.__probeRead = (ids) => {
    const r = ctx.renderer, gl = r.getContext();
    const W = gl.drawingBufferWidth, H = gl.drawingBufferHeight;
    const px = new Uint8Array(W * H * 4);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const out = {};
    for (const id of ids) {
      const p = all.get(id);
      p.g.updateMatrixWorld(true);
      const q = [[-1, 1], [1, 1], [1, -1], [-1, -1]].map(([sx, sy]) => {
        const v = new THREE.Vector3(sx * p.w / 2, sy * p.h / 2, 0).applyMatrix4(p.g.matrixWorld).project(ctx.camera);
        return [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H, v.z];
      });
      if (q.some((c) => c[2] > 1 || c[2] < -1)) { out[id] = { state: 'offscreen' }; continue; }
      const cx = q.reduce((a, c) => a + c[0], 0) / 4, cy = q.reduce((a, c) => a + c[1], 0) / 4;
      const edges = q.map((a, i) => {
        const b = q[(i + 1) % 4]; let ex = b[0] - a[0], ey = b[1] - a[1]; const l = Math.hypot(ex, ey); ex /= l; ey /= l;
        let nx = -ey, ny = ex; if ((cx - a[0]) * nx + (cy - a[1]) * ny < 0) { nx = -nx; ny = -ny; }
        return [a[0], a[1], nx, ny];
      });
      const y0 = Math.max(0, Math.floor(Math.min(...q.map((c) => c[1])))), y1 = Math.min(H - 1, Math.ceil(Math.max(...q.map((c) => c[1]))));
      let n = 0, hidden = 0, lo = 255, hi = 0;
      for (let y = y0; y <= y1; y++) {
        const yc = y + 0.5; let x0 = -Infinity, x1 = Infinity, ok = true;
        for (const [ax, ay, nx, ny] of edges) {
          const rhs = 2 + ax * nx + ay * ny - ny * yc;
          if (Math.abs(nx) < 1e-6) { if (rhs > 0) ok = false; } else if (nx > 0) x0 = Math.max(x0, rhs / nx); else x1 = Math.min(x1, rhs / nx);
        }
        if (!ok) continue;
        for (let x = Math.max(0, Math.ceil(x0 - 0.5)); x <= Math.min(W - 1, Math.floor(x1 - 0.5)); x++) {
          const i = ((H - 1 - y) * W + x) * 4;
          n++;
          if (px[i + 1] > 4 || Math.abs(px[i] - px[i + 2]) > 4) { hidden++; continue; }
          lo = Math.min(lo, px[i]); hi = Math.max(hi, px[i]);
        }
      }
      out[id] = { state: n === 0 ? 'offscreen' : hidden > 0 ? 'hidden' : lo >= 250 ? 'lit' : hi <= 5 ? 'shadow' : 'mixed', pixels: n, hidden, att_min: lo / 255, att_max: hi / 255 };
    }
    return out;
  };
}

// The in-view charts (calib_scene.json "views"), unbatched and shown only while the camera looks along their view,
// since shot.mjs renders every view in one page.
function inViewCharts(ctx, chart, views) {
  const dir = (yaw, pitch) => new THREE.Vector3(-Math.sin(deg(yaw)) * Math.cos(deg(pitch)), Math.sin(deg(pitch)), -Math.cos(deg(yaw)) * Math.cos(deg(pitch)));
  const groups = views.map((v) => v.charts.map((c) => {
    const g = chartMeshes(ctx, chart, { ...c, mat: 'toon', receive: true });
    ctx.noBatch(g);
    g.visible = false;
    return ctx.addStatic(g);
  }));
  const dirs = views.map((v) => dir(v.cam[2], v.cam[3]));
  const f = new THREE.Vector3();
  ctx.onUpdate(() => {
    ctx.camera.getWorldDirection(f);
    let best = 0;
    dirs.forEach((d, i) => { if (d.dot(f) > dirs[best].dot(f)) best = i; });
    groups.forEach((gs, i) => gs.forEach((g) => { g.visible = i === best; }));
  });
}
