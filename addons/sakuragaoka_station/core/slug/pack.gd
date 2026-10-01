# The station's canvas-texture pack: slug.elf's answers for every keyed texture, cached. The guest
# cannot read files, so a build feeds it each addons/sakuragaoka_station/slug/svg/<key>.svg
# (manifest.json lists them) through slug_load_svg, then takes slug_atlas() and every key's
# slug_cost (and slug_mesh for keys it recommends as "mesh"). That takes over a minute in the
# interpreted sandbox, so the answers are kept in user://slug_cache/, named by slug.elf's SHA-256,
# a SHA-256 over the listed keys' SVG files (svg_hash) and the tolerance; a launch with a matching file reads it and never starts the guest. slug_decal
# answers (per surface) are cached in the same file, keyed by a hash of their arguments; a miss on
# a cached launch starts the guest and loads only that key's SVG.
#   var p = Pack.shared()        # null: no cache and no guest (Pack.reason says why)
#   p.call_fn("slug_atlas")      # same API as slug.elf (core/slug/guest.gd)
#   p.flush()                    # writes new decal answers back (realize.gd calls it in finish())
# With Guest.override set (tests), calls go straight to the override, uncached.
extends RefCounted

const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const SVG_DIR := "res://addons/sakuragaoka_station/slug/svg"
const MANIFEST := SVG_DIR + "/manifest.json"
## slug_load_svg's mesh flattening tolerance (texture px) for every key.
## TODO(#72 close-up detail): per key, min(0.25, R * theta_px / metres-per-texel at the key's finest
## use), R = 2 m (the Slug/mesh switch radius), theta_px = (1/20) degree in radians (one screen px,
## a constant to revisit), so the baked mesh's chord error stays under a pixel at R. The finest use
## needs a pre-pass over the materials and their geometry's UV scale before the pack is built; until
## then every key takes 0.25 (the cache name carries the tolerance, so changing it rebuilds).
const TOLERANCE_PX := 0.25
const CACHE_DIR := "user://slug_cache"
const FORMAT := 1

static var _shared = null
static var _tried := false
static var reason := ""
## How the pack was obtained: {"source": "cache" | "guest" | "override", "ms": load time, "path": cache file}
static var info := {}

var source = null
var atlas := {}
var costs := {}
var meshes := {}
var decals := {}
var cache_path := ""
var _dirty := false
var _loaded := {}


static func shared():
	if not _tried:
		_tried = true
		var t0 := Time.get_ticks_msec()
		_shared = _open()
		info["ms"] = Time.get_ticks_msec() - t0
	return _shared


static func reset() -> void:
	_tried = false
	_shared = null
	info = {}


static func _open():
	var p = new()
	if Guest.override != null:
		p.source = Guest.override
		info["source"] = "override"
		return p
	if not FileAccess.file_exists(MANIFEST):
		reason = "%s not found" % MANIFEST
		return null
	if not FileAccess.file_exists(Guest.ELF):
		reason = "%s not found" % Guest.ELF
		return null
	var id := "%s_%s_%s_v%d" % [FileAccess.get_sha256(Guest.ELF).left(16), svg_hash().left(16), str(TOLERANCE_PX), FORMAT]
	p.cache_path = CACHE_DIR.path_join(id + ".bin")
	if p._read():
		info["source"] = "cache"
		info["path"] = p.cache_path
		return p
	if not p._build():
		return null
	p._write()
	info["source"] = "guest"
	info["path"] = p.cache_path
	return p


func _read() -> bool:
	if not FileAccess.file_exists(cache_path):
		return false
	var d = Kernels.read_cache(cache_path)
	if not (d is Dictionary) or int(d.get("format", 0)) != FORMAT:
		return false
	atlas = d.atlas
	costs = d.costs
	meshes = d.meshes
	decals = d.decals
	return true


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if not Kernels.write_cache(cache_path, {"format": FORMAT, "atlas": atlas, "costs": costs, "meshes": meshes, "decals": decals}):
		push_warning("slug pack: cannot write %s" % cache_path)
		return
	_dirty = false


func flush() -> void:
	if _dirty and source == null:
		_write()


## SHA-256 over the manifest's keys and each key's SVG file hash. Not the manifest file itself:
## tools/oracle/canvas_svg.mjs rewrites it on every run, and its bytes change even when no SVG does.
static func svg_hash() -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	for k in manifest_keys():
		hc.update((k + ":" + FileAccess.get_sha256(SVG_DIR.path_join(k + ".svg")) + "
").to_utf8_buffer())
	return hc.finish().hex_encode()


static func manifest_keys() -> PackedStringArray:
	var m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out := PackedStringArray()
	if m is Dictionary and m.get("keys") is Dictionary:
		for k in m.keys:
			if FileAccess.file_exists(SVG_DIR.path_join(str(k) + ".svg")):
				out.append(str(k))
	out.sort()
	return out


func _load_key(g, key: String) -> bool:
	if _loaded.has(key):
		return true
	var r = g.call_fn("slug_load_svg", [key, FileAccess.get_file_as_string(SVG_DIR.path_join(key + ".svg")), TOLERANCE_PX])
	_loaded[key] = true
	if not str(r).begins_with("ok"):
		push_warning("slug pack: slug_load_svg(%s): %s" % [key, r])
		return false
	return true


func _build() -> bool:
	var g = Guest.shared()
	if g == null:
		reason = "no cache and no guest: " + Guest.reason
		return false
	var t0 := Time.get_ticks_msec()
	var keys := manifest_keys()
	var answers := Kernels.load_svgs(g.sandbox, SVG_DIR, keys, TOLERANCE_PX)
	for i in keys.size():
		_loaded[keys[i]] = true
		if i >= answers.size() or not answers[i].begins_with("ok"):
			push_warning("slug pack: slug_load_svg(%s): %s" % [keys[i], answers[i] if i < answers.size() else "no answer"])
	var t1 := Time.get_ticks_msec()
	var a = g.call_fn("slug_atlas")
	if not (a is Dictionary) or a.is_empty() or a.has("error"):
		reason = "slug_atlas(): %s" % (a.get("error", "empty") if a is Dictionary else type_string(typeof(a)))
		return false
	atlas = a
	var t2 := Time.get_ticks_msec()
	for key in a.keys:
		var c = g.call_fn("slug_cost", [key])
		costs[key] = c if c is Dictionary else {}
		if str(costs[key].get("mode", "")) == "mesh":
			var m = g.call_fn("slug_mesh", [key])
			meshes[key] = m if m is Dictionary else {}
	info["build"] = {"load_ms": t1 - t0, "atlas_ms": t2 - t1, "bake_ms": Time.get_ticks_msec() - t2}
	return true


func has_fn(fn: String) -> bool:
	return source.has_fn(fn) if source != null else fn in ["slug_atlas", "slug_cost", "slug_mesh", "slug_decal"]


func call_fn(fn: String, args: Array = []):
	if source != null:
		return source.call_fn(fn, args)
	match fn:
		"slug_atlas":
			return atlas
		"slug_cost":
			return costs.get(args[0], {})
		"slug_mesh":
			return meshes.get(args[0], {})
		"slug_decal":
			var hc := HashingContext.new()
			hc.start(HashingContext.HASH_SHA256)
			hc.update(var_to_bytes(args))
			var h := hc.finish().hex_encode()
			if decals.has(h):
				return decals[h]
			var g = Guest.shared()
			if g == null or not _load_key(g, args[0]):
				return {}
			var r = g.call_fn("slug_decal", args)
			if r is Dictionary and not r.has("error"):
				decals[h] = r
				_dirty = true
			return r
	return null
