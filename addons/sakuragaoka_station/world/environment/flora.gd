# environment/flora.js: grass tufts, weeds, wildflowers, flat ground-cover patches and reeds.
# Instanced alpha cards that sway with the wind, chunked by area so frustum culling works.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")
const Levee = preload("res://addons/sakuragaoka_station/world/environment/levee.gd")
const Water = preload("res://addons/sakuragaoka_station/world/environment/water.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

const TUFT := {"short": 0, "tall": 1, "weed": 2, "mixed": 3}
const FLW := {"dandelion": 0, "puff": 1, "clover": 2, "violet": 3, "nano": 4, "henbit": 5, "fleabane": 6, "speedwell": 7}
const MAT := {"clover": 0, "speedwell": 1, "moss": 2, "rosette": 3}
const FLW_SIZE := {0: [0.24, 0.22], 1: [0.24, 0.26], 2: [0.2, 0.17], 3: [0.16, 0.13], 4: [0.55, 0.78], 5: [0.2, 0.22], 6: [0.34, 0.42], 7: [0.24, 0.12]}


static func build_flora(ctx, C, tx, env: Dictionary) -> Dictionary:
	return Flora.new(ctx, C, tx, env).build()


class Flora extends RefCounted:
	var ctx
	var C
	var tx
	var env: Dictionary
	var r: Rng
	var chunks := {}
	var TUFT := {"short": 0, "tall": 1, "weed": 2, "mixed": 3}
	var FLW := {"dandelion": 0, "puff": 1, "clover": 2, "violet": 3, "nano": 4, "henbit": 5, "fleabane": 6, "speedwell": 7}
	var MAT := {"clover": 0, "speedwell": 1, "moss": 2, "rosette": 3}
	var _park_chunk := "park"
	const LEVEE_FLOWERS := [[0, 4.0], [1, 1.0], [2, 3.0], [3, 1.5], [5, 2.0], [7, 1.5], [6, 1.0]]
	const TOWN_FLOWERS := [[0, 4.0], [1, 1.2], [2, 3.0], [3, 1.0], [5, 2.5], [7, 2.0], [6, 1.6], [4, 0.6]]

	func _init(c, common, textures, e: Dictionary) -> void:
		ctx = c
		C = common
		tx = textures
		env = e
		r = c.rng("env-flora")

	func ground(x: float, z: float) -> float:
		return C.terrain_h(x, z)

	func chunk(name: String) -> Dictionary:
		if not chunks.has(name):
			chunks[name] = {"tuft": [], "flower": [], "mat": [], "reed": []}
		return chunks[name]

	func near_stuff(x: float, z: float) -> bool:
		for s in Levee.STAIRS:
			if absf(x - s.x) < s.w / 2.0 + 0.5 and z < -83.3 and z > -91.8:
				return true
		for b in Levee.BENCHES:
			if absf(x - b.x) < 1.3 and z < -93.2 and z > -94.8:
				return true
		for lx in Levee.LAMPS:
			if absf(x - lx) < 0.5 and z < -93.6 and z > -94.8:
				return true
		return absf(x - (-8.9)) < 1.4 and z < -93.6 and z > -94.8

	func tint(a: float = 0.12, g: float = 0.0) -> Array:
		var k := 1.0 - a / 2.0 + r.f() * a
		var c0 := k * (1.0 - g * 0.5 + r.f() * g)
		var c2 := k * (0.95 + r.f() * 0.08)
		return [c0, k, c2]

	func add_tuft_to(c: Dictionary, x: float, z: float, s: float = 1.0, kind = null, y = null) -> void:
		var cell: int
		if kind != null:
			cell = kind
		elif r.f() < 0.45:
			cell = TUFT.short
		elif r.f() < 0.5:
			cell = TUFT.mixed
		elif r.f() < 0.6:
			cell = TUFT.tall
		else:
			cell = TUFT.weed
		var w := (0.55 if cell == TUFT.weed else 0.5) * s * (0.7 + r.f() * 0.6)
		var h := (0.55 if cell == TUFT.tall else (0.36 if cell == TUFT.weed else 0.3)) * s * (0.7 + r.f() * 0.6)
		var yy: float = y if y != null else ground(x, z)
		var rot := r.f() * PI
		c.tuft.append({"x": x, "z": z, "y": yy, "w": w, "h": h, "rot": rot, "cell": cell, "sway": 1.0 if cell == TUFT.tall else 0.65, "col": tint(0.16, 0.1)})

	func add_flower_to(c: Dictionary, x: float, z: float, cell: int, s: float = 1.0, y = null) -> void:
		var wh: Array = FLW_SIZE[cell]
		var k := s * (0.75 + r.f() * 0.5)
		var yy: float = y if y != null else ground(x, z)
		var h: float = wh[1] * k * (0.85 + r.f() * 0.3)
		var rot := r.f() * PI
		var sway := 1.0 if cell == FLW.nano else (0.9 if cell == FLW.fleabane else 0.6)
		c.flower.append({"x": x, "z": z, "y": yy, "w": wh[0] * k, "h": h, "rot": rot, "cell": cell, "sway": sway, "col": tint(0.1)})

	func add_mat_to(c: Dictionary, x: float, z: float, cell: int, s: float = 1.0, y = null) -> void:
		var yy: float = (y if y != null else ground(x, z)) + 0.012 + r.f() * 0.006
		var w := (0.35 + r.f() * 0.35) * s
		var rot := r.f() * PI * 2.0
		c.mat.append({"x": x, "z": z, "y": yy, "w": w, "rot": rot, "cell": cell, "col": tint(0.1)})

	func add_reed_to(c: Dictionary, x: float, z: float, y: float, s: float = 1.0) -> void:
		var cell := 1 if r.f() < 0.3 else 0
		var w := (0.8 + r.f() * 0.5) * s
		var h := (1.3 + r.f() * 0.9) * s * (1.1 if cell else 0.9)
		var rot := r.f() * PI
		c.reed.append({"x": x, "z": z, "y": y, "w": w, "h": h, "rot": rot, "cell": cell, "sway": 1.2, "col": tint(0.12)})

	# the park hook's API (F.addTuft ... in the original), all into the "park" chunk
	func add_tuft(x: float, z: float, s: float, k, y) -> void:
		add_tuft_to(chunk(_park_chunk), x, z, s, k, y)

	func add_flower(x: float, z: float, cell: int, s: float, y) -> void:
		add_flower_to(chunk(_park_chunk), x, z, cell, s, y)

	func add_mat(x: float, z: float, cell: int, s: float, y) -> void:
		add_mat_to(chunk(_park_chunk), x, z, cell, s, y)

	func pick_w(list: Array) -> int:
		var total := 0.0
		for e in list:
			total += e[1]
		var t := r.f() * total
		var acc := 0.0
		for e in list:
			acc += e[1]
			if t <= acc:
				return e[0]
		return list[0][0]

	static func levee_chunk(x: float) -> String:
		return "levW" if x < -45.0 else ("levC" if x < 45.0 else "levE")

	static func nano_patch(x: float, z: float) -> float:
		return Common.fbm(x / 9.0, z / 3.0, 2, 501)

	static func town_chunk(x: float, z: float) -> String:
		return "townN" if z < -34.0 else ("townSW" if x < 0.0 else "townSE")

	func open_ok(x: float, z: float) -> bool:
		if z > 128.5 or z < -83.6 or absf(x) > 94.0: return false
		if C.in_corridor(x, z, 0.25): return false
		if C.owned_by_others(x, z, 0.2) != null: return false
		if env.get("isParkMound") != null and env.isParkMound.call(x, z): return false
		var A: Dictionary = Common.ALLOT_W
		if x > A.x0 - 0.6 and x < A.x1 + 0.6 and z > A.z0 - 0.6 and z < A.z1 + 0.6: return false
		var N: Dictionary = Common.NANO_E
		if x > N.x0 and x < N.x1 and z > N.z0 and z < N.z1: return false
		var V: Dictionary = Common.VACANT_W
		if x > V.x0 and x < -76.0 and z > -13.5 and z < V.z1: return r.f() < 0.08
		if Common.path_dist(x, z).d < 1.1: return false
		return true

	func build() -> Dictionary:
		var BR: Dictionary = Common.BRIDGE
		var WATER_Y: float = Water.water_y(ctx.L)
		# ------------------------------------------------------- A/B: levee slopes (dense)
		for i in 9000:
			var x := -132.0 + r.f() * 264.0
			var side := "town" if r.f() < 0.55 else "river"
			var z := -84.3 - r.f() * 6.2 if side == "town" else -95.8 - r.f() * 3.0
			if near_stuff(x, z):
				continue
			if absf(z + 90.8) < 0.55 or absf(z + 95.3) < 0.45:
				continue
			var c := chunk(levee_chunk(x))
			var u := r.f()
			if side == "river":
				var np := nano_patch(x, z)
				if np > 0.5 and u < 0.62:
					add_flower_to(c, x, z, FLW.nano, 1.0 + (np - 0.5))
					continue
				if u < 0.75:
					add_tuft_to(c, x, z, 1.0)
					continue
				if u < 0.9:
					add_flower_to(c, x, z, pick_w(LEVEE_FLOWERS))
					continue
				add_mat_to(c, x, z, MAT.clover if r.f() < 0.5 else MAT.rosette)
			else:
				var np := nano_patch(x + 400.0, z)
				if np > 0.62 and u < 0.35:
					add_flower_to(c, x, z, FLW.nano, 0.9)
					continue
				if u < 0.36:
					var kind: int = TUFT.short if r.f() < 0.7 else TUFT.mixed
					add_tuft_to(c, x, z, 0.8, kind)
					continue
				if u < 0.8:
					add_flower_to(c, x, z, pick_w(LEVEE_FLOWERS))
					continue
				add_mat_to(c, x, z, pick_w([[MAT.clover, 3.0], [MAT.speedwell, 1.5], [MAT.rosette, 2.0], [MAT.moss, 1.0]]))
		var x := -130.0
		while x < 130.0:
			var z1 := -91.35 - r.f() * 0.25
			var z2 := -94.65 + r.f() * 0.25
			for z in [z1, z2]:
				if near_stuff(x, z) or r.f() < 0.3:
					continue
				add_tuft_to(chunk(levee_chunk(x)), x, z, 0.6, TUFT.short)
			x += 0.7 + r.f() * 0.9
		# ------------------------------------------------------- C: levee beyond the play area
		for i in 1900:
			var west := r.f() < 0.5
			var px := -135.0 - r.f() * 230.0 if west else 135.0 + r.f() * 230.0
			if absf(px - BR.x) < 7.0:
				continue
			var pz := -84.5 - r.f() * 6.0 if r.f() < 0.5 else -95.8 - r.f() * 3.0
			var c := chunk("levFar")
			if pz < -95.0 and nano_patch(px, pz) > 0.45:
				add_flower_to(c, px, pz, FLW.nano, 1.3)
			elif r.f() < 0.6:
				add_tuft_to(c, px, pz, 1.4)
			else:
				add_flower_to(c, px, pz, FLW.dandelion, 1.3)
		# ------------------------------------------------------- D: reeds at the waterline + gravel bar
		x = -150.0
		while x < 150.0:
			if not (absf(x - Water.STONES_X) < 1.5 or absf(x - Water.WEIR_X) < 3.0):
				if Common.fbm(x / 7.0, 1.3, 2, 511) > 0.52:
					add_reed_to(chunk("reedN"), x, -99.8 - r.f() * 0.5, WATER_Y - 0.05, 0.9)
				if Common.fbm(x / 9.0, 4.1, 2, 512) > 0.38:
					var rz := -117.1 - r.f() * 0.8
					var ry := WATER_Y - 0.05 + r.f() * 0.05
					add_reed_to(chunk("reedF"), x, rz, ry, 1.1)
					if r.f() < 0.5:
						add_reed_to(chunk("reedF"), x + 0.2, -117.7 - r.f() * 0.6, WATER_Y + 0.1, 1.0)
			x += 0.35 + r.f() * 0.9
		for i in 42:
			var a := r.f() * PI * 2.0
			var d := sqrt(r.f())
			add_reed_to(chunk("reedF"), 26.0 + cos(a) * d * 7.5, -112.4 + sin(a) * d * 1.3, WATER_Y - 0.02, 0.85)
		# ------------------------------------------------------- E: far bank verge
		for i in 1500:
			var px := -220.0 + r.f() * 440.0
			var pz := -119.1 - r.f() * 1.3
			if absf(px - BR.x) < 8.0:
				continue
			var c := chunk("farbank")
			if Common.fbm(px / 14.0, 2.2, 2, 521) > 0.45 and r.f() < 0.7:
				add_flower_to(c, px, pz, FLW.nano, 1.2)
			elif r.f() < 0.75:
				add_tuft_to(c, px, pz, 1.2)
			else:
				add_flower_to(c, px, pz, FLW.dandelion, 1.1)
		for e in env.get("nanoEdges", []):
			if e.z < -175.0 or absf((e.x0 + e.x1) / 2.0) > 260.0:
				continue
			var ex: float = e.x0
			while ex < e.x1:
				add_flower_to(chunk("farbank"), ex, e.z - 0.3 - r.f() * 0.8, FLW.nano, 1.25, e.y)
				ex += 0.45 + r.f() * 0.5
		# ------------------------------------------------------- F: open ground in / around the town
		for i in 26000:
			var px := -94.0 + r.f() * 188.0
			var pz := -84.0 + r.f() * 212.5
			if not open_ok(px, pz):
				continue
			var rd: float = C.road_dist(px, pz)
			var verge := rd > 0.2 and rd < 1.6
			var wall: bool = C.owned_by_others(px, pz, 0.9) != null
			var V: Dictionary = Common.VACANT_W
			var vacant: bool = px > V.x0 and px < V.x1 and pz > V.z0 and pz < V.z1
			var keep := 0.9 if verge else (0.75 if wall else (0.55 if vacant else 0.2))
			if r.f() > keep:
				continue
			var c := chunk(town_chunk(px, pz))
			var u := r.f()
			if vacant and u < 0.4:
				var kind: int = TUFT.tall if r.f() < 0.5 else TUFT.weed
				add_tuft_to(c, px, pz, 1.35, kind)
				continue
			if u < 0.42:
				add_tuft_to(c, px, pz, 0.85 if verge else 1.0)
			elif u < 0.86:
				add_flower_to(c, px, pz, pick_w(TOWN_FLOWERS))
			else:
				add_mat_to(c, px, pz, pick_w([[MAT.clover, 3.0], [MAT.speedwell, 2.0], [MAT.rosette, 2.0], [MAT.moss, 2.0]]))
		# ------------------------------------------------------- I: small nanohana field (east strip)
		var N: Dictionary = Common.NANO_E
		var nx: float = N.x0 + 0.4
		while nx < N.x1 - 0.3:
			var nz: float = N.z0 + 0.4
			while nz < N.z1 - 0.3:
				var jx := nx + (r.f() - 0.5) * 0.35
				var jz := nz + (r.f() - 0.5) * 0.35
				if absf(jz - (N.z0 + N.z1) / 2.0) >= 0.5:
					add_flower_to(chunk("nanoField"), jx, jz, FLW.nano, 0.9 + Common.fbm(jx / 5.0, jz / 5.0, 2, 531) * 0.35)
				nz += 0.62
			nx += 0.6
		# ------------------------------------------------------- park extras (the park's hook)
		if env.get("parkFlora") != null:
			env.parkFlora.call(self)
		# ------------------------------------------------------- instanced meshes
		var kinds := {
			"tuft": {"geo": card_geo(3), "mat": Shaders.sway_foliage(ctx, tx.tufts, [0.25, 1], "tufts"), "flat": false},
			"flower": {"geo": card_geo(2), "mat": Shaders.sway_foliage(ctx, tx.flowers, [0.25, 0.5], "flowers"), "flat": false},
			"mat": {"geo": flat_geo(), "mat": Shaders.sway_foliage(ctx, tx.mats, [0.5, 0.5], "mats", {"alphaTest": 0.45}), "flat": true},
			"reed": {"geo": card_geo(3), "mat": Shaders.sway_foliage(ctx, tx.reeds, [0.5, 1], "reeds"), "flat": false},
		}
		var count := 0
		var meshes := 0
		var tris := 0
		for name in chunks:
			var c: Dictionary = chunks[name]
			for kind in ["tuft", "flower", "mat", "reed"]:
				var list: Array = c[kind]
				if list.is_empty():
					continue
				var K: Dictionary = kinds[kind]
				var geo: T.Geometry = (K.geo as T.Geometry).clone()
				var im := T.InstancedMesh.new(geo, K.mat, list.size())
				for i in list.size():
					var it: Dictionary = list[i]
					if K.flat:
						var n: Array = C.terrain_normal(it.x, it.z)
						var q := T.quat_from_unit_vectors(Vector3.UP, Vector3(n[0], n[1], n[2])) * Quaternion(Vector3.UP, it.rot)
						im.set_matrix_at(i, T.compose(Vector3(it.x, it.y, it.z), q, Vector3(it.w, 1, it.w)))
					else:
						im.set_matrix_at(i, T.compose(Vector3(it.x, it.y - 0.02, it.z), Quaternion(Vector3.UP, it.rot), Vector3(it.w, it.h, it.w)))
					im.set_color_at(i, Color(it.col[0], it.col[1], it.col[2]))
				im.cast_shadow = false
				im.receive_shadow = not (kind == "flower" and (name == "nanoField" or name == "farbank" or name == "levFar"))
				im.name = "env-flora-%s-%s" % [name, kind]
				ctx.no_outline(im)
				ctx.add_static(im)
				count += list.size()
				meshes += 1
				tris += list.size() * (geo.index.size() / 3)
		return {"count": count, "meshes": meshes, "tris": tris}

	static func card_geo(n: int) -> T.Geometry:
		var pos := PackedFloat32Array()
		var uv := PackedFloat32Array()
		var nrm := PackedFloat32Array()
		var idx := PackedInt32Array()
		for q in n:
			var a := float(q) / n * PI
			var c := cos(a) * 0.5
			var s := sin(a) * 0.5
			var b := pos.size() / 3
			pos.append_array([-c, 0, -s, c, 0, s, c, 1, s, -c, 1, -s])
			uv.append_array([0, 0, 1, 0, 1, 1, 0, 1])
			for v in 4:
				nrm.append_array([0, 1, 0])
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_attribute("normal", T.Attr.new(nrm, 3))
		g.set_attribute("uv", T.Attr.new(uv, 2))
		g.set_index(idx)
		return g

	static func flat_geo() -> T.Geometry:
		var g := Geo.plane(1, 1)
		g.rotate_x(-PI / 2.0)
		var nr: T.Attr = g.attributes.normal
		for i in nr.count():
			nr.set_xyz(i, 0, 1, 0)
		return g
