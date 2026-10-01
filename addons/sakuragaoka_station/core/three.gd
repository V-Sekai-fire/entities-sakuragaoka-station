# The subset of three.js r170's scene graph, geometry and colour the world modules use, so each
# module ports line by line. Conventions are three.js's: Y up, Euler order XYZ, T * R * S, CCW
# front faces, float32 attribute arrays, colours stored linear and written as sRGB hex.
extends RefCounted

const EPS := 2.220446049250313e-16


## A property bag: fields three.js code sets ad hoc (castShadow, renderOrder, ...) land here.
class Bag extends RefCounted:
	var _props := {}

	func _get(p: StringName):
		return _props.get(p)

	func _set(p: StringName, v) -> bool:
		_props[p] = v
		return true

	func has(p: String) -> bool:
		return _props.has(p)


class Attr extends RefCounted:
	static var DOUBLE := OS.has_feature("double")
	var array: PackedFloat32Array
	var item_size: int
	var normalized := false

	func _init(a = PackedFloat32Array(), s: int = 3) -> void:
		array = a if a is PackedFloat32Array else PackedFloat32Array(a)
		item_size = s

	func count() -> int:
		return array.size() / item_size

	func get_x(i: int) -> float:
		return array[i * item_size]

	func get_y(i: int) -> float:
		return array[i * item_size + 1]

	func get_z(i: int) -> float:
		return array[i * item_size + 2]

	func get_w(i: int) -> float:
		return array[i * item_size + 3]

	func get_c(i: int, c: int) -> float:
		return array[i * item_size + c]

	func set_x(i: int, v: float) -> void:
		array[i * item_size] = v

	func set_y(i: int, v: float) -> void:
		array[i * item_size + 1] = v

	func set_z(i: int, v: float) -> void:
		array[i * item_size + 2] = v

	func set_c(i: int, c: int, v: float) -> void:
		array[i * item_size + c] = v

	func set_xy(i: int, x: float, y: float) -> void:
		var k := i * item_size
		array[k] = x
		array[k + 1] = y

	func set_xyz(i: int, x: float, y: float, z: float) -> void:
		var k := i * item_size
		array[k] = x
		array[k + 1] = y
		array[k + 2] = z

	func v3(i: int) -> Vector3:
		var k := i * item_size
		return Vector3(array[k], array[k + 1], array[k + 2])

	func set_v3(i: int, v: Vector3) -> void:
		var k := i * item_size
		array[k] = v.x
		array[k + 1] = v.y
		array[k + 2] = v.z

	## The bytes of a float32 array are a PackedVector3Array only while Vector3 is float32; a
	## precision=double engine has float64 vectors, so it copies element by element.
	func vec3_array() -> PackedVector3Array:
		if not DOUBLE:
			return array.to_byte_array().to_vector3_array()
		var out := PackedVector3Array()
		var n := array.size() / 3
		out.resize(n)
		for i in n:
			out[i] = Vector3(array[i * 3], array[i * 3 + 1], array[i * 3 + 2])
		return out

	func set_vec3_array(v: PackedVector3Array) -> void:
		if not DOUBLE:
			array = v.to_byte_array().to_float32_array()
			return
		var out := PackedFloat32Array()
		out.resize(v.size() * 3)
		for i in v.size():
			var p := v[i]
			out[i * 3] = p.x
			out[i * 3 + 1] = p.y
			out[i * 3 + 2] = p.z
		array = out

	func clone() -> Attr:
		var a := Attr.new(array.duplicate(), item_size)
		a.normalized = normalized
		return a


