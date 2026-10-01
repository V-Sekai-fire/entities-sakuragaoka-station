# sakura/bases.js: tree bases. Square tree pits, low stone rings and natural soil patches, each with
# grass tufts, small wild flowers and moss; and the shrine tree's shimenawa (sacred rope with shide).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const U = preload("res://addons/sakuragaoka_station/world/sakura/util.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

## flora atlas cells (u0, v0) in the 2x2 flora texture
const FL := {"grass": [0.0, 0.5], "dandelion": [0.5, 0.5], "white": [0.0, 0.0], "violet": [0.5, 0.0]}
## ground atlas cells (u0, width 0.5) in the 2x1 ground texture
const GROUND := {"soil": [0.0, 0.0], "moss": [0.5, 0.0]}


class BaseBuilder extends RefCounted:
	var ctx
	var L
	var M: Dictionary
	var R: Rng
	var flora := U.GeoBuilder.new()
	var ground := U.GeoBuilder.new()
	var stones := U.GeoBuilder.new()
	var kit_group := T.Group.new()
	var kit
	var grass_cols := []
	var stone_cols := []
	var moss_col := []
	var colliders := []

	func _init(c, m: Dictionary) -> void:
		ctx = c
		L = c.L
		M = m
		R = c.rng("sakura-bases")
		kit_group.name = "sakura-bases"
		kit = c.kit(kit_group)
		for h in ["#e9f0dc", "#f4f6e8", "#dfe8cf", "#ecefd8"]:
			grass_cols.append(U.hex(h))
		for h in ["#aaa69c", "#9d998f", "#b5b0a4", "#a39d92", "#b9b4a9"]:
			stone_cols.append(U.hex(h))
		moss_col = U.hex("#8d9d68")

	func H(x: float, z: float) -> float:
		return L.height_at(x, z)

	func tuft(x: float, z: float, y: float, h: float, cell: String, rot: float) -> void:
		var grass := cell == "grass"
		var w := h * (1.05 if grass else 0.9)
		var col: Array = grass_cols[floori(R.f() * grass_cols.size())] if grass else [0.95, 0.95, 0.95]
		var uv: Array = FL[cell]
		for q in 2:
			var a := rot + q * PI / 2.0
			var cx := cos(a) * w / 2.0
			var cz := sin(a) * w / 2.0
			var b := flora.count
			# normals point up so both faces read like lit ground
			flora.v(x - cx, y - 0.02, z - cz, 0, 1, 0, uv[0], uv[1], col[0], col[1], col[2])
			flora.v(x + cx, y - 0.02, z + cz, 0, 1, 0, uv[0] + 0.5, uv[1], col[0], col[1], col[2])
			flora.v(x + cx, y + h, z + cz, 0, 1, 0, uv[0] + 0.5, uv[1] + 0.5, col[0], col[1], col[2])
			flora.v(x - cx, y + h, z - cz, 0, 1, 0, uv[0], uv[1] + 0.5, col[0], col[1], col[2])
			flora.t(b, b + 1, b + 2)
			flora.t(b, b + 2, b + 3)

	## A flat decal patch draped on a surface function (soil or moss).
	func patch(cx: float, cz: float, rad: float, cell: Array, y_fn: Callable, rot: float = 0.0, tint: Array = [1.0, 1.0, 1.0], lift: float = 0.022) -> void:
		var n := 6
		var b := ground.count
		var c := cos(rot)
		var s := sin(rot)
		for i in n + 1:
			for j in n + 1:
				var u := float(i) / n
				var v := float(j) / n
				var lx := (u - 0.5) * 2.0 * rad
				var lz := (v - 0.5) * 2.0 * rad
				var x := cx + lx * c - lz * s
				var z := cz + lx * s + lz * c
				ground.v(x, y_fn.call(x, z) + lift, z, 0, 1, 0, cell[0] + u * 0.5, cell[1] + v, tint[0], tint[1], tint[2])
		for i in n:
			for j in n:
				var a := b + i * (n + 1) + j
				var bb := a + 1
				var cc := a + (n + 1)
				var d := cc + 1
				ground.t(a, bb, d)
				ground.t(a, d, cc)

	func scatter_flora(x: float, z: float, r_in: float, r_out: float, count: int, y_fn: Callable, flower_p: float = 0.3) -> void:
		for k in count:
			var a := R.f() * PI * 2.0
			var d := r_in + sqrt(R.f()) * (r_out - r_in)
			var px := x + cos(a) * d
			var pz := z + sin(a) * d
			var roll := R.f()
			var cell := "grass" if roll < 1.0 - flower_p else ("white" if roll < 1.0 - flower_p * 0.55 else ("dandelion" if roll < 1.0 - flower_p * 0.22 else "violet"))
			var y: float = y_fn.call(px, pz)
			var h := 0.2 + R.f() * 0.2 if cell == "grass" else 0.16 + R.f() * 0.12
			tuft(px, pz, y, h, cell, R.f() * PI)

	## An irregular natural stone (a lumpy rounded box from a displaced low-poly sphere).
	func stone(x: float, y: float, z: float, sx: float, sy: float, sz: float, rot_y: float) -> void:
		var col: Array = stone_cols[floori(R.f() * stone_cols.size())]
		var mossy := R.f() < 0.4
		var lon := 8
		var lat := 5
		var b := stones.count
		var c := cos(rot_y)
		var s := sin(rot_y)
		var ph := R.f() * 10.0
		for i in lat + 1:
			var th := (float(i) / lat) * PI
			var st := sin(th)
			var ct := cos(th)
			for j in lon + 1:
				var pphi := (float(j) / lon) * PI * 2.0
				# superellipsoid-ish (boxy but rounded), flat bottom
				var ux := _sgn(st, 0.6) * _sgn(cos(pphi), 0.6)
				var uy := _sgn(ct, 0.6)
				var uz := _sgn(st, 0.6) * _sgn(sin(pphi), 0.6)
				var bump := 1.0 + 0.08 * sin(pphi * 3.0 + ph) * st + 0.05 * sin(th * 4.0 + ph)
				ux *= bump
				uz *= bump
				if uy < -0.3:
					uy = -0.3 - (uy + 0.3) * 0.2
				var lx := ux * sx / 2.0
				var ly := uy * sy / 2.0
				var lz := uz * sz / 2.0
				var nx0 := st * cos(pphi) / sx
				var ny0 := ct / sy
				var nz0 := st * sin(pphi) / sz
				var nl := U.hypot3(nx0, ny0, nz0)
				if nl == 0.0:
					nl = 1.0
				var k := 0.7 if mossy and ct > 0.55 else 0.0
				var cc: Array = U.mix3(col, moss_col, k) if k != 0.0 else col
				stones.v(x + lx * c + lz * s, y + sy / 2.0 + ly, z - lx * s + lz * c, (nx0 * c + nz0 * s) / nl, ny0 / nl, (-nx0 * s + nz0 * c) / nl, 0, 0, cc[0], cc[1], cc[2])
		for i in lat:
			for j in lon:
				var a := b + i * (lon + 1) + j
				var bb := a + 1
				var cc := a + (lon + 1)
				var d := cc + 1
				stones.t(a, bb, cc)
				stones.t(bb, d, cc)

	func _sgn(v: float, e: float) -> float:
		return signf(v) * pow(absf(v), e)

	func build(spec: Dictionary) -> void:
		var base: Dictionary = spec.get("base", {"type": "soil"})
		var x: float = spec.x
		var z: float = spec.z
		var tr: float = spec.trunkR
		if base.type == "none":
			return
		if base.type == "pit":
			var S: float = base.size
			var cw := 0.12
			var ch := 0.15
			# the ground under a pit is about flat; use the lowest corner so nothing floats
			var g := INF
			for e in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [0.0, 0.0]]:
				g = minf(g, H(x + e[0] * S / 2.0, z + e[1] * S / 2.0))
			var cm = M.curb
			kit.rbox(S, ch + 0.1, cw, 0.03, cm, [x, g + (ch - 0.1) / 2.0, z - S / 2.0 + cw / 2.0])
			kit.rbox(S, ch + 0.1, cw, 0.03, cm, [x, g + (ch - 0.1) / 2.0, z + S / 2.0 - cw / 2.0])
			kit.rbox(cw, ch + 0.1, S - cw * 2.0, 0.03, cm, [x - S / 2.0 + cw / 2.0, g + (ch - 0.1) / 2.0, z])
			kit.rbox(cw, ch + 0.1, S - cw * 2.0, 0.03, cm, [x + S / 2.0 - cw / 2.0, g + (ch - 0.1) / 2.0, z])
			var top := g + ch - 0.05
			var soil = kit.box(S - cw * 2.0, 0.2, S - cw * 2.0, M.soil, [x, top - 0.1, z])
			soil.cast_shadow = false
			var flat := func(_x: float, _z: float) -> float: return top
			patch(x, z, S * 0.36, GROUND.moss, flat, R.f() * 6.0, [1.0, 1.0, 1.0], 0.012)
			var px0 := x + (R.f() - 0.5) * 0.3
			var pz0 := z + (R.f() - 0.5) * 0.3
			patch(px0, pz0, S * 0.25, GROUND.moss, flat, R.f() * 6.0, [0.92, 0.97, 0.9], 0.016)
			var inner := S / 2.0 - cw - 0.05
			var n := int(T.js_round(10.0 + S * S * 7.0))
			for k in n:
				var px := x + (R.f() - 0.5) * 2.0 * inner
				var pz := z + (R.f() - 0.5) * 2.0 * inner
				if U.hypot2(px - x, pz - z) < tr * 1.35:
					continue
				var roll := R.f()
				var cell := "grass" if roll < 0.62 else ("white" if roll < 0.8 else ("dandelion" if roll < 0.92 else "violet"))
				var h := 0.16 + R.f() * 0.16 if cell == "grass" else 0.14 + R.f() * 0.1
				tuft(px, pz, top, h, cell, R.f() * PI)
			return
		if base.type == "stones":
			var rr: float = base.r
			var n := maxi(8, int(T.js_round((2.0 * PI * rr) / 0.42)))
			for k in n:
				var a := (float(k) / n) * PI * 2.0 + (R.f() - 0.5) * 0.12
				var px := x + cos(a) * rr
				var pz := z + sin(a) * rr
				var sx := 0.36 + R.f() * 0.14
				var sy := 0.22 + R.f() * 0.14
				var sz := 0.26 + R.f() * 0.1
				var ry := -a + PI / 2.0 + (R.f() - 0.5) * 0.3
				stone(px, H(px, pz) - 0.06, pz, sx, sy, sz, ry)
			# slightly raised soil inside the ring
			var mound := func(px: float, pz: float) -> float:
				var d := U.hypot2(px - x, pz - z) / rr
				return H(px, pz) + 0.08 * maxf(0.0, 1.0 - d * d)
			patch(x, z, rr * 1.02, GROUND.soil, mound, R.f() * 6.0, [1.0, 1.0, 1.0], 0.02)
			patch(x + 0.15, z - 0.1, rr * 0.55, GROUND.moss, mound, R.f() * 6.0, [1.0, 1.0, 1.0], 0.03)
			scatter_flora(x, z, tr * 1.4, rr * 0.8, int(T.js_round(rr * rr * 16.0)), mound, 0.36)
			scatter_flora(x, z, rr * 1.05, rr * 1.45, int(T.js_round(rr * 12.0)), H, 0.25)
			if base.get("shimenawa", false):
				shimenawa(spec)
			return
		# natural soil
		var rr: float = base.get("r", 1.0)
		patch(x, z, rr * 1.15, GROUND.soil, H, R.f() * 6.0, [1.0, 1.0, 1.0], 0.02)
		var px1 := x + (R.f() - 0.5) * 0.4
		var pz1 := z + (R.f() - 0.5) * 0.4
		patch(px1, pz1, rr * 0.6, GROUND.moss, H, R.f() * 6.0, [1.0, 1.0, 1.0], 0.028)
		scatter_flora(x, z, rr * 0.55, rr * 1.35, int(T.js_round(rr * rr * 20.0)), H, 0.3)

	func shimenawa(spec: Dictionary) -> void:
		var x: float = spec.x
		var z: float = spec.z
		var y := H(x, z) + 1.55
		var rr: float = spec.trunkR * 1.12 + 0.04
		var pts := []
		for k in 25:
			var a := (k / 24.0) * PI * 2.0
			pts.append(Vector3(x + cos(a) * rr, y + sin(a * 2.0) * 0.015, z + sin(a) * rr))
		kit.mesh(Geo.tube_catmull(pts, true, 32, 0.035, 6, true), M.rope)
		# shide (zigzag paper streamers)
		for k in 4:
			var a := (k / 4.0) * PI * 2.0 + 0.4
			var px := x + cos(a) * (rr + 0.02)
			var pz := z + sin(a) * (rr + 0.02)
			var grp = kit.group([px, y - 0.03, pz], atan2(cos(a), sin(a)))
			var k2 = ctx.kit(grp)
			k2.box(0.06, 0.07, 0.004, M.paper, [0, -0.04, 0])
			k2.box(0.06, 0.07, 0.004, M.paper, [0.025, -0.1, 0.002], [0, 0, 0.35])
			k2.box(0.06, 0.07, 0.004, M.paper, [-0.005, -0.16, 0.004], [0, 0, -0.35])
			k2.box(0.06, 0.06, 0.004, M.paper, [0.02, -0.22, 0.006], [0, 0, 0.3])

	## {meshes, group, colliders, tris}
	func finish() -> Dictionary:
		var out := []
		var gF := flora.build()
		if gF != null:
			var m := T.MeshObj.new(gF, M.flora)
			m.receive_shadow = true
			m.cast_shadow = false
			m.name = "sakura-flora"
			ctx.no_outline(m)
			out.append(m)
		var gG := ground.build()
		if gG != null:
			var m := T.MeshObj.new(gG, M.ground)
			m.receive_shadow = true
			m.cast_shadow = false
			m.name = "sakura-groundpatch"
			ctx.no_outline(m)
			out.append(m)
		var gS := stones.build()
		if gS != null:
			var m := T.MeshObj.new(gS, M.stone)
			m.receive_shadow = true
			m.cast_shadow = true
			m.name = "sakura-stones"
			out.append(m)
		return {"meshes": out, "group": kit_group, "colliders": colliders, "tris": flora.tris() + ground.tris() + stones.tris()}
