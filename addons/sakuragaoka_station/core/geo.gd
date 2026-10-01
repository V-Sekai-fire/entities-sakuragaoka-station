# three.js r170's geometry generators, ported so a module's triangle counts and vertex layout match
# the original, and the helpers of src/core/geo.js (shared unit geometries, the placement kit,
# extrude, catenary, mergeMeshes, the wire list).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Earcut = preload("res://addons/sakuragaoka_station/core/earcut.gd")


static func _make(idx, pos: PackedFloat32Array, nor: PackedFloat32Array, uv: PackedFloat32Array) -> T.Geometry:
	var g := T.Geometry.new()
	if idx != null:
		g.set_index(idx)
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


# ---------------------------------------------------------------- BoxGeometry

static func box(width: float = 1.0, height: float = 1.0, depth: float = 1.0, wsg: int = 1, hsg: int = 1, dsg: int = 1) -> T.Geometry:
	var st := {"idx": PackedInt32Array(), "pos": PackedFloat32Array(), "nor": PackedFloat32Array(), "uv": PackedFloat32Array(), "nv": 0, "gs": 0}
	var g := T.Geometry.new()
	_box_plane(g, st, 2, 1, 0, -1, -1, depth, height, width, dsg, hsg, 0)
	_box_plane(g, st, 2, 1, 0, 1, -1, depth, height, -width, dsg, hsg, 1)
	_box_plane(g, st, 0, 2, 1, 1, 1, width, depth, height, wsg, dsg, 2)
	_box_plane(g, st, 0, 2, 1, 1, -1, width, depth, -height, wsg, dsg, 3)
	_box_plane(g, st, 0, 1, 2, 1, -1, width, height, depth, wsg, hsg, 4)
	_box_plane(g, st, 0, 1, 2, -1, -1, width, height, -depth, wsg, hsg, 5)
	g.set_index(st.idx)
	g.set_attribute("position", T.Attr.new(st.pos, 3))
	g.set_attribute("normal", T.Attr.new(st.nor, 3))
	g.set_attribute("uv", T.Attr.new(st.uv, 2))
	return g


static func _box_plane(g: T.Geometry, st: Dictionary, u: int, v: int, w: int, udir: float, vdir: float, width: float, height: float, depth: float, gx: int, gy: int, mi: int) -> void:
	var sw := width / gx
	var sh := height / gy
	var wh := width / 2.0
	var hh := height / 2.0
	var dh := depth / 2.0
	var gx1 := gx + 1
	var gy1 := gy + 1
	var vc := 0
	var gc := 0
	var pos: PackedFloat32Array = st.pos
	var nor: PackedFloat32Array = st.nor
	var uv: PackedFloat32Array = st.uv
	var idx: PackedInt32Array = st.idx
	for iy in gy1:
		var y := iy * sh - hh
		for ix in gx1:
			var x := ix * sw - wh
			var vec := Vector3.ZERO
			vec[u] = x * udir
			vec[v] = y * vdir
			vec[w] = dh
			pos.append(vec.x); pos.append(vec.y); pos.append(vec.z)
			var n := Vector3.ZERO
			n[w] = 1.0 if depth > 0.0 else -1.0
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			uv.append(float(ix) / gx)
			uv.append(1.0 - (float(iy) / gy))
			vc += 1
	var nv: int = st.nv
	for iy in gy:
		for ix in gx:
			var a := nv + ix + gx1 * iy
			var b := nv + ix + gx1 * (iy + 1)
			var c := nv + (ix + 1) + gx1 * (iy + 1)
			var d := nv + (ix + 1) + gx1 * iy
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(c); idx.append(d)
			gc += 6
	st.pos = pos
	st.nor = nor
	st.uv = uv
	st.idx = idx
	g.add_group(st.gs, gc, mi)
	st.gs += gc
	st.nv += vc


# ---------------------------------------------------------------- PlaneGeometry

static func plane(width: float = 1.0, height: float = 1.0, wsg: int = 1, hsg: int = 1) -> T.Geometry:
	var wh := width / 2.0
	var hh := height / 2.0
	var gx := int(floor(wsg))
	var gy := int(floor(hsg))
	var gx1 := gx + 1
	var gy1 := gy + 1
	var sw := width / gx
	var sh := height / gy
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	for iy in gy1:
		var y := iy * sh - hh
		for ix in gx1:
			var x := ix * sw - wh
			pos.append(x); pos.append(-y); pos.append(0.0)
			nor.append(0.0); nor.append(0.0); nor.append(1.0)
			uv.append(float(ix) / gx)
			uv.append(1.0 - (float(iy) / gy))
	for iy in gy:
		for ix in gx:
			var a := ix + gx1 * iy
			var b := ix + gx1 * (iy + 1)
			var c := (ix + 1) + gx1 * (iy + 1)
			var d := (ix + 1) + gx1 * iy
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(c); idx.append(d)
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- CircleGeometry

static func circle(radius: float = 1.0, segments: int = 32, theta_start: float = 0.0, theta_length: float = TAU) -> T.Geometry:
	segments = maxi(3, segments)
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array([0.0, 0.0, 0.0])
	var nor := PackedFloat32Array([0.0, 0.0, 1.0])
	var uv := PackedFloat32Array([0.5, 0.5])
	for s in segments + 1:
		var seg := theta_start + float(s) / segments * theta_length
		var x := radius * cos(seg)
		var y := radius * sin(seg)
		pos.append(x); pos.append(y); pos.append(0.0)
		nor.append(0.0); nor.append(0.0); nor.append(1.0)
		uv.append((pos[pos.size() - 3] / radius + 1.0) / 2.0)
		uv.append((pos[pos.size() - 2] / radius + 1.0) / 2.0)
	for i in range(1, segments + 1):
		idx.append(i); idx.append(i + 1); idx.append(0)
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- CylinderGeometry / ConeGeometry