class Geometry extends Bag:
	var attributes := {}
	var index := PackedInt32Array()
	var indexed := false
	var groups: Array = []
	var bounding_box = null
	var user_data := {}
	var draw_start := 0
	var draw_count := -1

	func set_attribute(name: String, a: Attr) -> Geometry:
		attributes[name] = a
		return self

	func get_attribute(name: String) -> Attr:
		return attributes.get(name)

	func has_attribute(name: String) -> bool:
		return attributes.has(name)

	func delete_attribute(name: String) -> Geometry:
		attributes.erase(name)
		return self

	func set_index(ix) -> Geometry:
		if ix == null:
			index = PackedInt32Array()
			indexed = false
		else:
			index = ix if ix is PackedInt32Array else PackedInt32Array(ix)
			indexed = true
		return self

	func add_group(start: int, count: int, material_index: int = 0) -> void:
		groups.append({"start": start, "count": count, "material_index": material_index})

	func clear_groups() -> void:
		groups = []

	func position() -> Attr:
		return attributes.get("position")

	func vertex_count() -> int:
		var p: Attr = attributes.get("position")
		return p.count() if p else 0

	func triangle_count() -> float:
		if indexed:
			return index.size() / 3.0
		return vertex_count() / 3.0

	func apply_matrix4(t: Transform3D) -> Geometry:
		var p: Attr = attributes.get("position")
		if p:
			p.set_vec3_array(t * p.vec3_array())
		var n: Attr = attributes.get("normal")
		if n:
			var nb := Transform3D(t.basis.inverse().transposed(), Vector3.ZERO)
			var v: PackedVector3Array = nb * n.vec3_array()
			for i in v.size():
				v[i] = v[i].normalized() if v[i].length_squared() > 0.0 else v[i]
			n.set_vec3_array(v)
		var tg: Attr = attributes.get("tangent")
		if tg and tg.item_size == 4:
			for i in tg.count():
				var d := (t.basis * Vector3(tg.get_x(i), tg.get_y(i), tg.get_z(i)))
				d = d.normalized() if d.length_squared() > 0.0 else d
				tg.set_xyz(i, d.x, d.y, d.z)
		if bounding_box != null:
			compute_bounding_box()
		return self

	func translate(x: float, y: float, z: float) -> Geometry:
		return apply_matrix4(Transform3D(Basis(), Vector3(x, y, z)))

	func rotate_x(a: float) -> Geometry:
		return apply_matrix4(Transform3D(Basis(Vector3(1, 0, 0), a), Vector3.ZERO))

	func rotate_y(a: float) -> Geometry:
		return apply_matrix4(Transform3D(Basis(Vector3(0, 1, 0), a), Vector3.ZERO))

	func rotate_z(a: float) -> Geometry:
		return apply_matrix4(Transform3D(Basis(Vector3(0, 0, 1), a), Vector3.ZERO))

	func scale(x: float, y: float, z: float) -> Geometry:
		return apply_matrix4(Transform3D(Basis.from_scale(Vector3(x, y, z)), Vector3.ZERO))

	func apply_quaternion(q: Quaternion) -> Geometry:
		return apply_matrix4(Transform3D(Basis(q), Vector3.ZERO))

	func compute_bounding_box() -> Geometry:
		var p: Attr = attributes.get("position")
		if p == null or p.count() == 0:
			bounding_box = null
			return self
		var a := p.array
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var i := 0
		while i < a.size():
			var x := a[i]
			var y := a[i + 1]
			var z := a[i + 2]
			if x < lo.x: lo.x = x
			if y < lo.y: lo.y = y
			if z < lo.z: lo.z = z
			if x > hi.x: hi.x = x
			if y > hi.y: hi.y = y
			if z > hi.z: hi.z = z
			i += 3
		bounding_box = AABB(lo, hi - lo)
		return self

	func compute_bounding_sphere() -> Geometry:
		return self

	## three.js's computeVertexNormals: area-weighted face normals summed per vertex.
	func compute_vertex_normals() -> Geometry:
		var p: Attr = attributes.get("position")
		if p == null:
			return self
		var nc := p.count()
		var acc := PackedVector3Array()
		acc.resize(nc)
		var pv := p.vec3_array()
		if indexed:
			var i := 0
			while i + 2 < index.size():
				var a := index[i]
				var b := index[i + 1]
				var c := index[i + 2]
				var fn := (pv[c] - pv[b]).cross(pv[a] - pv[b])
				acc[a] += fn
				acc[b] += fn
				acc[c] += fn
				i += 3
		else:
			var i := 0
			while i + 2 < nc:
				var fn := (pv[i + 2] - pv[i + 1]).cross(pv[i] - pv[i + 1])
				acc[i] = fn
				acc[i + 1] = fn
				acc[i + 2] = fn
				i += 3
		for k in nc:
			var l := acc[k].length()
			acc[k] = acc[k] / l if l > 0.0 else acc[k]
		var n := Attr.new()
		n.set_vec3_array(acc)
		attributes["normal"] = n
		return self

	func normalize_normals() -> Geometry:
		var n: Attr = attributes.get("normal")
		if n:
			var v := n.vec3_array()
			for i in v.size():
				var l := v[i].length()
				v[i] = v[i] / l if l > 0.0 else v[i]
			n.set_vec3_array(v)
		return self

	func to_non_indexed() -> Geometry:
		var g := Geometry.new()
		if not indexed:
			return clone()
		for name in attributes:
			var a: Attr = attributes[name]
			var s := a.item_size
			var out := PackedFloat32Array()
			out.resize(index.size() * s)
			var src := a.array
			var k := 0
			for ix in index:
				var o := ix * s
				for c in s:
					out[k + c] = src[o + c]
				k += s
			var na := Attr.new(out, s)
			na.normalized = a.normalized
			g.attributes[name] = na
		for gr in groups:
			g.groups.append(gr.duplicate())
		g.user_data = user_data.duplicate(true)
		return g

	func clone() -> Geometry:
		var g := Geometry.new()
		for name in attributes:
			g.attributes[name] = (attributes[name] as Attr).clone()
		g.index = index.duplicate()
		g.indexed = indexed
		for gr in groups:
			g.groups.append(gr.duplicate())
		if bounding_box != null:
			g.bounding_box = bounding_box
		g.user_data = user_data.duplicate(true)
		g.draw_start = draw_start
		g.draw_count = draw_count
		return g

	func center() -> Geometry:
		compute_bounding_box()
		if bounding_box == null:
			return self
		var c: Vector3 = (bounding_box as AABB).get_center()
		return translate(-c.x, -c.y, -c.z)


