# src/core/materials.js: the toon material library. Identical requests return the same material,
# keyed like the original (colour plus the options in the order given), so static batching works.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const LAYER_NO_OUTLINE := 1

const PALETTE := {
	"sakuraWhite": "#fbe9ef", "sakuraPale": "#f7d3de", "sakura": "#f2b5c8", "sakuraMid": "#eb9db6", "sakuraDeep": "#dd7f9d", "sakuraShadow": "#c3aecb",
	"skyTop": "#5f9bdc", "skyMid": "#9cc4ea", "skyHorizon": "#dde9f3",
	"cream": "#f4efe4", "offWhite": "#efe9dc", "beige": "#e3d4b8", "plaster": "#e8dcc6", "paleBlue": "#b7cddb", "paleGreen": "#cfe0c8", "paleYellow": "#f1e3b0",
	"lightGrayTile": "#cdd0cd", "concrete": "#bdbcb5", "concreteDark": "#9d9c96", "platform": "#c6c5be",
	"asphalt": "#6c6e73", "asphaltDark": "#5c5e63", "asphaltLight": "#7d7f83",
	"lineWhite": "#eeece6", "lineOrange": "#e9a23b", "lineYellow": "#e8c547",
	"woodDark": "#5a4032", "wood": "#8a6446", "woodLight": "#b48a62",
	"roofDark": "#4a4f58", "roofBlue": "#56677a", "roofGreen": "#4d6457", "roofBrown": "#6a5448", "metalRoof": "#7b8691",
	"frameDark": "#4b4d52", "frameBrown": "#5e4636", "steel": "#9aa1a8", "steelDark": "#6d747c", "rust": "#8a5a44",
	"ballast": "#7c7a76", "ballastDark": "#65625e", "ballastWarm": "#8d8378", "sleeper": "#6b5a4c", "railSide": "#6e625a", "railTop": "#d9dde2",
	"grass": "#8fb86f", "grassDark": "#6f9a5a", "grassLight": "#b3cf83", "leafYoung": "#c9d98e", "shrub": "#5f8c5c", "moss": "#7d9460", "soil": "#9b8367",
	"signBlue": "#2f64b5", "signRed": "#d9463b", "signYellow": "#f2c230", "signGreen": "#3f8f5b",
	"trainCream": "#f5f0e6", "trainPink": "#ef9fbe", "trainMint": "#8fd1c1", "trainGray": "#8e959d",
	"lampWarm": "#ffd9a0", "lampCool": "#e8f4ff",
	"ink": "#3a3346",
}

var cache := {}
var shared: Dictionary
var palette := PALETTE


func _init(sh: Dictionary = {}) -> void:
	shared = sh


func color(c) -> Color:
	return T.color(c)


static func _key(opts: Dictionary) -> String:
	var parts := []
	for k in opts:
		var v = opts[k]
		if v is T.Tex:
			v = "tex:" + v.uuid
		elif v is Color:
			v = T.hex_string(v)
		parts.append("%s=%s" % [k, str(v)])
	return ",".join(parts)


func _side(s) -> String:
	return "double" if s == "double" else ("back" if s == "back" else "front")


## The cel-shaded material. opts: map, alphaMap, alphaTest, transparent, opacity, side,
## vertexColors, emissive, emissiveIntensity, paint, grime, polygonOffset, depthWrite, name.
func toon(c = "#ffffff", opts: Dictionary = {}) -> T.Mat:
	var col := T.color(c)
	var key := "toon|" + T.hex_string(col) + "|" + _key(opts)
	if cache.has(key):
		return cache[key]
	var m := T.Mat.new()
	m.type = "toon"
	m.key = key
	m.opts = opts.duplicate()
	m.color = col
	m.map = opts.get("map")
	m.alpha_map = opts.get("alphaMap")
	m.alpha_test = opts.get("alphaTest", 0.0)
	m.transparent = bool(opts.get("transparent", false))
	m.opacity = opts.get("opacity", 1.0)
	m.vertex_colors = bool(opts.get("vertexColors", false))
	m.emissive = T.color(opts.emissive) if opts.get("emissive") else Color(0, 0, 0)
	m.emissive_intensity = opts.get("emissiveIntensity", 1.0)
	m.side = _side(opts.get("side", "front"))
	m.depth_write = opts.get("depthWrite", true)
	m.name = opts.get("name", "")
	m.polygonOffset = opts.get("polygonOffset", 0)
	m.user_data["toon"] = {"paint": opts.get("paint", 0.05), "grime": opts.get("grime", 0.0), "polygonOffset": opts.get("polygonOffset", 0)}
	cache[key] = m
	return m


