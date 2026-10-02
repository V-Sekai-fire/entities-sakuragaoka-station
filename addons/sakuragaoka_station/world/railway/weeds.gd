# railway/weeds.js: corridor weeds as one instanced crossed-card mesh with an atlas cell per instance
# and a wind-sway vertex patch. The per-instance cell rectangles sit in geometry.user_data.aCell.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

## Atlas cells: 0 tuft, 1 tall grass, 2 dandelion, 3 clocks, 4 rapeseed, 5 daisy, 6 henbit, 7 horsetail.
const SIZE := [[0.42, 0.3], [0.8, 0.8], [0.34, 0.24], [0.32, 0.32], [0.72, 0.85], [0.48, 0.5], [0.34, 0.2], [0.42, 0.4]]


static func weed_material(ctx, map):
	var m = ctx.mat.foliage("#ffffff", map, {"name": "rw-weeds", "paint": 0.04, "alphaTest": 0.42})
	if m.user_data.get("rwSway"):
		return m
	m.user_data["rwSway"] = true
	return m


static func cross_card() -> T.Geometry:
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	for q in 2:
		var a := q * PI / 2.0
		var cx := cos(a) * 0.5
		var cz := -sin(a) * 0.5
		var fn := [sin(a), 0.0, cos(a)]
		var base := pos.size() / 3
		for sy in [[-1, 0], [1, 0], [1, 1], [-1, 1]]:
			var s: float = sy[0]
			pos.append(cx * s); pos.append(sy[1]); pos.append(cz * s)
			var n := Vector3(fn[0] * 0.3, 1, fn[2] * 0.3).normalized()
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			uv.append(0.0 if s < 0 else 1.0); uv.append(sy[1])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	return g


