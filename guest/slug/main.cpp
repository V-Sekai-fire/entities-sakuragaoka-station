// slug.elf -- the canvas textures' compute for the sakuragaoka-station port: SVG (ThorVG) ->
// slughorn atlas (curve + band textures, per-key layer table), Slug -> planar mesh bakes, decal
// clipping. The port calls it through addons/sakuragaoka_station/core/slug/guest.gd.
//
// The godot-lite split (3-interactor/curvenet/guest/curvenet/main.cpp): this TU sees the
// sandbox's api.hpp and slug_api.h (std types) and nothing of slughorn's; slug_api.cpp sees
// slughorn and nothing of the sandbox's. So all marshalling is here. Meshes follow
// 2-contract/guest-common/guest/common/mesh_wire.h (vertices 3N float, triangles 3F int32, CCW).
//
// Call order: slug_load_svg(key, svg_text, tolerance_px) once per key (each call is one key, so
// no single call carries the whole station), then slug_atlas(), then any slug_cost / slug_mesh /
// slug_decal. A slug_load_svg after slug_atlas re-packs on the next slug_atlas.

#include <api.hpp>

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include "slug_api.h"

static Variant text(const std::string &s) {
	return Variant(String(s));
}

template <typename T>
static Variant packed(const std::vector<T> &v) {
	return Variant(PackedArray<T>(v));
}

// libriscv refuses to marshal a guest std::vector over 16 MiB in one transfer (guest_datatypes.hpp
// max_bytes); the station's curve and band textures are ~25 MiB each. Build the host-side array
// from the first slice and append the rest host-side, so the wire stays one PackedByteArray.
static constexpr size_t SLICE_BYTES = 8u << 20;

template <typename T>
static Variant packed_big(const std::vector<T> &v) {
	const size_t slice = SLICE_BYTES / sizeof(T);

	if (v.size() <= slice) {
		return packed(v);
	}

	PackedArray<T> out(v.data(), slice);

	for (size_t at = slice; at < v.size(); at += slice) {
		const size_t n = std::min(slice, v.size() - at);
		out("append_array", Variant(PackedArray<T>(v.data() + at, n)));
	}

	return Variant(out);
}

static Variant fail(const std::string &err) {
	Dictionary d = Dictionary::Create();
	d["error"] = text(err);
	return d;
}

static Variant slug_reset() {
	return text(slug::reset());
}

static Variant slug_load_svg(String key, String svg, double tolerance_px) {
	return text(slug::load_svg(key.utf8(), svg.utf8(), tolerance_px));
}

static Variant slug_set_wrap(String key, bool wrap) {
	return text(slug::set_wrap(key.utf8(), wrap));
}

static Variant slug_keys() {
	return Variant(PackedArray<std::string>(slug::keys()));
}

// Dictionary: tex_width, curve_format, curve_height, curves, band_height, bands, keys, key_layers,
// key_frames, layers, gradients (core/slug/atlas.gd documents each). {"error": ...} on failure.
static Variant slug_atlas() {
	slug::Atlas a;
	std::string err;

	if (!slug::atlas(a, err)) {
		return fail(err);
	}

	Dictionary d = Dictionary::Create();
	d["tex_width"] = int64_t(a.tex_width);
	d["curve_format"] = text(a.curve_format);
	d["curve_height"] = int64_t(a.curve_height);
	d["curves"] = packed_big(a.curves);
	d["band_height"] = int64_t(a.band_height);
	d["bands"] = packed_big(a.bands);
	d["keys"] = Variant(PackedArray<std::string>(a.keys));
	d["key_layers"] = packed(a.key_layers);
	d["key_frames"] = packed(a.key_frames);
	d["layers"] = packed_big(a.layers);
	d["gradients"] = packed(a.gradients);
	d["stamp_protos"] = packed_big(a.stamp_protos);
	d["stamp_instances"] = packed_big(a.stamp_instances);
	d["stamp_layers"] = packed_big(a.stamp_layers);
	d["stamp_cells"] = packed_big(a.stamp_cells);
	d["stamp_means"] = packed_big(a.stamp_means);
	d["stamp_cell_max"] = packed_big(a.stamp_cell_max);
	return d;
}

