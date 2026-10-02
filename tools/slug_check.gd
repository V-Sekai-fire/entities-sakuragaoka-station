# Slug and baked-mesh checks against the hand-made fixture (tools/slug_fixture/), served through
# slug.elf's API by fixture_guest.gd, so the port's own code paths run: core/slug/atlas.gd and
# baked.gd read the guest's arrays, realize.gd picks modes, slug.gdshaderinc draws.
#   CPU: the atlas table; a card bake (clipped through slug_decal: a known UV point lands at a known
#        3D position, the area matches; a card over one cell of a 2 x 2 atlas stays on the card and
#        holds only that cell, which the old extrapolating map_card fails); a decal (area and lift); realize_part over one object per mode (stats and
#        materials).
#   GPU: each fixture key through slug.gdshaderinc on a quad into a 256 x 256 SubViewport (64 px
#        canvas, 4 screen px a canvas px), known pixels against a CPU port of render.hpp's
#        coverage: inside, outside, the hole, the gradient midpoint, layered source-over, and an
#        edge pixel with partial coverage; then the Slug MToon cutout variant (the hole discards).
#   Stamp layers (core/slug/stamps.gd, fx-stamps): the wire arrays and textures (CPU); on the GPU
#        against reference.gd's instance-by-instance expansion: inside, outside, paint order in an
#        overlap, AA edges (also against a supersampled ground truth), an instance straddling cell
#        lines drawn whole, a curve prototype (body and hole), the whole image; the distance fade
#        (a far view lands on the cell means, and does not with the fade off); a negative control
#        (a corrupted cell list must fail the point checks); the MToon variant with stamps.
#        Rung 0: under each contact-sheet residual its floor (the GPU against itself, the CPU
#        reference against itself, the reference replayed through the 8-bit sRGB output path) and a
#        flat-fill sweep of that path; the sheet (user://slug_check_stamps_contact_sheet.png) sorts
#        cases by residual - floor and the table is printed.
#        The GPU half needs a rendering driver; under --headless it is skipped and says so.
#   godot --path . --script tools/slug_check.gd          (CPU + GPU)
#   godot --headless --path . --script tools/slug_check.gd (CPU only)
extends SceneTree

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const FixtureGuest = preload("res://tools/slug_fixture/fixture_guest.gd")
const LegacyMapCard = preload("res://tools/slug_fixture/legacy_map_card.gd")
const Fixture = preload("res://tools/slug_fixture/make_fixture.gd")
const Ref = preload("res://tools/slug_fixture/reference.gd")
const Stamps = preload("res://addons/sakuragaoka_station/core/slug/stamps.gd")
const Encoder = preload("res://tools/slug_fixture/encoder.gd")
const SIZE := 256

var _fails := 0
var _checks := 0
var _guest
var _stamps          # core/slug/stamps.gd over the fixture
var _pts := {}       # stamp check name -> [x, y, what]
const FADE := Vector2(0.75, 1.5)   # stamps.gd's default slug_stamp_fade
const DIFF_GAIN := 8


func _initialize() -> void:
	_guest = FixtureGuest.new()
	Guest.override = _guest
	Pack.reset()
	SlugAtlas.reset()
	Baked.reset()
	_cpu()
	_stamps_cpu()
	if DisplayServer.get_name() == "headless":
		print("slug_check: GPU checks SKIPPED (--headless has no renderer; run without --headless)")
		_done()
		return
	_gpu.call_deferred()


func _done() -> void:
	# teardown: the kernels' Sandbox and its ELF must not outlive the run ("resources still in use")
	Kernels.shutdown()
	Guest.shutdown()
	_check(not ResourceLoader.has_cached(Kernels.ELF) and not ResourceLoader.has_cached(Guest.ELF),
			"teardown: no Sandbox program (slug_kernels.elf, slug.elf) left loaded")
	print("slug_check: %s (%d checks, %d failed)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("slug_check: %s %s" % ["ok  " if ok else "FAIL", what])


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# ------------------------------------------------------------------------------------- CPU

func _cpu() -> void:
	var a = SlugAtlas.shared()
	_check(a != null, "atlas built from the guest's slug_atlas()")
	if a == null:
		return
	for k in [["fx-circle", 1], ["fx-hole", 1], ["fx-grad", 1], ["fx-layers", 2]]:
		var info = a.key_info(k[0], 64, 64)
		_check(info != null and info.layers.y == k[1], "%s: %d layer(s) (%s)" % [k[0], k[1], str(info.layers) if info else "null"])
	_check(a.key_info("fx-missing", 64, 64) == null, "a key not in the atlas is null")
	_check(a.frame_of("fx-circle", 64, 64).is_equal_approx(Vector4(1, -1, 0, 1)), "fx-circle frame from the guest: em = (0, 1) + uv * (1, -1)")
	_check(a.frame_of("fx-layers", 64, 32).is_equal_approx(Vector4(1, -0.5, 0, 0.5)), "fx-layers (no frame): nanosvg default 1/width, y down")
	var b = Baked.shared()
	_check(b.mode("fx-card") == "mesh" and b.mode("fx-circle") == "slug" and b.mode("fx-mean") == "mean" and b.mode("fx-hole") == "",
			"modes from slug_cost: fx-card mesh, fx-circle slug, fx-mean mean, fx-hole none")
	var bm = b.get_mesh("fx-card")
	_check(bm != null and bm.indices.size() == 15 and bm.overlay == Vector2i(12, 3) and not bm.radial, "fx-card mesh: 5 triangles, overlay at 12")
	_check(b.get_mesh("fx-radial").radial, "fx-radial mesh flagged radial")
	_card(bm)
	_decal()
	_realize()


## A card P(u, v) = O + u A + v B over geometry UV rect uv0..uv1, Godot-wound.
func _card_src(uv0: Vector2, uv1: Vector2) -> Dictionary:
	var uv := PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)])
	var pos := PackedVector3Array()
	for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		pos.append(CARD_O + CARD_A * k.x + CARD_B * k.y)
	return {"pos": pos, "nor": PackedVector3Array(), "uv": uv, "idx": PackedInt32Array([0, 2, 1, 0, 3, 2])}


const CARD_O := Vector3(1, 2, 3)
const CARD_A := Vector3(2, 0, 0.5)
const CARD_B := Vector3(0, 1.5, 0)


## Whether every vertex of a card result lies on the card quad (plane and bounds, 1e-5).
static func _on_card(r: Dictionary) -> bool:
	var n := CARD_A.cross(CARD_B).normalized()
	for p in r.pos:
		var d: Vector3 = p - CARD_O
		var u := d.dot(CARD_A) / CARD_A.length_squared()
		var v := d.dot(CARD_B) / CARD_B.length_squared()
		if absf(d.dot(n)) > 1e-5 or u < -1e-5 or u > 1.0 + 1e-5 or v < -1e-5 or v > 1.0 + 1e-5:
			return false
	return true


static func _area(r: Dictionary) -> float:
	var a := 0.0
	for t in range(0, r.pos.size(), 3):
		a += (r.pos[t + 1] - r.pos[t]).cross(r.pos[t + 2] - r.pos[t]).length() * 0.5
	return a


