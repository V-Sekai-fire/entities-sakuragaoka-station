# The real slug.elf under godot-sandbox, through the port's own consumers: every
# addons/sakuragaoka_station/slug/svg/<key>.svg goes in through slug_load_svg (one call a key), then
# slug_atlas() feeds core/slug/atlas.gd (SlugAtlas.from_guest builds its textures and per-key table),
# and every key's slug_cost / slug_mesh / slug_decal is checked against the wire contract
# (core/slug/baked.gd) and, with --native, against guest/slug's native harness (slug_native --json,
# the same slug_api.cpp on the host): the ELF is the parity oracle the other way round too.
# Prints the slowest call of each kind (what execution_timeout has to cover).
#
#   godot --headless --path <port with the godot_sandbox addon> --script res://guest/slug/tests/elf_check.gd \
#       -- [--native native.json] [--tolerance-px 0.25]
extends SceneTree

const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const Stamps = preload("res://addons/sakuragaoka_station/core/slug/stamps.gd")
const SVG_DIR := "res://addons/sakuragaoka_station/slug/svg"

var _fails := 0
var _checks := 0
var _slowest := {}


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("elf_check: FAIL ", what)


func _timed(fn: String, key: String, args: Array):
	var t0 := Time.get_ticks_usec()
	var r = Guest.shared().call_fn(fn, args)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not _slowest.has(fn) or ms > _slowest[fn][0]:
		_slowest[fn] = [ms, key]
	return r


