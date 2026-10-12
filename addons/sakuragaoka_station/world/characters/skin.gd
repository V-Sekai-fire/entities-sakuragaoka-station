# characters/skin.js: the skinned-character toolkit. Parametric surfaces, a skinning builder that
# merges every part of a character into ONE skinned mesh (one draw call, GPU skinning => outlines
# follow the pose), and a two-bone IK solver. Everything here is deterministic.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Self = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")

const DEG := PI / 180.0


static func clamp_(v: float, a: float, b: float) -> float:
	return minf(b, maxf(a, v))


static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func smooth(a: float, b: float, x: float) -> float:
	var t := clamp_((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func hypot(a: float, b: float, c: float = 0.0) -> float:
	return sqrt(a * a + b * b + c * c)


static func sgn(x: float) -> float:
	return T.sign(x)


## A three.js Bone: an Object3D whose rotation is a quaternion (bones are posed with quaternions).
class Bone extends T.Obj3D:
	var quat := Quaternion.IDENTITY

	func update_matrix() -> void:
		matrix = Transform3D(Basis(quat) * Basis.from_scale(scale), position)


## THREE.SkinnedMesh: geometry in bind pose plus the skeleton that poses it.
class SkinnedMesh extends T.MeshObj:
	var bones: Array = []
	var bone_inverses: Array = []
	var bind_matrix := Transform3D()
	var bind_matrix_inverse := Transform3D()
	var bounding_sphere = null

	func _init(g: T.Geometry = null, m = null) -> void:
		super(g, m)


# ------------------------------------------------------------------ world-matrix helpers

## Object3D.updateWorldMatrix(true, false): parents first, then this object, no children.
static func update_world(o) -> void:
	var p = o.parent()
	if p:
		update_world(p)
	if o.matrix_auto_update:
		o.update_matrix()
	o.matrix_world = p.matrix_world * o.matrix if p else o.matrix


static func world_quat(o) -> Quaternion:
	update_world(o)
	return o.matrix_world.basis.get_rotation_quaternion()


static func get_quat(o) -> Quaternion:
	return o.quat if o is Bone else o.quaternion()


static func set_quat(o, q: Quaternion) -> void:
	if o is Bone:
		o.quat = q
	else:
		o.set_quaternion(q)


# ------------------------------------------------------------------ geometry primitives

## Parametric grid surface. fn(u, v) -> [x, y, z]; u across cols, v across rows (both 0..1).
static func surface(cols: int, rows: int, fn: Callable, opts: Dictionary = {}) -> T.Geometry:
	var nv := (cols + 1) * (rows + 1)
	var pos := PackedFloat32Array()
	pos.resize(nv * 3)
	var uv := PackedFloat32Array()
	uv.resize(nv * 2)
	var k := 0
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / cols
			var v := float(j) / rows
			var p = fn.call(u, v)
			pos[k * 3] = p[0]
			pos[k * 3 + 1] = p[1]
			pos[k * 3 + 2] = p[2]
			uv[k * 2] = u
			uv[k * 2 + 1] = v
			k += 1
	var idx := PackedInt32Array()
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	g.compute_vertex_normals()
	if opts.get("weld", true) != false:
		weld_normals(g)
	return g


## Average normals of vertices sharing a position (fixes seams / poles => no false outline lines).
static func weld_normals(g: T.Geometry, eps: float = 1e-5) -> T.Geometry:
	var p: T.Attr = g.get_attribute("position")
	var n: T.Attr = g.get_attribute("normal")
	var map := {}
	var order: Array = []
	for i in p.count():
		var key := "%d,%d,%d" % [int(T.js_round(p.get_x(i) / eps)), int(T.js_round(p.get_y(i) / eps)), int(T.js_round(p.get_z(i) / eps))]
		var e = map.get(key)
		if e == null:
			e = [0.0, 0.0, 0.0, []]
			map[key] = e
			order.append(e)
		e[0] += n.get_x(i)
		e[1] += n.get_y(i)
		e[2] += n.get_z(i)
		e[3].append(i)
	for e in order:
		if e[3].size() < 2:
			continue
		var l := hypot(e[0], e[1], e[2])
		if l == 0.0:
			l = 1.0
		for i in e[3]:
			n.set_xyz(i, e[0] / l, e[1] / l, e[2] / l)
	return g


## Ellipsoid centred at c. Optional deform(x, y, z, u, v) -> [x, y, z].
static func ellipsoid(rx: float, ry: float, rz: float, c: Array = [0.0, 0.0, 0.0], cols: int = 12, rows: int = 8, deform = null) -> T.Geometry:
	return surface(cols, rows, func(u: float, v: float) -> Array:
		var ph := (u - 0.5) * TAU
		var th := (0.5 - v) * PI
		var x := rx * sin(ph) * cos(th)
		var y := ry * sin(th)
		var z := rz * cos(ph) * cos(th)
		if deform != null:
			var d: Array = deform.call(x, y, z, u, v)
			x = d[0]
			y = d[1]
			z = d[2]
		return [c[0] + x, c[1] + y, c[2] + z])


## Stack of horizontal elliptical rings. list: [{y, a, b, x?, z?}], closed at both ends when the
## first/last ring has a = b = 0. Seam is at the back (-Z) so it is never seen.
static func rings(list: Array, cols: int = 12, radial = null) -> T.Geometry:
	var rows := list.size() - 1
	return surface(cols, rows, func(u: float, v: float) -> Array:
		var ri := int(T.js_round(v * rows))
		var r: Dictionary = list[ri]
		var ph := (u - 0.5) * TAU
		var a: float = r.a
		var b: float = r.b
		if radial != null:
			var f: float = radial.call(ph, r, ri)
			a *= f
			b *= f
		return [r.get("x", 0.0) + sin(ph) * a, r.y, r.get("z", 0.0) + cos(ph) * b])


static func _nn(o: Dictionary, k: String, d):
	var v = o.get(k)
	return d if v == null else v


## Rounded limb hanging down from the local origin along -Y. r0 top radius, r1 bottom radius,
## mid: optional [[t, r]] bulges, depth: z/x ratio of the section.
static func limb(len: float, r0: float, r1: float, opt: Dictionary = {}) -> T.Geometry:
	var d: float = _nn(opt, "depth", 1.0)
	var cols: int = _nn(opt, "cols", 10)
	var cap_t: float = _nn(opt, "capTop", 0.75)
	var cap_b: float = _nn(opt, "capBottom", 0.75)
	var L: Array = []
	if cap_t > 0.0:
		L.append({"y": r0 * cap_t, "a": 0.0, "b": 0.0})
		L.append({"y": r0 * cap_t * 0.72, "a": r0 * 0.68, "b": r0 * 0.68 * d})
	L.append({"y": 0.0, "a": r0, "b": r0 * d})
	if opt.get("mid") != null:
		for m in opt.mid:
			var t: float = m[0]
			var r: float = m[1]
			L.append({"y": -len * t, "a": r, "b": r * d, "z": opt.midZ.call(t) if opt.get("midZ") != null else 0.0})
	L.append({"y": -len, "a": r1, "b": r1 * d})
	if cap_b > 0.0:
		L.append({"y": -len - r1 * cap_b * 0.72, "a": r1 * 0.68, "b": r1 * 0.68 * d})
		L.append({"y": -len - r1 * cap_b, "a": 0.0, "b": 0.0})
	return rings(L, cols)


## Sweep a lens-shaped cross-section along points (hair locks, straps, tails).
## width(s), thick(s): s = 0..1 along the path; out(p): direction the flat side faces.
static func sweep(points: Array, width: Callable, thick: Callable, out: Callable, sides: int = 6) -> T.Geometry:
	var n := points.size()
	var TT: Array = []
	for i in n:
		var a: Vector3 = points[maxi(0, i - 1)]
		var b: Vector3 = points[mini(n - 1, i + 1)]
		TT.append((b - a).normalized())
	var pos := PackedFloat32Array()
	var uvs := PackedFloat32Array()
	var s_arr: Array = []
	var acc := 0.0
	var lens: Array = [0.0]
	for i in range(1, n):
		acc += (points[i] as Vector3).distance_to(points[i - 1])
		lens.append(acc)
	for i in n:
		var s: float = lens[i] / acc if acc > 0.0 else float(i) / (n - 1)
		var o: Vector3 = out.call(points[i])
		var B: Vector3 = (TT[i] as Vector3).cross(o).normalized()
		var N: Vector3 = B.cross(TT[i]).normalized()
		var w: float = width.call(s) * 0.5
		var t: float = thick.call(s) * 0.5
		for k in sides + 1:
			var a := (float(k) / sides) * TAU
			var p: Vector3 = points[i] + B * (cos(a) * w) + N * (sin(a) * t)
			pos.append_array([p.x, p.y, p.z])
			uvs.append_array([float(k) / sides, s])
			s_arr.append(s)
	var idx := PackedInt32Array()
	for i in n - 1:
		for k in sides:
			var a := i * (sides + 1) + k
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("uv", T.Attr.new(uvs, 2))
	g.set_index(idx)
	g.compute_vertex_normals()
	weld_normals(g)
	g.user_data["s"] = s_arr
	return g


## Catmull-Rom (centripetal) resample of control points ([x, y, z] or Vector3) into n points.
static func curve(ctrl: Array, n: int = 8) -> Array:
	var pts: Array = []
	for p in ctrl:
		pts.append(p if p is Vector3 else Vector3(p[0], p[1], p[2]))
	var out: Array = []
	var div := n - 1
	for d in div + 1:
		out.append(Geo.catmull3_point(pts, false, float(d) / div))
	return out


## Box with rounded edges (for shoes, bags...): a superellipsoid (smooth, cheap, no seams).
static func rbox(w: float, h: float, d: float, _r: float, c: Array = [0.0, 0.0, 0.0], _seg: int = 2) -> T.Geometry:
	var e := 6.0
	var f := func(x: float) -> float:
		return (-1.0 if x < 0.0 else 1.0) * pow(absf(x), 2.0 / e)
	# tessellation follows size: tiny badges / buttons stay cheap, bags and soles stay smooth
	var m := maxf(w, maxf(h, d))
	var cols := 6 if m < 0.07 else (8 if m < 0.2 else 12)
	var rows := 4 if m < 0.07 else (6 if m < 0.2 else 8)
	return surface(cols, rows, func(u: float, v: float) -> Array:
		var ph := (u - 0.5) * TAU
		var th := (0.5 - v) * PI
		var x: float = f.call(cos(th)) * f.call(sin(ph))
		var y: float = f.call(sin(th))
		var z: float = f.call(cos(th)) * f.call(cos(ph))
		return [c[0] + x * w / 2.0, c[1] + y * h / 2.0, c[2] + z * d / 2.0])


# ------------------------------------------------------------------ skinning builder

static var _c := Color(1, 1, 1)
static var _ids := 0


class SkinBuilder extends RefCounted:
	var name := "skin"
	var bones: Array = []
	var bind := {}
	var P := PackedFloat32Array()
	var N := PackedFloat32Array()
	var UV := PackedFloat32Array()
	var C := PackedFloat32Array()
	var SI := PackedFloat32Array()
	var SW := PackedFloat32Array()
	var I := PackedInt32Array()
	var nv := 0
	var white_uv := [0.75, 0.75]

	func _init(n: String = "skin") -> void:
		name = n

	## Create a bone at local offset (x, y, z) from parent (bind pose has identity rotations).
	func bone(bname: String, parent, x: float = 0.0, y: float = 0.0, z: float = 0.0):
		var b = Self.Bone.new()
		b.name = bname
		b.position = Vector3(x, y, z)
		if parent:
			parent.add(b)
		b.user_data["bi"] = bones.size()
		# three.js Object3D.id (a global counter; seeds the hair sway phase)
		Self._ids += 1
		b.user_data["id"] = Self._ids
		bones.append(b)
		var pb = bind.get(parent) if parent else null
		bind[b] = [pb[0] + x, pb[1] + y, pb[2] + z] if pb else [x, y, z]
		b.user_data["rest"] = b.position
		return b

	func bind_pos(b) -> Array:
		return bind.get(b)

	## Add a geometry defined in `bone`-local coordinates.
	## o: {bone, color | colorFn(x, y, z, s, i), weights(lx, ly, lz, s, i) -> [[bone, w], ...],
	##     rect: [u0, v0, u1, v1] (remap geo uv into atlas), uvFn(lx, ly, lz, u, v, i) -> [u, v],
	##     matrix (extra local transform)}
	func add(geo: T.Geometry, o: Dictionary) -> SkinBuilder:
		var S = Self
		if o.get("matrix") != null:
			geo = geo.clone()
			geo.apply_matrix4(o.matrix)
		var pos: T.Attr = geo.position()
		var nrm: T.Attr = geo.get_attribute("normal")
		var uv: T.Attr = geo.get_attribute("uv")
		var sA = geo.user_data.get("s")
		var bp: Array = bind.get(o.bone, [0.0, 0.0, 0.0])
		var base := nv
		if o.get("color") != null:
			S._c = T.color(o.color)
		var uv_fn = o.get("uvFn")
		var rect = o.get("rect")
		var color_fn = o.get("colorFn")
		var weights = o.get("weights")
		for i in pos.count():
			var lx := pos.get_x(i)
			var ly := pos.get_y(i)
			var lz := pos.get_z(i)
			P.append_array([lx + bp[0], ly + bp[1], lz + bp[2]])
			N.append_array([nrm.get_x(i), nrm.get_y(i), nrm.get_z(i)])
			var s: float = sA[i] if sA != null else (uv.get_y(i) if uv else 0.0)
			if uv_fn != null:
				var t: Array = uv_fn.call(lx, ly, lz, uv.get_x(i) if uv else 0.0, uv.get_y(i) if uv else 0.0, i)
				UV.append_array([t[0], t[1]])
			elif rect != null and uv:
				UV.append_array([rect[0] + (rect[2] - rect[0]) * uv.get_x(i), rect[1] + (rect[3] - rect[1]) * uv.get_y(i)])
			else:
				UV.append_array([white_uv[0], white_uv[1]])
			if color_fn != null:
				S._c = T.color(color_fn.call(lx, ly, lz, s, i))
			var cc: Color = S._c
			C.append_array([cc.r, cc.g, cc.b])
			var w: Array = weights.call(lx, ly, lz, s, i) if weights != null else [[o.bone, 1.0]]
			if w.size() > 4:
				w = T.stable_sort(w.duplicate(), func(a, b2): return b2[1] - a[1]).slice(0, 4)
			var tot := 0.0
			for e in w:
				tot += e[1]
			var si := [0, 0, 0, 0]
			var sw := [0.0, 0.0, 0.0, 0.0]
			for k in w.size():
				si[k] = w[k][0].user_data.bi
				sw[k] = w[k][1] / tot if tot > 0.0 else 0.0
			if tot <= 0.0:
				si[0] = o.bone.user_data.bi
				sw[0] = 1.0
			SI.append_array(si)
			SW.append_array(sw)
		if geo.indexed:
			for i in geo.index.size():
				I.append(base + geo.index[i])
		else:
			for i in pos.count():
				I.append(base + i)
		nv += pos.count()
		return self

	func triangles() -> float:
		return I.size() / 3.0

	## Build the skinned mesh. root: Object3D that holds the root bone (at identity when called).
	func build(root, material):
		var S = Self
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(P, 3))
		g.set_attribute("normal", T.Attr.new(N, 3))
		g.set_attribute("uv", T.Attr.new(UV, 2))
		g.set_attribute("color", T.Attr.new(C, 3))
		g.set_attribute("skinIndex", T.Attr.new(SI, 4))
		g.set_attribute("skinWeight", T.Attr.new(SW, 4))
		g.set_index(I)
		g.compute_bounding_box()
		var mesh = S.SkinnedMesh.new(g, material)
		mesh.name = name
		mesh.cast_shadow = true
		mesh.receive_shadow = true
		root.add(mesh)
		root.update_matrix_world(true)
		# new Skeleton(bones) computes the inverses from the bones' current world matrices
		mesh.bones = bones
		mesh.bone_inverses = bones.map(func(b): return b.matrix_world.affine_inverse())
		mesh.bind_matrix = mesh.matrix_world
		mesh.bind_matrix_inverse = mesh.matrix_world.affine_inverse()
		# generous fixed bounds in mesh space (pose changes never cull wrongly)
		var bb: AABB = g.bounding_box
		mesh.bounding_sphere = {"center": bb.get_center(), "radius": bb.size.length() * 0.5 + 0.6}
		return mesh


# ------------------------------------------------------------------ IK & bone helpers

## Two-bone IK. upper, lower: bones (lower child of upper). end_local: offset of the end effector in
## lower's local space (bind). target / pole: world points. bend_dir: rest direction (upper-local)
## the lower bone folds toward (arms: +Z, legs: -Z). Leaves lower's rotation a pure hinge.
static func ik2(upper, lower, end_local: Vector3, target: Vector3, pole: Vector3, bend_dir: Vector3) -> void:
	var parent = upper.parent()
	update_world(parent)
	var m: Transform3D = parent.matrix_world.affine_inverse()
	var TT: Vector3 = m * target
	var PP: Vector3 = m * pole
	var S: Vector3 = upper.position
	var rest = lower.user_data.get("rest")
	var l1: float = (rest as Vector3).length() if rest != null else (lower.position as Vector3).length()
	var l2 := end_local.length()
	var D := TT - S
	var d := D.length()
	if d < 1e-6:
		return
	D /= d
	d = clamp_(d, absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var pv := PP - S
	pv += D * -pv.dot(D)
	if pv.length_squared() < 1e-10:
		pv = Vector3(0, 0, -1) + D * D.z
	pv = pv.normalized()
	var cosA := clamp_((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var A := acos(cosA)
	var u := (D * cos(A) + pv * sin(A)).normalized()                # upper dir
	var E := S + u * l1
	var f := (S + D * d - E).normalized()                          # fore dir
	var perp := f + u * -f.dot(u)
	if perp.length_squared() < 1e-8:
		perp = pv * -1.0
	perp = perp.normalized()
	# rest frame of the upper bone: axis a (toward lower), bend b
	var a: Vector3 = (rest if rest != null else lower.position).normalized()
	var b := (bend_dir + a * -bend_dir.dot(a)).normalized()
	var x1 := a.cross(b)
	var x2 := u.cross(perp)
	var mb := Basis(a, b, x1)
	var m2 := Basis(u, perp, x2) * mb.transposed()
	upper.quat = m2.get_rotation_quaternion()
	# lower: rotate its rest axis onto the fore direction expressed in upper-local space
	f = upper.quat.inverse() * f
	lower.quat = T.quat_from_unit_vectors(end_local.normalized(), f)


## Set a bone's world orientation to q (world quaternion).
static func set_world_quat(obj, q: Quaternion) -> void:
	var p = obj.parent()
	update_world(p)
	var q2 := world_quat(p)
	obj.quat = q2.inverse() * q


## Rotation that tilts a bone hanging along -Y toward horizontal direction (dx, dz) by angle a.
static func tilt_quat(dx: float, dz: float, a: float) -> Quaternion:
	var l := hypot(dx, dz)
	if l < 1e-6 or absf(a) < 1e-6:
		return Quaternion.IDENTITY
	return Quaternion(Vector3(-dz / l, 0.0, dx / l), a)


## Smooth deterministic noise from sines (per-character phase).
static func wave(t: float, seed: float, f: float = 1.0) -> float:
	return sin(t * 0.73 * f + seed * 1.7) * 0.5 + sin(t * 1.37 * f + seed * 3.1) * 0.3 + sin(t * 2.21 * f + seed * 5.3) * 0.2
