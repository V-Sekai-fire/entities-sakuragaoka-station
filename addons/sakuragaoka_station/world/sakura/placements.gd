# sakura/placements.js: where every cherry tree goes (all positions from the layout), with species,
# LOD and the clearance envelopes that keep crowns off roads, platforms, the train and catenary
# envelope and neighbouring buildings.
extends RefCounted

const U = preload("res://addons/sakuragaoka_station/world/sakura/util.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")


## Returns {trees: [spec], floor: Callable, roadWeight: Callable, fromHouses: bool, placer}; keep it
## while the specs are used.
static func make_placements(ctx) -> Dictionary:
	return Placer.new(ctx).place()


class Placer extends RefCounted:
	var ctx
	var L
	var R: Rng
	var trees := []

	func _init(c) -> void:
		ctx = c
		L = c.L
		R = c.rng("sakura-placement")

	func jit(a: float) -> float:
		return (R.f() - 0.5) * 2.0 * a

	func sstep(a: float, b: float, x: float) -> float:
		var t := minf(1.0, maxf(0.0, (x - a) / (b - a)))
		return t * t * (3.0 - 2.0 * t)

	# ------------------------------------------------------------ smooth clearance floor (absolute y)

	## 1 on a road surface, fading to 0 within 1.3 m outside its edge
	func road_weight(x: float, z: float) -> float:
		var d := INF
		if z > 1.0 and z < 131.0:
			d = minf(d, absf(x - L.street_center_x(z)) - L.STREET.halfW)
		var R2: Dictionary = L.ROADS.R2
		if z > R2.z0 and z < R2.z1:
			d = minf(d, absf(x - R2.x) - R2.halfW)
		var R3: Dictionary = L.ROADS.R3
		if absf(x) < R3.x1:
			d = minf(d, absf(z - R3.z) - R3.halfW)
		var R4: Dictionary = L.ROADS.R4
		if absf(x) < R4.x1:
			d = minf(d, absf(z - R4.z) - R4.halfW)
		var R6: Dictionary = L.ROADS.R6
		if absf(x) < R6.x1:
			d = minf(d, absf(z - R6.z) - R6.halfW)
		return 1.0 - sstep(0.0, 1.3, d)

	func in_rect(x: float, z: float, x0: float, x1: float, z0: float, z1: float, m: float) -> float:
		return minf(minf(sstep(x0 - m, x0, x), 1.0 - sstep(x1, x1 + m, x)), minf(sstep(z0 - m, z0, z), 1.0 - sstep(z1, z1 + m, z)))

	func base_floor(x: float, z: float) -> float:
		var g: float = L.height_at(x, z)
		var f := g + 2.45 + 1.85 * road_weight(x, z)
		var PS: Dictionary = L.PLATFORM.south
		var PN: Dictionary = L.PLATFORM.north
		var plat := maxf(in_rect(x, z, PS.x0, L.PLATFORM.rampX1, PS.z0, PS.z1, 0.8), in_rect(x, z, PN.x0, L.PLATFORM.rampX1, PN.z0, PN.z1, 0.8))
		f = maxf(f, g + (L.PLATFORM.y + 3.65 - g) * plat)
		var SY: Dictionary = L.STATION.sideYard
		var sy := in_rect(x, z, SY.x0, SY.x1, SY.z0, SY.z1, 0.8)
		f = maxf(f, g + 2.45 + 2.2 * sy)
		var lev := in_rect(x, z, -140.0, 140.0, -94.6, -91.4, 1.0)
		f = maxf(f, (L.ROADS.R5.y + 2.65) * lev)
		return f

	func floor_plaza(x: float, z: float) -> float:
		var g: float = L.height_at(x, z)
		return maxf(base_floor(x, z), g + 2.55 + 1.45 * (1.0 - sstep(-6.5, -4.8, x)))

	func floor_shrine(x: float, z: float) -> float:
		return L.height_at(x, z) + 1.75 + 2.3 * road_weight(x, z)

	func floor_plaza_sw(x: float, z: float) -> float:
		return maxf(base_floor(x, z), L.height_at(x, z) + 3.3)

	func floor_corner_w(x: float, z: float) -> float:
		return L.height_at(x, z) + 1.8 + 2.4 * road_weight(x, z)

	func box(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, push: String) -> Dictionary:
		return {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "y0": y0, "y1": y1, "push": push}

	func pole_boxes(tx: float) -> Array:
		var out := []
		for p in L.POLE_RUNS.R4S:
			out.append(box(p.x - 0.55, p.x + 0.55, p.z - 0.55, p.z + 0.55, -5.0, 14.0, "x-" if tx < p.x else "x+"))
		return out

	func add(t: Dictionary) -> void:
		var d := {"lod": 0, "bark": "old", "floorAt": base_floor, "seed": "sakura-" + t.id}
		d.merge(t, true)
		trees.append(d)

	func place() -> Dictionary:
		# ------------------------------------------------------------ keep-out boxes
		var TRACK_N := box(-500.0, 500.0, -46.7, -39.3, -5.0, 8.6, "z-")
		var TRACK_S := TRACK_N.duplicate()
		TRACK_S.push = "z+"
		var STATION := box(L.STATION.x0 - 0.9, L.STATION.x1 + 0.9, L.STATION.z0 - 0.5, L.STATION.z1 + 0.7, -5.0, 10.5, "z+")
		var house_rear_nw := box(-63.0, -15.0, -31.3, -5.5, -5.0, 12.0, "z-")
		var house_rear_ne := box(26.5, 63.0, -31.3, -5.5, -5.0, 12.0, "z-")
		var house_n1w := box(-86.0, -15.0, -70.0, -58.7, -5.0, 12.0, "z+")
		var house_n1e := box(-9.0, 86.0, -70.0, -58.7, -5.0, 12.0, "z+")

		# ============================================================ the hero plaza tree
		var PT: Dictionary = L.PLAZA.tree
		add({"id": "plaza", "kind": "old", "meshH": 0.2, "x": PT.x, "z": PT.z, "height": 10.3, "spread": 7.3, "spreadZ": 6.6, "vr": 0.5, "trunkR": 0.5, "forkH": 2.35,
			"lean": [0.28, -0.12], "offset": [0.35, 0.35], "limbs": 6, "padR": 1.3, "thetaMax": 1.92, "archDirs": [0.25, 1.75], "lobes": 0.2,
			"gnarl": 0.16, "limbArch": 0.26, "rootReach": 1.15, "inner": 0.24, "floorAt": floor_plaza, "keepOut": [STATION], "base": {"type": "none"}})
		# ============================================================ the W3 garden tree leaning east over the street
		var w3: Dictionary = L.SPOTS.w3Sakura
		add({"id": "w3", "kind": "old", "meshH": 0.19, "x": w3.x, "z": w3.z, "height": 9.1, "spread": 5.8, "spreadZ": 4.7, "vr": 0.47, "trunkR": 0.36, "forkH": 2.65,
			"lean": [1.15, 0.05], "leanEarly": 0.5, "offset": [2.35, 0.25], "limbs": 5, "padR": 1.12, "thetaMax": 1.9, "archDirs": [0.1], "lobes": 0.2,
			"gnarl": 0.15, "limbArch": 0.2, "limbReach": 0.66, "rootReach": 0.95,
			"keepOut": [box(-20.0, -10.3, 22.4, 31.6, -5.0, 13.0, "x+"), box(-20.0, -5.3, 14.0, 22.35, -5.0, 13.0, "z+"), box(-20.0, -5.3, 31.65, 41.0, -5.0, 13.0, "z-")],
			# houses lays a ring of garden stones round this tree; only add our own when it is absent
			"base": {"type": "soil", "r": 1.0} if ctx.services.get("houses") != null else {"type": "stones", "r": 1.18}})
		# ============================================================ shrine: weeping cherry
		var sh: Dictionary = L.SPOTS.shrineSakura
		add({"id": "shrine", "kind": "weeping", "x": sh.x, "z": sh.z, "height": 7.0, "spread": 3.9, "trunkR": 0.34, "forkH": 2.5, "limbs": 6, "strands": 11, "hang": 3.6,
			"floorAt": floor_shrine, "base": {"type": "stones", "r": 1.25, "shimenawa": true},
			"keepOut": [box(-2.0, 24.0, 30.0, 47.9, -5.0, 20.0, "z+")]})
		# ============================================================ plaza south-west corner (young, keeps the crossing view clear)
		add({"id": "plazaSW", "kind": "young", "x": -7.6, "z": -7.8, "height": 6.1, "spread": 2.9, "vr": 0.72, "trunkR": 0.15, "forkH": 1.75, "lean": [0.12, 0.08],
			"offset": [0.2, 0.1], "limbs": 3, "padR": 0.82, "bark": "young", "thetaMax": 1.85, "gnarl": 0.1, "limbArch": 0.35, "rootReach": 0.45,
			"floorAt": floor_plaza_sw, "base": {"type": "pit", "size": 1.35}})
		# ============================================================ east of the station forecourt
		add({"id": "forecourtE", "kind": "medium", "x": 19.5, "z": -22.0, "height": 7.8, "spread": 4.1, "spreadZ": 3.8, "vr": 0.55, "trunkR": 0.3, "forkH": 2.25,
			"lean": [0.1, 0.25], "offset": [0.1, 0.7], "limbs": 4, "padR": 1.05, "keepOut": [STATION], "rootReach": 0.7, "base": {"type": "pit", "size": 1.6}})
		# ============================================================ behind the north platform fence
		for x in [2.0, 14.0, 26.0]:
			var px: float = x + jit(0.4)
			var ph := 8.4 + jit(0.4)
			var l0 := jit(0.3)
			var o0 := jit(0.4)
			add({"id": "platN%d" % int(x), "kind": "medium", "x": px, "z": -51.3, "height": ph, "spread": 4.1, "spreadZ": 3.5, "vr": 0.52, "trunkR": 0.3, "forkH": 2.5,
				"lean": [l0, 0.3], "offset": [o0, 1.0], "limbs": 4, "padR": 1.08, "rootReach": 0.75,
				"keepOut": [TRACK_N] + pole_boxes(x), "base": {"type": "soil", "r": 1.1}})
		# ============================================================ behind the south platform (x 20 stands in the station side yard)
		for x in [20.0, 32.0]:
			var px: float = x + jit(0.3)
			var ph := 8.0 + jit(0.4)
			var l0 := jit(0.3)
			var o0 := jit(0.3)
			add({"id": "platS%d" % int(x), "kind": "medium", "x": px, "z": -33.7 if x < 27.0 else -34.6, "height": ph, "spread": 3.9, "spreadZ": 3.3, "vr": 0.54, "trunkR": 0.28,
				"forkH": 2.4, "lean": [l0, -0.3], "offset": [o0, -1.0], "limbs": 4, "padR": 1.05, "rootReach": 0.7,
				"keepOut": [TRACK_S, house_rear_ne], "base": {"type": "soil", "r": 1.0}})
		# ============================================================ corridor: south row (NW / NE rear strips)
		var row_s := []
		var rx := -23.5
		while rx > -61.0:
			row_s.append(rx + jit(1.2))
			rx -= 8.6
		rx = 51.5
		while rx < 62.5:
			row_s.append(rx + jit(0.8))
			rx += 8.8
		for i in row_s.size():
			var x: float = row_s[i]
			var pz := -32.8 + jit(0.25)
			var ph := 7.2 + jit(0.6)
			var ps := 3.8 + jit(0.3)
			var l0 := jit(0.3)
			var o0 := jit(0.3)
			add({"id": "rowS%d" % i, "kind": "medium", "x": x, "z": pz, "height": ph, "spread": ps, "spreadZ": 3.3, "vr": 0.55, "trunkR": 0.27, "forkH": 2.2,
				"lean": [l0, -0.35], "offset": [o0, -1.25], "limbs": 4, "padR": 1.2, "lod": 1, "rootReach": 0.7,
				"keepOut": [TRACK_S, house_rear_nw if x < 0.0 else house_rear_ne], "base": {"type": "soil", "r": 1.0}})
		# ============================================================ corridor: north row along R4 (a tunnel over the lane)
		var poles := []
		for p in L.POLE_RUNS.R4S:
			poles.append(p.x)
		var push_pole := func(x: float) -> float:
			for p in poles:
				if absf(x - p) < 2.6:
					var dd: float = x - p
					x = p + (signf(dd) if dd != 0.0 else 1.0) * 2.7
			return x
		var row_n := []
		rx = -24.5
		while rx > -91.0:
			row_n.append(push_pole.call(rx + jit(1.1)))
			rx -= 8.3
		rx = 52.5
		while rx < 91.0:
			row_n.append(push_pole.call(rx + jit(1.1)))
			rx += 8.3
		for i in row_n.size():
			var x: float = row_n[i]
			var pz := -52.9 + jit(0.15)
			var ph := 7.7 + jit(0.6)
			var ps := 4.2 + jit(0.3)
			var l0 := jit(0.3)
			var o0 := jit(0.3)
			add({"id": "rowN%d" % i, "kind": "medium", "x": x, "z": pz, "height": ph, "spread": ps, "spreadZ": 3.7, "vr": 0.52, "trunkR": 0.29, "forkH": 2.35,
				"lean": [l0, -0.4], "offset": [o0, -1.45], "limbs": 4, "padR": 1.2, "lod": 2 if absf(x) > 80.0 else 1, "rootReach": 0.65,
				"keepOut": [TRACK_N, house_n1w if x < 0.0 else house_n1e] + pole_boxes(x), "base": {"type": "soil", "r": 0.95}})
		# ============================================================ levee rows on both shoulders of the levee path
		var stairs := [-12.0, 40.0]
		var levee := []
		for row in [[-90.8, -1.0, -124.0], [-95.3, 1.0, -119.5]]:
			var lx: float = row[2]
			while lx <= 125.0:
				var xx := lx + jit(1.3)
				var near := false
				for s in stairs:
					if absf(xx - s) < 5.0:
						near = true
				if not near:
					levee.append({"x": xx, "z": row[0] + jit(0.12), "side": row[1]})
				lx += 9.2 + jit(0.6)
		for i in levee.size():
			var p: Dictionary = levee[i]
			var ph := 7.6 + jit(0.8)
			var ps := 4.3 + jit(0.4)
			var tr := 0.3 + jit(0.04)
			var l0 := jit(0.35)
			var o0 := jit(0.4)
			var far: bool = absf(p.x) > 92.0
			add({"id": "levee%d" % i, "kind": "medium", "x": p.x, "z": p.z, "height": ph, "spread": ps, "spreadZ": 3.9, "vr": 0.52, "trunkR": tr, "forkH": 2.3,
				"lean": [l0, p.side * -0.35], "offset": [o0, p.side * -1.05], "limbs": 4, "padR": 1.7 if far else 1.35, "lod": 2 if far else 1,
				"inner": 0.12, "rootReach": 0.7, "base": {"type": "none" if absf(p.x) > 100.0 else "soil", "r": 1.0}})
		# ============================================================ street-corner / roadside trees in square pits
		add({"id": "cornerE", "kind": "medium", "x": 64.6, "z": -8.0, "height": 6.8, "spread": 3.4, "vr": 0.58, "trunkR": 0.24, "forkH": 2.1, "lean": [0.1, 0.1],
			"offset": [0.0, 0.0], "limbs": 4, "padR": 1.0, "lod": 1, "rootReach": 0.55, "keepOut": [house_rear_ne], "base": {"type": "pit", "size": 1.5}})
		add({"id": "cornerW", "kind": "weeping", "x": -64.8, "z": -8.4, "height": 6.0, "spread": 3.3, "trunkR": 0.26, "forkH": 2.3, "limbs": 5, "strands": 9, "hang": 3.0,
			"lod": 1, "floorAt": floor_corner_w, "base": {"type": "stones", "r": 1.05}})
		var r3_south := box(-95.0, 95.0, 3.0, 20.0, -5.0, 12.0, "z-")
		for e in [["r3W", -36.2], ["r3E", 33.8]]:
			add({"id": e[0], "kind": "young", "x": e[1], "z": 1.85, "height": 5.4, "spread": 2.5, "vr": 0.7, "trunkR": 0.13, "forkH": 1.9, "lean": [0.0, -0.1],
				"offset": [0.0, -0.5], "limbs": 3, "padR": 0.8, "bark": "young", "lod": 1, "rootReach": 0.35, "keepOut": [r3_south], "base": {"type": "pit", "size": 1.05}})
		# ============================================================ garden trees (houses.gardenSpots, else fallback lot corners)
		var others := []
		for t in trees:
			others.append([t.x, t.z])
		var spots = null
		var houses = ctx.services.get("houses")
		if houses != null:
			spots = houses.get("gardenSpots")
		var from_houses: bool = spots is Array
		if not from_houses:
			spots = []
			for e in [["W5", 1.0], ["E4", -1.0], ["W7", -1.0], ["E8", 1.0], ["W9", 1.0], ["E10", -1.0], ["W11", -1.0], ["E12", 1.0]]:
				var lot = L.lot_by_id(e[0])
				if lot == null:
					continue
				var w: float = lot.z1 - lot.z0
				var p: Dictionary = L.lot_to_world(lot, e[1] * (w / 2.0 - 2.0), -12.2)
				spots.append({"x": p.x, "z": p.z, "r": 1.6})
		var cand := []
		for s in spots:
			if s == null or not is_finite(s.x) or not is_finite(s.z) or s.get("r", 1.5) < 1.0:
				continue
			var c: Dictionary = s.duplicate()
			c["d"] = U.hypot2(s.x - 0.0, (s.z - 10.0) * 0.8)
			cand.append(c)
		var by_size_then_distance := func(a, b) -> float:
			var dr: float = b.get("r", 1.5) - a.get("r", 1.5)
			return dr if dr != 0.0 else a.d - b.d
		cand = T.stable_sort(cand, by_size_then_distance)
		var n_g := 0
		for s in cand:
			if n_g >= 7:
				break
			var far_ok := true
			for o in others:
				if not (U.hypot2(o[0] - s.x, o[1] - s.z) > 9.0):
					far_ok = false
					break
			if not far_ok:
				continue
			# the spot radius is the free garden around the trunk: tight front gardens get a slim young
			# tree, open corner plots a medium one whose crown stays near the plot
			var sr: float = s.get("r", 1.5)
			var young := sr < 1.7 or R.f() < 0.3
			var r := minf(2.0, sr + 0.3) if young else minf(3.0, sr * 1.35)
			var ph := 4.9 + jit(0.3) if young else 6.4 + jit(0.4)
			var l0 := jit(0.2)
			var l1 := jit(0.2)
			var o0 := jit(0.3)
			var o1 := jit(0.3)
			var base_type := "stones" if R.f() < 0.45 else "soil"
			add({"id": "garden%d" % n_g, "kind": "young" if young else "medium", "x": s.x, "z": s.z, "height": ph, "spread": r, "vr": 0.85 if young else 0.6,
				"trunkR": 0.14 if young else 0.22, "forkH": 1.8 if young else 2.1, "lean": [l0, l1], "offset": [o0, o1], "limbs": 3 if young else 4,
				"padR": 0.82 if young else 0.98, "bark": "young" if young else "old", "lod": 0 if s.d < 60.0 else 1, "rootReach": 0.35 if young else 0.55,
				"base": {"type": base_type, "r": minf(0.95, s.get("r", 1.5) * 0.7)}})
			others.append([s.x, s.z])
			n_g += 1
		# the specs' floorAt Callables are bound to this placer, which "placer" keeps alive
		return {"trees": trees, "floor": base_floor, "roadWeight": road_weight, "fromHouses": from_houses, "placer": self}
