# houses.js: the residential module. Every residential lot on the main street (W3, W5, W7-W13, E4,
# E7-E13), the residential blocks (NW, NE, SWB, SEB, N1W/N1E/N2W/N2E) with their own lanes, an
# apartment, fields and the low-detail far town. Publishes ctx.services.houses = {gardenSpots,
# bikeSpots, wallTops}.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const GBM = preload("res://addons/sakuragaoka_station/world/houses/gb.gd")
const Tex = preload("res://addons/sakuragaoka_station/world/houses/tex.gd")
const Props = preload("res://addons/sakuragaoka_station/world/houses/props.gd")
const Laundry = preload("res://addons/sakuragaoka_station/world/houses/laundry.gd")
const Lot = preload("res://addons/sakuragaoka_station/world/houses/lot.gd")
const Apartment = preload("res://addons/sakuragaoka_station/world/houses/apartment.gd")
const Far = preload("res://addons/sakuragaoka_station/world/houses/far.gd")
const House = preload("res://addons/sakuragaoka_station/world/houses/house.gd")
const Fol = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")

const PLAN := {
	"W5": {"layout": "yard", "frontStyle": "hedge", "gardenSpot": true, "floors": 2},
	"W7": {"layout": "sidePark", "floors": 3, "roofType": "shed"},
	"W8": {"layout": "yard", "traditional": true, "frontStyle": "block", "gardenSpot": true},
	"W9": {"layout": "frontPark", "floors": 2},
	"W10": {"layout": "yard", "frontStyle": "fence", "floors": 2, "gardenSpot": true},
	"W11": {"layout": "sidePark", "floors": 2},
	"W12": {"layout": "yard", "frontStyle": "plasterWall", "floors": 2, "koinobori": true},
	"W13": {"layout": "sidePark", "floors": 2, "gardenSpot": false},
	"E4": {"layout": "yard", "frontStyle": "block", "floors": 2, "gardenSpot": true},
	"E7": {"layout": "frontPark", "floors": 2},
	"E8": {"layout": "yard", "frontStyle": "hedge", "floors": 2, "gardenSpot": true},
	"E9": {"layout": "sidePark", "floors": 3},
	"E10": {"layout": "yard", "traditional": true, "frontStyle": "plasterWall", "gardenSpot": true},
	"E11": {"layout": "sidePark", "floors": 2},
	"E12": {"layout": "yard", "frontStyle": "lattice", "floors": 2},
	"E13": {"layout": "frontPark", "floors": 2},
}


