# station.js: the station building (inside and out), forecourt, both platforms with shelters and
# furniture, name boards, fences, platform ends, east ramps and walkway, side and west yards.
# Publishes ctx.services.station = {benches: [{x, z, y, rotY, len}]}.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Util = preload("res://addons/sakuragaoka_station/world/station/util.gd")
const Tex = preload("res://addons/sakuragaoka_station/world/station/tex.gd")
const Mats = preload("res://addons/sakuragaoka_station/world/station/mats.gd")
const Building = preload("res://addons/sakuragaoka_station/world/station/building.gd")
const Interior = preload("res://addons/sakuragaoka_station/world/station/interior.gd")
const Platforms = preload("res://addons/sakuragaoka_station/world/station/platforms.gd")
const Yards = preload("res://addons/sakuragaoka_station/world/station/yards.gd")


func build(ctx) -> void:
	var root := T.Group.new()
	root.name = "station"
	ctx.add_static(root)
	var dyn := T.Group.new()
	dyn.name = "station-dynamic"
	var A := Station.new()
	A.ctx = ctx
	A.L = ctx.L
	A.P = ctx.physics
	A.root = root
	A.dyn = dyn
	A.U = Util.new(ctx)
	var tx: Dictionary = Tex.create_station_textures(ctx)
	var tx2: Dictionary = Tex.create_interior_textures(ctx, tx)
	A.tx = tx
	A.tx2 = tx2
	A.M = Mats.make_materials(ctx, tx, tx2)
	A.k = ctx.kit(root)
	A.kd = ctx.kit(dyn)
	A.atlases = tx.atlases.duplicate()
	A.atlases["N"] = tx2.atlases.N
	Building.build_building(A)
	Interior.build_interior(A)
	Platforms.build_platforms(A)
	Yards.build_yards(A)
	bake_colors(ctx, root)
	ctx.add(dyn)
	var benches := []
	for b in A.benches:
		benches.append({"x": b.x, "z": b.z, "y": b.y, "rotY": b.rotY, "len": b.len})
	ctx.services["station"] = {"benches": benches}


## Collapses plain solid-colour toon materials into a few shared vertex-coloured ones (colour baked
## per vertex). Emissive and flags are part of the signature; paint is bucketed.
static func bake_colors(ctx, root) -> void:
	var targets := {}
	root.traverse(func(o):
		if not o.is_mesh or o.is_instanced or o.user_data.get("dynamic", false):
			return
		var m = o.material
		if m == null or m is Array or m.type != "toon" or not m.has("opts"):
			return
		var op: Dictionary = m.opts
		if op.get("map") or op.get("alphaMap") or op.get("transparent") or op.get("alphaTest") or op.get("vertexColors") or op.get("side") \
				or op.get("polygonOffset") or op.get("depthWrite") == false or op.has("opacity"):
			return
		var paint: float = op.get("paint", 0.05)
		var sig := op.duplicate()
		sig["paint"] = 0.025 if paint < 0.035 else (0.05 if paint < 0.075 else 0.09)
		sig["vertexColors"] = true
		sig.erase("name")
		var key := JSON.stringify(sig, "", false)
		if not targets.has(key):
			targets[key] = ctx.mat.toon("#ffffff", sig)
		var g: T.Geometry = o.geometry.clone()
		var n := g.vertex_count()
		var a := PackedFloat32Array()
		a.resize(n * 3)
		for v in n:
			a[v * 3] = m.color.r
			a[v * 3 + 1] = m.color.g
			a[v * 3 + 2] = m.color.b
		g.set_attribute("color", T.Attr.new(a, 3))
		o.geometry = g
		o.material = targets[key])


