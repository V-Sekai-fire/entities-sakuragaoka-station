// Hide the lying petals and draw only the airborne kind given as the patch arg (glint = 3, soft = 5).
(arg) => {
  const k = Number(arg);
  let n = 0;
  window.__ctx.scene.traverse((o) => {
    if (o.name === 'petals-ground' || o.name === 'petals-carpet' || o.name === 'petals-rafts' || o.name === 'petals-floating') { o.visible = false; return; }
    if (o.name === 'petals-fall' || o.name === 'petals-soft' || o.name === 'petals-glint') {
      const m = o.material;
      m.vertexShader = m.vertexShader.replace('float kind = aA.w;', 'float kind = aA.w; if (abs(kind - ' + k.toFixed(1) + ') > 0.5) { gl_Position = vec4(0.0, 0.0, 2.0, 1.0); return; }');
      m.needsUpdate = true; n++;
    }
  });
  return n;
}