static func cylinder(r_top: float = 1.0, r_bot: float = 1.0, height: float = 1.0, radial: int = 32, hsegs: int = 1, open_ended: bool = false, theta_start: float = 0.0, theta_length: float = TAU) -> T.Geometry:
	radial = int(floor(radial))
	hsegs = int(floor(hsegs))
	var g := T.Geometry.new()
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var index := 0
	var index_array := []
	var half := height / 2.0
	var group_start := 0
	# torso
	var gc := 0
	var slope := (r_bot - r_top) / height
	for y in hsegs + 1:
		var row := []
		var v := float(y) / hsegs
		var radius := v * (r_bot - r_top) + r_top
		for x in radial + 1:
			var u := float(x) / radial
			var theta := u * theta_length + theta_start
			var st := sin(theta)
			var ct := cos(theta)
			pos.append(radius * st); pos.append(-v * height + half); pos.append(radius * ct)
			var n := Vector3(st, slope, ct).normalized()
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			uv.append(u); uv.append(1.0 - v)
			row.append(index)
			index += 1
		index_array.append(row)
	for x in radial:
		for y in hsegs:
			var a: int = index_array[y][x]
			var b: int = index_array[y + 1][x]
			var c: int = index_array[y + 1][x + 1]
			var d: int = index_array[y][x + 1]
			if r_top > 0.0 or y != 0:
				idx.append(a); idx.append(b); idx.append(d)
				gc += 3
			if r_bot > 0.0 or y != hsegs - 1:
				idx.append(b); idx.append(c); idx.append(d)
				gc += 3
	g.add_group(group_start, gc, 0)
	group_start += gc
	if not open_ended:
		for top in [true, false]:
			var radius := r_top if top else r_bot
			if radius <= 0.0:
				continue
			var sign := 1.0 if top else -1.0
			var cstart := index
			gc = 0
			for x in range(1, radial + 1):
				pos.append(0.0); pos.append(half * sign); pos.append(0.0)
				nor.append(0.0); nor.append(sign); nor.append(0.0)
				uv.append(0.5); uv.append(0.5)
				index += 1
			var cend := index
			for x in radial + 1:
				var u := float(x) / radial
				var theta := u * theta_length + theta_start
				var ct := cos(theta)
				var st := sin(theta)
				pos.append(radius * st); pos.append(half * sign); pos.append(radius * ct)
				nor.append(0.0); nor.append(sign); nor.append(0.0)
				uv.append((ct * 0.5) + 0.5); uv.append((st * 0.5 * sign) + 0.5)
				index += 1
			for x in radial:
				var c := cstart + x
				var i := cend + x
				if top:
					idx.append(i); idx.append(i + 1); idx.append(c)
				else:
					idx.append(i + 1); idx.append(i); idx.append(c)
				gc += 3
			g.add_group(group_start, gc, 1 if top else 2)
			group_start += gc
	g.set_index(idx)
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


static func cone(radius: float = 1.0, height: float = 1.0, radial: int = 32, hsegs: int = 1, open_ended: bool = false, theta_start: float = 0.0, theta_length: float = TAU) -> T.Geometry:
	return cylinder(0.0, radius, height, radial, hsegs, open_ended, theta_start, theta_length)


# ---------------------------------------------------------------- SphereGeometry

static func sphere(radius: float = 1.0, ws: int = 32, hs: int = 16, phi_start: float = 0.0, phi_length: float = TAU, theta_start: float = 0.0, theta_length: float = PI) -> T.Geometry:
	ws = maxi(3, int(floor(ws)))
	hs = maxi(2, int(floor(hs)))
	var theta_end := minf(theta_start + theta_length, PI)
	var index := 0
	var grid := []
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	for iy in hs + 1:
		var row := []
		var v := float(iy) / hs
		var u_off := 0.0
		if iy == 0 and theta_start == 0.0:
			u_off = 0.5 / ws
		elif iy == hs and theta_end == PI:
			u_off = -0.5 / ws
		for ix in ws + 1:
			var u := float(ix) / ws
			var vx := -radius * cos(phi_start + u * phi_length) * sin(theta_start + v * theta_length)
			var vy := radius * cos(theta_start + v * theta_length)
			var vz := radius * sin(phi_start + u * phi_length) * sin(theta_start + v * theta_length)
			pos.append(vx); pos.append(vy); pos.append(vz)
			var n := Vector3(vx, vy, vz)
			n = n.normalized() if n.length_squared() > 0.0 else n
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			uv.append(u + u_off); uv.append(1.0 - v)
			row.append(index)
			index += 1
		grid.append(row)
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]
			var b: int = grid[iy][ix]
			var c: int = grid[iy + 1][ix]
			var d: int = grid[iy + 1][ix + 1]
			if iy != 0 or theta_start > 0.0:
				idx.append(a); idx.append(b); idx.append(d)
			if iy != hs - 1 or theta_end < PI:
				idx.append(b); idx.append(c); idx.append(d)
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- TorusGeometry

static func torus(radius: float = 1.0, tube_r: float = 0.4, radial: int = 12, tubular: int = 48, arc: float = TAU) -> T.Geometry:
	radial = int(floor(radial))
	tubular = int(floor(tubular))
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var v := float(j) / radial * TAU
			var vx := (radius + tube_r * cos(v)) * cos(u)
			var vy := (radius + tube_r * cos(v)) * sin(u)
			var vz := tube_r * sin(v)
			pos.append(vx); pos.append(vy); pos.append(vz)
			var n := Vector3(vx - radius * cos(u), vy - radius * sin(u), vz).normalized()
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			uv.append(float(i) / tubular); uv.append(float(j) / radial)
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(c); idx.append(d)
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- PolyhedronGeometry / IcosahedronGeometry

