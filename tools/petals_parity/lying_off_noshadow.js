// Hide the lying petals and turn the airborne / floating petals' sun-shadow lookup off (petalShadow() = 1),
// as the port draws them.
(arg) => {
  let n = 0;
  window.__ctx.scene.traverse((o) => {
    if (o.name === 'petals-ground' || o.name === 'petals-carpet') { o.visible = false; return; }
    if (o.material && o.material.isShaderMaterial && /^petals-/.test(o.material.name)) {
      o.material.fragmentShader = o.material.fragmentShader.replace(/sh = getShadow\([^;]*;/, 'sh = 1.0;');
      o.material.needsUpdate = true; n++;
    }
  });
  return n;
}
