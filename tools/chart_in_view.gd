# The 24-patch chart in each Hammersley view's own light, placed only where both engines' shadow maps
# agree it is sunlit or shadowed; these renders are separate from the chart-free parity renders.
#   1. godot --path . --resolution 1920x1080 --script tools/chart_in_view.gd -- --place --out=<dir>
#   2. node tools/oracle/calib_probe.mjs --candidates <dir>/candidates.json --out <dir>/candidates_original.json
#   3. godot ... -- --pick --candidates=<dir>/candidates.json --original-probe=<dir>/candidates_original.json --out=<dir>
#   4. node tools/oracle/calib_inview.mjs --placements <dir>/placements.json --out <dir>/original --runs 2
#   5. godot ... -- --render --placements=<dir>/placements.json --shots=<dir>/port   (twice: port, port2)
#   6. godot ... -- --report --placements=<dir>/placements.json --original=<dir>/original
#          --original2=<dir>/original2 --port=<dir>/port --port2=<dir>/port2   (writes tools/calib/chart_in_view.json)
# tools/calib/chart_in_view_placements.json holds the placements behind that JSON; steps 4-6 from it reproduce it.
extends SceneTree

const Materials = preload("res://addons/sakuragaoka_station/core/materials.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Sheet = preload("res://tools/sheet.gd")
const Chart = preload("res://tools/chart_calib.gd")
const Floor = preload("res://tools/engine_floor.gd")
const CHART := "res://tools/calib/chart24.json"
const JSON_OUT := "res://tools/calib/chart_in_view.json"
const MODULES := ["environment", "station", "plaza", "sakura"]
const EYE := 1.52
const PATCH_MIN_PX := 24.0
const PATCH_AIM_PX := 30.0
const NL_MIN := 0.25
const TURN_MAX_DEG := 60.0
const PROBE_MARGIN := 1.3
const INSET := 2.0
# every preferred candidate is probed; the wide grid only when a state has fewer than ENOUGH
const DISTANCES := [3.0, 2.6, 3.4, 2.2, 3.8, 1.8, 4.4, 1.4, 1.1]
const SY := [0.75, 0.68, 0.82, 0.6, 0.88]
const SX := [0.5, 0.38, 0.62, 0.26, 0.74, 0.14, 0.86]
const DISTANCES_WIDE := [3.0, 3.5, 2.5, 4.5, 2.0, 5.5, 1.6, 7.0, 1.2, 9.0]
const SY_FINE := [0.75, 0.69, 0.81, 0.63, 0.87, 0.57, 0.92, 0.51, 0.45, 0.39, 0.33, 0.27, 0.21, 0.15]
const SX_FINE := [0.5, 0.43, 0.57, 0.36, 0.64, 0.29, 0.71, 0.22, 0.78, 0.15, 0.85, 0.08, 0.92]
const ENOUGH := 12
const CHECK := 60
const NEUTRALS := [19, 20, 21, 22, 23, 24]
const CROP := Vector2i(420, 286)
const PROBE_SHADER := """shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;
// red: the sun's shadow attenuation here (1 lit, 0 in shadow); green 1 marks a probe pixel
void fragment() {
	ALBEDO = vec3(1.0, 0.0, 0.0);
	EMISSION = vec3(0.0, 1.0, 0.0);
}
void light() {
	DIFFUSE_LIGHT += vec3(ATTENUATION);
}
"""

var _a := {}
var _st: Node3D
var _cam: Camera3D
var _layout
var _probe_mat: ShaderMaterial


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var eq := a.find("=")
			_a[a.substr(2, eq - 2) if eq > 0 else a.substr(2)] = a.substr(eq + 1) if eq > 0 else "1"
	if _a.has("place"):
		_place_all.call_deferred()
	elif _a.has("pick"):
		_pick_all.call_deferred()
	elif _a.has("render"):
		_render_all.call_deferred()
	elif _a.has("report"):
		_report.call_deferred()
	else:
		print("chart_in_view: give --place, --pick, --render or --report (see the header)")
		quit(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _make_cam() -> void:
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()
	_layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")


func _make_station() -> void:
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	_st.modules = PackedStringArray(MODULES)
	_st.quality = _a.get("q", "high")
	get_root().add_child(_st)
	await _st.built
	_make_cam()


func _teardown() -> void:
	_probe_mat = null
	_layout = null
	Kernels.shutdown()
	Guest.shutdown()


## The walking eye of a Hammersley camera [x, z, yaw, pitch], as realize_check and shot.mjs place it.
func _eye(c: Array) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[3]), deg_to_rad(c[2]), 0.0), EULER_ORDER_YXZ),
			Vector3(c[0], _layout.height_at(c[0], c[1]) + EYE, c[1]))


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# ------------------------------------------------------------------------------------- place