## houses.js's H: the module context shared by the lot, house, prop and laundry builders.
class HouseCtx extends RefCounted:
	var ctx
	var L
	var M: Dictionary
	var tex: Dictionary
	var A: Dictionary
	var gb
	var lod = 2
	var antenna_az := 0.0
	var dish_az := 0.0
	var props
	var P:
		get:
			return props
	var laundry
	var phys

	func blob_raw(variant: int, detail: int = 1) -> Dictionary:
		return Props.blob_raw(variant, detail)

	func gy(fr, x: float, z: float) -> float:
		var p: Vector3 = fr.w(x, 0, z)
		return L.height_at(p.x, p.z) - p.y

	func col(fr, x: float, z: float, w: float, d: float, ry: float, y0: float, y1: float) -> void:
		var p: Vector3 = fr.w(x, 0, z)
		phys.addBox(p.x, p.z, w, d, fr.ry + ry, p.y + y0, p.y + y1)

	func colC(fr, x: float, z: float, rad: float, y0: float, y1: float) -> void:
		var p: Vector3 = fr.w(x, 0, z)
		phys.addCylinder(p.x, p.z, rad, p.y + y0, p.y + y1)

	func walk(fr, x: float, z: float, w: float, d: float, ry: float, top: float, bottom = null) -> void:
		var p: Vector3 = fr.w(x, 0, z)
		phys.addWalkBox(p.x, p.z, w, d, fr.ry + ry, p.y + top, p.y + bottom if bottom != null else p.y + top - 0.6)

	## quads: [{p: [[x, y, z] x4], n: [x, y, z], uv?: [[u, v] x4]}], wound to face n.
	func quads(fr, mat, c, qs: Array, fl = null) -> void:
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		var U := PackedVector2Array()
		var I := PackedInt32Array()
		for q in qs:
			var k := P.size()
			var n := Vector3(q.n[0], q.n[1], q.n[2])
			for i in 4:
				P.append(Vector3(q.p[i][0], q.p[i][1], q.p[i][2]))
				N.append(n)
				U.append(Vector2(q.uv[i][0], q.uv[i][1]) if q.get("uv") else Vector2.ZERO)
			var a: Vector3 = P[k]
			var e1: Vector3 = P[k + 1] - a
			var e2: Vector3 = P[k + 2] - a
			if e1.cross(e2).dot(n) >= 0.0:
				I.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
			else:
				I.append_array([k, k + 2, k + 1, k, k + 3, k + 2])
		if not qs.is_empty():
			gb.mesh(mat, c, P, N, U, I, fr.M(0, 0, 0), fl)

	## A wall along local x (a..b) at z whose top follows the ground (+h); bottom at ground - 0.3
	## or ground + base.
	func sloped_wall(fr, a: float, b: float, z: float, h: float, t: float, mat, c, uS: float, vS: float, base = null) -> void:
		var L2 := b - a
		if L2 <= 0.01:
			return
		var n: int = maxi(1, ceili(L2 / 2.5))
		var qs := []
		var z0 := z - t / 2.0
		var z1 := z + t / 2.0
		var uv := func(x: float, dy: float) -> Array: return [x / uS, dy / vS] if uS else [0.5, 0.5]
		for i in n:
			var x0 := a + L2 * i / n
			var x1 := a + L2 * (i + 1) / n
			var g0 := gy(fr, x0, z)
			var g1 := gy(fr, x1, z)
			var bo: float = -0.3 if base == null else base
			var b0 := g0 + bo
			var b1 := g1 + bo
			var t0 := g0 + h
			var t1 := g1 + h
			qs.append({"p": [[x0, b0, z1], [x1, b1, z1], [x1, t1, z1], [x0, t0, z1]], "n": [0, 0, 1], "uv": [uv.call(x0, bo), uv.call(x1, bo), uv.call(x1, h), uv.call(x0, h)]})
			qs.append({"p": [[x1, b1, z0], [x0, b0, z0], [x0, t0, z0], [x1, t1, z0]], "n": [0, 0, -1], "uv": [uv.call(-x1, bo), uv.call(-x0, bo), uv.call(-x0, h), uv.call(-x1, h)]})
			qs.append({"p": [[x0, t0, z1], [x1, t1, z1], [x1, t1, z0], [x0, t0, z0]], "n": [0, 1, 0], "uv": [uv.call(x0, 0), uv.call(x1, 0), uv.call(x1, t), uv.call(x0, t)]})
			if i == 0:
				qs.append({"p": [[x0, b0, z0], [x0, b0, z1], [x0, t0, z1], [x0, t0, z0]], "n": [-1, 0, 0], "uv": [uv.call(0, bo), uv.call(t, bo), uv.call(t, h), uv.call(0, h)]})
			if i == n - 1:
				qs.append({"p": [[x1, b1, z1], [x1, b1, z0], [x1, t1, z0], [x1, t1, z1]], "n": [1, 0, 0], "uv": [uv.call(0, bo), uv.call(t, bo), uv.call(t, h), uv.call(0, h)]})
		quads(fr, mat, c, qs)

	## A terrain-following ground cover rectangle in frame-local coordinates; world-space UVs (uvS m
	## per repeat).
	func ground_rect(fr, x0: float, z0: float, x1: float, z1: float, mat, c, lift: float = 0.02, uvS: float = 2.0) -> void:
		if x1 - x0 < 0.05 or z1 - z0 < 0.05:
			return
		var nx: int = maxi(1, ceili((x1 - x0) / 2.2))
		var nz: int = maxi(1, ceili((z1 - z0) / 2.2))
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		var U := PackedVector2Array()
		var I := PackedInt32Array()
		for j in nz + 1:
			for i in nx + 1:
				var x := x0 + (x1 - x0) * i / nx
				var z := z0 + (z1 - z0) * j / nz
				var w: Vector3 = fr.w(x, 0, z)
				P.append(Vector3(x, L.height_at(w.x, w.z) - w.y + lift, z))
				N.append(Vector3(0, 1, 0))
				U.append(Vector2(w.x / uvS, -w.z / uvS))
		for j in nz:
			for i in nx:
				var a := j * (nx + 1) + i
				var b := a + 1
				var cc := a + nx + 1
				var d := cc + 1
				I.append_array([a, cc, b, b, cc, d])
		gb.mesh(mat, c, P, N, U, I, fr.M(0, 0, 0), {"shadow": false})

	## A decal quad (moss / streak / crack / dirt / stain) facing +z of fr, or on the floor.
	func decal(fr, name: String, x: float, y: float, w: float, h: float, z: float, c, o: Dictionary = {}) -> void:
		var rc = tex.decal.rects.get(name)
		if not rc:
			return
		var uv := [[rc[0], rc[1]], [rc[2], rc[1]], [rc[2], rc[3]], [rc[0], rc[3]]]
		if o.get("floor"):
			var zz: float = o.z
			var g := func(xx: float, zv: float) -> float: return (o.gy.call(xx, zv) if o.get("gy") else gy(fr, xx, zv)) + 0.066
			quads(fr, M.decal, c, [{"p": [[x - w / 2, g.call(x - w / 2, zz + h / 2), zz + h / 2], [x + w / 2, g.call(x + w / 2, zz + h / 2), zz + h / 2], [x + w / 2, g.call(x + w / 2, zz - h / 2), zz - h / 2], [x - w / 2, g.call(x - w / 2, zz - h / 2), zz - h / 2]], "n": [0, 1, 0], "uv": uv}], {"shadow": false, "noOutline": true})
			return
		quads(fr, M.decal, c, [{"p": [[x - w / 2, y - h / 2, z], [x + w / 2, y - h / 2, z], [x + w / 2, y + h / 2, z], [x - w / 2, y + h / 2, z]], "n": [0, 0, 1], "uv": uv}], {"shadow": false, "noOutline": true})

	## A see-through wire mesh panel between a..b at z (alpha).
	func mesh_panel(fr, a: float, b: float, z: float, y0: float, y1: float, c) -> void:
		var rc: Array = tex.decal.rects.mesh
		var n: int = maxi(1, int(T.js_round((b - a) / 1.0)))
		var qs := []
		for i in n:
			var x0 := a + (b - a) * i / n
			var x1 := a + (b - a) * (i + 1) / n
			var g0 := gy(fr, x0, z)
			var g1 := gy(fr, x1, z)
			qs.append({"p": [[x0, g0 + y0, z], [x1, g1 + y0, z], [x1, g1 + y1, z], [x0, g0 + y1, z]], "n": [0, 0, 1], "uv": [[rc[0], rc[1]], [rc[2], rc[1]], [rc[2], rc[3]], [rc[0], rc[3]]]})
		quads(fr, M.meshFence, c, qs, {"shadow": false, "noOutline": true})

	## An asphalt / gravel strip along a world polyline [[x, z]...] with half width hw.
	func strip(pts: Array, hw: float, mat, c, lift: float = 0.018, uvS: float = 4.0) -> void:
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		var U := PackedVector2Array()
		var I := PackedInt32Array()
		# resample every ~2 m
		var rs := []
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var az: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var bz: float = pts[i + 1][1]
			var n: int = maxi(1, ceili(Vector2(bx - ax, bz - az).length() / 2.0))
			for k in n:
				rs.append([ax + (bx - ax) * k / n, az + (bz - az) * k / n])
		rs.append(pts[pts.size() - 1])
		var dist := 0.0
		for i in rs.size():
			var p: Array = rs[i]
			var q: Array = rs[mini(rs.size() - 1, i + 1)]
			var o: Array = rs[maxi(0, i - 1)]
			var tx: float = q[0] - o[0]
			var tz: float = q[1] - o[1]
			var l := Vector2(tx, tz).length()
			if l == 0.0:
				l = 1.0
			tx /= l
			tz /= l
			var nx := -tz
			var nz := tx
			if i > 0:
				dist += Vector2(p[0] - rs[i - 1][0], p[1] - rs[i - 1][1]).length()
			for s in [-1, 1]:
				var x: float = p[0] + nx * hw * s
				var z: float = p[1] + nz * hw * s
				P.append(Vector3(x, L.height_at(x, z) + lift, z))
				N.append(Vector3(0, 1, 0))
				U.append(Vector2(x / uvS, -z / uvS))
			if i > 0:
				var k := (i - 1) * 2
				I.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
		# fix winding: make sure triangles face up
		for i in range(0, I.size(), 3):
			var a := I[i]
			var b := I[i + 1]
			var cc := I[i + 2]
			var e1x := P[b].x - P[a].x
			var e1z := P[b].z - P[a].z
			var e2x := P[cc].x - P[a].x
			var e2z := P[cc].z - P[a].z
			if e1z * e2x - e1x * e2z < 0.0:
				I[i + 1] = cc
				I[i + 2] = b
		gb.mesh(mat, c, P, N, U, I, Transform3D(), {"shadow": false})


