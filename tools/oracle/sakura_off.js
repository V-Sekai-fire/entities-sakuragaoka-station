// The original with one sakura/materials.js blossom-mass extension off (shot.mjs --patch-arg: oct,
// wobble, speck, rim, shade or dapple), or with the blossom cards hidden (cards).
(which) => {
  const mats = new Set();
  let cards = 0;
  window.__ctx.scene.traverse((o) => {
    if (!o.isMesh || !o.material) return;
    if (which === 'cards' && o.material.name === 'sakura:cards') { o.visible = false; cards++; }
    if (o.material.name === 'sakura:blob') mats.add(which === 'dapple' ? o.customDepthMaterial : o.material);
  });
  if (which === 'cards') {
    window.__patchReport = () => ({ hidden: cards });
    return { cards };
  }
  const edits = {
    oct: (sh) => ['vertexShader', 'vec3 objectNormal = normalize( vec3( uv.x, color.b, uv.y ) + vec3( 0.0, 1e-4, 0.0 ) );', 'vec3 objectNormal = vec3( normal );'],
    wobble: (sh) => ['fragmentShader', /float tn = vColor\.r \+[^;]*;/, 'float tn = vColor.r;'],
    rim: (sh) => ['fragmentShader', /totalEmissiveRadiance \+= (glow|diffuseColor)/g, 'totalEmissiveRadiance += 0.0 * $1'],
    shade: (sh) => ['fragmentShader', /outgoingLight = mix\( outgoingLight, lav, [^;]*;/, ''],
    dapple: (sh) => ['fragmentShader', 'if ( sakuraDapple( vDW ) ) discard;', ''],
  };
  if (which !== 'speck' && !edits[which]) throw new Error('sakura_off: unknown extension ' + which);
  let applied = 0;
  for (const m of mats) {
    const prev = m.onBeforeCompile;
    m.onBeforeCompile = (sh, r) => {
      prev.call(m, sh, r);
      if (which === 'speck') {
        sh.uniforms.uSpeckK.value = 0.0;
        applied++;
        return;
      }
      const [part, find, put] = edits[which](sh);
      const before = sh[part];
      sh[part] = before.replace(find, put);
      if (sh[part] === before) throw new Error('sakura_off: ' + which + ' found nothing to switch off');
      applied++;
    };
    const key = m.customProgramCacheKey();
    m.customProgramCacheKey = () => key + '|off-' + which;
    m.needsUpdate = true;
  }
  window.__patchReport = () => ({ compiled: applied });
  return { materials: mats.size, which };
}
