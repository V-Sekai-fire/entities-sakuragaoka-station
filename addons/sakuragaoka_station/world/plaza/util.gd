# plaza/util.js: flat shapes with world UVs, ring sectors, UV-scaled boxes, a small indexed geometry
# builder, and the placing, instancing and matrix helpers the plaza parts share.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")


static func rect(x0: float, z0: float, x1: float, z1: float) -> Array:
	return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]


static func circle_pts(cx: float, cz: float, r: float, n: int = 48, a0: float = 0.0) -> Array:
	var out := []
	for i in n:
		var a := a0 + (float(i) / n) * TAU
		out.append([cx + cos(a) * r, cz + sin(a) * r])
	return out


## Horizontal polygon (XZ, with holes) at height y, facing up. uv(x, z) -> [u, v]; null keeps [x, z].
static func flat_shape(outer: Array, holes: Array = [], y: float = 0.0, uv = null) -> T.Geometry:
	var o := []
	for p in outer:
		o.append([float(p[0]), -float(p[1])])
	var hs := []
	for h in holes:
		var hh := []
		for p in h:
			hh.append([float(p[0]), -float(p[1])])
		hs.append(hh)
	var g := Geo.shape_geometry(Geo.shape(o, hs), 24)
	g.rotate_x(-PI / 2.0)
	var p := g.position()
	var uva: T.Attr = g.attributes.uv
	var n: T.Attr = g.attributes.normal
	for i in p.count():
		var x := p.get_x(i)
		var z := p.get_z(i)
		p.set_y(i, y)
		var w: Array = uv.call(x, z) if uv != null else [x, z]
		uva.set_xy(i, w[0], w[1])
		n.set_xyz(i, 0.0, 1.0, 0.0)
	return g


## Minimal indexed geometry builder; tri() winds each face along its vertices' normals.
class GeoBuilder extends RefCounted:
	var pos := PackedFloat64Array()
	var nor := PackedFloat64Array()
	var uv := PackedFloat64Array()
	var idx := PackedInt32Array()

	func v(x: float, y: float, z: float, nx: float, ny: float, nz: float, u: float = 0.0, w: float = 0.0) -> int:
		pos.append(x)
		pos.append(y)
		pos.append(z)
		nor.append(nx)
		nor.append(ny)
		nor.append(nz)
		uv.append(u)
		uv.append(w)
		return pos.size() / 3 - 1

	func _dir(a: int, b: int, c: int) -> float:
		var ax := pos[a * 3]
		var ay := pos[a * 3 + 1]
		var az := pos[a * 3 + 2]
		var ux := pos[b * 3] - ax
		var uy := pos[b * 3 + 1] - ay
		var uz := pos[b * 3 + 2] - az
		var vx := pos[c * 3] - ax
		var vy := pos[c * 3 + 1] - ay
		var vz := pos[c * 3 + 2] - az
		var cx := uy * vz - uz * vy
		var cy := uz * vx - ux * vz
		var cz := ux * vy - uy * vx
		var nx := nor[a * 3] + nor[b * 3] + nor[c * 3]
		var ny := nor[a * 3 + 1] + nor[b * 3 + 1] + nor[c * 3 + 1]
		var nz := nor[a * 3 + 2] + nor[b * 3 + 2] + nor[c * 3 + 2]
		return cx * nx + cy * ny + cz * nz

	func tri(a: int, b: int, c: int) -> void:
		if _dir(a, b, c) < 0.0:
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])

	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(a, c, d)

	func build() -> T.Geometry:
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(Array(pos)), 3))
		g.set_attribute("normal", T.Attr.new(PackedFloat32Array(Array(nor)), 3))
		g.set_attribute("uv", T.Attr.new(PackedFloat32Array(Array(uv)), 2))
		g.set_index(idx)
		g.compute_bounding_box()
		return g


