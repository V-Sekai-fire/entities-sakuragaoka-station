# Seam detector for the sky, in a compute shader. A pixel's jump is how far a one-pixel step or a one-pixel
# line across it stands above the differences beside it (0..255); a seam pixel is one whose jump, averaged
# along its best line of 25 pixels (48 directions), reaches --threshold. Natural edges spread over several
# pixels and scattered noise does not line up, so the count of seam pixels is roughly the seams' length.
# Pixels count only where the mask is exactly magenta (tools/sky_mask.gd), or everywhere without one.
#   godot --path . --resolution 640x360 --script tools/sky_seam.gd -- --n=8 --img=<label>=<a_%d.png>
#       [--mask=<label>=<mask_%d.png>] [--ref=<label>=<b_%d.png>] [--threshold=3] [--vis=<dir>] [--json=<file>]
#       [--registered --floor=<label>] [--gate=<label,...>] [--mad-gate=<before>,<after>]
#       [--sheet=<png> --topic=sky-seam --heat=<label> --rows=k]
#   ... --self-test=<clean.png>   planted seams of 2..12 levels at six angles against the clean image's floor
# The first --img set is the reference the gates compare with. --ref adds MAD 0..255 over the counted pixels
# (Kernels.frame_diff), so one table holds both measures.
extends SceneTree

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Sheet = preload("res://tools/sheet.gd")
const THRESHOLDS := [2.0, 3.0, 4.0, 6.0, 8.0]
const MAGENTA := 0xff00ff
const SLACK := 300

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba8, set = 0, binding = 0) uniform restrict image2D src;
layout(rgba8, set = 0, binding = 1) uniform restrict readonly image2D mask;
layout(r32f, set = 0, binding = 2) uniform restrict image2D jmap;
layout(r32f, set = 0, binding = 3) uniform restrict image2D mmap;
layout(rgba8, set = 0, binding = 4) uniform restrict writeonly image2D vis;
layout(set = 0, binding = 5, std430) restrict buffer Counts {
	uint c[];
} counts;
layout(rgba8, set = 0, binding = 6) uniform restrict readonly image2D ref;
layout(push_constant, std430) uniform Params {
	ivec2 size;
	int mode;
	int masked;
	vec2 p0;
	vec2 u;
	float len;
	float h;
	float kind;
	float threshold;
	int has_refm;
	int pad0;
	int pad1;
	int pad2;
} p;
layout(r32f, set = 0, binding = 7) uniform restrict readonly image2D refm;

const int K = 48;
const int R = 12;
const float T[5] = float[](2.0, 3.0, 4.0, 6.0, 8.0);

bool inside(ivec2 c) {
	return c.x >= 0 && c.y >= 0 && c.x < p.size.x && c.y < p.size.y;
}

bool sky(ivec2 c) {
	if (!inside(c)) {
		return false;
	}
	if (p.masked == 0) {
		return true;
	}
	vec4 m = imageLoad(mask, c);
	return m.r > 0.998 && m.g < 0.002 && m.b > 0.998;
}

vec3 px(ivec2 c) {
	return round(imageLoad(src, c).rgb * 255.0);
}

float dif(ivec2 a, ivec2 b) {
	vec3 d = abs(px(b) - px(a));
	return max(d.r, max(d.g, d.b));
}

float step_at(ivec2 c, ivec2 e) {
	return max(0.0, dif(c, c + e) - max(dif(c - e, c), dif(c + e, c + 2 * e)));
}

float line_at(ivec2 c, ivec2 e) {
	vec3 a = px(c) - px(c - e);
	vec3 b = px(c + e) - px(c);
	vec3 pk = max(min(a, -b), min(-a, b));
	return max(0.0, max(pk.r, max(pk.g, pk.b)) - max(dif(c - 2 * e, c - e), dif(c + e, c + 2 * e)));
}

