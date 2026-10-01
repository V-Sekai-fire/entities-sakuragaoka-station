# environment/shaders.js: the distant-hill and water ShaderMaterials and the swaying foliage cards.
# The port renders them with the toon shader, so each keeps its colour and flags; like the original,
# every distant / water material is a new one (none is shared).
extends RefCounted

static var _serial := 0


static func distant_material(ctx, o: Dictionary = {}):
	_serial += 1
	var m = ctx.mat.shader("distant#%d" % _serial, "#ffffff", {"vertexColors": bool(o.get("vertexColors", false))})
	m.name = "env-distant"
	return m


static func water_material(ctx, o: Dictionary = {}):
	_serial += 1
	var m = ctx.mat.shader("water#%d" % _serial, o.get("mid", "#6fa6b5"), {})
	m.name = "env-water"
	return m


static func sway_foliage(ctx, map, _cell_scale, name: String, o: Dictionary = {}):
	var m = ctx.mat.foliage("#ffffff", map, {"name": "env-sway-" + name, "paint": o.get("paint", 0.03), "alphaTest": o.get("alphaTest", 0.5)})
	m.user_data["envSway"] = true
	return m