static func icosahedron(radius: float = 1.0, detail: int = 0) -> T.Geometry:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := [-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1]
	var ind := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	return polyhedron(verts, ind, radius, detail)


static func polyhedron(verts: Array, ind: Array, radius: float, detail: int) -> T.Geometry:
	var vb := []  # float64 vertex buffer as in JS
	var cols := detail + 1
	var i := 0
	while i < ind.size():
		var a := Vector3(verts[ind[i] * 3], verts[ind[i] * 3 + 1], verts[ind[i] * 3 + 2])
		var b := Vector3(verts[ind[i + 1] * 3], verts[ind[i + 1] * 3 + 1], verts[ind[i + 1] * 3 + 2])
		var c := Vector3(verts[ind[i + 2] * 3], verts[ind[i + 2] * 3 + 1], verts[ind[i + 2] * 3 + 2])
		var v := []
		for ci in cols + 1:
			v.append([])
			var aj := a.lerp(c, float(ci) / cols)
			var bj := b.lerp(c, float(ci) / cols)
			var rows := cols - ci
			for j in rows + 1:
				if j == 0 and ci == cols:
					v[ci].append(aj)
				else:
					v[ci].append(aj.lerp(bj, float(j) / rows))
		for ci in cols:
			for j in 2 * (cols - ci) - 1:
				var k := j / 2
				var tri: Array
				if j % 2 == 0:
					tri = [v[ci][k + 1], v[ci + 1][k], v[ci][k]]
				else:
					tri = [v[ci][k + 1], v[ci + 1][k + 1], v[ci + 1][k]]
				for p in tri:
					vb.append(p.x); vb.append(p.y); vb.append(p.z)
		i += 3
	var pos := PackedFloat32Array()
	pos.resize(vb.size())
	var k := 0
	while k < vb.size():
		var p := Vector3(vb[k], vb[k + 1], vb[k + 2]).normalized() * radius
		pos[k] = p.x
		pos[k + 1] = p.y
		pos[k + 2] = p.z
		k += 3
	var uv := PackedFloat32Array()
	k = 0
	while k < pos.size():
		var p := Vector3(pos[k], pos[k + 1], pos[k + 2])
		uv.append(atan2(p.z, -p.x) / 2.0 / PI + 0.5)
		uv.append(1.0 - (atan2(-p.y, sqrt(p.x * p.x + p.z * p.z)) / PI + 0.5))
		k += 3
	var g := _make(null, pos, pos.duplicate(), uv)
	if detail == 0:
		g.compute_vertex_normals()
	else:
		g.normalize_normals()
	return g


# ---------------------------------------------------------------- LatheGeometry

static func lathe(points: Array, segments: int = 12, phi_start: float = 0.0, phi_length: float = TAU) -> T.Geometry:
	segments = int(floor(segments))
	phi_length = clampf(phi_length, 0.0, TAU)
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var init_n := []
	var nor := PackedFloat32Array()
	var inv := 1.0 / segments
	var prev := Vector3.ZERO
	var n := points.size()
	for j in n:
		if j == 0:
			var dx: float = points[j + 1].x - points[j].x
			var dy: float = points[j + 1].y - points[j].y
			var nn := Vector3(dy, -dx, 0.0)
			prev = nn
			nn = nn.normalized()
			init_n.append_array([nn.x, nn.y, nn.z])
		elif j == n - 1:
			init_n.append_array([prev.x, prev.y, prev.z])
		else:
			var dx: float = points[j + 1].x - points[j].x
			var dy: float = points[j + 1].y - points[j].y
			var nn := Vector3(dy, -dx, 0.0)
			var cur := nn
			nn = (nn + prev).normalized()
			init_n.append_array([nn.x, nn.y, nn.z])
			prev = cur
	for i in segments + 1:
		var phi := phi_start + i * inv * phi_length
		var s := sin(phi)
		var c := cos(phi)
		for j in n:
			pos.append(points[j].x * s); pos.append(points[j].y); pos.append(points[j].x * c)
			uv.append(float(i) / segments); uv.append(float(j) / (n - 1))
			nor.append(init_n[3 * j] * s); nor.append(init_n[3 * j + 1]); nor.append(init_n[3 * j] * c)
	for i in segments:
		for j in n - 1:
			var base := j + i * n
			var a := base
			var b := base + n
			var c2 := base + n + 1
			var d := base + 1
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(c2); idx.append(d); idx.append(b)
	var g := T.Geometry.new()
	g.set_index(idx)
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	return g


# ---------------------------------------------------------------- RoundedBoxGeometry (examples/jsm)

static func rounded_box(width: float = 1.0, height: float = 1.0, depth: float = 1.0, segments: int = 2, radius: float = 0.1) -> T.Geometry:
	segments = segments * 2 + 1
	radius = minf(minf(width / 2.0, height / 2.0), minf(depth / 2.0, radius))
	var g := box(1, 1, 1, segments, segments, segments)
	if segments == 1:
		return g
	var g2 := g.to_non_indexed()
	g.set_index(null)
	g.attributes["position"] = g2.attributes["position"]
	g.attributes["normal"] = g2.attributes["normal"]
	g.attributes["uv"] = g2.attributes["uv"]
	var bx := Vector3(width, height, depth) / 2.0 - Vector3(radius, radius, radius)
	var positions: PackedFloat32Array = g.attributes["position"].array
	var normals: PackedFloat32Array = g.attributes["normal"].array
	var half_seg := 0.5 / segments
	var i := 0
	while i < positions.size():
		var p := Vector3(positions[i], positions[i + 1], positions[i + 2])
		var nn := p
		nn.x -= T.sign(nn.x) * half_seg
		nn.y -= T.sign(nn.y) * half_seg
		nn.z -= T.sign(nn.z) * half_seg
		nn = nn.normalized()
		positions[i] = bx.x * T.sign(p.x) + nn.x * radius
		positions[i + 1] = bx.y * T.sign(p.y) + nn.y * radius
		positions[i + 2] = bx.z * T.sign(p.z) + nn.z * radius
		normals[i] = nn.x
		normals[i + 1] = nn.y
		normals[i + 2] = nn.z
		i += 3
	g.attributes["position"].array = positions
	g.attributes["normal"].array = normals
	return g


