# tools/reference.mjs's per-module numbers, computed on what a module added: triangles (instanced
# meshes times their count), meshes, bounds and vertex centroid over non-instanced meshes.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")


static func snapshot(root) -> Dictionary:
	var seen := {}
	root.traverse(func(o): seen[o.get_instance_id()] = true)
	return seen


static func added(root, before: Dictionary) -> Array:
	var out := []
	root.traverse(func(o):
		if not before.has(o.get_instance_id()):
			out.append(o))
	return out


static func of(objs: Array) -> Dictionary:
	var tris := 0.0
	var meshes := 0
	var inst := 0
	var instances := 0
	var verts := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var sum := Vector3.ZERO
	var sum_x := 0.0
	var sum_y := 0.0
	var sum_z := 0.0
	var by_colour := {}
	for o in objs:
		if not o.is_mesh:
			continue
		meshes += 1
		var g: T.Geometry = o.geometry
		if o.is_instanced:
			inst += 1
			instances += o.count
		if g and g.position():
			tris += g.triangle_count() * (o.count if o.is_instanced else 1)
		for m in o.materials():
			if m == null:
				continue
			var k := "#" + T.hex_string(m.color)
			by_colour[k] = by_colour.get(k, 0) + 1
		if g and g.position() and not o.is_instanced and o.name != "wires":
			if g.bounding_box == null:
				g.compute_bounding_box()
			if g.bounding_box != null:
				var b: AABB = o.matrix_world * (g.bounding_box as AABB)
				lo = lo.min(b.position)
				hi = hi.max(b.end)
			var pv: PackedVector3Array = o.matrix_world * g.position().vec3_array()
			for p in pv:
				sum_x += p.x
				sum_y += p.y
				sum_z += p.z
			verts += pv.size()
	var r := {"triangles": tris, "meshes": meshes, "instancedMeshes": inst, "instances": instances, "vertices": verts,
		"byColour": by_colour}
	r["bounds"] = null if lo.x == INF else {"min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z]}
	r["centroid"] = null if verts == 0 else [sum_x / verts, sum_y / verts, sum_z / verts]
	return r


## A module's numbers against the oracle's: triangles within tri_tol (relative), bounds within
## box_tol metres per coordinate. Returns [ok, reason].
static func compare(got: Dictionary, ref: Dictionary, tri_tol: float = 0.02, box_tol: float = 0.1) -> Array:
	var rt := float(ref.triangles)
	var dt := absf(got.triangles - rt) / maxf(rt, 1.0)
	if dt > tri_tol:
		return [false, "triangles %d vs oracle %d (%.2f%%)" % [got.triangles, rt, dt * 100.0]]
	if (got.bounds == null) != (ref.bounds == null):
		return [false, "bounds present %s vs oracle %s" % [got.bounds != null, ref.bounds != null]]
	if got.bounds != null:
		var worst := 0.0
		var where := ""
		for side in ["min", "max"]:
			for i in 3:
				var d := absf(float(got.bounds[side][i]) - float(ref.bounds[side][i]))
				if d > worst:
					worst = d
					where = "%s.%s" % [side, "xyz"[i]]
		if worst > box_tol:
			return [false, "bounds %s off by %.3f m" % [where, worst]]
	return [true, "triangles %d vs %d (%.2f%%)" % [got.triangles, rt, dt * 100.0]]
