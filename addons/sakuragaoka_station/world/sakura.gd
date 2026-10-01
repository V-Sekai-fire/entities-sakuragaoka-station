# sakura.js: every cherry tree in the town. The big plaza tree, the W3 garden tree arching over the
# main street, the shrine's weeping cherry, station and platform trees, the rows along the railway
# corridor, the levee rows, roadside pit trees and garden trees; seeded and procedural (sakura/tree.gd).
# Publishes ctx.services.sakura = {trees: [{id, kind, x, z, y, r, h, bottom, ground, trunk: {x, z, r}}]}.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const U = preload("res://addons/sakuragaoka_station/world/sakura/util.gd")
const SakuraTree = preload("res://addons/sakuragaoka_station/world/sakura/tree.gd")
const Placements = preload("res://addons/sakuragaoka_station/world/sakura/placements.gd")
const Bases = preload("res://addons/sakuragaoka_station/world/sakura/bases.gd")
const Mats = preload("res://addons/sakuragaoka_station/world/sakura/materials.gd")


func build(ctx):
	var L = ctx.L
	var TX := Mats.create_textures(ctx)
	var M := Mats.create_materials(ctx, TX)
	var noise := U.ValueNoise.new(ctx.rng("sakura-noise"))
	var sd: Array = L.SUN_DIR
	var sl := U.hypot3(sd[0], sd[1], sd[2])
	var env := {"rng": ctx.rng, "noise": noise, "heightAt": L.height_at, "sun": [sd[0] / sl, sd[1] / sl, sd[2] / sl]}
	var placed: Dictionary = Placements.make_placements(ctx)
	var specs: Array = placed.trees

	var root := T.Group.new()
	root.name = "sakura"
	var bases := Bases.BaseBuilder.new(ctx, M)
	var published := []
	var blob_cells := {}
	for spec in specs:
		var t: Dictionary = SakuraTree.make_tree(spec, env)
		var g := T.Group.new()
		g.name = "sakura-" + spec.id
		var bark_geo: T.Geometry = t.bark.build(false)
		if bark_geo != null:
			var m := T.MeshObj.new(bark_geo, M.barkYoung if spec.bark == "young" else M.barkOld)
			m.cast_shadow = true
			m.receive_shadow = true
			g.add(m)
		# blossom masses stay on the outline layer and are merged per 48 m cell here (not by the core
		# batcher) to keep the dappled shadow material
		var blob_geo: T.Geometry = t.blob.build(true)
		if blob_geo != null:
			var c := _box_center_xz(blob_geo.position().array)
			var key := "%d,%d" % [floori(c[0] / 48.0), floori(c[1] / 48.0)]
			if not blob_cells.has(key):
				blob_cells[key] = []
			blob_cells[key].append(blob_geo)
		# cards: no-outline layer (alpha cut-outs)
		var card_geo: T.Geometry = t.cards.build(true)
		if card_geo != null:
			var m := T.MeshObj.new(card_geo, M.cards)
			m.cast_shadow = true
			m.receive_shadow = false
			ctx.no_outline(m)
			g.add(m)
		root.add(g)
		for c in t.colliders:
			ctx.physics.addCylinder(c.x, c.z, c.r, c.y0, c.y1)
		bases.build(spec)
		var I: Dictionary = t.info
		published.append({"id": spec.id, "kind": spec.kind, "x": snappedf(I.x, 0.01), "z": snappedf(I.z, 0.01), "y": snappedf(I.y, 0.01), "r": snappedf(I.r, 0.01),
			"h": snappedf(I.h, 0.01), "bottom": snappedf(I.bottom, 0.01), "ground": snappedf(t.groundY, 0.001), "trunk": {"x": spec.x, "z": spec.z, "r": spec.trunkR}})
	for key in blob_cells:
		var list: Array = blob_cells[key]
		var geo: T.Geometry = Geo.merge_geometries(list, false) if list.size() > 1 else list[0]
		if geo == null:
			continue
		geo.compute_bounding_box()
		var m := T.MeshObj.new(geo, M.blob)
		m.name = "sakura-mass-" + key
		m.cast_shadow = true
		m.receive_shadow = false
		m.user_data["customDepthMaterial"] = M.blobDepth
		ctx.no_batch(m)
		root.add(m)
	var B: Dictionary = bases.finish()
	for m in B.meshes:
		root.add(m)
	root.add(B.group)
	ctx.add_static(root)
	ctx.services["sakura"] = {"trees": published}
	return null


## The centre (x, z) of a float32 position array's bounding box, in float64 like three.js.
static func _box_center_xz(p: PackedFloat32Array) -> Array:
	var x0 := INF
	var x1 := -INF
	var z0 := INF
	var z1 := -INF
	var i := 0
	var n := p.size()
	while i < n:
		var x := p[i]
		var z := p[i + 2]
		x0 = minf(x0, x)
		x1 = maxf(x1, x)
		z0 = minf(z0, z)
		z1 = maxf(z1, z)
		i += 3
	return [(x0 + x1) * 0.5, (z0 + z1) * 0.5]
