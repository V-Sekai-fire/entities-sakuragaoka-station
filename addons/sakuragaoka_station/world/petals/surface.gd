# petals/surface.js: the surface index. Bins every near-horizontal triangle of the static scenery
# (built by the modules before us) into a 2D grid so petals can be laid EXACTLY on what is rendered
# (asphalt with its lift, curbs, sidewalks, plaza paving, platform tops, ballast, bench seats, table
# tops, vending machine tops) and so roofs / eaves / shelters can be detected (petals never lie or
# fall indoors). Excluded: sakura trees (their canopies must not count as roofs), instanced meshes,
# the no-outline layer (alpha cards), dynamic objects. With no scenery at all every query returns
# NaN and callers fall back to the analytic terrain. Triangles are float32, as the original's.
extends RefCounted

var x0: float
var x1: float
var z0: float
var z1: float
var cell: float
var nx: int
var nz: int
var tris := PackedFloat32Array()
var nt := 0
var counts := PackedInt32Array()
var list := PackedInt32Array()
var count: int:
	get:
		return nt
var empty: bool:
	get:
		return nt == 0
var bounds: Dictionary


static func create(ctx, o: Dictionary = {}):
	var si = load("res://addons/sakuragaoka_station/world/petals/surface.gd").new()
	si._build(ctx, o.get("x0", -135.0), o.get("x1", 135.0), o.get("z0", -122.0), o.get("z1", 140.0), o.get("cell", 1.0), o.get("maxAbove", 11.0))
	return si


static func _skip(o, root) -> bool:
	var p = o
	while p != null and p != root:
		var n: String = p.name if p.name else ""
		if n.begins_with("sakura") or n.begins_with("petals") or n == "wires":
			return true
		p = p.parent()
	return false


func _build(ctx, ax0: float, ax1: float, az0: float, az1: float, acell: float, max_above: float) -> void:
	x0 = ax0
	x1 = ax1
	z0 = az0
	z1 = az1
	cell = acell
	bounds = {"x0": x0, "x1": x1, "z0": z0, "z1": z1}
	var L = ctx.L
	nx = int(ceil((x1 - x0) / cell))
	nz = int(ceil((z1 - z0) / cell))
	tris.resize(9 * 65536)
	nt = 0
	var root = ctx.static_root
	root.update_matrix_world(true)
	var meshes: Array = []
	root.traverse(func(o):
		if not o.is_mesh or o.is_instanced or o.get("isSkinnedMesh"):
			return
		if o.layer != 0:
			return
		if not o.visible:
			return
		meshes.append(o))
	for o in meshes:
		if _skip(o, root):
			continue
		var g = o.geometry
		var pa = g.position() if g else null
		if pa == null:
			continue
		if g.bounding_box == null:
			g.compute_bounding_box()
		if g.bounding_box == null:
			continue
		var bb: AABB = o.matrix_world * (g.bounding_box as AABB)
		if bb.end.x < x0 or bb.position.x > x1 or bb.end.z < z0 or bb.position.z > z1:
			continue
		var n: int = pa.count()
		var P: PackedFloat32Array = pa.array
		var W := PackedFloat32Array()
		W.resize(n * 3)
		var mw: Transform3D = o.matrix_world
		var e0 := mw.basis.x.x
		var e1 := mw.basis.x.y
		var e2 := mw.basis.x.z
		var e4 := mw.basis.y.x
		var e5 := mw.basis.y.y
		var e6 := mw.basis.y.z
		var e8 := mw.basis.z.x
		var e9 := mw.basis.z.y
		var e10 := mw.basis.z.z
		var e12 := mw.origin.x
		var e13 := mw.origin.y
		var e14 := mw.origin.z
		for i in n:
			var x: float = P[i * 3]
			var y: float = P[i * 3 + 1]
			var z: float = P[i * 3 + 2]
			W[i * 3] = e0 * x + e4 * y + e8 * z + e12
			W[i * 3 + 1] = e1 * x + e5 * y + e9 * z + e13
			W[i * 3 + 2] = e2 * x + e6 * y + e10 * z + e14
		var has_idx: bool = g.indexed
		var idx: PackedInt32Array = g.index
		var m: int = idx.size() if has_idx else n
		var d0: int = g.draw_start
		var dc: int = mini(m, d0 + (g.draw_count if g.draw_count >= 0 else m))
		var k := d0
		while k + 2 < dc:
			var a: int = idx[k] if has_idx else k
			var b: int = idx[k + 1] if has_idx else k + 1
			var c: int = idx[k + 2] if has_idx else k + 2
			k += 3
			var ax: float = W[a * 3]
			var ay: float = W[a * 3 + 1]
			var az: float = W[a * 3 + 2]
			var bx: float = W[b * 3]
			var by: float = W[b * 3 + 1]
			var bz: float = W[b * 3 + 2]
			var cx: float = W[c * 3]
			var cy: float = W[c * 3 + 1]
			var cz: float = W[c * 3 + 2]
			var ux := bx - ax
			var uy := by - ay
			var uz := bz - az
			var wx := cx - ax
			var wy := cy - ay
			var wz := cz - az
			var Nx := uy * wz - uz * wy
			var Ny := uz * wx - ux * wz
			var Nz := ux * wy - uy * wx
			var ln := sqrt(Nx * Nx + Ny * Ny + Nz * Nz)
			if ln < 1e-9:
				continue
			if absf(Ny) / ln < 0.38:
				continue  # walls / vertical faces
			var mnx := minf(ax, minf(bx, cx))
			var mxx := maxf(ax, maxf(bx, cx))
			var mnz := minf(az, minf(bz, cz))
			var mxz := maxf(az, maxf(bz, cz))
			if mxx < x0 or mnx > x1 or mxz < z0 or mnz > z1:
				continue
			var my := minf(ay, minf(by, cy))
			var hc: float = L.height_at((mnx + mxx) / 2.0, (mnz + mxz) / 2.0)
			if my > hc + max_above:
				continue  # high roofs / canopies are irrelevant
			if nt * 9 + 9 > tris.size():
				tris.resize(tris.size() * 2)
			var q := nt * 9
			tris[q] = ax
			tris[q + 1] = ay
			tris[q + 2] = az
			tris[q + 3] = bx
			tris[q + 4] = by
			tris[q + 5] = bz
			tris[q + 6] = cx
			tris[q + 7] = cy
			tris[q + 8] = cz
			nt += 1
	# CSR bins
	counts.resize(nx * nz + 1)
	counts.fill(0)
	for t in nt:
		var r := _range(t)
		for j in range(r[2], r[3] + 1):
			for i in range(r[0], r[1] + 1):
				counts[j * nx + i + 1] += 1
	for c in nx * nz:
		counts[c + 1] += counts[c]
	list.resize(counts[nx * nz])
	var fill := counts.slice(0, nx * nz)
	for t in nt:
		var r := _range(t)
		for j in range(r[2], r[3] + 1):
			for i in range(r[0], r[1] + 1):
				var c := j * nx + i
				list[fill[c]] = t
				fill[c] += 1


