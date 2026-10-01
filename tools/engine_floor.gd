# Engine floor for the station parity diff (residual ladder rung 0): the calibration tiles of
# tools/oracle/calib_scene.json rendered by the port (realize.gd's palette/MToon path, the
# station's own sky, fog, sun and ambient) and compared with the same tiles rendered by the original
# (tools/oracle/calib.mjs, the original's own modules), one tile per content class:
#   a  unlit palette triangles with sharp edges   b  the toon ramp under the station's sun and
#   ambient (with and without the hand-paint noise)   c  sun shadows   d  sky and fog at distance
#   e  each post stage of the original alone, all off and all on; the port's composite
#      (core/composite.gd) runs the matching stages where it can (see _set_post), else stays off
#   chart  the 24-patch colour chart (tools/calib/chart24.json) unlit, toon lit and in shadow, and
#      as a canvas texture (the original's; the port's baked and runtime Slug): tools/chart_calib.gd
# Every tile but the e tiles has all post stages off in both engines.
# Measures, all in the parity's units (MAD 0..255 over every pixel and RGB channel, full resolution):
#   d(three, godot) per tile; for tile a also split into edge pixels (where either render is not
#   flat over its 3x3 neighbourhood) and interior pixels, and again with the port at MSAA 4x.
# With --station it also renders the station's Hammersley views with a class pass (sky; geometry
# past 150 m; unlit; toon in the sun's shadow; lit toon; edges where class or depth jumps) and
# estimates each view's floor from its class mix and the per-class floors, against its residual.
#   node tools/oracle/calib.mjs --out <dir>/three            (the original's tiles)
#   node tools/oracle/calib_svg.mjs --out <dir>/svg          (the chart's canvas texture as SVG)
#   godot --path . --resolution 1920x1080 --script tools/engine_floor.gd -- --three=<dir>/three --out=<dir>
#       --chart-svg=<dir>/svg/calib-chart24.svg [--q=high] [--sheet-only]
#   godot --path . --resolution 1920x1080 --script tools/engine_floor.gd -- --station --floors=<dir>/engine_floor.json
#       --original=<prefix> --views=<dir> [--hammersley=8@-1,-11.4]
# <prefix>_<tile id>.png are calib.mjs' renders; <dir>/godot_<tile id>.png are written here, with
# engine_floor.json (the measures) and engine-floor-contact-sheet.png (three | godot | diff, worst
# first; also copied to the desktop as engine-floor-NN by Sheet.publish), then chart_calib.json and
# chart-calib-sheet.png (chart-calib-NN). --chart-svg loads the SVG into a slug.elf of this run's own
# for the textured chart tiles (no cache); --sheet-only re-measures the renders already in <dir>.
extends SceneTree

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Materials = preload("res://addons/sakuragaoka_station/core/materials.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Sheet = preload("res://tools/sheet.gd")
const Chart = preload("res://tools/chart_calib.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const SCENE := "res://tools/oracle/calib_scene.json"
const FAR_M := 150.0
const EYE := 1.52

var _a := {}
var _st: Node3D
var _cam: Camera3D
var _fx = null
var _fx_on := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var eq := a.find("=")
			_a[a.substr(2, eq - 2) if eq > 0 else a.substr(2)] = a.substr(eq + 1) if eq > 0 else "1"
	(_station if _a.has("station") else _tiles).call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


## A free camera "x,y,z,yaw,pitch" as realize_check and shot.mjs place it (yaw 0 north, Euler YXZ).
func _place(c: Array) -> void:
	_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0), EULER_ORDER_YXZ), Vector3(c[0], c[1], c[2]))


func _make_station(modules: PackedStringArray) -> void:
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	_st.modules = modules
	_st.quality = _a.get("q", "high")
	get_root().add_child(_st)
	await _st.built
	_make_cam()
	# the composite among the compositor's effects (core/fog.gd's exact fog runs first, as scene fog)
	var we = _st.get_node_or_null("SkyAndFog")
	if we != null and we.compositor != null:
		for e in we.compositor.compositor_effects:
			if e != null and "outline" in e and "grade" in e:
				_fx = e
	if _fx != null:
		for k in PORT_STAGES:
			if k in _fx:
				_fx_on[k] = _fx.get(k)


func _make_cam() -> void:
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()


