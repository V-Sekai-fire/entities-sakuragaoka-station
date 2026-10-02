# vehicles/atlas.js: one 1024 px canvas atlas for every textured bit of the vehicles module (number
# plates, liveries, stickers, price tags, spokes, basket mesh, hubcaps) and the shared materials.
# The port draws no canvases, so the atlas is a sized stand-in under the original's key.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const S := 1024
## Regions in canvas pixels [x, y, w, h].
const R := {
	"plVan": [0, 0, 256, 128], "plKei": [256, 0, 256, 128], "plTaxi": [512, 0, 256, 128], "plCar": [768, 0, 256, 128],
	"taxiDoor": [0, 128, 512, 128], "vanSide": [512, 128, 512, 128],
	"andon": [0, 256, 256, 128], "kusha": [256, 256, 128, 64], "kinen": [256, 320, 128, 64],
	"tag1": [384, 256, 128, 128], "tag2": [512, 256, 128, 128], "tag3": [640, 256, 128, 128],
	"beginner": [768, 256, 64, 64], "emblem": [832, 256, 64, 64], "seibi": [896, 256, 128, 64],
	"reg": [768, 320, 128, 64], "park": [896, 320, 128, 64],
	"brandW1": [0, 384, 256, 64], "brandD1": [256, 384, 256, 64], "brandW2": [512, 384, 256, 64], "brandD2": [768, 384, 256, 64],
	"brandW3": [0, 448, 256, 64], "brandD3": [256, 448, 256, 64], "taxiRear": [512, 448, 256, 64], "vanRear": [768, 448, 256, 64],
	"basket": [0, 512, 256, 256], "capTaxi": [256, 512, 128, 128], "capCover": [384, 512, 128, 128],
	"capSteel": [256, 640, 128, 128], "capCompact": [384, 640, 128, 128],
	"spokes": [512, 512, 512, 512],
	"grille": [0, 768, 256, 128], "vanGrille": [256, 768, 256, 128], "lace": [0, 896, 256, 128],
	"bag": [256, 896, 128, 128], "charm": [384, 896, 64, 64], "sakuraMark": [448, 896, 64, 64],
}

static var _atlas_for = null
static var _atlas = null
static var _mats_for = null
static var _mats = null


## Remaps a geometry's 0..1 uv attribute into atlas region r (optionally its sub-rect u0, v0, u1, v1).
static func uv_into(r: Array, sub = null) -> Callable:
	var u0 := float(r[0]) / S
	var u1 := float(r[0] + r[2]) / S
	var v1 := 1.0 - float(r[1]) / S
	var v0 := 1.0 - float(r[1] + r[3]) / S
	var sb: Array = sub if sub != null else [0, 0, 1, 1]
	return func(uv: T.Attr) -> void:
		for i in uv.count():
			var u: float = sb[0] + (sb[2] - sb[0]) * uv.get_x(i)
			var v: float = sb[1] + (sb[3] - sb[1]) * uv.get_y(i)
			uv.set_xy(i, u0 + (u1 - u0) * u, v0 + (v1 - v0) * v)


static func get_atlas(ctx) -> Dictionary:
	if _atlas != null and _atlas_for == ctx:
		return _atlas
	var tex = ctx.tex.draw(S, S, null, {"key": "vehicles-atlas"})
	tex.anisotropy = 8
	_atlas = {"tex": tex, "R": R}
	_atlas_for = ctx
	return _atlas


static func get_mats(ctx) -> Dictionary:
	if _mats != null and _mats_for == ctx:
		return _mats
	var A := get_atlas(ctx)
	var m = ctx.mat
	_mats = {
		"vcol": m.toon("#ffffff", {"vertexColors": true, "paint": 0.035}),
		"atlas": m.toon("#ffffff", {"map": A.tex, "vertexColors": true, "alphaTest": 0.4, "side": "double", "paint": 0.0}),
		"glass": m.glass({"tint": "#8ea4b6", "opacity": 0.46}),
		"lit": m.emissive("#ffffff", 1.25, {"map": A.tex}),
		"brake": m.emissive("#ff5a48", 1.35),
	}
	_mats_for = ctx
	return _mats