## A decal on a surface (road markings, posters): pulled toward the camera, no depth write.
func decal(c = "#ffffff", opts: Dictionary = {}) -> T.Mat:
	var o := {"transparent": true if (opts.get("map") or opts.get("alphaMap")) else bool(opts.get("transparent", false)),
		"depthWrite": false, "polygonOffset": -2, "paint": 0.02}
	o.merge(opts, true)
	return toon(c, o)


## Unlit / self-lit (screens, lamps, lit signs). intensity > 1 blooms.
func emissive(c = "#ffffff", intensity: float = 1.6, opts: Dictionary = {}) -> T.Mat:
	var col := T.color(c)
	var key := "emi|" + T.hex_string(col) + "|" + str(intensity) + "|" + _key(opts)
	if cache.has(key):
		return cache[key]
	var m := T.Mat.new()
	m.type = "basic"
	m.key = key
	m.color = Color(col.r * intensity, col.g * intensity, col.b * intensity)
	m.map = opts.get("map")
	m.transparent = bool(opts.get("transparent", false))
	m.opacity = opts.get("opacity", 1.0)
	m.alpha_test = opts.get("alphaTest", 0.0)
	m.side = "double" if opts.get("side") == "double" else "front"
	m.depth_write = opts.get("depthWrite", true)
	m.toneMapped = false
	cache[key] = m
	return m


## Anime glass: sky reflection, fresnel, highlight streaks. opts: tint, opacity, streaks, frost.
func glass(opts: Dictionary = {}) -> T.Mat:
	var key := "glass|" + _key(opts)
	if cache.has(key):
		return cache[key]
	var m := T.Mat.new()
	m.type = "glass"
	m.key = key
	m.color = T.color(opts.get("tint", "#9fb6c8"))
	m.opacity = opts.get("opacity", 0.42)
	m.transparent = true
	m.depth_write = false
	m.side = "double"
	m.frost = bool(opts.get("frost", false))
	m.streaks = opts.get("streaks", true) != false
	cache[key] = m
	return m


## Vegetation cards and cut-outs: alpha tested, double sided.
func foliage(c = "#ffffff", map = null, opts: Dictionary = {}) -> T.Mat:
	var o := {"map": map, "alphaTest": 0.5, "side": "double", "paint": 0.04}
	o.merge(opts, true)
	return toon(c, o)


## A ShaderMaterial the original builds by hand (water, distant hills, the blossom pads): kept as
## its base colour and flags, since the port renders it with the same toon shader.
func shader(kind: String, c = "#ffffff", opts: Dictionary = {}) -> T.Mat:
	var key := "shader|" + kind + "|" + T.hex_string(T.color(c)) + "|" + _key(opts)
	if cache.has(key):
		return cache[key]
	var m := T.Mat.new()
	m.type = "shader"
	m.key = key
	m.color = T.color(c)
	m.vertex_colors = bool(opts.get("vertexColors", false))
	m.transparent = bool(opts.get("transparent", false))
	m.side = _side(opts.get("side", "front"))
	m.depth_write = opts.get("depthWrite", true)
	m.alpha_test = opts.get("alphaTest", 0.0)
	m.shader_kind = kind
	cache[key] = m
	return m
