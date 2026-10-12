# petals/plan.js: where petals LIE, the ground layout plan. Never uniform: clumpy clusters under
# every tree pushed downwind, wind-blown streaks, drifts hugging curbs / walls / gutters, small piles
# in road and platform corners, fence bases, ballast near the station, benches, vending machine
# tops, café tables + a few stuck to the café window, wall tops under trees, and a thin scatter
# elsewhere. All heights come from E.surf / E.surfP / E.SI (the exact rendered surfaces), so nothing
# floats or sinks; furniture is only decorated when the surface index proves it exists.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

var ctx
var L
var G
var E: Dictionary
var r
var Q: float
var SI
var WA := atan2(0.35, 0.9)
var wdx := cos(WA)
var wdz := sin(WA)


func _r() -> float:
	return r.f()


func _h(x: float, z: float) -> float:
	return L.height_at(x, z)


static func _fin(v) -> bool:
	return v != null and (v is float or v is int) and is_finite(float(v))


static func plan_ground(c, g, e: Dictionary) -> Dictionary:
	var p = load("res://addons/sakuragaoka_station/world/petals/plan.gd").new()
	p.ctx = c
	p.L = c.L
	p.G = g
	p.E = e
	p.r = e.r
	p.Q = e.Q
	p.SI = e.SI
	return p._run()


func clump_cell() -> int:
	return 0 if _r() < 0.5 else 1


func streak_cell() -> int:
	return 2 if _r() < 0.5 else 3


func dens(x: float, z: float) -> float:
	return E.dens.call(x, z)


func noise(x: float, z: float) -> float:
	return E.noise.call(x, z)


func gauss() -> float:
	return E.gauss.call()


func patch(x: float, z: float, l: float, w: float, ang: float, cell: int, o: Dictionary = {}) -> bool:
	return E.patch.call(x, z, l, w, ang, cell, o)


func clumpy(x: float, z: float, k: float = 1.0) -> float:
	return noise(x * 0.55 * k, z * 0.55 * k) * 0.65 + noise(x * 1.9 * k + 17.0, z * 1.9 * k - 9.0) * 0.35


func accept_clump(x: float, z: float, lo: float = 0.3, hi: float = 0.72) -> bool:
	var n := clumpy(x, z)
	var t := minf(1.0, maxf(0.0, (n - lo) / (hi - lo)))
	return _r() < t * t * (3.0 - 2.0 * t) * 1.15


func corner(x: float, z: float, ang: float, n: float, pile: float = 0.02) -> void:
	var sx := 0.26 + _r() * 0.2
	var sz := 0.12 + _r() * 0.08
	G.cluster(x, z, sx, sz, ang, int(T.js_round(n * Q)), {"pile": pile, "mode": "edge"})
	G.cluster(x + cos(ang) * 0.35, z + sin(ang) * 0.35, 0.6, 0.35, ang, int(T.js_round(n * 0.5 * Q)), {"mode": "edge"})


