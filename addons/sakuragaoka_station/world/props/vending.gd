# props/vending.js: vending machines at every L.VENDING spot (+ recycle bins, crates, a nobori flag,
# the さくらぽん sticker). Machine local frame: front = +Z, footprint 1.0 (x) x 0.75 (z) x 1.83 (y),
# origin at the footprint centre on the floor.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const C = preload("res://addons/sakuragaoka_station/world/props/common.gd")
const VT = preload("res://addons/sakuragaoka_station/world/props/vendtex.gd")

static var SLOT_X: Array = _slot_x()
const RAIL_Y := [1.35, 1.09, 0.855]  # bottom of the price rail of each row (top row first)
const RAIL_H := 0.045

const LINEUP := {
	"V1a": {"brand": "haru", "ad": "sakuraLatte", "no": "SK-0701", "rows": [
		["coffee", "coffee", "black", "cafeLatte", "lemon", "lemon", "sakuraSoda", "cider"],
		["sakuraLatte", "sakuraLatte", "greenTea", "greenTea", "water", "water", "orange", "ion"],
		["ichigo", "ichigo", "mugi", "orange", "milkTea*", "greenTeaHot*", "potage*", "oshiruko*"]]},
	"V1b": {"brand": "sakura", "ad": "sakuraSoda", "no": "SK-0702", "rows": [
		["sakuraSoda", "sakuraSoda", "cider", "cider", "lemon", "cafeLatte", "coffee", "black"],
		["water", "water", "ion", "ion", "greenTea", "mugi", "orange", "sakuraLatte"],
		["ichigo", "ichigo", "orange", "greenTea", "coffee*", "cafeLatte*", "potage*", "oshiruko*"]]},
	"V2": {"brand": "aozora", "ad": "water", "no": "SK-0715", "rows": [
		["cider", "cider", "lemon", "coffee", "coffee", "black", "cafeLatte", "sakuraSoda"],
		["water", "water", "water", "ion", "ion", "greenTea", "mugi", "orange"],
		["ichigo", "orange", "greenTea", "mugi", "milkTea*", "greenTeaHot*", "coffee*", "potage*"]]},
	"V3a": {"brand": "midori", "ad": "tea", "no": "SK-0731", "rows": [
		["coffee", "coffee", "black", "black", "cafeLatte", "lemon", "cider", "sakuraSoda"],
		["greenTea", "greenTea", "greenTea", "mugi", "mugi", "water", "water", "sakuraLatte"],
		["greenTea", "mugi", "ichigo", "orange", "greenTeaHot*", "greenTeaHot*", "milkTea*", "oshiruko*"]]},
	"V3b": {"brand": "haru", "ad": "coffee", "no": "SK-0732", "rows": [
		["lemon", "lemon", "cider", "sakuraSoda", "sakuraSoda", "cafeLatte", "coffee", "black"],
		["sakuraLatte", "sakuraLatte", "ion", "water", "orange", "orange", "greenTea", "mugi"],
		["ichigo", "ichigo", "water", "ion", "coffee*", "milkTea*", "potage*", "potage*"]]},
	"V4": {"brand": "sakura", "ad": "ichigo", "no": "SK-0744", "old": true, "sold": [[1, 6]], "rows": [
		["coffee", "coffee", "black", "cafeLatte", "cider", "lemon", "lemon", "sakuraSoda"],
		["water", "greenTea", "greenTea", "mugi", "orange", "ion", "ion", "sakuraLatte"],
		["ichigo", "orange", "mugi", "water", "coffee*", "oshiruko*", "oshiruko*", "potage*"]]},
	"V5": {"brand": "aozora", "ad": "lemon", "no": "SK-0752", "rows": [
		["cider", "cider", "lemon", "sakuraSoda", "coffee", "coffee", "black", "cafeLatte"],
		["water", "water", "ion", "greenTea", "greenTea", "mugi", "orange", "sakuraLatte"],
		["ichigo", "ichigo", "orange", "water", "greenTeaHot*", "milkTea*", "coffee*", "potage*"]]},
}


static func _slot_x() -> Array:
	var out := []
	for i in 8:
		out.append(-0.3675 + i * 0.105)
	return out