# ---------------------------------------------------------------- shapes, ShapeUtils, Extrude, ShapeGeometry
# A shape is {"pts": [[x, y], ...], "holes": [[[x, y], ...], ...]} with float64 coordinates, as a
# THREE.Shape made from points (its getPoints drops consecutive duplicates and does not close).

static func shape(points: Array, holes: Array = []) -> Dictionary:
	return {"pts": points, "holes": holes}


static func _path_points(pts: Array) -> Array:
	var out := []
	var last = null
	for p in pts:
		var q := [float(p[0]), float(p[1])]
		if last != null and last[0] == q[0] and last[1] == q[1]:
			continue
		out.append(q)
		last = q
	return out


static func shape_area(c: Array) -> float:
	var n := c.size()
	var a := 0.0
	var p := n - 1
	for q in n:
		a += c[p][0] * c[q][1] - c[q][0] * c[p][1]
		p = q
	return a * 0.5


static func is_clockwise(pts: Array) -> bool:
	return shape_area(pts) < 0.0


static func triangulate_shape(contour: Array, holes: Array) -> Array:
	var verts := PackedFloat64Array()
	var hole_idx := []
	_remove_dup_end(contour)
	for p in contour:
		verts.append(p[0]); verts.append(p[1])
	var hi := contour.size()
	for h in holes:
		_remove_dup_end(h)
	for h in holes:
		hole_idx.append(hi)
		hi += h.size()
		for p in h:
			verts.append(p[0]); verts.append(p[1])
	var tris := Earcut.triangulate(verts, hole_idx)
	var faces := []
	var i := 0
	while i + 2 < tris.size():
		faces.append([tris[i], tris[i + 1], tris[i + 2]])
		i += 3
	return faces


static func _remove_dup_end(points: Array) -> void:
	var l := points.size()
	if l > 2 and points[l - 1][0] == points[0][0] and points[l - 1][1] == points[0][1]:
		points.pop_back()


## ExtrudeGeometry(shape, {depth, bevelEnabled, bevelThickness, bevelSize, bevelOffset,
## bevelSegments, steps}) without extrudePath, with three.js's WorldUVGenerator.
static func extrude_shape(shp: Dictionary, opts: Dictionary) -> T.Geometry:
	var steps: int = opts.get("steps", 1)
	var depth: float = opts.get("depth", 1.0)
	var bevel_enabled: bool = opts.get("bevelEnabled", true)
	var bevel_thickness: float = opts.get("bevelThickness", 0.2)
	var bevel_size: float = opts.get("bevelSize", bevel_thickness - 0.1)
	var bevel_offset: float = opts.get("bevelOffset", 0.0)
	var bevel_segments: int = opts.get("bevelSegments", 3)
	if not bevel_enabled:
		bevel_segments = 0
		bevel_thickness = 0.0
		bevel_size = 0.0
		bevel_offset = 0.0
	var vertices := _path_points(shp.pts)
	var holes := []
	for h in shp.holes:
		holes.append(_path_points(h))
	if not is_clockwise(vertices):
		vertices.reverse()
		for h in holes.size():
			if is_clockwise(holes[h]):
				holes[h].reverse()
	var faces := triangulate_shape(vertices, holes)
	var contour := vertices
	var all := contour.duplicate()
	for h in holes:
		all.append_array(h)
	var vlen := all.size()
	var flen := faces.size()
	var contour_mv := []
	var il := contour.size()
	for i in il:
		contour_mv.append(_bevel_vec(contour[i], contour[(i - 1 + il) % il], contour[(i + 1) % il]))
	var holes_mv := []
	var verts_mv := contour_mv.duplicate()
	for h in holes:
		var one := []
		var hl: int = h.size()
		for i in hl:
			one.append(_bevel_vec(h[i], h[(i - 1 + hl) % hl], h[(i + 1) % hl]))
		holes_mv.append(one)
		verts_mv.append_array(one)
	var ph := PackedFloat64Array()  # placeholder, float64 as in JS
	for b in bevel_segments:
		var t := float(b) / bevel_segments
		var z := bevel_thickness * cos(t * PI / 2.0)
		var bs := bevel_size * sin(t * PI / 2.0) + bevel_offset
		for i in contour.size():
			ph.append(contour[i][0] + contour_mv[i][0] * bs); ph.append(contour[i][1] + contour_mv[i][1] * bs); ph.append(-z)
		for h in holes.size():
			for i in holes[h].size():
				ph.append(holes[h][i][0] + holes_mv[h][i][0] * bs); ph.append(holes[h][i][1] + holes_mv[h][i][1] * bs); ph.append(-z)
	var bs0 := bevel_size + bevel_offset
	for i in vlen:
		if bevel_enabled:
			ph.append(all[i][0] + verts_mv[i][0] * bs0); ph.append(all[i][1] + verts_mv[i][1] * bs0)
		else:
			ph.append(all[i][0]); ph.append(all[i][1])
		ph.append(0.0)
	for s in range(1, steps + 1):
		for i in vlen:
			if bevel_enabled:
				ph.append(all[i][0] + verts_mv[i][0] * bs0); ph.append(all[i][1] + verts_mv[i][1] * bs0)
			else:
				ph.append(all[i][0]); ph.append(all[i][1])
			ph.append(depth / steps * s)
	for b in range(bevel_segments - 1, -1, -1):
		var t := float(b) / bevel_segments
		var z := bevel_thickness * cos(t * PI / 2.0)
		var bs := bevel_size * sin(t * PI / 2.0) + bevel_offset
		for i in contour.size():
			ph.append(contour[i][0] + contour_mv[i][0] * bs); ph.append(contour[i][1] + contour_mv[i][1] * bs); ph.append(depth + z)
		for h in holes.size():
			for i in holes[h].size():
				ph.append(holes[h][i][0] + holes_mv[h][i][0] * bs); ph.append(holes[h][i][1] + holes_mv[h][i][1] * bs); ph.append(depth + z)
	var out := PackedFloat32Array()
	var uvs := PackedFloat32Array()
	var g := T.Geometry.new()
	# lids
	var start := 0
	if bevel_enabled:
		var off := 0
		for f in faces:
			_f3(ph, out, uvs, f[2] + off, f[1] + off, f[0] + off)
		off = vlen * (steps + bevel_segments * 2)
		for f in faces:
			_f3(ph, out, uvs, f[0] + off, f[1] + off, f[2] + off)
	else:
		for f in faces:
			_f3(ph, out, uvs, f[2], f[1], f[0])
		for f in faces:
			_f3(ph, out, uvs, f[0] + vlen * steps, f[1] + vlen * steps, f[2] + vlen * steps)
	g.add_group(start, out.size() / 3 - start, 0)
	# side walls
	start = out.size() / 3
	var layer := 0
	var sl := steps + bevel_segments * 2
	for c in [contour] + holes:
		var i: int = c.size()
		while true:
			i -= 1
			if i < 0:
				break
			var j := i
			var k := i - 1
			if k < 0:
				k = c.size() - 1
			for s in sl:
				var s1 := vlen * s
				var s2 := vlen * (s + 1)
				_f4(ph, out, uvs, layer + j + s1, layer + k + s1, layer + k + s2, layer + j + s2)
		layer += c.size()
	g.add_group(start, out.size() / 3 - start, 1)
	g.set_attribute("position", T.Attr.new(out, 3))
	g.set_attribute("uv", T.Attr.new(uvs, 2))
	g.compute_vertex_normals()
	return g


