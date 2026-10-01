# The compiled SafeGDScript port (core/slug/slug_kernels.sgd -> slug_kernels.elf) against the
# GDScript it replaces (core/slug/kernels.gd's bodies, Kernels.mode = "gd"), bit for bit
# (var_to_bytes of every answer), on the station's real data, with each stage timed both ways:
#   pack_layers / gradient_stops   the atlas data texture, from slug_atlas() (all 120 keys)
#   pack_stamps                    the stamp textures (the fixture's; the station's when it has any)
#   parse_mesh                     every key's slug_mesh bake
#   unpack_tris                    every cached slug_decal answer
#   ramp_row                       every linear paint in the bakes and the fixture, 3 tints, both alphas
#   read_cache / write_cache       the pack cache file
#   realize                        the whole station realized twice (gd, then sgd): every mesh,
#                                  MultiMesh and the palette image hashed and compared, which also
#                                  covers blob_cols and split_coloured on the real geometry
#   load_svgs (--load)             every key's SVG through slug_load_svg in two fresh slug.elf
#                                  Sandboxes, then slug_atlas() compared
# Needs the godot_sandbox addon and slug.elf (or a cached pack).
#   godot --headless --path . --script tools/sgd_check.gd -- [--load] [--no-realize]
extends SceneTree

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
const FixtureGuest = preload("res://tools/slug_fixture/fixture_guest.gd")
const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")

var _fails := 0
var _rows := []


func _initialize() -> void:
	_run.call_deferred()


func _hash(v) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(var_to_bytes(v))
	return hc.finish().hex_encode().left(16)


## Runs f under both modes; records times and whether the answers are identical.
func _both(stage: String, f: Callable, calls: int = 1) -> void:
	Kernels.mode = "gd"
	var t0 := Time.get_ticks_usec()
	var a = f.call()
	var tg := Time.get_ticks_usec() - t0
	Kernels.mode = "sgd"
	t0 = Time.get_ticks_usec()
	var b = f.call()
	var ts := Time.get_ticks_usec() - t0
	var same := var_to_bytes(a) == var_to_bytes(b)
	if not same:
		_fails += 1
	_rows.append([stage, calls, tg, ts, same, _hash(a) if same else "%s != %s" % [_hash(a), _hash(b)]])