static func product_geo(key: String) -> T.Geometry:
	var p: Dictionary = VT.products()[key]
	var s: Dictionary = VT.SHAPES[p.shape]
	var cp: Array = VT.cell_px(p.cell)
	var cx: float = cp[0]
	var cy: float = cp[1]
	var W: float = VT.ATLAS.W
	var H: float = VT.ATLAS.H
	var sw := func(i: int) -> Array: return VT.swatch_px(i)
	var parts := []
	var r: float = s.r
	var h: float = s.h
	if s.kind == "can":
		var body := Geo.cylinder(r, r, h * 0.84, 16, 1, true).rotate_y(PI)
		C.cell_uv(body, cx, cy, VT.ATLAS.cw, VT.ATLAS.ch, W, H)
		parts.append(C.xf(body, [0, h * 0.08 + h * 0.42, 0]))
		var bot := Geo.cylinder(r, r * 0.84, h * 0.08, 16, 1, true)
		var sp: Array = sw.call(VT.SWATCH.silver)
		C.solid_uv(bot, sp[0], sp[1], W, H)
		parts.append(C.xf(bot, [0, h * 0.04, 0]))
		var top := Geo.cylinder(r * 0.8, r, h * 0.065, 16, 1, true)
		C.solid_uv(top, sp[0], sp[1], W, H)
		parts.append(C.xf(top, [0, h * 0.92 + h * 0.0325, 0]))
		var lid := Geo.cylinder(r * 0.8, r * 0.8, 0.004, 16)
		var lp: Array = sw.call(VT.SWATCH.lid)
		C.solid_uv(lid, lp[0], lp[1], W, H)
		parts.append(C.xf(lid, [0, h * 0.985 + 0.002, 0]))
	else:
		var yb := 0.01
		var hb := h * 0.58
		var hs := h * 0.25
		var hc := h * 0.1
		var lq: Array = sw.call(p.liqSw)
		var bot := Geo.cylinder(r * 0.97, r * 0.88, yb, 14)
		C.solid_uv(bot, lq[0], lq[1], W, H)
		parts.append(C.xf(bot, [0, yb / 2.0, 0]))
		var body := Geo.cylinder(r, r, hb, 14, 1, true).rotate_y(PI)
		C.cell_uv(body, cx, cy, VT.ATLAS.cw, VT.ATLAS.ch, W, H)
		parts.append(C.xf(body, [0, yb + hb / 2.0, 0]))
		var sh := Geo.cylinder(0.0135, r, hs, 14, 1, true)
		C.solid_uv(sh, lq[0], lq[1], W, H)
		parts.append(C.xf(sh, [0, yb + hb + hs / 2.0, 0]))
		var cap := Geo.cylinder(0.0152, 0.0152, hc, 10)
		var cpx: Array = sw.call(p.capSw)
		C.solid_uv(cap, cpx[0], cpx[1], W, H)
		parts.append(C.xf(cap, [0, yb + hb + hs + hc / 2.0, 0]))
	return C.merge_all(parts)


