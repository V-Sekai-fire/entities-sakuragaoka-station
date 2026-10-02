# houses/tex.js: the module's canvas textures and atlases, and its materials. The port draws no
# canvases: each texture is a keyed stand-in, and the atlases keep the original's packed rects.
extends RefCounted

const SURNAMES := ["佐藤", "鈴木", "高橋", "田中", "渡辺", "伊藤", "山本", "中村", "小林", "加藤", "吉田", "山田", "佐々木", "山口", "松本", "井上",
	"木村", "清水", "山崎", "森", "池田", "橋本", "阿部", "石川", "前田", "藤田", "小川", "岡田", "後藤", "長谷川", "村上", "近藤", "坂本", "遠藤", "青木", "西村",
	"福田", "太田", "三浦", "藤原", "岡本", "中川", "原田", "小野", "田村", "竹内", "和田", "中山", "石田", "上田", "森田", "柴田", "宮本", "内田", "桜井", "野口"]


static func make_house_textures(ctx) -> Dictionary:
	var T = ctx.tex
	var tex := {}
	var rep := func(key: String, w: int, h: int): return T.draw(w, h, null, {"key": "houses_" + key, "repeat": [1, 1]})
	tex.plaster = rep.call("plaster", 256, 256)
	tex.siding = rep.call("siding", 256, 256)
	tex.tile = rep.call("tile", 256, 256)
	tex.wood = rep.call("wood", 256, 256)
	tex.block = T.draw(256, 128, null, {"key": "houses_block", "repeat": [1, 1]})
	tex.concrete = rep.call("concrete", 256, 256)
	tex.kawara = T.draw(256, 256, null, {"key": "houses_kawara", "repeat": [1, 1]})
	tex.kawaraEdge = T.draw(64, 32, null, {"key": "houses_kawaraEdge", "repeat": [1, 1]})
	tex.ridge = T.draw(128, 64, null, {"key": "houses_ridge", "repeat": [1, 1]})
	tex.metal = T.draw(128, 128, null, {"key": "houses_metal", "repeat": [1, 1]})
	tex.shutter = T.draw(64, 128, null, {"key": "houses_shutter", "repeat": [1, 1]})
	tex.gravel = rep.call("gravel", 256, 256)
	tex.asphalt = rep.call("asphalt", 256, 256)
	tex.lawn = rep.call("lawn", 256, 256)
	tex.soil = rep.call("soil", 128, 128)
	tex.paver = T.draw(128, 128, null, {"key": "houses_paver", "repeat": [1, 1]})
	tex.atlas = _make_atlas(ctx)
	tex.laundry = _make_laundry_atlas(ctx)
	tex.decal = _make_decal_atlas(ctx)
	tex.far = T.draw(128, 128, null, {"key": "houses_far", "repeat": [1, 1]})
	return tex


## The 1024 px shelf-packed atlas: the item sizes in the original's order, packed tallest first.
static func _make_atlas(ctx) -> Dictionary:
	var W := 1024
	var H := 1024
	var PAD := 3
	var items := []
	var add := func(name: String, w: int, h: int): items.append({"name": name, "w": w, "h": h, "i": items.size()})
	add.call("white", 16, 16)
	for n in ["door_wood", "door_white", "door_grey", "door_steel"]:
		add.call(n, 112, 240)
	add.call("door_slide", 256, 240)
	add.call("gate_alu", 128, 96)
	for n in ["int_lace", "int_curtain_pink", "int_curtain_green", "int_curtain_blue", "int_blind", "int_shoji", "int_dark", "int_frost", "int_louver", "int_room", "int_warm"]:
		add.call(n, 128, 128)
	for i in 24:
		if i % 3 == 1:
			add.call("plateV%d" % i, 44, 112)
		else:
			add.call("plateH%d" % i, 112, 44)
	for i in 6:
		add.call("addr%d" % i, 96, 40)
	add.call("ac_front", 128, 88)
	add.call("gas_meter", 64, 72)
	add.call("elec_meter", 56, 80)
	add.call("intercom", 40, 64)
	for n in ["mailbox", "mailbox_red", "mailbox_dark"]:
		add.call(n, 96, 72)
	add.call("milk", 72, 56)
	add.call("parcel_box", 96, 64)
	add.call("cardboard", 96, 64)
	for n in ["bin_burn", "bin_res", "bin_pla"]:
		add.call(n, 96, 40)
	add.call("gomi_sign", 160, 96)
	add.call("sticker_dog", 64, 40)
	add.call("sticker_nosale", 72, 32)
	add.call("vent", 64, 24)
	add.call("shed_door", 256, 160)
	add.call("apt_sign", 256, 64)
	for n in [101, 102, 103, 104, 201, 202, 203, 204]:
		add.call("room%d" % n, 48, 24)
	add.call("posts", 192, 96)
	add.call("hose", 64, 64)
	for n in ["futon_a", "futon_b", "futon_c"]:
		add.call(n, 128, 96)
	add.call("solar", 128, 64)
	add.call("kotatsu_sign", 128, 48)
	add.call("greenhouse", 128, 64)
	var order := items.duplicate()
	order.sort_custom(func(a, b):
		if a.h != b.h:
			return a.h > b.h
		if a.w != b.w:
			return a.w > b.w
		return a.i < b.i)
	var x := 0
	var y := 0
	var row_h := 0
	var rects := {}
	for it in order:
		if x + it.w + PAD > W:
			x = 0
			y += row_h + PAD
			row_h = 0
		var ix := x
		var iy := y
		x += it.w + PAD
		row_h = maxi(row_h, it.h)
		var e := 0.5
		rects[it.name] = [(ix + e) / W, 1.0 - (iy + it.h - e) / H, (ix + it.w - e) / W, 1.0 - (iy + e) / H]
	var texture = ctx.tex.draw(W, H, null, {"key": "houses_atlas"})
	var wr: Array = rects.white
	return {"texture": texture, "rects": rects, "white": [(wr[0] + wr[2]) / 2.0, (wr[1] + wr[3]) / 2.0]}


