# plaza/textures.js: the plaza's canvas textures. The port draws no canvases, so each is a sized
# stand-in with the original's key and tiling (repeat = 1 / its real-world size in metres).
extends RefCounted

## [name, width, height, key, repeat or null]
const TEXTURES := [
	["tiles", 1024, 1024, "plaza-tiles", [1 / 5.0, 1 / 5.0]],
	["granite", 512, 256, "plaza-granite", [1 / 2.4, 1 / 1.2]],
	["curb", 256, 128, "plaza-curb", [1 / 0.6, 1 / 0.3]],
	["circle", 1024, 256, "plaza-circle", null],
	["brick", 512, 256, "plaza-brick", [1 / 1.1, 1 / 0.45]],
	["concrete", 256, 256, "plaza-concrete", [1.0, 1.0]],
	["wood", 256, 128, "plaza-wood", [1 / 1.2, 1 / 0.3]],
	["soil", 256, 256, "plaza-soil", [1.0, 1.0]],
	["leafy", 256, 256, "plaza-leafy", [1.0, 1.0]],
	["azalea", 256, 256, "plaza-azalea", [1.0, 1.0]],
	["tacDots", 128, 128, "plaza-tactile-dots", [1 / 0.3, 1 / 0.3]],
	["tacBarsV", 128, 128, "plaza-tactile-barsV", [1 / 0.3, 1 / 0.3]],
	["tacBarsU", 128, 128, "plaza-tactile-barsU", [1 / 0.3, 1 / 0.3]],
	["inlay", 1024, 1024, "plaza-inlay", null],
	["dust", 256, 256, "plaza-dust", null],
	["moss", 128, 128, "plaza-moss", null],
	["grass", 256, 256, "plaza-grass", null],
	["daisy", 128, 128, "plaza-daisy", null],
	["pansy", 128, 128, "plaza-pansy", null],
	["tinyFlower", 128, 128, "plaza-tiny", null],
	["dandelion", 128, 128, "plaza-dandelion", null],
	["leafClump", 256, 256, "plaza-leafclump", null],
	["rosette", 128, 128, "plaza-rosette", null],
]


static func make_textures(ctx) -> Dictionary:
	var out := {}
	for t in TEXTURES:
		var opts := {"key": t[3]}
		if t[4] != null:
			opts["repeat"] = t[4]
		out[t[0]] = ctx.tex.draw(t[1], t[2], null, opts)
	out.circle.wrap_s = "repeat"
	return out
