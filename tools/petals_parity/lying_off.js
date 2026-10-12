// Hide the lying petals (petals-ground, petals-carpet): the port holds those alpha cards for now.
(arg) => {
  let n = 0;
  window.__ctx.scene.traverse((o) => { if (o.name === 'petals-ground' || o.name === 'petals-carpet') { o.visible = false; n++; } });
  return n;
}
