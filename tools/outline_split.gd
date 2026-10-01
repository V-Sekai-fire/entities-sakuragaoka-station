# The outline term alone, per engine: a render with the outline on less the same render with it off, for the
# original (tools/oracle/shot.mjs --patch tools/oracle/outline_weight.js --patch-arg 0) and each port set
# (tools/stack_shots.gd's base and outline_off). In a compute shader it reports each set's contribution MAD
# against the original's (0..255), the full-frame MAD of its outline-on render, and the line pixels (a
# contribution of 8 levels or more) each side draws alone, and writes the lines and where they disagree.
#   godot --path . --resolution 640x360 --script tools/outline_split.gd -- --n=8 --set=original=<on_%d>,<off_%d>
#       --set=<label>=<on_%d>,<off_%d> ... [--gate=<before>,<after>] [--vis=<dir>] [--json=<file>]
#       [--sheet=<png> --topic=outline] [--self-test]
# --gate holds the after set's contribution MAD and full MAD no worse than the before set's in every view.
# --self-test plants a grid of one-pixel lines into each port contribution, which must lift its MAD and its
# lines the original lacks.
extends SceneTree

const Sheet = preload("res://tools/sheet.gd")
const LINE := 8.0

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba8, set = 0, binding = 0) uniform restrict readonly image2D port_on;
layout(rgba8, set = 0, binding = 1) uniform restrict readonly image2D port_off;
layout(rgba8, set = 0, binding = 2) uniform restrict readonly image2D orig_on;
layout(rgba8, set = 0, binding = 3) uniform restrict readonly image2D orig_off;
layout(rgba8, set = 0, binding = 4) uniform restrict writeonly image2D vis;
layout(set = 0, binding = 5, std430) restrict buffer Counts {
	uint c[];
} counts;
layout(push_constant, std430) uniform Params {
	ivec2 size;
	int plant;
	int view;
	float line;
	float pad0;
	float pad1;
	float pad2;
} p;