void plant(ivec2 c) {
	vec2 x = vec2(c) + 0.5 - p.p0;
	float s = dot(x, p.u);
	float d = dot(x, vec2(-p.u.y, p.u.x));
	float along = clamp((p.len * 0.5 - abs(s)) / 40.0, 0.0, 1.0);
	float across = p.kind < 0.5 ? (d < 0.0 ? 0.0 : clamp((46.0 - d) / 40.0, 0.0, 1.0)) : (d >= 0.0 && d < 1.0 ? 1.0 : 0.0);
	float off = round(p.h * along * across);
	if (off != 0.0) {
		vec4 v = imageLoad(src, c);
		imageStore(src, c, vec4(clamp((round(v.rgb * 255.0) + off) / 255.0, 0.0, 1.0), v.a));
	}
}

void jump(ivec2 c) {
	ivec2 ex = ivec2(1, 0);
	ivec2 ey = ivec2(0, 1);
	for (int k = -2; k <= 2; k++) {
		if (!sky(c + ex * k) || !sky(c + ey * k)) {
			imageStore(jmap, c, vec4(-1.0));
			return;
		}
	}
	float j = max(max(step_at(c - ex, ex), step_at(c, ex)), max(step_at(c - ey, ey), step_at(c, ey)));
	imageStore(jmap, c, vec4(max(j, max(line_at(c, ex), line_at(c, ey)))));
}

bool alone(ivec2 c) {
	if (p.has_refm == 0) {
		return false;
	}
	float near = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 q = c + ivec2(x, y);
			near = inside(q) ? max(near, imageLoad(refm, q).r) : near;
		}
	}
	return near < p.threshold * 0.5;
}

void support(ivec2 c) {
	if (imageLoad(jmap, c).r < 0.0) {
		imageStore(mmap, c, vec4(-1.0));
		return;
	}
	float best = 0.0;
	for (int k = 0; k < K; k++) {
		float a = 3.14159265 * float(k) / float(K);
		vec2 dir = vec2(cos(a), sin(a));
		float s = 0.0;
		int n = 0;
		for (int t = -R; t <= R; t++) {
			ivec2 q = ivec2(floor(vec2(c) + dir * float(t) + 0.5));
			if (!inside(q)) {
				continue;
			}
			float j = imageLoad(jmap, q).r;
			if (j >= 0.0) {
				s += j;
				n++;
			}
		}
		if (n * 4 >= (2 * R + 1) * 3) {
			best = max(best, s / float(n));
		}
	}
	imageStore(mmap, c, vec4(best));
	atomicAdd(counts.c[5], 1u);
	for (int i = 0; i < 5; i++) {
		if (best >= T[i]) {
			atomicAdd(counts.c[i], 1u);
		}
	}
	if (best >= p.threshold && alone(c)) {
		atomicAdd(counts.c[262], 1u);
	}
	atomicAdd(counts.c[6 + min(int(best * 4.0), 255)], 1u);
}

void mark(ivec2 c) {
	vec3 col = imageLoad(src, c).rgb;
	vec3 o = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), 0.6) * (sky(c) ? 1.0 : 0.35);
	bool seam = false;
	bool own = false;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 q = c + ivec2(x, y);
			if (inside(q) && imageLoad(mmap, q).r >= p.threshold) {
				seam = true;
				own = own || alone(q);
			}
		}
	}
	o = own ? vec3(1.0, 0.05, 0.05) : (seam ? vec3(1.0, 0.85, 0.1) : o);
	imageStore(vis, c, vec4(o, 1.0));
}

