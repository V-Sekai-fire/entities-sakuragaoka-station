# station/platforms.js: both platforms (bodies and wear, coping, white line, tactile strip, door
# marks), shelters, name boards, benches, bins, clocks, speakers, timetables, fences, platform ends,
# east ramps and the walkway across the tracks, and the north exit.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")


static func build_platforms(A) -> void:
	var ctx = A.ctx
	var k = A.k
	var kd = A.kd
	var U = A.U
	var M: Dictionary = A.M
	var P = A.P
	var L = A.L
	var PY: float = L.PLATFORM.y
	var r: Rng = ctx.rng("station-platforms")
	var S: Dictionary = L.PLATFORM.south.duplicate()
	S["t"] = -1.0
	S["name"] = "S"
	var N: Dictionary = L.PLATFORM.north.duplicate()
	N["t"] = 1.0
	N["name"] = "N"
	var back_z := func(p: Dictionary) -> float: return p.z1 if p.name == "S" else p.z0
	var z_at := func(p: Dictionary, d: float) -> float: return p.edgeZ - p.t * d
	var GROUND: float = L.RAIL.groundY - 0.05
	var yellow = ctx.mat.toon("#e3b93a", {"paint": 0.02})
	# ------------------------------------------------------------ platform bodies + surface markings
	for p in [S, N]:
		var bz: float = back_z.call(p)
		var e: float = p.edgeZ
		var x0: float = p.x0
		var x1: float = p.x1
		var cx := (x0 + x1) / 2.0
		var len := x1 - x0
		var zmin := minf(bz, e)
		var zmax := maxf(bz, e)
		var t: float = p.t
		k.box(len, 0.16, zmax - zmin, M.concrete, [cx, PY - 0.08, (zmin + zmax) / 2.0])
		var e_in := e - t * 0.14
		var bmin := minf(bz, e_in)
		var bmax := maxf(bz, e_in)
		k.box(len, PY - 0.16 - GROUND, bmax - bmin, M.concreteSide, [cx, (PY - 0.16 + GROUND) / 2.0, (bmin + bmax) / 2.0])
		var x := x0 + 3.0
		while x < x1:
			k.box(0.03, PY - 0.2 - GROUND, 0.02, M.concreteDark, [x, (PY - 0.2 + GROUND) / 2.0, e_in + t * 0.008])
			x += 3.0
		x = x0 + 1.0
		while x < x1 - 1.0:
			var gw := 1.4 + r.f()
			k.plane(gw, 0.5, M.grime, [x, GROUND + 0.3, e_in + t * 0.012], [0, 0.0 if t > 0 else PI, 0]).receive_shadow = true
			x += 2.3 + r.f() * 2.0
		P.addWalkBox(cx, (zmin + zmax) / 2.0, len, zmax - zmin, 0, PY)
		var out := -t
		var fz := bz + out * 0.01
		var rot := 0.0 if out > 0 else PI
		var segs := [[x0, -4.0], [12.0, x1]] if p.name == "S" else [[7.4, x1]]
		for sg in segs:
			var a: float = sg[0]
			var b: float = sg[1]
			k.box(b - a, 0.1, 0.05, M.coping, [(a + b) / 2.0, PY - 0.06, bz + out * 0.025])
			x = a + 3.0
			while x < b - 0.5:
				k.box(0.03, PY - 0.2 - GROUND, 0.02, M.concreteDark, [x, (PY - 0.2 + GROUND) / 2.0, fz])
				x += 3.0
			x = a + 0.9
			while x < b - 0.9:
				var gw := 1.5 + r.f()
				k.plane(gw, 0.55, M.grime, [x, GROUND + 0.33, bz + out * 0.014], [0, rot, 0]).receive_shadow = true
				x += 2.0 + r.f() * 1.6
			x = a + 1.4
			while x < b - 1.0:
				var sw := 0.9 + r.f() * 0.9
				var sh := 0.5 + r.f() * 0.3
				k.plane(sw, sh, M.streak, [x, PY - 0.42, bz + out * 0.016], [0, rot, 0]).receive_shadow = true
				x += 2.6 + r.f() * 2.5
			x = a + 1.6
			while x < b - 0.5:
				k.cyl(0.045, 0.045, 0.1, M.equipDark, [x, GROUND + 0.5, bz + out * 0.04], [PI / 2.0, 0, 0], 8)
				x += 4.5
		P.addAABB(x0, minf(e, e + t * 0.35), x1, maxf(e, e + t * 0.35), 0.9, 4)
		var band := func(d0: float, d1: float, h: float, m):
			var z0: float = z_at.call(p, d0)
			var z1: float = z_at.call(p, d1)
			return k.box(len, h, absf(z1 - z0), m, [cx, PY + h / 2.0, (z0 + z1) / 2.0])
		band.call(0.0, 0.3, 0.008, M.coping)
		k.plane(len, 0.09, M.whiteLine, [cx, PY + 0.0045, z_at.call(p, 0.42)], [-PI / 2.0, 0, 0]).receive_shadow = true
		band.call(0.8, 1.1, 0.012, M.tactDot)
		band.call(1.1, 1.14, 0.014, yellow)
		var tz0: float = z_at.call(p, 1.14)
		var tz1 := bz
		k.box(0.3, 0.012, absf(tz1 - tz0) - 0.3, M.tactDot, [x1 - 0.2, PY + 0.006, (tz0 + tz1) / 2.0 + t * 0.15])
		var dm: Dictionary = A.atlases.misc.r("doorMark")
		for dx in L.TRAIN_DOORS_X:
			var m := T.MeshObj.new(U.rect_plane(1.3, 0.6, dm), M.doorMark)
			m.position = Vector3(dx, PY + 0.005, z_at.call(p, 1.5))
			m.rotation = Vector3(-PI / 2.0, 0, 0.0 if p.name == "S" else PI)
			m.receive_shadow = true
			A.root.add(m)
		for i in 9:
			var px: float = x0 + 2.0 + r.f() * (len - 4.0)
			var d := 0.4 + r.f() * 3.2
			var pw := 0.8 + r.f() * 1.6
			var ph := 0.4 + r.f() * 0.7
			var prz := r.f() * PI
			k.plane(pw, ph, M.grime, [px, PY + 0.003, z_at.call(p, d)], [-PI / 2.0, 0, prz]).receive_shadow = true
		k.plane(len - 1.0, 0.25, M.grime, [cx, PY + 0.003, bz + t * 0.2], [-PI / 2.0, 0, 0]).receive_shadow = true
	# ------------------------------------------------------------ east ramps + walkway across the tracks
	var RX0: float = L.PLATFORM.rampX0
	var RX1: float = L.PLATFORM.rampX1
	var WX0: float = L.PLATFORM.walkCrossing.x0
	var WX1: float = L.PLATFORM.walkCrossing.x1
	var WY: float = L.RAIL.railTopY
	for p in [S, N]:
		var bz: float = back_z.call(p)
		var e: float = p.edgeZ
		var t: float = p.t
		var zmin := minf(bz, e)
		var zmax := maxf(bz, e)
		var w := zmax - zmin
		var cz := (zmin + zmax) / 2.0
		var g: T.Geometry = ctx.geo.extrude([[RX0, GROUND], [RX1, GROUND], [RX1, WY], [RX0, PY]], w)
		k.mesh(g, M.concreteSide, [0, 0, cz])
		var Ls := sqrt((RX1 - RX0) ** 2 + (PY - WY) ** 2)
		var ang := atan2(WY - PY, RX1 - RX0)
		k.box(Ls, 0.02, w, M.concrete, [(RX0 + RX1) / 2.0, (PY + WY) / 2.0 - 0.002, cz], [0, 0, ang])
		var x := RX0 + 0.6
		while x < RX1 - 0.3:
			var y := PY + (x - RX0) / (RX1 - RX0) * (WY - PY)
			k.box(0.05, 0.01, w - 0.3, M.concreteDark, [x, y + 0.008, cz], [0, 0, ang])
			x += 0.6
		P.addWalkRamp((RX0 + RX1) / 2.0, cz, w, RX1 - RX0, -PI / 2.0, WY, PY)
		k.box(WX1 - WX0 + 0.3, WY - GROUND, w, M.concreteSide, [(WX0 + WX1 + 0.3) / 2.0, (WY + GROUND) / 2.0, cz])
		k.box(WX1 - WX0 + 0.3, 0.02, w, M.concrete, [(WX0 + WX1 + 0.3) / 2.0, WY - 0.008, cz])
		P.addWalkBox((WX0 + WX1 + 0.3) / 2.0, cz, WX1 - WX0 + 0.3, w, 0, WY)
		var fz := e - t * 0.12
		var ramp_y := func(xx: float, _z: float) -> float: return PY if xx <= RX0 else (WY if xx >= RX1 else PY + (xx - RX0) / (RX1 - RX0) * (WY - PY))
		U.railing(k, [[RX0 - 0.02, fz], [RX1, fz]], ramp_y, {"h": 1.1, "post": 1.5, "rails": [1.0, 0.55, 0.12], "bar": 0.15, "barLo": 0.14, "mat": M.fenceWhite, "postW": 0.06})
		P.addBox((RX0 + RX1) / 2.0, fz, RX1 - RX0, 0.12, 0, -1, 4)
		U.railing(k, [[WX1 + 0.12, bz], [WX1 + 0.12, e - t * 0.25]], WY, {"h": 1.1, "post": 1.3, "rails": [1.0, 0.55, 0.12], "bar": 0.15, "barLo": 0.14, "mat": M.fenceWhite, "postW": 0.06})
		P.addBox(WX1 + 0.12, cz, 0.12, w, 0, -1, 4)
		k.box(WX1 - WX0 - 0.1, 0.012, 0.3, M.tactDot, [(WX0 + WX1) / 2.0, WY + 0.006, e - t * 0.35])
	var zA: float = L.RAIL.zA
	var zB: float = L.RAIL.zB
	var hg: float = L.RAIL.gauge / 2.0
	var head := 0.065
	var fl := 0.07
	var outer := func(zc: float, s: float) -> float: return zc + s * (hg + head + 0.005)
	var inner := func(zc: float, s: float) -> float: return zc + s * (hg - fl)
	var boards := [
		[S.edgeZ, outer.call(zA, 1.0), M.stone], [inner.call(zA, 1.0), inner.call(zA, -1.0), M.rubber], [outer.call(zA, -1.0), outer.call(zB, 1.0), M.stone],
		[inner.call(zB, 1.0), inner.call(zB, -1.0), M.rubber], [outer.call(zB, -1.0), N.edgeZ, M.stone],
	]
	for bd in boards:
		var z0 := minf(bd[0], bd[1])
		var z1 := maxf(bd[0], bd[1])
		k.box(WX1 - WX0, 0.12, z1 - z0 - 0.01, bd[2], [(WX0 + WX1) / 2.0, WY - 0.06, (z0 + z1) / 2.0])
		k.box(WX1 - WX0, 0.006, 0.05, M.signYellow, [(WX0 + WX1) / 2.0, WY + 0.003, z0 + 0.06])
		k.box(WX1 - WX0, 0.006, 0.05, M.signYellow, [(WX0 + WX1) / 2.0, WY + 0.003, z1 - 0.06])
	P.addWalkBox((WX0 + WX1) / 2.0, (S.edgeZ + N.edgeZ) / 2.0, WX1 - WX0, S.edgeZ - N.edgeZ, 0, WY)
	P.addAABB(WX0 - 0.15, N.edgeZ, WX0, S.edgeZ, -1, 3)
	P.addAABB(WX1, N.edgeZ, WX1 + 0.15, S.edgeZ, -1, 3)
	for e3 in [[S.edgeZ + 0.25, 0.0, 1.0], [N.edgeZ - 0.25, PI, -1.0]]:
		var z: float = e3[0]
		var rot: float = e3[1]
		var face: float = e3[2]
		var x := WX1 - 0.1
		k.cyl(0.045, 0.05, 2.5, M.fenceWhite, [x, WY + 1.25, z], null, 10)
		for i in 6:
			k.box(0.1, 0.12, 0.1, M.ink if i % 2 else M.signYellow, [x, WY + 0.1 + i * 0.12, z])
		A.board("misc", "crossWarn", 0.46, 0.593, [x - 0.35, WY + 1.55, z + face * 0.04], rot, {"frame": M.fenceWhite, "border": 0.02})
		var lamp_y := WY + 2.35
		k.box(0.22, 0.22, 0.14, M.ink, [x, lamp_y, z + face * 0.02])
		k.cyl(0.07, 0.07, 0.03, ctx.mat.toon("#7a3030"), [x, lamp_y, z + face * 0.1], [PI / 2.0, 0, 0], 16)
		var lit = kd.cyl(0.07, 0.07, 0.032, ctx.mat.emissive("#ff4a3a", 2.2), [x, lamp_y, z + face * 0.101], [PI / 2.0, 0, 0], 16)
		k.box(0.24, 0.03, 0.12, M.ink, [x, lamp_y + 0.14, z + face * 0.1])
		A.blinkers.append({"mesh": lit, "kind": "crossing"})
		P.addCylinder(x, z, 0.08, -1, 3)
	# ------------------------------------------------------------ fences on the outer sides
	var south_fence_z: float = S.z1 - 0.02
	var north_fence_z: float = N.z0 + 0.02
	var base_y := func(xx: float, _z: float) -> float: return PY if xx <= RX0 else (WY if xx >= RX1 else PY + (xx - RX0) / (RX1 - RX0) * (WY - PY))
	var white_fence := func(xa: float, xb: float, z: float) -> void:
		U.railing(k, [[xa, z], [xb, z]], base_y, {"h": 1.1, "post": 2.0, "rails": [1.0, 0.55, 0.1], "bar": 0.15, "barLo": 0.12, "mat": M.fenceWhite, "postW": 0.06})
		P.addBox((xa + xb) / 2.0, z, xb - xa, 0.14, 0, -1, 5)
	white_fence.call(S.x0, -4.0, south_fence_z)
	for ab in [[12.0, 26.0], [26.0, RX0], [RX0, RX1], [RX1, WX1 + 0.12]]:
		white_fence.call(ab[0], ab[1], south_fence_z)
	var mesh_fence := func(xa: float, xb: float, z: float) -> void:
		var h := 1.25
		var n := maxi(1, int(T.js_round((xb - xa) / 2.4)))
		for i in n + 1:
			var x := xa + (xb - xa) * i / n
			k.box(0.06, h + 0.05, 0.06, M.fenceGreen, [x, base_y.call(x, z) + (h + 0.05) / 2.0, z])
		for i in n:
			var a := xa + (xb - xa) * i / n
			var b := xa + (xb - xa) * (i + 1) / n
			var ya: float = base_y.call(a, z)
			var yb: float = base_y.call(b, z)
			U.beam(k, [a, ya + h, z], [b, yb + h, z], 0.045, 0.045, M.fenceGreen, true)
			U.beam(k, [a, ya + 0.08, z], [b, yb + 0.08, z], 0.035, 0.035, M.fenceGreen, true)
			var g := Geo.plane(b - a, h - 0.1)
			var pos := g.position()
			var uv: T.Attr = g.attributes.uv
			for j in pos.count():
				var lx := pos.get_x(j)
				var ly := pos.get_y(j)
				var tt := (lx + (b - a) / 2.0) / (b - a)
				pos.set_y(j, ly + (ya + (yb - ya) * tt) + h / 2.0 + 0.03)
				uv.set_xy(j, uv.get_x(j) * (b - a) / 0.12, uv.get_y(j) * (h - 0.1) / 0.12)
			var m := T.MeshObj.new(g, M.wireMesh)
			m.position = Vector3((a + b) / 2.0, 0, z)
			ctx.no_outline(m)
			A.root.add(m)
		P.addBox((xa + xb) / 2.0, z, xb - xa, 0.14, 0, -1, 5)
	mesh_fence.call(N.x0, -5.95, north_fence_z)
	for ab in [[-4.05, 16.0], [16.0, RX0], [RX0, RX1], [RX1, WX1 + 0.12]]:
		mesh_fence.call(ab[0], ab[1], north_fence_z)
	# ------------------------------------------------------------ platform ends (west)
	for p in [S, N]:
		var bz: float = back_z.call(p)
		var t: float = p.t
		var x: float = p.x0 + 0.06
		var z_gate0: float = p.edgeZ - t * 0.3
		var z_gate1 := bz
		U.railing(k, [[x, z_gate0], [x, (z_gate0 + z_gate1) / 2.0 - t * 0.55]], PY, {"h": 1.15, "post": 1.0, "rails": [1.0, 0.55, 0.1], "bar": 0.12, "mat": M.fenceWhite, "postW": 0.07})
		U.railing(k, [[x, (z_gate0 + z_gate1) / 2.0 + t * 0.55], [x, z_gate1]], PY, {"h": 1.15, "post": 1.0, "rails": [1.0, 0.55, 0.1], "bar": 0.12, "mat": M.fenceWhite, "postW": 0.07})
		var gz := (z_gate0 + z_gate1) / 2.0
		U.railing(k, [[x, gz - 0.53], [x, gz + 0.53]], PY, {"h": 1.05, "post": 1.06, "rails": [1.0, 0.5, 0.1], "bar": 0.1, "mat": M.signYellow, "postW": 0.05})
		A.board("misc", "keepOut", 0.5, 0.37, [x + 0.05, PY + 0.8, gz], PI / 2.0, {"frame": M.fenceWhite, "border": 0.02})
		A.board("misc", "platNo1" if p.name == "S" else "platNo2", 0.26, 0.26, [x + 0.05, PY + 1.35, gz + t * 1.1], PI / 2.0, {"frame": M.fenceWhite, "border": 0.02})
		P.addAABB(p.x0, minf(z_gate0, z_gate1), p.x0 + 0.15, maxf(z_gate0, z_gate1), -1, 5)
		var ez: float = z_at.call(p, 3.3)
		var kk = ctx.kit(k.group([p.x0 + 0.75, PY, ez], PI if p.name == "S" else 0.0))
		kk.box(0.7, 1.0, 0.42, M.equip, [0, 0.62, 0])
		kk.box(0.74, 0.04, 0.46, M.equipDark, [0, 1.13, 0])
		for dx in [-0.3, 0.3]:
			kk.box(0.05, 0.12, 0.4, M.equipDark, [dx, 0.06, 0])
		kk.box(0.01, 0.8, 0.02, M.equipDark, [0, 0.62, 0.215])
		var lb := T.MeshObj.new(U.rect_plane(0.3, 0.12, A.atlases.misc.r("equipLabel")), A.sign_mat("misc", false))
		lb.position = Vector3(0, 0.95, 0.213)
		kk.parent.add(lb)
		P.addBox(p.x0 + 0.75, ez, 0.74, 0.46, 0, -1, 3)
	var dep_ind := func(x: float, z: float, rot: float) -> void:
		k.cyl(0.05, 0.05, 2.4, M.steelDark, [x, PY + 1.2, z], null, 10)
		var g = k.group([x, PY + 2.4, z], rot)
		var kk = ctx.kit(g)
		kk.box(0.34, 0.34, 0.16, M.ink, [0, 0, 0])
		kk.box(0.4, 0.04, 0.2, M.ink, [0, 0.2, 0.02])
		kk.cyl(0.1, 0.1, 0.02, ctx.mat.toon("#b8bcc4"), [0, 0, 0.085], [PI / 2.0, 0, 0], 16)
		var lamp := T.MeshObj.new(Geo.g_cyl(ctx.cache, 16), ctx.mat.emissive("#f4fbff", 2.4))
		lamp.scale = Vector3(0.2, 0.022, 0.2)
		lamp.position = Vector3(0, 0, 0.098).rotated(Vector3.UP, rot) + Vector3(x, PY + 2.4, z)
		lamp.set_rotation(PI / 2.0, rot, 0, "YXZ")
		A.dyn.add(lamp)
		A.blinkers.append({"mesh": lamp, "kind": "departure"})
		P.addCylinder(x, z, 0.08, -1, 4)
	dep_ind.call(S.x0 + 0.6, z_at.call(S, 0.5), PI / 2.0)
	dep_ind.call(N.x1 - 0.6, z_at.call(N, 0.5), -PI / 2.0)
	var mirror := func(x: float, z: float, rot: float) -> void:
		k.cyl(0.05, 0.06, 2.9, M.fenceWhite, [x, PY + 1.45, z], null, 10)
		for i in 5:
			k.box(0.13, 0.12, 0.13, M.ink if i % 2 else M.signYellow, [x, PY + 0.1 + i * 0.12, z])
		var g = k.group([x, PY + 2.55, z], rot)
		var kk = ctx.kit(g)
		kk.box(0.72, 1.02, 0.08, M.signYellow, [0, 0, 0])
		kk.box(0.12, 0.08, 0.2, M.steelDark, [0, 0, -0.1])
		kk.box(0.62, 0.92, 0.02, M.mirror, [0, 0, 0.045]).cast_shadow = false
		P.addCylinder(x, z, 0.1, -1, 4)
	mirror.call(-3.2, z_at.call(S, 0.45), PI / 2.0 - 0.35)
	mirror.call(37.4, z_at.call(N, 0.45), -PI / 2.0 + 0.35 + PI * 0.0)
	var stop_mark := func(x: float, z: float, rot: float) -> void:
		k.cyl(0.03, 0.03, 1.2, M.steelDark, [x, PY + 0.6, z], null, 8)
		A.board("misc", "stopPos", 0.22, 0.275, [x, PY + 1.35, z], rot, {"frame": M.ink, "border": 0.015})
		P.addCylinder(x, z, 0.05, -1, 3)
	stop_mark.call(-1.3, z_at.call(S, 0.2), PI / 2.0)
	stop_mark.call(35.3, z_at.call(N, 0.2), -PI / 2.0)
	# ------------------------------------------------------------ shelters
	var shelter := func(p: Dictionary, xa: float, xb: float, cols: Array) -> Dictionary:
		var t: float = p.t
		var bz: float = back_z.call(p)
		var z_back := bz + t * 0.1
		var z_front: float = z_at.call(p, 0.6)
		var z_col := bz + t * 0.6
		var yB := PY + 3.17
		var yF := PY + 3.35
		var y_at_z := func(z: float) -> float: return yB + (z - z_back) / (z_front - z_back) * (yF - yB)
		var ang := atan2(yF - yB, absf(z_front - z_back)) * (1.0 if t < 0 else -1.0)
		var depth := absf(z_front - z_back)
		var zc := (z_back + z_front) / 2.0
		k.box(xb - xa, 0.07, depth / cos(absf(ang)), M.shelterRoof, [(xa + xb) / 2.0, (yB + yF) / 2.0 - 0.035, zc], [ang, 0, 0])
		k.box(xb - xa, 0.01, depth - 0.05, M.shelterUnder, [(xa + xb) / 2.0, (yB + yF) / 2.0 - 0.075, zc], [ang, 0, 0])
		var x := xa + 0.25
		while x < xb:
			k.box(0.04, 0.03, depth / cos(absf(ang)) - 0.04, M.shelterFascia, [x, (yB + yF) / 2.0 + 0.01, zc], [ang, 0, 0])
			x += 0.5
		k.box(xb - xa + 0.04, 0.24, 0.05, M.shelterFascia, [(xa + xb) / 2.0, yF - 0.08, z_front - t * 0.02])
		k.box(xb - xa + 0.05, 0.04, 0.055, M.pinkBand, [(xa + xb) / 2.0, yF - 0.15, z_front - t * 0.02])
		k.box(xb - xa, 0.1, 0.13, M.gutter, [(xa + xb) / 2.0, yB - 0.1, z_back - t * 0.02])
		for f in [0.15, 0.5, 0.85]:
			var z: float = z_back + (z_front - z_back) * f
			k.box(xb - xa, 0.1, 0.06, M.shelterCol, [(xa + xb) / 2.0, y_at_z.call(z) - 0.14, z])
		for i in cols.size():
			var cx: float = cols[i]
			var top: float = y_at_z.call(z_col) - 0.2
			k.cyl(0.075, 0.075, top - PY, M.shelterCol, [cx, (PY + top) / 2.0, z_col], null, 12)
			k.box(0.26, 0.03, 0.26, M.shelterCol, [cx, PY + 0.015, z_col])
			U.beam(k, [cx, y_at_z.call(z_back) - 0.16, z_back], [cx, y_at_z.call(z_front) - 0.16, z_front], 0.1, 0.2, M.shelterCol)
			U.beam(k, [cx, top - 0.55, z_col], [cx, y_at_z.call(z_col - t * -1.4) - 0.24, z_col + t * 1.4], 0.06, 0.08, M.shelterCol)
			if i % 2 == 0:
				U.beam(k, [cx + 0.12, yB - 0.12, z_back], [cx + 0.12, PY + 0.05, z_back], 0.07, 0.07, M.gutter, true)
			P.addCylinder(cx, z_col, 0.1, -1, 5)
		var zl := z_back + (z_front - z_back) * 0.5
		x = xa + 1.2
		while x < xb - 0.8:
			k.box(1.3, 0.06, 0.16, M.shelterFascia, [x, y_at_z.call(zl) - 0.22, zl])
			k.box(1.22, 0.025, 0.07, M.tube, [x, y_at_z.call(zl) - 0.255, zl]).cast_shadow = false
			x += 2.4
		return {"yAtZ": y_at_z, "zBack": z_back, "zFront": z_front, "zCol": z_col}
	var shS: Dictionary = shelter.call(S, 12.5, 28.5, [13.3, 16.6, 20.0, 23.4, 26.8])
	var shN: Dictionary = shelter.call(N, 5.0, 25.0, [6.0, 9.6, 13.2, 16.8, 20.4, 24.0])
	var ex := -2.6
	while ex < 12.0:
		k.box(1.3, 0.06, 0.16, M.shelterFascia, [ex, 4.06, -36.1])
		k.box(1.22, 0.025, 0.07, M.tube, [ex, 4.025, -36.1]).cast_shadow = false
		ex += 2.8
	# ------------------------------------------------------------ name boards (standing x2 + hanging x1 per platform)
	var standing := func(x: float, p: Dictionary) -> void:
		var face_n: bool = p.name == "S"
		var t: float = p.t
		var z: float = back_z.call(p) + t * 0.32
		var rot := PI if face_n else 0.0
		var id := "ekiS" if face_n else "ekiN"
		var w := 2.3
		var h := w * 360.0 / 1016.0
		var yc := PY + 1.25 + h / 2.0
		for dx in [-w / 2.0 + 0.15, w / 2.0 - 0.15]:
			k.box(0.08, yc + h / 2.0 - PY + 0.05, 0.08, M.shelterCol, [x + dx, (PY + yc + h / 2.0 + 0.05) / 2.0, z - t * 0.05])
			k.box(0.2, 0.03, 0.2, M.shelterCol, [x + dx, PY + 0.015, z - t * 0.05])
			P.addCylinder(x + dx, z - t * 0.05, 0.08, -1, 4)
		A.board("signs", id, w, h, [x, yc, z + t * 0.01], rot, {"frame": M.shelterFascia, "border": 0.04, "depth": 0.05})
		k.box(w + 0.12, 0.06, 0.12, M.shelterFascia, [x, yc + h / 2.0 + 0.07, z])
	standing.call(-5.5, S)
	standing.call(35.3, S)
	standing.call(1.0, N)
	standing.call(30.6, N)
	var hanging := func(x: float, p: Dictionary, sh: Dictionary) -> void:
		var z: float = z_at.call(p, 1.9)
		var w := 1.9
		var h := w * 360.0 / 1016.0
		var yc := PY + 2.45
		var g = k.group([x, yc, z], 0.0)
		var kk = ctx.kit(g)
		kk.box(w + 0.08, h + 0.08, 0.08, M.shelterFascia, [0, 0, 0])
		var f1 := T.MeshObj.new(U.rect_plane(w, h, A.atlases.signs.r("ekiN")), A.sign_mat("signs", 0.95))
		f1.position.z = 0.043
		g.add(f1)
		var f2 := T.MeshObj.new(U.rect_plane(w, h, A.atlases.signs.r("ekiS")), A.sign_mat("signs", 0.95))
		f2.position.z = -0.043
		f2.rotation.y = PI
		g.add(f2)
		for dx in [-w * 0.38, w * 0.38]:
			U.beam(k, [x + dx, yc + h / 2.0 + 0.04, z], [x + dx, sh.yAtZ.call(z) - 0.14, z], 0.02, 0.02, M.steelDark, true)
	hanging.call(21.7, S, shS)
	hanging.call(11.4, N, shN)
	# ------------------------------------------------------------ hanging perpendicular signs, clocks, speakers, timetables
	var perp := func(x: float, p: Dictionary, sh: Dictionary, id_e, id_w) -> void:
		var atlas := "signs"
		var w := 1.4
		var z: float = z_at.call(p, 2.2)
		var h := w * 128.0 / 500.0
		var yc := PY + 2.55
		var g = k.group([x, yc, z], PI / 2.0)
		var kk = ctx.kit(g)
		kk.box(w + 0.06, h + 0.06, 0.06, M.shelterFascia, [0, 0, 0])
		var aE: Array = [atlas, id_e] if id_e is String else id_e
		var aW: Array = [atlas, id_w] if id_w is String else id_w
		var fE := T.MeshObj.new(U.rect_plane(w, h, A.atlases[aE[0]].r(aE[1])), A.sign_mat(aE[0], 0.95))
		fE.position.z = 0.033
		g.add(fE)
		var fW := T.MeshObj.new(U.rect_plane(w, h, A.atlases[aW[0]].r(aW[1])), A.sign_mat(aW[0], 0.95))
		fW.position.z = -0.033
		fW.rotation.y = PI
		g.add(fW)
		for dz in [-w * 0.38, w * 0.38]:
			U.beam(k, [x, yc + h / 2.0 + 0.03, z + dz], [x, sh.yAtZ.call(z + dz) - 0.14, z + dz], 0.02, 0.02, M.steelDark, true)
	perp.call(14.4, S, shS, ["face", "exitUp"], "toTrack2")
	perp.call(25.2, S, shS, "plat1", "plat1")
	perp.call(7.2, N, shN, ["misc", "northExit"], ["face", "exitUp"])
	perp.call(18.6, N, shN, "plat2", "plat2")
	var h_clock := func(x: float, p: Dictionary, sh: Dictionary) -> void:
		var z: float = z_at.call(p, 2.2)
		var y := PY + 2.6
		A.clock([x, y, z], PI / 2.0, 0.24, {"double": true, "lit": false, "frame": M.shelterFascia})
		U.beam(k, [x, y + 0.26, z], [x, sh.yAtZ.call(z) - 0.14, z], 0.03, 0.03, M.steelDark, true)
	h_clock.call(18.2, S, shS)
	h_clock.call(14.9, N, shN)
	var dep := func(x: float, p: Dictionary, sh: Dictionary, id: String) -> void:
		var z: float = z_at.call(p, 2.2)
		var y := PY + 2.45
		var w := 1.0
		var h := 0.42
		var g = k.group([x, y, z], -PI / 2.0 if p.name == "S" else PI / 2.0)
		var kk = ctx.kit(g)
		kk.box(w + 0.08, h + 0.08, 0.12, M.darkPanel, [0, 0, 0])
		var f := T.MeshObj.new(U.rect_plane(w, h, A.atlases.TVM.r(id)), A.sign_mat("TVM", 1.1))
		f.position.z = 0.062
		g.add(f)
		for dz in [-0.35, 0.35]:
			U.beam(k, [x, y + h / 2.0 + 0.04, z + dz], [x, sh.yAtZ.call(z + dz) - 0.14, z + dz], 0.02, 0.02, M.steelDark, true)
	dep.call(13.1, S, shS, "depSmall")
	dep.call(5.6, N, shN, "depSmall2")
	for e3 in [[16.6, S, shS], [23.4, S, shS], [9.6, N, shN], [16.8, N, shN], [24.0, N, shN]]:
		var p: Dictionary = e3[1]
		var z: float = e3[2].zCol
		var y := PY + 2.75
		var g = k.group([e3[0], y, z - p.t * 0.12], PI if p.name == "S" else 0.0)
		var kk = ctx.kit(g)
		kk.box(0.08, 0.12, 0.1, M.shelterFascia, [0, 0, -0.04])
		kk.cyl(0.11, 0.04, 0.22, M.shelterFascia, [0, 0, 0.1], [PI / 2.0 + 0.25, 0, 0], 12)
	for x in [2.0, 9.2]:
		var g = k.group([x, 3.85, -35.62], PI)
		ctx.kit(g).cyl(0.11, 0.04, 0.22, M.shelterFascia, [0, 0, 0.1], [PI / 2.0 + 0.3, 0, 0], 12)
	A.board("I", "tt1", 0.44, 0.616, [13.3 - 0.085, PY + 1.55, shS.zCol], -PI / 2.0, {"frame": M.shelterFascia, "border": 0.02})
	A.board("I", "tt2", 0.44, 0.616, [6.0 - 0.085, PY + 1.55, shN.zCol], -PI / 2.0, {"frame": M.shelterFascia, "border": 0.02})
	A.board("I", "tt1", 0.5, 0.7, [0.2, PY + 1.5, -35.52], PI, {"frame": M.fascia, "border": 0.02})
	A.board("P", "safety", 0.42, 0.595, [-3.45, PY + 1.55, -35.52], PI, {"frame": null})
	A.board("P", "wantedPoster", 0.42, 0.6, [5.2, PY + 1.55, -35.52], PI, {"frame": null})
	# ------------------------------------------------------------ benches
	var bench_a := func(x: float, z: float, rot: float, len: float) -> void:
		var g = k.group([x, PY, z], rot)
		var kk = ctx.kit(g)
		for i in 4:
			kk.rbox(len, 0.035, 0.09, 0.012, M.benchSlat, [0, 0.425, -0.15 + i * 0.1])
		for i in 3:
			kk.rbox(len, 0.08, 0.03, 0.012, M.benchSlat, [0, 0.58 + i * 0.12, -0.24 - i * 0.02], [-0.18, 0, 0])
		for dx in [-len / 2.0 + 0.14, len / 2.0 - 0.14]:
			kk.box(0.05, 0.42, 0.06, M.benchGreen, [dx, 0.21, 0.14])
			kk.box(0.05, 0.84, 0.06, M.benchGreen, [dx, 0.42, -0.2], [-0.12, 0, 0])
			kk.box(0.05, 0.05, 0.44, M.benchGreen, [dx, 0.4, -0.03])
			kk.box(0.05, 0.04, 0.34, M.benchGreen, [dx, 0.64, 0.02])
			kk.box(0.05, 0.2, 0.04, M.benchGreen, [dx, 0.54, 0.18])
		P.addBox(x, z, len, 0.5, rot, -1, PY + 0.8)
		A.benches.append({"x": x, "z": z, "y": PY + 0.445, "rotY": rot, "len": len})
	var bench_b := func(x: float, z: float, rot: float, n: int, m) -> void:
		var pitch := 0.48
		var len := n * pitch
		var g = k.group([x, PY, z], rot)
		var kk = ctx.kit(g)
		kk.box(len, 0.06, 0.08, M.steelDark, [0, 0.3, -0.05])
		for dx in [-len / 2.0 + 0.3, len / 2.0 - 0.3]:
			kk.box(0.06, 0.3, 0.06, M.steelDark, [dx, 0.15, -0.05])
			kk.box(0.3, 0.02, 0.36, M.steelDark, [dx, 0.01, -0.05])
		for i in n:
			var sx := -len / 2.0 + pitch * (i + 0.5)
			kk.rbox(0.44, 0.06, 0.42, 0.03, m, [sx, 0.42, 0.0])
			kk.rbox(0.44, 0.4, 0.05, 0.03, m, [sx, 0.66, -0.2], [-0.14, 0, 0])
			kk.box(0.06, 0.1, 0.08, M.steelDark, [sx, 0.36, -0.05])
		P.addBox(x, z, len, 0.5, rot, -1, PY + 0.8)
		A.benches.append({"x": x, "z": z, "y": PY + 0.45, "rotY": rot, "len": len})
	var B1: Dictionary = L.PLATFORM.benchB1
	bench_a.call(B1.x, B1.z, B1.rotY, 1.8)
	bench_b.call(-2.0, -35.84, PI, 4, M.benchBlue)
	bench_a.call(25.1, -36.15, PI, 1.8)
	bench_b.call(33.4, -35.84, PI, 3, M.benchBrown)
	bench_a.call(7.8, -49.85, 0.0, 1.8)
	bench_b.call(15.0, -49.84, 0.0, 4, M.benchBlue)
	bench_a.call(22.2, -49.85, 0.0, 1.8)
	bench_b.call(31.0, -49.84, 0.0, 3, M.benchGreen)
	# ------------------------------------------------------------ sorted bin units + column fittings (modelled props)
	var X = A.X
	X.bin_unit(21.8, -35.8, PI, {"y": PY, "warm": false})
	X.bin_unit(11.5, -50.2, 0.0, {"y": PY, "warm": false})
	X.bin_unit(-0.9, -35.78, PI, {"y": PY, "warm": false})
	var C: Dictionary = X.C
	var red = ctx.mat.toon("#cc4a42", {"paint": 0.03})
	var ylw = ctx.mat.toon("#e8c24a", {"paint": 0.03})
	var wht = ctx.mat.toon("#e2e3df", {"paint": 0.03})
	var em_stop := func(x: float, zc: float, face: float) -> void:
		var g = X.grp(x + face * 0.08, PY + 1.35, zc, PI / 2.0 if face > 0 else -PI / 2.0)
		var kk = X.K(g)
		kk.rb(0.24, 0.3, 0.1, 0.015, ylw, [0, 0, 0.0])
		X.lab(g, "N", "emStop", 0.2, 0.2, [0, 0.03, 0.0505], null, false)
		kk.rb(0.12, 0.08, 0.05, 0.012, wht, [0, -0.1, 0.06])
		kk.cz(0.035, 0.03, red, [0, -0.1, 0.095], 16)
		kk.box(0.26, 0.03, 0.12, ylw, [0, 0.165, 0.005])
		for y in [-0.08, 0.08]:
			kk.box(0.18, 0.02, 0.04, C.steelDk, [0, y, -0.065])
	var fire_col := func(x: float, zc: float, face: float) -> void:
		var g = X.grp(x + face * 0.1, PY + 0.42, zc, PI / 2.0 if face > 0 else -PI / 2.0)
		var kk = X.K(g)
		kk.box(0.3, 0.02, 0.2, red, [0, -0.41, 0])
		kk.box(0.3, 0.62, 0.02, red, [0, -0.1, -0.09])
		for s in [-1, 1]:
			kk.box(0.02, 0.62, 0.2, red, [s * 0.14, -0.1, 0])
		kk.rb(0.32, 0.03, 0.22, 0.008, red, [0, 0.22, 0])
		kk.box(0.26, 0.12, 0.012, red, [0, 0.14, 0.095])
		X.lab(g, "N", "fireSign", 0.22, 0.07, [0, 0.14, 0.102], null, false)
		X.fire_extinguisher(kk, 0, -0.4, -0.01, 0.85)
	em_stop.call(16.6, shS.zCol, -1.0)
	em_stop.call(23.4, shS.zCol, -1.0)
	em_stop.call(9.6, shN.zCol, -1.0)
	em_stop.call(20.4, shN.zCol, -1.0)
	fire_col.call(20.0, shS.zCol, 1.0)
	fire_col.call(13.2, shN.zCol, 1.0)
	P.addBox(20.2, shS.zCol, 0.3, 0.3, 0, -1, PY + 1)
	P.addBox(13.4, shN.zCol, 0.3, 0.3, 0, -1, PY + 1)
	# ------------------------------------------------------------ tactile guide line on platform 1
	var tz: float = z_at.call(S, 1.14)
	k.box(0.3, 0.01, absf(tz - S.z1) - 0.02, M.tactLine, [7.05, PY + 0.005, (tz + S.z1) / 2.0])
	# ------------------------------------------------------------ north exit
	var nz0 := -52.0
	var nz1: float = N.z0
	var lx0 := -6.4
	var lx1 := -3.6
	var rx1 := 7.4
	var y_foot: float = L.height_at(7.4, -51.25) + 0.02
	k.box(lx1 - lx0, PY - GROUND, nz1 - nz0, M.concreteSide, [(lx0 + lx1) / 2.0, (PY + GROUND) / 2.0, (nz0 + nz1) / 2.0])
	k.box(lx1 - lx0, 0.02, nz1 - nz0, M.concrete, [(lx0 + lx1) / 2.0, PY - 0.008, (nz0 + nz1) / 2.0])
	P.addWalkBox((lx0 + lx1) / 2.0, (nz0 + nz1) / 2.0, lx1 - lx0, nz1 - nz0, 0, PY)
	var rg: T.Geometry = ctx.geo.extrude([[lx1, GROUND], [rx1, GROUND], [rx1, y_foot], [lx1, PY]], nz1 - nz0)
	k.mesh(rg, M.concreteSide, [0, 0, (nz0 + nz1) / 2.0])
	var Ls := sqrt((rx1 - lx1) ** 2 + (PY - y_foot) ** 2)
	var ang := atan2(y_foot - PY, rx1 - lx1)
	k.box(Ls, 0.02, nz1 - nz0, M.concrete, [(lx1 + rx1) / 2.0, (PY + y_foot) / 2.0 - 0.002, (nz0 + nz1) / 2.0], [0, 0, ang])
	P.addWalkRamp((lx1 + rx1) / 2.0, (nz0 + nz1) / 2.0, nz1 - nz0, rx1 - lx1, -PI / 2.0, y_foot, PY)
	k.box(1.6, 0.04, 2.0, M.paving, [8.2, L.height_at(8.2, -52.5) + 0.0, -52.3])
	k.box(1.0, 0.04, 1.5, M.paving, [7.9, y_foot - 0.01, -51.25])
	var ramp_y2 := func(xx: float, _z: float) -> float: return PY if xx <= lx1 else PY + (xx - lx1) / (rx1 - lx1) * (y_foot - PY)
	U.railing(k, [[lx0 + 0.05, nz0 + 0.06], [lx1, nz0 + 0.06], [rx1, nz0 + 0.06]], ramp_y2, {"h": 1.1, "post": 1.8, "rails": [1.0, 0.55, 0.1], "bar": 0.15, "barLo": 0.12, "mat": M.fenceWhite, "postW": 0.06})
	U.railing(k, [[lx0 + 0.05, nz1], [lx0 + 0.05, nz0 + 0.06]], PY, {"h": 1.1, "post": 1.5, "rails": [1.0, 0.55, 0.1], "bar": 0.15, "mat": M.fenceWhite, "postW": 0.06})
	P.addAABB(lx0, nz0 - 0.1, rx1, nz0 + 0.12, -1, 5)
	P.addAABB(lx0 - 0.05, nz0, lx0 + 0.12, nz1, -1, 5)
	for h in [0.85, 0.65]:
		U.beam(k, [lx1, PY + h, nz1 - 0.08], [rx1, y_foot + h, nz1 - 0.08], 0.04, 0.04, M.stainless, true)
	for x in [-5.6, -4.45]:
		var kk = ctx.kit(k.group([x, PY, -50.55], 0.0))
		kk.rbox(0.26, 1.0, 0.4, 0.04, M.gateBody, [0, 0.5, 0])
		kk.box(0.28, 0.03, 0.42, M.gateTop, [0, 1.015, 0])
		var p1 := T.MeshObj.new(U.rect_plane(0.16, 0.16, A.atlases.face.r("icPad")), A.sign_mat("face", 1.15))
		p1.position = Vector3(0, 1.035, 0.08)
		p1.rotation.x = -PI / 2.0
		kk.parent.add(p1)
		var p2 := T.MeshObj.new(U.rect_plane(0.16, 0.16, A.atlases.face.r("icPad")), A.sign_mat("face", 1.15))
		p2.position = Vector3(0, 1.035, -0.1)
		p2.rotation = Vector3(-PI / 2.0, 0, PI)
		kk.parent.add(p2)
		var ind := T.MeshObj.new(U.rect_plane(0.08, 0.08, A.atlases.face.r("gateGo")), A.sign_mat("face", 1.2))
		ind.position = Vector3(0, 0.85, 0.202)
		kk.parent.add(ind)
		P.addBox(x, -50.55, 0.28, 0.42, 0, -1, 3)
	for x in [-6.2, -3.8]:
		k.cyl(0.05, 0.05, 2.35, M.shelterCol, [x, PY + 1.175, -51.9], null, 10)
	k.box(2.8, 0.08, 2.2, M.shelterRoof, [-5.0, PY + 2.4, -51.0])
	k.box(2.84, 0.18, 0.05, M.shelterFascia, [-5.0, PY + 2.33, -49.9])
	k.box(2.84, 0.035, 0.055, M.pinkBand, [-5.0, PY + 2.27, -49.9])
	A.board("misc", "northExit", 1.2, 0.307, [-5.0, PY + 2.05, -49.93], 0.0, {"frame": M.shelterFascia, "border": 0.03, "lit": 0.95})
	k.box(1.22, 0.025, 0.07, M.tube, [-5.0, PY + 2.34, -51.0]).cast_shadow = false
