# poles/facade.js: facade finder for service drops. Runs once, after every module has been built and
# just before the shared wire mesh is generated (see poles.gd: the hook on ctx.wires). It casts short
# segments against the static scene to find the real wall a drop wire should end on. Other modules'
# meshes are only read, never modified. A triangle loop with a coarse spatial grid and per-triangle
# AABB rejection.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const CELL := 12.0
const BC := 4.0

var ctx
var exclude: Array
var meshes = null
var grid := {}
var stamp := 0


func _init(c, excl: Array = []) -> void:
	ctx = c
	exclude = excl


func count() -> int:
	return meshes.size() if meshes != null else 0


func collect() -> int:
	meshes = []
	grid.clear()
	ctx.scene.update_matrix_world(true)
	ctx.scene.traverse(_visit)
	return meshes.size()


func _visit(o) -> void:
	if not o.is_mesh or o.is_instanced or not o.visible or o.name == "wires":
		return
	if o.layer != 0:  # alpha cut-outs / particles live on layer 1
		return
	if o.user_data and o.user_data.get("dynamic"):  # trains, animated things
		return
	var m = o.material
	if m == null or m is Array or exclude.has(m):
		return
	if m.alpha_test > 0.0:
		return
	var g: T.Geometry = o.geometry
	var pa: T.Attr = g.position() if g else null
	if pa == null or pa.item_size != 3:
		return
	if g.bounding_box == null:
		g.compute_bounding_box()
	if g.bounding_box == null:
		return
	var box: AABB = o.matrix_world * (g.bounding_box as AABB)
	if not is_finite(box.position.x):
		return
	# solid = an opaque cel surface a wire may end on; anything else (glass, lit panels) only blocks
	var solid: bool = not m.transparent and m.type == "toon"
	var identity: bool = o.matrix_world == Transform3D.IDENTITY
	var it := {"o": o, "g": g, "box": box, "identity": identity, "inv": null, "nm": null, "solid": solid, "stamp": 0, "buckets": null}
	meshes.append(it)
	var x0 := floori(box.position.x / CELL)
	var x1 := floori(box.end.x / CELL)
	var z0 := floori(box.position.z / CELL)
	var z1 := floori(box.end.z / CELL)
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			var k := "%d,%d" % [ix, iz]
			if not grid.has(k):
				grid[k] = []
			grid[k].append(it)


static func _intersects(a: AABB, b: AABB) -> bool:
	# Box3.intersectsBox: touching boxes intersect
	return not (b.end.x < a.position.x or b.position.x > a.end.x or b.end.y < a.position.y or b.position.y > a.end.y
		or b.end.z < a.position.z or b.position.z > a.end.z)


## lazily bucket a mesh's triangles on a local-space XZ grid (merged meshes can span the whole town)
func _bucketize(it: Dictionary) -> void:
	var g: T.Geometry = it.g
	var pos: PackedFloat32Array = g.position().array
	var idx = g.index if g.indexed else null
	var n: int = int((idx.size() if idx != null else pos.size() / 3) / 3)
	var bb: AABB = g.bounding_box
	var nx := maxi(1, ceili(bb.size.x / BC))
	var nz := maxi(1, ceili(bb.size.z / BC))
	if n < 400 or nx * nz < 3:
		it.buckets = false
		return
	var seen := PackedInt64Array()
	seen.resize(n)
	var b := {"x0": bb.position.x, "z0": bb.position.z, "nx": nx, "nz": nz, "cells": {}, "seen": seen, "q": 0}
	for t in n:
		var i0: int = (idx[t * 3] if idx != null else t * 3) * 3
		var i1: int = (idx[t * 3 + 1] if idx != null else t * 3 + 1) * 3
		var i2: int = (idx[t * 3 + 2] if idx != null else t * 3 + 2) * 3
		var ax := minf(pos[i0], minf(pos[i1], pos[i2]))
		var bx := maxf(pos[i0], maxf(pos[i1], pos[i2]))
		var az := minf(pos[i0 + 2], minf(pos[i1 + 2], pos[i2 + 2]))
		var bz := maxf(pos[i0 + 2], maxf(pos[i1 + 2], pos[i2 + 2]))
		var cx0 := maxi(0, floori((ax - b.x0) / BC))
		var cx1 := mini(nx - 1, floori((bx - b.x0) / BC))
		var cz0 := maxi(0, floori((az - b.z0) / BC))
		var cz1 := mini(nz - 1, floori((bz - b.z0) / BC))
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var k := cx * 100003 + cz
				if not b.cells.has(k):
					b.cells[k] = []
				b.cells[k].append(t)
	it.buckets = b


## meshes whose world AABB touches box
func near(box: AABB) -> Array:
	if meshes == null:
		collect()
	var out := []
	stamp += 1
	var x0 := floori(box.position.x / CELL)
	var x1 := floori(box.end.x / CELL)
	var z0 := floori(box.position.z / CELL)
	var z1 := floori(box.end.z / CELL)
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			var a = grid.get("%d,%d" % [ix, iz])
			if a == null:
				continue
			for it in a:
				if it.stamp == stamp:
					continue
				it.stamp = stamp
				if _intersects(it.box, box):
					out.append(it)
	return out