## Each chart tile's patch read rects, per chart placement (its "charts", then its "textured" quad).
func _chart_rects(scene: Dictionary, chart: Dictionary) -> Dictionary:
	var rects := {}
	for t in scene.tiles:
		if t.has("charts") or t.has("textured"):
			_place(t.cam)
			var rs := []
			for c in t.get("charts", []):
				rs.append(Chart.patch_rects(_cam, c, chart))
			if t.has("textured"):
				rs.append(Chart.patch_rects(_cam, t.textured, chart))
			rects[t.id] = rs
	return rects


## Frees what this run made in the sandbox (the chart's slug.elf, the kernels), then the station's.
func _teardown() -> void:
	if Guest.override != null:
		SandboxUtil.release(Guest.override.sandbox)
		Guest.override = null
	Kernels.shutdown()
	Guest.shutdown()


# ------------------------------------------------------------------------------------- tiles

## Each port composite switch and the original stage it follows; the port's grade block holds grading, leak and
## vignette together, so it runs only when all three are on. The port has no dither.
const PORT_STAGES := {"outline": "outline", "bloom": "bloom", "glow": "bloom", "grade": "block", "vignette": "block"}


## Sets the port's composite for a tile's post stages; stages it cannot run stay off, so the tile measures their
## whole contribution. Returns what the port ran, for the labels.
func _set_post(p: Dictionary) -> String:
	if _fx == null:
		return "port: no composite"
	var block: bool = bool(p.grade) and bool(p.leak) and bool(p.vignette)
	for k in _fx_on:
		var on: bool = block if PORT_STAGES[k] == "block" else bool(p[PORT_STAGES[k]])
		_fx.set(k, _fx_on[k] if on else 0.0)
	return _port_label(p, _fx_on.has("bloom"))


## The port's switches as a key for reusing a render, [] without a composite.
func _post_key() -> Array:
	var out := []
	for k in _fx_on:
		out.append(_fx.get(k))
	return out


static func _port_label(p: Dictionary, has_bloom: bool = true) -> String:
	var block: bool = bool(p.grade) and bool(p.leak) and bool(p.vignette)
	var on := PackedStringArray()
	if p.outline:
		on.append("outline")
	if p.bloom and has_bloom:
		on.append("bloom")
	if block:
		on.append("grade block")
	var s := "port composite: " + (" + ".join(on) if not on.is_empty() else "off")
	var not_run := PackedStringArray()
	if p.dither:
		not_run.append("dither (not in the port)")
	if p.bloom and not has_bloom:
		not_run.append("bloom (not in the port)")
	if not block:
		for k in ["grade", "leak", "vignette"]:
			if p[k]:
				not_run.append(k + " (alone: not separable in the port)")
	return s + ("; not run: " + ", ".join(not_run) if not not_run.is_empty() else "")


static func _geometry(o: Dictionary) -> T.Geometry:
	var a: Array = o.args
	match o.geo:
		"plane":
			return Geo.plane(a[0], a[1])
		"sphere":
			return Geo.sphere(a[0], int(a[1]), int(a[2]))
		"cylinder":
			return Geo.cylinder(a[0], a[1], a[2], int(a[3]))
		"box":
			return Geo.box(a[0], a[1], a[2])
	push_error("engine_floor: unknown geometry " + str(o.geo))
	return null


## calib_world.js' grid: one mesh per colour of flat unlit triangles facing +Z.
static func _grid(mats, g: Dictionary) -> Array:
	var by := {}
	for c in int(g.cols):
		for r in int(g.rows):
			var x: float = g.x0 + c * g.cell
			var y: float = g.y0 + r * g.cell
			var p00 := Vector2(x, y)
			var p10 := Vector2(x + g.cell, y)
			var p11 := Vector2(x + g.cell, y + g.cell)
			var p01 := Vector2(x, y + g.cell)
			var tris := [[p00, p10, p11], [p00, p11, p01]] if (c + r) % 2 == 0 else [[p00, p10, p01], [p10, p11, p01]]
			for k in 2:
				var col: String = g.colors[(c * 7 + r * 3 + k) % g.colors.size()]
				if not by.has(col):
					by[col] = PackedFloat32Array()
				for p in tris[k]:
					by[col].append_array(PackedFloat32Array([p.x, p.y, g.z]))
	var out := []
	for col in by:
		var pos: PackedFloat32Array = by[col]
		var nor := PackedFloat32Array()
		nor.resize(pos.size())
		for i in range(2, nor.size(), 3):
			nor[i] = 1.0
		var geo := T.Geometry.new()
		geo.set_attribute("position", T.Attr.new(pos, 3))
		geo.set_attribute("normal", T.Attr.new(nor, 3))
		var o := T.MeshObj.new(geo, mats.emissive(col, 1.0))
		o.name = "calib-grid-" + col
		out.append(o)
	return out