## The shared state every station part builds with (station.js's A).
class Station extends RefCounted:
	var ctx
	var L
	var P
	var root
	var dyn
	var k
	var kd
	var U
	var M: Dictionary
	var tx: Dictionary
	var tx2: Dictionary
	var atlases: Dictionary
	var clocks := []
	var blinkers := []
	var benches := []
	var X
	var _smat := {}

	func sign_mat(name: String, lit = false):
		var key := "%s|%s" % [name, str(lit) if lit else "0"]
		if not _smat.has(key):
			var a = atlases[name]
			if lit:
				_smat[key] = ctx.mat.emissive("#ffffff", 0.92 if lit is bool else float(lit), {"map": a.tex})
			else:
				_smat[key] = ctx.mat.toon("#ffffff", {"map": a.tex, "paint": 0})
		return _smat[key]

	## textured plane (faces +Z before rotY) from an atlas item
	func plane(name: String, id, w: float, h: float, pos: Array, rot_y: float = 0.0, lit = false, parent = null):
		var m := T.MeshObj.new(U.rect_plane(w, h, atlases[name].r(id)), sign_mat(name, lit))
		m.position = Vector3(pos[0], pos[1], pos[2])
		m.rotation.y = rot_y
		m.receive_shadow = true
		m.cast_shadow = false
		(parent if parent != null else root).add(m)
		return m

	## framed board: backing box (frame) + atlas face plane in front; pos = centre of the face
	func board(name: String, id, w: float, h: float, pos: Array, rot_y: float = 0.0, o: Dictionary = {}):
		var g := T.Group.new()
		g.position = Vector3(pos[0], pos[1], pos[2])
		g.rotation.y = rot_y
		root.add(g)
		var kk = ctx.kit(g)
		var d: float = o.get("depth", 0.03)
		var b: float = o.get("border", 0.03)
		if not (o.has("frame") and o.frame == null):
			kk.box(w + b * 2.0, h + b * 2.0, d, o.frame if o.get("frame") != null else M.trim, [0, 0, -d / 2.0])
		var m := T.MeshObj.new(U.rect_plane(w, h, atlases[name].r(id)), sign_mat(name, o.get("lit", false)))
		m.position.z = 0.004
		m.receive_shadow = true
		g.add(m)
		if o.get("back"):
			var m2 := T.MeshObj.new(U.rect_plane(w, h, atlases[name].r(o.back)), sign_mat(name, o.get("lit", false)))
			m2.position.z = -d - 0.004
			m2.rotation.y = PI
			g.add(m2)
		return g

	## clock: static face, animated hands (dynamic)
	func clock(pos: Array, rot_y: float, r: float = 0.2, o: Dictionary = {}):
		var g := T.Group.new()
		g.position = Vector3(pos[0], pos[1], pos[2])
		g.rotation.y = rot_y
		root.add(g)
		var kk = ctx.kit(g)
		var dbl: bool = o.get("double", false)
		var faces := [0.0, PI] if dbl else [0.0]
		kk.cyl(r * 1.08, r * 1.08, 0.09 if dbl else 0.05, o.frame if o.get("frame") != null else M.fascia, [0, 0, 0 if dbl else -0.025], [PI / 2.0, 0, 0], 28)
		for fy in faces:
			var face := T.MeshObj.new(Geo.circle(r, 32), sign_mat("face", 0.9 if o.get("lit") else false))
			var z := 0.047 if dbl else 0.003
			face.position = Vector3(sin(fy) * z, 0, cos(fy) * z)
			face.rotation.y = fy
			g.add(face)
			var hg := T.Group.new()
			hg.position = g.position
			hg.rotation.y = rot_y + fy
			var off := Vector3(sin(fy) * (z + 0.006), 0, cos(fy) * (z + 0.006)).rotated(Vector3.UP, rot_y)
			hg.position += off
			dyn.add(hg)
			var hour := T.Group.new()
			var minute := T.Group.new()
			hg.add(hour)
			hg.add(minute)
			var hm := T.MeshObj.new(Geo.g_box(ctx.cache), M.ink)
			hm.scale = Vector3(r * 0.09, r * 0.55, 0.008)
			hm.position.y = r * 0.22
			hour.add(hm)
			var mm := T.MeshObj.new(Geo.g_box(ctx.cache), M.ink)
			mm.scale = Vector3(r * 0.06, r * 0.82, 0.008)
			mm.position = Vector3(0, r * 0.34, 0.006)
			minute.add(mm)
			var cap := T.MeshObj.new(Geo.g_sphere(ctx.cache, 8), M.signRed)
			cap.scale = Vector3.ONE * (r * 0.1)
			cap.position.z = 0.01
			hg.add(cap)
			clocks.append({"hour": hour, "minute": minute})
		return g