func _card(bm: Dictionary) -> void:
	var b = Baked.shared()
	var quad := CARD_A.cross(CARD_B).length()
	var src := _card_src(Vector2(0, 0), Vector2(1, 1))
	var r: Dictionary = b.map_decal("fx-card", src, Vector4(1, 1, 0, 0), false, 0.0, 0.5)
	# cutout bake at alpha_test 0.5: the overlay triangle (alpha 0.5) turns opaque base, no overlay
	_check(r.overlay_from == r.tri_paint.size() and _near(_area(r), quad * (0.125 + 0.25 + 0.02), 1e-4),
			"card bake: cutout, no overlay, area = baked area (%.4f of %.4f)" % [_area(r), quad])
	var want := CARD_O + CARD_A * 0.25 + CARD_B * 0.5
	var found := false
	for p in r.pos:
		found = found or p.is_equal_approx(want)
	_check(found, "card bake: UV (0.25, 0.5) lands at %s, unlifted" % want)
	var cn := Baked.face_normal(src.pos[0], src.pos[2], src.pos[1])
	var facing := true
	for t in range(0, r.pos.size(), 3):
		facing = facing and Baked.face_normal(r.pos[t], r.pos[t + 1], r.pos[t + 2]).dot(cn) > 0.99
	_check(facing, "card bake: every triangle faces as the card")
	# one cell of a 2 x 2 atlas: UVs over [0.5, 1] x [0.5, 1] hold only the white square (paint 3)
	var cells = b.get_mesh("fx-cells")
	var cs := _card_src(Vector2(0.5, 0.5), Vector2(1, 1))
	var rc: Dictionary = b.map_decal("fx-cells", cs, Vector4(1, 1, 0, 0), false, 0.0, 0.5)
	var only: bool = rc.tri_paint.size() > 0
	for p in rc.tri_paint:
		only = only and p == 3
	_check(_on_card(rc), "atlas cell card: every vertex on the card quad (plane and bounds within 1e-5)")
	_check(only, "atlas cell card: only cell (0.5, 0.5)'s content (%d triangles, paints %s)" % [rc.tri_paint.size(), str(rc.tri_paint)])
	_check(_near(_area(rc), quad * 0.36, 1e-4), "atlas cell card: area 0.36 of the card (%.4f of %.4f)" % [_area(rc), quad])
	# negative control: the old extrapolating mapping fails the same test
	var old: Dictionary = LegacyMapCard.map_card(cs, cells, Vector4(1, 1, 0, 0))
	var old_only := true
	for p in old.tri_paint:
		old_only = old_only and p == 3
	_check(not (_on_card(old) and old_only), "negative control: the old map_card puts %d triangles, cells %s, off the card" % [
			old.tri_paint.size(), str(old.tri_paint)])


## A 2 x 2 m plane at z = 0 with UV 0..1 and the texture repeated 2 x 2: four tiles of 1 m each.
func _decal() -> void:
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var pos := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 2, 0), Vector3(0, 2, 0)])
	var src := {"pos": pos, "nor": PackedVector3Array(), "uv": uv, "idx": PackedInt32Array([0, 2, 1, 0, 3, 2])}
	var r: Dictionary = Baked.shared().map_decal("fx-card", src, Vector4(2, 2, 0, 0), true, 1.0)
	_check(not r.has("capped"), "decal: under the cap")
	var base := 0.0
	var over := 0.0
	var lift_ok := true
	var facing := true
	for t in range(0, r.pos.size(), 3):
		var area: float = (r.pos[t + 1] - r.pos[t]).cross(r.pos[t + 2] - r.pos[t]).length() * 0.5
		var ovl: bool = t / 3 >= r.overlay_from
		if ovl:
			over += area
		else:
			base += area
		for k in 3:
			lift_ok = lift_ok and _near(r.pos[t + k].z, Baked.OVERLAY_LIFT if ovl else Baked.DECAL_LIFT, 1e-6)
		facing = facing and Baked.face_normal(r.pos[t], r.pos[t + 1], r.pos[t + 2]).z > 0.99
	# per tile: square 0.5 x 0.25 + strip 1 x 0.25 = 0.375; overlay 0.02. Four 1 m tiles.
	_check(_near(base, 1.5, 1e-4) and _near(over, 0.08, 1e-4), "decal: base area %.5f (want 1.5), overlay %.5f (want 0.08)" % [base, over])
	_check(lift_ok, "decal: lifted %.3f m (overlay %.3f m) along the normal" % [Baked.DECAL_LIFT, Baked.OVERLAY_LIFT])
	_check(facing, "decal: every triangle faces +z with the plane")
	_check(r.tri_paint.size() >= 20, "decal: %d triangles (5 baked x 4 tiles, more where the plane's diagonal splits them)" % r.tri_paint.size())


func _tex(key: String, rep := Vector2.ONE, wrap := false) -> T.Tex:
	var t := T.Tex.new()
	t.width = 64
	t.height = 64
	t.repeat = rep
	t.user_data["key"] = key
	if wrap:
		t.wrap_s = "repeat"
		t.wrap_t = "repeat"
	return t


func _mat(key: String, cut: bool, rep := Vector2.ONE, wrap := false) -> T.Mat:
	var m := T.Mat.new()
	m.type = "toon"
	m.color = Color(1, 1, 1)
	m.map = _tex(key, rep, wrap)
	if cut:
		m.alpha_test = 0.5
		m.side = "double"
	return m


func _quad() -> T.Geometry:
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(PackedFloat32Array([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]), 3))
	g.set_attribute("normal", T.Attr.new(PackedFloat32Array([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]), 3))
	g.set_attribute("uv", T.Attr.new(PackedFloat32Array([0, 0, 1, 0, 1, 1, 0, 1]), 2))
	g.set_index(PackedInt32Array([0, 1, 2, 0, 2, 3]))
	return g


func _realize() -> void:
	var objs := []
	var specs := [["A card fx-card", "fx-card", true], ["B card fx-hole", "fx-hole", true], ["C fx-circle", "fx-circle", false],
			["D fx-card decal", "fx-card", false], ["E fx-missing", "fx-missing", false], ["F fx-radial", "fx-radial", false],
			["G card fx-mean", "fx-mean", true]]
	var x := 0.0
	for s in specs:
		var m := _mat(s[1], s[2], Vector2(2, 2) if s[0].begins_with("D") else Vector2.ONE, s[0].begins_with("D"))
		var o := T.MeshObj.new(_quad(), m)
		o.name = s[0]
		o.position = Vector3(x, 0, 0)
		x += 2.0
		o.update_matrix_world()
		objs.append(o)
	var inst := T.InstancedMesh.new(_quad(), _mat("fx-card", true), 3)
	inst.name = "H instanced card fx-card"
	for i in 3:
		inst.set_matrix_at(i, Transform3D(Basis(), Vector3(i, 5, 0)))
	inst.update_matrix_world()
	objs.append(inst)
	var root := Node3D.new()
	get_root().add_child(root)
	var r = Realize.new()
	r.realize_part(objs, root)
	r.finish()
	var s: Dictionary = r.stats
	print("slug_check: realize stats: slugged %d, fallback %d, held %d, modes mesh/slug/mean %d/%d/%d, baked cards %d, decals %d, %d triangles, %d ramps" % [
			s.slugged, s.fallback, s.held, s.mode_mesh, s.mode_slug, s.mode_mean, s.baked_cards, s.baked_decals, s.baked_tris, s.ramps])
	_check(s.mode_mesh == 3 and s.mode_slug == 2 and s.mode_mean == 3, "realize: modes mesh 3 (A, D, H), slug 2 (B, C), mean 3 (E, F, G)")
	_check(s.slugged == 2 and s.fallback == 2 and s.held == 1, "realize: 2 slugged (B, C), 2 on the mean (E, F), 1 card held (G)")
	_check(s.baked_cards == 2 and s.baked_decals == 1, "realize: 2 baked cards (A, H), 1 decal (D)")
	_check(s.ramps == 1, "realize: the strip's linear gradient became one palette ramp")
	var shaders := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		for i in n.mesh.get_surface_count():
			var mat = n.mesh.surface_get_material(i)
			if mat is ShaderMaterial:
				shaders[n.name + "/" + str(i)] = mat.shader.resource_path.get_file()
	var slug_c := false
	var slug_b := false
	for k in shaders:
		slug_c = slug_c or (k.begins_with("C") and shaders[k] == "mtoon_slug.gdshader")
		slug_b = slug_b or (k.begins_with("batch") and shaders[k] == "mtoon_slug_cutout_cull_off.gdshader")
	_check(slug_c, "realize: C is drawn with mtoon_slug.gdshader")
	_check(slug_b, "realize: B (a card) is batched with mtoon_slug_cutout_cull_off.gdshader")
	var mm := false
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		mm = mm or (n.multimesh.mesh.get_surface_count() == 1 and n.material_override == null)
	_check(mm, "realize: H's MultiMesh carries the baked card (one cutout surface)")
	root.queue_free()