class Obj3D extends Bag:
	var name := ""
	var position := Vector3.ZERO
	var rotation := Vector3.ZERO
	var rotation_order := EULER_ORDER_XYZ
	var scale := Vector3.ONE
	var children: Array = []
	var _parent: WeakRef = null
	var user_data := {}
	var visible := true
	var matrix := Transform3D()
	var matrix_world := Transform3D()
	var matrix_auto_update := true
	var layer := 0
	var cast_shadow := false
	var receive_shadow := false
	var render_order := 0
	var frustum_culled := true
	var is_mesh := false
	var is_instanced := false

	func parent() -> Obj3D:
		return _parent.get_ref() if _parent else null

	func add(...objs: Array) -> Obj3D:
		for o in objs:
			if o == null or o == self:
				continue
			var p: Obj3D = o.parent()
			if p:
				p.children.erase(o)
			o._parent = weakref(self)
			children.append(o)
		return self

	func remove(...objs: Array) -> Obj3D:
		for o in objs:
			if children.has(o):
				children.erase(o)
				o._parent = null
		return self

	func traverse(fn: Callable) -> void:
		fn.call(self)
		for c in children.duplicate():
			c.traverse(fn)

	## rotation.set(x, y, z, order) with a three.js order string ("XYZ", "YXZ", ...).
	func set_rotation(x: float, y: float, z: float, order: String = "XYZ") -> void:
		rotation = Vector3(x, y, z)
		rotation_order = {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ, "YZX": EULER_ORDER_YZX, "ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}[order]

	func set_quaternion(q: Quaternion) -> void:
		rotation = Basis(q).get_euler(rotation_order)

	func quaternion() -> Quaternion:
		return Basis.from_euler(rotation, rotation_order).get_rotation_quaternion()

	func update_matrix() -> void:
		matrix = Transform3D(Basis.from_euler(rotation, rotation_order) * Basis.from_scale(scale), position)

	func update_matrix_world(_force: bool = false) -> void:
		if matrix_auto_update:
			update_matrix()
		var p := parent()
		matrix_world = p.matrix_world * matrix if p else matrix
		for c in children:
			c.update_matrix_world(true)

	func look_at(target: Vector3) -> void:
		# three.js Object3D.lookAt for non-cameras: local +Z points at the target
		update_matrix_world()
		var eye := matrix_world.origin
		var z := (target - eye)
		if z.length_squared() == 0.0:
			z = Vector3(0, 0, 1)
		z = z.normalized()
		var up := Vector3.UP
		var x := up.cross(z)
		if x.length_squared() == 0.0:
			if absf(up.z) == 1.0:
				z.x += 0.0001
			else:
				z.z += 0.0001
			z = z.normalized()
			x = up.cross(z)
		x = x.normalized()
		var y := z.cross(x)
		var b := Basis(x, y, z)
		var p := parent()
		if p:
			b = p.matrix_world.basis.orthonormalized().inverse() * b
		rotation = b.get_euler(EULER_ORDER_XYZ)

	func get_world_position() -> Vector3:
		update_matrix_world()
		return matrix_world.origin


class Group extends Obj3D:
	pass


class MeshObj extends Obj3D:
	var geometry: Geometry
	var material

	func _init(g: Geometry = null, m = null) -> void:
		geometry = g if g else Geometry.new()
		material = m
		is_mesh = true

	func materials() -> Array:
		return material if material is Array else [material]


class InstancedMesh extends MeshObj:
	var count := 0
	var instance_matrix: Array[Transform3D] = []
	var instance_color = null  # PackedColorArray once set_color_at is called

	func _init(g: Geometry = null, m = null, n: int = 0) -> void:
		super(g, m)
		is_instanced = true
		count = n
		instance_matrix.resize(n)
		for i in n:
			instance_matrix[i] = Transform3D()

	func set_matrix_at(i: int, t: Transform3D) -> void:
		instance_matrix[i] = t

	func get_matrix_at(i: int) -> Transform3D:
		return instance_matrix[i]

	func set_color_at(i: int, c: Color) -> void:
		if instance_color == null:
			instance_color = PackedColorArray()
			instance_color.resize(instance_matrix.size())
			for k in instance_color.size():
				instance_color[k] = Color(1, 1, 1)
		instance_color[i] = c


## A material description; core/scene.gd turns it into a Godot material.
class Mat extends Bag:
	var type := "toon"
	var color := Color(1, 1, 1)
	var vertex_colors := false
	var transparent := false
	var opacity := 1.0
	var alpha_test := 0.0
	var side := "front"
	var depth_write := true
	var emissive := Color(0, 0, 0)
	var emissive_intensity := 1.0
	var map = null
	var alpha_map = null
	var user_data := {}
	var name := ""
	var key := ""


## A texture stand-in: the port draws no canvases, so a map only carries its size and settings.
class Tex extends Bag:
	var is_texture := true
	var uuid := ""
	var width := 1
	var height := 1
	var repeat := Vector2.ONE
	var offset := Vector2.ZERO
	var user_data := {}


# ---------------------------------------------------------------- colour (three.js ColorManagement)

static func color(c) -> Color:
	if c is Color:
		return c
	if c is int:
		return Color.hex((c << 8) | 0xFF).srgb_to_linear()
	var s := str(c)
	if s.begins_with("#"):
		if s.length() == 4:
			s = "#" + s[1] + s[1] + s[2] + s[2] + s[3] + s[3]
		return Color.html(s).srgb_to_linear()
	return Color.from_string(s, Color(1, 1, 1)).srgb_to_linear()


static func hex_string(c: Color) -> String:
	var s := Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)).linear_to_srgb()
	return "%02x%02x%02x" % [roundi(s.r * 255.0), roundi(s.g * 255.0), roundi(s.b * 255.0)]