vec3 px(vec4 v) {
	return round(v.rgb * 255.0);
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= p.size.x || c.y >= p.size.y) {
		return;
	}
	vec3 pon = px(imageLoad(port_on, c));
	vec3 poff = px(imageLoad(port_off, c));
	if (p.plant != 0 && (c.x % 64 == 32 || c.y % 64 == 32)) {
		pon = max(pon - 40.0, 0.0);
	}
	vec3 op = pon - poff;
	vec3 oo = px(imageLoad(orig_on, c)) - px(imageLoad(orig_off, c));
	vec3 d = abs(op - oo);
	atomicAdd(counts.c[0], uint(d.r + d.g + d.b));
	vec3 f = abs(pon - px(imageLoad(orig_on, c)));
	atomicAdd(counts.c[4], uint(f.r + f.g + f.b));
	bool lp = max(abs(op.r), max(abs(op.g), abs(op.b))) >= p.line;
	bool lo = max(abs(oo.r), max(abs(oo.g), abs(oo.b))) >= p.line;
	if (lp) {
		atomicAdd(counts.c[1], 1u);
	}
	if (lo) {
		atomicAdd(counts.c[2], 1u);
	}
	if (lp && lo) {
		atomicAdd(counts.c[3], 1u);
	}
	vec3 o;
	if (p.view == 0) {
		o = vec3(1.0) - abs(op) * (3.0 / 255.0);
	} else if (p.view == 1) {
		o = vec3(1.0) - abs(oo) * (3.0 / 255.0);
	} else {
		o = lp && lo ? vec3(0.1) : (lp ? vec3(0.9, 0.1, 0.1) : (lo ? vec3(0.1, 0.35, 1.0) : vec3(1.0)));
	}
	imageStore(vis, c, vec4(clamp(o, 0.0, 1.0), 1.0));
}
"""

var _a := {}
var _sets := []
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()


func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if not s.begins_with("--"):
			continue
		var k := s.substr(2, s.find("=") - 2) if "=" in s else s.substr(2)
		var v := s.substr(s.find("=") + 1) if "=" in s else ""
		if k == "set":
			_sets.append({"label": v.substr(0, v.find("=")), "paths": v.substr(v.find("=") + 1).split(",")})
		else:
			_a[k] = v
	_run.call_deferred()


func _texture(img: Image) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = img.get_width()
	tf.height = img.get_height()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return _rd.texture_create(tf, RDTextureView.new(), [img.get_data()])


## A port set's two frames against the original's: {"mad", "full_mad", "port_px", "original_px", "both_px",
## "vis": [port lines, original lines, disagreement]}; vis only when wanted.
func measure(frames: Array, plant: bool, want_vis: bool) -> Dictionary:
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var tex := []
	for f in frames:
		tex.append(_texture(f))
	var blank := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var out := {"vis": []}
	for view in (3 if want_vis else 1):
		var vt := _texture(blank)
		var zero := PackedByteArray()
		zero.resize(20)
		var buf := _rd.storage_buffer_create(zero.size(), zero)
		var us := []
		for i in 5:
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u.binding = i
			u.add_id(tex[i] if i < 4 else vt)
			us.append(u)
		var ub := RDUniform.new()
		ub.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		ub.binding = 5
		ub.add_id(buf)
		us.append(ub)
		var set := _rd.uniform_set_create(us, _shader, 0)
		var pc := PackedInt32Array([w, h, 1 if plant else 0, view]).to_byte_array()
		pc.append_array(PackedFloat32Array([LINE, 0.0, 0.0, 0.0]).to_byte_array())
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, set, 0)
		_rd.compute_list_set_push_constant(list, pc, pc.size())
		_rd.compute_list_dispatch(list, (w + 7) / 8, (h + 7) / 8, 1)
		_rd.compute_list_end()
		_rd.submit()
		_rd.sync()
		var r := _rd.buffer_get_data(buf)
		out.mad = float(r.decode_u32(0)) / float(w * h * 3)
		out.port_px = r.decode_u32(4)
		out.original_px = r.decode_u32(8)
		out.both_px = r.decode_u32(12)
		out.full_mad = float(r.decode_u32(16)) / float(w * h * 3)
		if want_vis:
			out.vis.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _rd.texture_get_data(vt, 0)))
		for x in [set, buf, vt]:
			_rd.free_rid(x)
	for t in tex:
		_rd.free_rid(t)
	return out


static func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var im := Image.load_from_file(path)
	im.convert(Image.FORMAT_RGBA8)
	return im


func _run() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	var failed := 0
	if _rd != null:
		var src := RDShaderSource.new()
		src.source_compute = GLSL
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute == "":
			_shader = _rd.shader_create_from_spirv(spirv)
			_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid() or _sets.size() < 2:
		print("outline_split: FAIL no RenderingDevice, no shader, or fewer than two sets (run without --headless)")
		quit(1)
		return
	var n := int(_a.get("n", "8"))
	var want_vis := _a.has("vis") or _a.has("sheet")
	var res := {"line_levels": LINE, "sets": {}}
	var shots := {}
	print("outline_split: set | view | contribution MAD | full MAD | line px port, original, both | port alone | original alone")
	for v in n:
		var orig := [_load(_sets[0].paths[0] % v), _load(_sets[0].paths[1] % v)]
		for s in _sets.slice(1):
			var frames := [_load(s.paths[0] % v), _load(s.paths[1] % v)] + orig
			if frames.has(null) or frames.any(func(f): return f.get_size() != frames[0].get_size()):
				print("outline_split: FAIL %s view %d: a frame is missing or a different size" % [s.label, v])
				failed += 1
				continue
			var r := measure(frames, false, want_vis)
			var row := {"view": v, "mad": r.mad, "full_mad": r.full_mad, "port_px": r.port_px, "original_px": r.original_px,
					"both_px": r.both_px}
			print("outline_split: %-12s | %d | %6.3f | %6.2f | %7d %7d %7d | %7d | %7d" % [s.label, v, r.mad, r.full_mad,
					r.port_px, r.original_px, r.both_px, r.port_px - r.both_px, r.original_px - r.both_px])
			if _a.has("self-test"):
				var pl := measure(frames, true, false)
				var ok: bool = pl.mad > r.mad + 0.05 and pl.port_px - pl.both_px > r.port_px - r.both_px + 1000
				print("outline_split: self-test %s view %d: planted grid MAD %.3f -> %.3f, port-alone px %d -> %d %s" % [s.label, v,
						r.mad, pl.mad, r.port_px - r.both_px, pl.port_px - pl.both_px, "ok" if ok else "FAIL"])
				row.planted_mad = pl.mad
				failed += 0 if ok else 1
			if _a.has("vis"):
				DirAccess.make_dir_recursive_absolute(_a.vis)
				for i in 3:
					r.vis[i].save_png(_a.vis.path_join("%s_%s_%d.png" % [s.label, ["port", "original", "disagree"][i], v]))
			if _a.has("sheet"):
				for im in r.vis:
					im.resize(480, 270, Image.INTERPOLATE_BILINEAR)
				shots["%s/%d" % [s.label, v]] = {"row": row, "vis": r.vis}
			if not res.sets.has(s.label):
				res.sets[s.label] = []
			res.sets[s.label].append(row)
	failed += _gate(res, n)
	if _a.has("sheet"):
		await _sheet(shots, n)
	if _a.has("json"):
		var f := FileAccess.open(_a.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
	_rd.free_rid(_pipeline)
	_rd.free_rid(_shader)
	_rd.free()
	print("outline_split: %s" % ("FAIL (%d)" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _gate(res: Dictionary, n: int) -> int:
	var g: PackedStringArray = _a.get("gate", "").split(",", false)
	if g.size() != 2:
		return 0
	var bad := 0
	for v in n:
		var b: Array = res.sets.get(g[0], []).filter(func(r): return r.view == v)
		var a: Array = res.sets.get(g[1], []).filter(func(r): return r.view == v)
		if b.is_empty() or a.is_empty() or a[0].mad > b[0].mad or a[0].full_mad > b[0].full_mad:
			bad += 1
			print("outline_split: gate view %d: %s against %s FAIL (contribution MAD %s vs %s, full MAD %s vs %s)" % [v, g[1], g[0],
					a[0].mad if a else "none", b[0].mad if b else "none", a[0].full_mad if a else "none", b[0].full_mad if b else "none"])
	print("outline_split: gate %s no worse than %s in %d of %d views %s" % [g[1], g[0], n - bad, n, "PASS" if bad == 0 else "FAIL"])
	return 1 if bad else 0


## One row per view, the worst contribution MAD first: the original's lines, then each port set's lines and where they
## disagree with the original's (black both, red the port alone, blue the original alone).
func _sheet(shots: Dictionary, n: int) -> void:
	var columns := ["original, outline term alone"]
	for s in _sets.slice(1):
		columns.append("%s, outline term alone" % s.label)
		columns.append("%s against the original" % s.label)
	var rows := []
	for v in n:
		var cells := []
		var worst := 0.0
		for s in _sets.slice(1):
			var x: Dictionary = shots.get("%s/%d" % [s.label, v], {})
			if x.is_empty():
				continue
			if cells.is_empty():
				cells.append({"image": x.vis[1], "label": "original: %d line px" % x.row.original_px})
			worst = maxf(worst, x.row.mad)
			cells.append({"image": x.vis[0], "label": "%s: %d line px, term MAD %.3f, full MAD %.2f" % [s.label, x.row.port_px,
					x.row.mad, x.row.full_mad]})
			cells.append({"image": x.vis[2], "label": "%d alone (red), original %d alone (blue)" % [x.row.port_px - x.row.both_px,
					x.row.original_px - x.row.both_px]})
		rows.append({"label": "view %d: worst outline-term MAD %.3f" % [v, worst], "cells": cells, "worst": worst})
	rows.sort_custom(func(x, y): return x.worst > y.worst)
	var img: Image = await Sheet.render(self, _a.get("title", "outline term alone (on less off), line = 8+ levels"), columns, rows,
			Vector2i(480, 270))
	for p in Sheet.publish(img, _a.sheet, _a.get("topic", "outline")):
		print("outline_split: sheet ", p)
