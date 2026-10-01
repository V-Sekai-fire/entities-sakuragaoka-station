# environment/shaders.js: the distant-hill and water ShaderMaterials and the swaying foliage cards.
# The distant hills render with distant.gdshader through material(); water still renders with the toon
# shader, keeping its colour and flags. Like the original, every distant / water material is a new one.
extends RefCounted

const DISTANT := preload("res://addons/sakuragaoka_station/world/environment/distant.gdshader")
const DISTANT_DEFAULTS := {
	"litK": 1.0, "midK": 0.87, "shadeK": 0.74, "shadeTint": "#b4b8e2",
	"haze": "#c9d7ea", "hazeMin": 0.0, "hazeMax": 0.92, "hazeK": 0.0012,
	"mist": "#e2eaf3", "mistY0": 0.0, "mistY1": 30.0, "mistAmt": 0.5,
	"pink": "#efc3d2", "pinkAmt": 0.0, "young": "#b4cf86", "youngAmt": 0.0, "dark": "#5d7b66", "darkAmt": 0.0,
	"crown": 9.0, "crownAmt": 0.0, "patch": 70.0, "arc": false, "wrap": 1e6,
	"fogMul": 0.35, "rim": 0.0,
}

const FLOATS := {
	"litK": "lit_k", "midK": "mid_k", "shadeK": "shade_k", "hazeMin": "haze_min", "hazeMax": "haze_max",
	"hazeK": "haze_k", "mistY0": "mist_y0", "mistY1": "mist_y1", "mistAmt": "mist_amt", "pinkAmt": "pink_amt",
	"youngAmt": "young_amt", "darkAmt": "dark_amt", "crown": "crown", "crownAmt": "crown_amt", "wrap": "wrap",
	"fogMul": "fog_mul", "rim": "rim",
}
const COLOURS := {"shadeTint": "shade_tint", "haze": "haze", "mist": "mist", "pink": "pink", "young": "young", "dark": "dark"}

static var _serial := 0


static func distant_material(ctx, o: Dictionary = {}):
	_serial += 1
	var m = ctx.mat.shader("distant#%d" % _serial, "#ffffff", {"vertexColors": bool(o.get("vertexColors", false))})
	m.name = "env-distant"
	var opts := DISTANT_DEFAULTS.duplicate()
	opts.merge(o, true)
	opts["sunDir"] = ctx.sun_dir
	m.user_data["distant"] = opts
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


## The Godot material for one of this module's ShaderMaterials, reading its base colour from the
## palette by UV as MToon does, or null where the toon shader still stands in.
static func material(m, palette: Texture2D) -> ShaderMaterial:
	var o: Dictionary = m.user_data.get("distant", {})
	if o.is_empty():
		return null
	var sm := ShaderMaterial.new()
	sm.shader = DISTANT
	sm.set_shader_parameter("palette", palette)
	sm.set_shader_parameter("sun_dir", o.sunDir)
	for k in FLOATS:
		sm.set_shader_parameter(FLOATS[k], float(o[k]))
	for k in COLOURS:
		sm.set_shader_parameter(COLOURS[k], Color(o[k]))
	sm.set_shader_parameter("patch_scale", 1.0 / float(o.patch))
	sm.set_shader_parameter("arc", bool(o.arc))
	sm.set_shader_parameter("fog_colour", Color("#cfdcec"))
	sm.set_shader_parameter("fog_density", 0.0026)
	return sm