static func build_vending(ctx, H) -> void:
	var L = ctx.L
	var mat = ctx.mat
	var physics = ctx.physics
	var tx: Dictionary = VT.make_vend_textures(ctx)
	var PRODUCTS: Dictionary = VT.products()
	var M := {
		"silver": mat.toon("#c3c9cf", {"paint": 0.02}),
		"grey": mat.toon("#8d939b", {"paint": 0.02}),
		"dark": mat.toon("#4b4d55", {"paint": 0.02}),
		"ink": mat.toon("#3a3346", {"paint": 0}),
		"kick": mat.toon("#5b5e66", {"paint": 0.03}),
		"rail": mat.toon("#e2e6ea", {"paint": 0.01}),
		"concrete": mat.toon("#c4c2ba", {"paint": 0.08}),
		"steelBase": mat.toon("#7d848c", {"paint": 0.04}),
		"icBody": mat.toon("#5a6170", {"paint": 0.02}),
		"liner": mat.emissive("#eef4fa", 0.86),
		"back": mat.emissive("#ffffff", 0.97, {"map": tx.backPanel}),
		"ic": mat.emissive("#ffffff", 0.95, {"map": tx.icFace}),
		"glass": mat.glass({"tint": "#c8dbe9", "opacity": 0.08, "streaks": true}),
		"products": mat.emissive("#ffffff", 0.93, {"map": tx.atlas}),
	}
	var machines := []

	for v in L.VENDING:
		var cfg: Dictionary = LINEUP.get(v.id, LINEUP.V1a)
		var B: Dictionary = VT.BRANDS[cfg.brand]
		var rot: float = v.rotY
		var old: bool = cfg.get("old", false)
		var y0: float
		var base: Dictionary
		if v.get("y") != null:
			y0 = v.y + 0.02
			base = {"top": 0.0, "bottom": -0.02, "steel": true}
		else:
			var fp: Dictionary = H.footprint(v.x, v.z, 1.08, 0.82, rot)
			y0 = fp.max + 0.04
			base = {"top": 0.0, "bottom": fp.min - 0.07 - y0}
		var g = H.place(v.x, y0, v.z, rot)
		var k = ctx.kit(g)
		var casing = mat.toon(B.casing, {"paint": 0.07 if old else 0.045})
		var door = mat.toon(B.door, {"paint": 0.07 if old else 0.04})
		var stile = mat.toon(B.stile, {"paint": 0.04})
		# --- base / plinth
		if base.get("steel"):
			k.boxb(1.04, 0.02, 0.78, M.steelBase, [0, -0.02, 0])
		else:
			k.boxb(1.08, base.top - base.bottom, 0.82, M.concrete, [0, base.bottom, 0])
		# --- body + cap
		k.rbox(1.0, 1.79, 0.625, 0.035, casing, [0, 0.895, -0.0625])
		k.rbox(1.03, 0.045, 0.785, 0.018, casing, [0, 1.8075, -0.0045])
		# --- front door pieces around the display opening
		k.rbox(0.99, 0.835, 0.125, 0.02, door, [0, 0.4375, 0.3125])
		k.rbox(0.99, 0.23, 0.125, 0.02, door, [0, 1.67, 0.3125])
		for s in [-1, 1]:
			k.box(0.035, 0.70, 0.125, stile, [s * 0.4775, 1.205, 0.3125])
		# --- header (lit brand panel)
		k.box(0.935, 0.205, 0.006, M.dark, [0, 1.665, 0.3765])
		k.plane(0.91, 0.188, mat.emissive("#ffffff", 1.0, {"map": tx.headers[cfg.brand]}), [0, 1.665, 0.3805])
		# --- display: back glow, liners, rails, glass
		k.plane(0.92, 0.70, M.back, [0, 1.205, 0.2515])
		k.plane(0.125, 0.70, M.liner, [-0.4595, 1.205, 0.3125], [0, PI / 2.0, 0])
		k.plane(0.125, 0.70, M.liner, [0.4595, 1.205, 0.3125], [0, -PI / 2.0, 0])
		k.plane(0.92, 0.125, M.liner, [0, 1.5535, 0.3125], [PI / 2.0, 0, 0])
		var rail_rows := []
		for r in cfg.rows.size():
			var row_out := []
			for i in cfg.rows[r].size():
				var key0: String = cfg.rows[r][i]
				var hot := key0.ends_with("*")
				var p: Dictionary = PRODUCTS[key0.replace("*", "")]
				var sold := false
				if cfg.get("sold"):
					for ri in cfg.sold:
						if ri[0] == r and ri[1] == i:
							sold = true
				row_out.append({"price": p.price, "hot": hot, "sold": sold})
			rail_rows.append(row_out)
		var rail_tex = tx.rails.call(v.id, rail_rows, SLOT_X)
		var rail_mat = mat.emissive("#ffffff", 0.9, {"map": rail_tex})
		for r in cfg.rows.size():
			var row: Array = cfg.rows[r]
			var ry: float = RAIL_Y[r]
			k.box(0.92, RAIL_H, 0.11, M.rail, [0, ry + RAIL_H / 2.0, 0.31])
			var pg := Geo.plane(0.91, RAIL_H)
			C.cell_uv(pg, 0, r * 53, 1024, 52, 1024, 160)
			var rm = k.mesh(pg, rail_mat, [0, ry + RAIL_H / 2.0, 0.3658])
			rm.cast_shadow = false
			# products (instanced later)
			for i in row.size():
				var key: String = row[i].replace("*", "")
				var m := T.compose(Vector3(SLOT_X[i], ry + RAIL_H, 0.305), Quaternion(), Vector3.ONE)
				machines.append({"g": g, "key": key, "m": m})
		var glass = k.plane(0.92, 0.70, M.glass, [0, 1.205, 0.3715])
		glass.cast_shadow = false
		glass.receive_shadow = false
		ctx.no_outline(glass)
		# --- lower door: decal art + payment hardware + take-out frame
		var lower = mat.decal("#ffffff", {"map": tx.lowerPanel.call(v.id, cfg.brand, cfg.ad, {"faded": old, "no": cfg.no}), "transparent": true})
		k.plane(0.95, 0.83, lower, [0, 0.44, 0.3772])
		k.box(0.05, 0.08, 0.012, M.silver, [0.35, 0.755, 0.381])
		k.box(0.007, 0.045, 0.004, M.ink, [0.35, 0.755, 0.3885])
		k.box(0.026, 0.05, 0.02, M.silver, [0.415, 0.755, 0.385])
		k.box(0.15, 0.04, 0.02, M.dark, [0.35, 0.645, 0.385])
		k.box(0.11, 0.006, 0.004, M.ink, [0.35, 0.645, 0.3965])
		k.rbox(0.125, 0.095, 0.02, 0.008, M.icBody, [0.35, 0.505, 0.385])
		k.plane(0.115, 0.085, M.ic, [0.35, 0.505, 0.3955])
		k.box(0.11, 0.075, 0.025, M.silver, [0.35, 0.36, 0.3875])
		k.plane(0.085, 0.048, M.ink, [0.35, 0.357, 0.4005])
		k.box(0.64, 0.02, 0.02, M.silver, [-0.13, 0.28, 0.385])
		k.box(0.66, 0.012, 0.05, M.silver, [-0.13, 0.294, 0.397])
		k.box(0.64, 0.02, 0.02, M.silver, [-0.13, 0.08, 0.385])
		for x in [-0.44, 0.18]:
			k.box(0.02, 0.22, 0.02, M.silver, [x, 0.18, 0.385])
		k.box(0.97, 0.055, 0.02, M.kick, [0, 0.0275, 0.378])
		# --- sides: brand graphics + grime; front grime
		var side_mat = mat.decal("#ffffff", {"map": tx.sides[cfg.brand], "transparent": true})
		k.plane(0.56, 1.5, side_mat, [0.5015, 0.98, -0.075], [0, PI / 2.0, 0])
		k.plane(0.56, 1.5, side_mat, [-0.5015, 0.98, -0.075], [0, -PI / 2.0, 0])
		var grime_mat = mat.decal("#ffffff", {"map": tx.grime.call(old), "transparent": true, "opacity": 1 if old else 0.8})
		k.plane(0.99, 0.42, grime_mat, [0, 0.21, 0.3795])
		k.plane(0.7, 0.42, grime_mat, [0.5035, 0.21, -0.02], [0, PI / 2.0, 0])
		k.plane(0.7, 0.42, grime_mat, [-0.5035, 0.21, -0.02], [0, -PI / 2.0, 0])
		if v.id == "V4":
			k.plane(0.17, 0.17, mat.decal("#ffffff", {"map": tx.sticker, "transparent": true}), [0.504, 1.16, 0.12], [0, PI / 2.0, 0.08])
		physics.addBox(v.x, v.z, 1.0, 0.75, rot, y0 - 0.1, y0 + 1.83)
		# --- neighbours: bins, crates, flag
		var vx: float = v.x
		var vz: float = v.z
		var put := func(lx: float, lz: float, lrot: float = 0.0) -> Dictionary:
			var p: Dictionary = H.to_world(vx, vz, rot, lx, lz)
			return {"x": p.x, "z": p.z, "rotY": rot + lrot}
		if v.id == "V1b":
			recycle_bin(ctx, H, M, tx, put.call(0.77, 0.0), "blue", "#e9ecee", "#5b8fd6")
			nobori(ctx, H, tx, put.call(1.32, 0.05, -0.25))
		if v.id == "V2":
			recycle_bin(ctx, H, M, tx, put.call(-0.77, 0.0), "blue", "#e9ecee", "#5b8fd6", v.get("y"))
		if v.id == "V3a":
			recycle_bin(ctx, H, M, tx, put.call(-0.77, 0.02), "blue", "#e8eae6", "#4f9e78")
		if v.id == "V4":
			recycle_bin(ctx, H, M, tx, put.call(-0.77, 0.02), "old", "#d8ddd6", "#4d8a6a")
			crate_stack(ctx, H, tx, put.call(-1.36, 0.0, 0.08), ["#4f7fc4", "#e7c14f"])
		if v.id == "V5":
			recycle_bin(ctx, H, M, tx, put.call(-0.83, 0.04), "blue", "#e9ecee", "#5b8fd6")

	# --- products: one shared geometry per product type, plain meshes (the static batcher merges them
	#     per cell into one draw call with the shared atlas material)
	var geo_by_key := {}
	for e in machines:
		if not geo_by_key.has(e.key):
			geo_by_key[e.key] = product_geo(e.key)
		var pm := T.MeshObj.new(geo_by_key[e.key], M.products)
		var m: Transform3D = e.m
		pm.position = m.origin
		pm.set_quaternion(m.basis.get_rotation_quaternion())
		pm.scale = m.basis.get_scale()
		pm.cast_shadow = false
		pm.receive_shadow = false
		pm.name = "props.product." + e.key
		e.g.add(pm)