# ------------------------------------------------------------------------- CPU reference

## render.hpp Sampler::renderSample (every curve, no bands) at shape-em point (rx, ry).
static func _coverage(curves: Array, rx: float, ry: float, ppe: float) -> float:
	return Ref.coverage(curves, rx, ry, Vector2(ppe, ppe))


## The fixture key's premultiplied colour at screen pixel (px, py) of the 256 px quad.
func _reference(key: String, px: int, py: int) -> Color:
	var em := Vector2((px + 0.5) / SIZE, (py + 0.5) / SIZE)  # canvas y down: screen row = canvas row
	var comp: Dictionary
	for c in _guest.enc.composites:
		if c.key.value == key:
			comp = c
	var shapes := {}
	for s in _guest.enc.shapes:
		shapes[s.key] = s.curves
	var acc := Color(0, 0, 0, 0)
	for l in comp.layers:
		var p := em - Vector2(l.transform[0], l.transform[1])
		var cov := _coverage(shapes[l.key.value], p.x, p.y, float(SIZE))
		var col := Color(l.color[0], l.color[1], l.color[2], l.color[3])
		if int(l.gradient_id) > 0:
			var g: Dictionary = _guest.enc.gradients[l.gradient_id - 1]
			var m: Array = g.transform
			var t := clampf(m[0] * p.x + m[2] * p.y + m[4], 0, 1)
			var c0: Array = g.stops[0].color
			var c1: Array = g.stops[1].color
			col = Color(c0[0], c0[1], c0[2]).lerp(Color(c1[0], c1[1], c1[2]), t)
			col.a = l.color[3]
		var a := col.a * cov
		acc = Color(col.r * a + acc.r * (1 - a), col.g * a + acc.g * (1 - a), col.b * a + acc.b * (1 - a), a + acc.a * (1 - a))
	return acc


# ------------------------------------------------------------------------------------- GPU