## Solid ring sector around the origin: radius r0..r1, height y0..y1, angle a0..a1 (a point is
## (r cos a, y, r sin a)). UVs in metres / uvScale; caps close the ends unless it is a full circle.
static func ring_sector(r0: float, r1: float, y0: float, y1: float, a0: float, a1: float, seg: int = 16, opts: Dictionary = {}) -> T.Geometry:
	var s: float = opts.get("uvScale", 1.0) if opts.get("uvScale") else 1.0
	var full := absf(a1 - a0) >= TAU - 1e-6
	var caps: bool = opts.caps if opts.get("caps") != null else not full
	var B := GeoBuilder.new()
	var rm := (r0 + r1) / 2.0
	for e in [[y1, 1.0], [y0, -1.0]]:
		var y: float = e[0]
		var ny: float = e[1]
		if opts.get("noBottom", false) and ny < 0.0:
			continue
		var prev := []
		for i in seg + 1:
			var a := a0 + (a1 - a0) * i / seg
			var u := a * rm / s
			var ia := B.v(r0 * cos(a), y, r0 * sin(a), 0.0, ny, 0.0, u, 0.0)
			var ib := B.v(r1 * cos(a), y, r1 * sin(a), 0.0, ny, 0.0, u, (r1 - r0) / s)
			if not prev.is_empty():
				B.quad(prev[0], prev[1], ib, ia)
			prev = [ia, ib]
	for e in [[r1, 1.0], [r0, -1.0]]:
		var r: float = e[0]
		var sg: float = e[1]
		if r <= 1e-5:
			continue
		var prev := []
		for i in seg + 1:
			var a := a0 + (a1 - a0) * i / seg
			var nx := cos(a) * sg
			var nz := sin(a) * sg
			var u := a * r / s
			var ib := B.v(r * cos(a), y0, r * sin(a), nx, 0.0, nz, u, 0.0)
			var it := B.v(r * cos(a), y1, r * sin(a), nx, 0.0, nz, u, (y1 - y0) / s)
			if not prev.is_empty():
				B.quad(prev[0], prev[1], it, ib)
			prev = [ib, it]
	if caps:
		for e in [[a0, -1.0], [a1, 1.0]]:
			var a: float = e[0]
			var sg: float = e[1]
			var tx := -sin(a) * sg
			var tz := cos(a) * sg
			var q := [[r0, y0], [r1, y0], [r1, y1], [r0, y1]]
			var uvs := [[0.0, 0.0], [(r1 - r0) / s, 0.0], [(r1 - r0) / s, (y1 - y0) / s], [0.0, (y1 - y0) / s]]
			var ids := []
			for kk in 4:
				var rr: float = q[kk][0]
				ids.append(B.v(rr * cos(a), q[kk][1], rr * sin(a), tx, 0.0, tz, uvs[kk][0], uvs[kk][1]))
			B.quad(ids[0], ids[1], ids[2], ids[3])
	return B.build()


## Flat annulus (horizontal) with polar UVs: u = angle * u_rep / TAU, v = (r - r0) / (r1 - r0).
static func annulus(r0: float, r1: float, y: float, seg: int = 64, rings: int = 4, u_rep: float = 1.0) -> T.Geometry:
	var B := GeoBuilder.new()
	var rows := []
	for j in rings + 1:
		var r := r0 + (r1 - r0) * j / rings
		var row := []
		for i in seg + 1:
			var a := TAU * i / seg
			row.append(B.v(r * cos(a), y, r * sin(a), 0.0, 1.0, 0.0, u_rep * i / seg, float(j) / rings))
		rows.append(row)
	for j in rings:
		for i in seg:
			B.quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i])
	return B.build()


## BoxGeometry whose UVs are scaled to metres / s on every face.
static func box_uv(w: float, h: float, d: float, s: float = 1.0, off: Array = [0.0, 0.0]) -> T.Geometry:
	var g := Geo.box(w, h, d)
	var uv: T.Attr = g.attributes.uv
	var dims := [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]]
	for f in 6:
		for k in 4:
			var i := f * 4 + k
			uv.set_xy(i, uv.get_x(i) * dims[f][0] / s + off[0], uv.get_y(i) * dims[f][1] / s + off[1])
	return g


## A mesh from a geometry placed into parent, with shadows (opts: cast, receive).
static func put(parent, geo, material, pos: Array = [0, 0, 0], rot = null, opts: Dictionary = {}):
	var m := T.MeshObj.new(geo, material)
	m.position = Vector3(pos[0], pos[1], pos[2])
	if rot != null:
		m.rotation = Vector3(rot[0] if rot[0] else 0.0, rot[1] if rot[1] else 0.0, rot[2] if rot[2] else 0.0)
	m.cast_shadow = opts.get("cast", true)
	m.receive_shadow = opts.get("receive", true)
	parent.add(m)
	return m


## Instanced mesh from a list of matrices (and optional colours).
static func instanced(geo, material, mats: Array, colors = null, opts: Dictionary = {}):
	var im := T.InstancedMesh.new(geo, material, maxi(1, mats.size()))
	im.count = mats.size()
	for i in mats.size():
		im.set_matrix_at(i, mats[i])
		if colors != null:
			im.set_color_at(i, colors[i])
	im.cast_shadow = opts.get("cast", false)
	im.receive_shadow = opts.get("receive", true)
	return im


## A matrix from position, euler (order YXZ) and scale (a number or [x, y, z]).
static func mtx(x: float, y: float, z: float, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0, sc = 1.0) -> Transform3D:
	var s := Vector3(sc[0], sc[1], sc[2]) if sc is Array else Vector3(sc, sc, sc)
	var q := Basis.from_euler(Vector3(rx, ry, rz), EULER_ORDER_YXZ).get_rotation_quaternion()
	return T.compose(Vector3(x, y, z), q, s)


## Wind sway for small outline-free foliage cards. The port's sway lives in the renderer's foliage
## shader, so this only marks the material as the original does.
static func add_sway(_ctx, material, amp: float, mode: String = "up"):
	if material.user_data.get("plazaSway"):
		return material
	material.user_data["plazaSway"] = {"amp": amp, "mode": mode}
	return material
