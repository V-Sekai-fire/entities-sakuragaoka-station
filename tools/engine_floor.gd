# Engine floor for the station parity diff (residual ladder rung 0): the calibration tiles of
# tools/oracle/calib_scene.json rendered by the port (realize.gd's palette/MToon path, the
# station's own sky, fog, sun and ambient) and compared with the same tiles rendered by the original
# (tools/oracle/calib.mjs, the original's own modules), one tile per content class:
#   a  unlit palette triangles with sharp edges   b  the toon ramp under the station's sun and
#   ambient (with and without the hand-paint noise)   c  sun shadows   d  sky and fog at distance
#   e  each post stage of the original alone, all off and all on (the port has none)
# Measures, all in the station's units (MAD 0..255: both images at half size, RGB):
#   d(three, godot) per tile; for tile a also split into edge pixels (where either render is not
#   flat over its 3x3 neighbourhood) and interior pixels, and again with the port at MSAA 4x.
# With --station it also renders the station's Hammersley views with a class pass (sky; geometry
# past 150 m; unlit; toon in the sun's shadow; lit toon; edges where class or depth jumps) and
# estimates each view's floor from its class mix and the per-class floors, against its residual.
#   godot --path . --resolution 1920x1080 --script tools/engine_floor.gd -- --three=<prefix> --out=<dir>
#   godot --path . --resolution 1920x1080 --script tools/engine_floor.gd -- --station --floors=<dir>/engine_floor.json
#       --original=<prefix> --views=<dir> [--hammersley=8@-1,-11.4]
# <prefix>_<tile id>.png are calib.mjs' renders; <dir>/godot_<tile id>.png are written here, with
# engine_floor.json (the measures) and engine-floor-contact-sheet.png (three | godot | diff, worst
# first; also copied to the desktop as engine-floor-NN by Sheet.publish).
extends SceneTree

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Materials = preload("res://addons/sakuragaoka_station/core/materials.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Sheet = preload("res://tools/sheet.gd")
const SCENE := "res://tools/oracle/calib_scene.json"
const FAR_M := 150.0
const EYE := 1.52

var _a := {}
var _st: Node3D
var _cam: Camera3D


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
	get_root().add_child(_st)
	await _st.built
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()


# ------------------------------------------------------------------------------------- tiles

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
		for t in scene.tiles:
			have[t.id] = Image.load_from_file(out.path_join("godot_%s.png" % (t.id if not (t.has("same_as") and t.same_as != null) else t.same_as)))
		_compare(scene, have, Image.load_from_file(out.path_join("godot_%s-msaa4.png" % scene.tiles[0].id)), out)
		return
	await _make_station(PackedStringArray())
	var mats = Materials.new()
	var objs := []
	for t in scene.tiles:
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
	for t in scene.tiles:
		if t.has("same_as") and t.same_as != null and renders.has(t.same_as):
			renders[t.id] = renders[t.same_as]
			continue
		sun.shadow_enabled = bool(t.shadows)
		_place(t.cam)
		await _frames(12)
		var img := get_root().get_texture().get_image()
		img.save_png(out.path_join("godot_%s.png" % t.id))
		renders[t.id] = img
		print("engine_floor: rendered ", t.id)
	# tile a again with the port at MSAA 4x: how much of its floor is the AA setting
	var ta: Dictionary = scene.tiles[0]
	sun.shadow_enabled = bool(ta.shadows)
	get_root().msaa_3d = Viewport.MSAA_4X
	_place(ta.cam)
	await _frames(12)
	var a4 := get_root().get_texture().get_image()
	a4.save_png(out.path_join("godot_%s-msaa4.png" % ta.id))
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	_compare(scene, renders, a4, out)


## The class verdict the measure supports: FLOOR only where the math is identical on both sides.
static func _verdict(id: String, mad: float, base_e: float, ta) -> String:
	if id == "a-unlit (port MSAA 4x)":
		return "FLOOR: identical math and AA, %.2f" % mad
	if id == "a-unlit":
		return "PORT ERROR (setting): MSAA off in the port; %.2f with MSAA 4x" % (ta.mad_msaa4 if ta != null else -1.0)
	if id == "e-post-off":
		return "PORT ERROR: as b-d, plus the sky's clouds missing (rung 2, #68)"
	if id.begins_with("e-"):
		return "MISSING in the port (rung 2, #68): %+.2f over all-off" % (mad - base_e)
	if id == "d-skyfog":
		return "PORT ERROR: fog curve and toon ground; clouds missing (rung 2, #68)"
	return "PORT ERROR: different shading math"


## Half-size RGB8 (the station measure's scale).
static func _half(img: Image) -> Image:
	var x: Image = img.duplicate()
	x.convert(Image.FORMAT_RGB8)
	x.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	return x


## Mean |a - b| over RGB of half-size images, split by a's and b's 3x3 flatness: [all, edge, interior, edge fraction].
static func _split(a: Image, b: Image) -> Array:
	var x := _half(a)
	var y := _half(b)
	var w := x.get_width()
	var h := x.get_height()
	var da := x.get_data()
	var db := y.get_data()
	var flat := func(d: PackedByteArray, i: int, j: int) -> bool:
		var o := (j * w + i) * 3
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var q := ((clampi(j + dj, 0, h - 1)) * w + clampi(i + di, 0, w - 1)) * 3
				if d[q] != d[o] or d[q + 1] != d[o + 1] or d[q + 2] != d[o + 2]:
					return false
		return true
	var se := 0.0
	var ne := 0
	var si := 0.0
	var ni := 0
	for j in h:
		for i in w:
			var o := (j * w + i) * 3
			var dd := (absi(da[o] - db[o]) + absi(da[o + 1] - db[o + 1]) + absi(da[o + 2] - db[o + 2])) / 3.0
			if flat.call(da, i, j) and flat.call(db, i, j):
				si += dd
				ni += 1
			else:
				se += dd
				ne += 1
	return [(se + si) / maxf(ne + ni, 1), se / maxf(ne, 1), si / maxf(ni, 1), float(ne) / maxf(ne + ni, 1)]


func _compare(scene: Dictionary, renders: Dictionary, a4: Image, out: String) -> void:
	var three: String = _a.get("three", "")
	var rows := []
	var res := {"tiles": {}}
	for t in scene.tiles:
		var ti = Image.load_from_file("%s_%s.png" % [three, t.id])
		if ti == null:
			print("engine_floor: FAIL no three.js render %s_%s.png" % [three, t.id])
			continue
		var g: Image = renders[t.id]
		var m := Sheet.mad(g, ti)
		var e := {"class": t["class"], "title": t.title, "mad": m}
		if t.id == "a-unlit":
			var s := _split(ti, g)
			var s4 := _split(ti, a4)
			e["edge"] = s[1]
			e["interior"] = s[2]
			e["edge_fraction"] = s[3]
			e["mad_msaa4"] = Sheet.mad(a4, ti)
			e["edge_msaa4"] = s4[1]
			e["interior_msaa4"] = s4[2]
		res.tiles[t.id] = e
		rows.append({"id": t.id, "mad": m, "cells": [
			{"image": ti, "label": "three.js (original's modules)"},
			{"image": g, "label": "Godot (port's realize/MToon)"},
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
				_verdict(r.id, r.mad, base_e, ta)]
		r["color"] = Color(1, 0.55, 0.45) if i < 3 else Color(1, 0.95, 0.7)
	print("engine_floor: tile | class | MAD(three, godot)")
	for id in res.tiles:
		var e: Dictionary = res.tiles[id]
		print("engine_floor: %-14s %s  %6.2f  %s" % [id, e["class"], e.mad, e.title])
	if ta != null:
		print("engine_floor: a-unlit split: edge %.2f, interior %.3f, edge fraction %.3f; port at MSAA 4x: MAD %.2f, edge %.2f, interior %.3f" % [
				ta.edge, ta.interior, ta.edge_fraction, ta.mad_msaa4, ta.edge_msaa4, ta.interior_msaa4])
	var f := FileAccess.open(out.path_join("engine_floor.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	var img: Image = await Sheet.render(self, "Engine floor tiles, 1920x1080: three.js (original) | Godot (port) | difference, worst first (MAD 0..255, half size)",
			["three.js", "Godot", "|godot - three|"], rows, Vector2i(480, 270))
	for p in Sheet.publish(img, out.path_join("engine-floor-contact-sheet.png"), "engine-floor"):
		print("engine_floor: saved ", p)
	quit()


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
		var lit := _half(lit_full)
		# the same view at the original's MSAA 4x: the AA setting's effect measured, not estimated
		get_root().msaa_3d = Viewport.MSAA_4X
		await _frames(12)
		var msaa4 := get_root().get_texture().get_image()
		get_root().msaa_3d = Viewport.MSAA_DISABLED
		sun.shadow_enabled = false
		await _frames(12)
		var unshadowed := _half(get_root().get_texture().get_image())
		sun.shadow_enabled = true
		# class pass
		for s in swaps:
			if s[1] >= 0:
				s[0].set_surface_override_material(s[1], s[2])
			else:
				s[0].material_override = s[2]
		_cam.environment = plain
		await _frames(12)
		var cls := _half(get_root().get_texture().get_image())
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


## Class fractions of a half-size class render: sky, far, unlit, toon shadowed, toon lit (they sum
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