void heat(ivec2 c) {
	vec3 d = abs(px(c) - round(imageLoad(ref, c).rgb * 255.0));
	float t = clamp((d.r + d.g + d.b) / 3.0 / 64.0 * 3.0, 0.0, 3.0);
	imageStore(vis, c, vec4(clamp(t, 0.0, 1.0), clamp(t - 1.0, 0.0, 1.0), clamp(t - 2.0, 0.0, 1.0), 1.0));
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (!inside(c)) {
		return;
	}
	if (p.mode == 0) {
		plant(c);
	} else if (p.mode == 1) {
		jump(c);
	} else if (p.mode == 2) {
		support(c);
	} else if (p.mode == 3) {
		mark(c);
	} else {
		heat(c);
	}
}
"""

var _a := {}
var _sets := {}
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()


func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if not s.begins_with("--"):
			continue
		var k := s.substr(2, s.find("=") - 2) if "=" in s else s.substr(2)
		var v := s.substr(s.find("=") + 1) if "=" in s else ""
		if k in ["img", "mask", "ref"]:
			var label := v.substr(0, v.find("="))
			if not _sets.has(label):
				_sets[label] = {}
				_sets[label]["order"] = _sets.size()
			_sets[label][k] = v.substr(v.find("=") + 1)
		else:
			_a[k] = v
	_run.call_deferred()


func _compile() -> bool:
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		return false
	var src := RDShaderSource.new()
	src.source_compute = GLSL
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("sky_seam: %s" % spirv.compile_error_compute)
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	return _pipeline.is_valid()


func _texture(w: int, h: int, fmt: int, data: PackedByteArray) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = w
	tf.height = h
	tf.format = fmt
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return _rd.texture_create(tf, RDTextureView.new(), [data] if not data.is_empty() else [])


func _uniform(type: int, binding: int, id: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	u.add_id(id)
	return u


func _dispatch(set: RID, w: int, h: int, mode: int, masked: int, plant: Array, threshold: float, has_refm := 0) -> void:
	var pc := PackedInt32Array([w, h, mode, masked]).to_byte_array()
	pc.append_array(PackedFloat32Array(plant + [threshold]).to_byte_array())
	pc.append_array(PackedInt32Array([has_refm, 0, 0, 0]).to_byte_array())
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, set, 0)
	_rd.compute_list_set_push_constant(list, pc, pc.size())
	_rd.compute_list_dispatch(list, (w + 7) / 8, (h + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()


## One image: {"valid", "counts" (per threshold), "hist" (0.25-level bins of the line support), "vis", "planted",
## "m" (the line support, R32F bytes), "heat" against ref when one is given, and "alone": seam pixels with no
## seam within 2 px in refm, the line support of a registered reference}. plants: [[x, y, angle degrees, length,
## height, kind 0 step / 1 line], ...] drawn into the image first.
func measure(img: Image, mask: Image, plants: Array, threshold: float, ref: Image = null, refm := PackedByteArray()) -> Dictionary:
	var im: Image = img.duplicate()
	im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width()
	var h := im.get_height()
	var rgba := RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	var src := _texture(w, h, rgba, im.get_data())
	var extra := []
	for e in [mask, ref]:
		var x: Image = e.duplicate() if e != null else Image.create(w, h, false, Image.FORMAT_RGBA8)
		x.convert(Image.FORMAT_RGBA8)
		extra.append(_texture(w, h, rgba, x.get_data()))
	var r32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT
	var jm := _texture(w, h, r32, PackedByteArray())
	var mm := _texture(w, h, r32, PackedByteArray())
	var vt := _texture(w, h, rgba, PackedByteArray())
	var rm: RID
	if refm.size() == w * h * 4:
		rm = _texture(w, h, r32, refm)
	else:
		var blank := PackedByteArray()
		blank.resize(w * h * 4)
		rm = _texture(w, h, r32, blank)
	var zero := PackedByteArray()
	zero.resize((6 + 256 + 1) * 4)
	var buf := _rd.storage_buffer_create(zero.size(), zero)
	var set := _rd.uniform_set_create([
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, src), _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, extra[0]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, jm), _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 3, mm),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 4, vt), _uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, buf),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, extra[1]), _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 7, rm)], _shader, 0)
	var masked := 1 if mask != null else 0
	var none := [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
	for pl in plants:
		var a := deg_to_rad(float(pl[2]))
		_dispatch(set, w, h, 0, masked, [pl[0], pl[1], cos(a), sin(a), pl[3], pl[4], pl[5]], threshold)
	for mode in [1, 2, 3]:
		_dispatch(set, w, h, mode, masked, none, threshold, 1 if refm.size() == w * h * 4 else 0)
	var raw := _rd.buffer_get_data(buf)
	var out := {"counts": [], "hist": PackedInt32Array(), "valid": raw.decode_u32(20), "alone": raw.decode_u32(262 * 4),
			"m": _rd.texture_get_data(mm, 0)}
	for i in THRESHOLDS.size():
		out.counts.append(raw.decode_u32(i * 4))
	for i in 256:
		out.hist.append(raw.decode_u32((6 + i) * 4))
	out.vis = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _rd.texture_get_data(vt, 0))
	out.planted = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _rd.texture_get_data(src, 0))
	if ref != null:
		_dispatch(set, w, h, 4, masked, none, threshold)
		out.heat = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _rd.texture_get_data(vt, 0))
	for r in [set, buf, src, extra[0], extra[1], jm, mm, vt, rm]:
		_rd.free_rid(r)
	return out


static func _rgb(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var im := Image.load_from_file(path)
	im.convert(Image.FORMAT_RGB8)
	return im


func _count(r: Dictionary, threshold: float) -> int:
	var i := THRESHOLDS.find(threshold)
	if i >= 0:
		return r.counts[i]
	var n := 0
	for b in range(int(threshold * 4.0), 256):
		n += r.hist[b]
	return n


func _run() -> void:
	var failed := 0
	if not _compile():
		print("sky_seam: FAIL no RenderingDevice or the shader did not compile (run without --headless)")
		quit(1)
		return
	var threshold := float(_a.get("threshold", "3"))
	if _a.has("self-test"):
		failed += _self_test(_a["self-test"], threshold)
	var n := int(_a.get("n", "8"))
	var res := {"threshold": threshold, "thresholds": THRESHOLDS, "sets": []}
	if not _sets.is_empty():
		print("sky_seam: set | view | counted px | seam px at %.1f (at %s) | MAD vs ref" % [threshold, str(THRESHOLDS)])
	var labels := _sets.keys()
	labels.sort_custom(func(x, y): return _sets[x].order < _sets[y].order)
	var cell := Vector2i(int(_a.get("cell", "480x270").split("x")[0]), int(_a.get("cell", "480x270").split("x")[1]))
	var shots := {}
	var per := {}
	for label in labels:
		per[label] = {"label": label, "views": []}
		res.sets.append(per[label])
	for v in n:
		var first_m := PackedByteArray()
		for label in labels:
			var c: Dictionary = _sets[label]
			var e: Dictionary = per[label]
			var img := _rgb(c.img % v)
			var mask := _rgb(c.mask % v) if c.has("mask") else null
			var ref := _rgb(c.ref % v) if c.has("ref") else null
			if img == null or (c.has("mask") and (mask == null or mask.get_size() != img.get_size())) \
					or (c.has("ref") and (ref == null or ref.get_size() != img.get_size())):
				print("sky_seam: FAIL %s view %d: the image, its mask or its reference is missing or a different size" % [label, v])
				failed += 1
				continue
			var r := measure(img, mask, [], threshold, ref, first_m if _a.has("registered") else PackedByteArray())
			if label == labels[0]:
				first_m = r.m
			var row := {"view": v, "valid": r.valid, "seam_px": _count(r, threshold), "counts": r.counts, "hist": Array(r.hist)}
			if _a.has("registered") and label != labels[0]:
				row.alone = r.alone
			var mad := ""
			if ref != null:
				var d := Kernels.frame_diff(img.get_data(), ref.get_data(), mask.get_data() if mask != null else PackedByteArray(), MAGENTA)
				row.mad = float(d[0]) / maxf(d[1], 1.0)
				mad = "%.2f" % row.mad
			if r.valid == 0:
				print("sky_seam: UNCHECKED %s view %d: no sky pixel to count (counted, not passed)" % [label, v])
				row.unchecked = true
			if _a.has("vis"):
				DirAccess.make_dir_recursive_absolute(_a.vis)
				r.vis.save_png(_a.vis.path_join("%s_%d.png" % [label, v]))
			if _a.has("sheet"):
				for k in ["vis", "heat"]:
					if r.has(k):
						r[k].resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
				shots["%s/%d" % [label, v]] = {"row": row, "vis": r.vis, "heat": r.get("heat")}
			e.views.append(row)
			var alone := (" | %d not in %s" % [row.alone, labels[0]]) if row.has("alone") else ""
			print("sky_seam: %-28s | %3d | %8d | %6d (%s) | %s%s" % [label, v, r.valid, row.seam_px, str(r.counts), mad, alone])
	Kernels.shutdown()
	failed += _gates(res, labels, n)
	if _a.has("sheet"):
		await _sheet(shots, labels, n, cell, threshold)
	if _a.has("json"):
		var f := FileAccess.open(_a.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
	for r in [_pipeline, _shader]:
		if r.is_valid():
			_rd.free_rid(r)
	_rd.free()
	print("sky_seam: %s" % ("FAIL (%d)" % failed if failed else "PASS"))
	quit(1 if failed else 0)


## --gate=<label,...>: each set's seam px per view at most the first set's plus one planted control seam (SLACK);
## with --registered (the sets show the same pixels), its seam px with no first-set seam within 2 px at most SLACK
## more than --floor's, a second faithful render of the first set (the original under another backend).
## --mad-gate=<before>,<after>: the after set's MAD against its reference no worse than the before set's, per view.
func _gates(res: Dictionary, labels: Array, n: int) -> int:
	var by := {}
	for e in res.sets:
		for row in e.views:
			by["%s/%d" % [e.label, row.view]] = row
	var fails := 0
	for g in (_a.get("gate", "").split(",", false) as PackedStringArray):
		var bad := 0
		var skipped := PackedInt32Array()
		for v in n:
			var a: Dictionary = by.get("%s/%d" % [g, v], {})
			var r: Dictionary = by.get("%s/%d" % [labels[0], v], {})
			var allowed: int = SLACK + int(by.get("%s/%d" % [_a.get("floor", ""), v], {}).get("alone", 0))
			if a.get("unchecked", false) and r.get("unchecked", false):
				skipped.append(v)
			elif a.has("alone") and a.alone > allowed:
				bad += 1
				print("sky_seam: gate %s view %d: %d seam px where %s has none within 2 px (%d allowed) FAIL" % [g, v,
						a.alone, labels[0], allowed])
			elif a.is_empty() or r.is_empty() or (not a.has("alone") and a.seam_px > r.seam_px + SLACK):
				bad += 1
				print("sky_seam: gate %s view %d: %s seam px against %s's %s (+%d allowed) FAIL" % [g, v,
						a.get("seam_px", "no"), labels[0], r.get("seam_px", "no"), SLACK])
		print("sky_seam: gate %s at %s's level in %d of %d views, %d without sky (%s) %s" % [g, labels[0],
				n - bad - skipped.size(), n - skipped.size(), skipped.size(), ",".join(Array(skipped).map(func(x): return str(x))),
				"PASS" if bad == 0 else "FAIL"])
		fails += 1 if bad else 0
	var mg: PackedStringArray = _a.get("mad-gate", "").split(",", false)
	if mg.size() == 2:
		var bad := 0
		for v in n:
			var b: Dictionary = by.get("%s/%d" % [mg[0], v], {})
			var a: Dictionary = by.get("%s/%d" % [mg[1], v], {})
			if not (a.has("mad") and b.has("mad")) or a.mad > b.mad:
				bad += 1
				print("sky_seam: mad gate view %d: %s %s against %s %s FAIL" % [v, mg[1], a.get("mad", "none"), mg[0], b.get("mad", "none")])
		print("sky_seam: mad gate %s no worse than %s in %d of %d views %s" % [mg[1], mg[0], n - bad, n, "PASS" if bad == 0 else "FAIL"])
		fails += 1 if bad else 0
	return fails


## One row per view, failures first (the largest seam excess over the first set), one column per set with its seams
## marked (yellow at --threshold, red at 8 levels), and a heat column for each set named in --heat.
func _sheet(shots: Dictionary, labels: Array, n: int, cell: Vector2i, threshold: float) -> void:
	var heat: PackedStringArray = _a.get("heat", "").split(",", false)
	var columns := []
	for l in labels:
		columns.append("%s, seams marked" % l)
		if l in heat:
			columns.append("|%s - its reference| (red 21, yellow 43, white 64 levels)" % l)
	var rows := []
	for v in n:
		var ref: Dictionary = shots.get("%s/%d" % [labels[0], v], {})
		var fl: int = shots.get("%s/%d" % [_a.get("floor", ""), v], {}).get("row", {}).get("alone", 0)
		var cells := []
		var excess := 0
		for l in labels:
			var s: Dictionary = shots.get("%s/%d" % [l, v], {})
			if s.is_empty() or ref.is_empty():
				cells.append({"image": null, "label": "%s: missing" % l})
				continue
			var over: int = s.row.alone - fl if s.row.has("alone") else s.row.seam_px - ref.row.seam_px
			excess = maxi(excess, over if l != _a.get("floor", "") else 0)
			var text := "%s: %d seam px" % [l, s.row.seam_px]
			if s.row.has("alone"):
				text += ", %d not in %s" % [s.row.alone, labels[0]]
			if s.row.has("mad"):
				text += ", MAD %.2f" % s.row.mad
			cells.append({"image": s.vis, "label": text, "mark": Color(0.9, 0.2, 0.2) if over > SLACK else null})
			if l in heat:
				cells.append({"image": s.heat, "label": "%s against its reference" % l})
		var what := "not in %s, over the floor" % labels[0] if _a.has("registered") else "over %s" % labels[0]
		rows.append({"label": "view %d: largest seam px %s %+d" % [v, what, excess], "cells": cells, "excess": excess,
				"color": Color(1, 0.5, 0.45) if excess > SLACK else Color(0.7, 1, 0.7)})
	rows.sort_custom(func(x, y): return x.excess > y.excess)
	rows = rows.slice(0, int(_a.get("rows", str(rows.size()))))
	var title: String = _a.get("title", "sky seams at %.0f levels over 25 px lines" % threshold)
	var img: Image = await Sheet.render(self, title, columns, rows, cell)
	for p in Sheet.publish(img, _a.sheet, _a.get("topic", "sky-seam")):
		print("sky_seam: sheet ", p)


## The negative control: a clean image must read the same floor twice, and a seam planted into it must lift the count
## by at least half its length. Steps and one-pixel lines of 2..12 levels, 300 px long, at six angles.
func _self_test(path: String, threshold: float) -> int:
	var img := _rgb(path)
	if img == null:
		print("sky_seam: FAIL self-test: no image at ", path)
		return 1
	var base := measure(img, null, [], threshold)
	var floor_px := _count(base, threshold)
	var again := measure(img, null, [], threshold, null, base.m)
	var fails := 0 if _count(again, threshold) == floor_px and again.alone == 0 else 1
	print("sky_seam: self-test clean image %s: %d seam px of %d counted at %.1f, again %d, %d not in itself" % [path.get_file(),
			floor_px, base.valid, threshold, _count(again, threshold), again.alone])
	var c := Vector2(img.get_width(), img.get_height()) * 0.5
	for kind in [0, 1]:
		for height in [2, 3, 4, 6, 8, 12]:
			var line := "sky_seam: self-test %-4s %2d levels (rise, not in clean):" % [["step", "line"][kind], height]
			var found := 0
			for angle in [0.0, 17.0, 45.0, 73.0, 90.0, 131.0]:
				var r := measure(img, null, [[c.x, c.y, angle, 300.0, float(height), float(kind)]], threshold, null, base.m)
				var rise := _count(r, threshold) - floor_px
				line += " %3.0f deg +%d %d," % [angle, rise, r.alone]
				found += 1 if rise >= 150 and r.alone >= 150 else 0
				if _a.has("vis") and angle == 17.0 and height == 6:
					DirAccess.make_dir_recursive_absolute(_a.vis)
					r.vis.save_png(_a.vis.path_join("self_test_%s.png" % ["step", "line"][kind]))
					r.planted.save_png(_a.vis.path_join("self_test_%s_planted.png" % ["step", "line"][kind]))
			var want: bool = height > threshold + 1.0
			line += "  -> %d/6 found%s" % [found, (" (must be 6)" if want else " (below the threshold, informational)")]
			if want and found < 6:
				fails += 1
				line += " FAIL"
			print(line)
	return fails