const TEST_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://addons/sakuragaoka_station/core/slug/slug.gdshaderinc"
void fragment() {
	ALBEDO = slug_texture(slug_key, slug_frame, slug_uv, slug_wrap, UV).rgb;  // premultiplied over black
}
"""


## A 2 x 2 quad filling an orthographic 256 px view, UVs in three.js convention (v = 1 at the top).
func _view(mat: Material, bg: Color, light: bool, cam_size := 2.0) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	if light:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.3, 0.2, 0)
		vp.add_child(sun)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1)])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	vp.add_child(mi)
	return vp


func _slug_material(shader: Shader, key: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	var a = SlugAtlas.shared()
	a.bind(sm, a.key_info(key, 64, 64), Vector2.ONE, Vector2.ZERO, false)
	return sm


func _gpu() -> void:
	var sh := Shader.new()
	sh.code = TEST_SHADER
	var keys := ["fx-circle", "fx-hole", "fx-grad", "fx-layers"]
	var views := {}
	for k in keys:
		views[k] = _view(_slug_material(sh, k), Color(0, 0, 0), false)
	var mt := _slug_material(load("res://addons/sakuragaoka_station/core/slug/mtoon_slug_cutout_cull_off.gdshader"), "fx-hole")
	mt.set_shader_parameter("_AlphaCutoutEnable", 1.0)
	mt.set_shader_parameter("_Cutoff", 0.5)
	var bg := Color(1, 0, 1)
	var mview := _view(mt, bg, true)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	print("slug_check: rendering with %s" % RenderingServer.get_current_rendering_driver_name())
	var img := {}
	for k in keys:
		img[k] = views[k].get_texture().get_image()
	var mimg: Image = mview.get_texture().get_image()
	img["fx-hole"].save_png("user://slug_check_hole.png")
	var pts := [
		["fx-circle", 128, 128, "inside the circle"], ["fx-circle", 10, 10, "outside the circle"],
		["fx-circle", 208, 128, "the circle's right edge (partial coverage)"],
		["fx-hole", 66, 194, "the square, below the hole"], ["fx-hole", 130, 98, "the hole"], ["fx-hole", 10, 10, "outside the square"],
		["fx-grad", 128, 128, "the gradient midpoint"], ["fx-grad", 8, 128, "the gradient's red end"], ["fx-grad", 248, 60, "the gradient's blue end"],
		["fx-layers", 128, 128, "red at alpha 0.5 over green"], ["fx-layers", 10, 10, "green alone"],
	]
	for p in pts:
		var got: Color = (img[p[0]] as Image).get_pixel(p[1], p[2]).srgb_to_linear()
		var want := _reference(p[0], p[1], p[2])
		var ok := _near(got.r, want.r, 0.02) and _near(got.g, want.g, 0.02) and _near(got.b, want.b, 0.02)
		_check(ok, "%s at (%d, %d), %s: GPU (%.3f %.3f %.3f), reference (%.3f %.3f %.3f)" % [
				p[0], p[1], p[2], p[3], got.r, got.g, got.b, want.r, want.g, want.b])
	var edge := _reference("fx-circle", 208, 128)
	_check(edge.a > 0.2 and edge.a < 0.8, "the edge pixel is partial: reference coverage %.3f" % edge.a)
	var mid := _reference("fx-grad", 128, 128)
	_check(_near(mid.r, 0.5, 0.01) and _near(mid.b, 0.5, 0.01), "the gradient midpoint is half red, half blue (%.3f, %.3f)" % [mid.r, mid.b])
	var hole_px: Color = mimg.get_pixel(130, 98)
	var fill_px: Color = mimg.get_pixel(66, 194)
	_check(hole_px.is_equal_approx(bg), "MToon Slug cutout: the hole discards to the background (%s)" % hole_px)
	_check(not fill_px.is_equal_approx(bg) and fill_px.b > fill_px.r + 0.2, "MToon Slug cutout: the square is drawn, lit blue (%s)" % fill_px)
	_check(mimg.get_pixel(10, 10).is_equal_approx(bg), "MToon Slug cutout: outside the square discards")
	await _stamps_gpu()
	_done()


# ------------------------------------------------------------------------------ stamp layers

func _sinst(name: String) -> Dictionary:
	return _guest.stamps.layers[1].instances[_guest.stamps.special[name]]


## Screen pixel (256 px view) of canvas em point em.
static func _pix(em: Vector2) -> Vector2i:
	return Vector2i(floori(em.x * SIZE), floori(em.y * SIZE))


static func _em(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) / SIZE, (y + 0.5) / SIZE)


## The fx-stamps cell (index j * G + i) of screen pixel (x, y): uv = (em.x, 1 - em.y).
static func _cell_of(x: int, y: int) -> int:
	var g := Fixture.STAMP_GRID
	var e := _em(x, y)
	return clampi(floori((1.0 - e.y) * g), 0, g - 1) * g + clampi(floori(e.x * g), 0, g - 1)


func _icov(name: String, x: int, y: int) -> float:
	return Ref.stamp_coverage(_sinst(name), _em(x, y), Vector2(1.0 / SIZE, 0), Vector2(0, 1.0 / SIZE))


## A pixel in instance a's bbox meeting test(x, y), or (-1, -1).
func _find(a: String, test: Callable) -> Vector2i:
	var b: Rect2 = _sinst(a).bbox
	for y in range(maxi(floori(b.position.y * SIZE), 0), mini(ceili(b.end.y * SIZE), SIZE)):
		for x in range(maxi(floori(b.position.x * SIZE), 0), mini(ceili(b.end.x * SIZE), SIZE)):
			if test.call(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## fx-stamps' reference at screen pixel (x, y): the stamp layer expanded instance by instance
## (reference.gd raster), over the grey canvas.
func _stamp_ref(x: int, y: int, g = null) -> Color:
	var s: Color = (g if g != null else _guest).stamp_raster[1][y * SIZE + x]
	var b := Fixture.STAMP_BASE
	return Color(s.r + b.r * (1 - s.a), s.g + b.g * (1 - s.a), s.b + b.b * (1 - s.a), 1)


func _mean_ref(cell: int) -> Color:
	var m: Color = _guest.stamp_mean(1, cell)
	var b := Fixture.STAMP_BASE
	return Color(m.r + b.r * (1 - m.a), m.g + b.g * (1 - m.a), m.b + b.b * (1 - m.a), 1)


static func _diff(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


func _stamps_cpu() -> void:
	var a = SlugAtlas.shared()
	if a == null:
		return
	var r: Dictionary = _guest.call_fn("slug_atlas")
	_stamps = Stamps.build(r, a)
	var st: Dictionary = _guest.stamps
	var insts: Array = st.layers[1].instances
	_check(_stamps != null and _stamps.stamp_layer_count == 2 and _stamps.instance_count == insts.size(),
			"stamps: built, %d stamp layers, %d instances (%d random ellipses/rects, %d placed by hand)" % [
			_stamps.stamp_layer_count if _stamps else 0, _stamps.instance_count if _stamps else 0, st.random, insts.size() - st.random])
	if _stamps == null:
		return
	var info = a.key_info("fx-stamps", 64, 64)
	_check(info != null and info.layers.y == 2, "fx-stamps: 2 layers (grey canvas, stamp layer)")
	var li: int = info.layers.x + 1
	_check(_stamps.stamp_of_layer.get(li, -1) == 1, "fx-stamps layer 1 (blend 100, slot 14 = 1) is stamp layer 1")
	var t := li * Stamps.LAYER_TEXELS + 3
	var d3: Color = a.data.get_image().get_pixel(t % Stamps.DATA_WIDTH, t / Stamps.DATA_WIDTH)
	_check(d3.b == -2.0 and d3.a == 1.0, "data texel 3 marked (z %.0f, w %.0f): stamp index 1 is also gradient id 1, so atlas.gd wrote gradient fields there" % [d3.b, d3.a])
	# the cell texture round trip
	var lists := Encoder.bin_cells(Fixture.STAMP_GRID, insts)
	var cb: PackedByteArray = r.stamp_cells
	var sl: PackedInt32Array = r.stamp_layers
	var base := sl[5 + 1]
	var same := true
	var deepest := 0
	for c in lists.size():
		var f := Stamps.cell_fields(cb, base + c)
		same = same and f.y == lists[c].size()
		deepest = maxi(deepest, f.y)
		for k in f.y:
			var e := 2 * base + f.x + k
			var v := Stamps.cell_fields(cb, e / 2)
			same = same and (v.x if e % 2 == 0 else v.y) == lists[c][k]
	_check(same, "stamp_cells decode to the binned lists (paint order), max %d per cell (wire max %d)" % [deepest, sl[5 + 4]])
	_check(lists[st.deep_cell].size() == 32, "the deep cell (%d) lists exactly 32 instances (%d)" % [st.deep_cell, lists[st.deep_cell].size()])
	var s4 := 0
	for l in lists:
		s4 += 1 if st.special.S4 in l else 0
	_check(s4 >= 3, "S4 straddles cell lines: listed in %d cells" % s4)
	# test pixels
	var s1c := _pix(_sinst("S1").fwd * Vector2(0.5, 0.5))
	_pts["inside"] = [s1c.x, s1c.y, "inside S1 (rect)"]
	var ov := _find("S2", func(x, y): return _icov("S1", x, y) >= 1.0 and _icov("S2", x, y) >= 1.0)
	_pts["overlap"] = [ov.x, ov.y, "S2 (blue ellipse) over S1 (red rect): paint order"]
	_check(ov.x >= 0, "an S1/S2 overlap pixel exists (%s)" % ov)
	var aa := _find("S3", func(x, y): var c := _icov("S3", x, y); return c > 0.35 and c < 0.65)
	_pts["aa_rect"] = [aa.x, aa.y, "S3 (sheared rect) AA edge"]
	var aa2 := _find("S4", func(x, y): var c := _icov("S4", x, y); return c > 0.35 and c < 0.65)
	_pts["aa_ellipse"] = [aa2.x, aa2.y, "S4 (rotated ellipse) AA edge"]
	for k in [["S3", aa], ["S4", aa2]]:
		var c := _icov(k[0], k[1].x, k[1].y)
		var gt := Ref.stamp_supersampled(_sinst(k[0]), _em(k[1].x, k[1].y), Vector2(1.0 / SIZE, 0), Vector2(0, 1.0 / SIZE))
		_check(k[1].x >= 0 and absf(c - gt) < 0.1, "%s AA at %s: analytic coverage %.3f, 32 x 32 supersampled %.3f" % [k[0], k[1], c, gt])
	_pts["straddle_l"] = [95, 72, "S4 left of the x = 24 px cell line"]
	_pts["straddle_r"] = [96, 72, "S4 right of the x = 24 px cell line"]
	_check(_cell_of(95, 72) != _cell_of(96, 72) and _icov("S4", 95, 72) >= 1.0 and _icov("S4", 96, 72) >= 1.0,
			"(95, 72) and (96, 72) are inside S4, in cells %d and %d" % [_cell_of(95, 72), _cell_of(96, 72)])
	_pts["outside"] = [240, 16, "the empty cell (grey canvas only)"]
	var body := _pix(_sinst("S5").fwd * (Vector2(12, 12) / 64.0))
	var hole := _pix(_sinst("S5").fwd * (Vector2(32, 24) / 64.0))
	_pts["curve_body"] = [body.x, body.y, "S5 (curve prototype) body"]
	_pts["curve_hole"] = [hole.x, hole.y, "S5 (curve prototype) hole"]
	_check(_icov("S5", body.x, body.y) >= 0.99 and _icov("S5", hole.x, hole.y) <= 0.01, "S5 reference: body covered, hole empty")
	var mix := _find("S7", func(x, y): return _icov("S5", x, y) >= 1.0 and _icov("S6", x, y) >= 1.0 and _icov("S7", x, y) >= 1.0)
	_pts["mixed"] = [mix.x, mix.y, "a mixed run: rect S7 over ellipse S6 over curve S5"]
	if mix.x >= 0:
		var fwd := Color(0, 0, 0, 0)
		var rev := Color(0, 0, 0, 0)
		for n in ["S5", "S6", "S7"]:
			fwd = Ref.over(fwd, _sinst(n).color, 1.0)
		for n in ["S7", "S6", "S5"]:
			rev = Ref.over(rev, _sinst(n).color, 1.0)
		_check(_diff(fwd, rev) > 0.1, "mixed run pixel %s: order matters (%.3f between orders)" % [mix, _diff(fwd, rev)])
	else:
		_check(false, "a pixel under S5, S6 and S7 exists")
	var g8: Dictionary = _sinst("S8")
	for q in [[Vector2(0.2, 0.5), "t = 0.2"], [Vector2(0.8, 0.5), "t = 0.8"],
			[Vector2(0.5, 0.15), "t = 0.5 (near one long edge)"], [Vector2(0.5, 0.85), "t = 0.5 (near the other)"]]:
		var p := _pix(g8.fwd * q[0])
		_pts["grad %s" % q[1]] = [p.x, p.y, "S8 gradient %s" % q[1]]
	var ga: Array = _pts["grad t = 0.5 (near one long edge)"]
	var gb: Array = _pts["grad t = 0.5 (near the other)"]
	var gd := Vector2(ga[0], ga[1]).distance_to(Vector2(gb[0], gb[1]))
	var gr := _stamp_ref(ga[0], ga[1])
	_check(_diff(gr, _stamp_ref(gb[0], gb[1])) < 0.05 and gr.g > 0.8 and gd > 8.0,
			"S8 reference: both t = 0.5 points green though %.1f px apart across the rotated rect" % gd)
	# the deep cell: column 160 + k covered by rects 0..k
	var dist := true
	for k in range(1, 32):
		dist = dist and _diff(_stamp_ref(160 + k, 144), _stamp_ref(159 + k, 144)) > 0.02
	var no31 := Color(0, 0, 0, 0)
	for k in 31:
		no31 = Ref.over(no31, insts[st.deep[0] + k].color, 1.0)
	var bg := Fixture.STAMP_BASE
	no31 = Color(no31.r + bg.r * (1 - no31.a), no31.g + bg.g * (1 - no31.a), no31.b + bg.b * (1 - no31.a))
	_check(dist and _diff(no31, _stamp_ref(191, 144)) > 0.1, "deep cell reference: each of the 32 rects changes its column; dropping the 32nd moves column 191 by %.3f" % _diff(no31, _stamp_ref(191, 144)))


## The point checks on an fx-stamps render; {name: [ok, message]}.
func _stamp_points(img: Image) -> Dictionary:
	var out := {}
	for k in _pts:
		var p: Array = _pts[k]
		if p[0] < 0:
			out[k] = [false, "%s: no pixel" % p[2]]
			continue
		var got: Color = img.get_pixel(p[0], p[1]).srgb_to_linear()
		var want := _stamp_ref(p[0], p[1])
		out[k] = [_diff(got, want) <= 0.02, "fx-stamps at (%d, %d), %s: GPU (%.3f %.3f %.3f), reference (%.3f %.3f %.3f)" % [
				p[0], p[1], p[2], got.r, got.g, got.b, want.r, want.g, want.b]]
	var worst := 0.0
	var bad := 0
	for k in 32:
		var dd := _diff(img.get_pixel(160 + k, 144).srgb_to_linear(), _stamp_ref(160 + k, 144))
		worst = maxf(worst, dd)
		bad += 1 if dd > 0.02 else 0
	out["deep"] = [bad == 0, "the 32-deep cell, columns 160..191 of row 144: %d of 32 off the reference, worst %.3f" % [bad, worst]]
	return out


func _stamp_material(sh: Shader, stamps, fade := Vector2(0.75, 1.5)) -> ShaderMaterial:
	var sm := _slug_material(sh, "fx-stamps")
	stamps.bind(sm, fade)
	return sm


## Pixels of a cam_size view inside the quad: [x, y, cell].
static func _quad_pixels(cam_size: float) -> Array:
	var span := SIZE * 2.0 / cam_size
	var x0 := SIZE * 0.5 - span * 0.5
	var out := []
	var g := Fixture.STAMP_GRID
	for y in range(floori(x0), ceili(x0 + span)):
		for x in range(floori(x0), ceili(x0 + span)):
			var u := (x + 0.5 - x0) / span
			var v := 1.0 - (y + 0.5 - x0) / span
			if u <= 0.0 or u >= 1.0 or v <= 0.0 or v >= 1.0:
				continue
			out.append([x, y, floori(v * g) * g + floori(u * g)])
	return out


func _stamps_gpu() -> void:
	if _stamps == null:
		return
	var sh := Shader.new()
	sh.code = TEST_SHADER
	var black := Color(0, 0, 0)
	var near := _view(_stamp_material(sh, _stamps), black, false)
	var scales := [8.0, 32.0, 128.0]
	var fade_views := []
	for c in scales:
		fade_views.append(_view(_stamp_material(sh, _stamps), black, false, c))
	var far_off := _view(_stamp_material(sh, _stamps, Vector2(-2, -1)), black, false, 128.0)
	# the negative control: S4 dropped from the cell right of x = 24 px, the overlap cell's list
	# reversed, paint ids ignored
	var lists := Encoder.bin_cells(Fixture.STAMP_GRID, _guest.stamps.layers[1].instances)
	var rc := _cell_of(96, 72)
	lists[rc].erase(_guest.stamps.special.S4)
	var oc := _cell_of(_pts.overlap[0], _pts.overlap[1])
	lists[oc].reverse()
	_guest.stamp_lists = {1: lists}
	_guest.ignore_paint = true
	var bad_stamps = Stamps.build(_guest.call_fn("slug_atlas"), SlugAtlas.shared())
	_guest.stamp_lists = {}
	_guest.ignore_paint = false
	var bad := _view(_stamp_material(sh, bad_stamps), black, false)
	# and the loop bound one short of the contract's 32
	var sh31 := Shader.new()
	sh31.code = TEST_SHADER.replace("#include", "#define SLUG_STAMP_MAX 31\n#include")
	var bad31 := _view(_stamp_material(sh31, _stamps), black, false)
	var mts := {}
	for v in ["", "_cull_off", "_cutout", "_cutout_cull_off", "_trans", "_trans_cull_off"]:
		var mt := _stamp_material(load("res://addons/sakuragaoka_station/core/slug/mtoon_slug%s.gdshader" % v), _stamps)
		mt.set_shader_parameter("_Cutoff", 0.5)
		if v.begins_with("_cutout"):
			mt.set_shader_parameter("_AlphaCutoutEnable", 1.0)
		mts[v] = _view(mt, Color(1, 0, 1), true)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = near.get_texture().get_image()
	img.save_png("user://slug_check_stamps.png")
	var pts := _stamp_points(img)
	for k in pts:
		_check(pts[k][0], pts[k][1])
	# S4 whole, and the whole image, against the reference
	var b4: Rect2 = _sinst("S4").bbox.grow(2.0 / SIZE)
	var s4bad := 0
	var s4n := 0
	for y in range(floori(b4.position.y * SIZE), ceili(b4.end.y * SIZE)):
		for x in range(floori(b4.position.x * SIZE), ceili(b4.end.x * SIZE)):
			s4n += 1
			s4bad += 1 if _diff(img.get_pixel(x, y).srgb_to_linear(), _stamp_ref(x, y)) > 0.02 else 0
	_check(s4bad == 0, "S4 drawn whole across its cells: %d of %d bbox pixels off the reference" % [s4bad, s4n])
	var worst := 0.0
	var nbad := 0
	for y in SIZE:
		for x in SIZE:
			var dd := _diff(img.get_pixel(x, y).srgb_to_linear(), _stamp_ref(x, y))
			worst = maxf(worst, dd)
			nbad += 1 if dd > 0.02 else 0
	_check(nbad == 0, "fx-stamps whole image (%d px): %d pixels off the reference by > 0.02, worst %.4f" % [SIZE * SIZE, nbad, worst])
	# the distance fade: GPU against the CPU fade model at each distance; the deviation from the
	# cell mean shrinks with distance and is ~0 far away
	var devs := []
	var fade_imgs := []
	var fade_refs := []
	for i in scales.size():
		var fimg: Image = fade_views[i].get_texture().get_image()
		fade_imgs.append(fimg)
		var fr := _fade_ref(scales[i])
		fade_refs.append(fr)
		var fmx := 0.0
		for k in fr:
			fmx = maxf(fmx, _diff(fimg.get_pixel(k.x, k.y).srgb_to_linear(), fr[k]))
		_check(fmx <= 0.03, "fade: canvas at %.0f px, GPU against the CPU fade model (footprint, smoothstep %.2f..%.2f, cell mean): worst %.4f over %d px" % [
				512.0 / scales[i], FADE.x, FADE.y, fmx, fr.size()])
		var sum := 0.0
		var mx := 0.0
		var qp := _quad_pixels(scales[i])
		for p in qp:
			var dd := _diff(fimg.get_pixel(p[0], p[1]).srgb_to_linear(), _mean_ref(p[2]))
			sum += dd
			mx = maxf(mx, dd)
		devs.append([sum / qp.size(), mx])
		print("slug_check: fade: canvas at %.0f screen px (1 canvas px = %.3f px): mean |pixel - cell mean| %.4f, worst %.4f over %d px" % [
				512.0 / scales[i], 512.0 / scales[i] / 64.0, sum / qp.size(), mx, qp.size()])
	_check(devs[2][1] < 0.025, "fade: far away (canvas at 4 px) every pixel is its cell's mean (worst %.4f)" % devs[2][1])
	_check(devs[0][0] > devs[2][0], "fade: the deviation from the mean shrinks with distance (%.4f -> %.4f -> %.4f)" % [devs[0][0], devs[1][0], devs[2][0]])
	var oimg: Image = far_off.get_texture().get_image()
	var off_mx := 0.0
	for p in _quad_pixels(128.0):
		off_mx = maxf(off_mx, _diff(oimg.get_pixel(p[0], p[1]).srgb_to_linear(), _mean_ref(p[2])))
	_check(off_mx > 0.05, "fade control: the same far view with the fade off is not the cell mean (worst %.4f)" % off_mx)
	# the negative control
	var bimg: Image = bad.get_texture().get_image()
	var bp := _stamp_points(bimg)
	var failed := []
	for k in bp:
		if not bp[k][0]:
			failed.append(k)
	print("slug_check: negative control (S4 dropped from cell %d, cell %d reversed, paint ids ignored): failing %s" % [rc, oc, ", ".join(failed)])
	for k in ["straddle_r", "overlap", "grad t = 0.2", "grad t = 0.8"]:
		_check(not bp[k][0], "negative control fails %s: %s" % [k, bp[k][1]])
	_check(bp.inside[0] and bp.outside[0] and bp.straddle_l[0], "negative control: untouched cells still pass (inside, outside, straddle_l)")
	var b31img: Image = bad31.get_texture().get_image()
	var b31 := _stamp_points(b31img)
	_check(not b31.deep[0] and b31.inside[0], "negative control, loop bound 31: %s" % b31.deep[1])
	# MToon with stamps (every variant compiles with the stamp samplers and draws S1 red)
	var s1: Array = _pts.inside
	for v in mts:
		var c: Color = (mts[v].get_texture().get_image() as Image).get_pixel(s1[0], s1[1])
		_check(c.r > c.g + 0.2 and c.r > c.b + 0.2, "MToon Slug%s with stamps: S1 lit red at (%d, %d) (%s)" % [v, s1[0], s1[1], c])
	# rung 0: the contact sheet, each residual over its measured floor
	await _stamp_floors({"sh": sh, "sh31": sh31, "bad_stamps": bad_stamps, "img": img, "fade_imgs": fade_imgs,
			"fade_refs": fade_refs, "bimg": bimg, "b31img": b31img, "scales": scales, "rc": rc, "oc": oc})


## The CPU fade model for a cam_size view: per pixel of the quad, the cell's instances expanded
## (coverage, colour), the footprint of the largest, smoothstep(FADE) between the cell mean and the
## stamps, over the grey canvas. {Vector2i pixel: linear Color}. g: another fixture guest.
func _fade_ref(cam_size: float, g = null) -> Dictionary:
	var gg = g if g != null else _guest
	var span := SIZE * 2.0 / cam_size
	var x0 := SIZE * 0.5 - span * 0.5
	var insts: Array = gg.stamps.layers[1].instances
	var lists := Encoder.bin_cells(Fixture.STAMP_GRID, insts)
	var dx := Vector2(1.0 / span, 0)
	var dy := Vector2(0, 1.0 / span)
	var bg := Fixture.STAMP_BASE
	var out := {}
	for p in _quad_pixels(cam_size):
		var em := Vector2((p[0] + 0.5 - x0) / span, (p[1] + 0.5 - x0) / span)
		var acc := Color(0, 0, 0, 0)
		var fmax := 0.0
		for k in lists[p[2]]:
			var it: Dictionary = insts[k]
			fmax = maxf(fmax, Ref.stamp_footprint(it, dx, dy))
			var cov := Ref.stamp_coverage(it, em, dx, dy)
			if cov > 0.0:
				acc = Ref.over(acc, Ref.stamp_color(it, em), cov)
		var keep := smoothstep(FADE.x, FADE.y, fmax)
		var sc: Color = gg.stamp_mean(1, p[2]).lerp(acc, keep)
		out[Vector2i(p[0], p[1])] = Color(sc.r + bg.r * (1 - sc.a), sc.g + bg.g * (1 - sc.a), sc.b + bg.b * (1 - sc.a), 1)
	return out


## The screen-pixel box around instances (by name), grown by pad px.
func _px_box(names: Array, pad: int) -> Rect2i:
	var b: Rect2 = _sinst(names[0]).bbox
	for n in names:
		b = b.merge(_sinst(n).bbox)
	var r := Rect2i(floori(b.position.x * SIZE) - pad, floori(b.position.y * SIZE) - pad, 0, 0)
	r.end = Vector2i(ceili(b.end.x * SIZE) + pad, ceili(b.end.y * SIZE) + pad)
	return r.intersection(Rect2i(0, 0, SIZE, SIZE))


const REPLAY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D replay : filter_nearest, repeat_disable;
uniform int cell_px = 1;
void fragment() {
	ALBEDO = texelFetch(replay, ivec2(FRAGCOORD.xy) / cell_px, 0).rgb;
}
"""