## Returns null, or the error that stopped the build.
func build(ctx):
	var L = ctx.L
	var tex: Dictionary = Tex.make_house_textures(ctx)
	var M: Dictionary = Tex.make_house_materials(ctx, tex)
	M["foliage"] = Fol.foliage_material(ctx)  # smooth shrubs / hedges / tree clouds
	M["meshFence"] = ctx.mat.decal("#ffffff", {"map": tex.decal.texture, "vertexColors": true, "transparent": true, "side": "double"})
	var root := T.Group.new()
	root.name = "houses"
	ctx.add_static(root)
	var gb := GBM.GB.new(ctx)
	var H := HouseCtx.new()
	H.ctx = ctx
	H.L = L
	H.M = M
	H.tex = tex
	H.A = tex.atlas
	H.gb = gb
	H.lod = 2
	H.antenna_az = atan2(-0.62, -0.78) + PI / 2.0  # Yagi booms point toward the NW transmitter
	H.dish_az = 0.7  # BS dishes face south-west
	H.phys = ctx.physics
	H.props = Props.new(H)
	H.laundry = Laundry.new(H)
	var P = H.props

	var services := {"gardenSpots": [], "bikeSpots": [], "wallTops": []}
	var collect := func(res, pri: int = 1) -> void:
		if not res:
			return
		for k in ["gardenSpots", "bikeSpots", "wallTops"]:
			for s in res.get(k, []):
				var e: Dictionary = s.duplicate()
				e["pri"] = pri
				services[k].append(e)

	# ================================================================== main street lots
	var house_lots := {}
	for l in L.LOTS:
		if l.owner == "houses":
			house_lots[l.id] = true
	for i in L.LOTS.size():
		var lot: Dictionary = L.LOTS[i]
		if lot.owner != "houses":
			continue
		var f: Dictionary = L.lot_frame(lot)
		var F = GBM.Frame.at(gb, f.x, f.y, f.z, f.rotY)
		if lot.id == "W3":
			collect.call(_build_w3(H, F, f), 3)
			continue
		# right neighbour (+lx): W lots -> north (previous index), E lots -> south (next index)
		var ri: int = i - 1 if lot.side < 0 else i + 1
		var right_n = L.LOTS[ri] if ri >= 0 and ri < L.LOTS.size() else null
		var right_is_house: bool = right_n != null and right_n.side == lot.side and house_lots.has(right_n.id) and right_n.id != "W3"
		var plan: Dictionary = PLAN.get(lot.id, {})
		var D := {"F": F, "w": f.w, "depth": f.depth, "seed": "main-" + lot.id, "lod": 2, "walls": {"left": true, "right": not right_is_house, "back": true}}
		D.merge(plan, true)
		D.merge({"antennaP": 0.7, "balconyP": 0.85, "laundryP": 0.75}, true)
		var res: Dictionary = Lot.build_lot(H, D)
		if plan.get("koinobori"):
			var p: Dictionary = res.houseRect
			var kx: float = p.hx0 - 0.6 if p.hx1 + 0.55 > f.w / 2.0 - 0.3 else p.hx1 + 0.55
			H.laundry.koinobori(F, kx, H.gy(F, kx, -2.0), -2.0, 7.2)
			H.colC(F, kx, -2.0, 0.08, -1, 8)
		collect.call(res, 3)

	# ================================================================== residential blocks
	# lots facing south along z = zf, spanning x a..b
	var rowS := func(id: String, xa: float, xb: float, zf: float, depth: float, o: Dictionary = {}) -> Array:
		var r = ctx.rng("row-" + id)
		var out := []
		var x := xa
		var k := 0
		var widths := []
		while x < xb - 7.5:
			var w: float = o.w if o.get("w") else 9 + r.f() * 2.4
			if xb - (x + w) < 7.5:
				w = xb - x
			widths.append([x, w])
			x += w
		for xw in widths:
			var cx: float = xw[0] + xw[1] / 2.0
			var F = GBM.Frame.at(gb, cx, L.height_at(cx, zf), zf, 0)
			out.append({"F": F, "w": xw[1], "depth": depth, "id": id + "-" + str(k), "cx": cx})
			k += 1
		return out
	# lots facing east (face = 1) or west (-1) along x = xf, spanning z a..b
	var rowE := func(id: String, xf, za: float, zb: float, depth: float, face: int = 1, o: Dictionary = {}) -> Array:
		var r = ctx.rng("rowE-" + id)
		var out := []
		var z := za
		var k := 0
		while z < zb - 7.5:
			var w: float = 9.2 + r.f() * 2.0
			if zb - (z + w) < 7.5:
				w = zb - z
			var cz := z + w / 2.0
			var xx: float = xf.call(cz) if xf is Callable else xf
			var ry := PI / 2.0 if face > 0 else -PI / 2.0
			var F = GBM.Frame.at(gb, xx, L.height_at(xx, cz), cz, ry + (o.slope.call(cz) if o.get("slope") else 0.0))
			out.append({"F": F, "w": w, "depth": depth, "id": id + "-" + str(k), "cz": cz})
			k += 1
			z += w
		return out
	var doRow := func(lots: Array, o: Dictionary = {}) -> void:
		var skip = o.get("skip")
		for i in lots.size():
			var d: Dictionary = lots[i]
			if skip and skip.call(d, i):
				continue
			var right: bool = i == lots.size() - 1 or (skip != null and skip.call(lots[i + 1], i + 1))
			var D := {
				"F": d.F, "w": d.w, "depth": d.depth, "seed": d.id, "lod": o.lod if o.get("lod") != null else 1,
				"walls": {"left": true, "right": right, "back": o.get("back") != false},
				"gardenSpot": o.gardenSpot.call(d, i) if o.get("gardenSpot") else false,
				"traditional": o.trad.call(d, i) if o.get("trad") else false,
			}
			if o.get("per"):
				D.merge(o.per.call(d, i), true)
			var res: Dictionary = Lot.build_lot(H, D)
			collect.call(res, o.pri if o.get("pri") != null else 1)
			if o.get("after"):
				o.after.call(d, i, res)

	# --- NW block (south of the tracks, west of R2)
	doRow.call(rowS.call("NWs", -62, -15.7, -5.8, 11.2), {"lod": 2, "pri": 2, "gardenSpot": func(_d, i): return i == 1 or i == 3, "trad": func(_d, i): return i == 2})
	# lane between the rows
	H.strip([[-14.9, -18.6], [-62.5, -18.6]], 1.5, M.asphalt, "#8a8c90", 0.018, 4)
	var nwN: Array = rowS.call("NWn", -62, -24.5, -20.1, 10.8)
	doRow.call(nwN, {"lod": 2, "pri": 2, "per": func(_d, i): return {"floors": 2 if i == nwN.size() - 1 else null}, "gardenSpot": func(_d, i): return i == 0})
	# NW corner by R2 / V5: small garden with a sakura spot, low hedge, bench-free
	if true:
		var F = GBM.Frame.at(gb, -21.0, 0, -25.5, 0)
		var gyF := func(x: float, z: float) -> float: return H.gy(F, x, z)
		H.ground_rect(F, -3.4, -5.4, 3.35, 5.3, M.lawn, "#b9cf98", 0.02, 2)
		Lot.boundary_seg(H, F, -3.4, 3.35, 5.25, "low", 0.4, "#c9c7c0", ctx.rng("nwc"), gyF, 2, null, true)
		Lot.boundary_seg_z(H, F, 3.35, 5.0, -3.0, "hedge", 1.0, "#c9c7c0", ctx.rng("nwc2"), gyF)
		P.bush(F, -2.2, H.gy(F, -2.2, -3.8), -3.8, 0.5, ctx.rng("nwc3"), {"pal": "green", "flowers": "azalea"})
		P.bush(F, 1.8, H.gy(F, 1.8, -4.4), -4.4, 0.45, ctx.rng("nwc4"), {"pal": "dark"})
		services.gardenSpots.append({"x": -20.6, "z": -26.2, "r": 2.0, "pri": 3})

	# --- NE block (east of the plaza)
	if true:
		# corner plot (disaster cabinet stays at (29.5, -7.2)): gravel + shrubs + a sakura spot
		var F = GBM.Frame.at(gb, 29.6, 0, -11.4, 0)
		H.ground_rect(F, -2.5, -5.6, 2.5, 5.5, M.gravel, "#d6d0c4", 0.02, 1.5)
		H.ground_rect(F, -2.2, -5.3, 2.2, -1.6, M.lawn, "#b9cf98", 0.03, 2)
		Lot.boundary_seg_z(H, F, 2.45, 5.4, -5.6, "mesh", 1.1, "#c9c7c0", ctx.rng("nec"), func(x: float, z: float) -> float: return H.gy(F, x, z))
		P.bush(F, -1.8, 0, 1.2, 0.4, ctx.rng("nec2"), {"pal": "green", "flowers": "azalea"})
		P.bush(F, 1.7, 0, 0.5, 0.35, ctx.rng("nec3"), {"pal": "dark"})
		services.gardenSpots.append({"x": 29.5, "z": -14.8, "r": 1.8, "pri": 3})
	doRow.call(rowS.call("NEs", 32.2, 62, -5.8, 11.2), {"lod": 2, "pri": 2, "gardenSpot": func(_d, i): return i == 1})
	H.strip([[26.05, -18.6], [62.5, -18.6]], 1.5, M.asphalt, "#8a8c90", 0.018, 4)
	if true:
		var w := 17.0
		var cx := 27.2 + w / 2.0
		var F = GBM.Frame.at(gb, cx, L.height_at(cx, -20.1), -20.1, 0)
		collect.call(Apartment.build_apartment(H, F, w, 10.8, ctx.rng("apt")), 2)
	doRow.call(rowS.call("NEn", 44.4, 62, -20.1, 10.8), {"lod": 2, "pri": 2})

	# --- north residential rows
	var n1w: Array = rowS.call("N1W", -85, -15.7, -57.9, 10.9)
	doRow.call(n1w, {"lod": 1, "pri": 1, "gardenSpot": func(_d, i): return i == 2 or i == 5, "trad": func(_d, i): return i == 4})
	var n1e: Array = rowS.call("N1E", -7.4, 85, -57.9, 10.9)
	var n1e_after := func(d, i, res) -> void:
		if i == 5:
			var p: Dictionary = res.houseRect
			H.laundry.koinobori(d.F, p.hx1 + 0.6 if p.hx1 + 0.6 < d.w / 2.0 - 0.3 else p.hx0 - 0.6, 0, -1.8, 7.0)
	doRow.call(n1e, {"lod": 2, "pri": 2, "gardenSpot": func(_d, i): return i == 1 or i == 4 or i == 7, "trad": func(_d, i): return i == 3, "after": n1e_after})
	var n2w: Array = rowS.call("N2W", -85, -15.7, -72.7, 10.8)
	doRow.call(n2w, {"lod": 1, "pri": 1, "gardenSpot": func(_d, i): return i == 3, "trad": func(_d, i): return i == 1 or i == 5, "back": true, "per": func(_d, _i): return {"backStyle": "block", "backH": 1.1}})
	var n2e: Array = rowS.call("N2E", -8.5, 85, -72.7, 10.8)
	doRow.call(n2e, {"lod": 1, "pri": 1, "gardenSpot": func(_d, i): return i == 2 or i == 6, "trad": func(_d, i): return i == 4 or i == 8, "per": func(_d, _i): return {"backStyle": "block", "backH": 1.1}})

	# --- SWB / SEB back blocks: lane A behind the main-street lots, lane B further out, connectors
	var cX := func(z: float) -> float: return L.street_center_x(z)
	var laneA := func(s: int) -> Array:
		var pts := []
		var z := 1.05
		while z <= 128.01:
			pts.append([cX.call(z) + s * 20.6, z])
			z += 3
		return pts
	H.strip(laneA.call(-1), 1.7, M.asphalt, "#8a8c90", 0.018, 4)
	H.strip(laneA.call(1), 1.7, M.asphalt, "#8a8c90", 0.018, 4)
	H.strip([[-43.5, 1.05], [-43.5, 128]], 1.5, M.asphalt, "#8d8f93", 0.018, 4)
	H.strip([[43.5, 1.05], [43.5, 128]], 1.5, M.asphalt, "#8d8f93", 0.018, 4)
	for zc in [46.0, 96.0]:
		H.strip([[cX.call(zc) - 22.2, zc], [-42.0, zc]], 1.5, M.asphalt, "#8d8f93", 0.02, 4)
		H.strip([[cX.call(zc) + 22.2, zc], [42.0, zc]], 1.5, M.asphalt, "#8d8f93", 0.02, 4)
	var segsA := [[3.0, 44.4], [47.6, 94.4], [97.6, 128.0]]
	for side in [-1, 1]:
		var tag := "SWB" if side < 0 else "SEB"
		for s in segsA.size():
			var za: float = segsA[s][0]
			var zb: float = segsA[s][1]
			var lots: Array = rowE.call(tag + "A" + str(s), func(z: float) -> float: return cX.call(z) + side * 22.3, za, zb, 12, -side, {"slope": func(z: float) -> float: return -atan(L.street_slope_x(z)) * 0})
			# orient with the curve: use the street frame's rotation
			for d in lots:
				var fr: Dictionary = L.street_frame(d.cz, side, 22.3)
				d.F = GBM.Frame.at(gb, fr.x, fr.y, fr.z, fr.rotY)
			doRow.call(lots, {"lod": 1, "pri": 1, "gardenSpot": func(_d, i): return (i + s) % 3 == 1, "trad": func(_d, i): return (i + s * 2) % 4 == 2})
		# lane B row (outer): fewer houses, fields in between
		var lotsB: Array = rowE.call(tag + "B", side * 45.0, 3.0, 128, 13.5, -side)
		doRow.call(lotsB, {"lod": 1, "pri": 0, "skip": func(d, i): return d != null and (i == 3 or i == 8), "gardenSpot": func(_d, i): return i == 5 or i == 10, "trad": func(_d, i): return i % 4 == 1})
		# fields & vacant plots between row A backs and lane B (and the skipped B lots)
		var r = ctx.rng("fields-" + tag)
		var z := 3.2
		while z < 127:
			var ln: float = 12 + r.f() * 12
			var z1 := minf(127.5, z + ln)
			if absf((z + z1) / 2.0 - 46) < ln / 2.0 + 1.6 or absf((z + z1) / 2.0 - 96) < ln / 2.0 + 1.6:
				z = z1 + 0.1
				continue
			var xa: float = -42.1 if side < 0 else cX.call(z) + 34.4
			var xb: float = cX.call(z1) - 34.4 if side < 0 else 42.1
			if xb - xa > 3:
				var kind := "field" if r.f() < 0.45 else ("parking" if r.f() < 0.5 else "vacant")
				_plot(H, r, xa, xb, z + 0.2, z1 - 0.2, kind)
			z = z1 + 0.1
		for i in [3, 8]:
			if i >= lotsB.size():
				continue
			var d: Dictionary = lotsB[i]
			var cz: float = d.cz
			_plot(H, r, -58.4 if side < 0 else 45.2, -45.2 if side < 0 else 58.4, cz - d.w / 2.0 + 0.2, cz + d.w / 2.0 - 0.2, "field" if i == 3 else "parking")

	# ================================================================== far town
	gb.flush(root, "houses")
	var far: Dictionary = Far.build_far_town(H)

	# ================================================================== laundry (dynamic, swaying)
	H.laundry.build()

	# ================================================================== services
	var sort_pick := func(arr: Array, n: int) -> Array:
		T.stable_sort(arr, func(a, b): return b.pri - a.pri)
		var out := []
		for s in arr.slice(0, n):
			var e: Dictionary = s.duplicate()
			e.erase("pri")
			out.append(e)
		return out
	var pub := {
		"gardenSpots": sort_pick.call(services.gardenSpots, 25),
		"bikeSpots": sort_pick.call(services.bikeSpots, 25),
		"wallTops": sort_pick.call(services.wallTops, 60),
	}
	ctx.services["houses"] = pub
	ctx.set_meta("__housesStats", {"far": far.count, "laundry": H.laundry.count})
	return null


