// The original with sakura/materials.js blossom-mass extensions off (shot.mjs --patch-arg, comma list of
// oct, wobble, speck, rim, shade, dapple), and with the blossom cards hidden for "cards".
(arg) => {
  const offs = arg.split(',').filter((w) => w);
  const edits = {
    oct: ['vertexShader', 'vec3 objectNormal = normalize( vec3( uv.x, color.b, uv.y ) + vec3( 0.0, 1e-4, 0.0 ) );', 'vec3 objectNormal = vec3( normal );'],
    wobble: ['fragmentShader', /float tn = vColor\.r \+[^;]*;/, 'float tn = vColor.r;'],
    rim: ['fragmentShader', /totalEmissiveRadiance \+= (glow|diffuseColor)/g, 'totalEmissiveRadiance += 0.0 * $1'],
    shade: ['fragmentShader', /outgoingLight = mix\( outgoingLight, lav, [^;]*;/, ''],
    dapple: ['fragmentShader', 'if ( sakuraDapple( vDW ) ) discard;', ''],
  };
  for (const w of offs) if (w !== 'cards' && w !== 'speck' && !edits[w]) throw new Error('sakura_off: unknown switch ' + w);
  const mats = new Map();
  let cards = 0;
  window.__ctx.scene.traverse((o) => {
    if (!o.isMesh || !o.material) return;
    if (offs.includes('cards') && o.material.name === 'sakura:cards') { o.visible = false; cards++; }
    if (o.material.name === 'sakura:blob') {
      mats.set(o.material, offs.filter((w) => w !== 'dapple' && w !== 'cards'));
      if (offs.includes('dapple')) mats.set(o.customDepthMaterial, ['dapple']);
    }
  });
  let applied = 0;
  for (const [m, ws] of mats) {
    if (!ws.length) continue;
    const prev = m.onBeforeCompile;
    m.onBeforeCompile = (sh, r) => {
      prev.call(m, sh, r);
      for (const w of ws) {
        if (w === 'speck') { sh.uniforms.uSpeckK.value = 0.0; continue; }
        const [part, find, put] = edits[w];
        const before = sh[part];
        sh[part] = before.replace(find, put);
        if (sh[part] === before) throw new Error('sakura_off: ' + w + ' found nothing to switch off');
      }
      applied++;
    };
    const key = m.customProgramCacheKey();
    m.customProgramCacheKey = () => key + '|off-' + ws.join('-');
    m.needsUpdate = true;
  }
  window.__patchReport = () => ({ compiled: applied, cards });
  return { switches: offs, materials: [...mats.values()].filter((ws) => ws.length).length, cards };
}