func _tiles() -> void:
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	var out: String = _a.get("out", "user://engine_floor")
	DirAccess.make_dir_recursive_absolute(out)
	if _a.has("sheet-only"):
		# the port's renders from an earlier run, for re-measuring and a new sheet
		var have := {}
		var labels := {}
		for t in scene.tiles:
			if FileAccess.file_exists(out.path_join("godot_%s.png" % t.id)):
				have[t.id] = Image.load_from_file(out.path_join("godot_%s.png" % t.id))
			labels[t.id] = _port_label(t.post)
		await _compare(scene, have, Image.load_from_file(out.path_join("godot_%s-msaa4.png" % scene.tiles[0].id)), out,
				Image.load_from_file(out.path_join("godot_%s-msaa-off.png" % scene.tiles[0].id)), labels)
		_make_cam()
		var ch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + str(scene.get("chart", "tools/calib/chart24.json"))))
		await _frames(2)
		await _chart_report(scene, ch, have, _chart_rects(scene, ch), out)
		quit()
		return
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + str(scene.get("chart", "tools/calib/chart24.json"))))
	await _make_station(PackedStringArray())
	if _texture_tiles(scene) and not await _chart_guest():
		_teardown()
		quit(1)
		return
	var mats = Materials.new()
	var objs := []
	for t in scene.tiles:
		if t.has("engines") and not t.engines.has("godot"):
			continue
		for c in t.get("charts", []):
			objs.append(_chart(mats, chart, c))
		if t.has("textured"):
			objs.append(_textured(mats, t.textured))
		if t.has("grid"):
			objs.append_array(_grid(mats, t.grid))
		for o in t.objects:
			var m = mats.emissive(o.mat.color, o.mat.get("intensity", 1.0)) if o.mat.kind == "emissive" else mats.toon(o.mat.color, {"paint": o.mat.get("paint", 0.05)})
			var mo := T.MeshObj.new(_geometry(o), m)
			mo.position = Vector3(o.pos[0], o.pos[1], o.pos[2])
			mo.rotation = Vector3(deg_to_rad(o.rot[0]), deg_to_rad(o.rot[1]), deg_to_rad(o.rot[2]))
			mo.name = "calib-%s-%s" % [t.id, o.geo]
			mo.update_matrix_world()
			objs.append(mo)
	for o in objs:
		o.update_matrix_world()
	var holder := Node3D.new()
	holder.name = "calib"
	_st.add_child(holder)
	var r = Realize.new()
	r.realize_part(objs, holder)
	await process_frame
	await process_frame
	r.finish()
	var sun: DirectionalLight3D = _st.get_node("Sun")
	var renders := {}
	var rects := _chart_rects(scene, chart)
	var ports := {}
	var drawn := {}
	for t in scene.tiles:
		_place(t.cam)
		if t.has("engines") and not t.engines.has("godot"):
			continue
		ports[t.id] = _set_post(t.post)
		# a tile the port draws exactly as an earlier one (same camera, shadows and composite) reuses it
		var same := JSON.stringify([t.cam, t.shadows, _post_key() if _fx != null else []])
		if drawn.has(same):
			renders[t.id] = renders[drawn[same]]
			renders[t.id].save_png(out.path_join("godot_%s.png" % t.id))
			print("engine_floor: rendered %s (as %s)" % [t.id, drawn[same]])
			continue
		sun.shadow_enabled = bool(t.shadows)
		await _frames(12)
		var img := get_root().get_texture().get_image()
		img.save_png(out.path_join("godot_%s.png" % t.id))
		renders[t.id] = img
		drawn[same] = t.id
		print("engine_floor: rendered %s (%s)" % [t.id, ports[t.id]])
	# tile a again at both AA settings, whatever the quality level runs: how much of its floor is AA
	var ta: Dictionary = scene.tiles[0]
	var as_run := get_root().msaa_3d
	sun.shadow_enabled = bool(ta.shadows)
	_set_post(ta.post)
	_place(ta.cam)
	var alt := {}
	for m in [[Viewport.MSAA_DISABLED, "msaa-off"], [Viewport.MSAA_4X, "msaa4"]]:
		get_root().msaa_3d = m[0]
		await _frames(12)
		alt[m[1]] = get_root().get_texture().get_image()
		alt[m[1]].save_png(out.path_join("godot_%s-%s.png" % [ta.id, m[1]]))
	get_root().msaa_3d = as_run
	print("engine_floor: quality %s, MSAA %s as run" % [_st.quality, ["off", "2x", "4x", "8x"][as_run]])
	await _compare(scene, renders, alt.msaa4, out, alt["msaa-off"], ports)
	await _chart_report(scene, chart, renders, rects, out)
	_teardown()
	quit()