// Dictionary: mode ("mesh" | "slug" | "mean") plus the record behind it. {} for an unknown key.
static Variant slug_cost(String key) {
	slug::Cost c;
	std::string err;

	if (!slug::cost(key.utf8(), c, err)) {
		return Dictionary::Create();
	}

	Dictionary d = Dictionary::Create();
	d["mode"] = text(c.mode);
	d["curves"] = c.curves;
	d["curves_before"] = c.curves_before;
	d["curves_after"] = c.curves_after;
	d["max_band_curves_h"] = c.max_band_curves_h;
	d["max_band_curves_v"] = c.max_band_curves_v;
	d["slug_work"] = c.slug_work;
	d["slug_work_mean"] = c.slug_work_mean;
	d["layers_before"] = c.layers_before;
	d["layers_after"] = c.layers_after;
	d["stroke_layers"] = c.stroke_layers;
	d["gradient_layers"] = c.gradient_layers;
	d["triangles_before"] = c.triangles_before;
	d["triangles_after"] = c.triangles_after;
	d["stamp_layers"] = c.stamp_layers;
	d["stamp_instances"] = c.stamp_instances;
	d["stamp_max_per_cell"] = c.stamp_max_per_cell;
	d["stamp_grid"] = c.stamp_grid;
	d["stamp_depth"] = c.stamp_depth;
	d["stamp_work"] = c.stamp_work;
	d["tolerance_px"] = c.tolerance_px;
	d["width"] = c.width;
	d["height"] = c.height;
	return d;
}

// Dictionary (core/slug/baked.gd): vertices, triangles, paint, param, paints, overlay. {} for an
// unknown key. alpha_test 0: the planar bake; > 0: the cutout bake (no overlay).
static Variant mesh_dict(const std::string &key, double alpha_test) {
	slug::Mesh m;
	std::string err;

	if (!slug::mesh(key, alpha_test, m, err)) {
		return Dictionary::Create();
	}

	Dictionary d = Dictionary::Create();
	d["vertices"] = packed_big(m.vertices);
	d["triangles"] = packed_big(m.triangles);
	d["paint"] = packed_big(m.paint);
	d["param"] = packed_big(m.param);
	d["paints"] = packed(m.paints);
	d["overlay"] = packed(std::vector<int32_t>{m.overlay_first, m.overlay_count});
	return d;
}

// slug_mesh(key): the planar bake. A sandbox call that passes fewer arguments than the function
// declares hands it garbage for the rest (measured: slug_mesh(key) against a 2-argument slug_mesh
// returned a cutout), so the alpha test is a separate function rather than an optional argument.
static Variant slug_mesh(String key) {
	return mesh_dict(key.utf8(), 0.0);
}

// slug_mesh_cutout(key, alpha_test): composite alpha >= alpha_test kept opaque with the
// unpremultiplied composite colour, the rest dropped, no overlay (three.js alphaTest on the canvas).
static Variant slug_mesh_cutout(String key, double alpha_test) {
	return mesh_dict(key.utf8(), alpha_test);
}

// slug_decal(key, vertices 3N, normals 3N or empty, uvs 2N, triangles 3F, uv_xform [repeat.x,
// repeat.y, offset.x, offset.y, wrap 0/1], lift [base, overlay, cap, alpha_test]); alpha_test > 0
// clips the cutout bake (cards). With 6+ floats in lift_cap it is slug-baked (see the branch
// below: alpha folded in, LOD to the cap, never capped). The cap (max output
// triangles) rides in lift's third slot: the sandbox passes at most 7 arguments to a guest
// function ("Too many arguments for VM function call (register overflow)"), so the proposed
// eighth `cap` argument cannot exist. Without a third slot there is no cap.
static Variant lods_wire(const std::vector<slug::Lod> &lods) {
	std::vector<float> w;

	for (const slug::Lod &l : lods) {
		w.insert(w.end(), {float(l.level), float(l.triangles), float(l.surface_triangles), float(l.feature_px), float(l.tolerance_px),
						   float(l.simplify_error_px), l.aborted ? 1.0f : 0.0f});
	}

	return packed(w);
}

