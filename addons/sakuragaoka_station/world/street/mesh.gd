# street/mesh.js: a small indexed-geometry builder for roads, sidewalks, gutters and decals, plus 2D
# polyline helpers. quad() and tri() take a wanted facing normal and fix the winding.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const UP := [0.0, 1.0, 0.0]


class MeshBuilder extends RefCounted:
	var pos := []
	var nrm := []
	var uv := []
	var col = null
	var idx := []
	var n := 0

	func _init(with_color: bool = false) -> void:
		col = [] if with_color else null

	func vert(x: float, y: float, z: float, u: float = 0.0, v: float = 0.0, nn = null, c = null) -> int:
		if nn == null:
			nn = UP
		pos.append_array([x, y, z])
		nrm.append_array([nn[0], nn[1], nn[2]])
		uv.append_array([u, v])
		if col != null:
			if c:
				col.append_array([c[0], c[1], c[2]])
			else:
				col.append_array([1.0, 1.0, 1.0])
		n += 1
		return n - 1

	func tri(a: int, b: int, c: int, want = null) -> void:
		if want == null:
			want = UP
		var p := pos
		var ax: float = p[a * 3]
		var ay: float = p[a * 3 + 1]
		var az: float = p[a * 3 + 2]
		var ux: float = p[b * 3] - ax
		var uy: float = p[b * 3 + 1] - ay
		var uz: float = p[b * 3 + 2] - az
		var vx: float = p[c * 3] - ax
		var vy: float = p[c * 3 + 1] - ay
		var vz: float = p[c * 3 + 2] - az
		var nx := uy * vz - uz * vy
		var ny := uz * vx - ux * vz
		var nz := ux * vy - uy * vx
		var d: float = nx * want[0] + ny * want[1] + nz * want[2]
		if absf(nx) + absf(ny) + absf(nz) < 1e-12:
			return
		if d >= 0:
			idx.append_array([a, b, c])
		else:
			idx.append_array([a, c, b])

	func quad(a: int, b: int, c: int, d: int, want = null) -> void:
		tri(a, b, c, want)
		tri(a, c, d, want)

	func is_empty() -> bool:
		return idx.is_empty()

	func geometry(compute_normals: bool = false) -> T.Geometry:
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(pos), 3))
		g.set_attribute("normal", T.Attr.new(PackedFloat32Array(nrm), 3))
		g.set_attribute("uv", T.Attr.new(PackedFloat32Array(uv), 2))
		if col != null:
			g.set_attribute("color", T.Attr.new(PackedFloat32Array(col), 3))
		g.set_index(PackedInt32Array(idx))
		if compute_normals:
			g.compute_vertex_normals()
		return g

	func mesh(material, opts: Dictionary = {}) -> T.MeshObj:
		var m := T.MeshObj.new(geometry(bool(opts.get("computeNormals", false))), material)
		m.cast_shadow = bool(opts.get("cast", false))
		m.receive_shadow = opts.get("receive", true) != false
		if opts.has("renderOrder"):
			m.render_order = opts.renderOrder
		if opts.get("name"):
			m.name = opts.name
		return m


## A rows by cols grid of vertices from fn(i, j) -> {x, y, z, u, v, c?, n?}; quads face want.
static func grid(b: MeshBuilder, rows: int, cols: int, fn: Callable, want = null) -> Array:
	if want == null:
		want = UP
	var base := []
	for i in rows:
		var row := []
		for j in cols:
			var p: Dictionary = fn.call(i, j)
			row.append(b.vert(p.x, p.y, p.z, p.u, p.v, p.get("n") if p.get("n") else want, p.get("c")))
		base.append(row)
	for i in rows - 1:
		for j in cols - 1:
			b.quad(base[i][j], base[i][j + 1], base[i + 1][j + 1], base[i + 1][j], want)
	return base


## Resamples a polyline so consecutive points are at most step apart: [{x, z, s, tx, tz}].
static func resample(pts: Array, step: float) -> Array:
	var out := []
	var s := 0.0
	for i in pts.size() - 1:
		var x0: float = pts[i][0]
		var z0: float = pts[i][1]
		var x1: float = pts[i + 1][0]
		var z1: float = pts[i + 1][1]
		var L := Vector2(x1 - x0, z1 - z0).length()
		if L < 1e-6:
			continue
		var n := maxi(1, int(ceilf(L / step)))
		var tx := (x1 - x0) / L
		var tz := (z1 - z0) / L
		for k in n:
			var f := float(k) / n
			out.append({"x": x0 + (x1 - x0) * f, "z": z0 + (z1 - z0) * f, "s": s + L * f, "tx": tx, "tz": tz})
		s += L
	var last: Array = pts[pts.size() - 1]
	var prev: Dictionary = out[out.size() - 1] if out.size() else {"tx": 1.0, "tz": 0.0}
	out.append({"x": float(last[0]), "z": float(last[1]), "s": s, "tx": prev.tx, "tz": prev.tz})
	for i in range(1, out.size() - 1):
		var a: Dictionary = out[i - 1]
		var c: Dictionary = out[i + 1]
		var tx: float = c.x - a.x
		var tz: float = c.z - a.z
		var l := Vector2(tx, tz).length()
		if l == 0.0:
			l = 1.0
		out[i].tx = tx / l
		out[i].tz = tz / l
	return out


## Point and tangent at arc length s along a resampled polyline.
static func point_at(rs: Array, s: float) -> Dictionary:
	if s <= 0:
		return rs[0]
	for i in range(1, rs.size()):
		if rs[i].s >= s:
			var a: Dictionary = rs[i - 1]
			var b: Dictionary = rs[i]
			var f: float = (s - a.s) / maxf(1e-6, b.s - a.s)
			return {"x": a.x + (b.x - a.x) * f, "z": a.z + (b.z - a.z) * f, "s": s, "tx": a.tx + (b.tx - a.tx) * f, "tz": a.tz + (b.tz - a.tz) * f}
	return rs[rs.size() - 1]
