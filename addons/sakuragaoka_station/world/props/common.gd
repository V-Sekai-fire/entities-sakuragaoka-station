# props/common.js: shared helpers for the props module: floor sampling, placement groups, geometry
# utilities. The canvas helpers (rr, sakuraFlower, vtext, ftext) only draw into textures, which the
# port does not draw (see props/vendtex.gd), so they are not ported.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

const DEG := PI / 180.0


static func make_helpers(ctx) -> Helpers:
	return Helpers.new(ctx)


## makeHelpers(ctx): { floorAt, footprint, toWorld, place }.
class Helpers extends RefCounted:
	const STEP_HEIGHT := 0.45
	var ctx
	var L
	var physics

	func _init(c) -> void:
		ctx = c
		L = c.L
		physics = c.physics

	## physics.js groundHeight(x, z, feetY): the highest walkable top (walk box or ramp) under (x,z)
	## not above feet + STEP_HEIGHT, else the terrain. The port's core Physics keeps the same
	## records in items: [type, cx, cz, hw, hd, rotY, r, y0, y1, top, yA, yB].
	func ground_height(x: float, z: float, feet_y: float = 1e9) -> float:
		var g: float = L.height_at(x, z)
		for it in physics.items:
			if it[0] != "walk" and it[0] != "ramp":
				continue
			var c: float = cos(it[5])
			var s: float = sin(it[5])
			var dx: float = x - it[1]
			var dz: float = z - it[2]
			var lx: float = dx * c - dz * s
			var lz: float = dx * s + dz * c
			if absf(lx) > it[3] or absf(lz) > it[4]:
				continue
			var top: float = it[9] if it[0] == "walk" else it[10] + (it[11] - it[10]) * (lz / (2.0 * it[4]) + 0.5)
			if top <= feet_y + STEP_HEIGHT and top > g:
				g = top
		return g

	## Floor height at (x,z): terrain, or a walkable surface an earlier module registered (<= +0.4 m).
	func floor_at(x: float, z: float) -> float:
		var h: float = L.height_at(x, z)
		var g: float = ground_height(x, z, h + 0.05)
		if is_nan(g) or is_inf(g) or g > h + 0.4:
			g = h
		return g

	## min / max floor under an oriented footprint (w along local x, d along local z).
	func footprint(cx: float, cz: float, w: float, d: float, rot_y: float = 0.0) -> Dictionary:
		var c := cos(rot_y)
		var s := sin(rot_y)
		var mn := INF
		var mx := -INF
		for a in range(-1, 2):
			for b in range(-1, 2):
				var lx := a * w / 2.0
				var lz := b * d / 2.0
				var y := floor_at(cx + lx * c + lz * s, cz - lx * s + lz * c)
				if y < mn:
					mn = y
				if y > mx:
					mx = y
		return {"min": mn, "max": mx}

	## local (lx,lz) in a frame (cx,cz,rotY) -> world {x,z}
	func to_world(cx: float, cz: float, rot_y: float, lx: float, lz: float) -> Dictionary:
		var c := cos(rot_y)
		var s := sin(rot_y)
		return {"x": cx + lx * c + lz * s, "z": cz - lx * s + lz * c}

	## Static group at a world position/rotation.
	func place(x: float, y: float, z: float, rot_y: float = 0.0, parent = null) -> T.Group:
		var g := T.Group.new()
		g.position = Vector3(x, y, z)
		g.rotation.y = rot_y
		if parent:
			parent.add(g)
		else:
			ctx.add_static(g)
		return g


# ------------------------------------------------------------------ geometry utilities

## Remap a geometry's 0..1 UVs into a canvas-pixel rectangle of an atlas (x0,y0 from the top).
static func cell_uv(geo: T.Geometry, x0: float, y0: float, w: float, h: float, W: float, H: float) -> T.Geometry:
	var uv: T.Attr = geo.get_attribute("uv")
	for i in uv.count():
		var u := uv.get_x(i)
		var v := uv.get_y(i)
		uv.set_xy(i, (x0 + u * w) / W, 1.0 - (y0 + (1.0 - v) * h) / H)
	return geo


## Point every UV of a geometry at one atlas pixel (flat colour swatch).
static func solid_uv(geo: T.Geometry, px: float, py: float, W: float, H: float) -> T.Geometry:
	var uv: T.Attr = geo.get_attribute("uv")
	for i in uv.count():
		uv.set_xy(i, px / W, 1.0 - py / H)
	return geo


## Make every geometry non-indexed with position/normal/uv only, then merge.
static func merge_all(geos: Array) -> T.Geometry:
	var list := []
	for g in geos:
		var n: T.Geometry = g.to_non_indexed() if g.indexed else g.clone()
		if not n.has_attribute("normal"):
			n.compute_vertex_normals()
		if not n.has_attribute("uv"):
			var z := PackedFloat32Array()
			z.resize(n.vertex_count() * 2)
			n.set_attribute("uv", T.Attr.new(z, 2))
		for k in n.attributes.keys():
			if k != "position" and k != "normal" and k != "uv":
				n.delete_attribute(k)
		n.clear_groups()
		list.append(n)
	return _merge_geoms(list)


static func _merge_geoms(list: Array) -> T.Geometry:
	var P := PackedFloat32Array()
	var N := PackedFloat32Array()
	var U := PackedFloat32Array()
	for g in list:
		P.append_array(g.attributes.position.array)
		N.append_array(g.attributes.normal.array)
		U.append_array(g.attributes.uv.array)
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(P, 3))
	g.set_attribute("normal", T.Attr.new(N, 3))
	g.set_attribute("uv", T.Attr.new(U, 2))
	g.compute_bounding_box()
	return g


