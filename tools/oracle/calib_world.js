// Engine-floor calibration world for the original (three.js), loaded by the original's own page
// as ?only=calib: tools/oracle/calib.mjs serves this file at /src/world/calib.js, so main.js builds
// it with ctx.mat (core/materials.js), lights and fogs it with core/sky.js and renders it through
// core/renderer.js, exactly as it does the station. The tiles come from calib_scene.json (the same
// file tools/engine_floor.gd builds the port's side from).
//
// Charts (tools/calib/chart24.json, served at /chart24.json): a tile's "charts" are 24-patch charts
// laid out as chart24.svg (690 x 470 px canvas, 100 px patches, 10 px gaps, 20 px margin, #1a1a1a
// ground), "px" metres a canvas pixel, facing +Z turned by "yaw", each patch its own unlit
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
  grp.rotation.set(0, deg(c.yaw), 0);
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
  if (ctx.renderer) hookPost(ctx.renderer);
  window.__calib = scene;
}
