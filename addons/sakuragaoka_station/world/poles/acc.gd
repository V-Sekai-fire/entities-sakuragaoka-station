# poles/acc.js: geometry accumulator. Bakes many small parts (transformed, vertex-coloured, atlas-UV'd)
# into one geometry so a whole pole is 2-3 meshes (then static batching merges poles per cell).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

var parts: Array = []
var T_ := Transform3D()
var white: Array
var tris := 0.0


func _init(white_uv: Array) -> void:
	white = white_uv


## geo: source geometry (not modified). m: local transform (pre-multiplied by T_). col: Color (linear)
## or null. uvr: [u0, v0, u1, v1] to remap the geometry's own 0..1 UVs into an atlas rect; null =
## sample the white patch.
func add(geo: T.Geometry, m, col, uvr = null) -> T.Geometry:
	var g := geo.clone()
	for k in g.attributes.keys():
		if k != "position" and k != "normal" and k != "uv":
			g.delete_attribute(k)
	g.clear_groups()
	if not g.has_attribute("normal"):
		g.compute_vertex_normals()
	var n := g.vertex_count()
	if not g.has_attribute("uv"):
		var z := PackedFloat32Array()
		z.resize(n * 2)
		g.set_attribute("uv", T.Attr.new(z, 2))
	if not g.indexed:
		var idx := PackedInt32Array()
		idx.resize(n)
		for i in n:
			idx[i] = i
		g.set_index(idx)
	var mm: Transform3D = m if m != null else Transform3D()
	g.apply_matrix4(T_ * mm)
	var c := PackedFloat32Array()
	c.resize(n * 3)
	var r: float = col.r if col != null else 1.0
	var gg: float = col.g if col != null else 1.0
	var b: float = col.b if col != null else 1.0
	for i in n:
		c[i * 3] = r
		c[i * 3 + 1] = gg
		c[i * 3 + 2] = b
	g.set_attribute("color", T.Attr.new(c, 3))
	var uva: T.Attr = g.get_attribute("uv")
	var uv := uva.array
	if uvr == null:
		for i in n:
			uv[i * 2] = white[0]
			uv[i * 2 + 1] = white[1]
	else:
		var u0: float = uvr[0]
		var v0: float = uvr[1]
		var u1: float = uvr[2]
		var v1: float = uvr[3]
		for i in n:
			uv[i * 2] = u0 + uv[i * 2] * (u1 - u0)
			uv[i * 2 + 1] = v0 + uv[i * 2 + 1] * (v1 - v0)
	uva.array = uv
	tris += g.index.size() / 3.0
	parts.append(g)
	return g


func build():
	if parts.is_empty():
		return null
	var g: T.Geometry = Geo.merge_geometries(parts, false)
	parts = []
	if g == null:
		return null
	g.compute_bounding_sphere()
	g.compute_bounding_box()
	return g