static func _texture_tiles(scene: Dictionary) -> bool:
	for t in scene.tiles:
		if t.has("textured") and (not t.has("engines") or t.engines.has("godot")):
			return true
	return false


## slug.elf with the chart's SVG (--chart-svg, from tools/oracle/calib_svg.mjs) loaded as
## calib-chart24, as the guest every Slug consumer reads for this run (no cache).
func _chart_guest() -> bool:
	var svg_path: String = _a.get("chart-svg", "")
	var svg := FileAccess.get_file_as_string(svg_path)
	if svg == "":
		print("engine_floor: FAIL the textured tiles need --chart-svg=<calib-chart24.svg> (tools/oracle/calib_svg.mjs)")
		return false
	var r := SandboxUtil.make_sandbox(null, Guest.ELF, Guest.MEM_MB, Guest.REFS, Guest.TIMEOUT_UNITS)
	if r.sandbox == null:
		print("engine_floor: FAIL no slug.elf: ", r.reason)
		return false
	var ans = r.sandbox.vmcall("slug_load_svg", "calib-chart24", svg, 0.25)
	print("engine_floor: slug_load_svg(calib-chart24): ", ans)
	var g = Guest.new()
	g.sandbox = r.sandbox
	Guest.override = g
	Pack.reset()
	SlugAtlas.reset()
	Baked.reset()
	return str(ans).begins_with("ok")


## calib_world.js' chart: the #1a1a1a ground 5 mm behind, a quad per patch, one material each.
static func _chart(mats, chart: Dictionary, c: Dictionary):
	var grp := T.Group.new()
	grp.name = "calib-chart-" + str(c.get("name", ""))
	grp.position = Vector3(c.pos[0], c.pos[1], c.pos[2])
	grp.rotation = Vector3(0, deg_to_rad(c.yaw), 0)
	var px: float = c.px
	var cols := []
	for p in chart.patches:
		cols.append("#%02x%02x%02x" % [p.srgb8[0], p.srgb8[1], p.srgb8[2]])
	if c.has("swap"):
		var a: int = c.swap[0] - 1
		var b: int = c.swap[1] - 1
		var tmp = cols[a]
		cols[a] = cols[b]
		cols[b] = tmp
	var mat := func(col: String): return mats.toon(col, {"paint": 0}) if c.mat == "toon" else mats.emissive(col, 1.0)
	var ground := T.MeshObj.new(Geo.plane(690 * px, 470 * px), mat.call("#1a1a1a"))
	ground.position = Vector3(0, 0, -0.005)
	grp.add(ground)
	for i in chart.patches.size():
		var p: Dictionary = chart.patches[i]
		var q := T.MeshObj.new(Geo.plane(100 * px, 100 * px), mat.call(cols[i]))
		q.position = Vector3((20 + p.col * 110 + 50 - 345) * px, (235 - (20 + p.row * 110 + 50)) * px, 0)
		grp.add(q)
	grp.update_matrix_world()
	return grp


## The chart texture on an unlit quad, drawn one way (realize.gd's calibration draw_mode).
static func _textured(mats, t: Dictionary):
	var tex := T.Tex.new()
	tex.width = 690
	tex.height = 470
	tex.uuid = "calib-chart24"
	tex.user_data["key"] = "calib-chart24"
	var m = mats.emissive("#ffffff", 1.0, {"map": tex})
	m = m.duplicate() if m.has_method("duplicate") else m
	var mat := T.Mat.new()
	mat.type = m.type
	mat.key = m.key + "|" + str(t.draw)
	mat.color = m.color
	mat.map = tex
	mat.side = m.side
	mat.user_data = {"draw_mode": t.draw}
	var q := T.MeshObj.new(Geo.plane(690 * t.px, 470 * t.px), mat)
	q.name = "calib-chart-texture-" + str(t.draw)
	q.position = Vector3(t.pos[0], t.pos[1], t.pos[2])
	q.rotation = Vector3(0, deg_to_rad(t.yaw), 0)
	q.update_matrix_world()
	return q