static func _bevel_vec(pt: Array, prev: Array, next: Array) -> Array:
	var vtx: float
	var vty: float
	var shrink: float
	var vpx: float = pt[0] - prev[0]
	var vpy: float = pt[1] - prev[1]
	var vnx: float = next[0] - pt[0]
	var vny: float = next[1] - pt[1]
	var vp_lensq := vpx * vpx + vpy * vpy
	var collinear0 := vpx * vny - vpy * vnx
	if absf(collinear0) > T.EPS:
		var vp_len := sqrt(vp_lensq)
		var vn_len := sqrt(vnx * vnx + vny * vny)
		var pps_x: float = prev[0] - vpy / vp_len
		var pps_y: float = prev[1] + vpx / vp_len
		var pns_x: float = next[0] - vny / vn_len
		var pns_y: float = next[1] + vnx / vn_len
		var sf := ((pns_x - pps_x) * vny - (pns_y - pps_y) * vnx) / (vpx * vny - vpy * vnx)
		vtx = pps_x + vpx * sf - pt[0]
		vty = pps_y + vpy * sf - pt[1]
		var lsq := vtx * vtx + vty * vty
		if lsq <= 2.0:
			return [vtx, vty]
		shrink = sqrt(lsq / 2.0)
	else:
		var dir_eq := false
		if vpx > T.EPS:
			if vnx > T.EPS:
				dir_eq = true
		elif vpx < -T.EPS:
			if vnx < -T.EPS:
				dir_eq = true
		elif signf(vpy) == signf(vny):
			dir_eq = true
		if dir_eq:
			vtx = -vpy
			vty = vpx
			shrink = sqrt(vp_lensq)
		else:
			vtx = vpx
			vty = vpy
			shrink = sqrt(vp_lensq / 2.0)
	return [vtx / shrink, vty / shrink]


static func _f3(ph: PackedFloat64Array, out: PackedFloat32Array, uvs: PackedFloat32Array, a: int, b: int, c: int) -> void:
	for ix in [a, b, c]:
		out.append(ph[ix * 3]); out.append(ph[ix * 3 + 1]); out.append(ph[ix * 3 + 2])
	for ix in [a, b, c]:
		uvs.append(ph[ix * 3]); uvs.append(ph[ix * 3 + 1])


static func _f4(ph: PackedFloat64Array, out: PackedFloat32Array, uvs: PackedFloat32Array, a: int, b: int, c: int, d: int) -> void:
	for ix in [a, b, d, b, c, d]:
		out.append(ph[ix * 3]); out.append(ph[ix * 3 + 1]); out.append(ph[ix * 3 + 2])
	var ax := ph[a * 3]; var ay := ph[a * 3 + 1]
	var bx := ph[b * 3]; var by := ph[b * 3 + 1]
	var q := [a, b, c, d]
	var u := []
	if absf(ay - by) < absf(ax - bx):
		for ix in q:
			u.append([ph[ix * 3], 1.0 - ph[ix * 3 + 2]])
	else:
		for ix in q:
			u.append([ph[ix * 3 + 1], 1.0 - ph[ix * 3 + 2]])
	for k in [0, 1, 3, 1, 2, 3]:
		uvs.append(u[k][0]); uvs.append(u[k][1])


