# station/mats.js: the station material set, all from ctx.mat so identical requests share one
# material. Interior furniture shares one warm emissive signature so the colour bake can merge it.
extends RefCounted

const WARM_SIG := {"emissive": "#4a3826", "emissiveIntensity": 0.4}


static func make_materials(ctx, tx: Dictionary, tx2: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var C: Dictionary = ctx.palette
	var t := func(c, o: Dictionary = {}): return mat.toon(c, o)
	var e := func(c, i: float = 1.6, o: Dictionary = {}): return mat.emissive(c, i, o)
	var warm := func(i: float = 0.55, c: String = "#5f4a32", keep: bool = false) -> Dictionary:
		return {"emissive": c, "emissiveIntensity": i} if keep else WARM_SIG
	var ic := func(hex, paint = null):
		if paint == null:
			return mat.toon(hex, WARM_SIG.duplicate())
		var o := WARM_SIG.duplicate()
		o["paint"] = paint
		return mat.toon(hex, o)
	var tb = tx.bag
	var t2 = tx2.bag
	var A: Dictionary = tx.atlases
	var merge := func(a: Dictionary, b: Dictionary) -> Dictionary:
		var o := a.duplicate()
		o.merge(b, true)
		return o
	var pool = e.call("#fff0d6", 1.0, {"map": t2.pool, "transparent": true, "depthWrite": false, "opacity": 0.26})
	pool.polygonOffset = true
	var pool_wall = e.call("#fff0d6", 1.0, {"map": t2.pool, "transparent": true, "depthWrite": false, "opacity": 0.11})
	pool_wall.polygonOffset = true
	var umbrella_cols := []
	for c in ["#e7b1c2", "#5a79b8", "#d9e3ea", "#4f7f68", "#e2c05a", "#b64f5c"]:
		umbrella_cols.append(t.call(c, warm.call(0.25, "#2a2028")))
	return {
		"ic": ic,
		"pool": pool,
		"poolWall": pool_wall,
		"cork": t.call("#b8906a", warm.call(0.3, "#3a2818")),
		"corkBoard": t.call("#ffffff", {"map": t2.cork, "paint": 0.02, "emissive": "#4a3826", "emissiveIntensity": 0.45}),
		"grainWood": t.call("#b88a60", {"map": t2.grain, "paint": 0.03, "emissive": "#4a3220", "emissiveIntensity": 0.42}),
		"grainWoodDark": t.call("#8a6446", {"map": t2.grain, "paint": 0.03, "emissive": "#3a2818", "emissiveIntensity": 0.4}),
		"fixtureBody": t.call("#f2eee4", {"emissive": "#a09078", "emissiveIntensity": 0.55, "paint": 0.01}),
		"tubeLit": e.call("#fff4de", 1.35),
		"ledGreen": e.call("#7dffa0", 1.3), "ledRed": e.call("#ff6a5a", 1.3), "ledBlue": e.call("#7cc4ff", 1.4), "ledAmber": e.call("#ffc070", 1.3),
		"screenDim": e.call("#bcd6ee", 0.75),
		"smoked": t.call("#3d3a48", {"paint": 0.0, "emissive": "#1a1622", "emissiveIntensity": 0.3}),
		"chalkTray": t.call("#8a6446", WARM_SIG.duplicate()),
		"vinyl": mat.glass({"tint": "#e8eef2", "opacity": 0.5, "streaks": false}),
		"tactBase": t.call("#e2b640", {"paint": 0.02, "emissive": "#4a3a10", "emissiveIntensity": 0.35}),
		"tactBump": t.call("#eec450", {"paint": 0.01, "emissive": "#4a3a10", "emissiveIntensity": 0.35}),
		"tactJoint": t.call("#b8902c", {"paint": 0.0, "emissive": "#3a2c10", "emissiveIntensity": 0.3}),
		"plasterExt": t.call("#fff0d2", {"map": tb.plaster, "paint": 0.07}),
		"plasterInt": t.call("#fff7e8", merge.call({"map": tb.plaster, "paint": 0.03}, warm.call(0.62, "#7a5e40", true))),
		"plinth": t.call("#b9b3a7", {"paint": 0.09}),
		"band": t.call("#d3ccbc", {"paint": 0.04}),
		"trim": t.call("#5f4b3d", {"paint": 0.03}),
		"trimInt": t.call("#6a5546", warm.call(0.35, "#3a2a1c")),
		"sill": t.call("#e7e0cf", {"paint": 0.03}),
		"fascia": t.call("#50545c", {"paint": 0.03}),
		"roof": t.call("#4b505a", {"paint": 0.07}),
		"roofSeam": t.call("#5c636e", {"paint": 0.03}),
		"soffit": t.call("#dcd5c5", {"paint": 0.03}),
		"gutter": t.call("#80868e", {"paint": 0.03}),
		"alu": t.call("#b8bdc3", {"paint": 0.02}),
		"aluDark": t.call("#8c9299", {"paint": 0.02}),
		"stainless": t.call("#c6cbcf", {"paint": 0.02}),
		"steel": t.call(C.steel, {"paint": 0.03}), "steelDark": t.call(C.steelDark, {"paint": 0.03}),
		"glass": mat.glass({"tint": "#9fb6c8", "opacity": 0.34}),
		"glassIn": mat.glass({"tint": "#c3d0d8", "opacity": 0.14, "streaks": false}),
		"frost": mat.glass({"frost": true, "tint": "#dfe6ea"}),
		"floor": t.call("#fffaf0", merge.call({"map": tb.floorTile, "paint": 0.02}, warm.call(0.62, "#6a5034", true))),
		"ceiling": t.call("#f4f0e6", merge.call({"paint": 0.02}, warm.call(0.75, "#7a6448", true))),
		"ceilingGrid": t.call("#d9d2c2", warm.call(0.4, "#4a3d2c", true)),
		"tube": e.call("#f6fbff", 1.3),
		"tubeWarm": e.call("#fff1d6", 1.2),
		"lampWarm": e.call("#ffd9a0", 1.35),
		"lampGlow": e.call("#ffe8c4", 1.05),
		"screen": e.call("#dff0ff", 1.0),
		"darkPanel": t.call("#3d3f48", {"paint": 0.02}),
		"woodInt": t.call("#9a7352", warm.call(0.3, "#3a2818")),
		"woodIntDark": t.call("#6e5140", warm.call(0.25, "#2e2016")),
		"counterTop": t.call("#c9a57a", warm.call(0.3, "#3a2818")),
		"tvmBody": t.call("#c3d3df", warm.call(0.3, "#2f3440")),
		"tvmDark": t.call("#5d6674", warm.call(0.2, "#20242c")),
		"gateBody": t.call("#d5dade", warm.call(0.3, "#303440")),
		"gateTop": t.call("#4c5161", warm.call(0.15, "#1c1e26")),
		"gateBase": t.call("#7c828b", warm.call(0.2, "#22252c")),
		"flap": t.call("#e89f6c", warm.call(0.3, "#402616")),
		"boothPanel": t.call("#8fa7ae", warm.call(0.3, "#263036")),
		"officeDesk": t.call("#b9b7ad", warm.call(0.35, "#2e2c26")),
		"officeGrey": t.call("#8f949b", warm.call(0.3, "#24262a")),
		"plantPot": t.call("#c7a489", warm.call(0.25)),
		"leafInt": t.call("#5f8c5c", warm.call(0.25, "#1f301c")),
		"binBlue": t.call("#3f6fb0"), "binGreen": t.call("#3f8a5c"), "binRed": t.call("#c9504a"), "binGrey": t.call("#8e949b"),
		"binBlueI": t.call("#3f6fb0", warm.call(0.25, "#101c30")), "binGreenI": t.call("#3f8a5c", warm.call(0.25, "#10281a")), "binRedI": t.call("#c9504a", warm.call(0.25, "#301410")),
		"umbrellaCols": umbrella_cols,
		"concrete": t.call("#ffffff", {"map": tb.concrete, "paint": 0.035}),
		"concreteSide": t.call("#aeaca4", {"paint": 0.09}),
		"concreteDark": t.call("#9d9b94", {"paint": 0.08}),
		"coping": t.call("#d4d3cb", {"paint": 0.03}),
		"whiteLine": mat.decal("#e9e8e1", {"paint": 0.02}),
		"tactDot": t.call("#ffffff", {"map": tb.tactileDot, "paint": 0.02}),
		"tactLine": t.call("#ffffff", {"map": tb.tactileLine, "paint": 0.02}),
		"tactDotI": t.call("#ffffff", merge.call({"map": tb.tactileDot, "paint": 0.02}, warm.call(0.35, "#3a2c10", true))),
		"tactLineI": t.call("#ffffff", merge.call({"map": tb.tactileLine, "paint": 0.02}, warm.call(0.35, "#3a2c10", true))),
		"paving": t.call("#ffffff", {"map": tb.paving, "paint": 0.03}),
		"stone": t.call("#ffffff", {"map": tb.stoneTile, "paint": 0.03}),
		"rubber": t.call("#ffffff", {"map": tb.rubber, "paint": 0.02}),
		"gravel": t.call("#ffffff", {"map": tb.gravel, "paint": 0.03}),
		"grass": t.call("#ffffff", {"map": tb.grassTex, "paint": 0.05}),
		"soil": t.call("#ffffff", {"map": tb.soil, "paint": 0.04}),
		"streak": mat.decal("#ffffff", {"map": tb.streaks, "opacity": 0.3}),
		"grime": mat.decal("#ffffff", {"map": tb.grime, "opacity": 0.45}),
		"doorMark": mat.decal("#ffffff", {"map": A.misc.tex, "opacity": 0.95}),
		"wood": t.call(C.wood, {"paint": 0.05}), "woodDark": t.call(C.woodDark, {"paint": 0.05}), "woodLight": t.call(C.woodLight, {"paint": 0.05}),
		"benchGreen": t.call("#3f6552", {"paint": 0.03}), "benchBlue": t.call("#4a78a8", {"paint": 0.03}), "benchBrown": t.call("#8a6246", {"paint": 0.05}),
		"benchSlat": t.call("#a97f58", {"paint": 0.06}),
		"shelterCol": t.call("#cfd5d6", {"paint": 0.03}),
		"shelterRoof": t.call("#d9dad4", {"paint": 0.04}),
		"shelterUnder": t.call("#e7e6df", {"paint": 0.02}),
		"shelterFascia": t.call("#e9e6dc", {"paint": 0.02}),
		"pinkBand": t.call(ctx.L.NAMES.lineColor, {"paint": 0.02}),
		"pinkDeep": t.call(ctx.L.NAMES.lineColorDeep, {"paint": 0.02}),
		"navy": t.call("#2b4574", {"paint": 0.02}),
		"fenceWhite": t.call("#e2e3df", {"paint": 0.03}),
		"fenceGreen": t.call("#5a8763", {"paint": 0.03}),
		"wireMesh": mat.foliage("#5a8763", tb.wireMesh, {"paint": 0.0}),
		"equip": t.call("#b9bec0", {"paint": 0.05}),
		"equipDark": t.call("#6f757c", {"paint": 0.04}),
		"signRed": t.call("#cf4a44"), "signYellow": t.call("#efc53c"), "ink": t.call("#3a3346"),
		"mirror": mat.glass({"tint": "#b8cfe0", "opacity": 0.85, "streaks": true}),
		"rubberMat": t.call("#55535a", {"paint": 0.03}),
		"brick": t.call("#b0735c", {"paint": 0.08}),
		"brickLight": t.call("#c48b72", {"paint": 0.08}),
		"shrub": t.call(C.shrub, {"paint": 0.12}), "shrubLight": t.call("#77a16a", {"paint": 0.12}), "shrubDark": t.call("#4f7a52", {"paint": 0.1}),
		"yukiyanagi": t.call("#f1efe7", {"paint": 0.08}),
		"foliage": mat.foliage("#ffffff", A.FOL.tex),
		"tileWall": t.call("#c9cfd0", {"paint": 0.04}),
		"pastelGreen": t.call("#a9c8b0", {"paint": 0.04}),
		"trainCream": t.call(C.trainCream, {"paint": 0.03}),
		"stoneGrey": t.call("#a7a39a", {"paint": 0.1}),
	}
