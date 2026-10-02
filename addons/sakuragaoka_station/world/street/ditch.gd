# street/ditch.js: open and grated ditch spans as a flat quad at the rim level; the original's fragment
# shader traces a virtual U-channel below it. The port keeps the geometry and its per-vertex channel
# attributes (dLoc, dN, dSpan) and renders it with a plain shader material.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")


class DitchBuilder extends RefCounted:
	var pos := []
	var loc := []
	var dn := []
	var span := []
	var idx := []
	var n := 0

	## a: across offset (+n side), s: along, dp: plane depth below rim, n2: across unit (x, z),
	## span: [s0, s1, wi, wl] (along range, inner half width, water depth below rim).
	func vert(x: float, y: float, z: float, a: float, s: float, dp: float, n2: Array, sp: Array) -> int:
		pos.append_array([x, y, z])
		loc.append_array([a, s, dp])
		dn.append_array([n2[0], n2[1]])
		span.append_array([sp[0], sp[1], sp[2], sp[3]])
		n += 1
		return n - 1

	func quad(a: int, b: int, c: int, d: int) -> void:
		var p := pos
		var ux: float = p[b * 3] - p[a * 3]
		var uz: float = p[b * 3 + 2] - p[a * 3 + 2]
		var vx: float = p[c * 3] - p[a * 3]
		var vz: float = p[c * 3 + 2] - p[a * 3 + 2]
		var ny := uz * vx - ux * vz
		if ny >= 0:
			idx.append_array([a, b, c, a, c, d])
		else:
			idx.append_array([a, c, b, a, d, c])

	func is_empty() -> bool:
		return idx.is_empty()

	func mesh(material) -> T.MeshObj:
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(pos), 3))
		var nrm := PackedFloat32Array()
		nrm.resize(n * 3)
		for i in n:
			nrm[i * 3 + 1] = 1.0
		g.set_attribute("normal", T.Attr.new(nrm, 3))
		g.set_attribute("dLoc", T.Attr.new(PackedFloat32Array(loc), 3))
		g.set_attribute("dN", T.Attr.new(PackedFloat32Array(dn), 2))
		g.set_attribute("dSpan", T.Attr.new(PackedFloat32Array(span), 4))
		g.set_index(PackedInt32Array(idx))
		var m := T.MeshObj.new(g, material)
		m.receive_shadow = true
		m.cast_shadow = false
		m.name = "street-ditch-interior"
		m.user_data["noBatch"] = true
		return m


static func ditch_material(ctx):
	return ctx.mat.shader("street-ditch", "#b3b1a8", {"name": "street-ditch"})
