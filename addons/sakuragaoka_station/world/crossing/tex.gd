# crossing/tex.js: the level crossing's canvas textures. The port draws no canvases, so each texture is
# a sized stand-in under the original's key, and the two atlases keep the original's shelf packing so
# every sign and road symbol gets the UV rectangle (rect[name] = [u0, v0, u1, v1]) it has there.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const INK := "#3a3346"
const HAZ_YELLOW := "#f0c23a"

const SIGN_ITEMS := [["buckA", 256, 40], ["buckB", 256, 40], ["namePlate", 384, 300], ["emergency", 224, 320], ["tomareMiyo", 192, 256],
	["chui", 256, 160], ["kinshi", 256, 160], ["cabinet", 256, 400], ["relay", 192, 288], ["grille", 64, 64]]
const ROAD_ITEMS := [["tactile", 192, 128], ["tomare", 512, 512], ["tomareSmall", 256, 128], ["feet", 128, 128], ["chevron", 128, 128], ["navi", 128, 256]]

var ctx
var machStripe
var rubber
var asphalt
var concrete
var worn
var guide
var mesh
var grass
var signAtlas
var roadAtlas
var rect := {}


func _init(c) -> void:
	ctx = c
	var tex = ctx.tex
	machStripe = tex.draw(128, 128, null, {"key": "crossing.machStripe", "repeat": [1, 2.4]})
	rubber = tex.draw(256, 256, null, {"key": "crossing.rubber"})
	asphalt = tex.draw(512, 512, null, {"key": "crossing.asphalt", "repeat": [1, 1]})
	concrete = tex.draw(256, 256, null, {"key": "crossing.concrete", "repeat": [1, 1]})
	worn = tex.draw(256, 128, null, {"key": "crossing.worn", "repeat": [1, 1]})
	guide = tex.draw(64, 64, null, {"key": "crossing.guide", "repeat": [1, 1]})
	mesh = tex.draw(64, 64, null, {"key": "crossing.mesh", "repeat": [1, 1]})
	grass = tex.draw(128, 128, null, {"key": "crossing.grass"})
	signAtlas = _pack(SIGN_ITEMS, "crossing.signAtlas")
	roadAtlas = _pack(ROAD_ITEMS, "crossing.roadAtlas")


func postStripe(v_repeat: float):
	return ctx.tex.draw(128, 128, null, {"key": "crossing.postStripe.%.2f" % v_repeat, "repeat": [1, v_repeat]})


func _pack(list: Array, key: String):
	var S := 1024
	var PAD := 6
	var items := []
	for it in list:
		items.append({"name": it[0], "w": it[1], "h": it[2]})
	items = T.stable_sort(items, func(a, b): return (b.h - a.h) if b.h != a.h else (b.w - a.w))
	var x := 0
	var y := 0
	var shelf_h := 0
	for it in items:
		if x + it.w > S:
			x = 0
			y += shelf_h + PAD
			shelf_h = 0
		it["x"] = x
		it["y"] = y
		x += it.w + PAD
		shelf_h = maxi(shelf_h, it.h)
	var H := int(ceilf((y + shelf_h) / 64.0)) * 64
	var t = ctx.tex.draw(S, H, null, {"key": key})
	var e := 0.5
	for it in items:
		rect[it.name] = [(it.x + e) / S, 1.0 - (it.y + it.h - e) / H, (it.x + it.w - e) / S, 1.0 - (it.y + e) / H]
	return t