static slug::BakeParams bake_params(const std::vector<float> &p, size_t mode_at, size_t test_at, size_t opacity_at, size_t cap_at) {
	slug::BakeParams b;

	b.mode = p.size() > mode_at ? int(p[mode_at]) : 2;
	b.alpha_test = p.size() > test_at ? double(p[test_at]) : 0.5;
	b.opacity = p.size() > opacity_at ? double(p[opacity_at]) : 1.0;
	b.cap = p.size() > cap_at ? int64_t(p[cap_at]) : 0;

	return b;
}

// slug_bake(key_spec, params [mode, alpha_test, opacity, cap, feature_floor_px, wx0, wy0, wx1, wy1]):
// slug-baked, the key spec's ("map|alphaMap") final composite at the finest LOD within cap (cap 0:
// level 0), as a UV mesh (mesh_wire, v up, no overlay; paints with the final alpha). mode 0 opaque,
// 1 transparent, 2 alpha test. Also: lod, lods (7 floats a level: level, triangles,
// surface_triangles, feature_px, tolerance_px, simplify_error_px, aborted), transparent_area /
// canvas_area (opaque mode: px^2 whose final alpha < 1 - transparent at the end), folded, feature_px.
static Variant slug_bake(String key_spec, PackedArray<float> params) {
	const std::vector<float> p = params.fetch();
	slug::BakeParams b = bake_params(p, 0, 1, 2, 3);
	slug::FinalBake o;
	std::string err;

	b.feature_floor_px = p.size() > 4 ? double(p[4]) : 0.0;

	for (size_t i = 0; i < 4; ++i) {
		b.window[i] = p.size() > 5 + i ? double(p[5 + i]) : 0.0;
	}

	if (!slug::bake(key_spec.utf8(), b, o, err)) {
		return fail(err);
	}

	Dictionary d = Dictionary::Create();
	d["vertices"] = packed_big(o.mesh.vertices);
	d["triangles"] = packed_big(o.mesh.triangles);
	d["paint"] = packed_big(o.mesh.paint);
	d["param"] = packed_big(o.mesh.param);
	d["paints"] = packed(o.mesh.paints);
	d["overlay"] = packed(std::vector<int32_t>{int32_t(o.mesh.triangles.size()), 0});
	d["lod"] = int64_t(o.lod);
	d["lods"] = lods_wire(o.lods);
	d["transparent_area"] = o.transparent_area;
	d["canvas_area"] = o.canvas_area;
	d["transparent_at_end"] = b.mode == 0 && o.transparent_area > 0.0;
	d["folded"] = o.folded_features;
	d["feature_px"] = o.feature_px;
	return d;
}