static func build_weeds(ctx, root, TX, E: Dictionary, track: Dictionary, cat: Dictionary, side: Dictionary) -> Dictionary:
	var L = ctx.L
	var r = ctx.rng("rw-weeds")
	var items := []
	var pick_w := func(list: Array) -> int:
		var s := 0.0
		for it in list:
			s += it[1]
		var v: float = r.f() * s
		for it in list:
			v -= it[1]
			if v <= 0.0:
				return it[0]
		return list[0][0]
	var add := func(x: float, y: float, z: float, cell: int, scale: float = 1.0) -> void:
		var w: float = SIZE[cell][0]
		var h: float = SIZE[cell][1]
		var kk: float = scale * (0.75 + r.f() * 0.5)
		var it := {"x": x, "y": y - 0.015, "z": z}
		it["ry"] = r.f() * PI
		it["sx"] = w * kk * (0.85 + r.f() * 0.3)
		it["sy"] = h * kk
		it["sz"] = w * kk * (0.85 + r.f() * 0.3)
		it["cell"] = cell
		items.append(it)
	var in_cross := func(x: float, m: float = 0.2) -> bool:
		return x > E.cross[0] - m and x < E.cross[1] + m
	var in_walk := func(x: float, m: float = 0.2) -> bool:
		return x > E.walk[0] - m and x < E.walk[1] + m
	var in_station := func(x: float) -> bool:
		return x > -7.3 and x < 50.3
	var gy := func(x: float, z: float) -> float:
		return L.height_at(x, z)
	var zs: Callable = side.zs
	var S: Dictionary = side.S

	var MIX_FENCE := [[1, 30], [0, 26], [7, 10], [5, 12], [2, 8], [3, 4], [6, 6], [4, 4]]
	var MIX_EDGE := [[0, 40], [2, 16], [6, 16], [7, 10], [5, 8], [3, 8]]
	var MIX_BED := [[0, 55], [6, 22], [2, 14], [3, 9]]
	var NANOHANA := [[-82, -64], [-44, -36], [58, 70], [96, 112], [-150, -128], [140, 160], [-240, -205], [205, 250], [-330, -300], [300, 340]]
	var in_nano := func(x: float) -> bool:
		for ab in NANOHANA:
			if x > ab[0] and x < ab[1]:
				return true
		return false

	for sgn in [1.0, -1.0]:
		var zF: float = zs.call(S.fence, sgn)
		for ab in side.STRIP_X:
			var x: float = ab[0] + 0.3
			while x < ab[1]:
				var near := absf(x) < 175.0
				if not near and r.f() > 0.3:
					x += 0.34
					continue
				var n_fence := 2 if near else 1
				for i in n_fence:
					var z: float = zF - sgn * (0.08 + pow(r.f(), 1.6) * 1.05)
					var cell: int = 4 if (in_nano.call(x) and r.f() < 0.42) else pick_w.call(MIX_FENCE)
					add.call(x + (r.f() - 0.5) * 0.3, gy.call(x, z), z, cell, 1.0 if near else 1.25)
				if near:
					if side.inRanges.call(x, side.DETAIL_X) and r.f() < 0.28:
						var z: float = zs.call(S.drain, sgn) - sgn * (0.28 + r.f() * 0.15)
						add.call(x, gy.call(x, z), z, pick_w.call(MIX_EDGE), 0.8)
					if r.f() < 0.1:
						var z: float = zs.call(-38.2 + r.f() * 3.0, sgn)
						add.call(x, gy.call(x, z), z, pick_w.call(MIX_EDGE), 0.7)
					if side.inRanges.call(x, side.DETAIL_X) and r.f() < 0.12:
						var z: float = zs.call(S.trough, sgn) + sgn * (0.22 + r.f() * 0.1)
						add.call(x, gy.call(x, z), z, pick_w.call(MIX_EDGE), 0.65)
				x += 0.34
	var x := -250.0
	while x < 260.0:
		if not (in_cross.call(x) or in_walk.call(x) or (x > -7.3 and x < 46.3)):
			var near := absf(x) < 175.0
			for sgn in [1.0, -1.0]:
				if r.f() > (0.62 if near else 0.2):
					continue
				var d: float = 3.35 + r.f() * 0.62
				var z: float = -43.0 + sgn * d
				add.call(x + (r.f() - 0.5) * 0.4, E.ballastY.call(z), z, pick_w.call(MIX_EDGE), 0.72)
		x += 0.5
	x = -200.0
	while x < 220.0:
		if not (in_cross.call(x) or in_walk.call(x)):
			var near := absf(x) < 150.0
			var p_between := 0.14 if in_station.call(x) else (0.3 if near else 0.08)
			if r.f() < p_between:
				var z: float = -43.0 + (r.f() - 0.5) * 1.8
				if not track.onSleeper.call(x, z) and not track.nearRail.call(x, z, 0.12) and not (x > track.TX0 and x < track.TX1 and absf(z - E.xo.zc.call(x)) < 1.2):
					add.call(x, E.ballastY.call(z), z, pick_w.call(MIX_BED), 0.6)
			if near and r.f() < 0.05:
				var zT: float = E.zA if r.f() < 0.5 else E.zB
				var z: float = zT + (r.f() - 0.5) * 1.9
				if not track.onSleeper.call(x, z, 0.05) and not track.nearRail.call(x, z, 0.14):
					add.call(x, E.ballastY.call(z), z, 0 if r.f() < 0.7 else 6, 0.45)
		x += 0.5
	for p in cat.poles:
		if absf(p.x) > 200.0 or in_cross.call(p.x, 1.0) or in_walk.call(p.x, 1.0):
			continue
		var spots: Array = [[p.x, -43.0]] if p.type == "C" else [[p.x, cat.zSouthPole], [p.x, cat.zNorthPole]]
		for sp in spots:
			for i in 5:
				var a: float = r.f() * 6.28
				var d: float = 0.36 + r.f() * 0.25
				var px: float = sp[0] + cos(a) * d
				var pz: float = sp[1] + sin(a) * d * (0.5 if p.type == "C" else 1.0)
				var y: float = E.ballastY.call(pz) if p.type == "C" else gy.call(px, pz)
				add.call(px, y, pz, pick_w.call(MIX_BED) if p.type == "C" else pick_w.call(MIX_EDGE), 0.75)

	var geo := cross_card()
	var n := items.size()
	var cells := PackedFloat32Array()
	cells.resize(n * 4)
	for i in n:
		var c: int = items[i].cell % 4
		var row: int = items[i].cell / 4
		cells[i * 4] = c * 0.25 + 0.004
		cells[i * 4 + 1] = 1.0 - (row + 1) * 0.5 + 0.004
		cells[i * 4 + 2] = 0.25 - 0.008
		cells[i * 4 + 3] = 0.5 - 0.008
	geo.user_data["aCell"] = cells
	var m := T.InstancedMesh.new(geo, weed_material(ctx, TX.weeds), n)
	for i in n:
		var it: Dictionary = items[i]
		m.set_matrix_at(i, T.compose(Vector3(it.x, it.y, it.z), Quaternion(Vector3.UP, it.ry), Vector3(it.sx, it.sy, it.sz)))
	m.cast_shadow = false
	m.receive_shadow = true
	m.name = "rw-weeds"
	m.frustum_culled = true
	ctx.no_outline(m)
	root.add(m)
	return {"count": n}