## A chart facing the camera at screen point s and view depth d, turned toward the sun when its face would get
## under NL_MIN; {} when it cannot be framed whole with patches of at least PATCH_MIN_PX.
func _candidate(s: Vector2, d: float, sun: Vector3) -> Dictionary:
	var size := Vector2(get_root().size)
	var centre := _cam.project_position(s * size, d)
	var eye := _cam.global_position
	var n := (eye - centre).normalized()
	var turn := 0.0
	if n.dot(sun) < NL_MIN:
		for k in range(5, int(TURN_MAX_DEG) + 1, 5):
			var m1 := n.rotated(Vector3.UP, deg_to_rad(k))
			var m2 := n.rotated(Vector3.UP, deg_to_rad(-k))
			var m := m1 if m1.dot(sun) >= m2.dot(sun) else m2
			if m.dot(sun) >= NL_MIN:
				n = m
				turn = k if m == m1 else -k
				break
	var c := {"pos": [centre.x, centre.y, centre.z], "yaw": rad_to_deg(atan2(n.x, n.z)), "pitch": rad_to_deg(-asin(clampf(n.y, -1.0, 1.0))),
			"px": 0.001, "screen": [s.x, s.y], "depth": d, "turn_deg": turn, "normal": [n.x, n.y, n.z], "n_dot_l": n.dot(sun),
			"distance": (centre - eye).length()}
	for it in 2:
		var m := _patch_px(c)
		if m <= 0.0:
			return {}
		c.px = c.px * PATCH_AIM_PX / m
	c["patch_px"] = _patch_px(c)
	if c.patch_px < PATCH_MIN_PX or c.px * 690.0 > 1.6:
		return {}
	var box := _quad_box(_quad(c, 1.0))
	if box.size.x <= 0.0 or not Rect2(Vector2(8, 8), size - Vector2(16, 16)).encloses(box):
		return {}
	c["box"] = box
	c["probe_quad"] = _quad(c, PROBE_MARGIN)
	c["probe_box"] = _quad_box(c.probe_quad)
	return c


## The smallest on-screen side of a corner patch (patches 1, 6, 19 and 24), or -1 behind the camera.
func _patch_px(c: Dictionary) -> float:
	var m := INF
	for rc in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 3), Vector2i(5, 3)]:
		var u: float = 20.0 + rc.x * 110.0
		var v: float = 20.0 + rc.y * 110.0
		var pts := []
		for k in [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]:
			var w := Chart.chart_point(c, u + k.x, v + k.y)
			if _cam.is_position_behind(w):
				return -1.0
			pts.append(_cam.unproject_position(w))
		m = minf(m, minf((pts[1] - pts[0]).length(), (pts[3] - pts[0]).length()))
	return m