func _print_rows() -> void:
	print("sgd_check: %-34s %6s %12s %12s %7s  %s" % ["stage", "calls", ".gd ms", ".sgd ms", "ratio", "identical (sha256 of var_to_bytes)"])
	for r in _rows:
		print("sgd_check: %-34s %6d %12.1f %12.1f %6.2fx  %s %s" % [r[0], r[1], r[2] / 1000.0, r[3] / 1000.0,
				float(r[3]) / maxf(float(r[2]), 1.0), "yes" if r[4] else "NO", r[5]])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if Kernels.sandbox() == null:
		print("sgd_check: FAIL no kernel sandbox: ", Kernels.reason)
		quit(1)
		return
	print("sgd_check: slug_kernels.elf in a Sandbox; binary translation %s" % ("on" if SandboxUtil.translated else "off (no res://bintr/ library)"))
	var pack = Pack.shared()
	if pack == null:
		print("sgd_check: FAIL no pack: ", Pack.reason)
		quit(1)
		return
	var at: Dictionary = pack.atlas
	var layers: PackedFloat32Array = at.layers
	var grads: PackedFloat32Array = at.get("gradients", PackedFloat32Array([0]))
	print("sgd_check: pack (%s): %d keys, %d layers, %d gradients, %d bakes, %d decals" % [Pack.info.get("source", "?"),
			at.keys.size(), layers.size() / 24, int(grads[0]) if grads.size() > 0 else 0, pack.meshes.size(), pack.decals.size()])

	_both("pack_layers (atlas data texture)", func(): return Kernels.pack_layers(layers, grads))
	_both("gradient_stops", func(): return Kernels.gradient_stops(layers.size() / 24, grads))
	# negative control: the comparison has to see one float32 ulp in one layer
	var nudged := layers.duplicate()
	var bits := nudged.to_byte_array()
	bits[4 * 12] = bits[4 * 12] ^ 1
	nudged = bits.to_float32_array()
	Kernels.mode = "sgd"
	var ctl_same := var_to_bytes(Kernels.pack_layers(layers, grads)) == var_to_bytes(Kernels.pack_layers(nudged, grads))
	if ctl_same:
		_fails += 1
	_rows.append(["negative control (1 ulp in layer 0)", 1, 0, 0, not ctl_same, "differs, as it must" if not ctl_same else "NOT SEEN"])

	# stamps: the fixture's (the station's slug.elf output has %d stamp layers)
	var fx = FixtureGuest.new()
	var fr: Dictionary = fx.call_fn("slug_atlas")
	var stamp_sets := [["fixture", fr]]
	if at.get("stamp_layers", PackedInt32Array()).size() >= 5:
		stamp_sets.append(["station", at])
	for e in stamp_sets:
		var r: Dictionary = e[1]
		var stops := Kernels.gradient_stops(r.layers.size() / 24, r.get("gradients", PackedFloat32Array([0])))
		_both("pack_stamps (%s)" % e[0], func(): return Kernels.pack_stamps(r, stops))

	# bakes
	var meshes: Array = pack.meshes.values().filter(func(m): return m is Dictionary and m.has("vertices"))
	var verts := 0
	for m in meshes:
		verts += m.vertices.size() / 3
	_both("parse_mesh (%d bakes, %d vertices)" % [meshes.size(), verts], func():
		var out := []
		for m in meshes:
			out.append(Kernels.parse_mesh(m.vertices, m.get("paint", PackedInt32Array()), m.get("param", PackedFloat32Array()), m.get("paints", PackedFloat32Array([0]))))
		return out, meshes.size())
	var decals: Array = pack.decals.values().filter(func(d): return d is Dictionary and not d.get("capped", false) and d.has("vertices"))
	var dtris := 0
	for d in decals:
		dtris += d.vertices.size() / 9
	_both("unpack_tris (%d decals, %d triangles)" % [decals.size(), dtris], func():
		var out := []
		for d in decals:
			out.append(Kernels.unpack_tris(d.vertices, d.get("normals", PackedFloat32Array()), d.get("param", PackedFloat32Array())))
		return out, decals.size())

	# ramps: every linear paint in the bakes and the fixture
	var linear := []
	for m in meshes + [fx.bakes.get("fx-card", {})]:
		if m is Dictionary and m.has("paints"):
			for p in Kernels.decode_paints(m.paints):
				if p.type == "linear":
					linear.append(p.stops)
	linear.append([{"t": 0.0, "color": Color(1, 0, 0)}, {"t": 0.3, "color": Color(0.2, 0.9, 0.1, 0.5)}, {"t": 1.0, "color": Color(0, 0, 1)}])
	var tints := [Color(1, 1, 1), Color(0.8, 0.6, 0.9), Color(1.6, 1.6, 1.6)]
	_both("ramp_row (%d gradients x 3 tints x 2)" % linear.size(), func():
		var out := []
		for st in linear:
			for t in tints:
				for ov in [false, true]:
					out.append(Kernels.ramp_row(st, t, ov, 512))
		return out, linear.size() * 6)

	# the cache file
	var path: String = pack.cache_path
	_both("read_cache (%d MB)" % (FileAccess.get_file_as_bytes(path).size() >> 20), func(): return _hash(Kernels.read_cache(path)))
	var tmp := "user://slug_cache/sgd_check_write.bin"
	_both("write_cache", func():
		Kernels.write_cache(tmp, {"format": 1, "atlas": at, "costs": pack.costs, "meshes": pack.meshes, "decals": pack.decals})
		return FileAccess.get_sha256(tmp))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	if "--load" in args:
		_load_svgs()
	if not "--no-realize" in args:
		await _realize()
	_print_rows()
	Kernels.shutdown()
	Guest.shutdown()
	print("sgd_check: %s (%d stages, %d differ)" % ["PASS" if _fails == 0 else "FAIL", _rows.size(), _fails])
	quit(0 if _fails == 0 else 1)


