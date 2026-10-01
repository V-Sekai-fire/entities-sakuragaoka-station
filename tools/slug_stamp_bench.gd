# GPU cost of Slug stamp layers: a full-screen quad (2048 x 2048, unshaded slug.gdshaderinc) over
# keys built here and served through the fixture guest, GPU ms per frame from the viewport's
# measured render time (per case, the median of FRAMES frames after a warm-up, in each of ROUNDS
# rounds that alternate the case order; reported as min / median / max over the rounds):
#   stamps         one stamp layer, 8 x 8 grid, every cell at the contract's max 32 instances
#                  (ellipses and rects alternating, random affines, alpha 0.3): 2048 instances
#   curve stamps   the same transforms on a curve prototype (a 12-curve disc with a square hole)
#   plain 2048     the same 2048 ellipses / rects as plain Slug layers (outlines through the
#                  instance affines): what the content costs without stamps
#   plain 32       32 overlapping full-canvas plain layers: the same per-pixel depth as a stamp cell
#   no-stamp keys  plain 32 and a 1-layer key with the stamp code compiled in, and with
#                  SLUG_NO_STAMPS (the branch on texel 3.z removed): the cost to keys without stamps
#   empty          a key with no layers
#   godot --path . --script tools/slug_stamp_bench.gd     (needs a GPU; not --headless)
extends SceneTree

const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Stamps = preload("res://addons/sakuragaoka_station/core/slug/stamps.gd")
const FixtureGuest = preload("res://tools/slug_fixture/fixture_guest.gd")
const Fixture = preload("res://tools/slug_fixture/make_fixture.gd")
const Encoder = preload("res://tools/slug_fixture/encoder.gd")
const SIZE := 2048
const FRAMES := 60
const WARMUP := 10
const ROUNDS := 5
const G := 8
const DEPTH := 32

const SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
%s
#include "res://addons/sakuragaoka_station/core/slug/slug.gdshaderinc"
void fragment() {
	ALBEDO = slug_texture(slug_key, slug_frame, slug_uv, slug_wrap, UV).rgb;
}
"""


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("slug_stamp_bench: needs a GPU (run without --headless)")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var t0 := Time.get_ticks_msec()
	var content := _content()
	Guest.override = FixtureGuest.new(content.enc, content.stamps, false)
	Pack.reset()
	SlugAtlas.reset()
	print("slug_stamp_bench: content built in %d ms" % (Time.get_ticks_msec() - t0))
	_run.call_deferred()


static func _content() -> Dictionary:
	var e = Encoder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# the curve prototype: a disc of radius 0.5 em around (0.5, 0.5) with a square hole
	var proto_curves: Array = Encoder.circle(Vector2(0.5, 0.5), 0.5) + Encoder.polygon([Vector2(0.35, 0.35), Vector2(0.35, 0.65), Vector2(0.65, 0.65), Vector2(0.65, 0.35)])
	var proto_layer: Dictionary = e.layer("bench-proto/0", proto_curves, Color.WHITE)
	var proto_off: Vector2 = proto_layer._origin
	e.composite("bench-proto", [proto_layer], Fixture.FRAME)
	var unit_circle := Encoder.circle(Vector2.ZERO, 1.0)
	var unit_square := Encoder.polygon([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	var plain := []
	var ins := []
	var cins := []
	for j in G:
		for i in G:
			# cell (i, j) in UV is canvas em x [i, i + 1] / G, y [G - j - 1, G - j] / G
			var c := Vector2((i + 0.5) / G, 1.0 - (j + 0.5) / G)
			for k in DEPTH:
				var ell := k % 2 == 0
				var r := rng.randf_range(1.2, 2.2) / 64.0
				var at := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)) / 64.0
				var fwd := Transform2D(rng.randf() * TAU, Vector2(r, r * rng.randf_range(0.5, 1.0)), 0.0, at)
				var col := Color(rng.randf(), rng.randf(), rng.randf(), 0.3)
				var f2 := fwd if ell else fwd * Transform2D(0, Vector2(-0.5, -0.5))
				var it := Fixture._stamp(0 if ell else 1, 1 if ell else 2, f2, col, [], Vector2.ZERO)
				ins.append(it)
				var cf := fwd * Transform2D(0, Vector2(2.0, 2.0), 0, Vector2.ZERO) * Transform2D(0, -Vector2(0.5, 0.5))
				cins.append(Fixture._stamp(2, 0, cf, col, proto_curves.map(func(q): return [q[0] - proto_off.x, q[1] - proto_off.y, q[2] - proto_off.x, q[3] - proto_off.y, q[4] - proto_off.x, q[5] - proto_off.y]), proto_off))
				var outline := []
				for q in (unit_circle if ell else unit_square):
					var a: Vector2 = f2 * Vector2(q[0], q[1])
					var b: Vector2 = f2 * Vector2(q[2], q[3])
					var d: Vector2 = f2 * Vector2(q[4], q[5])
					outline.append([a.x, a.y, b.x, b.y, d.x, d.y])
				plain.append(e.layer("bench-plain/%d" % plain.size(), outline, col))
	e.composite("bench-plain", plain, Fixture.FRAME)
	var full := []
	for k in DEPTH:
		var fwd := Transform2D(rng.randf() * TAU, Vector2(0.8, rng.randf_range(0.75, 0.8)), 0.0, Vector2(0.5, 0.5))
		var outline := []
		for q in Encoder.circle(Vector2.ZERO, 1.0):
			var a: Vector2 = fwd * Vector2(q[0], q[1])
			var b: Vector2 = fwd * Vector2(q[2], q[3])
			var d: Vector2 = fwd * Vector2(q[4], q[5])
			outline.append([a.x, a.y, b.x, b.y, d.x, d.y])
		full.append(e.layer("bench-full/%d" % k, outline, Color(rng.randf(), rng.randf(), rng.randf(), 0.3)))
	e.composite("bench-full32", full, Fixture.FRAME)
	e.composite("bench-one", [full[0]], Fixture.FRAME)
	var st := {
		"protos": [[1, "", -1], [2, "", -1], [0, "bench-proto", 0]],
		"layers": [{"g": G, "instances": ins}, {"g": G, "instances": cins}],
		"keys": [{"key": {"type": "name", "value": "bench-stamps"}, "layers": [{"stamp": 0}], "frame": Fixture.FRAME},
				{"key": {"type": "name", "value": "bench-curve-stamps"}, "layers": [{"stamp": 1}], "frame": Fixture.FRAME},
				{"key": {"type": "name", "value": "bench-empty"}, "layers": [], "frame": Fixture.FRAME}],
	}
	return {"enc": e, "stamps": st}


func _view(mat: Material) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_root().add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	vp.add_child(mi)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	return vp


func _run() -> void:
	var a = SlugAtlas.shared()
	var s = Stamps.from_guest(Guest.shared(), a)
	if a == null or s == null:
		print("slug_stamp_bench: no atlas / stamps")
		quit(1)
		return
	var with := Shader.new()
	with.code = SHADER % ""
	var without := Shader.new()
	without.code = SHADER % "#define SLUG_NO_STAMPS"
	var cases := [["stamps (2048 ellipses/rects, 32 per cell)", "bench-stamps", with],
			["curve stamps (2048, 32 per cell)", "bench-curve-stamps", with],
			["plain 2048 layers (the same ellipses/rects)", "bench-plain", with],
			["plain 32 full-canvas layers", "bench-full32", with],
			["plain 32 full-canvas layers, SLUG_NO_STAMPS", "bench-full32", without],
			["plain 1 layer", "bench-one", with],
			["plain 1 layer, SLUG_NO_STAMPS", "bench-one", without],
			["empty key", "bench-empty", with]]
	print("slug_stamp_bench: %s, %d x %d, %d rounds (alternating order), %d frames per case per round after %d warm-up" % [
			RenderingServer.get_video_adapter_name(), SIZE, SIZE, ROUNDS, FRAMES, WARMUP])
	var views := []
	for c in cases:
		var sm := ShaderMaterial.new()
		sm.shader = c[2]
		var info = a.key_info(c[1], 64, 64)
		if info == null:
			info = {"layers": Vector2i(0, 0), "frame": Vector4(1, -1, 0, 1)}
		a.bind(sm, info, Vector2.ONE, Vector2.ZERO, false)
		s.bind(sm)
		c.append(info.layers.y)
		views.append(_view(sm))
	var medians := []
	for c in cases:
		medians.append([])
	for r in ROUNDS:
		var idx := range(cases.size())
		if r % 2 == 1:
			idx.reverse()
		for ci in idx:
			var vp: SubViewport = views[ci]
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var times := []
			for f in WARMUP + FRAMES:
				await RenderingServer.frame_post_draw
				if f >= WARMUP:
					times.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			times.sort()
			medians[ci].append(times[times.size() / 2])
	print("slug_stamp_bench: %-48s %9s %9s %9s  layers" % ["case (GPU ms per frame, per-round medians)", "min", "median", "max"])
	for ci in cases.size():
		var m: Array = medians[ci]
		m.sort()
		print("slug_stamp_bench: %-48s %9.3f %9.3f %9.3f  %d" % [cases[ci][0], m[0], m[m.size() / 2], m[m.size() - 1], cases[ci][3]])
	quit(0)
