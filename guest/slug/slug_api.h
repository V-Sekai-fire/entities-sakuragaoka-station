// slug_api -- slug.elf's compute, std types only.
//
// The godot-lite split (3-interactor/curvenet/guest/curvenet): main.cpp sees the sandbox's api.hpp
// and this header and nothing of slughorn's; slug_api.cpp sees slughorn (+ ThorVG, Clipper2,
// earcut) and nothing of the sandbox's. All marshalling (PackedArray <-> std::vector, String <->
// std::string, Dictionary) happens in main.cpp. The same TU links into the native harness
// (tests/native.cpp), which is how the API is exercised off-sandbox.
//
// Lifecycle: load_svg() once per key (one call per key keeps every call small), optionally
// set_wrap() for keys sampled with repeat wrapping, then atlas() packs every loaded key into one
// slughorn Atlas (built once; a later load_svg() / set_wrap() marks it dirty and the next atlas()
// rebuilds). mesh() / cost() / decal() bake on demand from that built atlas and cache per key (and
// alpha test). Wire formats are documented on each function and match the port's
// addons/sakuragaoka_station/core/slug/{atlas,baked,stamps}.gd and slug.gdshaderinc.
//
// Colours on every wire are LINEAR RGBA (the sRGB-encoded SVG colours through the sRGB EOTF per
// channel, alpha unchanged); gradient stops are converted the same way.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace slug {

// Drop every key, the atlas and every cached bake.
std::string reset();

// Load one SVG under `key` with ThorVG (stamp runs lifted into stamp layers first), merge its
// same-paint layers, keep it for the next atlas(). tolerance_px is the planar mesh's flattening
// chord tolerance (texture pixels) for this key. Answers
// "ok key=K width=W height=H layers=A->B curves=C->D stamp_layers=S instances=N depth=D warnings=N"
// or "FAIL: ...".
std::string load_svg(const std::string &key, const std::string &svg, double tolerance_px);

// Mark `key` as sampled with repeat wrapping: its stamp instances crossing a canvas edge get
// copies at the opposite edge (seamless tiling). "ok" / "FAIL: unknown key".
std::string set_wrap(const std::string &key, bool wrap);

// Keys loaded so far, load order.
std::vector<std::string> keys();

struct Atlas {
	int tex_width = 0;
	std::string curve_format;          // "RGBA32F"
	int curve_height = 0;
	std::vector<uint8_t> curves;       // row-major curve texture bytes
	int band_height = 0;
	std::vector<uint8_t> bands;        // row-major RG16UI band texture bytes (4 bytes a texel)
	std::vector<std::string> keys;     // table order
	std::vector<int32_t> key_layers;   // 2 per key: first layer, layer count
	std::vector<float> key_frames;     // 4 per key: width px, height px, em per px, y_down (1)
	std::vector<float> layers;         // LAYER_STRIDE per layer (key layers, then curve prototypes)
	std::vector<float> gradients;      // [n, per gradient: type, xx, yx, xy, yy, dx, dy,
	                                   //  inner_radius, start_angle, end_angle, k, k*(t,r,g,b,a)]

	// Stamp layers (see slug_api.cpp for the exact layouts).
	std::vector<float> stamp_protos;     // 2 per prototype: kind, layer
	std::vector<float> stamp_instances;  // 12 per instance
	std::vector<int32_t> stamp_layers;   // 5 per stamp layer
	std::vector<uint8_t> stamp_cells;    // RG16UI texels (4 bytes)
	std::vector<uint8_t> stamp_means;    // RGBA8 per cell
	std::vector<float> stamp_cell_max;   // 1 per cell
};

constexpr int LAYER_STRIDE = 24;
constexpr int STAMP_BLEND = 100;

// Builds (when dirty) and returns the atlas. `err` says what failed.
bool atlas(Atlas &out, std::string &err);

struct Mesh {
	std::vector<float> vertices;    // 3N: u, v, 0 (UV 0..1, v up: v = 1 is the canvas top)
	std::vector<int32_t> triangles; // 3F, CCW in UV; opaque planar base first, then the overlay
	std::vector<int32_t> paint;     // N, paint id per vertex
	std::vector<float> param;       // 2N: linear (t, 0); radial (gx, gy), t = length; solid (0, 0)
	std::vector<float> paints;      // [n, per paint: type (0 solid, 1 linear, 2 radial), k, k*(t,r,g,b,a)]
	int32_t overlay_first = 0;      // first overlay index into triangles
	int32_t overlay_count = 0;      // overlay index count (0 for a cutout bake)
};

// The key's planar bake (alpha_test 0) or its cutout bake (alpha_test > 0: composite alpha >=
// alpha_test kept opaque with the unpremultiplied composite colour, the rest dropped, no overlay).
// False when the key is unknown (or the atlas cannot be built).
bool mesh(const std::string &key, double alpha_test, Mesh &out, std::string &err);