static Variant slug_decal(String key, PackedArray<float> vertices, PackedArray<float> normals, PackedArray<float> uvs,
		PackedArray<int32_t> triangles, PackedArray<float> uv_xform, PackedArray<float> lift_cap) {
	slug::Decal o;
	std::string err;

	std::vector<float> lc = lift_cap.fetch();

	// slug-baked: lift_cap [base, overlay, cap, alpha_test, opacity, mode, feature_floor_world]
	// (key = "map|alphaMap"); never capped - the finest LOD whose triangles fit.
	if (lc.size() >= 6) {
		slug::BakeParams b = bake_params(lc, 5, 3, 4, 2);
		const double floorWorld = lc.size() >= 7 ? double(lc[6]) : 0.0;
		std::vector<float> lift{lc[0], lc[1]};

		if (!slug::decal_final(key.utf8(), vertices.fetch(), normals.fetch(), uvs.fetch(), triangles.fetch(), uv_xform.fetch(),
					lift, b, floorWorld, o, err)) {
			Dictionary d = Dictionary::Create();
			d["capped"] = false;
			d["vertices"] = packed(std::vector<float>{});
			d["normals"] = packed(std::vector<float>{});
			d["paint"] = packed(std::vector<int32_t>{});
			d["param"] = packed(std::vector<float>{});
			d["paints"] = packed(std::vector<float>{0.0f});
			d["overlay_from"] = int64_t(0);
			d["error"] = text(err);
			return d;
		}

		Dictionary d = Dictionary::Create();
		d["capped"] = false;
		d["vertices"] = packed_big(o.vertices);
		d["normals"] = packed_big(o.normals);
		d["paint"] = packed_big(o.paint);
		d["param"] = packed_big(o.param);
		d["paints"] = packed(o.paints);
		d["overlay_from"] = int64_t(o.overlay_from);
		d["lod"] = int64_t(o.lod);
		d["lods"] = lods_wire(o.lods);
		d["transparent_area"] = o.transparent_area;
		d["canvas_area"] = o.canvas_area;
		d["transparent_at_end"] = b.mode == 0 && o.transparent_area > 0.0;
		d["world_per_uv"] = o.world_per_uv;
		d["feature_px"] = o.feature_px;
		return d;
	}
	const int64_t cap = lc.size() >= 3 ? int64_t(lc[2]) : INT64_MAX;
	const double alpha_test = lc.size() >= 4 ? double(lc[3]) : 0.0;
	lc.resize(2, 0.0f);

	if (!slug::decal(key.utf8(), vertices.fetch(), normals.fetch(), uvs.fetch(), triangles.fetch(), uv_xform.fetch(),
				lc, cap, alpha_test, o, err)) {
		Dictionary d = Dictionary::Create();
		d["capped"] = false;
		d["vertices"] = packed(std::vector<float>{});
		d["normals"] = packed(std::vector<float>{});
		d["paint"] = packed(std::vector<int32_t>{});
		d["param"] = packed(std::vector<float>{});
		d["overlay_from"] = int64_t(0);
		d["error"] = text(err);
		return d;
	}

	Dictionary d = Dictionary::Create();
	d["capped"] = o.capped;

	if (!o.capped) {
		d["vertices"] = packed_big(o.vertices);
		d["normals"] = packed_big(o.normals);
		d["paint"] = packed_big(o.paint);
		d["param"] = packed_big(o.param);
		d["overlay_from"] = int64_t(o.overlay_from);
	}

	return d;
}

// CPU reference raster of a key (premultiplied linear RGBA floats, row 0 = canvas top).
static Variant slug_render(String key, int width, int height) {
	std::vector<float> img;
	std::string err;

	if (!slug::render(key.utf8(), width, height, img, err)) {
		return packed(std::vector<float>{});
	}

	return packed_big(img);
}

int main() {
	ADD_API_FUNCTION(slug_reset, "String", "", "Drop every key, the atlas and every bake");
	ADD_API_FUNCTION(slug_load_svg, "String", "String key, String svg, float tolerance_px",
			"Load one <key>.svg's text (ThorVG) and merge its layers; ok/FAIL line");
	ADD_API_FUNCTION(slug_set_wrap, "String", "String key, bool wrap",
			"Key sampled with repeat wrapping: stamp instances crossing an edge are copied to the opposite edge");
	ADD_API_FUNCTION(slug_keys, "PackedStringArray", "", "Keys loaded so far");
	ADD_API_FUNCTION(slug_atlas, "Dictionary", "",
			"Pack every loaded key into one slughorn atlas: textures, per-key layer table, gradients");
	ADD_API_FUNCTION(slug_cost, "Dictionary", "String key", "mode (mesh | slug | mean) and the cost record");
	ADD_API_FUNCTION(slug_mesh, "Dictionary", "String key", "The key's planar bake (mesh_wire, UV 0..1 v up)");
	ADD_API_FUNCTION(slug_mesh_cutout, "Dictionary", "String key, float alpha_test",
			"The key's cutout bake at alpha_test (opaque, no overlay; mesh_wire, UV 0..1 v up)");
	ADD_API_FUNCTION(slug_render, "PackedFloat32Array", "String key, int width, int height",
			"CPU reference of the key (stamps included, linear, no fade): premultiplied RGBA, row 0 = top");
	ADD_API_FUNCTION(slug_bake, "Dictionary", "String key_spec, PackedFloat32Array params",
			"slug-baked: the final composite (map|alphaMap) at the finest LOD within cap (mesh_wire UV, paints with alpha)");
	ADD_API_FUNCTION(slug_decal, "Dictionary",
			"String key, PackedFloat32Array vertices, PackedFloat32Array normals, PackedFloat32Array uvs, PackedInt32Array triangles, PackedFloat32Array uv_xform, PackedFloat32Array lift_cap",
			"Clip the key's bake onto a surface's UV footprint");
	halt();
}