## Rung 0 under the stamp residuals (GPU against the CPU expanded reference), per contact-sheet case:
##   (a) GPU floor: the case rendered again in a fresh viewport with the same parameters, diffed
##       against the first render;
##   (b) CPU floor: the reference recomputed from a fresh fixture guest (content regenerated from its
##       seed, raster and fade model rerun), diffed against the first;
##   (c) quantization floor: the reference replayed through the same output path as per-pixel flat
##       fills (_replay_view) and read back the same way, diffed against the reference; beside a
##       sweep of 256 flat fills measuring the 8-bit readback step and the sRGB round trip.
## residual - floor = residual max - (GPU + CPU + quantization floor max). The sheet sorts the cases
## by it, worst first, then the negative controls the same way, then the flat-fill sweep; the
## table is printed.
func _stamp_floors(s: Dictionary) -> void:
	var black := Color(0, 0, 0)
	var scales: Array = s.scales
	# (a) fresh viewports, same parameters
	var g_near := _view(_stamp_material(s.sh, _stamps), black, false)
	var g_fade := []
	for c in scales:
		g_fade.append(_view(_stamp_material(s.sh, _stamps), black, false, c))
	var g_bad := _view(_stamp_material(s.sh, s.bad_stamps), black, false)
	var g_bad31 := _view(_stamp_material(s.sh31, _stamps), black, false)
	# (c) the references replayed as flat fills, and the sweep: per 16 x 16 px patch k, R k / 255
	# (a uniform grid in linear), G the sRGB code midpoint (k + 0.5) / 255 (the worst rounding), B the
	# exact sRGB code k / 255, all as linear values
	var near_ref := func(x, y): return _stamp_ref(x, y)
	var r_near := _replay_view(_ref_image(near_ref))
	var r_fade := []
	for fr in s.fade_refs:
		r_fade.append(_replay_view(_ref_image(func(x, y): return fr.get(Vector2i(x, y), Color(0, 0, 0)))))
	var levels := Image.create(16, 16, false, Image.FORMAT_RGBAF)
	for k in 256:
		levels.set_pixel(k % 16, k / 16, Color(k / 255.0, Color(minf((k + 0.5) / 255.0, 1.0), 0, 0).srgb_to_linear().r,
				Color(k / 255.0, 0, 0).srgb_to_linear().r, 1))
	var r_sweep := _replay_view(levels, 16)
	# (b) a fresh guest, computed while the GPU works
	var g2 = FixtureGuest.new()
	var near_ref2 := func(x, y): return _stamp_ref(x, y, g2)
	var fade_refs2 := []
	for c in scales:
		fade_refs2.append(_fade_ref(c, g2))
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var i_near: Image = g_near.get_texture().get_image()
	var i_bad: Image = g_bad.get_texture().get_image()
	var i_bad31: Image = g_bad31.get_texture().get_image()
	var i_rnear: Image = r_near.get_texture().get_image()
	var rows := []
	rows.append(_frow("whole key fx-stamps (256 px view)", Rect2i(0, 0, SIZE, SIZE), s.img, i_near, i_rnear, near_ref, near_ref2, false))
	rows.append(_frow("mixed run: curve S5, ellipse S6, rect S7", _px_box(["S5", "S6", "S7"], 4), s.img, i_near, i_rnear, near_ref, near_ref2, false))
	rows.append(_frow("gradient on S8 (rotated 30 deg, 14 x 5 px)", _px_box(["S8"], 4), s.img, i_near, i_rnear, near_ref, near_ref2, false))
	rows.append(_frow("32-deep cell (cell x 160..192, y 128..160)", Rect2i(156, 124, 40, 40), s.img, i_near, i_rnear, near_ref, near_ref2, false))
	rows.append(_frow("straddle: S4 across cell lines x 96, y 64", _px_box(["S4"], 6), s.img, i_near, i_rnear, near_ref, near_ref2, false))
	for i in scales.size():
		var span := int(512.0 / scales[i])
		var fr: Dictionary = s.fade_refs[i]
		var fr2: Dictionary = fade_refs2[i]
		rows.append(_frow("fade %s: canvas at %d px (vs CPU fade model)" % [["near", "mid", "far"][i], span],
				Rect2i(SIZE / 2 - span / 2, SIZE / 2 - span / 2, span, span), s.fade_imgs[i], g_fade[i].get_texture().get_image(),
				r_fade[i].get_texture().get_image(), func(x, y): return fr.get(Vector2i(x, y), Color(0, 0, 0)),
				func(x, y): return fr2.get(Vector2i(x, y), Color(0, 0, 0)), false))
	rows.append(_frow("NEGATIVE: S4 dropped from cell %d, cell %d reversed" % [s.rc, s.oc], Rect2i(0, 0, 128, 96), s.bimg, i_bad, i_rnear, near_ref, near_ref2, true))
	rows.append(_frow("NEGATIVE: paint ids ignored (S8)", _px_box(["S8"], 4), s.bimg, i_bad, i_rnear, near_ref, near_ref2, true))
	rows.append(_frow("NEGATIVE: loop bound 31 (32-deep cell)", Rect2i(156, 124, 40, 40), s.b31img, i_bad31, i_rnear, near_ref, near_ref2, true))
	# worst residual - floor first; ties (within 1e-6) by the pixels off the replayed reference, then
	# by the residual max
	var by_excess := func(a, b):
		if absf(a.excess - b.excess) > 1e-6:
			return a.excess > b.excess
		if a.off != b.off:
			return a.off > b.off
		return a.st.res[0] > b.st.res[0]
	var cases := rows.filter(func(r): return not r.neg)
	var negs := rows.filter(func(r): return r.neg)
	cases.sort_custom(by_excess)
	negs.sort_custom(by_excess)
	rows = cases + negs
	# the flat-fill sweep
	var simg: Image = r_sweep.get_texture().get_image()
	var spread := 0.0
	var offgrid := 0.0
	var enc := 0.0
	var lin := [0.0, 0.0, 0.0]
	var lin_sum := 0.0
	var codes := {}
	for k in 256:
		var o := Vector2i((k % 16) * 16, (k / 16) * 16)
		var c0: Color = simg.get_pixel(o.x + 8, o.y + 8)
		for yy in 16:
			for xx in 16:
				spread = maxf(spread, _diff(simg.get_pixel(o.x + xx, o.y + yy), c0))
		var v: Color = levels.get_pixel(k % 16, k / 16)
		var cl := c0.srgb_to_linear()
		for ch in 3:
			offgrid = maxf(offgrid, absf(c0[ch] * 255.0 - roundf(c0[ch] * 255.0)))
			enc = maxf(enc, absf(c0[ch] - Color(v[ch], 0, 0).linear_to_srgb().r))
			lin[ch] = maxf(lin[ch], absf(cl[ch] - v[ch]))
			lin_sum += absf(cl[ch] - v[ch])
			codes[roundi(c0[ch] * 255.0)] = true
	var ks := codes.keys()
	ks.sort()
	var step := 1.0
	for i in range(1, ks.size()):
		step = minf(step, (ks[i] - ks[i - 1]) / 255.0)
	_check(spread == 0.0 and offgrid < 1e-4 and enc <= 1.0 / 255.0 + 1e-6,
			"rung 0: 256 flat fills read back flat (in-patch spread %.4f), on the 1/255 grid (off by %.6f codes), within a code of the exact sRGB encoding (max %.5f = %.2f/255)" % [
			spread, offgrid, enc, enc * 255.0])
	var sweep_note := "8-bit readback: step %.5f (1/255 = %.5f), %d distinct codes, encoded max %.5f (%.2f/255)\nsRGB round trip (linear): max %.4f on the linear grid (R), %.4f at code midpoints (G), %.4f at exact codes (B); mean %.5f" % [
			step, 1.0 / 255.0, ks.size(), enc, enc * 255.0, lin[0], lin[1], lin[2], lin_sum / 768.0]
	print("slug_check: rung 0 quantization on flat fills: %s" % sweep_note.replace("\n", "; "))
	var sw := {"name": "quantization floor: 256 flat fills, 16 x 16 px patches", "rect": Rect2i(0, 0, SIZE, SIZE), "neg": false, "sweep": true,
			"header": sweep_note}
	var ex := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var di := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var v: Color = levels.get_pixel(x / 16, y / 16)
			ex.set_pixel(x, y, v.linear_to_srgb())
			var d := simg.get_pixel(x, y).srgb_to_linear()
			di.set_pixel(x, y, Color(minf(absf(d.r - v.r) * DIFF_GAIN, 1), minf(absf(d.g - v.g) * DIFF_GAIN, 1), minf(absf(d.b - v.b) * DIFF_GAIN, 1)))
	var sg := simg.duplicate()
	sg.convert(Image.FORMAT_RGBA8)
	sw["tiles"] = [sg, ex, di]
	# the table
	print("slug_check: rung 0 (linear, max over rgb; max / mean over each crop; residual - floor = residual max - sum of the floor maxes)")
	print("slug_check:   %-52s | %-16s | %-16s | %-18s | %-16s | %-16s | %s" % ["case", "floor GPU", "floor CPU", "quantization floor", "residual",
			"residual - floor", "GPU vs replayed reference, 8-bit codes"])
	for r in rows:
		var st: Dictionary = r.st
		print("slug_check:   %-52s | %.4f / %.5f | %.4f / %.5f | %.4f / %.5f   | %.4f / %.5f | %+.4f          | %d of %d px differ, by <= %d" % [
				r.name, st.gpu[0], st.gpu[1], st.cpu[0], st.cpu[1], st.quant[0], st.quant[1], st.res[0], st.res[1], r.excess,
				r.off, r.rect.size.x * r.rect.size.y, r.off_max])
	for r in rows:
		var st: Dictionary = r.st
		r["header"] = "floor (max / mean): GPU self %.4f / %.5f   CPU self %.4f / %.5f   quantization %.4f / %.5f\nresidual %.4f / %.5f   residual - floor %+.4f   GPU vs replayed reference: %d of %d px differ in 8-bit codes (by <= %d)" % [
				st.gpu[0], st.gpu[1], st.cpu[0], st.cpu[1], st.quant[0], st.quant[1], st.res[0], st.res[1], r.excess,
				r.off, r.rect.size.x * r.rect.size.y, r.off_max]
	rows.append(sw)
	for v in [g_near, g_bad, g_bad31, r_near, r_sweep] + g_fade + r_fade:
		v.queue_free()
	await _contact_sheet(rows, "user://slug_check_stamps_contact_sheet.png")