## The chart's outline on screen (grown by `grow` about its centre).
func _quad(c: Dictionary, grow: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var w := Chart.chart_point(c, 345.0 + k.x * 345.0 * grow, 235.0 + k.y * 235.0 * grow)
		if _cam.is_position_behind(w):
			return PackedVector2Array()
		out.append(_cam.unproject_position(w))
	return out


static func _quad_box(q: PackedVector2Array) -> Rect2:
	if q.is_empty():
		return Rect2()
	var lo := q[0]
	var hi := q[0]
	for p in q:
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


## Classifies one probe from the frame: the pixels inside its quad, INSET px in from the edges.
static func _classify(d: PackedByteArray, w: int, h: int, q: PackedVector2Array) -> Dictionary:
	var centre := (q[0] + q[1] + q[2] + q[3]) / 4.0
	var edges := []
	for i in 4:
		var a := q[i]
		var e := (q[(i + 1) % 4] - a).normalized()
		var n := Vector2(-e.y, e.x)
		if (centre - a).dot(n) < 0.0:
			n = -n
		edges.append([a, n])
	var box := _quad_box(q)
	var n_px := 0
	var hidden := 0
	var lo := 255
	var hi := 0
	for y in range(maxi(int(box.position.y), 0), mini(int(box.end.y) + 1, h)):
		var yc := y + 0.5
		var x0 := -INF
		var x1 := INF
		var row_ok := true
		for e in edges:
			var a: Vector2 = e[0]
			var n: Vector2 = e[1]
			var rhs := INSET + a.dot(n) - n.y * yc
			if absf(n.x) < 1e-6:
				if rhs > 0.0:
					row_ok = false
			elif n.x > 0.0:
				x0 = maxf(x0, rhs / n.x)
			else:
				x1 = minf(x1, rhs / n.x)
		if not row_ok:
			continue
		for x in range(maxi(ceili(x0 - 0.5), 0), mini(floori(x1 - 0.5), w - 1) + 1):
			var i := (y * w + x) * 3
			n_px += 1
			if d[i + 1] < 250 or d[i + 2] > 5:
				hidden += 1
				continue
			lo = mini(lo, d[i])
			hi = maxi(hi, d[i])
	var state := "offscreen"
	if n_px > 0:
		state = "hidden" if hidden > 0 else ("lit" if lo >= 250 else ("shadow" if hi <= 5 else "mixed"))
	return {"state": state, "pixels": n_px, "hidden": hidden, "att_min": lo / 255.0, "att_max": hi / 255.0}


## Every candidate's probe, in passes of probes that do not overlap on screen.
func _probe(cands: Array) -> void:
	var passes := []
	for c in cands:
		var placed := false
		for p in passes:
			var free := true
			for o in p:
				if o.probe_box.grow(4.0).intersects(c.probe_box):
					free = false
					break
			if free:
				p.append(c)
				placed = true
				break
		if not placed:
			passes.append([c])
	for p in passes:
		var nodes := []
		for c in p:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(690.0 * c.px * PROBE_MARGIN, 470.0 * c.px * PROBE_MARGIN)
			mi.mesh = q
			mi.material_override = _probe_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(Chart.chart_basis(c), _vec(c.pos))
			get_root().add_child(mi)
			nodes.append(mi)
		await _frames(4)
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var d := img.get_data()
		for c in p:
			c["probe"] = _classify(d, img.get_width(), img.get_height(), c.probe_quad)
		for n in nodes:
			n.queue_free()
	await process_frame


## Lower is better: near the preferred depth, low and central in the frame, and facing the sun.
static func _score(c: Dictionary, lit: bool) -> float:
	var s: float = absf(c.depth - 3.0) + 3.0 * absf(c.screen[1] - 0.75) + 0.5 * absf(c.screen[0] - 0.5)
	if c.n_dot_l < NL_MIN:
		s += 4.0 if lit else 1.0
	return s


## The best sunlit and shadowed pair whose charts do not overlap on screen, else the best of each.
static func _pick(lit: Array, sh: Array) -> Dictionary:
	var best := {"lit": null, "shadow": null, "pair": false}
	var bs := INF
	for a in lit:
		for b in sh:
			if _rect(a.box).grow(10.0).intersects(_rect(b.box)):
				continue
			var s := _score(a, true) + _score(b, false)
			if s < bs:
				bs = s
				best = {"lit": a, "shadow": b, "pair": true}
	if best.pair:
		return best
	for k in [["lit", lit], ["shadow", sh]]:
		var bk := INF
		for c in k[1]:
			if _score(c, k[0] == "lit") < bk:
				bk = _score(c, k[0] == "lit")
				best[k[0]] = c
	return best


static func _rect(b) -> Rect2:
	return b if b is Rect2 else Rect2(b[0], b[1], b[2], b[3])


static func _arr(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


## The light a chart's face gets from the sun where nothing shades it.
static func _facing(n_dot_l: float) -> String:
	return "front-lit" if n_dot_l >= NL_MIN else ("grazing" if n_dot_l > 0.0 else "back-lit")


func _place_all() -> void:
	var out: String = _a.get("out", "user://chart_in_view")
	DirAccess.make_dir_recursive_absolute(out)
	await _make_station()
	var sun: Vector3 = _st.sun_dir.normalized()
	var we = _st.get_node_or_null("SkyAndFog")
	if we != null and we.compositor != null:
		for e in we.compositor.compositor_effects:
			if e != null:
				e.enabled = false
	_probe_mat = ShaderMaterial.new()
	_probe_mat.shader = Shader.new()
	_probe_mat.shader.code = PROBE_SHADER
	var spec: String = _a.get("hammersley", "8@-1,-11.4")
	var cams: Array = Floor._hammersley(spec)
	var views := []
	for vi in cams.size():
		var cam: Array = cams[vi]
		_cam.transform = _eye(cam)
		await _frames(12)
		var cands := []
		for d in DISTANCES:
			var level := []
			for sy in SY:
				for sx in SX:
					var c := _candidate(Vector2(sx, sy), d, sun)
					if not c.is_empty():
						level.append(c)
			await _probe(level)
			cands.append_array(level)
		var wide := false
		if _count(cands, "lit") < ENOUGH or _count(cands, "shadow") < ENOUGH:
			wide = true
			for d in DISTANCES_WIDE:
				var level := []
				for sy in SY_FINE:
					for sx in SX_FINE:
						var c := _candidate(Vector2(sx, sy), d, sun)
						if not c.is_empty():
							level.append(c)
				await _probe(level)
				cands.append_array(level)
		var tally := {}
		for c in cands:
			tally[c.probe.state] = tally.get(c.probe.state, 0) + 1
		var check := []
		for k in [["lit", true], ["shadow", false]]:
			var ks := cands.filter(func(c): return c.probe.state == k[0])
			ks.sort_custom(func(x, y): return _score(x, k[1]) < _score(y, k[1]))
			for c in ks.slice(0, CHECK):
				var e: Dictionary = c.duplicate()
				e.id = "v%d-%d" % [vi, check.size()]
				e.box = _arr(c.box)
				e.probe_box = _arr(c.probe_box)
				e.erase("probe_quad")
				check.append(e)
		print("chart_in_view: view %d: %d candidates %s%s; %d to check in the original" % [vi, cands.size(), str(tally),
				" (wider search)" if wide else "", check.size()])
		views.append({"view": vi, "cam": cam, "eye": [_cam.global_position.x, _cam.global_position.y, _cam.global_position.z],
				"tried": cands.size(), "probe_states": tally, "wider_search": wide, "check": check})
	var res := {"note": "in-view chart candidates, probed with the port's shadow map (tools/chart_in_view.gd --place)", "hammersley": spec,
			"w": get_root().size.x, "h": get_root().size.y, "quality": _st.quality, "modules": MODULES, "sun_dir": [sun.x, sun.y, sun.z],
			"probe_margin": PROBE_MARGIN, "views": views}
	var f := FileAccess.open(out.path_join("candidates.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	print("chart_in_view: saved ", out.path_join("candidates.json"))
	_teardown()
	quit()


static func _count(cands: Array, state: String) -> int:
	var n := 0
	for c in cands:
		if c.probe.state == state:
			n += 1
	return n


## The best sunlit and shadowed pair per view that both engines' probes agree on: placements.json.
func _pick_all() -> void:
	var cand: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_a.get("candidates", "")))
	var orig := {}
	if _a.has("original-probe"):
		var op: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_a.get("original-probe")))
		for v in op.views:
			orig[int(v.view)] = v.states
	var out: String = _a.get("out", str(_a.get("candidates", "")).get_base_dir())
	var views := []
	print("chart_in_view: view | chart | state | world position | normal | N.L | distance | screen | patch px")
	for v in cand.views:
		var vi := int(v.view)
		var lit := []
		var sh := []
		var agree := {"lit": {}, "shadow": {}}
		for c in v.check:
			var st: String = c.probe.state
			if orig.has(vi):
				st = orig[vi][c.id].state if orig[vi].has(c.id) else "unchecked"
				c["probe_original"] = orig[vi].get(c.id)
			agree[c.probe.state][st] = agree[c.probe.state].get(st, 0) + 1
			if st != c.probe.state:
				continue
			if st == "lit":
				lit.append(c)
			else:
				sh.append(c)
		var pick := _pick(lit, sh)
		var charts := []
		for k in ["lit", "shadow"]:
			var c = pick[k]
			if c == null:
				print("chart_in_view: %d | %s | NONE: no candidate %s in both engines" % [vi, k, "sunlit" if k == "lit" else "shadowed"])
				continue
			var e := {"name": "v%d-%s" % [vi, k], "state": "sunlit" if k == "lit" else "shadowed", "facing": _facing(c.n_dot_l),
					"pos": c.pos, "yaw": c.yaw, "pitch": c.pitch, "px": c.px, "normal": c.normal, "n_dot_l": c.n_dot_l,
					"turn_deg": c.turn_deg, "distance": c.distance, "depth": c.depth, "screen": c.screen, "patch_px": c.patch_px,
					"probe": c.probe, "probe_original": c.get("probe_original"), "lower_frame": c.screen[1] >= 0.55,
					"wider_search": v.wider_search}
			charts.append(e)
			print("chart_in_view: %d | %s | %s, %s | (%.2f, %.2f, %.2f) | (%.2f, %.2f, %.2f) | %.2f | %.2f m | (%.2f, %.2f) | %.0f" % [
					vi, k, e.state, e.facing, c.pos[0], c.pos[1], c.pos[2], c.normal[0], c.normal[1], c.normal[2], c.n_dot_l, c.distance,
					c.screen[0], c.screen[1], c.patch_px])
		print("chart_in_view: %d   the original's verdict on the port's sunlit candidates %s, on its shadowed ones %s" % [vi,
				str(agree.lit), str(agree.shadow)])
		views.append({"view": vi, "cam": v.cam, "eye": v.eye, "charts": charts, "pair": pick.pair, "tried": v.tried,
				"probe_states": v.probe_states, "agreement": agree, "wider_search": v.wider_search})
	var res := {"note": "in-view chart placements (tools/chart_in_view.gd --pick): " + ("sunlit or shadowed in both engines' shadow maps" if not orig.is_empty() else "the port's shadow map alone"),
			"hammersley": cand.hammersley, "w": cand.w, "h": cand.h, "quality": cand.quality, "modules": cand.modules, "sun_dir": cand.sun_dir,
			"probe_margin": cand.probe_margin, "both_engines": not orig.is_empty(), "views": views}
	var f := FileAccess.open(out.path_join("placements.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	print("chart_in_view: saved ", out.path_join("placements.json"))
	quit()


# ------------------------------------------------------------------------------------ render

func _render_all() -> void:
	var pl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_a.get("placements", "")))
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART))
	var out: String = _a.get("shots", "user://chart_in_view/port")
	DirAccess.make_dir_recursive_absolute(out)
	await _make_station()
	var mats = Materials.new()
	var holders := []
	for v in pl.views:
		var objs := []
		for c in v.charts:
			objs.append(Floor._chart(mats, chart, {"name": c.name, "pos": c.pos, "yaw": c.yaw, "pitch": c.pitch, "px": c.px, "mat": "toon"}))
		var h := Node3D.new()
		h.name = "chart-in-view-%d" % int(v.view)
		_st.add_child(h)
		var r = Realize.new()
		r.realize_part(objs, h)
		await process_frame
		await process_frame
		r.finish()
		for g in h.find_children("*", "GeometryInstance3D", true, false):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holders.append(h)
	for i in pl.views.size():
		for j in holders.size():
			holders[j].visible = i == j
		_cam.transform = _eye(pl.views[i].cam)
		await _frames(12)
		var img := get_root().get_texture().get_image()
		img.save_png(out.path_join("port_%d.png" % int(pl.views[i].view)))
		print("chart_in_view: rendered view %d (%d charts)" % [int(pl.views[i].view), pl.views[i].charts.size()])
	_teardown()
	quit()