func _chart_report(scene: Dictionary, chart: Dictionary, renders: Dictionary, rects: Dictionary, out: String) -> void:
	var three: String = _a.get("three", "")
	var reads := {}
	var add := func(key: String, img, tile: String, idx: int) -> void:
		if img != null and rects.has(tile) and rects[tile].size() > idx:
			reads[key] = {"img": img, "rects": rects[tile][idx]}
	add.call("three-unlit", Image.load_from_file("%s_chart-unlit.png" % three), "chart-unlit", 0)
	add.call("godot-unlit", renders.get("chart-unlit"), "chart-unlit", 0)
	add.call("godot-unlit-swapped", renders.get("chart-unlit-swapped"), "chart-unlit-swapped", 0)
	add.call("three-texture", Image.load_from_file("%s_chart-tex.png" % three), "chart-tex", 0)
	add.call("godot-baked", renders.get("chart-tex-baked"), "chart-tex-baked", 0)
	add.call("godot-runtime", renders.get("chart-tex-runtime"), "chart-tex-runtime", 0)
	add.call("three-lit", Image.load_from_file("%s_chart-toon.png" % three), "chart-toon", 0)
	add.call("godot-lit", renders.get("chart-toon"), "chart-toon", 0)
	add.call("three-shadow", Image.load_from_file("%s_chart-toon.png" % three), "chart-toon", 1)
	add.call("godot-shadow", renders.get("chart-toon"), "chart-toon", 1)
	if reads.is_empty():
		return
	await Chart.report(self, chart, reads, out)


## The class verdict the measure supports: FLOOR only where the math is identical on both sides and
## the measure is (near) zero; an e tile's figure is its increase over all post off.
static func _verdict(id: String, mad: float, base_e: float, ta, port: String) -> String:
	if id.begins_with("a-unlit"):
		if mad < 0.05:
			return "FLOOR: identical math and AA, %.2f" % mad
		return "PORT ERROR: the unlit palette path differs, %.2f" % mad
	if id == "chart-unlit":
		return "per patch in chart-calib; the frame's MAD includes the sky behind the chart"
	if id == "chart-toon":
		return "PORT ERROR: different shading math (per patch in chart-calib; the MAD includes the sky)"
	if id == "e-post-off":
		return "as b-d (shading, sky and fog); post off in both"
	if id.begins_with("e-"):
		if "not run" in port:
			return "%+.2f over all-off: stage(s) the port does not run" % (mad - base_e)
		return "%+.2f over all-off: the port's own stage(s)" % (mad - base_e)
	if id == "d-skyfog":
		return "PORT ERROR: sky and fog differ (rung 2, #68)"
	return "PORT ERROR: different shading math"


## Full-resolution RGB8 (the parity measure's scale: no resize).
static func _rgb(img: Image) -> Image:
	var x: Image = img.duplicate()
	x.convert(Image.FORMAT_RGB8)
	return x


## Mean |a - b| over RGB at full resolution, split by a's and b's 3x3 flatness: [all, edge, interior, edge fraction].
static func _split(a: Image, b: Image) -> Array:
	var x := _rgb(a)
	var y := _rgb(b)
	var w := x.get_width()
	var h := x.get_height()
	var da := x.get_data()
	var db := y.get_data()
	var fa := _flat(da, w, h)
	var fb := _flat(db, w, h)
	var se := 0.0
	var ne := 0
	var si := 0.0
	var ni := 0
	for p in w * h:
		var o := p * 3
		var dd := (absi(da[o] - db[o]) + absi(da[o + 1] - db[o + 1]) + absi(da[o + 2] - db[o + 2])) / 3.0
		if fa[p] and fb[p]:
			si += dd
			ni += 1
		else:
			se += dd
			ne += 1
	return [(se + si) / maxf(ne + ni, 1), se / maxf(ne, 1), si / maxf(ni, 1), float(ne) / maxf(ne + ni, 1)]