func _range(t: int) -> PackedInt32Array:
	var o := t * 9
	var mnx := minf(tris[o], minf(tris[o + 3], tris[o + 6]))
	var mxx := maxf(tris[o], maxf(tris[o + 3], tris[o + 6]))
	var mnz := minf(tris[o + 2], minf(tris[o + 5], tris[o + 8]))
	var mxz := maxf(tris[o + 2], maxf(tris[o + 5], tris[o + 8]))
	return PackedInt32Array([maxi(0, floori((mnx - x0) / cell)), mini(nx - 1, floori((mxx - x0) / cell)),
		maxi(0, floori((mnz - z0) / cell)), mini(nz - 1, floori((mxz - z0) / cell))])


## Visit the y of every triangle covering (x, z) (each() in the original), folded by mode: TOP keeps
## the highest y in [lo, hi], COVER the lowest y in (lo, hi].
const TOP := 0
const COVER := 1


func _fold(x: float, z: float, lo: float, hi: float, mode: int) -> float:
	var best := -INF if mode == TOP else INF
	var i := floori((x - x0) / cell)
	var j := floori((z - z0) / cell)
	if i < 0 or j < 0 or i >= nx or j >= nz:
		return best
	var c := j * nx + i
	for k in range(counts[c], counts[c + 1]):
		var o := list[k] * 9
		var ax: float = tris[o]
		var az: float = tris[o + 2]
		var bx: float = tris[o + 3]
		var bz: float = tris[o + 5]
		var cx: float = tris[o + 6]
		var cz: float = tris[o + 8]
		var d := (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
		if absf(d) < 1e-12:
			continue
		var l1 := ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
		var l2 := ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
		var l3 := 1.0 - l1 - l2
		if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
			continue
		var y := l1 * tris[o + 1] + l2 * tris[o + 4] + l3 * tris[o + 7]
		if mode == TOP:
			if y >= lo and y <= hi and y > best:
				best = y
		elif y > lo and y <= hi and y < best:
			best = y
	return best


## Highest rendered surface at (x, z) with lo <= y <= hi (NAN if none).
func top(x: float, z: float, lo: float, hi: float) -> float:
	var best := _fold(x, z, lo, hi, TOP)
	return NAN if best == -INF else best


## Lowest surface strictly above y0 (up to y1): a roof, eave, shelter, table... (INF if none).
func cover(x: float, z: float, y0: float, y1 = null) -> float:
	return _fold(x, z, y0, y0 + 12.0 if y1 == null else float(y1), COVER)