## Transform helper: returns geo after translate/rotate (Euler xyz) in place.
static func xf(geo: T.Geometry, pos = [0, 0, 0], rot = [0, 0, 0], scl = null) -> T.Geometry:
	var s := Vector3(scl[0], scl[1], scl[2]) if scl != null else Vector3.ONE
	geo.apply_matrix4(T.compose(Vector3(pos[0], pos[1], pos[2]), T.quat_from_euler(Vector3(rot[0], rot[1], rot[2])), s))
	return geo


## A back side for a single-sided sheet (flag, card): flipped normals + winding, u mirrored so text
## reads right from behind.
static func back_side(geo: T.Geometry, offset: float = 0.0015) -> T.Geometry:
	var g: T.Geometry = geo.to_non_indexed() if geo.indexed else geo.clone()
	var p: T.Attr = g.attributes.position
	var n: T.Attr = g.attributes.normal
	var uv: T.Attr = g.attributes.uv
	var i := 0
	while i < p.count():
		for k in ["position", "normal", "uv"]:
			var a: T.Attr = g.attributes[k]
			var s := a.item_size
			for j in s:
				var t := a.array[(i + 1) * s + j]
				a.array[(i + 1) * s + j] = a.array[(i + 2) * s + j]
				a.array[(i + 2) * s + j] = t
		i += 3
	for k in n.count():
		n.set_xyz(k, -n.get_x(k), -n.get_y(k), -n.get_z(k))
		p.set_xyz(k, p.get_x(k) - n.get_x(k) * -offset, p.get_y(k) - n.get_y(k) * -offset, p.get_z(k) - n.get_z(k) * -offset)
		uv.set_x(k, 1.0 - uv.get_x(k))
	return g


## Box geometry bent along x: y += bend(xNorm) where xNorm in [-1,1].
static func bent_box(w: float, h: float, d: float, seg: int, bend: Callable) -> T.Geometry:
	var g := Geo.box(w, h, d, seg, 1, 1)
	var p: T.Attr = g.attributes.position
	for i in p.count():
		p.set_y(i, p.get_y(i) + float(bend.call(p.get_x(i) / (w / 2.0))))
	g.compute_vertex_normals()
	return g


static func rbox_geo(w: float, h: float, d: float, r: float, seg: int = 2) -> T.Geometry:
	return Geo.rounded_box(w, h, d, seg, minf(minf(r, w / 2.0), minf(h / 2.0, d / 2.0)))


## Pentagon (house-shaped) prism: ema plaque. Front face (+z) UV -> front rect, back/sides -> back
## rect (atlas px).
static func ema_geo(w: float, h: float, t: float, front: Array, back: Array, W: float, H: float) -> T.Geometry:
	var sh := h * 0.72  # shoulder height
	var pts := [[-w / 2.0, -h / 2.0], [w / 2.0, -h / 2.0], [w / 2.0, -h / 2.0 + sh], [0.0, h / 2.0], [-w / 2.0, -h / 2.0 + sh]]
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uvs := PackedFloat32Array()
	var fu := func(x: float, y: float, r: Array) -> Array:
		return [(r[0] + (x / w + 0.5) * r[2]) / W, 1.0 - (r[1] + (0.5 - y / h) * r[3]) / H]
	var tri := func(a: Array, b: Array, c: Array, z: float, nz: float, r: Array, flip_u: bool) -> void:
		for q in ([a, b, c] if nz > 0 else [a, c, b]):
			pos.append_array([q[0], q[1], z])
			nor.append_array([0.0, 0.0, nz])
			var uv: Array = fu.call(-q[0] if flip_u else q[0], q[1], r)
			uvs.append_array([uv[0], uv[1]])
	# fan triangulation (convex)
	for i in range(1, 4):
		tri.call(pts[0], pts[i], pts[i + 1], t / 2.0, 1.0, front, false)
		tri.call(pts[0], pts[i], pts[i + 1], -t / 2.0, -1.0, back, true)
	# sides
	var cu: float = (back[0] + back[2] / 2.0) / W
	var cv: float = 1.0 - (back[1] + back[3] / 2.0) / H
	for i in 5:
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % 5]
		var ex: float = b[0] - a[0]
		var ey: float = b[1] - a[1]
		var l := sqrt(ex * ex + ey * ey)
		var nx := ey / l
		var ny := -ex / l
		var quad := [[a[0], a[1], t / 2.0], [b[0], b[1], t / 2.0], [b[0], b[1], -t / 2.0], [a[0], a[1], t / 2.0], [b[0], b[1], -t / 2.0], [a[0], a[1], -t / 2.0]]
		for q in quad:
			pos.append_array(q)
			nor.append_array([nx, ny, 0.0])
			uvs.append_array([cu, cv])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uvs, 2))
	return g


## Wavy cloth sheet (flag) w x h facing +z, hanging from the top-left corner region.
static func wave_sheet(w: float, h: float, amp: float = 0.03, waves: float = 1.3, seed: float = 0.0) -> T.Geometry:
	var g := Geo.plane(w, h, 10, 6)
	var p: T.Attr = g.attributes.position
	for i in p.count():
		var x := p.get_x(i)
		var y := p.get_y(i)
		var u := x / w + 0.5
		var v := 0.5 - y / h
		p.set_z(i, amp * sin((u * waves + seed) * PI * 2.0) * (0.4 + 0.6 * u) + amp * 0.35 * sin((v * 1.5 + seed * 0.7) * PI * 2.0) * u)
	g.compute_vertex_normals()
	return g
