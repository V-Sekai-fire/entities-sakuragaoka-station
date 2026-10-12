extends SceneTree
const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")

func _initialize() -> void:
	var ctx = Ctx.new(1, "")
	var C = load("res://addons/sakuragaoka_station/world/shopsA/common.gd").new(ctx)
	C.G = load("res://addons/sakuragaoka_station/world/shopsA/goods.gd").new(ctx, C)
	load("res://addons/sakuragaoka_station/world/shopsA/konbini.gd").build_konbini(ctx, C)
	var only := OS.get_environment("SHOPS_ONLY").split(",", false)
	for e in [["cafe", "build_cafe"], ["flower", "build_flower"], ["books", "build_books"]]:
		if only.has(e[0]):
			load("res://addons/sakuragaoka_station/world/shopsA/%s.gd" % e[0]).call(e[1], ctx, C)
	C.scatter.build()
	C.G.build()
	ctx.scene.update_matrix_world(true)
	var tris := 0.0
	var meshes := 0
	var inst := {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var groups := {}
	var all := []
	ctx.scene.traverse(func(o): all.append(o))
	for o in all:
		if not o.is_mesh:
			continue
		meshes += 1
		var g = o.geometry
		var t: float = g.triangle_count()
		if o.is_instanced:
			inst[o.name] = [o.count, t]
		else:
			tris += t
			if g.bounding_box == null:
				g.compute_bounding_box()
			var b: AABB = o.matrix_world * (g.bounding_box as AABB)
			lo = lo.min(b.position)
			hi = hi.max(b.end)
			var p = o
			while p.parent() != null and not str(p.parent().name).begins_with("shopsA:") and p.parent().parent() != null:
				p = p.parent()
			var gn = p.parent().name if p.parent() != null else "root"
			groups[gn] = groups.get(gn, 0) + t
	print("plain tris ", tris, " meshes ", meshes, " box ", lo, " ", hi)
	print("groups ", groups)
	var keys := inst.keys()
	keys.sort()
	var itot := 0.0
	for k in keys:
		print("inst ", k, " ", inst[k][0], " ", inst[k][1])
		itot += inst[k][0] * inst[k][1]
	print("colliders ", ctx.physics.items.size(), " wires ", ctx.wires.count())
	print("total tris ", tris + itot)
	quit(0)