# ------------------------------------------------------------------------------------ report

static func _y(rgb8: Vector3) -> float:
	var l := func(c: float) -> float: return c / 255.0 / 12.92 if c / 255.0 <= 0.04045 else pow((c / 255.0 + 0.055) / 1.055, 2.4)
	return 0.2126729 * l.call(rgb8.x) + 0.7151522 * l.call(rgb8.y) + 0.0721750 * l.call(rgb8.z)


## Byte-identity of two renders: [identical, pixels that differ, largest channel difference].
static func _same(a: Image, b: Image) -> Array:
	if a == null or b == null:
		return [false, -1, -1]
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	var da := x.get_data()
	var db := y.get_data()
	if da == db:
		return [true, 0, 0]
	var n := 0
	var m := 0
	for i in range(0, mini(da.size(), db.size()), 3):
		var dd := maxi(absi(da[i] - db[i]), maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
		if dd > 0:
			n += 1
			m = maxi(m, dd)
	return [false, n, m]


## dE00 on a black-red-yellow-white scale: 0 black, 5 red, 10 yellow, 20 and up white.
static func _de_colour(de: float) -> Color:
	var t := clampf(de / 20.0, 0.0, 1.0)
	if t < 0.25:
		return Color(t / 0.25, 0, 0)
	if t < 0.5:
		return Color(1, (t - 0.25) / 0.25, 0)
	return Color(1, 1, (t - 0.5) / 0.5)


static func _grid(des: Array) -> Image:
	var im := Image.create(CROP.x, CROP.y, false, Image.FORMAT_RGB8)
	im.fill(Color(0.12, 0.12, 0.14))
	var cw := CROP.x / 6
	var ch := CROP.y / 4
	for i in 24:
		im.fill_rect(Rect2i((i % 6) * cw + 1, (i / 6) * ch + 1, cw - 2, ch - 2), _de_colour(des[i]))
	return im


static func _crop(img: Image, box: Rect2) -> Image:
	var r := Rect2i(box.grow(maxf(box.size.x, box.size.y) * 0.04))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var c := img.get_region(r)
	c.convert(Image.FORMAT_RGB8)
	var s := minf(float(CROP.x) / r.size.x, float(CROP.y) / r.size.y)
	c.resize(maxi(1, roundi(r.size.x * s)), maxi(1, roundi(r.size.y * s)), Image.INTERPOLATE_NEAREST)
	var out := Image.create(CROP.x, CROP.y, false, Image.FORMAT_RGB8)
	out.fill(Color(0.12, 0.12, 0.14))
	out.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), (CROP - c.get_size()) / 2)
	return out