## A view whose every pixel (cell_px block) is a flat fill of a known linear colour: img
## (FORMAT_RGBAF) fetched at FRAGCOORD, unshaded, in the same output path as the stamp views (fp16
## colour buffer, linear tonemap, sRGB encode, 8-bit readback).
func _replay_view(img: Image, cell_px := 1) -> SubViewport:
	var sh := Shader.new()
	sh.code = REPLAY_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("replay", ImageTexture.create_from_image(img))
	sm.set_shader_parameter("cell_px", cell_px)
	return _view(sm, Color(0, 0, 0), false)


## ref(x, y) (linear) over the SIZE x SIZE view as a FORMAT_RGBAF image.
func _ref_image(ref: Callable) -> Image:
	var im := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBAF)
	for y in SIZE:
		for x in SIZE:
			var c: Color = ref.call(x, y)
			im.set_pixel(x, y, Color(c.r, c.g, c.b, 1))
	return im


## A contact-sheet row at crop r: tiles GPU | reference | |GPU - reference| x DIFF_GAIN, and per
## error [max, mean] over the crop (linear, max over rgb): res GPU against the reference, gpu the
## GPU floor (gpu against gpu2), cpu the CPU floor (ref against ref2), quant the quantization floor
## (the replayed reference against the reference).
func _frow(name: String, r: Rect2i, gpu: Image, gpu2: Image, replay: Image, ref: Callable, ref2: Callable, neg: bool) -> Dictionary:
	var g := gpu.get_region(r)
	g.convert(Image.FORMAT_RGBA8)
	var re := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	var di := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	var st := {"res": [0.0, 0.0], "gpu": [0.0, 0.0], "cpu": [0.0, 0.0], "quant": [0.0, 0.0]}
	var off := 0       # pixels whose 8-bit codes differ between the GPU render and the replayed reference
	var off_max := 0   # the largest such code difference
	for y in r.size.y:
		for x in r.size.x:
			var px := r.position + Vector2i(x, y)
			var w: Color = ref.call(px.x, px.y)
			var c8: Color = gpu.get_pixel(px.x, px.y)
			var q8: Color = replay.get_pixel(px.x, px.y)
			var dc := 0
			for ch in 3:
				dc = maxi(dc, absi(roundi(c8[ch] * 255.0) - roundi(q8[ch] * 255.0)))
			off += 1 if dc > 0 else 0
			off_max = maxi(off_max, dc)
			var c: Color = c8.srgb_to_linear()
			re.set_pixel(x, y, Color(w.r, w.g, w.b, 1).linear_to_srgb())
			var d := Color(absf(c.r - w.r), absf(c.g - w.g), absf(c.b - w.b))
			di.set_pixel(x, y, Color(minf(d.r * DIFF_GAIN, 1), minf(d.g * DIFF_GAIN, 1), minf(d.b * DIFF_GAIN, 1), 1))
			_acc(st.res, _diff(c, w))
			_acc(st.gpu, _diff(gpu2.get_pixel(px.x, px.y).srgb_to_linear(), c))
			_acc(st.cpu, _diff(ref2.call(px.x, px.y), w))
			_acc(st.quant, _diff(replay.get_pixel(px.x, px.y).srgb_to_linear(), w))
	for k in st:
		st[k][1] /= float(r.size.x * r.size.y)
	var floor_max: float = st.gpu[0] + st.cpu[0] + st.quant[0]
	return {"name": name, "tiles": [g, re, di], "rect": r, "neg": neg, "st": st, "excess": st.res[0] - floor_max,
			"off": off, "off_max": off_max}


