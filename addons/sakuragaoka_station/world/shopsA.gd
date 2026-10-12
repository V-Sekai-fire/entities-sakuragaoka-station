# shopsA.js: konbini HIDAMARI MART (W1), flower shop HANANOWA (W2), KOMOREBI books (W4) and cafe
# HARUIRO (E1). Each shop is built in its lot-local frame (L.lotFrame): +Z faces the street,
# x in [-w/2, w/2], z in [-14, 0]. Publishes ctx.services.shopsA = {cafeWindow: {x, y, z, rotY, w, h},
# cafeTables: [{x, z, y}]}.
extends RefCounted

const Common = preload("res://addons/sakuragaoka_station/world/shopsA/common.gd")
const Goods = preload("res://addons/sakuragaoka_station/world/shopsA/goods.gd")
const Konbini = preload("res://addons/sakuragaoka_station/world/shopsA/konbini.gd")

## The original imports these lazily and skips any that are missing.
const OPTIONAL := [
	["cafe", "res://addons/sakuragaoka_station/world/shopsA/cafe.gd", "build_cafe"],
	["flower", "res://addons/sakuragaoka_station/world/shopsA/flower.gd", "build_flower"],
	["books", "res://addons/sakuragaoka_station/world/shopsA/books.gd", "build_books"],
]


func build(ctx):
	var C := Common.new(ctx)
	C.G = Goods.new(ctx, C)  # instanced shop goods (products, books, cups, flowers, tiles...)
	var out := {}
	Konbini.build_konbini(ctx, C)
	for e in OPTIONAL:
		if not ResourceLoader.exists(e[1]):
			continue
		var mod = load(e[1])
		out[e[0]] = mod.call(e[2], ctx, C)
	C.scatter.build()
	C.G.build()
	for a in ["lit", "glow", "cut", "inner"]:
		C.A[a].finalize()

	var L = ctx.L
	var f: Dictionary = L.lot_frame(L.lot_by_id("E1"))
	var cafe: Dictionary = out.get("cafe", {})
	ctx.services["shopsA"] = {
		"cafeWindow": cafe.cafeWindow if cafe.get("cafeWindow") != null else {"x": f.x + 3.8, "y": f.y + 1.8, "z": f.z + 1.5, "rotY": f.rotY, "w": 6.8, "h": 1.9},
		"cafeTables": cafe.cafeTables if cafe.get("cafeTables") != null else [],
	}
	return null
