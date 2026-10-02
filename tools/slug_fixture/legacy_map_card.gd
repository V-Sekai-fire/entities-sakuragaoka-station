# The first card mapping, kept only as a negative control for tools/slug_check.gd: it places EVERY
# baked vertex of the key on the card, extrapolating points outside the card's UV footprint onto
# the nearest triangle, so a card that samples one cell of an atlas got all the cells around it.
# The port now clips through slug_decal (core/slug/baked.gd map_decal); slug_check shows this
# version fails the in-footprint test.
extends RefCounted

const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")


static func bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2):
	return Baked.bary(p, a, b, c)


static func face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return Baked.face_normal(a, b, c)


## The baked triangles laid over a card. src: {pos: PackedVector3Array, nor (may be empty),
## uv: PackedVector2Array (geometry UV), idx: PackedInt32Array (Godot winding)}; xf: the texture's
## repeat.xy, offset.zw. Each baked point is located in texture space on the card triangle holding
## it (or the nearest) and placed by that triangle's barycentric coordinates. Returns unindexed
## triangles in Godot winding facing as the card triangle they land on: {pos, nor, param (per
## vertex), tri_paint (per triangle), overlay_from (first overlay triangle)}, or {} when the card
## has no UV area.
static func map_card(src: Dictionary, mesh: Dictionary, xf: Vector4) -> Dictionary:
	var tuv := PackedVector2Array()
	tuv.resize(src.uv.size())
	for i in src.uv.size():
		tuv[i] = src.uv[i] * Vector2(xf.x, xf.y) + Vector2(xf.z, xf.w)
	var bp: PackedVector2Array = mesh.positions
	var placed := PackedVector3Array()
	var pnor := PackedVector3Array()
	var host := PackedInt32Array()
	placed.resize(bp.size())
	pnor.resize(bp.size())
	host.resize(bp.size())
	var idx: PackedInt32Array = src.idx
	var has_nor: bool = src.nor.size() == src.pos.size()
	for i in bp.size():
		var best := -1
		var best_w := Vector3.ZERO
		var best_err := INF
		for t in range(0, idx.size() - 2, 3):
			var w = bary(bp[i], tuv[idx[t]], tuv[idx[t + 1]], tuv[idx[t + 2]])
			if w == null:
				continue
			var err := maxf(0.0, -minf(w.x, minf(w.y, w.z)))
			if err < best_err:
				best_err = err
				best = t
				best_w = w
				if err == 0.0:
					break
		if best < 0:
			return {}
		var a := idx[best]
		var b := idx[best + 1]
		var c := idx[best + 2]
		placed[i] = src.pos[a] * best_w.x + src.pos[b] * best_w.y + src.pos[c] * best_w.z
		pnor[i] = (src.nor[a] * best_w.x + src.nor[b] * best_w.y + src.nor[c] * best_w.z).normalized() if has_nor \
				else face_normal(src.pos[a], src.pos[b], src.pos[c])
		host[i] = best
	var out_pos := PackedVector3Array()
	var out_nor := PackedVector3Array()
	var out_prm := PackedVector2Array()
	var paint := PackedInt32Array()
	var bi: PackedInt32Array = mesh.indices
	var overlay_from := -1
	for t in range(0, bi.size() - 2, 3):
		if overlay_from < 0 and mesh.overlay.y > 0 and t >= mesh.overlay.x:
			overlay_from = t / 3
		var v := [bi[t], bi[t + 1], bi[t + 2]]
		var p0: Vector3 = placed[v[0]]
		var ht := host[v[0]]
		var hn := face_normal(src.pos[idx[ht]], src.pos[idx[ht + 1]], src.pos[idx[ht + 2]])
		if (placed[v[1]] - p0).cross(placed[v[2]] - p0).dot(hn) > 0.0:  # Godot fronts are clockwise
			v = [v[0], v[2], v[1]]
		for k in v:
			out_pos.append(placed[k])
			out_nor.append(pnor[k])
			out_prm.append(mesh.param[k])
		paint.append(mesh.paint[v[0]])
	return {"pos": out_pos, "nor": out_nor, "param": out_prm, "tri_paint": paint,
			"overlay_from": overlay_from if overlay_from >= 0 else paint.size()}