static func _acc(a: Array, v: float) -> void:
	a[0] = maxf(a[0], v)
	a[1] += v


## Composes rows of [GPU | CPU expanded reference | abs diff] tiles with labels in a 2D SubViewport
## (Image cannot draw text) and saves it to path. Each row: its name and header (floor | residual)
## across the row, a column label over each tile.
func _contact_sheet(rows: Array, path: String) -> void:
	const TILE := 300
	const LABEL := 70
	const GAP := 10
	const TOP := 62
	var cols := ["GPU", "CPU expanded reference", "|GPU - reference| x%d" % DIFF_GAIN]
	var w := GAP + 3 * (TILE + GAP)
	var h := TOP + rows.size() * (TILE + LABEL + GAP) + GAP
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1)
	bg.size = Vector2(w, h)
	vp.add_child(bg)
	var title := Label.new()
	title.text = "slug_check stamp layers, rung 0 (fx-stamps, %s): GPU | CPU expanded reference | abs diff x%d; errors linear, max over rgb\ncases by residual - floor (max), worst first (ties: px off the replayed reference, then residual); then the negative controls (expected to fail); then the quantization floor itself\nfloor = GPU against itself (fresh viewport) + CPU reference against itself (fresh guest) + quantization (the reference replayed as flat fills, read back)" % [
			RenderingServer.get_current_rendering_driver_name(), DIFF_GAIN]
	title.position = Vector2(GAP, 4)
	title.add_theme_color_override("font_color", Color(0, 0, 0))
	title.add_theme_font_size_override("font_size", 11)
	vp.add_child(title)
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var y0 := TOP + ri * (TILE + LABEL + GAP)
		var hl := Label.new()
		hl.text = "%d. %s  (%d x %d px)\n%s" % [ri + 1, row.name, row.rect.size.x, row.rect.size.y, row.header]
		hl.position = Vector2(GAP, y0)
		hl.add_theme_color_override("font_color", Color(0.75, 0, 0) if row.neg else (Color(0, 0.25, 0.7) if row.has("sweep") else Color(0, 0, 0)))
		hl.add_theme_font_size_override("font_size", 11)
		vp.add_child(hl)
		for ci in 3:
			var t: Image = row.tiles[ci].duplicate()
			var f := maxi(1, TILE / maxi(t.get_width(), t.get_height()))
			t.resize(t.get_width() * f, t.get_height() * f, Image.INTERPOLATE_NEAREST)
			var x0 := GAP + ci * (TILE + GAP)
			var frame := ColorRect.new()
			frame.color = Color(0.85, 0.85, 0.85)
			frame.position = Vector2(x0, y0 + LABEL)
			frame.size = Vector2(TILE, TILE)
			vp.add_child(frame)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(t)
			tr.position = Vector2(x0 + (TILE - t.get_width()) / 2, y0 + LABEL + (TILE - t.get_height()) / 2)
			vp.add_child(tr)
			var lb := Label.new()
			lb.text = "%s  (shown x%d)" % [("flat fills read back" if ci == 0 else ("exact linear values" if ci == 1 else cols[2])) if row.has("sweep") else cols[ci], f]
			lb.clip_text = true
			lb.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			lb.position = Vector2(x0, y0)
			lb.size = Vector2(TILE, LABEL)
			lb.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			lb.add_theme_font_size_override("font_size", 11)
			vp.add_child(lb)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var out: Image = vp.get_texture().get_image()
	out.save_png(path)
	print("slug_check: contact sheet (%d rows) saved to %s" % [rows.size(), ProjectSettings.globalize_path(path)])
	vp.queue_free()