func _load_svgs() -> void:
	var keys := Pack.manifest_keys()
	var res := {}
	var times := {}
	for mode in ["gd", "sgd"]:
		Kernels.mode = mode
		var sb = SandboxUtil.make_sandbox(null, Guest.ELF, Guest.MEM_MB, Guest.REFS, Guest.TIMEOUT_UNITS).sandbox
		var t0 := Time.get_ticks_usec()
		var answers := Kernels.load_svgs(sb, Pack.SVG_DIR, keys, Pack.TOLERANCE_PX)
		times[mode] = Time.get_ticks_usec() - t0
		var a = sb.vmcall("slug_atlas")
		res[mode] = [answers, _hash(a.curves), _hash(a.bands), _hash(a.layers), _hash(a.gradients)]
		sb.free()
	var same := var_to_bytes(res.gd) == var_to_bytes(res.sgd)
	if not same:
		_fails += 1
	_rows.append(["load_svgs (%d keys) + slug_atlas" % keys.size(), keys.size(), times.gd, times.sgd, same, _hash(res.gd)])


## The whole station realized under each mode; every node's arrays and the palette hashed.
func _realize() -> void:
	var ctx = Ctx.new(1)
	var t0 := Time.get_ticks_msec()
	for n in ["environment", "station", "plaza", "sakura"]:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	print("sgd_check: station built in %d ms" % (Time.get_ticks_msec() - t0))
	var snap := {}
	var times := {}
	# gd twice: the control that two realizes of the same station agree at all
	for run in ["gd", "gd again", "sgd"]:
		var mode: String = run.split(" ")[0]
		Kernels.mode = mode
		var root := Node3D.new()
		get_root().add_child(root)
		var r = Realize.new()
		var t1 := Time.get_ticks_usec()
		r.realize(ctx, root)
		var t2 := Time.get_ticks_usec()
		await process_frame
		await process_frame
		var t3 := Time.get_ticks_usec()
		r.finish()
		times[run] = (t2 - t1) + (Time.get_ticks_usec() - t3)
		snap[run] = _snapshot(root, r)
		root.queue_free()
		await process_frame
	var ctl := 0
	for k in snap.gd:
		if snap["gd again"].get(k) != snap.gd[k]:
			ctl += 1
	if ctl > 0:
		_fails += 1
	_rows.append(["realize control (gd vs gd)", 1, times.gd, times["gd again"], ctl == 0, "%d differ" % ctl if ctl else "deterministic"])
	var diff := 0
	for k in snap.gd:
		if snap.sgd.get(k) != snap.gd[k]:
			diff += 1
	diff += absi(snap.gd.size() - snap.sgd.size())
	if diff > 0:
		_fails += 1
		var shown := 0
		for k in snap.gd:
			if snap.sgd.get(k) != snap.gd[k] and shown < 8:
				print("sgd_check: realize differs at ", k)
				shown += 1
	_rows.append(["realize (%d nodes + palette, hashed)" % (snap.gd.size() - 1), 1, times.gd, times.sgd, diff == 0, "%d differ" % diff if diff else _hash(snap.gd)])


func _snapshot(root: Node3D, r) -> Dictionary:
	var out := {"palette": _hash(r._palette_img.get_data())}
	var i := 0
	for n in root.get_children():
		var key := "%d %s %s" % [i, n.get_class(), "" if str(n.name).begins_with("@") else n.name]
		i += 1
		if n is MeshInstance3D:
			var arrs := []
			for s in n.mesh.get_surface_count():
				arrs.append(n.mesh.surface_get_arrays(s))
			out[key] = _hash([arrs, n.transform])
		elif n is MultiMeshInstance3D:
			var arrs := []
			for s in n.multimesh.mesh.get_surface_count():
				arrs.append(n.multimesh.mesh.surface_get_arrays(s))
			var xf := []
			for k in n.multimesh.instance_count:
				xf.append(n.multimesh.get_instance_transform(k))
			out[key] = _hash([arrs, xf, n.transform])
	return out