struct Cost {
	std::string mode;               // "mesh" | "stamp" | "slug" | "mean"
	int64_t curves = 0;
	int64_t curves_before = 0;
	int64_t curves_after = 0;
	int64_t max_band_curves_h = 0;
	int64_t max_band_curves_v = 0;
	int64_t slug_work = 0;
	double slug_work_mean = 0.0;
	int64_t layers_before = 0;
	int64_t layers_after = 0;
	int64_t stroke_layers = 0;
	int64_t gradient_layers = 0;
	int64_t triangles_before = 0;
	int64_t triangles_after = 0;
	int64_t stamp_layers = 0;
	int64_t stamp_instances = 0;
	int64_t stamp_max_per_cell = 0;
	int64_t stamp_grid = 0;
	int64_t stamp_depth = 0;
	double stamp_work = 0.0;
	double tolerance_px = 0.0;
	double width = 0.0, height = 0.0;
};

bool cost(const std::string &key, Cost &out, std::string &err);

// CPU reference of a key's whole canvas (slughorn render::renderComposite with stamp layers, linear
// light, the shader's coverage and no distance fade) at width x height: premultiplied linear RGBA
// floats, row-major, row 0 = canvas top (UV v = 1). What the port's slug.gdshaderinc must match.
bool render(const std::string &key, int width, int height, std::vector<float> &out, std::string &err);

// ---- slug-baked: the final composite at an LOD within a budget (bake::bakeFinal) ----------------
// A key spec is "colorKey|alphaKey": the material's map and alphaMap keys ("|alphaKey": an alpha
// map over the material colour alone, the map taken as white; "colorKey": no alpha map). three.js:
// rgb = map, alpha = map alpha x opacity x alphaMap.g.

struct BakeParams {
	int mode = 2;                    // 0 opaque, 1 transparent (base-colour alpha), 2 alpha test
	double alpha_test = 0.5;
	double opacity = 1.0;
	int64_t cap = 0;                 // max triangles; 0 = no cap (level 0)
	double feature_floor_px = 0.0;   // fold features narrower than this (texture px) at every level
	double window[4] = {0, 0, 0, 0}; // canvas px x0, y0, x1, y1; all 0 = the whole canvas
};

constexpr int LOD_MEAN = 15;         // the level after the last (bake::LOD_LEVELS): the mean colour

struct Lod {
	int level = 0;
	int64_t triangles = 0;           // the level's bake of the window
	int64_t surface_triangles = -1;  // after clipping onto the surface (-1: not clipped / past cap)
	double feature_px = 0.0;         // features narrower than this were folded into local means
	double tolerance_px = 0.0;       // flattening / outline tolerance
	double simplify_error_px = 0.0;  // meshoptimizer's error, when it was tried on this level
	bool aborted = false;            // the bake passed 8 x cap and stopped
};

struct FinalBake {
	Mesh mesh;                       // UV (v up), no overlay; paints carry the final alpha
	int lod = 0;
	std::vector<Lod> lods;           // every level tried, finest first
	double transparent_area = 0.0;   // opaque mode: px^2 whose final alpha < 1 (shown straight)
	double canvas_area = 0.0;        // px^2 of the window
	int64_t folded_features = 0;
	double feature_px = 0.0;
};

// The spec's final bake over the window at the finest level within cap (meshoptimizer first
// when a level is within 8x of it), else the mean.
bool bake(const std::string &key_spec, const BakeParams &p, FinalBake &out, std::string &err);

struct Decal {
	bool capped = false;
	std::vector<float> vertices;    // 9T unindexed, CCW outward, lifted
	std::vector<float> normals;     // 9T
	std::vector<int32_t> paint;     // T, paint id per triangle
	std::vector<float> param;       // 6T, per vertex as Mesh::param
	int32_t overlay_from = 0;       // first overlay triangle

	// decal_final only.
	std::vector<float> paints;      // this result's paints (Mesh::paints layout, with alpha)
	int lod = -1;
	std::vector<Lod> lods;
	double transparent_area = 0.0;
	double canvas_area = 0.0;       // px^2 of the surface's window
	double world_per_uv = 0.0;      // the surface's texel density (world units per UV unit)
	double feature_px = 0.0;        // folded below this at the chosen level (x world_per_uv / width = world)
};

// Clips the key's bake onto a surface (see slug_api.cpp). uv_xform = repeat.x, repeat.y,
// offset.x, offset.y, wrap (0/1); lift = base, overlay (input units); cap = max output triangles;
// alpha_test > 0 clips the cutout bake instead (cards: lift 0).
bool decal(const std::string &key, const std::vector<float> &vertices, const std::vector<float> &normals,
		const std::vector<float> &uvs, const std::vector<int32_t> &triangles, const std::vector<float> &uv_xform,
		const std::vector<float> &lift, int64_t cap, double alpha_test, Decal &out, std::string &err);

// slug-baked onto a surface: the window is the surface's UV footprint, the cap its budget, and
// the finest LOD level whose clipped triangles fit is returned (never capped; past every level,
// the surface's own faces in the mean colour). feature_floor_world > 0 folds features narrower
// than that many world units at every level (via the surface's texel density).
bool decal_final(const std::string &key_spec, const std::vector<float> &vertices, const std::vector<float> &normals,
		const std::vector<float> &uvs, const std::vector<int32_t> &triangles, const std::vector<float> &uv_xform,
		const std::vector<float> &lift, const BakeParams &params, double feature_floor_world, Decal &out, std::string &err);

} // namespace slug