static func _make_laundry_atlas(ctx) -> Dictionary:
	var W := 1024.0
	var H := 512.0
	var items := [["shirt", 0, 0, 160, 200], ["sailor", 160, 0, 160, 200], ["tee", 320, 0, 160, 160], ["gym", 480, 0, 160, 160],
		["towel", 640, 0, 128, 200], ["sheet", 768, 0, 256, 256], ["pinch", 0, 256, 256, 200], ["skirt", 256, 256, 144, 176],
		["tanzaku", 400, 256, 40, 140], ["carp_black", 440, 256, 256, 64], ["carp_red", 440, 324, 256, 64], ["carp_blue", 440, 392, 256, 64],
		["fukinagashi", 700, 256, 256, 64]]
	var rects := {}
	for it in items:
		var e := 1.0
		rects[it[0]] = [(it[1] + e) / W, 1.0 - (it[2] + it[4] - e) / H, (it[1] + it[3] - e) / W, 1.0 - (it[2] + e) / H]
	return {"texture": ctx.tex.draw(int(W), int(H), null, {"key": "houses_laundry"}), "rects": rects}


static func _make_decal_atlas(ctx) -> Dictionary:
	var W := 512.0
	var H := 256.0
	var items := [["streak", 0, 0, 128, 256], ["moss", 128, 0, 256, 64], ["crack", 128, 64, 128, 128], ["stain", 256, 64, 128, 128],
		["mesh", 384, 64, 128, 128], ["dirt", 384, 0, 128, 64]]
	var rects := {}
	for it in items:
		var e := 1.0
		rects[it[0]] = [(it[1] + e) / W, 1.0 - (it[2] + it[4] - e) / H, (it[1] + it[3] - e) / W, 1.0 - (it[2] + e) / H]
	return {"texture": ctx.tex.draw(int(W), int(H), null, {"key": "houses_decal"}), "rects": rects}


## Vertex-coloured materials, so few materials serve every colour.
static func make_house_materials(ctx, tex: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var vc := func(map, extra: Dictionary = {}):
		var o := {"vertexColors": true, "map": map, "paint": 0.05}
		o.merge(extra, true)
		return mat.toon("#ffffff", o)
	return {
		"plain": vc.call(null, {"paint": 0.05}),
		"plainLow": vc.call(null, {"paint": 0.02}),
		"plaster": vc.call(tex.plaster, {"paint": 0.06}),
		"siding": vc.call(tex.siding, {"paint": 0.04}),
		"tile": vc.call(tex.tile, {"paint": 0.04}),
		"wood": vc.call(tex.wood, {"paint": 0.05}),
		"block": vc.call(tex.block, {"paint": 0.06}),
		"concrete": vc.call(tex.concrete, {"paint": 0.06}),
		"kawara": vc.call(tex.kawara, {"paint": 0.05}),
		"kawaraEdge": vc.call(tex.kawaraEdge, {"paint": 0.03}),
		"ridge": vc.call(tex.ridge, {"paint": 0.04}),
		"metal": vc.call(tex.metal, {"paint": 0.04}),
		"shutter": vc.call(tex.shutter, {"paint": 0.03}),
		"gravel": vc.call(tex.gravel, {"paint": 0.05}),
		"asphalt": vc.call(tex.asphalt, {"paint": 0.06}),
		"lawn": vc.call(tex.lawn, {"paint": 0.08}),
		"soil": vc.call(tex.soil, {"paint": 0.06}),
		"paver": vc.call(tex.paver, {"paint": 0.04}),
		"atlas": vc.call(tex.atlas.texture, {"paint": 0.02}),
		"atlasCut": mat.toon("#ffffff", {"vertexColors": true, "map": tex.atlas.texture, "alphaTest": 0.5, "side": "double", "paint": 0.02}),
		"decal": mat.decal("#ffffff", {"map": tex.decal.texture, "vertexColors": true, "transparent": true}),
		"glass": mat.glass({"tint": "#8fa6bb", "opacity": 0.38}),
		"frost": mat.glass({"tint": "#b9c4cc", "opacity": 0.5, "frost": true, "streaks": false}),
		"poly": mat.toon("#dfe6ea", {"transparent": true, "opacity": 0.55, "side": "double", "depthWrite": false, "paint": 0.0}),
		"lamp": mat.emissive("#ffd9a0", 1.25),
		"lampDim": mat.emissive("#ffe2b8", 0.95),
		"farWall": mat.toon("#ffffff", {"map": tex.far, "paint": 0.04}),
		"farPlain": mat.toon("#ffffff", {"paint": 0.04}),
	}