# ====================================================================================
#  Special fields / vacant plots
# ====================================================================================
static func _plot(H, r, x0: float, x1: float, z0: float, z1: float, kind: String) -> void:
	var M: Dictionary = H.M
	var P = H.props
	var L = H.L
	var F = GBM.Frame.at(H.gb, 0, 0, 0, 0)
	if kind == "field":  # 畑: soil with green rows, a few stakes and a small shed
		H.ground_rect(F, x0, z0, x1, z1, M.soil, "#c9b89c", 0.02, 1.5)
		var along := (x1 - x0) > (z1 - z0)
		var n: int = floori(((z1 - z0 if along else x1 - x0) - 1) / 0.9)
		for i in n:
			var t := 0.6 + i * 0.9
			var c = r.pick(["#8fb86f", "#7aa564", "#a9c77c", "#6f9a5a"])
			var leafy: bool = r.f() < 0.7
			if along:
				var zz := z0 + t
				H.ground_rect(F, x0 + 0.5, zz - 0.18, x1 - 0.5, zz + 0.18, M.soil, "#b5a283", 0.05, 1.5)
				if leafy:
					var x := x0 + 0.8
					while x < x1 - 0.6:
						F.raw(M.plain, c, H.blob_raw(floori(r.f() * 6), 0), x, L.height_at(x, zz) + 0.12, zz, {"sx": 0.5, "sy": 0.22, "sz": 0.36})
						x += 0.8 + r.f() * 0.3
			else:
				var xx := x0 + t
				H.ground_rect(F, xx - 0.18, z0 + 0.5, xx + 0.18, z1 - 0.5, M.soil, "#b5a283", 0.05, 1.5)
				if leafy:
					var z := z0 + 0.8
					while z < z1 - 0.6:
						F.raw(M.plain, c, H.blob_raw(floori(r.f() * 6), 0), xx, L.height_at(xx, z) + 0.12, z, {"sx": 0.36, "sy": 0.22, "sz": 0.5})
						z += 0.8 + r.f() * 0.3
		# low mesh fence on the lane side + a small shed & hose
		if r.f() < 0.6:
			P.shed(F.sub(x1 - 1.2, 0, z0 + 0.8, 0), 0, L.height_at(x1 - 1.2, z0 + 0.8), 0, r, 1.4)
			H.col(F, x1 - 1.2, z0 + 0.8, 1.6, 1.0, 0, -1, L.height_at(x1 - 1.2, z0 + 0.8) + 2)
		if r.f() < 0.5:  # greenhouse (ビニールハウス) tunnel
			var gx := x0 + 2.5
			var gz0 := z0 + 1
			var gz1 := minf(z1 - 1, z0 + 7)
			var g: float = L.height_at(gx, (gz0 + gz1) / 2.0)
			F.cyl(M.poly, null, 1.3, gz1 - gz0, gx, g, (gz0 + gz1) / 2.0, {"rx": PI / 2.0, "seg": 10, "open": true, "noOutline": true, "shadow": false})
			var z := gz0
			while z <= gz1 + 0.01:
				F.cyl(M.plain, "#c9ccd1", 1.31, 0.03, gx, g, z, {"rx": PI / 2.0, "seg": 10, "open": true})
				z += 1.2
		for k in 4:
			var x: float = x0 + 1 + r.f() * (x1 - x0 - 2)
			var z: float = z0 + 1 + r.f() * (z1 - z0 - 2)
			F.boxB(M.plain, "#b48a62", 0.03, 0.9, 0.03, x, L.height_at(x, z), z)
	elif kind == "parking":  # 月極駐車場 (gravel, rope lines, sign)
		H.ground_rect(F, x0, z0, x1, z1, M.gravel, "#cfc9bd", 0.025, 1.5)
		var along := (x1 - x0) > (z1 - z0)
		var n: int = floori((x1 - x0 if along else z1 - z0) / 2.6)
		for i in n + 1:
			if along:
				var x := x0 + i * (x1 - x0) / n
				H.ground_rect(F, x - 0.05, z0 + 0.3, x + 0.05, z0 + 4.8, M.plain, "#ece8df", 0.035, 1)
			else:
				var z := z0 + i * (z1 - z0) / n
				H.ground_rect(F, x0 + 0.3, z - 0.05, x0 + 4.8, z + 0.05, M.plain, "#ece8df", 0.035, 1)
		var px := x0 + 0.4
		var pz := z1 - 0.4
		var g: float = L.height_at(px, pz)
		F.boxB(M.plain, "#8e949b", 0.06, 1.3, 0.06, px, g, pz)
		F.box(M.atlas, "#ffffff", 0.7, 0.26, 0.03, px, g + 1.3, pz + 0.04, {"uv": {"rect": H.A.rects.kotatsu_sign, "white": H.A.white}})
		for k in 3:
			var x: float = x0 + 1.5 + r.f() * (x1 - x0 - 3)
			var z: float = z0 + 1 + r.f() * (z1 - z0 - 2)
			F.boxB(M.concrete, "#b9b8b2", 0.6, 0.12, 0.15, x, L.height_at(x, z), z, {"uv": {"world": 2}})
	else:  # vacant lot with weeds and a couple of bushes
		H.ground_rect(F, x0, z0, x1, z1, M.lawn, "#b4c98f", 0.02, 2)
		for k in 8:
			var x: float = x0 + 0.8 + r.f() * (x1 - x0 - 1.6)
			var z: float = z0 + 0.8 + r.f() * (z1 - z0 - 1.6)
			var rad: float = 0.25 + r.f() * 0.3
			var flw = "flowers" if r.f() < 0.4 else null
			P.bush(F, x, L.height_at(x, z) - 0.05, z, rad, r, {"pal": "young", "n": 2, "flowers": flw, "fn": 4})
		if r.f() < 0.5:
			var x := (x0 + x1) / 2.0
			var z := (z0 + z1) / 2.0
			P.tree(F, x, L.height_at(x, z), z, 1.3, r, "round")
			H.colC(F, x, z, 0.15, -1, 5)