func _run() -> Dictionary:
	var trees: Array = E.trees
	# ------------------------------------------------------------------ 1. under every sakura
	var core := {"x": 6.0, "z": -8.0}
	var wsum := 0.0
	var tw: Array = []
	for t in trees:
		var d := Vector2(t.x - core.x, t.z - core.z).length()
		var p := maxf(0.12, minf(1.0, 1.0 - (d - 45.0) / 100.0))
		var w: float = (t.boost if t.boost else 1.0) * pow(t.r, 2.4) * p * p
		wsum += w
		tw.append(w)
	var tree_budget := 26000.0 * Q
	for i in trees.size():
		var t: Dictionary = trees[i]
		var n: float = minf(6000.0, T.js_round(tree_budget * tw[i] / maxf(1.0, wsum)))
		if n < 8:
			continue
		var tx: float = t.tx
		var tz: float = t.tz
		# canopy footprint centre, pushed downwind (petals fly ~0.3-0.6 r before landing)
		var cx: float = (t.x + tx) / 2.0 + wdx * t.r * 0.35
		var cz: float = (t.z + tz) / 2.0 + wdz * t.r * 0.35
		var reject := func(x: float, z: float) -> bool: return not accept_clump(x, z, 0.26, 0.7)
		# a) main patchy carpet under the crown
		G.cluster(cx, cz, t.r * 0.52, t.r * 0.42, WA, int(T.js_round(n * 0.34)), {"reject": reject})
		G.cluster(cx, cz, t.r * 0.8, t.r * 0.66, WA, int(T.js_round(n * 0.2)), {"reject": reject})
		# b) root ring: petals caught around the trunk base / tree pit
		var tr: float = (t.trunkR if t.trunkR else 0.3) + 0.04
		var k := 0
		while k < n * 0.1:
			var a := _r() * PI * 2.0
			var dd := tr + pow(_r(), 2.2) * 0.55
			G.on_ground(tx + cos(a) * dd, tz + sin(a) * dd, {})
			k += 1
		# c) downwind streaks trailing out from under the crown
		var ns := 2 + floori(_r() * 3.0)
		for s in ns:
			var ang := WA + (_r() - 0.5) * 0.7
			var length: float = t.r * (0.8 + _r() * 1.1) + 2.0
			var ox: float = cx + (_r() - 0.5) * t.r * 0.8
			var oz: float = cz + (_r() - 0.5) * t.r * 0.8
			var wid := 0.35 + _r() * 0.6
			G.streak(ox + cos(ang) * length * 0.5, oz + sin(ang) * length * 0.5, ang, length, wid, int(T.js_round(n * 0.3 / ns)), {})
		# d) sparse halo
		G.cluster(cx + wdx * t.r * 0.4, cz + wdz * t.r * 0.4, t.r * 1.5, t.r * 1.2, WA, int(T.js_round(n * 0.1)), {})
		# e) carpet patches (many petals per quad) where the drift is thickest
		var np := T.js_round(n / 30.0)
		k = 0
		var tries := 0
		while k < np and tries < np * 5:
			tries += 1
			var u: float = gauss() * t.r * 0.55
			var v: float = gauss() * t.r * 0.45
			var x := cx + u * wdx - v * wdz
			var z := cz + u * wdz + v * wdx
			if not accept_clump(x, z, 0.3, 0.66):
				continue
			var streaky := _r() < 0.35
			var l := 1.2 + _r() * 1.4 if streaky else 0.7 + _r() * 0.9
			var w := 0.4 + _r() * 0.35 if streaky else l * (0.7 + _r() * 0.3)
			var ang := WA + (_r() - 0.5) * 0.5 if streaky else _r() * PI * 2.0
			var cell := streak_cell() if streaky else clump_cell()
			if patch(x, z, l, w, ang, cell):
				k += 1

	# ------------------------------------------------------------------ 2. edges: curbs, walls, gutters, road edges
	for e in E.edges:
		var ax: float = e.a[0]
		var az: float = e.a[1]
		var bx: float = e.b[0]
		var bz: float = e.b[1]
		var mx := (ax + bx) / 2.0
		var mz := (az + bz) / 2.0
		var length := Vector2(bx - ax, bz - az).length()
		if length < 0.3:
			continue
		var d := dens(mx, mz)
		var kk := (0.25 + d * 1.1) * Q
		var tx := (bx - ax) / length
		var tz := (bz - az) / length
		var nx := -tz
		var nz := tx
		if e.kind == "curb":
			var yP = E.surfRaw.call(mx + nx * 0.22, mz + nz * 0.22, 0.55)
			var yN = E.surfRaw.call(mx - nx * 0.22, mz - nz * 0.22, 0.55)
			var low := -1 if not _fin(yP) else (1 if not _fin(yN) else (1 if yP < yN else -1))
			G.strip(ax, az, bx, bz, 6.5 * kk, {"sides": [low], "band": [0.015, 0.34], "hug": 2.6, "piles": 4.5, "mode": "edge"})
			G.strip(ax, az, bx, bz, 1.2 * kk, {"sides": [-low], "band": [0.04, 0.55], "hug": 1.6, "mode": "edge"})
		elif e.kind == "wall":
			G.strip(ax, az, bx, bz, 4.0 * kk, {"band": [0.03, 0.3], "hug": 2.4, "piles": 6, "mode": "edge"})
		elif e.kind == "gutter":
			G.strip(ax, az, bx, bz, 2.6 * kk, {"band": [0.0, 0.28], "hug": 1.4, "piles": 7, "mode": "edge"})
		else:
			G.strip(ax, az, bx, bz, 1.8 * kk, {"band": [0.05, 0.6], "hug": 1.8, "mode": "edge"})
	# petals caught on / around gutter grates
	for g in E.grates:
		var n := int(T.js_round((10.0 + _r() * 16.0) * Q * (0.4 + dens(g.x, g.z))))
		G.cluster(g.x, g.z, 0.3, 0.12, g.ang, n, {"pile": 0.006, "mode": "edge"})

	# ------------------------------------------------------------------ 3. road corners (drifts pile up where the wind eddies)
	var C := [
		[-3.35, 1.25, 2.4], [3.35, 1.25, 0.7], [-3.1, 3.2, -2.2], [3.1, 3.2, -0.9],
		[-14.95, -5.15, 2.6], [-9.05, -5.15, 0.5], [-14.95, 1.1, -2.6], [-9.05, 1.1, -0.5],
		[-14.95, -53.4, 2.6], [-9.05, -53.4, 0.5], [-14.95, -57.6, -2.6], [-9.05, -57.6, -0.5],
		[-14.95, -69.4, 2.6], [-9.05, -69.4, 0.5], [-14.95, -72.6, -2.6], [-9.05, -72.6, -0.5],
		[L.PLAZA.x0 + 0.3, L.PLAZA.z1 - 0.3, -0.8], [L.PLAZA.x1 - 0.3, L.PLAZA.z1 - 0.3, -2.3], [L.PLAZA.x1 - 0.4, L.PLAZA.z0 + 0.5, 2.3],
		[-8.9, -33.8, 0.6], [-15.2, -33.8, 2.5],
	]
	for cc in C:
		var x: float = cc[0]
		var z: float = cc[1]
		var a: float = cc[2]
		var cn := 70.0 + _r() * 70.0
		corner(x, z, a, cn, 0.018 + _r() * 0.012)
		var pl := 0.9 + _r() * 0.5
		var pw := 0.6 + _r() * 0.3
		patch(x + cos(a) * 0.45, z + sin(a) * 0.45, pl, pw, a, clump_cell())

	# ------------------------------------------------------------------ 4. wind streaks on open pavement + along the roads
	streaks_in(L.PLAZA.x0, L.PLAZA.z0, L.PLAZA.x1, L.PLAZA.z1, 34, 60)
	streaks_in(-60, -5, 60, 1, 30, 40)  # R3
	streaks_in(-14.7, -33, -9.3, -6, 8, 45)  # R2 south of the crossing
	streaks_in(-60, -57.5, 60, -53.5, 22, 35)  # R4 under the sakura tunnel
	# main street: petals combed into lines along the wheel tracks and the edges
	var zz := 2.0
	while zz < 128.0:
		var cx: float = L.street_center_x(zz)
		var sx: float = L.street_slope_x(zz)
		var d := dens(cx, zz)
		if _r() > 0.35 + d:
			zz += 2.4 + _r() * 3.0
			continue
		var off: float = r.pick([-2.45, -1.35, -0.05, 1.35, 2.45]) + (_r() - 0.5) * 0.3
		var ang := atan2(-1.0, -sx) + (_r() - 0.5) * 0.25
		var sl := 1.5 + _r() * 4.0
		var sw := 0.18 + _r() * 0.25
		G.streak(cx + off, zz, ang, sl, sw, int(T.js_round((30.0 + _r() * 40.0) * Q)), {})
		if _r() < 0.75:
			var pz := zz + (_r() - 0.5)
			var pl := 1.3 + _r() * 1.3
			var pw := 0.28 + _r() * 0.22
			var pa := ang + (_r() - 0.5) * 0.15
			patch(cx + off, pz, pl, pw, pa, streak_cell())
		if _r() < 0.3:
			var qx := cx + (_r() - 0.5) * 4.0
			var qz := zz + (_r() - 0.5) * 2.0
			var qa := WA + (_r() - 0.5) * 0.4
			var ql := 1.2 + _r() * 2.0
			var qw := 0.3 + _r() * 0.4
			G.streak(qx, qz, qa, ql, qw, int(T.js_round(30.0 * Q)), {})
		zz += 2.4 + _r() * 3.0

	# ------------------------------------------------------------------ 5. platforms: fence bases, corners, edges, streaks
	var PL: Dictionary = L.PLATFORM
	var plats := [
		{"p": PL.south, "back": PL.south.z1, "inward": -1.0, "edge": PL.south.z0},
		{"p": PL.north, "back": PL.north.z0, "inward": 1.0, "edge": PL.north.z1},
	]
	for PP in plats:
		var p: Dictionary = PP.p
		var back: float = PP.back
		var inward: float = PP.inward
		var edge: float = PP.edge
		# fence / wall base drift along the back edge
		var i := 0
		while i < 2400.0 * Q:
			i += 1
			var x: float = p.x0 + 0.1 + _r() * (p.x1 - p.x0 - 0.2)
			if not accept_clump(x * 1.7, back, 0.3, 0.75):
				continue
			var off := 0.03 + pow(_r(), 2.4) * 0.45
			on_p(x, back + inward * off)
		# tactile strip / track edge: a looser line of petals the trains keep brushing
		i = 0
		while i < 700.0 * Q:
			i += 1
			var x: float = p.x0 + 0.2 + _r() * (p.x1 - p.x0 - 0.4)
			if not accept_clump(x, edge * 1.3):
				continue
			on_p(x, edge - inward * (0.35 + _r() * 0.9))
		# corners
		for xz in [[p.x0 + 0.25, back + inward * 0.25], [p.x1 - 0.3, back + inward * 0.25], [p.x0 + 0.3, edge - inward * 0.5]]:
			i = 0
			while i < 90.0 * Q:
				i += 1
				var u := gauss() * 0.28
				var v := gauss() * 0.16
				var stack := maxf(0.0, 0.012 * (1.0 - (u * u + v * v) / 0.15)) * _r()
				on_p(xz[0] + u, xz[1] + v, {"stack": stack, "tilt": 0.5})
		# streaks and scatter across the deck
		for s in 16:
			var x: float = p.x0 + 1.0 + _r() * (p.x1 - p.x0 - 2.0)
			var z: float = p.z0 + 0.5 + _r() * (p.z1 - p.z0 - 1.0)
			var ang := WA + (_r() - 0.5) * 0.6
			var length := 1.2 + _r() * 3.0
			var cnt := T.js_round((25.0 + _r() * 35.0) * Q)
			var c := cos(ang)
			var sn := sin(ang)
			var k := 0
			while k < cnt:
				k += 1
				var u := (pow(_r(), 0.7) - 0.5) * length
				var v := gauss() * 0.14
				on_p(x + u * c - v * sn, z + u * sn + v * c)
		i = 0
		while i < 500.0 * Q:
			i += 1
			var x: float = p.x0 + _r() * (p.x1 - p.x0)
			var z: float = p.z0 + _r() * (p.z1 - p.z0)
			on_p(x, z)
		var raw_p := func(x: float, z: float): return L.PLATFORM.y if SI.empty else SI.top(x, z, L.PLATFORM.y - 0.25, L.PLATFORM.y + 0.25)
		for s in 44:
			var x: float = p.x0 + 1.0 + _r() * (p.x1 - p.x0 - 2.0)
			var z: float
			if _r() < 0.5:
				z = back + inward * (0.3 + _r() * 0.3)
			else:
				z = p.z0 + 0.6 + _r() * (p.z1 - p.z0 - 1.2)
			var along := absf(z - back) < 0.7
			var pl := 1.0 + _r() * 1.4
			var pw := 0.3 + _r() * 0.15 if along else 0.35 + _r() * 0.3
			var pa := (_r() - 0.5) * 0.12 if along else WA + (_r() - 0.5) * 0.6
			patch(x, z, pl, pw, pa, streak_cell(), {"surf": E.surfP, "raw": raw_p})

	# ------------------------------------------------------------------ 6. between the ballast near the station
	var i6 := 0
	while i6 < 3200.0 * Q:
		i6 += 1
		var x := -45.0 + pow(_r(), 1.2) * 120.0
		var zc: float = L.RAIL.zA if _r() < 0.5 else L.RAIL.zB
		var z := zc + gauss() * 1.5
		if z > PL.south.z0 and x > PL.south.x0 and x < PL.south.x1 + 6.0:
			continue  # under the platform overhang
		if z < PL.north.z1 and x > PL.north.x0 and x < PL.north.x1 + 6.0:
			continue
		if not accept_clump(x * 1.3, z * 1.3, 0.28, 0.7) and _r() < 0.6:
			continue
		on_ballast(x, z)
	# corridor margins further out (sparser)
	i6 = 0
	while i6 < 1400.0 * Q:
		i6 += 1
		var x := -90.0 + _r() * 180.0
		var z := -51.5 + _r() * 17.0
		if x > -8.0 and x < 47.0 and z > -51.0 and z < -35.0:
			continue
		if _r() > 0.2 + dens(x, z):
			continue
		on_ballast(x, z)

	# ------------------------------------------------------------------ 7. furniture: benches, vending tops, café tables & window, wall tops
	var benches: Array = []
	var station = ctx.services.get("station")
	if station != null:
		for b in station.get("benches", []):
			var bb: Dictionary = b.duplicate()
			bb["n"] = 14.0 + _r() * 16.0
			benches.append(bb)
	var plaza = ctx.services.get("plaza")
	if plaza != null:
		for b in plaza.get("benches", []):
			var bb: Dictionary = b.duplicate()
			bb["n"] = 12.0 + _r() * 20.0
			benches.append(bb)
	var v5: Dictionary = L.SPOTS.v5Bench
	benches.append({"x": v5.x, "z": v5.z, "y": _h(v5.x, v5.z) + v5.seatY, "rotY": v5.rotY, "len": v5.len, "n": 150.0, "heavy": true})
	if station == null:
		var b1: Dictionary = PL.benchB1
		benches.append({"x": b1.x, "z": b1.z, "y": PL.y + 0.44, "rotY": b1.rotY, "len": 1.6, "n": 18.0})
	var bench_count := 0
	for b in benches:
		if not _fin(b.get("x")) or not _fin(b.get("y")):
			continue
		# find the real seat top near the declared height (tolerant: 0.44 vs 0.45 conventions; the
		# probe grid covers the footprint so a gap between slats cannot hide the bench)
		var y := -INF
		var rot_y: float = b.rotY if b.get("rotY") else 0.0
		var blen: float = b.len if b.get("len") else 1.4
		if not SI.empty:
			var c := cos(rot_y)
			var sn := sin(rot_y)
			var hl := maxf(0.3, blen / 2.0 - 0.05)
			for ii in range(-2, 3):
				for jj in range(-2, 3):
					var lx := ii / 2.0 * hl
					var lz := jj / 2.0 * 0.17
					var t: float = SI.top(b.x + lx * c + lz * sn, b.z - lx * sn + lz * c, b.y - 0.12, b.y + 0.12)
					if is_finite(t) and t > y:
						y = t
		if not is_finite(y):
			continue
		var n := int(T.js_round(b.n * Q))
		bench_count += on_surface(b.x, b.z, rot_y, maxf(0.5, blen - 0.06), 0.4, y, 0.05, n, {"tilt": 0.2})
		if b.get("heavy"):  # a bench covered in petals: they also drift under / around it
			var c := cos(b.rotY)
			var s := sin(b.rotY)
			var k := 0
			while k < 70.0 * Q:
				k += 1
				var lx: float = (_r() - 0.5) * (b.len + 0.8)
				var lz := 0.35 + pow(_r(), 1.5) * 0.9
				G.on_ground(b.x + lx * c + lz * s, b.z - lx * s + lz * c, {})
	var vend_count := 0
	for v in L.VENDING:
		var base: float = v.y if _fin(v.get("y")) else _h(v.x, v.z)
		if SI.empty:
			continue
		var t: float = SI.top(v.x, v.z, base + 1.6, base + 2.2)
		if not is_finite(t):
			continue
		# settle toward the back edge (the wind rolls them off the front)
		var cnt := int(T.js_round((16.0 + _r() * 14.0) * Q))
		vend_count += on_surface(v.x, v.z, v.rotY, 0.86, 0.62, t, 0.06, cnt, {"tilt": 0.12, "size": 0.034, "tone": func(): return 0.45 + _r() * 0.7})
	var cafe_count := 0
	var sA = ctx.services.get("shopsA")
	if sA != null and sA.get("cafeTables") is Array:
		for tb in sA.cafeTables:
			if not _fin(tb.get("x")) or not _fin(tb.get("y")):
				continue
			if not exists(tb.x, tb.z, tb.y, 0.08):
				continue
			var tt: float = SI.top(tb.x, tb.z, tb.y - 0.08, tb.y + 0.08)
			var n := T.js_round((11.0 + _r() * 8.0) * Q)
			var i := 0
			var placed := 0
			while i < n * 3 and placed < n:
				i += 1
				var a := _r() * PI * 2.0
				var d := sqrt(_r()) * 0.34
				var x: float = tb.x + cos(a) * d
				var z: float = tb.z + sin(a) * d
				var y: float = SI.top(x, z, tt - 0.03, tt + 0.03)
				if not is_finite(y):
					continue
				var tone := 0.55 + _r() * 0.65
				if G.put(x, y, z, {"lift": 0.005, "tilt": 0.14, "size": 0.031, "tone": tone}):
					placed += 1
					cafe_count += 1
	if sA != null and sA.get("cafeWindow") != null and _fin(sA.cafeWindow.get("x")):
		var w: Dictionary = sA.cafeWindow.duplicate()
		w["w"] = w.w if w.get("w") else 2.0
		w["h"] = w.h if w.get("h") else 1.5
		G.on_pane(w, int(T.js_round(34.0 * Q)))
		cafe_count += 34
	if sA != null:  # a few blown onto the café terrace / doorstep (under the awning edge)
		var lot = L.lot_by_id("E1")
		var i := 0
		while i < 260.0 * Q:
			i += 1
			var lx := (_r() - 0.5) * 11.0
			var lz := -pow(_r(), 1.3) * 3.2
			var p: Dictionary = L.lot_to_world(lot, lx, lz)
			G.on_ground(p.x, p.z, {"mode": "edge"})
	var houses = ctx.services.get("houses")
	var wall_tops: Array = houses.get("wallTops", []) if houses != null and houses.get("wallTops") != null else []
	for wt in wall_tops:
		if not _fin(wt.get("x")) or not _fin(wt.get("y")):
			continue
		var near := 0.0
		for t in trees:
			var d := Vector2(t.x - wt.x, t.z - wt.z).length()
			if d < t.r + 4.0:
				near = maxf(near, 1.0 - d / (t.r + 4.0))
		if near <= 0.0:
			continue
		var top: float = NAN if SI.empty else SI.top(wt.x, wt.z, wt.y - 0.12, wt.y + 0.12)
		if not is_finite(top):
			continue
		var wlen: float = wt.len if wt.get("len") else 2.0
		on_surface(wt.x, wt.z, wt.rotY if wt.get("rotY") else 0.0, maxf(0.3, wlen - 0.1), 0.1, top, 0.04, int(T.js_round(near * wlen * 5.0 * Q)), {"tilt": 0.15})

	# ------------------------------------------------------------------ 8. thin scatter across the walkable town
	var S: Dictionary = L.WORLD.play
	var i8 := 0
	while i8 < 9000.0 * Q:
		i8 += 1
		var x: float = S.x0 + _r() * (S.x1 - S.x0)
		var z: float = S.z0 + _r() * (S.z1 - S.z0)
		var d := dens(x, z)
		if _r() > d * d * 0.9 + 0.03:
			continue
		G.on_ground(x, z, {})
	# levee path + slopes: a pink carpet under the sakura levee
	i8 = 0
	while i8 < 2600.0 * Q:
		i8 += 1
		var x := -95.0 + _r() * 190.0
		var z := -96.5 + _r() * 9.0
		if not accept_clump(x, z, 0.32, 0.7):
			continue
		G.on_ground(x, z, {})
	i8 = 0
	var k8 := 0
	while i8 < 400 and k8 < 110.0 * Q:
		i8 += 1
		var x := -95.0 + _r() * 190.0
		var z := -95.6 + _r() * 5.2
		if not accept_clump(x, z, 0.35, 0.68):
			continue
		var streaky := _r() < 0.5
		var pl := 1.4 + _r() * 1.2 if streaky else 0.8 + _r() * 0.8
		var pw := 0.4 + _r() * 0.3 if streaky else 0.6 + _r() * 0.5
		var pa := WA + (_r() - 0.5) * 0.4 if streaky else _r() * 6.28
		var cell := streak_cell() if streaky else clump_cell()
		if patch(x, z, pl, pw, pa, cell):
			k8 += 1
	return {"benchCount": bench_count, "vendCount": vend_count, "cafeCount": cafe_count}


