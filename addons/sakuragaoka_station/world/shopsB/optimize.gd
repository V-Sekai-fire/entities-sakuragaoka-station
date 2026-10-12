# shopsB/optimize.js: draw-call optimisation. Plain cel materials that differ only by colour are
# collapsed into ONE vertex-coloured material per option set (same map / paint / side ...): the colour
# is baked into a per-vertex 'color' attribute, so the core static batcher can merge hundreds of small
# parts into a handful of draw calls. Interior "warm glow" materials (emissive proportional to albedo)
# are grouped the same way per glow level, with the emissive tint taken from the group's average colour.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")


static func consolidate(ctx, K, opts: Dictionary = {}) -> Dictionary:
	var roots: Array = K.spaces
	var rec: Dictionary = K.rec
	var mat = ctx.mat
	var stats := {"meshes": 0, "before": {}, "after": {}, "skipped": 0}
	var jobs := []
	for root in roots:
		root.traverse(func(o):
			if not o.is_mesh or o.is_instanced or o.material is Array:
				return
			if o.user_data.get("noBatch") or o.user_data.get("keepMat"):
				return
			var r = rec.get(o.material)
			if r == null:
				stats.skipped += 1
				return
			var op: Dictionary = r.o if r.o else {}
			if op.get("vertexColors") or op.get("transparent") or op.get("alphaMap") or (op.opacity if op.get("opacity") != null else 1.0) < 1.0:
				stats.skipped += 1
				return
			if op.get("emissive") and not r.glow:
				stats.skipped += 1
				return
			var c: Color = o.material.color
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			jobs.append({"o": o, "r": r, "glow": maxf(0.1, T.js_round(r.glow * 10) / 10.0) if r.glow else 0.0,
				"band": 0 if lum < 0.07 else (1 if lum < 0.28 else 2)}))
	# group glow materials by (glow, opts) to derive one emissive tint per group
	var glow_groups := {}
	var key_cache := {}
	var key_of := func(r) -> String:
		var k = key_cache.get(r)
		if k == null:
			var o: Dictionary = r.o.duplicate()
			o.erase("emissive")
			o.erase("emissiveIntensity")
			k = K.opt_key(o)
			key_cache[r] = k
		return k
	var made := {}
	var toon := func(o: Dictionary):
		var k: String = K.opt_key(o)
		var mm = made.get(k)
		if mm == null:
			mm = mat.toon("#ffffff", o)
			made[k] = mm
		return mm
	for j in jobs:
		if not j.glow:
			continue
		var k := "%s|%d|%s" % [str(j.glow), j.band, key_of.call(j.r)]
		var g = glow_groups.get(k)
		if g == null:
			g = {"r": 0.0, "g": 0.0, "b": 0.0, "n": 0}
			glow_groups[k] = g
		var c: Color = j.o.material.color
		g.r += c.r
		g.g += c.g
		g.b += c.b
		g.n += 1
	var warm := T.color("#ffc58a")
	for j in jobs:
		var o = j.o
		var r = j.r
		var glow: float = j.glow
		var mm = o.material
		stats.before[mm] = true
		var nm
		var base: Dictionary = r.o.duplicate()
		base.erase("emissive")
		base.erase("emissiveIntensity")
		if glow:
			var g = glow_groups.get("%s|%d|%s" % [str(glow), j.band, key_of.call(r)])
			var avg := Color(g.r / g.n, g.g / g.n, g.b / g.n) * warm
			var oo := base.duplicate()
			oo["vertexColors"] = true
			oo["emissive"] = "#" + T.hex_string(avg)
			oo["emissiveIntensity"] = glow
			nm = toon.call(oo)
		else:
			var oo := base.duplicate()
			oo["vertexColors"] = true
			nm = toon.call(oo)
		var geo: T.Geometry = o.geometry.clone()
		var n := geo.vertex_count()
		var col := PackedFloat32Array()
		col.resize(n * 3)
		var c: Color = mm.color
		for i in n:
			col[i * 3] = c.r
			col[i * 3 + 1] = c.g
			col[i * 3 + 2] = c.b
		geo.set_attribute("color", T.Attr.new(col, 3))
		o.geometry = geo
		o.material = nm
		stats.after[nm] = true
		stats.meshes += 1
	return {"meshes": stats.meshes, "materialsBefore": stats.before.size(), "materialsAfter": stats.after.size(), "skipped": stats.skipped}
