# shopsB/common.js: the shared toolkit. Lot-space helpers, hand-painted detail textures (sized
# stand-ins: the port draws no canvases), walls with openings, sliding doors, windows, roofs, cloth
# (nobori / noren) animation, lanterns, steam, small props.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Foliage = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")
const Inst = preload("res://addons/sakuragaoka_station/world/shopsB/inst.gd")

## Colours (soft Showa palette).
const C := {
	"frame": "#5a4032", "frameDeep": "#4a3528", "woodMid": "#7a5a42", "wood": "#8a6446", "woodLight": "#b48a62", "woodPale": "#cfae84", "woodAged": "#8e7862",
	"plaster": "#efe6d3", "plasterWarm": "#eadcc4", "plasterGrey": "#dcd8cf", "mortar": "#cbc5b8", "base": "#b7b1a6", "concrete": "#c6c3bb", "concreteDark": "#a9a69f",
	"tile": "#5f6a79", "tileDark": "#4f5866", "metalRoof": "#7b8691", "metalBlue": "#5f7389", "rust": "#9a6450",
	"alu": "#b9bfc4", "aluDark": "#8d949b", "steel": "#9aa1a8", "steelDark": "#6d747c", "ink": "#3a3346", "white": "#ece8df", "paper": "#f1ece0",
	"red": "#c9473e", "redDeep": "#a93a35", "pink": "#f2b5c8", "pinkDeep": "#e38aa6", "indigo": "#3e4d78", "green": "#6f9a6a", "mint": "#a9cfc0", "copper": "#8fb7a3",
}

## Detail textures (near-white; tinted by material colour): [name, w, h, key]. All tile [1, 1].
const DETAIL := [
	["plaster", 512, 512, "sb-plaster"], ["siding", 512, 512, "sb-siding"], ["vboards", 512, 512, "sb-vboards"],
	["grain", 256, 256, "sb-grain"], ["tile", 512, 512, "sb-tile"], ["kawara", 512, 512, "sb-kawara"],
	["corr", 256, 256, "sb-corr"], ["shutter", 256, 256, "sb-shutter"], ["concrete", 512, 512, "sb-concrete"],
	["gravel", 256, 256, "sb-gravel"], ["copper", 512, 512, "sb-copper"], ["peg", 256, 256, "sb-peg"],
	["bamboo", 256, 256, "sb-bamboo"],
]

var ctx
var F
var mat
var tex
var L
## The detail texture table (K.T in the original; T is three.gd here).
var TX: Dictionary = {}
var I
var rec := {}
var memo_ := {}
var spaces: Array = []
var _ht := {}
var cloth_updaters: Array = []