static func shape_geometry(shp: Dictionary, _curve_segments: int = 12) -> T.Geometry:
	var idx := PackedInt32Array()
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var sv := _path_points(shp.pts)
	var sh := []
	for h in shp.holes:
		sh.append(_path_points(h))
	if not is_clockwise(sv):
		sv.reverse()
	for i in sh.size():
		if is_clockwise(sh[i]):
			sh[i].reverse()
	var faces := triangulate_shape(sv, sh)
	for h in sh:
		sv = sv + h
	for v in sv:
		pos.append(v[0]); pos.append(v[1]); pos.append(0.0)
		nor.append(0.0); nor.append(0.0); nor.append(1.0)
		uv.append(v[0]); uv.append(v[1])
	for f in faces:
		idx.append(f[0]); idx.append(f[1]); idx.append(f[2])
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- curves

## SplineCurve(points).getPoints(divisions); points are [x, y].
static func spline_points(points: Array, divisions: int = 5) -> Array:
	var out := []
	for d in divisions + 1:
		out.append(_spline_point(points, float(d) / divisions))
	return out


static func _spline_point(points: Array, t: float) -> Array:
	var p := (points.size() - 1) * t
	var ip := int(floor(p))
	var w := p - ip
	var n := points.size()
	var p0: Array = points[ip if ip == 0 else ip - 1]
	var p1: Array = points[ip]
	var p2: Array = points[n - 1 if ip > n - 2 else ip + 1]
	var p3: Array = points[n - 1 if ip > n - 3 else ip + 2]
	return [_catmull_rom(w, p0[0], p1[0], p2[0], p3[0]), _catmull_rom(w, p0[1], p1[1], p2[1], p3[1])]


static func _catmull_rom(t: float, p0: float, p1: float, p2: float, p3: float) -> float:
	var v0 := (p2 - p0) * 0.5
	var v1 := (p3 - p1) * 0.5
	var t2 := t * t
	var t3 := t * t2
	return (2.0 * p1 - 2.0 * p2 + v0 + v1) * t3 + (-3.0 * p1 + 3.0 * p2 - 2.0 * v0 - v1) * t2 + v0 * t + p1


## CatmullRomCurve3(points, closed, 'centripetal').getPoint(t).
static func catmull3_point(pts: Array, closed: bool, t: float) -> Vector3:
	var l := pts.size()
	var p := (l - (0 if closed else 1)) * t
	var ip := int(floor(p))
	var w := p - ip
	if closed:
		ip += 0 if ip > 0 else (int(floor(absf(ip) / l)) + 1) * l
	elif w == 0.0 and ip == l - 1:
		ip = l - 2
		w = 1.0
	var p0: Vector3
	var p3: Vector3
	if closed or ip > 0:
		p0 = pts[(ip - 1) % l]
	else:
		p0 = pts[0] - pts[1] + pts[0]
	var p1: Vector3 = pts[ip % l]
	var p2: Vector3 = pts[(ip + 1) % l]
	if closed or ip + 2 < l:
		p3 = pts[(ip + 2) % l]
	else:
		p3 = pts[l - 1] - pts[l - 2] + pts[l - 1]
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4: dt1 = 1.0
	if dt0 < 1e-4: dt0 = dt1
	if dt2 < 1e-4: dt2 = dt1
	return Vector3(_nonuniform(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2, w),
		_nonuniform(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2, w),
		_nonuniform(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2, w))