func streaks_in(x0: float, z0: float, x1: float, z1: float, n: int, per: float, lmin: float = 1.4, lmax: float = 4.2) -> void:
	for i in n:
		var x := x0 + _r() * (x1 - x0)
		var z := z0 + _r() * (z1 - z0)
		if _r() > 0.25 + dens(x, z):
			continue
		var ang := WA + (_r() - 0.5) * 0.5
		var length := lmin + _r() * (lmax - lmin)
		var wid := 0.25 + _r() * 0.5
		G.streak(x, z, ang, length, wid, int(T.js_round(per * (0.6 + _r() * 0.8) * Q)), {})
		if _r() < 0.7:
			var pw := 0.35 + _r() * 0.35
			patch(x + cos(ang) * length * 0.2, z + sin(ang) * length * 0.2, minf(2.6, length * 0.7), pw, ang, streak_cell())


func on_p(x: float, z: float, o: Dictionary = {}) -> bool:
	var y = E.surfP.call(x, z)
	if y == null:
		return false
	return G.put(x, y, z, o)


func on_ballast(x: float, z: float) -> void:
	var y = E.surfRaw.call(x, z, 0.55)
	if not _fin(y):
		return
	# never on the rail heads
	for zc in [L.RAIL.zA, L.RAIL.zB]:
		for s in [-1.0, 1.0]:
			if absf(z - (zc + s * L.RAIL.gauge / 2.0)) < 0.06 and y > 0.08:
				return
	G.put(x, y, z, {"tilt": 0.55, "lift": 0.012})