func _initialize() -> void:
	var native := {}
	var tol := 0.25
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--native" and i + 1 < args.size():
			native = JSON.parse_string(FileAccess.get_file_as_string(args[i + 1]))
		elif args[i] == "--tolerance-px" and i + 1 < args.size():
			tol = float(args[i + 1])

	var g = Guest.shared()
	if g == null:
		print("elf_check: no guest: ", Guest.reason)
		quit(2)
		return

	var keys := PackedStringArray()
	for f in DirAccess.get_files_at(SVG_DIR):
		if f.ends_with(".svg"):
			keys.append(f.get_basename())
	keys.sort()

	var t_load := 0.0
	for key in keys:
		var t0 := Time.get_ticks_usec()
		var r = _timed("slug_load_svg", key, [key, FileAccess.get_file_as_string(SVG_DIR + "/" + key + ".svg"), tol])
		t_load += (Time.get_ticks_usec() - t0) / 1000.0
		_check(str(r).begins_with("ok"), "%s: slug_load_svg: %s" % [key, r])

	var a = _timed("slug_atlas", "", [])
	_check(a is Dictionary and not a.has("error"), "slug_atlas: %s" % (a.get("error", "") if a is Dictionary else type_string(typeof(a))))
	if not (a is Dictionary) or a.has("error"):
		_finish()
		return

	var w: int = a.tex_width
	_check(a.curves.size() == w * a.curve_height * 16, "curve bytes = width * height * 16")
	_check(a.bands.size() == w * a.band_height * 4, "band bytes = width * height * 4")
	_check(a.keys.size() == keys.size(), "every key in the table (%d / %d)" % [a.keys.size(), keys.size()])
	_check(a.key_layers.size() == a.keys.size() * 2 and a.key_frames.size() == a.keys.size() * 4, "key_layers / key_frames sizes")
	_check(a.layers.size() % 24 == 0, "layer stride 24")
	if not native.is_empty():
		_check(int(native.tex_width) == w, "tex_width matches native")
		# Shapes pack in Atlas's unordered_map order, which differs between the two standard
		# libraries (libstdc++ in the guest, the host's for slug_native): same content, other
		# padding, so the heights are reported, not compared.
		print("elf_check: texture rows curve %d band %d (native %d / %d)" % [a.curve_height, a.band_height, native.curve_height, native.band_height])
		_check(int(native.layers) == a.layers.size() / 24, "layer count matches native")

	var atlas = SlugAtlas.from_guest(g)
	_check(atlas != null, "core/slug/atlas.gd builds from the real slug_atlas()")
	var n_stamp_layers: int = a.get("stamp_layers", PackedInt32Array()).size() / 5
	if atlas != null and n_stamp_layers > 0:
		var st = Stamps.build(a, atlas)
		_check(st != null, "core/slug/stamps.gd builds from the real stamp arrays (%d stamp layers, %d instances)" % [
				n_stamp_layers, a.stamp_instances.size() / 12])
		print("elf_check: stamps: %d layers, %d instances, %d prototypes, %d cell texels, %d mean bytes" % [
				n_stamp_layers, a.stamp_instances.size() / 12, a.stamp_protos.size() / 2, a.stamp_cells.size() / 4, a.stamp_means.size()])

	var modes := {"mesh": 0, "slug": 0, "mean": 0}
	var mism := []
	var quad_v := PackedFloat32Array([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0])
	var quad_uv := PackedFloat32Array([0, 0, 1, 0, 1, 1, 0, 1])
	var quad_f := PackedInt32Array([0, 1, 2, 0, 2, 3])
	for key in keys:
		if atlas != null:
			_check(atlas.has(key), "%s: in atlas.gd's table" % key)
		var c = _timed("slug_cost", key, [key])
		_check(c is Dictionary and c.get("mode", "") in modes, "%s: slug_cost mode" % key)
		if c is Dictionary and c.get("mode", "") in modes:
			modes[c.mode] += 1
		var m = _timed("slug_mesh", key, [key])
		_check(m is Dictionary and m.has("vertices"), "%s: slug_mesh" % key)
		if not (m is Dictionary and m.has("vertices")):
			continue
		var n: int = m.vertices.size() / 3
		_check(m.paint.size() == n and m.param.size() == n * 2, "%s: per-vertex streams" % key)
		_check(m.overlay[0] + m.overlay[1] == m.triangles.size(), "%s: overlay ends the index list" % key)
		var area := 0.0
		for t in range(0, m.overlay[0], 3):
			var i0: int = m.triangles[t] * 3
			var i1: int = m.triangles[t + 1] * 3
			var i2: int = m.triangles[t + 2] * 3
			area += ((m.vertices[i1] - m.vertices[i0]) * (m.vertices[i2 + 1] - m.vertices[i0 + 1])
					- (m.vertices[i2] - m.vertices[i0]) * (m.vertices[i1 + 1] - m.vertices[i0 + 1])) * 0.5
		if native.has("keys") and native.keys.has(key):
			var nk: Dictionary = native.keys[key]
			var same: bool = nk.mode == c.mode and int(nk.triangles) == m.triangles.size() / 3 and int(nk.vertices) == n
			if not same:
				mism.append("%s (elf %s %d tris %d verts, native %s %d tris %d verts)" % [key, c.mode, m.triangles.size() / 3, n, nk.mode, nk.triangles, nk.vertices])
			_check(absf(area - float(nk.opaque_area)) < 1e-3, "%s: opaque area %.5f vs native %.5f" % [key, area, float(nk.opaque_area)])
		var cm = _timed("slug_mesh_cutout", key, [key, 0.5])
		_check(cm is Dictionary and cm.has("overlay") and cm.overlay[1] == 0, "%s: slug_mesh_cutout: opaque only" % key)
		var d = _timed("slug_decal", key, [key, quad_v, PackedFloat32Array(), quad_uv, quad_f,
				PackedFloat32Array([1, 1, 0, 0, 0]), PackedFloat32Array([0, 0, 4000000])])
		_check(d is Dictionary and not d.get("capped", true), "%s: slug_decal" % key)
		if d is Dictionary and not d.get("capped", true):
			var da := 0.0
			for t in d.overlay_from:
				var o: int = t * 9
				da += ((d.vertices[o + 3] - d.vertices[o]) * (d.vertices[o + 7] - d.vertices[o + 1])
						- (d.vertices[o + 6] - d.vertices[o]) * (d.vertices[o + 4] - d.vertices[o + 1])) * 0.5
			_check(absf(da - area) < 1e-3, "%s: decal base area %.5f == bake opaque area %.5f" % [key, da, area])

	# core/slug/baked.gd over the real guest.
	Baked.reset()
	var baked = Baked.shared()
	_check(baked != null, "core/slug/baked.gd opens on the real guest")
	if baked != null:
		for key in keys:
			var mode: String = baked.mode(key)
			_check(mode in modes, "%s: baked.gd mode" % key)
			var bm = baked.get_mesh(key)
			_check(bm != null and bm.positions.size() > 0, "%s: baked.gd parses slug_mesh" % key)

	print("elf_check: modes ", modes)
	if not mism.is_empty():
		print("elf_check: %d keys differ from native in triangle/vertex count or mode (float rounding across ISAs):" % mism.size())
		for s in mism:
			print("  ", s)
	print("elf_check: all slug_load_svg %.0f ms" % t_load)
	_finish()


func _finish() -> void:
	for fn in _slowest:
		print("elf_check: slowest %s %.1f ms (%s)" % [fn, _slowest[fn][0], _slowest[fn][1]])
	print("elf_check: %s (%d checks, %d failed)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)
