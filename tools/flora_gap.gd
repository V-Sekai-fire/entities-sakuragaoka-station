# Every rendered tuft, weed, flower and ground-cover instance around the station plaza against the
# rendered ground under it, in metres. Two orthographic depth passes: the ground from above with
# the plants hidden, and from below a marker quad at each instance's base, drawn by the plant's own
# shader through the engine's MultiMesh path. Fails on a gap over --max, an instance with nothing
# drawn at its place, or a calibration miss; control: one tuft lifted 5 cm must fail.
#   godot --path . --resolution 2000x1200 --script tools/flora_gap.gd -- [--seed N] [--max 0.01] [--list 10]
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const MODULES := ["environment", "plaza"]
const REGION := Rect2(-12.0, -27.0, 40.0, 24.0)
const PLANT_GROUPS := ["plaza-plants", "plaza-tree"]
const ON_STEMS := ["bloom", "plaza-sway-dand"]
const TOP := 30.0
const BOTTOM := -10.0
const PAVE_Y := 0.02
const DEPTH := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float mm = clamp(round(-v.z / v.w * 1000.0), 0.0, 65535.0);
	float hi = floor(mm / 256.0);
	vec3 c = vec3(hi, mm - hi * 256.0, d > 0.0 ? 255.0 : 0.0) / 255.0;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
	ALPHA = 1.0;
}
"""

var _limit := 0.01
var _list := 10
var _seed := 1
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--seed": _seed = int(args[i + 1])
			"--max": _limit = float(args[i + 1])
			"--list": _list = int(args[i + 1])
	_run.call_deferred()


func _run() -> void:
	var ctx = Ctx.new(_seed)
	for n in MODULES:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	var kinds := {}
	var held := [0]
	ctx.static_root.traverse(func(o):
		if not o.is_instanced:
			return
		var kind := _kind(o)
		if kind == "":
			return
		o.name = "plant-%d" % kinds.size()
		kinds[o.name] = kind)
	var world := Node3D.new()
	get_root().add_child(world)
	var r = Realize.new()
	r.realize(ctx, world)
	await process_frame
	await process_frame
	r.finish()
	var probes := Node3D.new()
	get_root().add_child(probes)
	var items := []
	var drawn := {}
	for n in world.find_children("plant-*", "MultiMeshInstance3D", true, false):
		n.visible = false
		var probe := _probe(n)
		if probe == null:
			var mesh: Mesh = n.multimesh.mesh
			print("DEBUG ", n.name, " ", kinds[String(n.name)], " surfaces ", mesh.get_surface_count() if mesh else -1, " override ", n.material_override, " s0 ", mesh.surface_get_material(0) if mesh and mesh.get_surface_count() > 0 else null, " aabb ", mesh.get_aabb() if mesh else null)
			continue
		drawn[String(n.name)] = true
		probe.visible = false
		probes.add_child(probe)
		for i in n.multimesh.instance_count:
			var p: Vector3 = (n.global_transform * n.multimesh.get_instance_transform(i)).origin
			if REGION.has_point(Vector2(p.x, p.z)):
				items.append({"kind": kinds[String(n.name)], "p": p, "probe": probe, "i": i})
	ctx.static_root.traverse(func(o):
		if o.is_instanced and kinds.has(o.name) and not drawn.has(o.name):
			for t in o.instance_matrix:
				var p: Vector3 = (o.matrix_world * t).origin
				if REGION.has_point(Vector2(p.x, p.z)):
					held[0] += 1)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = REGION.size.y
	_cam.near = 0.05
	_cam.far = TOP - BOTTOM + 10.0
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2, 2)
	quad.extra_cull_margin = 16384.0
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = DEPTH
	quad.material_override = sm
	_cam.add_child(quad)
	get_root().add_child(_cam)
	_cam.make_current()
	var ground := await _pass(true)
	world.visible = false
	var base := {}
	for probe in probes.get_children():
		base[probe] = await _pass_one(probe)
	var cal = _at(ground, _cam_px(Vector3(6.0, 0.0, -12.0), true), true)
	var cal_ok: bool = cal != null and absf(cal - PAVE_Y) < 0.002
	for it in items:
		it["up"] = _cam_px(it.p, true)
		it["down"] = _cam_px(it.p, false)
	var res := _verdict(items, ground, base)
	print("plaza region %s: %d plant instances drawn, %d not drawn, %d on stems excluded" % [REGION, items.size(), held[0], res.stems])
	print("calibration: paving at (6, -12) reads %s m against %.3f: %s" % [cal, PAVE_Y, "ok" if cal_ok else "MISS"])
	print("max gap %.4f m (%s), over %.3f m: %d, nothing drawn at its place: %d" % [res.max, _house(res.max), _limit, res.over.size(), res.missing])
	for k in res.by_kind:
		print("  %-22s %5d over %d missing %d" % [k, res.by_kind[k][0], res.by_kind[k][1], res.by_kind[k][2]])
	res.over.sort_custom(func(x, y): return x[0] > y[0])
	for e in res.over.slice(0, _list):
		var it: Dictionary = items[e[1]]
		print("  gap %.4f %s at %.2f, %.2f, %.2f" % [e[0], it.kind, it.p.x, it.p.y, it.p.z])
	var ci := _isolated_tuft(items)
	var control_failed := false
	if ci >= 0:
		var it: Dictionary = items[ci]
		var mm: MultiMesh = it.probe.multimesh
		var t0: Transform3D = mm.get_instance_transform(it.i)
		mm.set_instance_transform(it.i, t0.translated(Vector3(0, 0.05, 0)))
		var lifted := base.duplicate()
		lifted[it.probe] = await _pass_one(it.probe)
		mm.set_instance_transform(it.i, t0)
		control_failed = not _verdict(items, ground, lifted).ok
	print("control one tuft +5 cm fails: %s" % control_failed)
	var ok: bool = res.ok and cal_ok and control_failed
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _kind(o) -> String:
	var m = o.materials()[0]
	var mn: String = m.name if m != null else ""
	if o.name.begins_with("env-flora-"):
		return "env-" + o.name.get_slice("-", 3)
	var p = o.parent()
	while p != null:
		if PLANT_GROUPS.has(p.name):
			if mn != "":
				return mn
			return "rosette" if m.map != null else ("bloom" if m.side == "front" else "stem")
		p = p.parent()
	return ""


func _probe(n: MultiMeshInstance3D) -> MultiMeshInstance3D:
	var src: Material = n.material_override
	if src == null and n.multimesh.mesh.get_surface_count() > 0:
		src = n.multimesh.mesh.surface_get_material(0)
	if not src is ShaderMaterial:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = (src as ShaderMaterial).shader
	var s := 0.25
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n.multimesh.instance_count
	for i in mm.instance_count:
		mm.set_instance_transform(i, n.multimesh.get_instance_transform(i))
	var probe := MultiMeshInstance3D.new()
	probe.multimesh = mm
	probe.transform = n.global_transform
	probe.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	return probe


func _pass(above: bool) -> Image:
	var c := REGION.get_center()
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0 if above else PI / 2.0), Vector3(c.x, TOP if above else BOTTOM, c.y))
	for i in 4:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.set_meta("above", above)
	return img


func _pass_one(probe: Node3D) -> Image:
	probe.visible = true
	var img := await _pass(false)
	probe.visible = false
	return img


func _cam_px(p: Vector3, above: bool) -> Vector2i:
	var c := REGION.get_center()
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0 if above else PI / 2.0), Vector3(c.x, TOP if above else BOTTOM, c.y))
	var v := _cam.unproject_position(Vector3(p.x, 0.0, p.z))
	return Vector2i(roundi(v.x), roundi(v.y))


func _height(img: Image, px: Vector2i):
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return null
	var col := img.get_pixel(px.x, px.y)
	if col.b8 < 128:
		return null
	var mm := col.r8 * 256 + col.g8
	return TOP - mm / 1000.0 if img.get_meta("above") else BOTTOM + mm / 1000.0


func _at(img: Image, px: Vector2i, center: bool):
	if center:
		return _height(img, px)
	var lo = null
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var h = _height(img, px + Vector2i(dx, dy))
			if h != null and (lo == null or h < lo):
				lo = h
	return lo


func _verdict(items: Array, ground: Image, base: Dictionary) -> Dictionary:
	var mx := -INF
	var over := []
	var missing := 0
	var stems := 0
	var by_kind := {}
	for i in items.size():
		var it: Dictionary = items[i]
		if ON_STEMS.has(it.kind):
			stems += 1
			continue
		var bk: Array = by_kind.get(it.kind, [0, 0, 0])
		bk[0] += 1
		by_kind[it.kind] = bk
		var g = _at(ground, it.up, true)
		var b = _at(base[it.probe], it.down, false)
		if g == null or b == null:
			missing += 1
			bk[2] += 1
			continue
		var gap: float = b - g
		mx = maxf(mx, gap)
		if gap > _limit:
			over.append([gap, i])
			bk[1] += 1
	return {"max": mx, "over": over, "missing": missing, "stems": stems, "by_kind": by_kind,
			"ok": over.is_empty() and missing == 0 and by_kind.size() > 0}


func _isolated_tuft(items: Array) -> int:
	var cells := {}
	for i in items.size():
		var c := Vector2i(floori(items[i].p.x), floori(items[i].p.z))
		cells[c] = cells.get(c, []) + [i]
	var best := -1
	var best_d := 0.0
	for i in items.size():
		if not String(items[i].kind).contains("grass"):
			continue
		var d := 1.0
		var c := Vector2i(floori(items[i].p.x), floori(items[i].p.z))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in cells.get(c + Vector2i(dx, dz), []):
					if j != i:
						d = minf(d, Vector2(items[i].p.x - items[j].p.x, items[i].p.z - items[j].p.z).length())
		if d > best_d:
			best_d = d
			best = i
	return best


func _house(m: float) -> String:
	var mm := absf(m) * 1000.0
	for e in [[66.0, "soda cans"], [42.7, "golf balls"], [10.5, "AAA batteries"], [7.0, "pencils"], [1.52, "pennies"]]:
		if mm >= e[0]:
			return "%.1f %s" % [mm / e[0], e[1]]
	return "%.1f credit cards" % (mm / 0.76)
