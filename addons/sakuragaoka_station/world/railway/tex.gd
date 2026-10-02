# railway/tex.js: the corridor's canvas textures and the shared sign atlas. The port draws no canvases,
# so each texture is a sized stand-in with the original's key and tiling, and the atlas keeps the
# original's shelf packing so every sign face gets the UV rectangle it has there.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

const AW := 1024
const AH := 1024
const PAD := 4

var ctx
var ballast
var pc
var wood
var strip
var trough
var slab
var mesh
var weeds
var glow
var atlas
var sign := {}
var atlas_fallbacks := 0
var _shelves: Array = []
var _y_top := 0
var _regions := {}
var _geo_cache := {}


func _init(c) -> void:
	ctx = c
	var tex = ctx.tex
	ballast = tex.draw(512, 512, null, {"key": "rw-ballast", "repeat": [1, 1]})
	pc = tex.draw(256, 64, null, {"key": "rw-pc"})
	wood = tex.draw(256, 64, null, {"key": "rw-wood"})
	strip = tex.draw(1024, 512, null, {"key": "rw-strip2", "repeat": [1, 1]})
	trough = tex.draw(256, 64, null, {"key": "rw-trough", "repeat": [1, 1]})
	slab = tex.draw(256, 128, null, {"key": "rw-slab", "repeat": [1, 1]})
	mesh = tex.draw(128, 128, null, {"key": "rw-mesh2", "repeat": [1, 1]})
	weeds = tex.draw(1024, 512, null, {"key": "rw-weeds"})
	atlas = tex.draw(AW, AH, null, {"key": "rw-sign-atlas"})
	atlas.anisotropy = 8
	sign["emergency"] = region("emergency", 256, 320, 512, 640)
	sign["kiken"] = region("kiken", 336, 252, 512, 384)
	sign["tachiiri"] = region("tachiiri", 336, 252, 512, 384)
	sign["hv"] = region("hv", 160, 120, 256, 192)
	sign["box"] = region("box", 160, 240, 256, 384)
	sign["pm"] = region("pm", 192, 96, 256, 128)


func _alloc(w: int, h: int):
	var w2 := w + PAD * 2
	var h2 := h + PAD * 2
	var best = null
	for s in _shelves:
		if s.h >= h2 and AW - s.x >= w2 and (best == null or s.h < best.h):
			best = s
	if best == null:
		if _y_top + h2 > AH:
			return null
		best = {"y": _y_top, "h": h2, "x": 0}
		_shelves.append(best)
		_y_top += h2
	var r := {"x": best.x + PAD, "y": best.y + PAD, "w": w, "h": h}
	best.x += w2
	return r


func region(key: String, w: int, h: int, dw: int, dh: int) -> Dictionary:
	if _regions.has(key):
		return _regions[key]
	var rc = _alloc(w, h)
	var reg: Dictionary
	if rc == null:
		atlas_fallbacks += 1
		reg = {"map": ctx.tex.draw(dw, dh, null, {"key": "rw-fb|" + key}), "u0": 0.0, "v0": 0.0, "u1": 1.0, "v1": 1.0}
	else:
		reg = {"map": atlas, "u0": (rc.x + 0.5) / AW, "u1": (rc.x + w - 0.5) / AW, "v1": 1.0 - (rc.y + 0.5) / AH, "v0": 1.0 - (rc.y + h - 0.5) / AH}
	_regions[key] = reg
	return reg


func num(txt: String, bg: String = "#f4f2ec", fg: String = "#35303c", sub: String = "") -> Dictionary:
	return region("num|" + txt + "|" + bg + "|" + fg + "|" + sub, 96, 96, 128, 128)


func km(k: int, hm: int) -> Dictionary:
	return region("km|%d|%d" % [k, hm], 80, 120, 128, 192)


func plate(_lines: Array, key: String, w: int = 256, h: int = 128, _opts: Dictionary = {}) -> Dictionary:
	return region("plate|" + key, T.js_round(w * 0.5), T.js_round(h * 0.5), w, h)


func speed(v: int) -> Dictionary:
	return region("speed|%d" % v, 96, 96, 128, 128)


func sign_geo(reg: Dictionary) -> T.Geometry:
	var k: String = ",".join([_js(reg.u0), _js(reg.v0), _js(reg.u1), _js(reg.v1)]) + ("" if reg.map == atlas else reg.map.uuid)
	if _geo_cache.has(k):
		return _geo_cache[k]
	var g := Geo.plane(1, 1)
	var uv: T.Attr = g.attributes.uv
	for i in uv.count():
		uv.set_xy(i, reg.u0 + uv.get_x(i) * (reg.u1 - reg.u0), reg.v0 + uv.get_y(i) * (reg.v1 - reg.v0))
	_geo_cache[k] = g
	return g


func sign_mat(reg: Dictionary):
	return ctx.mat.toon("#ffffff", {"map": reg.map, "paint": 0.02})


## A sign face (facing local +Z) of w x h metres.
func sign_mesh(kit, reg: Dictionary, w: float, h: float, pos, rot = null):
	var m = kit.mesh(sign_geo(reg), sign_mat(reg), pos, rot, [w, h, 1])
	m.cast_shadow = false
	m.receive_shadow = true
	return m


func atlas_fill() -> float:
	return float(_y_top) / AH


static func _js(v: float) -> String:
	return str(v)