func on_surface(cx: float, cz: float, rot_y: float, w: float, d: float, y_ref: float, tol: float, cnt: int, o: Dictionary = {}) -> int:
	var c := cos(rot_y)
	var s := sin(rot_y)
	var bx := (_r() - 0.5) * 0.7
	var bz := (_r() - 0.5) * 0.6
	var placed := 0
	var i := 0
	while i < cnt * 1.6 and placed < cnt:
		i += 1
		var lx := (_r() - 0.5) * w
		var lz := (_r() - 0.5) * d
		if _r() < 0.5:
			lx = (bx + gauss() * 0.22) * w * 0.5
			lz = (bz + gauss() * 0.3) * d * 0.5
		if absf(lx) > w / 2.0 or absf(lz) > d / 2.0:
			continue
		var x := cx + lx * c + lz * s
		var z := cz - lx * s + lz * c
		var y := y_ref
		if not SI.empty:
			y = SI.top(x, z, y_ref - tol, y_ref + tol)
			if not is_finite(y):
				continue
		var po := {"lift": 0.006, "tilt": o.get("tilt", 0.16), "size": o.get("size", 0.031)}
		if o.get("tone") != null:
			po["tone"] = o.tone.call()
		if G.put(x, y, z, po):
			placed += 1
	return placed


func exists(x: float, z: float, y: float, tol: float) -> bool:
	return false if SI.empty else is_finite(SI.top(x, z, y - tol, y + tol))