## nearest hit of segment A->B (world). returns {t (0..1), dist, point, normal, solid} or null
func seg(A: Vector3, B: Vector3):
	var lo := A.min(B) - Vector3(0.05, 0.05, 0.05)
	var hi := A.max(B) + Vector3(0.05, 0.05, 0.05)
	var list := near(AABB(lo, hi - lo))
	var best = null
	for it in list:
		var a := A
		var b := B
		if not it.identity:
			if it.inv == null:
				it.inv = (it.o.matrix_world as Transform3D).affine_inverse()
				it.nm = (it.o.matrix_world as Transform3D).basis.inverse().transposed()
			a = it.inv * A
			b = it.inv * B
		var dx := b.x - a.x
		var dy := b.y - a.y
		var dz := b.z - a.z
		var mnx := minf(a.x, b.x) - 0.01
		var mxx := maxf(a.x, b.x) + 0.01
		var mny := minf(a.y, b.y) - 0.01
		var mxy := maxf(a.y, b.y) + 0.01
		var mnz := minf(a.z, b.z) - 0.01
		var mxz := maxf(a.z, b.z) + 0.01
		var g: T.Geometry = it.g
		var pos: PackedFloat32Array = g.position().array
		var idx = g.index if g.indexed else null
		if it.buckets == null:
			_bucketize(it)
		var tris = null
		if it.buckets:
			var bk: Dictionary = it.buckets
			tris = []
			bk.q += 1
			var seen: PackedInt64Array = bk.seen
			var cx0 := maxi(0, floori((mnx - bk.x0) / BC))
			var cx1 := mini(bk.nx - 1, floori((mxx - bk.x0) / BC))
			var cz0 := maxi(0, floori((mnz - bk.z0) / BC))
			var cz1 := mini(bk.nz - 1, floori((mxz - bk.z0) / BC))
			for cx in range(cx0, cx1 + 1):
				for cz in range(cz0, cz1 + 1):
					var cl = bk.cells.get(cx * 100003 + cz)
					if cl != null:
						for t in cl:
							if seen[t] != bk.q:
								seen[t] = bk.q
								tris.append(t)
			bk.seen = seen
			if tris.is_empty():
				continue
		var n: int = tris.size() * 3 if tris != null else (idx.size() if idx != null else pos.size() / 3)
		var j := 0
		while j + 2 < n:
			var i: int = tris[j / 3] * 3 if tris != null else j
			j += 3
			var i0: int = (idx[i] if idx != null else i) * 3
			var i1: int = (idx[i + 1] if idx != null else i + 1) * 3
			var i2: int = (idx[i + 2] if idx != null else i + 2) * 3
			var x0 := pos[i0]
			var x1 := pos[i1]
			var x2 := pos[i2]
			if (x0 < mnx and x1 < mnx and x2 < mnx) or (x0 > mxx and x1 > mxx and x2 > mxx):
				continue
			var z0 := pos[i0 + 2]
			var z1 := pos[i1 + 2]
			var z2 := pos[i2 + 2]
			if (z0 < mnz and z1 < mnz and z2 < mnz) or (z0 > mxz and z1 > mxz and z2 > mxz):
				continue
			var y0 := pos[i0 + 1]
			var y1 := pos[i1 + 1]
			var y2 := pos[i2 + 1]
			if (y0 < mny and y1 < mny and y2 < mny) or (y0 > mxy and y1 > mxy and y2 > mxy):
				continue
			# Möller–Trumbore
			var e1 := Vector3(x1 - x0, y1 - y0, z1 - z0)
			var e2 := Vector3(x2 - x0, y2 - y0, z2 - z0)
			var p := Vector3(dy * e2.z - dz * e2.y, dz * e2.x - dx * e2.z, dx * e2.y - dy * e2.x)
			var det := e1.dot(p)
			if absf(det) < 1e-12:
				continue
			var inv := 1.0 / det
			var s := Vector3(a.x - x0, a.y - y0, a.z - z0)
			var u := s.dot(p) * inv
			if u < 0.0 or u > 1.0:
				continue
			var q := s.cross(e1)
			var v := (dx * q.x + dy * q.y + dz * q.z) * inv
			if v < 0.0 or u + v > 1.0:
				continue
			var t := e2.dot(q) * inv
			if t < 0.0 or t > 1.0:
				continue
			if best == null or t < best.t:
				var nrm := e1.cross(e2)
				if not it.identity:
					nrm = (it.nm as Basis) * nrm
				nrm = nrm.normalized()
				best = {"t": t, "nrm": nrm, "solid": it.solid}
	if best == null:
		return null
	var D := B - A
	var point := A + D * float(best.t)
	var nrm: Vector3 = best.nrm
	if nrm.dot(D) > 0.0:
		nrm = -nrm
	return {"t": best.t, "dist": best.t * D.length(), "point": point, "normal": nrm, "solid": best.solid}
