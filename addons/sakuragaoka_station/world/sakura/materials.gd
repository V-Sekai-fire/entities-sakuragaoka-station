# sakura/textures.js and sakura/materials.js: the bark, blossom, flora, ground and speckle canvases
# (sized stand-ins here; the port draws no canvases) and the sakura materials. The original's shader
# patches (sway, banded tone, rim, dappled shadow) are recorded in user_data for the renderer.
extends RefCounted


static func create_textures(ctx) -> Dictionary:
	return {
		"barkOld": ctx.tex.draw(256, 512, null, {"key": "sakura-bark-old", "repeat": [1, 1]}),
		"barkYoung": ctx.tex.draw(128, 256, null, {"key": "sakura-bark-young", "repeat": [1, 1]}),
		"blossom": ctx.tex.draw(1024, 1024, null, {"key": "sakura-blossom-atlas"}),
		"flora": ctx.tex.draw(512, 512, null, {"key": "sakura-flora-atlas"}),
		"ground": ctx.tex.draw(512, 256, null, {"key": "sakura-ground-atlas"}),
		"speck": ctx.tex.draw(512, 512, null, {"key": "sakura-speck4", "repeat": [1, 1]}),
	}


static func _extend(m, o: Dictionary):
	m.user_data["sakura"] = o
	return m


static func create_materials(ctx, TX: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var M := {}
	M["barkOld"] = mat.toon("#ffffff", {"map": TX.barkOld, "paint": 0.07, "name": "sakura:barkOld"})
	M["barkYoung"] = mat.toon("#ffffff", {"map": TX.barkYoung, "paint": 0.06, "name": "sakura:barkYoung"})
	M["blob"] = _extend(mat.toon("#ffffff", {"vertexColors": true, "paint": 0.05, "name": "sakura:blob"}),
		{"key": "sakura-mass1", "rim": 0.7, "sheen": 0.0, "speck": TX.speck, "speckK": 0.7, "octNormal": true, "band": true, "envRim": true, "shade": 0.28})
	M["blobDepth"] = {"type": "depth", "dapple": true}
	M["cards"] = _extend(mat.toon("#ffffff", {"map": TX.blossom, "alphaTest": 0.5, "side": "double", "vertexColors": true, "paint": 0.04, "name": "sakura:cards"}),
		{"key": "sakura-cards3", "rim": 1.0, "sheen": 0.05, "sway": true, "noFlip": true, "shade": 0.22, "edgeFade": true})
	# ground plants: double sided, normals point up so both faces read like the lit ground
	M["flora"] = _extend(mat.toon("#ffffff", {"map": TX.flora, "alphaTest": 0.5, "side": "double", "vertexColors": true, "paint": 0.05, "name": "sakura:flora"}),
		{"key": "sakura-flora", "noFlip": true})
	M["ground"] = mat.toon("#ffffff", {"map": TX.ground, "alphaTest": 0.45, "vertexColors": true, "polygonOffset": -2, "paint": 0.05, "name": "sakura:ground"})
	M["curb"] = mat.toon("#cbc7bd", {"paint": 0.09, "name": "sakura:curb"})
	M["curbDark"] = mat.toon("#b3afa5", {"paint": 0.09, "name": "sakura:curbDark"})
	M["stone"] = mat.toon("#ffffff", {"vertexColors": true, "paint": 0.1, "name": "sakura:stone"})
	M["soil"] = mat.toon("#8a7157", {"paint": 0.1, "name": "sakura:soil"})
	M["rope"] = mat.toon("#e3d6b2", {"paint": 0.05, "name": "sakura:rope"})
	M["paper"] = mat.toon("#f4f1ea", {"paint": 0.02, "side": "double", "name": "sakura:paper"})
	M["wood"] = mat.toon(ctx.palette.wood, {"paint": 0.08, "name": "sakura:wood"})
	return M