static func smooth(a: float, b: float, x: float) -> float:
	var t := minf(1.0, maxf(0.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)


func _init(c) -> void:
	ctx = c
	mat = c.mat
	tex = c.tex
	L = c.L
	F = tex.FONTS
	for d in DETAIL:
		TX[d[0]] = draw(d[1], d[2], d[3])
	ctx.on_update(func(dt, t):
		var gust: float = ctx.shared.uGust
		for f in cloth_updaters:
			f.call(t, gust, dt))


func draw(w: int, h: int, key: String, repeat := true):
	var o := {"key": key}
	if repeat:
		o["repeat"] = [1, 1]
	return tex.draw(w, h, null, o)


# ------------------------------------------------------------------ materials
# Every plain / texture-tinted toon material made through K is recorded so optimize.js can bake its
# colour into vertex colours and collapse many colours into one material (far fewer draw calls).

static func _val(v) -> String:
	if v is T.Tex:
		return "tex:" + v.uuid
	if v is Color:
		return "#" + T.hex_string(v)
	return var_to_str(v)


func opt_key(o: Dictionary) -> String:
	var ks := o.keys()
	ks.sort()
	var parts := []
	for k in ks:
		parts.append("%s:%s" % [k, _val(o[k])])
	return "{" + ",".join(parts) + "}"


func toon_memo(color, o: Dictionary = {}):
	var key: String = (color if color is String else "#" + T.hex_string(T.color(color))) + "|" + opt_key(o)
	var m = memo_.get(key)
	if m == null:
		m = mat.toon(color, o)
		memo_[key] = m
	return m


## Memoised ctx.mat.decal / ctx.mat.emissive.
func memo(kind: String, color, o: Dictionary = {}, intensity: float = 1.0):
	var key := kind + "|" + str(color) + "|" + str(intensity) + "|" + opt_key(o)
	var m = memo_.get(key)
	if m == null:
		m = mat.decal(color, o) if kind == "decal" else mat.emissive(color, intensity, o)
		memo_[key] = m
	return m


func _toon_r(color, o: Dictionary, glow: float = 0.0):
	var m = toon_memo(color, o)
	if not rec.has(m):
		rec[m] = {"color": color, "o": o, "glow": glow}
	return m


func m(color, o: Dictionary = {}):
	return _toon_r(color, o)


func mt(color, map, o: Dictionary = {}):
	var oo := {"map": map}
	oo.merge(o, true)
	return _toon_r(color, oo)


## Interior material: warm self-light so rooms read as lit behind glass even in shadow.
func im(color, glow: float = 0.3, o: Dictionary = {}):
	var c := T.color(color) * T.color("#ffc58a")
	var oo := o.duplicate()
	oo["emissive"] = "#" + T.hex_string(Color(c.r, c.g, c.b))
	oo["emissiveIntensity"] = glow
	return _toon_r(color, oo, glow)


func lamp(intensity: float = 1.3, color = "#ffe3b8"):
	return mat.emissive(color, intensity)


func glass(o: Dictionary = {}):
	var oo := {"tint": "#a6bccb", "opacity": 0.3}
	oo.merge(o, true)
	return mat.glass(oo)


# ------------------------------------------------------------------ geometry

static func v3(p) -> Vector3:
	return Vector3(p[0], p[1], p[2])


static func _r(rot, i: int) -> float:
	return float(rot[i]) if i < rot.size() and rot[i] != null else 0.0


static func _rot(o, rot) -> void:
	if rot != null:
		o.rotation = Vector3(_r(rot, 0), _r(rot, 1), _r(rot, 2))


## Box geometry with world-tiled UVs (tile = metres per texture repeat); off = box centre in parent space.
func box_geo(w: float, h: float, d: float, tile: float = 1.0, off = [0, 0, 0], tile_v = null) -> T.Geometry:
	var tv: float = tile if tile_v == null else tile_v
	var g := Geo.box(w, h, d)
	var p: T.Attr = g.attributes["position"]
	var n: T.Attr = g.attributes["normal"]
	var uv: T.Attr = g.attributes["uv"]
	for i in p.count():
		var x: float = p.get_x(i) + off[0]
		var y: float = p.get_y(i) + off[1]
		var z: float = p.get_z(i) + off[2]
		var nx := n.get_x(i)
		var ny := n.get_y(i)
		var nz := n.get_z(i)
		var u: float
		var v: float
		if absf(nx) > 0.5:
			u = -z * T.sign(nx)
			v = y
		elif absf(ny) > 0.5:
			u = x
			v = -z * T.sign(ny)
		else:
			u = x * T.sign(nz)
			v = y
		uv.set_xy(i, u / tile, v / tv)
	return g


func _finish(parent, mm, pos, rot):
	mm.position = v3(pos)
	_rot(mm, rot)
	mm.cast_shadow = true
	mm.receive_shadow = true
	parent.add(mm)
	return mm


## Textured box (centre pos) with world-tiled UV.
func tbox(parent, w: float, h: float, d: float, material, pos, tile: float = 1.0, rot = null, tile_v = null):
	var mm := T.MeshObj.new(box_geo(w, h, d, tile, [0, 0, 0] if rot != null else pos, tile if tile_v == null else tile_v), material)
	return _finish(parent, mm, pos, rot)


## Box via shared unit geometry (untextured).
func box(parent, w: float, h: float, d: float, material, pos, rot = null):
	var mm := T.MeshObj.new(Geo.g_box(ctx.cache), material)
	mm.scale = Vector3(w, h, d)
	return _finish(parent, mm, pos, rot)


func boxb(parent, w: float, h: float, d: float, material, pos, rot = null):
	return box(parent, w, h, d, material, [pos[0], pos[1] + h / 2.0, pos[2]], rot)


func cyl(parent, r: float, h: float, material, pos, seg: int = 12, rot = null, r2 = null):
	var rb: float = r if r2 == null else r2
	var mm: T.MeshObj
	if r == rb:
		mm = T.MeshObj.new(Geo.g_cyl(ctx.cache, seg), material)
		mm.scale = Vector3(r * 2.0, h, r * 2.0)
	else:
		mm = T.MeshObj.new(Geo.cylinder(r, rb, 1, seg), material)
		mm.scale = Vector3(1, h, 1)
	return _finish(parent, mm, pos, rot)


func sph(parent, r: float, material, pos, seg: int = 10, scale = null):
	var mm := T.MeshObj.new(Geo.g_sphere(ctx.cache, seg), material)
	mm.scale = Vector3(r * 2.0, r * 2.0, r * 2.0)
	if scale != null:
		mm.scale *= v3(scale)
	return _finish(parent, mm, pos, null)


func rbox(parent, w: float, h: float, d: float, r: float, material, pos, rot = null):
	var mm := T.MeshObj.new(Geo.g_rbox(ctx.cache, r, 2), material)
	mm.scale = Vector3(w, h, d)
	return _finish(parent, mm, pos, rot)


## Rounded box with true radius (unique geometry).
func rbox_r(parent, w: float, h: float, d: float, r: float, material, pos, rot = null):
	var mm := T.MeshObj.new(Geo.rounded_box(w, h, d, 2, minf(minf(r, w / 2.0), minf(h / 2.0, d / 2.0))), material)
	return _finish(parent, mm, pos, rot)


## Plane facing +Z (no shadow cast).
func plane(parent, w: float, h: float, material, pos, rot_y: float = 0.0, rot_x: float = 0.0):
	var mm := T.MeshObj.new(Geo.g_plane(ctx.cache), material)
	mm.scale = Vector3(w, h, 1)
	mm.position = v3(pos)
	mm.rotation = Vector3(rot_x, rot_y, 0)
	mm.receive_shadow = true
	parent.add(mm)
	return mm


## Poster / sticker (decal material, 4 mm in front of its surface; the caller passes the surface pos).
func decal(parent, texture, w: float, h: float, pos, rot_y: float = 0.0, o: Dictionary = {}):
	var oo := {"map": texture}
	oo.merge(o, true)
	return plane(parent, w, h, memo("decal", "#ffffff", oo), pos, rot_y)


## Horizontal cylinder along X.
func cyl_x(parent, r: float, length: float, material, pos, seg: int = 10):
	return cyl(parent, r, length, material, pos, seg, [0, 0, PI / 2.0])


func cyl_z(parent, r: float, length: float, material, pos, seg: int = 10):
	return cyl(parent, r, length, material, pos, seg, [PI / 2.0, 0, 0])


func lathe(parent, pts: Array, material, pos, seg: int = 16, rot_y: float = 0.0):
	var v := []
	for p in pts:
		v.append(Vector2(p[0], p[1]))
	var mm := T.MeshObj.new(Geo.lathe(v, seg), material)
	mm.rotation.y = rot_y
	return _finish(parent, mm, pos, null)


func extrude(parent, pts: Array, depth: float, material, pos, rot = null, opts = null):
	var mm := T.MeshObj.new(Geo.extrude(pts, depth, opts if opts != null else {}), material)
	return _finish(parent, mm, pos, rot)


## Half tube (round side up), axis along Z, flat side at y = 0 (cached).
func half_tube(r: float, length: float) -> T.Geometry:
	var key := "%s|%s" % [str(r), str(length)]
	if _ht.has(key):
		return _ht[key]
	var g := Geo.cylinder(r, r, length, 7, 1, false, 0, PI)
	g.rotate_z(PI / 2.0)
	g.rotate_y(PI / 2.0)
	_ht[key] = g
	return g


## Wall with rectangular openings. o: {axis: "x"|"z", a0, a1 (along axis), y0, y1, c (plane centre
## coord), t, holes: [{a0, a1, y0, y1}], tile}
func wall(parent, material, o: Dictionary) -> Array:
	var holes := []
	for h in o.get("holes", []):
		var hh := {"a0": maxf(o.a0, h.a0), "a1": minf(o.a1, h.a1), "y0": maxf(o.y0, h.y0), "y1": minf(o.y1, h.y1)}
		if hh.a1 > hh.a0 and hh.y1 > hh.y0:
			holes.append(hh)
	var cuts := [float(o.a0), float(o.a1)]
	for h in holes:
		cuts.append(h.a0)
		cuts.append(h.a1)
	var uniq := []
	for c in cuts:
		if not uniq.has(c):
			uniq.append(c)
	cuts = T.stable_sort(uniq, func(a, b): return a - b)
	var cols := []
	for i in cuts.size() - 1:
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 1e-4:
			continue
		var mid := (a + b) / 2.0
		var hs := []
		for h in holes:
			if h.a0 <= mid and h.a1 >= mid:
				hs.append(h)
		hs = T.stable_sort(hs, func(p, q): return p.y0 - q.y0)
		var spans := []
		var y: float = o.y0
		for h in hs:
			if h.y0 > y + 1e-4:
				spans.append([y, h.y0])
			y = maxf(y, h.y1)
		if y < o.y1 - 1e-4:
			spans.append([y, o.y1])
		var last = cols[cols.size() - 1] if cols.size() > 0 else null
		if last != null and last.spans == spans and absf(last.b - a) < 1e-6:
			last.b = b
		else:
			cols.append({"a": a, "b": b, "spans": spans})
	var out := []
	var tile: float = o.tile if o.get("tile") else 1.0
	for c in cols:
		for s in c.spans:
			var y0: float = s[0]
			var y1: float = s[1]
			var length: float = c.b - c.a
			var h := y1 - y0
			var am: float = (c.a + c.b) / 2.0
			var ym := (y0 + y1) / 2.0
			if o.axis == "z":
				out.append(tbox(parent, o.t, h, length, material, [o.c, ym, am], tile))
			else:
				out.append(tbox(parent, length, h, o.t, material, [am, ym, o.c], tile))
	return out


## Sloped slab that follows the terrain (top = ground + lift). Lot terrain is planar.
func slab(S, x0: float, x1: float, z0: float, z1: float, lift: float, material, tile: float = 4.0, thick: float = 0.25):
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	var g := box_geo(w, 1, d, tile, [cx, 0, cz])
	var p: T.Attr = g.attributes["position"]
	for i in p.count():
		var lx := p.get_x(i) + cx
		var lz := p.get_z(i) + cz
		var top := p.get_y(i) > 0.0
		p.set_y(i, S.gl(lx, lz) + (lift if top else -thick))
	g.compute_vertex_normals()
	var mm := T.MeshObj.new(g, material)
	mm.position = Vector3(cx, 0, cz)
	mm.receive_shadow = true
	mm.cast_shadow = false
	S.g.add(mm)
	return mm


## Minimum / maximum local ground height over a local rectangle.
func g_range(S, x0: float, x1: float, z0: float, z1: float) -> Array:
	var v := [S.gl(x0, z0), S.gl(x1, z0), S.gl(x0, z1), S.gl(x1, z1)]
	return [v.min(), v.max()]


# ------------------------------------------------------------------ lot space

class Space extends RefCounted:
	var lot: Dictionary
	var f: Dictionary
	var g
	var d
	var c: float
	var s: float
	var L
	var P

	func w2(lx: float, lz: float) -> Dictionary:
		return {"x": f.x + lx * c + lz * s, "z": f.z - lx * s + lz * c}

	func gl(lx: float, lz: float) -> float:
		var p := w2(lx, lz)
		return L.height_at(p.x, p.z) - f.y

	## local point of a world position
	func local(x: float, z: float) -> Dictionary:
		var dx: float = x - f.x
		var dz: float = z - f.z
		return {"x": dx * c - dz * s, "z": dx * s + dz * c}

	func box(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float):
		var p := w2((x0 + x1) / 2.0, (z0 + z1) / 2.0)
		return P.addBox(p.x, p.z, absf(x1 - x0), absf(z1 - z0), f.rotY, f.y + y0, f.y + y1)

	func walk(x0: float, z0: float, x1: float, z1: float, top: float, bottom = null):
		var p := w2((x0 + x1) / 2.0, (z0 + z1) / 2.0)
		return P.addWalkBox(p.x, p.z, absf(x1 - x0), absf(z1 - z0), f.rotY, f.y + top, -50.0 if bottom == null else f.y + bottom)

	func cyl(x: float, z: float, r: float, y0: float, y1: float):
		var p := w2(x, z)
		return P.addCylinder(p.x, p.z, r, f.y + y0, f.y + y1)

	## oriented box in local space rotated by rl around its centre
	func obox(x: float, z: float, w: float, dd: float, rl: float, y0: float, y1: float):
		var p := w2(x, z)
		return P.addBox(p.x, p.z, w, dd, f.rotY + rl, f.y + y0, f.y + y1)


func space(lot: Dictionary) -> Space:
	var f: Dictionary = L.lot_frame(lot)
	var g := T.Group.new()
	g.position = Vector3(f.x, f.y, f.z)
	g.rotation.y = f.rotY
	g.name = "shopsB-" + lot.id
	var d := T.Group.new()
	d.position = g.position
	d.rotation.y = f.rotY
	d.name = "shopsB-dyn-" + lot.id
	ctx.add_static(g)
	ctx.add(d)
	spaces.append(g)
	var S := Space.new()
	S.lot = lot
	S.f = f
	S.g = g
	S.d = d
	S.c = cos(f.rotY)
	S.s = sin(f.rotY)
	S.L = L
	S.P = ctx.physics
	return S


func player_local(S: Space) -> Dictionary:
	var p: Vector3 = ctx.player.position
	var q := S.local(p.x, p.z)
	q["y"] = p.y - S.f.y
	return q


# ------------------------------------------------------------------ building parts

static func _o(o: Dictionary, k: String, d):
	return o[k] if o.get(k) != null else d


## Sliding door / window panel (group, origin = bottom centre). o: {w, h, d, frame, glass, stile, top,
## bottom, bars: [y..], vbars: [x..], kick: {h, mat}, lattice}
func panel(parent, o: Dictionary):
	var g := T.Group.new()
	parent.add(g)
	var w: float = o.w
	var h: float = o.h
	var d: float = _o(o, "d", 0.04)
	var st: float = _o(o, "stile", 0.045)
	var tr: float = _o(o, "top", 0.05)
	var br: float = _o(o, "bottom", 0.08)
	var fm = o.frame
	box(g, st, h, d, fm, [-w / 2.0 + st / 2.0, h / 2.0, 0])
	box(g, st, h, d, fm, [w / 2.0 - st / 2.0, h / 2.0, 0])
	box(g, w - 2.0 * st, tr, d, fm, [0, h - tr / 2.0, 0])
	var y0 := br
	if o.get("kick"):
		tbox(g, w - 2.0 * st, o.kick.h, d * 0.6, o.kick.mat, [0, br + o.kick.h / 2.0, 0], o.kick.tile if o.kick.get("tile") else 1.0)
		y0 = br + o.kick.h
		box(g, w - 2.0 * st, 0.03, d, fm, [0, y0, 0])
	box(g, w - 2.0 * st, br, d, fm, [0, br / 2.0, 0])
	var gh := h - tr - y0
	var gw := w - 2.0 * st
	if o.get("glass"):
		var gp = box(g, gw, gh, 0.006, o.glass, [0, y0 + gh / 2.0, 0])
		gp.cast_shadow = false
		if o.get("noOutlineGlass") != false:
			ctx.no_outline(gp)
	for by in o.get("bars", []):
		box(g, gw, 0.022, d * 0.7, fm, [0, y0 + by * gh, 0])
	for bx in o.get("vbars", []):
		box(g, 0.022, gh, d * 0.7, fm, [bx * gw / 2.0, y0 + gh / 2.0, 0])
	if o.get("lattice"):  # 格子 (vertical close bars in front)
		var n := maxi(2, int(T.js_round(gw / o.lattice)))
		for i in range(1, n):
			box(g, 0.02, gh, d * 0.8, fm, [-gw / 2.0 + gw * i / n, y0 + gh / 2.0, d * 0.2])
	return g


## Window: frame + glass + sill, opening centred at (x, y0..y1) on a wall plane z (+Z facing).
func window(parent, o: Dictionary):
	var g := T.Group.new()
	g.position = Vector3(o.x, o.y0, o.z)
	g.rotation.y = o.rotY if o.get("rotY") else 0.0
	parent.add(g)
	var w: float = o.w
	var h: float = o.h
	var fm = o.frame
	var ft: float = _o(o, "ft", 0.05)
	var fd: float = _o(o, "fd", 0.07)
	box(g, w + ft * 2.0, ft, fd, fm, [0, -ft / 2.0, 0])
	box(g, w + ft * 2.0, ft, fd, fm, [0, h + ft / 2.0, 0])
	box(g, ft, h, fd, fm, [-w / 2.0 - ft / 2.0, h / 2.0, 0])
	box(g, ft, h, fd, fm, [w / 2.0 + ft / 2.0, h / 2.0, 0])
	if o.get("sill") != false:
		box(g, w + ft * 2.0 + 0.08, 0.04, fd + 0.06, o.sillMat if o.get("sillMat") else fm, [0, -ft - 0.02, 0.04])
	var panes: int = o.panes if o.get("panes") else 2
	for i in panes:
		var pw := w / panes
		var px := -w / 2.0 + pw * (i + 0.5)
		var pz := (-0.012 if i % 2 else 0.012) - 0.01
		box(g, 0.03, h, 0.035, fm, [px + pw / 2.0 - (0.0 if i == panes - 1 else 0.015), h / 2.0, pz])
		var gp = box(g, pw - 0.03, h - 0.02, 0.006, o.glass, [px, h / 2.0, pz])
		gp.cast_shadow = false
		ctx.no_outline(gp)
	if o.get("lattice"):
		var n := int(T.js_round(w / o.lattice))
		var lm = o.latticeMat if o.get("latticeMat") else fm
		for i in range(1, n):
			box(g, 0.025, h, 0.035, lm, [-w / 2.0 + w * i / n, h / 2.0, 0.035])
		box(g, w, 0.03, 0.035, lm, [0, h * 0.5, 0.036])
	if o.get("behind"):
		var b = plane(g, w, h, o.behind, [0, h / 2.0, -_o(o, "behindD", 0.08)])
		b.cast_shadow = false
	return g


## Gable roof, ridge along X. o: {x0, x1, zf, zb (eave lines), yE (eave height), yR (ridge), zR (ridge
## z), t, mat, tile, fascia, edgeTiles}
func gable_x(parent, o: Dictionary) -> Array:
	var t: float = _o(o, "t", 0.12)
	var parts := []
	for side in [1, -1]:
		var ze: float = o.zf if side > 0 else o.zb
		var run := absf(ze - o.zR)
		var rise: float = o.yR - o.yE
		var length := Vector2(run, rise).length()
		var ang := atan2(rise, run)
		var cz: float = (ze + o.zR) / 2.0
		var cy: float = (o.yE + o.yR) / 2.0
		var mm = tbox(parent, o.x1 - o.x0, t, length + 0.02, o.mat, [(o.x0 + o.x1) / 2.0, cy + t / 2.0 * cos(ang), cz + side * 0], o.tile if o.get("tile") else 2.1, [side * ang, 0, 0])
		mm.user_data["shopsBRoof"] = true
		parts.append(mm)
		if o.get("fascia"):  # eave fascia board (鼻隠し)
			box(parent, o.x1 - o.x0, 0.16, 0.05, o.fascia, [(o.x0 + o.x1) / 2.0, o.yE - 0.02, ze + side * 0.02])
		if o.get("edgeTiles"):  # 軒瓦: rounded tile ends along the eave
			var n := int(T.js_round((o.x1 - o.x0) / 0.2625))
			var geo := half_tube(0.065, 0.1)
			for i in n:
				var x: float = o.x0 + (i + 0.5) * (o.x1 - o.x0) / n
				var e := T.MeshObj.new(geo, o.edgeTiles)
				e.position = Vector3(x, o.yE + t * 0.85, ze - side * 0.05)
				e.rotation.x = side * ang
				e.cast_shadow = true
				e.receive_shadow = true
				parent.add(e)
	return parts


## Gable end wall triangle (in the plane x = xc), spanning z0..z1 at base y0 up to apex (zA, yA).
func gable_end(parent, material, xc: float, z0: float, z1: float, y0: float, z_a: float, y_a: float, t: float = 0.15, tile: float = 2.5):
	var pts := [[z0, y0], [z1, y0], [z_a, y_a]]
	var g := Geo.extrude_shape(Geo.shape(pts), {"depth": t, "bevelEnabled": false})
	g.translate(0, 0, -t / 2.0)
	g.rotate_y(-PI / 2.0)
	var p: T.Attr = g.attributes["position"]
	var uv: T.Attr = g.attributes["uv"]
	for i in p.count():
		uv.set_xy(i, p.get_z(i) / tile, p.get_y(i) / tile)
	g.compute_vertex_normals()
	var mm := T.MeshObj.new(g, material)
	mm.position = Vector3(xc, 0, 0)
	mm.cast_shadow = true
	mm.receive_shadow = true
	parent.add(mm)
	return mm


## Ridge (棟) along X with rounded cap + simple onigawara at the ends.
func ridge_x(parent, x0: float, x1: float, y: float, z: float, material, cap_mat = null) -> void:
	var cm = cap_mat if cap_mat else material
	box(parent, x1 - x0, 0.2, 0.3, material, [(x0 + x1) / 2.0, y + 0.08, z])
	box(parent, x1 - x0 + 0.02, 0.07, 0.36, cm, [(x0 + x1) / 2.0, y + 0.2, z])
	cyl_x(parent, 0.1, x1 - x0 + 0.06, cm, [(x0 + x1) / 2.0, y + 0.25, z], 10)
	for x in [x0 - 0.05, x1 + 0.05]:
		var oni = extrude(parent, [[-0.24, 0], [0.24, 0], [0.26, 0.28], [0.12, 0.44], [0, 0.4], [-0.12, 0.44], [-0.26, 0.28]], 0.08, cm, [x, y - 0.02, z], [0, PI / 2.0, 0])
		oni.user_data["oni"] = true


## Pent roof (庇) on a +Z facing wall at zWall: from (y at wall) sloping down to the front edge.
func pent(parent, o: Dictionary):
	var depth: float = o.depth
	var drop: float = _o(o, "drop", 0.25)
	var length := Vector2(depth, drop).length()
	var ang := atan2(drop, depth)
	var t: float = _o(o, "t", 0.08)
	var cz: float = o.zWall + depth / 2.0
	var cy: float = o.y - drop / 2.0
	var mm = tbox(parent, o.x1 - o.x0, t, length, o.mat, [(o.x0 + o.x1) / 2.0, cy, cz], o.tile if o.get("tile") else 2.1, [ang, 0, 0])
	if o.get("fascia"):
		box(parent, o.x1 - o.x0 + 0.02, _o(o, "fasciaH", 0.1), 0.04, o.fascia, [(o.x0 + o.x1) / 2.0, o.y - drop - 0.03, o.zWall + depth + 0.01])
	if o.get("edgeTiles"):
		var n := int(T.js_round((o.x1 - o.x0) / 0.2625))
		var geo := half_tube(0.055, 0.09)
		for i in n:
			var x: float = o.x0 + (i + 0.5) * (o.x1 - o.x0) / n
			var e := T.MeshObj.new(geo, o.edgeTiles)
			e.position = Vector3(x, o.y - drop + t * 0.55, o.zWall + depth - 0.04)
			e.rotation.x = ang
			e.cast_shadow = true
			e.receive_shadow = true
			parent.add(e)
	if o.get("brackets"):  # 腕木
		var bm = o.bracketMat if o.get("bracketMat") else (o.fascia if o.get("fascia") else o.mat)
		for x in o.brackets:
			box(parent, 0.07, 0.09, depth * 0.85, bm, [x, o.y - drop * 0.5 - 0.13, o.zWall + depth * 0.42], [ang, 0, 0])
			box(parent, 0.06, 0.34, 0.06, bm, [x, o.y - 0.36, o.zWall + 0.04])
	return mm


## Half-round gutter along X + downpipe.
func gutter_x(parent, x0: float, x1: float, y: float, z: float, material):
	var g := Geo.cylinder(0.06, 0.06, 1, 8, 1, true, PI, PI)
	var mm := T.MeshObj.new(g, material)
	mm.scale = Vector3(1, x1 - x0, 1)
	mm.rotation = Vector3(0, 0, PI / 2.0)
	mm.position = Vector3((x0 + x1) / 2.0, y, z)
	mm.material = material
	mm.cast_shadow = true
	parent.add(mm)
	box(parent, x1 - x0, 0.02, 0.012, material, [(x0 + x1) / 2.0, y + 0.05, z + 0.058])
	return mm


## Downpipe with wall brackets; dir = unit [dx, dz] from the pipe toward its wall.
func downpipe(parent, x: float, z: float, y_top: float, y_bot: float, material, off: float = 0.1, dir = [0, -1]) -> void:
	cyl(parent, 0.035, y_top - y_bot, material, [x, (y_top + y_bot) / 2.0, z], 8)
	var y := y_bot + 0.6
	while y < y_top - 0.2:
		box(parent, off if dir[0] else 0.06, 0.03, 0.06 if dir[0] else off, material, [x + dir[0] * off / 2.0, y, z + dir[1] * off / 2.0])
		y += 1.4
	cyl(parent, 0.045, 0.14, material, [x, y_bot + 0.07, z], 8)
	cyl(parent, 0.045, 0.1, material, [x + dir[0] * 0.03, y_bot + 0.05, z + dir[1] * 0.03], 8, [dir[1] * 0.9, 0, -dir[0] * 0.9])


## Pipe along a polyline of [x, y, z] points (elbows are small spheres).
func pipe_run(parent, pts: Array, r: float, material) -> void:
	for i in pts.size() - 1:
		var A := v3(pts[i])
		var Bv := v3(pts[i + 1])
		var d := Bv - A
		var length := d.length()
		var mm := T.MeshObj.new(Geo.g_cyl(ctx.cache, 8), material)
		mm.scale = Vector3(r * 2.0, length, r * 2.0)
		mm.position = A + d * 0.5
		mm.set_quaternion(T.quat_from_unit_vectors(Vector3(0, 1, 0), d.normalized()))
		mm.cast_shadow = true
		mm.receive_shadow = true
		parent.add(mm)
		if i > 0:
			sph(parent, r * 1.15, material, pts[i], 8)


## AC outdoor unit (室外機) standing at local (x, y, z), facing +Z by rotY.
func ac_unit(parent, x: float, y: float, z: float, rot_y: float = 0.0, with_pipe := true):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	parent.add(g)
	var body = m("#e3e1da")
	var dark = m("#8f949a")
	rbox(g, 0.78, 0.56, 0.28, 0.06, body, [0, 0.33, 0])
	cyl(g, 0.2, 0.02, dark, [-0.1, 0.34, 0.14], 16, [PI / 2.0, 0, 0])
	for i in range(-2, 3):
		box(g, 0.4, 0.012, 0.012, m("#b9bcbf"), [-0.1, 0.34 + i * 0.07, 0.155])
	box(g, 0.14, 0.4, 0.02, m("#cfcdc6"), [0.28, 0.33, 0.145])
	for sx in [-0.3, 0.3]:
		box(g, 0.06, 0.05, 0.3, dark, [sx, 0.025, 0])
	if with_pipe:
		cyl(g, 0.035, 0.5, m("#e9e3d2"), [0.33, 0.8, -0.1], 8)
	return g


## Electric meter box on a +Z wall.
func meter(parent, x: float, y: float, z: float) -> void:
	rbox(parent, 0.2, 0.28, 0.1, 0.02, m("#d9d7d0"), [x, y, z + 0.05])
	box(parent, 0.13, 0.1, 0.012, mat.emissive("#d7e2e6", 0.9), [x, y + 0.04, z + 0.105])
	cyl(parent, 0.012, 0.6, m("#5c5a60"), [x + 0.06, y + 0.44, z + 0.04], 6)


func gas_meter(parent, x: float, y: float, z: float) -> void:
	var mm = m("#cfd2cc")
	rbox(parent, 0.22, 0.26, 0.16, 0.03, mm, [x, y, z + 0.08])
	cyl(parent, 0.018, 0.5, m("#c9a44a"), [x - 0.06, y - 0.36, z + 0.06], 6)
	box(parent, 0.1, 0.05, 0.01, m("#e4e0d4"), [x, y + 0.05, z + 0.162])


## Potted plant: ceramic pot + leafy clump.
func plant(parent, x: float, y: float, z: float, o: Dictionary = {}) -> void:
	var r: float = _o(o, "r", 0.16)
	var h: float = _o(o, "h", 0.24)
	var pot: String = o.pot if o.get("pot") else "#a8674b"
	cyl(parent, r, h, m(pot), [x, y + h / 2.0, z], 12, null, r * 0.78)
	cyl(parent, r * 1.04, 0.035, m(pot), [x, y + h, z], 12)
	var rr = ctx.rng("plant" + ("%.2f" % x) + ("%.2f" % z))
	var tall: float = _o(o, "tall", 1.0)
	# smooth cel shrub (lib/foliage.js) instead of faceted sphere clumps
	var sh = Foliage.make_shrub(ctx, {"r": r * 1.12, "h": r * (1.25 + 0.55 * tall), "seed": 1 + floori(rr.f() * 97), "lumps": 0.24, "freq": 3.2,
		"colors": {"top": o.leaf2 if o.get("leaf2") else "#a9cf7c", "mid": o.leaf if o.get("leaf") else "#6fa35c", "base": "#4a7a5a"}})
	sh.position = Vector3(x, y + h - 0.03, z)
	sh.rotation.y = rr.f() * 6.28
	parent.add(sh)
	var sh_h := r * (1.25 + 0.55 * tall)
	if o.get("flowers"):
		for i in 9:
			var a: float = rr.f() * 6.28
			var t: float = 0.35 + rr.f() * 0.5
			var d := r * 1.05 * sqrt(1.0 - t * t)
			sph(parent, 0.026, m(o.flowers), [x + cos(a) * d, y + h - 0.03 + sh_h * (0.5 + 0.5 * t), z + sin(a) * d], 6)


# ------------------------------------------------------------------ cloth: nobori & noren (CPU-animated geometry keeps outlines)

## Nobori flag. Pole + top bar static; banner animated. o: {x, z, rot, tex, w, h, poleH, base}
func nobori(S: Space, o: Dictionary) -> Dictionary:
	var w: float = _o(o, "w", 0.45)
	var h: float = _o(o, "h", 1.65)
	var ph: float = _o(o, "poleH", 2.55)
	var y0 := S.gl(o.x, o.z)
	var gs := T.Group.new()
	gs.position = Vector3(o.x, y0, o.z)
	gs.rotation.y = o.rot if o.get("rot") else 0.0
	S.g.add(gs)
	var pole = m("#e8e6e0")
	var base_m = m(o.baseColor if o.get("baseColor") else "#6d747c")
	cyl(gs, 0.016, ph, pole, [0, ph / 2.0, 0], 8)
	box(gs, w + 0.03, 0.016, 0.016, pole, [(-1.0 if o.get("flip") else 1.0) * (w / 2.0 + 0.01), ph - 0.05, 0])
	# water-tank base (注水式スタンド)
	cyl(gs, 0.2, 0.12, base_m, [0, 0.06, 0], 14, null, 0.22)
	cyl(gs, 0.08, 0.12, base_m, [0, 0.18, 0], 10)
	var gd := T.Group.new()
	gd.position = gs.position
	gd.rotation.y = gs.rotation.y
	S.d.add(gd)
	var nx := 5
	var ny := 14
	var sgn := -1.0 if o.get("flip") else 1.0
	var geo := Geo.plane(w, h, nx, ny)
	geo.translate(sgn * (w / 2.0 + 0.018), ph - 0.07 - h / 2.0, 0)
	var base: PackedFloat32Array = geo.attributes["position"].array.duplicate()
	var mm := T.MeshObj.new(geo, toon_memo("#ffffff", {"map": o.tex, "side": "double", "paint": 0.02}))
	mm.cast_shadow = true
	mm.receive_shadow = true
	mm.frustum_culled = false
	gd.add(mm)
	# loops (チチ) on the pole
	for i in 4:
		cyl(gs, 0.024, 0.03, m("#f0ece2"), [0, ph - 0.12 - i * (h - 0.1) / 3.0, 0], 8)
	var ph0 := fmod(o.x * 1.7 + o.z * 0.9, 6.28)
	var p: T.Attr = geo.attributes["position"]
	cloth_updaters.append(func(t, gust, _dt):
		var amp: float = 0.035 + 0.05 * gust
		for i in p.count():
			var bx: float = base[i * 3]
			var by: float = base[i * 3 + 1]
			var u: float = (sgn * bx - 0.018) / w
			var vt: float = (by - (ph - 0.07 - h)) / h  # u 0 at pole, vt 1 at top
			var free := u * (0.25 + 0.75 * (1.0 - vt))
			var wave := sin(5.2 * u + 3.0 * (1.0 - vt) - 4.8 * t + ph0) + 0.45 * sin(9.0 * u - 7.4 * t + ph0 * 2.1)
			var dz: float = amp * free * wave + 0.07 * gust * u * (1.0 - vt * 0.6) * sin(0.8 * t + ph0)
			p.set_xyz(i, bx - sgn * absf(dz) * 0.3 * u, by + absf(dz) * 0.15 * (1.0 - vt) * u, dz)
		geo.compute_vertex_normals())
	S.cyl(o.x, o.z, 0.2, y0, y0 + ph)
	return {"gs": gs, "gd": gd, "mesh": mm}


## Noren (暖簾): n strips hung from a rod at (x, y, z) (+Z faces the street); strips part when the
## player walks through.
func noren(S: Space, o: Dictionary):
	var n: int = _o(o, "n", 3)
	var w: float = o.w
	var h: float = o.h
	var gap: float = _o(o, "gap", 0.014)
	var sw := (w - gap * (n - 1)) / n
	# rod + brackets (static)
	cyl_x(S.g, 0.018, w + 0.16, m(o.rodColor if o.get("rodColor") else "#6b4a35"), [o.x, o.y + 0.02, o.z], 8)
	var gd := T.Group.new()
	gd.position = Vector3(o.x, o.y, o.z)
	S.d.add(gd)
	var mtl = toon_memo("#ffffff", {"map": o.tex, "side": "double", "paint": 0.02})
	var strips := []
	for i in n:
		var geo := Geo.plane(sw, h, 2, 8)
		geo.translate(0, -h / 2.0, 0)
		var uv: T.Attr = geo.attributes["uv"]
		for j in uv.count():
			uv.set_x(j, (i * (sw + gap) + uv.get_x(j) * sw) / w)
		var mm := T.MeshObj.new(geo, mtl)
		var xs := -w / 2.0 + sw / 2.0 + i * (sw + gap)
		mm.position = Vector3(xs, 0, 0)
		mm.cast_shadow = true
		mm.receive_shadow = true
		mm.frustum_culled = false
		gd.add(mm)
		strips.append({"m": mm, "geo": geo, "base": geo.attributes["position"].array.duplicate(), "xs": xs, "open": 0.0})
	cloth_updaters.append(func(t, gust, dt):
		var pl := player_local(S)
		for i in n:
			var s = strips[i]
			var p: T.Attr = s.geo.attributes["position"]
			var dx: float = absf(pl.x - (o.x + s.xs)) - sw / 2.0
			var dzp: float = pl.z - o.z
			var near: float = (1.0 - smooth(0.05, 0.45, dx)) * (1.0 - smooth(0.15, 0.75, absf(dzp))) * (1.0 if pl.y > o.y - h - 1.9 and pl.y < o.y + 0.3 else 0.0)
			var target := near * (-1.0 if dzp > 0 else 1.0)
			if not dt:
				s.open = target
			else:
				s.open += (target - s.open) * minf(1.0, dt * 6.0)
			var sway: float = (0.03 + 0.05 * gust) * sin(1.3 * t + i * 0.9 + o.x) + 0.02 * sin(3.1 * t + i * 1.7)
			var ang: float = sway + s.open * 1.05
			var ca := cos(ang)
			var sa := sin(ang)
			for j in p.count():
				var bx: float = s.base[j * 3]
				var by: float = s.base[j * 3 + 1]
				var dd := -by  # depth below rod
				var rip: float = 0.012 * sin(6.0 * dd - 3.3 * t + i) * dd
				p.set_xyz(j, bx + s.open * 0.12 * dd * T.sign(bx + 0.001) * 0.4, -dd * ca, dd * sa + rip)
			s.geo.compute_vertex_normals())
	return gd


## Paper lantern (提灯) hanging from a hook at (x, y, z); swings gently. tex drawn centred at u = 0.5.
func lantern(S: Space, o: Dictionary):
	var r: float = _o(o, "r", 0.2)
	var h: float = _o(o, "h", 0.5)
	var gd := T.Group.new()
	gd.position = Vector3(o.x, o.y, o.z)
	S.d.add(gd)
	var pts := []
	for i in 11:
		var v := i / 10.0
		var y := -h + v * h
		var rr := r * (0.62 + 0.38 * sin(PI * v))
		pts.append([rr, y - 0.06])
	lathe(gd, pts, memo("emi", "#ffffff", {"map": o.tex}, _o(o, "glow", 1.0)), [0, 0, 0], 18, PI)
	var cap = m("#3f3a3c")
	cyl(gd, r * 0.66, 0.05, cap, [0, -0.06 + 0.02, 0], 14)
	cyl(gd, r * 0.66, 0.05, cap, [0, -h - 0.06 - 0.02, 0], 14)
	cyl(gd, 0.008, 0.08, cap, [0, 0.0, 0], 6)
	if o.get("tassel"):
		cyl(gd, 0.03, 0.12, m(o.tassel), [0, -h - 0.16, 0], 6)
	merge_group(gd)
	var ph0: float = o.x * 2.1 + o.z
	cloth_updaters.append(func(t, gust, _dt):
		gd.rotation.z = (0.03 + 0.04 * gust) * sin(1.1 * t + ph0)
		gd.rotation.x = 0.025 * sin(0.83 * t + ph0 * 1.3))
	return gd


## Rising steam / smoke puffs (billboards, pure function of t).
func steam(S: Space, o: Dictionary) -> Array:
	var n: int = _o(o, "n", 6)
	var ptex = puff_tex()
	var levels := []
	for a in [0.08, 0.16, 0.26, 0.36]:
		levels.append(memo("emi", o.color if o.get("color") else "#f3f0ea", {"map": ptex, "transparent": true, "depthWrite": false, "opacity": a * _o(o, "alpha", 1.0)}, _o(o, "bright", 0.95)))
	var puffs := []
	for i in n:
		var mm := T.MeshObj.new(Geo.g_plane(ctx.cache), levels[0])
		mm.render_order = 3
		mm.frustum_culled = false
		ctx.no_outline(mm)
		S.d.add(mm)
		puffs.append(mm)
	cloth_updaters.append(func(t, _gust, _dt):
		var cam = ctx.get("camera")
		var q := Quaternion.IDENTITY
		if cam != null:
			q = cam.quaternion()
		var pq: Quaternion = Inst.world_of(S.d).basis.get_rotation_quaternion().inverse()
		for i in n:
			var life: float = _o(o, "life", 3.2)
			var a: float = fposmod(fposmod(t / life + float(i) / n, 1.0) + 1.0, 1.0)
			var mm = puffs[i]
			var y: float = o.y + a * _o(o, "rise", 1.0)
			var drift: Array = o.drift if o.get("drift") else [0.25, 0]
			mm.position = Vector3(o.x + drift[0] * a + 0.05 * sin(t * 1.3 + i * 2), y, o.z + drift[1] * a + 0.04 * cos(t + i))
			var s: float = _o(o, "size", 0.25) * (0.5 + a * 1.4)
			mm.scale = Vector3(s, s, s)
			var alpha := sin(PI * minf(1.0, a * 1.15))
			mm.material = levels[maxi(0, mini(3, floori(alpha * 4)))]
			mm.set_quaternion(pq * q))
	return puffs


func puff_tex():
	return draw(128, 128, "sb-puff", false)


## Merge a (dynamic) group's child meshes by material + layer + shadow flags into one mesh each, in
## group space; dynamic objects are never batched, so this keeps their draw calls low.
func merge_group(grp):
	var inv := Inst.world_of(grp).affine_inverse()
	var by := {}
	var order := []
	grp.traverse(func(o):
		if not o.is_mesh or o == grp or o.material is Array or not o.geometry.indexed:
			return
		var k := "%d|%d|%s%s" % [o.material.get_instance_id(), o.layer, str(o.cast_shadow), str(o.receive_shadow)]
		if not by.has(k):
			by[k] = []
			order.append(k)
		by[k].append(o))
	for k in order:
		var list: Array = by[k]
		if list.size() < 2:
			continue
		var geos := []
		for o in list:
			var gg: T.Geometry = o.geometry.clone()
			for nm in gg.attributes.keys():
				if nm != "position" and nm != "normal" and nm != "uv":
					gg.delete_attribute(nm)
			if not gg.has_attribute("uv"):
				var uvs := PackedFloat32Array()
				uvs.resize(gg.vertex_count() * 2)
				gg.set_attribute("uv", T.Attr.new(uvs, 2))
			gg.apply_matrix4(inv * Inst.world_of(o))
			geos.append(gg)
		var mg = Geo.merge_geometries(geos, false)
		if mg == null:
			continue
		var s = list[0]
		var mesh := T.MeshObj.new(mg, s.material)
		mesh.cast_shadow = s.cast_shadow
		mesh.receive_shadow = s.receive_shadow
		mesh.layer = s.layer
		for o in list:
			o.parent().remove(o)
		grp.add(mesh)
	return grp


## Automatic sliding door (panel group slides along local X of its parent when the player is near).
func auto_slide(S: Space, pnl, o: Dictionary) -> void:
	merge_group(pnl)
	var x0: float = pnl.position.x
	var st := [0.0]
	ctx.on_update(func(dt, _t):
		var pl := player_local(S)
		var d := Vector2(pl.x - o.cx, pl.z - o.cz).length()
		var target: float = 1.0 if d < _o(o, "r", 2.6) else _o(o, "rest", 0.0)
		if not dt:
			st[0] = target
		else:
			st[0] += (target - st[0]) * minf(1.0, dt * 3.2)
		var e: float = st[0] * st[0] * (3.0 - 2.0 * st[0])
		pnl.position.x = x0 + e * o.dx)


# ------------------------------------------------------------------ small shop props

## Plastic beer/drink crate with bottle tops.
func crate(parent, x: float, y: float, z: float, color, rot_y: float = 0.0, bottles := true, bottle_color = "#8a5a3a"):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	parent.add(g)
	var cm = mt(color, crate_tex(), {})
	box(g, 0.46, 0.3, 0.34, cm, [0, 0.15, 0])
	box(g, 0.42, 0.02, 0.3, m("#4a4450"), [0, 0.295, 0])
	if bottles:
		var bm = m(bottle_color)
		for i in 4:
			for j in 3:
				cyl(g, 0.028, 0.05, bm, [-0.165 + i * 0.11, 0.33, -0.1 + j * 0.1], 6)
	return g


func crate_tex():
	return draw(128, 128, "sb-crate", false)


## Wooden bench.
func bench(parent, x: float, y: float, z: float, length: float, rot_y: float = 0.0, o: Dictionary = {}):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	parent.add(g)
	var wm = mt(o.color if o.get("color") else C.woodLight, TX.grain)
	var dm = m(o.leg if o.get("leg") else C.woodMid)
	var sh: float = _o(o, "seatH", 0.42)
	var d: float = _o(o, "d", 0.38)
	tbox(g, length, 0.045, d, wm, [0, sh - 0.022, 0], 1)
	for sx in [-length / 2.0 + 0.12, length / 2.0 - 0.12]:
		box(g, 0.06, sh - 0.045, 0.06, dm, [sx, (sh - 0.045) / 2.0, -d / 2.0 + 0.06])
		box(g, 0.06, sh - 0.045, 0.06, dm, [sx, (sh - 0.045) / 2.0, d / 2.0 - 0.06])
		box(g, 0.05, 0.05, d - 0.1, dm, [sx, 0.12, 0])
	box(g, length - 0.2, 0.05, 0.04, dm, [0, sh - 0.09, -d / 2.0 + 0.05])
	if o.get("back"):
		for sx in [-length / 2.0 + 0.12, length / 2.0 - 0.12]:
			box(g, 0.05, 0.42, 0.05, dm, [sx, sh + 0.2, -d / 2.0 + 0.03])
		tbox(g, length, 0.12, 0.03, wm, [0, sh + 0.32, -d / 2.0 + 0.03], 1)
	return g


## Price tag / small card texture (cached by text).
func card(lines: Array, o: Dictionary = {}):
	var w: int = o.w if o.get("w") else 256
	var h: int = o.h if o.get("h") else 128
	return draw(w, h, "sb-card|" + "/".join(lines) + "|" + str(o), false)


## Standard stickers shared by the shops.
func hours_sticker(lines: Array, _accent = "#d9718f"):
	return draw(256, 192, "sb-hours|" + "/".join(lines), false)


func cashless():
	return draw(512, 160, "sb-cashless", false)


## Hand-written 営業中 wooden plate.
func eigyo_tex(text := "営業中", sub := ""):
	return draw(256, 128, "sb-eigyo|" + text + sub, false)


func eigyo_plate(parent, x: float, y: float, z: float, rot_y: float = 0.0, text := "営業中", sub := "", scale: float = 1.0):
	# reversible plate: 営業中 on the street side, 準備中 on the back (never mirrored text)
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	parent.add(g)
	var mm = plane(g, 0.3 * scale, 0.15 * scale, toon_memo("#ffffff", {"map": eigyo_tex(text, sub)}), [0, 0, 0.0015])
	plane(g, 0.3 * scale, 0.15 * scale, toon_memo("#ffffff", {"map": eigyo_tex("準備中", "")}), [0, 0, -0.0015], PI)
	return mm


## Clipped hedge strip for window boxes (lib/foliage.js).
func hedge(parent, x: float, y: float, z: float, length: float, h: float, d: float, seed: int = 3):
	var mm = Foliage.make_hedge(ctx, {"length": length, "h": h, "d": d, "seed": seed, "lumps": 0.16, "square": 2.2})
	mm.position = Vector3(x, y, z)
	parent.add(mm)
	return mm


## Soft pool of warm lamplight on a floor/wall (transparent emissive gradient, no outline).
func light_pool(parent, x: float, y: float, z: float, w: float, h: float, o: Dictionary = {}):
	var t = draw(128, 128, "sb-pool", false)
	var mm = plane(parent, w, h, memo("emi", o.color if o.get("color") else "#ffd9a0", {"map": t, "transparent": true, "depthWrite": false, "opacity": _o(o, "opacity", 0.28)}, _o(o, "intensity", 1.0)),
		[x, y, z], o.rotY if o.get("rotY") else 0.0, _o(o, "rotX", -PI / 2.0))
	mm.receive_shadow = false
	mm.render_order = 1
	ctx.no_outline(mm)
	return mm


## Shoji screen material (paper + wooden grid) seen behind upper-floor windows.
func shoji():
	return toon_memo("#ffffff", {"map": draw(256, 256, "sb-shoji", false), "emissive": "#6b5a44", "emissiveIntensity": 0.25})


## Curtain (light fabric with folds) behind a window.
func curtain(color = "#e8dccb"):
	return toon_memo(color, {"map": draw(256, 128, "sb-curtain", false), "emissive": "#5a4a3a", "emissiveIntensity": 0.15})


## Vertical projecting lightbox sign (袖看板), perpendicular to the facade. texA faces +X, texB faces -X.
func sode_sign(parent, o: Dictionary):
	var g := T.Group.new()
	g.position = Vector3(o.x, o.y, o.z)
	parent.add(g)
	var w: float = _o(o, "w", 0.5)
	var h: float = _o(o, "h", 1.6)
	var t: float = _o(o, "t", 0.14)
	var frame = m(o.frame if o.get("frame") else "#e8e4da")
	rbox_r(g, t, h + 0.06, w + 0.06, 0.02, frame, [0, h / 2.0, w / 2.0 + 0.2])
	for s in [1, -1]:
		plane(g, w, h, memo("emi", "#ffffff", {"map": o.tex}, _o(o, "glow", 0.95)), [s * (t / 2.0 + 0.004), h / 2.0, w / 2.0 + 0.2], s * PI / 2.0)
	for yy in [0.25, h - 0.25]:
		box(g, 0.04, 0.04, 0.24, m("#8d949b"), [0, yy, 0.1])
	return g