static func recycle_bin(ctx, H, M: Dictionary, tx: Dictionary, p: Dictionary, style: String, body: String, lid: String, y_fixed = null) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var y0: float
	if y_fixed != null:
		y0 = y_fixed
	else:
		y0 = H.footprint(p.x, p.z, 0.44, 0.36, p.rotY).max
	var g = H.place(p.x, y0, p.z, p.rotY)
	var k = ctx.kit(g)
	var mb = mat.toon(body, {"paint": 0.05})
	var ml = mat.toon(lid, {"paint": 0.04})
	if y_fixed == null:
		var fp: Dictionary = H.footprint(p.x, p.z, 0.44, 0.36, p.rotY)
		k.boxb(0.44, 0.03 + (y0 - fp.min) + 0.04, 0.36, M.kick, [0, fp.min - y0 - 0.04, 0])
	else:
		k.boxb(0.44, 0.03, 0.36, M.kick, [0, 0, 0])
	k.rbox(0.42, 0.78, 0.34, 0.05, mb, [0, 0.42, 0])
	k.rbox(0.44, 0.07, 0.36, 0.03, ml, [0, 0.835, 0])
	k.plane(0.39, 0.49, mat.decal("#ffffff", {"map": tx.bin.call(style), "transparent": true}), [0, 0.36, 0.1725])
	for sx in [-0.095, 0.095]:
		k.cyl(0.066, 0.066, 0.012, ml, [sx, 0.67, 0.172], [PI / 2.0, 0, 0], 20)
		k.cyl(0.052, 0.052, 0.004, M.ink, [sx, 0.67, 0.1795], [PI / 2.0, 0, 0], 20)
	physics.addBox(p.x, p.z, 0.44, 0.36, p.rotY, y0 - 0.1, y0 + 0.87)