## Per pixel: 1 when its 3x3 neighbourhood (clamped at the borders) is one colour.
static func _flat(d: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var c := PackedInt32Array()
	c.resize(w * h)
	for p in w * h:
		c[p] = (d[p * 3] << 16) | (d[p * 3 + 1] << 8) | d[p * 3 + 2]
	var out := PackedByteArray()
	out.resize(w * h)
	for j in h:
		var j0 := maxi(j - 1, 0) * w
		var j1 := j * w
		var j2 := mini(j + 1, h - 1) * w
		for i in w:
			var i0 := maxi(i - 1, 0)
			var i2 := mini(i + 1, w - 1)
			var v := c[j1 + i]
			out[j1 + i] = 1 if (c[j0 + i0] == v and c[j0 + i] == v and c[j0 + i2] == v and c[j1 + i0] == v and c[j1 + i2] == v
					and c[j2 + i0] == v and c[j2 + i] == v and c[j2 + i2] == v) else 0
	return out


func _compare(scene: Dictionary, renders: Dictionary, a4: Image, out: String, a0: Image = null, ports: Dictionary = {}) -> void:
	var three: String = _a.get("three", "")
	var rows := []
	var res := {"tiles": {}}
	for t in scene.tiles:
		if t.has("engines") and not (t.engines.has("three") and t.engines.has("godot")):
			continue
		var ti = Image.load_from_file("%s_%s.png" % [three, t.id])
		if ti == null:
			print("engine_floor: FAIL no three.js render %s_%s.png" % [three, t.id])
			continue
		if not renders.has(t.id) or renders[t.id] == null:
			print("engine_floor: FAIL no port render of ", t.id)
			continue
		var g: Image = renders[t.id]
		var m := Sheet.mad(g, ti)
		var e := {"class": t["class"], "title": t.title, "mad": m, "port": ports.get(t.id, "")}
		if t.id == "a-unlit":
			var s := _split(ti, g)
			var s4 := _split(ti, a4)
			e["edge"] = s[1]
			e["interior"] = s[2]
			e["edge_fraction"] = s[3]
			e["mad_msaa4"] = Sheet.mad(a4, ti)
			e["edge_msaa4"] = s4[1]
			e["interior_msaa4"] = s4[2]
			if a0 != null:
				var s0 := _split(ti, a0)
				e["mad_msaa_off"] = Sheet.mad(a0, ti)
				e["edge_msaa_off"] = s0[1]
				e["interior_msaa_off"] = s0[2]
		res.tiles[t.id] = e
		rows.append({"id": t.id, "mad": m, "cells": [
			{"image": ti, "label": "three.js (original's modules)"},
			{"image": g, "label": "Godot (port's realize/MToon)\n" + str(ports.get(t.id, ""))},
			{"image": Sheet.heat(g, ti), "label": "|godot - three|: MAD %.2f" % m}]})
	var ta = res.tiles.get("a-unlit")
	if ta != null:
		var ti = Image.load_from_file("%s_a-unlit.png" % three)
		rows.append({"id": "a-unlit (port MSAA 4x)", "mad": ta.mad_msaa4, "cells": [
			{"image": ti, "label": "three.js (MSAA 4x render target)"},
			{"image": a4, "label": "Godot with MSAA 4x"},
			{"image": Sheet.heat(a4, ti), "label": "|godot - three|: MAD %.2f" % ta.mad_msaa4}]})
	rows.sort_custom(func(x, y): return x.mad > y.mad)
	var base_e: float = res.tiles["e-post-off"].mad if res.tiles.has("e-post-off") else 0.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var e = res.tiles.get(r.id)
		r["label"] = "#%d  %s  MAD %.2f  %s  [%s]" % [i + 1, r.id, r.mad, e.title if e != null else "unlit, the port at MSAA 4x",
				_verdict(r.id, r.mad, base_e, ta, str(e.port) if e != null else "")]
		if e != null:
			e["verdict"] = _verdict(r.id, r.mad, base_e, ta, str(e.port))
		r["color"] = Color(1, 0.55, 0.45) if i < 3 else Color(1, 0.95, 0.7)
	print("engine_floor: tile | class | MAD(three, godot)")
	for id in res.tiles:
		var e: Dictionary = res.tiles[id]
		print("engine_floor: %-20s %-5s  %6.2f  %s  [%s]" % [id, e["class"], e.mad, e.title, e.port])
	if ta != null:
		print("engine_floor: a-unlit as run: MAD %.2f, edge %.2f, interior %.3f, edge fraction %.3f; port at MSAA 4x: MAD %.2f, edge %.2f, interior %.3f; at MSAA off: MAD %.2f, edge %.2f, interior %.3f" % [
				ta.mad, ta.edge, ta.interior, ta.edge_fraction, ta.mad_msaa4, ta.edge_msaa4, ta.interior_msaa4,
				ta.get("mad_msaa_off", -1.0), ta.get("edge_msaa_off", -1.0), ta.get("interior_msaa_off", -1.0)])
	var f := FileAccess.open(out.path_join("engine_floor.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	var img: Image = await Sheet.render(self, "Engine floor tiles, 1920x1080: three.js (original) | Godot (port) | difference, worst first (MAD 0..255, full resolution)",
			["three.js", "Godot", "|godot - three|"], rows, Vector2i(480, 270))
	for p in Sheet.publish(img, out.path_join("engine-floor-contact-sheet.png"), "engine-floor"):
		print("engine_floor: saved ", p)


# ------------------------------------------------------------------------------------ station

const CLASS_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float cls = 0.5;
void fragment() {
	float d = length(VERTEX);
	ALBEDO = vec3(cls, sqrt(clamp(d / 2000.0, 0.0, 1.0)), 0.0);
}
"""


static func _hammersley(spec: String) -> Array:
	var parts := spec.split("@")
	var n := int(parts[0])
	var at := parts[1].split(",")
	var out := []
	for i in n:
		var u := float(i) / n
		var v := 0.0
		var f := 0.5
		var k := i
		while k > 0:
			v += (k & 1) * f
			k >>= 1
			f *= 0.5
		u = 2.0 * u if u < 0.25 else 2.0 / 3.0 * u + 1.0 / 3.0
		out.append([float(at[0]), float(at[1]), v * 360.0, clampf(rad_to_deg(acos(1.0 - 2.0 * u) - PI / 2.0), -85.0, 85.0)])
	return out


static func _unlit(mat) -> bool:
	if mat is ShaderMaterial:
		if mat.get_shader_parameter("slug_emission") == true:
			return true
		var c = mat.get_shader_parameter("_Color")
		return c is Color and c.r == 0.0 and c.g == 0.0 and c.b == 0.0
	return false


func _station() -> void:
	var floors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_a.get("floors", "")))
	await _make_station(PackedStringArray(["environment", "station", "plaza", "sakura"]))
	var layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")
	var cams := _hammersley(_a.get("hammersley", "8@-1,-11.4"))
	var sun: DirectionalLight3D = _st.get_node("Sun")
	var plain := Environment.new()
	plain.background_mode = Environment.BG_COLOR
	plain.background_color = Color(0, 0, 0)
	plain.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sh := Shader.new()
	sh.code = CLASS_SHADER
	var cm := {}
	for k in [1, 2]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("cls", 0.5 if k == 1 else 1.0)
		cm[k] = m
	# per-node / per-surface class materials, applied for the class pass only
	var swaps := []
	for n in _st.find_children("*", "MeshInstance3D", true, false):
		for i in n.mesh.get_surface_count():
			swaps.append([n, i, cm[1] if _unlit(n.mesh.surface_get_material(i)) else cm[2]])
	for n in _st.find_children("*", "MultiMeshInstance3D", true, false):
		var mat = n.material_override if n.material_override != null else n.multimesh.mesh.surface_get_material(0)
		swaps.append([n, -1, cm[1] if _unlit(mat) else cm[2]])
	print("engine_floor: station view | sky | far | unlit | toon shadowed | toon lit | edges | floor (engine, AA matched) | AA setting term (port MSAA off) | residual | residual - floor")
	var fa: Dictionary = floors.tiles["a-unlit"]
	var table := []
	for vi in cams.size():
		var c: Array = cams[vi]
		_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[3]), deg_to_rad(c[2]), 0.0), EULER_ORDER_YXZ),
				Vector3(c[0], layout.height_at(c[0], c[1]) + EYE, c[1]))
		sun.shadow_enabled = true
		await _frames(12)
		var lit_full := get_root().get_texture().get_image()
		var lit := _rgb(lit_full)
		# the same view at the original's MSAA 4x: the AA setting's effect measured, not estimated
		get_root().msaa_3d = Viewport.MSAA_4X
		await _frames(12)
		var msaa4 := get_root().get_texture().get_image()
		get_root().msaa_3d = Viewport.MSAA_DISABLED
		sun.shadow_enabled = false
		await _frames(12)
		var unshadowed := _rgb(get_root().get_texture().get_image())
		sun.shadow_enabled = true
		# class pass
		for s in swaps:
			if s[1] >= 0:
				s[0].set_surface_override_material(s[1], s[2])
			else:
				s[0].material_override = s[2]
		_cam.environment = plain
		await _frames(12)
		var cls := _rgb(get_root().get_texture().get_image())
		_cam.environment = null
		for s in swaps:
			if s[1] >= 0:
				s[0].set_surface_override_material(s[1], null)
			else:
				s[0].material_override = null
		var mix := _mix(cls, lit, unshadowed)
		# the engine floor: tile a with the port at the original's MSAA 4x (identical math and AA);
		# the AA term: what the port's MSAA-off setting adds on edge pixels (tile a as the port runs)
		var floor_est: float = mix.edge * fa.edge_msaa4 + (1.0 - mix.edge) * fa.interior_msaa4
		var aa_term: float = mix.edge * fa.edge + (1.0 - mix.edge) * fa.interior - floor_est
		var orig := Image.load_from_file("%s_%d.png" % [_a.get("original", ""), vi])
		var port := Image.load_from_file(str(_a.get("views", "")).path_join("port-view_%d.png" % vi))
		var resid := Sheet.mad(port, orig) if orig != null and port != null else -1.0
		var resid_now := Sheet.mad(lit_full, orig) if orig != null else -1.0
		var resid_msaa4 := Sheet.mad(msaa4, orig) if orig != null else -1.0
		var aa_delta := Sheet.mad(lit_full, msaa4)
		table.append([vi, mix, floor_est, resid, aa_term, resid_msaa4, aa_delta, resid_now])
		print("engine_floor: station view %d | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.2f | %.1f | %.1f" % [vi, mix.sky, mix.far, mix.unlit,
				mix.shadow, mix.lit, mix.edge, floor_est, aa_term, resid, resid - floor_est])
		print("engine_floor: station view %d at MSAA 4x: residual %.2f (this run's MSAA-off render %.2f); MAD(MSAA off, MSAA 4x) %.2f" % [vi, resid_msaa4, resid_now, aa_delta])
	var f := FileAccess.open(str(_a.get("floors", "")).get_base_dir().path_join("station_floor.json"), FileAccess.WRITE)
	var j := []
	for t in table:
		j.append({"view": t[0], "mix": t[1], "floor": t[2], "residual": t[3], "aa_setting_term": t[4], "residual_msaa4": t[5],
				"mad_msaa_off_vs_4x": t[6], "residual_this_run": t[7]})
	f.store_string(JSON.stringify(j, " "))
	f.close()
	quit()


## Class fractions of a full-resolution class render: sky, far, unlit, toon shadowed, toon lit (they sum
## to 1) and the edge fraction (class or depth jumps against a 4-neighbour).
static func _mix(cls: Image, lit: Image, unshadowed: Image) -> Dictionary:
	var w := cls.get_width()
	var h := cls.get_height()
	var dc := cls.get_data()
	var dl := lit.get_data()
	var du := unshadowed.get_data()
	var n := {"sky": 0, "far": 0, "unlit": 0, "shadow": 0, "lit": 0, "edge": 0}
	var lut := PackedFloat32Array()
	for v in 256:
		lut.append(Color8(v, 0, 0).srgb_to_linear().r)
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	cx.resize(w * h)
	cy.resize(w * h)
	for p in w * h:
		cx[p] = lut[dc[p * 3]]
		cy[p] = lut[dc[p * 3 + 1]]
	for j in h:
		for i in w:
			var p := j * w + i
			var c := Vector2(cx[p], cy[p])
			var k := "sky"
			if c.x > 0.25:
				var dist := c.y * c.y * 2000.0
				if dist > FAR_M:
					k = "far"
				elif c.x < 0.75:
					k = "unlit"
				else:
					var dlum := (du[p * 3] + du[p * 3 + 1] + du[p * 3 + 2]) - (dl[p * 3] + dl[p * 3 + 1] + dl[p * 3 + 2])
					k = "shadow" if dlum > 6 else "lit"
			n[k] += 1
			for q in [p - 1, p + 1, p - w, p + w]:
				if q < 0 or q >= w * h:
					continue
				var cq := Vector2(cx[q], cy[q])
				if (cq.x > 0.25) != (c.x > 0.25) or absf(cq.x - c.x) > 0.25 or absf(cq.y - c.y) > 0.02:
					n.edge += 1
					break
	var total := float(w * h)
	for k in n:
		n[k] = n[k] / total
	return n