# ====================================================================================
#  W3: the hero garden house (white cat on the wall, garden sakura leaning over the street)
# ====================================================================================
static func _build_w3(H, F, f: Dictionary) -> Dictionary:
	var ctx = H.ctx
	var L = H.L
	var M: Dictionary = H.M
	var P = H.props
	var r = ctx.rng("W3")
	var SP: Dictionary = L.SPOTS.w3Wall
	var gy := func(x: float, z: float) -> float: return H.gy(F, x, z)
	var res := {"gardenSpots": [], "bikeSpots": [], "wallTops": []}
	var W: float = f.w
	var Dp: float = f.depth
	var wz: float = SP.lz
	var wh: float = SP.h
	var wt := 0.22
	# --- frontage wall: plaster over a stone base, dark flat coping; gate opening at lx -1.8..-0.8
	var segs := [[SP.lx0, -2.1], [-0.5, SP.lx1]]
	var wallC := "#e6dccb"
	var baseC := "#b9b19c"
	var capC := "#6f6b67"
	for sg in segs:
		var a: float = sg[0]
		var b: float = sg[1]
		H.sloped_wall(F, a, b, wz, wh - 0.06, wt, M.plaster, wallC, 3, 3)
		H.sloped_wall(F, a - 0.005, b + 0.005, wz, 0.38, wt + 0.03, M.block, baseC, 1.6, 0.8)
		H.sloped_wall(F, a - 0.03, b + 0.03, wz, wh, wt + 0.08, M.plain, capC, 0, 0, wh - 0.06)
		H.decal(F, "moss", (a + b) / 2.0, gy.call((a + b) / 2.0, wz) + 0.1, (b - a) * 0.95, 0.28, wz + wt / 2.0 + 0.022, "#ffffff")
		H.decal(F, "streak", a + (b - a) * 0.3, gy.call(a, wz) + wh - 0.4, 0.6, 0.7, wz + wt / 2.0 + 0.006, "#ffffff")
		H.col(F, (a + b) / 2.0, wz, b - a, wt + 0.08, 0, gy.call(a, wz) - 1, maxf(gy.call(a, wz), gy.call(b, wz)) + wh)
		var m: Vector3 = F.w((a + b) / 2.0, 0, wz)
		res.wallTops.append({"x": m.x, "z": m.z, "y": snappedf(L.height_at(m.x, m.z) + wh, 0.001), "rotY": F.ry, "len": snappedf(b - a, 0.01)})
	H.decal(F, "crack", 2.6, gy.call(2.6, wz) + 0.75, 0.3, 0.45, wz + wt / 2.0 + 0.007, "#ffffff")
	# gate pillars (wood-capped plaster) + wooden lattice gate (木戸), ajar
	for px in [-1.95, -0.65]:
		var g: float = gy.call(px, wz)
		F.boxB(M.plaster, wallC, 0.3, 1.62, 0.3, px, g - 0.1, wz, {"uv": {"world": 3}})
		F.boxB(M.plain, "#5a4032", 0.38, 0.07, 0.38, px, g + 1.52, wz)
		F.box(M.plain, capC, 0.42, 0.05, 0.42, px, g + 1.6, wz)
		H.col(F, px, wz, 0.32, 0.32, 0, g - 1, g + 1.6)
	P.plate(F.sub(-0.65, 0, wz + 0.15, 0), 0, gy.call(-0.65, wz) + 1.15, 0.0, "plateV1")
	F.box(M.atlas, "#ffffff", 0.09, 0.15, 0.03, -0.65, gy.call(-0.65, wz) + 0.86, wz + 0.165, {"uv": {"rect": H.A.rects.intercom, "white": H.A.white}})
	F.box(M.atlas, "#ffffff", 0.3, 0.24, 0.08, -1.95, gy.call(-1.95, wz) + 1.0, wz + 0.18, {"uv": {"rect": H.A.rects.mailbox_red, "white": H.A.white}})
	for s in [-1, 1]:
		var hinge: float = -1.3 + s * 0.5
		var GF = F.sub(hinge, gy.call(hinge, wz), wz - 0.05, s * 0.9)
		var lw := 0.48
		GF.box(M.plain, "#6b4f3c", lw, 0.05, 0.04, -s * lw / 2.0, 1.1, 0)
		GF.box(M.plain, "#6b4f3c", lw, 0.05, 0.04, -s * lw / 2.0, 0.12, 0)
		for k in 6:
			GF.box(M.plain, "#7a5a43", 0.035, 1.0, 0.035, -s * (0.03 + k * (lw - 0.06) / 5.0), 0.6, 0)
	# --- ground: moss lawn + gravel + stepping stones
	H.ground_rect(F, -W / 2.0 + 0.05, -Dp + 0.05, W / 2.0 - 0.05, wz - wt / 2.0 - 0.02, M.gravel, "#d8d2c6", 0.02, 1.5)
	H.ground_rect(F, -0.2, -4.6, 4.25, wz - wt / 2.0 - 0.05, M.lawn, "#a9c48a", 0.03, 2)
	H.ground_rect(F, -4.25, -4.4, -2.3, -0.5, M.lawn, "#b0c890", 0.03, 2)
	H.ground_rect(F, -W / 2.0 + 0.02, wz - wt / 2.0, W / 2.0 - 0.02, 0, M.concrete, "#c9c7c0", 0.03, 2)
	P.stepping_stones(F, -1.3, -0.6, -1.25, -3.6, gy, r)
	# --- house: traditional 2F, plaster + dark wood trim, hip kawara roof with 下屋 skirt
	var hx0 := -4.0
	var hx1 := 3.9
	var hz0 := -12.4
	var hz1 := -5.3
	var hcx := (hx0 + hx1) / 2.0
	var hcz := (hz0 + hz1) / 2.0
	var hw := hx1 - hx0
	var hd := hz1 - hz0
	var HF = F.sub(hcx, 0, hcz, 0)
	var gmin := 1e9
	var gmax := -1e9
	for xz in [[hx0, hz0], [hx1, hz0], [hx0, hz1], [hx1, hz1]]:
		var g: float = gy.call(xz[0], xz[1])
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
	var S := {
		"rng": r, "w": hw, "d": hd, "floors": 2, "fh": 2.85, "lod": 2, "floorY": gmax + 0.55, "groundMin": gmin, "groundFront": gy.call(hcx, hz1 + 1), "baseY": HF.origin().y,
		"wall": {"kind": "plaster", "color": "#ede3cf"}, "wall2": null, "trim": "#5a4032", "traditional": true,
		"roof": {"type": "hip", "mat": "kawara", "color": "#4f555f", "pitch": 0.46, "over": 0.62}, "ridgeColor": "#4a4f58",
		"frameColor": "#5e4636", "sillColor": "#5e4636", "grilleColor": "#6b5a4c", "fasciaColor": "#5a4032", "soffitColor": "#e9e1cf", "gutterColor": "#6b5242", "flashColor": "#8a8f96", "foundColor": "#bdbcb5",
		"shutterColor": "#8e8a82", "shutterStyle": "tobukuro", "shutterClosed": 0, "hoods": false, "hoodColor": "#6b7079",
		"belt": true, "cornerTrim": false, "porchColor": "#b9b1a4", "canopyColor": "#5a4032", "balconySlab": "#d8d2c4", "railColor": "#5e4636", "poleColor": "#8fb3c9",
		"bigFront": true, "antenna": true, "solar": false, "propane": false, "interiors": ["int_shoji", "int_lace", "int_shoji", "int_room"],
		"door": {"u": -1.3 - hcx, "style": "door_slide", "canopy": "none", "porchD": 1.2}, "skirt": {"depth": 0.95}, "plate": "plateV1", "gatePlate": true,
	}
	S.ridgeColor = "#4a4f58"
	House.build_house(H, HF, S)
	# futon on the 2F window railing + wind chime under the skirt eave
	var FF = HF.sub(0, 0, hd / 2.0, 0)
	P.futon(FF, 1.9, S.floorY + 2.85 + 1.03, 0.24, r)
	H.laundry.chime(FF, 2.9, S.floorY + 2.85 - 0.05, 0.8)
	# --- garden: sakura spot kept open (lx 1.8, lz -2.2, r 1.5); pine, lantern, azaleas, bonsai, nandina
	var sk := {"x": 1.8, "z": -2.2}
	var clear := func(x: float, z: float, rr: float) -> bool: return Vector2(x - sk.x, z - sk.z).length() > 1.5 + rr
	P.pine(F, 3.35, gy.call(3.35, -3.9), -3.9, 1.25, r)
	P.lantern(F, -3.35, gy.call(-3.35, -2.6), -2.6)
	for b in [[-3.9, -0.75, 0.42, "azalea"], [-3.1, -0.8, 0.36, "azalea"], [-2.45, -0.8, 0.3, null], [3.9, -0.8, 0.4, "azalea"], [-0.1, -0.85, 0.32, "azalea"], [-3.9, -4.2, 0.38, null]]:
		var x: float = b[0]
		var z: float = b[1]
		var s: float = b[2]
		var fl = b[3]
		if clear.call(x, z, s):
			P.bush(F, x, gy.call(x, z), z, s, r, {"pal": "green" if fl else "dark", "flowers": fl, "fn": 8})
	P.nandina(F, -0.3, gy.call(-0.3, -1.4), -1.4, 1.0, r)
	P.bonsai_shelf(F, -3.1, gy.call(-3.1, -4.5), -4.5, r)
	P.bush(F, 3.6, gy.call(3.6, -5.0), -5.0, 0.3, r, {"pal": "green", "flowers": "hydrangea", "fn": 5, "fsize": 0.16})
	# stones around the future tree
	for k in 5:
		var a: float = k * 1.3 + 0.4
		var d: float = 1.25 + r.f() * 0.3
		var x: float = sk.x + cos(a) * d
		var z: float = sk.z + sin(a) * d
		if z < wz - 0.4 and z > -4.6:
			F.raw(M.concrete, "#a8a59c", H.blob_raw(k, 0), x, gy.call(x, z) + 0.05, z, {"sx": 0.35, "sy": 0.18, "sz": 0.3, "ry": a})
	var gp: Vector3 = F.w(sk.x, 0, sk.z)
	res.gardenSpots.append({"x": gp.x, "z": gp.z, "r": 1.5})
	# --- side + back boundaries (neighbours are shops)
	Lot.boundary_seg_z(H, F, -W / 2.0 + 0.07, wz - 0.1, -Dp + 0.08, "block", 1.2, "#c9c7c0", r, gy)
	Lot.boundary_seg_z(H, F, W / 2.0 - 0.07, wz - 0.1, -Dp + 0.08, "block", 1.2, "#c9c7c0", r, gy)
	Lot.boundary_seg(H, F, -W / 2.0 + 0.07, W / 2.0 - 0.07, -Dp + 0.08, "block", 1.2, "#c9c7c0", r, gy, 2, null, false)
	# bike parked along the house front, right of the entrance (clear of the sakura circle and the porch)
	var bp: Vector3 = F.w(1.3, 0, -4.72)
	res.bikeSpots.append({"x": bp.x, "z": bp.z, "rotY": F.ry + PI / 2.0})
	return res