static func _nonuniform(x0: float, x1: float, x2: float, x3: float, dt0: float, dt1: float, dt2: float, s: float) -> float:
	var t1 := (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
	var t2 := (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
	t1 *= dt1
	t2 *= dt1
	var c0 := x1
	var c1 := t1
	var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
	var c3 := 2.0 * x1 - 2.0 * x2 + t1 + t2
	return c0 + c1 * s + c2 * s * s + c3 * s * s * s


## TubeGeometry(new CatmullRomCurve3(points, closed), tubular, radius, radial, closed).
static func tube_catmull(pts: Array, curve_closed: bool, tubular: int, radius: float, radial: int, closed: bool) -> T.Geometry:
	var get_point := func(t: float) -> Vector3: return catmull3_point(pts, curve_closed, t)
	# arc lengths (Curve.getLengths, 200 divisions)
	var lengths := PackedFloat64Array([0.0])
	var last: Vector3 = get_point.call(0.0)
	var sum := 0.0
	for p in range(1, 201):
		var cur: Vector3 = get_point.call(float(p) / 200)
		sum += cur.distance_to(last)
		lengths.append(sum)
		last = cur
	var u_to_t := func(u: float) -> float:
		var il := lengths.size()
		var target := u * lengths[il - 1]
		var low := 0
		var high := il - 1
		var i := 0
		while low <= high:
			i = int(floor(low + (high - low) / 2.0))
			var cmp := lengths[i] - target
			if cmp < 0.0:
				low = i + 1
			elif cmp > 0.0:
				high = i - 1
			else:
				high = i
				break
		i = high
		if lengths[i] == target:
			return float(i) / (il - 1)
		var seg := lengths[i + 1] - lengths[i]
		return (i + (target - lengths[i]) / seg) / (il - 1)
	var tangent_at := func(u: float) -> Vector3:
		var t: float = u_to_t.call(u)
		var t1 := maxf(t - 0.0001, 0.0)
		var t2 := minf(t + 0.0001, 1.0)
		return ((get_point.call(t2) as Vector3) - (get_point.call(t1) as Vector3)).normalized()
	var tangents := []
	for i in tubular + 1:
		tangents.append(tangent_at.call(float(i) / tubular))
	var normals := [Vector3.ZERO]
	var binormals := [Vector3.ZERO]
	var mn := INF
	var t0: Vector3 = tangents[0]
	var nrm := Vector3.ZERO
	if absf(t0.x) <= mn:
		mn = absf(t0.x)
		nrm = Vector3(1, 0, 0)
	if absf(t0.y) <= mn:
		mn = absf(t0.y)
		nrm = Vector3(0, 1, 0)
	if absf(t0.z) <= mn:
		nrm = Vector3(0, 0, 1)
	var vec := t0.cross(nrm).normalized()
	normals[0] = t0.cross(vec)
	binormals[0] = t0.cross(normals[0])
	for i in range(1, tubular + 1):
		normals.append(normals[i - 1])
		binormals.append(binormals[i - 1])
		vec = (tangents[i - 1] as Vector3).cross(tangents[i])
		if vec.length() > T.EPS:
			vec = vec.normalized()
			var theta := acos(clampf((tangents[i - 1] as Vector3).dot(tangents[i]), -1.0, 1.0))
			normals[i] = Basis(vec, theta) * (normals[i] as Vector3)
		binormals[i] = (tangents[i] as Vector3).cross(normals[i])
	if closed:
		var theta := acos(clampf((normals[0] as Vector3).dot(normals[tubular]), -1.0, 1.0)) / tubular
		if (tangents[0] as Vector3).dot((normals[0] as Vector3).cross(normals[tubular])) > 0.0:
			theta = -theta
		for i in range(1, tubular + 1):
			normals[i] = Basis(tangents[i], theta * i) * (normals[i] as Vector3)
			binormals[i] = (tangents[i] as Vector3).cross(normals[i])
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	var segs := range(tubular)
	segs.append(tubular if not closed else 0)
	for i in segs:
		var P: Vector3 = get_point.call(u_to_t.call(float(i) / tubular))
		var N: Vector3 = normals[i]
		var B: Vector3 = binormals[i]
		for j in radial + 1:
			var v := float(j) / radial * TAU
			var s := sin(v)
			var c := -cos(v)
			var n := (c * N + s * B).normalized()
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			pos.append(P.x + radius * n.x); pos.append(P.y + radius * n.y); pos.append(P.z + radius * n.z)
	for i in tubular + 1:
		for j in radial + 1:
			uv.append(float(i) / tubular); uv.append(float(j) / radial)
	for j in range(1, tubular + 1):
		for i in range(1, radial + 1):
			var a := (radial + 1) * (j - 1) + (i - 1)
			var b := (radial + 1) * j + (i - 1)
			var c := (radial + 1) * j + i
			var d := (radial + 1) * (j - 1) + i
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(c); idx.append(d)
	return _make(idx, pos, nor, uv)


# ---------------------------------------------------------------- BufferGeometryUtils

static func merge_geometries(geos: Array, use_groups: bool = false) -> T.Geometry:
	if geos.is_empty():
		return null
	var is_indexed: bool = geos[0].indexed
	var names: Array = geos[0].attributes.keys()
	for g in geos:
		if g.indexed != is_indexed or g.attributes.size() != names.size():
			return null
		for nm in g.attributes:
			if not names.has(nm):
				return null
	var m := T.Geometry.new()
	var offset := 0
	if use_groups:
		for i in geos.size():
			var c: int = geos[i].index.size() if is_indexed else geos[i].vertex_count()
			m.add_group(offset, c, i)
			offset += c
	if is_indexed:
		var mi := PackedInt32Array()
		var io := 0
		for g in geos:
			for ix in g.index:
				mi.append(ix + io)
			io += g.vertex_count()
		m.set_index(mi)
	for nm in names:
		var arr := PackedFloat32Array()
		var s: int = geos[0].attributes[nm].item_size
		for g in geos:
			if g.attributes[nm].item_size != s:
				return null
			arr.append_array(g.attributes[nm].array)
		m.set_attribute(nm, T.Attr.new(arr, s))
	return m


static func merge_vertices(g: T.Geometry, tolerance: float = 1e-4) -> T.Geometry:
	tolerance = maxf(tolerance, T.EPS)
	var hash_to_index := {}
	var positions: T.Attr = g.attributes["position"]
	var vertex_count: int = g.index.size() if g.indexed else positions.count()
	var next_index := 0
	var names: Array = g.attributes.keys()
	var tmp := {}
	for nm in names:
		tmp[nm] = PackedFloat32Array()
	var half := tolerance * 0.5
	var mult := pow(10.0, log(1.0 / tolerance) / log(10.0))
	var add := half * mult
	var new_idx := PackedInt32Array()
	for i in vertex_count:
		var ix: int = g.index[i] if g.indexed else i
		var h := ""
		for nm in names:
			var a: T.Attr = g.attributes[nm]
			for k in a.item_size:
				h += str(int(a.get_c(ix, k) * mult + add)) + ","
		if hash_to_index.has(h):
			new_idx.append(hash_to_index[h])
		else:
			for nm in names:
				var a: T.Attr = g.attributes[nm]
				for k in a.item_size:
					tmp[nm].append(a.get_c(ix, k))
			hash_to_index[h] = next_index
			new_idx.append(next_index)
			next_index += 1
	var r := g.clone()
	for nm in names:
		r.set_attribute(nm, T.Attr.new(tmp[nm], g.attributes[nm].item_size))
	r.set_index(new_idx)
	return r


# ---------------------------------------------------------------- src/core/geo.js

## Shared unit geometries, per build (geo.js keeps them module-wide; a build is one process there).
class Cache extends RefCounted:
	var _m := {}

	func get_or(key: String, make: Callable) -> T.Geometry:
		if not _m.has(key):
			_m[key] = make.call()
		return _m[key]


static func g_box(cache: Cache) -> T.Geometry:
	return cache.get_or("box", func(): return box(1, 1, 1))


static func g_cyl(cache: Cache, seg: int = 12) -> T.Geometry:
	return cache.get_or("cyl%d" % seg, func(): return cylinder(0.5, 0.5, 1, seg))


static func g_plane(cache: Cache) -> T.Geometry:
	return cache.get_or("plane", func(): return plane(1, 1))


static func g_sphere(cache: Cache, seg: int = 12) -> T.Geometry:
	return cache.get_or("sph%d" % seg, func(): return sphere(0.5, seg, maxi(6, int(seg * 0.66))))


static func g_rbox(cache: Cache, r: float = 0.1, seg: int = 2) -> T.Geometry:
	return cache.get_or("rbox%s|%d" % [str(r), seg], func(): return rounded_box(1, 1, 1, seg, r))


## The placement kit: sizes in metres, pos = [x, y, z] is the centre unless noted, rot = [rx, ry, rz].
class Kit extends RefCounted:
	var parent
	var cache: Cache

	func _init(p, c: Cache) -> void:
		parent = p
		cache = c

	func _place(mesh, pos, rot, scl):
		if pos != null:
			mesh.position = Vector3(pos[0], pos[1], pos[2])
		if rot != null:
			mesh.rotation = Vector3(_n(rot, 0), _n(rot, 1), _n(rot, 2))
		if scl != null:
			mesh.scale = Vector3(scl[0], scl[1], scl[2])
		mesh.cast_shadow = true
		mesh.receive_shadow = true
		parent.add(mesh)
		return mesh

	static func _n(a, i: int) -> float:
		return float(a[i]) if i < a.size() and a[i] != null else 0.0

	func box(w: float, h: float, d: float, mat, pos, rot = null):
		return _place(T.MeshObj.new(load("res://addons/sakuragaoka_station/core/geo.gd").g_box(cache), mat), pos, rot, [w, h, d])

	func boxb(w: float, h: float, d: float, mat, pos, rot = null):
		return _place(T.MeshObj.new(load("res://addons/sakuragaoka_station/core/geo.gd").g_box(cache), mat), [pos[0], pos[1] + h / 2.0, pos[2]], rot, [w, h, d])

	func rbox(w: float, h: float, d: float, r: float, mat, pos, rot = null):
		var G = load("res://addons/sakuragaoka_station/core/geo.gd")
		var g = G.rounded_box(w, h, d, 2, minf(minf(r, w / 2.0), minf(h / 2.0, d / 2.0)))
		return _place(T.MeshObj.new(g, mat), pos, rot, null)

	func cyl(r_top: float, r_bot: float, h: float, mat, pos, rot = null, seg: int = 12):
		var G = load("res://addons/sakuragaoka_station/core/geo.gd")
		if r_top == r_bot:
			return _place(T.MeshObj.new(G.g_cyl(cache, seg), mat), pos, rot, [r_top * 2.0, h, r_top * 2.0])
		return _place(T.MeshObj.new(G.cylinder(r_top, r_bot, h, seg), mat), pos, rot, null)

	func sphere(r: float, mat, pos, seg: int = 12):
		var G = load("res://addons/sakuragaoka_station/core/geo.gd")
		return _place(T.MeshObj.new(G.g_sphere(cache, seg), mat), pos, null, [r * 2.0, r * 2.0, r * 2.0])

	func plane(w: float, h: float, mat, pos, rot = null):
		var G = load("res://addons/sakuragaoka_station/core/geo.gd")
		var m = _place(T.MeshObj.new(G.g_plane(cache), mat), pos, rot, [w, h, 1.0])
		m.cast_shadow = false
		return m

	func mesh(geo, mat, pos = null, rot = null, scl = null):
		return _place(T.MeshObj.new(geo, mat), pos, rot, scl)

	func group(pos = null, rot_y: float = 0.0):
		var g := T.Group.new()
		if pos != null:
			g.position = Vector3(pos[0], pos[1], pos[2])
		g.rotation.y = rot_y
		parent.add(g)
		return g


## geo.js extrude(points, depth, opts): outline [x, y] extruded along +Z, centred unless center=false.
static func extrude(points: Array, depth: float, opts: Dictionary = {}) -> T.Geometry:
	var holes := []
	for h in opts.get("holes", []):
		holes.append(h)
	var bevel: float = opts.get("bevel", 0.0)
	var g := extrude_shape(shape(points, holes), {"depth": depth, "bevelEnabled": bevel != 0.0, "bevelSize": bevel,
		"bevelThickness": bevel, "bevelSegments": 1})
	if opts.get("center", true) != false:
		g.translate(0, 0, -depth / 2.0)
	return g


## Points along a sagging wire between a and b; sag is the drop at midspan.
static func catenary(a, b, sag: float = 0.4, segments: int = 14) -> Array:
	var A: Vector3 = a if a is Vector3 else Vector3(a[0], a[1], a[2])
	var B: Vector3 = b if b is Vector3 else Vector3(b[0], b[1], b[2])
	var pts := []
	for i in segments + 1:
		var t := float(i) / segments
		var p := A.lerp(B, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


static func merge_meshes(meshes: Array) -> T.Geometry:
	var geos := []
	for m in meshes:
		m.update_matrix()
		var g: T.Geometry = m.geometry.clone()
		g.apply_matrix4(m.matrix)
		geos.append(g)
	return merge_geometries(geos, false)


## The wire list: modules add polylines; the renderer draws them as ribbons (not ported here).
class Wires extends RefCounted:
	var lists: Array = []

	func add(points: Array, opts: Dictionary = {}) -> void:
		if points.size() < 2:
			return
		var pts := []
		for p in points:
			pts.append(p if p is Vector3 else Vector3(p[0], p[1], p[2]))
		lists.append({"pts": pts, "width": opts.get("width", 0.02), "color": T.color(opts.get("color", "#3a3640"))})

	func count() -> int:
		return lists.size()