static func get_hsl(c: Color) -> Vector3:
	var r := c.r
	var g := c.g
	var b := c.b
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var h := 0.0
	var s := 0.0
	var l := (mn + mx) / 2.0
	if mn != mx:
		var d := mx - mn
		s = d / (mx + mn) if l <= 0.5 else d / (2.0 - mx - mn)
		if mx == r:
			h = (g - b) / d + (6.0 if g < b else 0.0)
		elif mx == g:
			h = (b - r) / d + 2.0
		else:
			h = (r - g) / d + 4.0
		h /= 6.0
	return Vector3(h, s, l)


static func _hue2rgb(p: float, q: float, t: float) -> float:
	if t < 0.0: t += 1.0
	if t > 1.0: t -= 1.0
	if t < 1.0 / 6.0: return p + (q - p) * 6.0 * t
	if t < 1.0 / 2.0: return q
	if t < 2.0 / 3.0: return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


static func from_hsl(h: float, s: float, l: float) -> Color:
	h = fposmod(h, 1.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	if s == 0.0:
		return Color(l, l, l)
	var p := l * (1.0 + s) if l <= 0.5 else l + s - (l * s)
	var q := (2.0 * l) - p
	return Color(_hue2rgb(q, p, h + 1.0 / 3.0), _hue2rgb(q, p, h), _hue2rgb(q, p, h - 1.0 / 3.0))


static func offset_hsl(c: Color, dh: float, ds: float, dl: float) -> Color:
	var hsl := get_hsl(c)
	return from_hsl(hsl.x + dh, hsl.y + ds, hsl.z + dl)


# ---------------------------------------------------------------- math

static func euler_basis(r: Vector3) -> Basis:
	return Basis.from_euler(r, EULER_ORDER_XYZ)


static func compose(p: Vector3, q: Quaternion, s: Vector3) -> Transform3D:
	return Transform3D(Basis(q) * Basis.from_scale(s), p)


static func quat_from_euler(r: Vector3) -> Quaternion:
	return Basis.from_euler(r, EULER_ORDER_XYZ).get_rotation_quaternion()


## three.js Quaternion.setFromUnitVectors.
static func quat_from_unit_vectors(a: Vector3, b: Vector3) -> Quaternion:
	var r := a.dot(b) + 1.0
	var q: Quaternion
	if r < EPS:
		r = 0.0
		if absf(a.x) > absf(a.z):
			q = Quaternion(-a.y, a.x, 0.0, r)
		else:
			q = Quaternion(0.0, -a.z, a.y, r)
	else:
		q = Quaternion(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x, r)
	return q.normalized()


static func js_round(x: float) -> float:
	return floor(x + 0.5)


static func sign(x: float) -> float:
	return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else x)


## A stable sort (Array.prototype.sort is stable; Godot's sort_custom is not).
## cmp(a, b) returns a number like a JS comparator.
static func stable_sort(arr: Array, cmp: Callable) -> Array:
	if arr.size() < 2:
		return arr
	var src := arr.duplicate()
	var dst := arr.duplicate()
	var width := 1
	var n := src.size()
	while width < n:
		var i := 0
		while i < n:
			var mid := mini(i + width, n)
			var hi := mini(i + 2 * width, n)
			var a := i
			var b := mid
			var k := i
			while a < mid and b < hi:
				if float(cmp.call(src[b], src[a])) < 0.0:
					dst[k] = src[b]
					b += 1
				else:
					dst[k] = src[a]
					a += 1
				k += 1
			while a < mid:
				dst[k] = src[a]
				a += 1
				k += 1
			while b < hi:
				dst[k] = src[b]
				b += 1
				k += 1
			i += 2 * width
		var t := src
		src = dst
		dst = t
		width *= 2
	for k in n:
		arr[k] = src[k]
	return arr