func _report() -> void:
	var pl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_a.get("placements", "")))
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART))
	_make_cam()
	await _frames(2)
	var o1: String = _a.get("original", "")
	var o2: String = _a.get("original2", "")
	var p1: String = _a.get("port", "")
	var p2: String = _a.get("port2", "")
	var res := {"note": "the 24-patch chart in each Hammersley view's own light (tools/chart_in_view.gd); colours are mean 8-bit sRGB codes of each patch's central 60%; dE00 is CIEDE2000 on L*a*b* D50 (Bradford) of those means; truth is the patch's srgb8 (the unlit chart both engines draw exactly)",
			"hammersley": pl.hammersley, "w": pl.w, "h": pl.h, "quality": pl.get("quality", "high"), "modules": pl.get("modules", MODULES),
			"sun_dir": pl.sun_dir, "determinism": {"original": [], "port": []}, "views": []}
	var rows := []
	var all_og := []
	print("chart_in_view: determinism (each engine rendered twice):")
	for v in pl.views:
		var vi := int(v.view)
		var imgs := {}
		for k in [["original", "%s_%d.png" % [o1, vi]], ["original2", "%s_%d.png" % [o2, vi]], ["port", p1.path_join("port_%d.png" % vi)],
				["port2", p2.path_join("port_%d.png" % vi)]]:
			imgs[k[0]] = Image.load_from_file(k[1]) if FileAccess.file_exists(k[1]) else null
		var so := _same(imgs.original, imgs.original2)
		var sp := _same(imgs.port, imgs.port2)
		_cam.transform = _eye(v.cam)
		await _frames(1)
		var ve := {"view": vi, "cam": v.cam, "charts": []}
		var area_same := {"original": true, "port": true}
		for c in v.charts:
			var rects := Chart.patch_rects(_cam, c, chart)
			var reads := {}
			for k in imgs:
				if imgs[k] != null:
					reads[k] = Chart.read(imgs[k], rects)
			for k in [["original", "original2"], ["port", "port2"]]:
				if reads.has(k[0]) and reads.has(k[1]) and reads[k[0]] != reads[k[1]]:
					area_same[k[0]] = false
			if not (reads.has("original") and reads.has("port")):
				print("chart_in_view: FAIL view %d chart %s: missing renders" % [vi, c.name])
				continue
			var ce := {"name": c.name, "state": c.state, "facing": c.get("facing", ""), "placement": {"pos": c.pos, "normal": c.normal, "yaw": c.yaw, "pitch": c.pitch,
					"px": c.px, "n_dot_l": c.n_dot_l, "turn_deg": c.turn_deg, "distance": c.distance, "screen": c.screen,
					"patch_px": c.patch_px, "lower_frame": c.lower_frame}, "patches": []}
			var des := []
			var s_og := 0.0
			var s_ot := 0.0
			var s_pt := 0.0
			var worst := [0.0, 0]
			for i in chart.patches.size():
				var p: Dictionary = chart.patches[i]
				var truth := Vector3(p.srgb8[0], p.srgb8[1], p.srgb8[2])
				var o: Vector3 = reads.original[i]
				var g: Vector3 = reads.port[i]
				var og := Chart.de2000(Chart.lab(o), Chart.lab(g))
				var ot := Chart.de2000(Chart.lab(truth), Chart.lab(o))
				var pt := Chart.de2000(Chart.lab(truth), Chart.lab(g))
				des.append(og)
				all_og.append(og)
				s_og += og
				s_ot += ot
				s_pt += pt
				if og > worst[0]:
					worst = [og, p.no]
				ce.patches.append({"no": p.no, "name": p.name, "srgb8": p.srgb8, "original": [o.x, o.y, o.z], "port": [g.x, g.y, g.z],
						"de_original_port": og, "de_original_truth": ot, "de_port_truth": pt})
			var nn: int = chart.patches.size()
			ce["de_original_port"] = {"mean": s_og / nn, "max": worst[0], "max_patch": worst[1]}
			ce["de_original_truth_mean"] = s_ot / nn
			ce["de_port_truth_mean"] = s_pt / nn
			# the neutral row's tone curve: linear luminance and L*, reference and each engine
			var tone := {"no": [], "truth_y": [], "original_y": [], "port_y": [], "truth_l": [], "original_l": [], "port_l": [],
					"gain_original": [], "gain_port": []}
			for no in NEUTRALS:
				var p: Dictionary = chart.patches[no - 1]
				var t8 := Vector3(p.srgb8[0], p.srgb8[1], p.srgb8[2])
				var yo := _y(reads.original[no - 1])
				var yp := _y(reads.port[no - 1])
				var yt := _y(t8)
				tone.no.append(no)
				tone.truth_y.append(yt)
				tone.original_y.append(yo)
				tone.port_y.append(yp)
				tone.truth_l.append(Chart.lab(t8).x)
				tone.original_l.append(Chart.lab(reads.original[no - 1]).x)
				tone.port_l.append(Chart.lab(reads.port[no - 1]).x)
				tone.gain_original.append(yo / yt)
				tone.gain_port.append(yp / yt)
			ce["neutral_tone"] = tone
			ve.charts.append(ce)
			var box := _quad_box(_quad(c, 1.0))
			var lines := PackedStringArray()
			for r in 4:
				var parts := PackedStringArray()
				for col in 6:
					parts.append("%4.1f" % des[r * 6 + col])
				lines.append("  ".join(parts))
			rows.append({"mean": s_og / nn, "label": "view %d (yaw %.0f, pitch %.1f) %s chart: %s, N.L %.2f, %.1f m | dE00 original-port mean %.2f, max %.2f (patch %d)" % [
					vi, v.cam[2], v.cam[3], c.name.split("-")[1], c.state + ", " + str(c.get("facing", "")), c.n_dot_l, c.distance,
					s_og / nn, worst[0], worst[1]],
					"cells": [
						{"image": _crop(imgs.original, box), "label": "original: dE00 vs truth mean %.2f\nwhite gain %.2f, black gain %.2f\nat (%.2f, %.2f, %.2f), normal (%.2f, %.2f, %.2f)" % [
								s_ot / nn, tone.gain_original[0], tone.gain_original[5], c.pos[0], c.pos[1], c.pos[2], c.normal[0], c.normal[1], c.normal[2]]},
						{"image": _crop(imgs.port, box), "label": "port: dE00 vs truth mean %.2f\nwhite gain %.2f, black gain %.2f\npatches %.0f px, screen (%.2f, %.2f)" % [
								s_pt / nn, tone.gain_port[0], tone.gain_port[5], c.patch_px, c.screen[0], c.screen[1]]},
						{"image": _grid(des), "label": "dE00 original-port per patch (rows as the chart):\n" + "\n".join(lines)}]})
		res.determinism.original.append({"view": vi, "identical": so[0], "pixels_differ": so[1], "max": so[2], "chart_reads_identical": area_same.original})
		res.determinism.port.append({"view": vi, "identical": sp[0], "pixels_differ": sp[1], "max": sp[2], "chart_reads_identical": area_same.port})
		print("chart_in_view:   view %d: original %s, port %s" % [vi,
				"byte-identical" if so[0] else "%d px differ (max %d); chart reads %s" % [so[1], so[2], "identical" if area_same.original else "DIFFER"],
				"byte-identical" if sp[0] else "%d px differ (max %d); chart reads %s" % [sp[1], sp[2], "identical" if area_same.port else "DIFFER"]])
		res.views.append(ve)
	var m := 0.0
	for x in all_og:
		m += x
	res["summary"] = {"de_original_port_mean": m / maxf(all_og.size(), 1), "charts": rows.size()}
	print("chart_in_view: view | chart | state | dE00 original-port mean / max (patch) | vs truth: original, port | neutral gains original | neutral gains port")
	for ve in res.views:
		for ce in ve.charts:
			var go := PackedStringArray()
			var gp := PackedStringArray()
			for k in ce.neutral_tone.gain_original.size():
				go.append("%.2f" % ce.neutral_tone.gain_original[k])
				gp.append("%.2f" % ce.neutral_tone.gain_port[k])
			print("chart_in_view: %d | %s | %s, %s | %.2f / %.2f (%d) | %.2f, %.2f | %s | %s" % [ve.view, ce.name, ce.state, ce.facing, ce.de_original_port.mean,
					ce.de_original_port.max, ce.de_original_port.max_patch, ce.de_original_truth_mean, ce.de_port_truth_mean, " ".join(go), " ".join(gp)])
	print("chart_in_view: mean dE00 original-port over every patch of every chart: %.2f" % res.summary.de_original_port_mean)
	var json_path: String = _a.get("json", ProjectSettings.globalize_path(JSON_OUT))
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	print("chart_in_view: saved ", json_path)
	rows.sort_custom(func(x, y): return x.mean > y.mean)
	for i in rows.size():
		rows[i].label = "#%d  %s" % [i + 1, rows[i].label]
		rows[i]["color"] = Color(1, 0.55, 0.45) if i < 3 else Color(1, 0.95, 0.7)
	var img: Image = await Sheet.render(self, "24-patch chart in each view's light, worst first: original | port | dE00 per patch (0 black, 5 red, 10 yellow, 20+ white)",
			["original", "port", "dE00 per patch"], rows, CROP)
	var out: String = _a.get("out", p1.get_base_dir())
	for p in Sheet.publish(img, out.path_join("chart-in-view-sheet.png"), "chart-in-view"):
		print("chart_in_view: saved ", p)
	quit()
