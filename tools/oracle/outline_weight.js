// The original's composite outline (renderer.js's uOutline, set as its pass is drawn) at --patch-arg; 0 isolates it.
(arg) => {
  const w = Number(arg === '' ? 1 : arg);
  if (!Number.isFinite(w)) throw new Error('outline_weight: --patch-arg is not a number: ' + arg);
  const r = window.__ctx.renderer;
  const render = r.render.bind(r);
  let set = 0;
  r.render = (scene, camera) => {
    const u = scene.children.length === 1 && scene.children[0].material && scene.children[0].material.uniforms;
    if (u && u.uOutline && u.tND) { u.uOutline.value = w; set++; }
    return render(scene, camera);
  };
  window.__patchReport = () => {
    if (!set) throw new Error('outline_weight: no composite pass was drawn, so uOutline was never set');
    return { outline: w, passes: set };
  };
  return { outline: w };
}