static func crate_stack(ctx, H, tx: Dictionary, p: Dictionary, colors: Array) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var fp: Dictionary = H.footprint(p.x, p.z, 0.45, 0.33, p.rotY)
	var g = H.place(p.x, fp.max, p.z, p.rotY)
	var y := 0.0
	for i in colors.size():
		var c: String = colors[i]
		var gg := T.Group.new()
		gg.position = Vector3(0.012 if i else 0.0, y, -0.01 if i else 0.0)
		gg.rotation.y = 0.07 if i else 0.0
		g.add(gg)
		var k = ctx.kit(gg)
		var mt = mat.toon("#ffffff", {"map": tx.crate.call(c), "paint": 0.03})
		var mc = mat.toon(c, {"paint": 0.05})
		var h := 0.28
		for s in [-1, 1]:
			k.box(0.45, h, 0.018, mt, [0, h / 2.0, s * 0.156])
			k.box(0.018, h, 0.294, mt, [s * 0.216, h / 2.0, 0])
		k.box(0.42, 0.02, 0.3, mc, [0, 0.012, 0])
		for z in [-0.05, 0.05]:
			k.box(0.42, 0.19, 0.008, mc, [0, 0.115, z])
		for x in [-0.105, 0, 0.105]:
			k.box(0.008, 0.19, 0.3, mc, [x, 0.115, 0])
		y += h + 0.002
	physics.addBox(p.x, p.z, 0.47, 0.35, p.rotY, fp.min - 0.1, fp.max + y)


static func nobori(ctx, H, tx: Dictionary, p: Dictionary) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var y0: float = H.footprint(p.x, p.z, 0.34, 0.34, p.rotY).max
	var g = H.place(p.x, y0, p.z, p.rotY)
	var k = ctx.kit(g)
	k.rbox(0.26, 0.12, 0.26, 0.04, mat.toon("#6a6874", {"paint": 0.03}), [0, 0.06, 0])
	var pole = mat.toon("#e6e6e2", {"paint": 0.02})
	k.cyl(0.016, 0.016, 2.25, pole, [0, 0.12 + 1.125, 0])
	k.cyl(0.009, 0.009, 0.5, pole, [0.25, 2.33, 0], [0, 0, PI / 2.0])
	var sheet := C.wave_sheet(0.45, 1.55, 0.035, 1.1, 0.3)
	var fm = mat.toon("#ffffff", {"map": tx.flag, "paint": 0.02})
	k.mesh(sheet, fm, [0.255, 2.33 - 0.8, 0])
	k.mesh(C.back_side(sheet), fm, [0.255, 2.33 - 0.8, 0])
	physics.addCylinder(p.x, p.z, 0.2, y0 - 0.1, y0 + 2.4)
