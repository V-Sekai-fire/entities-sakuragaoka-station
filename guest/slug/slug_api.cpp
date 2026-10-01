// slug_api.cpp -- slug.elf's compute on slughorn (ThorVG SVG loading, Clipper2, earcut). Sees
// nothing of the sandbox (see slug_api.h for the split and the lifecycle).
//
// Pipeline per key (load_svg): stamp runs (<g data-stamp-run> of <use> of <symbol
// data-stamp-kind>) are lifted out of the SVG text into stamp layers (slughorn/stamp.hpp), the rest
// goes through ThorVG (slughorn/thorvg.hpp: fills, gradients, strokes expanded to fills, clip paths
// intersected), then slughorn/bake.hpp merges runs of same-solid-paint layers, keeping painter's
// order. atlas() packs every key's merged shapes and curve prototypes into ONE slughorn Atlas (one
// composite per key; stamp layers as placeholders) and lays the stamp layers out for the port's
// shader. mesh() bakes a key from that built atlas's own contours (Slug -> mesh), stamps expanded.
//
// ---------------------------------------------------------------------------------- atlas wire
// slug_atlas() Dictionary (core/slug/atlas.gd, stamps.gd, slug.gdshaderinc):
//   tex_width, curve_format "RGBA32F", curve_height, curves (bytes), band_height, bands (RG16UI
//   bytes), keys, key_layers (2 per key: first layer, count), key_frames (4 per key: width px,
//   height px, em per px = 1 / width, y_down = 1), gradients ([n, per gradient: type (0 linear,
//   1 radial, 2 sweep, 3 affine radial), xx, yx, xy, yy, dx, dy, inner radius, start angle, end
//   angle, k, k x (t, r, g, b, a)], colours linear).
//   layers: 24 floats per layer. First every key's layers (key_layers ranges), then one record per
//   CURVE stamp prototype (outside every key range). A record:
//     0 band_tex_x  1 band_tex_y  2 band_max_x  3 band_max_y  4 band_scale_x  5 band_scale_y
//     6 band_offset_x  7 band_offset_y  8 bearing_x  9 bearing_y  10 width  11 height
//     12 transform.x - origin_x  13 transform.y - origin_y  14 gradient id (1-based, 0 none)
//     15 blend mode  16..19 colour, linear straight RGBA  20..23 zero
//   A stamp layer's record: all zero except 14 = its stamp layer index, 15 = 100, 16..19 = 1.
//   A curve prototype's record is an ordinary band layer whose canvas em IS the prototype frame
//   (slots 12..13 = 0).
//   stamp_protos     2 floats per prototype: kind (0 curve, 1 ellipse = unit circle at the origin,
//                    2 rect = the 0..1 square), layer (kind 0: index into "layers"; else -1)
//   stamp_instances  12 floats per instance: a, b, c, d, e, f, proto id, paint, r, g, b, a with
//                    q = (a x + c y + e, b x + d y + f) the prototype-frame point of canvas em
//                    (x, y); paint 0 = solid colour, > 0 = 1-based id into "gradients" (defined in
//                    the prototype frame, evaluated at q) times the colour; colour linear straight
//   stamp_layers     5 int32 per stamp layer: G, first cell texel B, first instance, instance
//                    count, max instances per cell (<= 32)
//   stamp_cells      bytes, RG16UI texels (two little-endian u16 = 4 bytes a texel). Per stamp
//                    layer from texel B: G x G header texels (list start in u16 elements counted
//                    from element 2B, count), cell (i, j) at B + j G + i with (i, j) = floor(UV G)
//                    over three.js UV (v up); then the lists as u16 elements, instance indices
//                    relative to the layer's first instance, paint order; a layer ends on a texel
//                    boundary. Each layer < 65536 instances and < 65536 elements (split otherwise).
//   stamp_means      bytes, 4 per cell (premultiplied linear RGBA8 mean of the layer alone),
//                    stamp layers in order, cells in index order
//   stamp_cell_max   floats, 1 per cell (same order): the largest bbox side, canvas em, of any
//                    instance listed in the cell (fade footprint bound: px <= value x px per em)

#include "slug_api.h"

#include <slughorn/bake.hpp>
#include <slughorn/stamp.hpp>
#include <slughorn/thorvg.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <unordered_map>

namespace slug {

namespace {

using slughorn::slug_t;

struct KeyData {
	std::string key;
	float width = 0.0f, height = 0.0f;
	double tolerancePx = 0.25;
	bool wrap = false;

	// Merged layers, independent of the global atlas (re-registered on every rebuild). Stamp
	// layers are placeholders (stamp.hpp) with an empty shape.
	std::vector<slughorn::Atlas::ShapeInfo> shapes; // one per layer (empty curves for stamp layers)
	std::vector<slughorn::Layer> layers;            // gradientId indexes `gradients` (1-based)
	std::vector<slughorn::GradientInfo> gradients;
	std::vector<slughorn::bake::LayerSource> sources;
	slughorn::stamp::Set stamps;                    // as loaded (no wrap copies, not split)

	size_t layersBefore = 0;
	size_t curvesBefore = 0;
	size_t curvesAfter = 0;
};

// A key as packed into the current atlas: its stamps with wrap copies and depth / limit splits
// applied, its composite (placeholders renumbered) and sources aligned with it.
struct Built {
	slughorn::stamp::Set stamps;
	slughorn::CompositeShape comp;
	std::vector<slughorn::bake::LayerSource> sources;
	uint32_t depth = 0;
	size_t firstStampLayer = 0; // global stamp layer index of stamps.layers[0]
};

struct Baked {
	slughorn::bake::BakedMesh mesh;
	bool costed = false;
	slughorn::bake::Cost cost;
};

struct State {
	std::vector<KeyData> keys;
	std::unordered_map<std::string, size_t> index;

	std::unique_ptr<slughorn::Atlas> atlas;
	std::vector<Built> built; // parallel to keys
	bool dirty = true;

	// The last few bakes only: a sandbox heap counts live allocations (allocations_max), and a
	// cutout bake of a big key holds many. Costs are kept for every key (small).
	static constexpr size_t BAKE_CACHE = 4;

	std::map<std::pair<std::string, int64_t>, Baked> baked; // (key, alpha test x 1e6)
	std::vector<std::pair<std::string, int64_t>> bakeOrder;  // least recently used first
	std::map<std::string, slughorn::bake::Cost> costs;
};

State &state() {
	static State s;
	return s;
}

float srgbToLinear(float c) {
	c = std::clamp(c, 0.0f, 1.0f);
	return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

void pushLinear(std::vector<float> &out, const slughorn::Color &c) {
	out.push_back(srgbToLinear(c.r));
	out.push_back(srgbToLinear(c.g));
	out.push_back(srgbToLinear(c.b));
	out.push_back(c.a);
}

std::string layerKey(const std::string &key, size_t i) {
	return key + "/l_" + std::to_string(i);
}

const KeyData *findKey(const std::string &key) {
	State &s = state();
	std::unordered_map<std::string, size_t>::iterator it = s.index.find(key);
	return it == s.index.end() ? nullptr : &s.keys[it->second];
}

bool ensureAtlas(std::string &err) {
	State &s = state();

	if (s.atlas && !s.dirty) {
		return true;
	}

	if (s.keys.empty()) {
		err = "no keys loaded (call slug_load_svg first)";
		return false;
	}

	std::unique_ptr<slughorn::Atlas> atlas = std::make_unique<slughorn::Atlas>();
	std::vector<Built> built;
	size_t stampBase = 0;

	for (const KeyData &k : s.keys) {
		Built b;

		b.stamps = k.stamps;
		b.comp.advance = 1.0f;

		std::vector<uint32_t> gradMap(k.gradients.size() + 1, 0);

		for (size_t g = 0; g < k.gradients.size(); ++g) {
			gradMap[g + 1] = atlas->addGradient(k.gradients[g]);
		}

		for (size_t i = 0; i < k.layers.size(); ++i) {
			slughorn::Layer l = k.layers[i];

			if (!slughorn::stamp::isStampLayer(l)) {
				const slughorn::Key sk(layerKey(k.key, i));

				atlas->addShape(sk, k.shapes[i]);
				l.key = sk;
				l.gradientId = l.gradientId < gradMap.size() ? gradMap[l.gradientId] : 0;
			}

			b.comp.layers.push_back(l);
		}

		const slug_t heightEm = k.height / k.width;

		if (k.wrap) {
			slughorn::stamp::wrapDuplicates(b.stamps, 1.0f, heightEm, k.width);
		}

		b.depth = slughorn::stamp::splitDeep(b.stamps, b.comp, 1.0f, heightEm, k.width);

		// Sources aligned with the (possibly expanded) composite: stamp layers take a default.
		size_t src = 0;

		for (const slughorn::Layer &l : b.comp.layers) {
			if (slughorn::stamp::isStampLayer(l)) {
				b.sources.push_back({});
			} else {
				while (src < k.layers.size() && slughorn::stamp::isStampLayer(k.layers[src])) {
					++src;
				}

				b.sources.push_back(src < k.sources.size() ? k.sources[src] : slughorn::bake::LayerSource{});
				++src;
			}
		}

		slughorn::stamp::registerProtos(b.stamps, *atlas, k.key + "/p_");

		atlas->addCompositeShape(slughorn::Key(k.key), b.comp);

		b.firstStampLayer = stampBase;
		stampBase += b.stamps.layers.size();

		built.push_back(std::move(b));
	}

	try {
		atlas->build();
	} catch (const std::exception &e) {
		err = std::string("atlas build failed: ") + e.what();
		return false;
	}

	s.atlas = std::move(atlas);
	s.built = std::move(built);
	s.dirty = false;
	s.baked.clear();
	s.bakeOrder.clear();
	s.costs.clear();

	return true;
}

Baked *ensureBaked(const std::string &key, double alphaTest, std::string &err) {
	State &s = state();
	std::unordered_map<std::string, size_t>::iterator it = s.index.find(key);

	if (it == s.index.end()) {
		err = "unknown key '" + key + "'";
		return nullptr;
	}

	if (!ensureAtlas(err)) {
		return nullptr;
	}

	const KeyData &k = s.keys[it->second];
	const Built &b = s.built[it->second];
	const std::pair<std::string, int64_t> cacheKey = std::make_pair(key, int64_t(std::llround(std::max(0.0, alphaTest) * 1e6)));

	std::function<void()> touch = [&]() {
		s.bakeOrder.erase(std::remove(s.bakeOrder.begin(), s.bakeOrder.end(), cacheKey), s.bakeOrder.end());
		s.bakeOrder.push_back(cacheKey);
	};

	std::map<std::pair<std::string, int64_t>, Baked>::iterator hit = s.baked.find(cacheKey);

	if (hit != s.baked.end()) {
		touch();
		return &hit->second;
	}

	while (s.baked.size() >= State::BAKE_CACHE && !s.bakeOrder.empty()) {
		s.baked.erase(s.bakeOrder.front());
		s.bakeOrder.erase(s.bakeOrder.begin());
	}

	slughorn::bake::BakeConfig bc;
	bc.width = k.width;
	bc.height = k.height;
	bc.tolerancePx = static_cast<slug_t>(k.tolerancePx);
	bc.vUp = true;
	bc.alphaTest = static_cast<slug_t>(std::max(0.0, alphaTest));

	Baked out;

	try {
		out.mesh = slughorn::bake::bakeMesh(*s.atlas, b.comp, b.sources, bc, &b.stamps);
	} catch (const std::exception &e) {
		err = std::string("bake failed: ") + e.what();
		return nullptr;
	}

	touch();

	return &(s.baked[cacheKey] = std::move(out));
}

void putU16(std::vector<uint8_t> &out, size_t element, uint32_t v) {
	const size_t at = element * 2;

	if (out.size() < at + 2) {
		out.resize(at + 2, 0);
	}

	out[at] = uint8_t(v & 0xFF);
	out[at + 1] = uint8_t((v >> 8) & 0xFF);
}

} // namespace

// ------------------------------------------------------------------------------------------ API

std::string reset() {
	state() = State{};
	return "ok";
}

std::string load_svg(const std::string &key, const std::string &svg, double tolerance_px) {
	if (key.empty()) {
		return "FAIL: empty key";
	}

	if (!(tolerance_px > 0.0)) {
		tolerance_px = 0.25;
	}

	std::vector<std::string> warnings;

	slughorn::thorvg::LoadConfig cfg;
	cfg.log = [&](int, std::string_view m) { warnings.emplace_back(m); };

	slughorn::Atlas staging;
	slughorn::KeyIterator skeys("s", true);
	slughorn::stamp::Set stamps;
	slughorn::CompositeShape loaded;

	try {
		loaded = slughorn::stamp::loadString(svg, staging, skeys, &cfg, stamps, "s/", &warnings);
	} catch (const std::exception &e) {
		return std::string("FAIL: load: ") + e.what();
	}

	if (cfg.width <= 0.0f) {
		return "FAIL: ThorVG could not load the SVG" + (warnings.empty() ? std::string() : " (" + warnings.front() + ")");
	}

	std::vector<slughorn::bake::LayerSource> meta;
	meta.reserve(cfg.layers.size());

	for (const slughorn::thorvg::LayerInfo &li : cfg.layers) {
		meta.push_back({li.fillRule, li.stroke, static_cast<uint8_t>(li.spread)});
	}

	slughorn::Atlas keyAtlas;
	slughorn::KeyIterator lkeys("l");
	slughorn::bake::MergeResult merged;

	try {
		merged = slughorn::bake::mergeLayers(staging, loaded, meta, keyAtlas, lkeys);
	} catch (const std::exception &e) {
		return std::string("FAIL: merge: ") + e.what();
	}

	KeyData k;
	k.key = key;
	k.width = cfg.width;
	k.height = cfg.height;
	k.tolerancePx = tolerance_px;
	k.gradients = keyAtlas.getGradients();
	k.layersBefore = merged.layersBefore;
	k.curvesBefore = merged.curvesBefore;
	k.curvesAfter = merged.curvesAfter;

	for (size_t i = 0; i < merged.composite.layers.size(); ++i) {
		const slughorn::Layer &l = merged.composite.layers[i];

		if (slughorn::stamp::isStampLayer(l)) {
			k.shapes.emplace_back();
			k.layers.push_back(l);
			k.sources.push_back(i < merged.layers.size() ? merged.layers[i] : slughorn::bake::LayerSource{});
			continue;
		}

		const std::optional<slughorn::Atlas::Shape> shape = keyAtlas.getShape(l.key);

		if (!shape) {
			continue;
		}

		slughorn::Atlas::ShapeInfo info;
		info.curves = shape->curves;
		info.contourStarts = shape->contourStarts;
		info.autoMetrics = true;
		info.numBandsX = info.numBandsY = static_cast<int>(std::clamp<size_t>(info.curves.size() / 2, 1, slughorn::bake::MAX_AUTO_BANDS));

		k.shapes.push_back(std::move(info));
		k.layers.push_back(l);
		k.sources.push_back(i < merged.layers.size() ? merged.layers[i] : slughorn::bake::LayerSource{});
	}

	// Prototype curves stay in the set; their staging registration is dropped (re-registered at pack).
	k.stamps = std::move(stamps);

	size_t instances = 0;

	for (const slughorn::stamp::Layer &l : k.stamps.layers) {
		instances += l.instances.size();
	}

	// Depth as packed without wrap copies (the pack re-derives it).
	uint32_t depth = 0;

	{
		slughorn::stamp::Set probe = k.stamps;
		slughorn::CompositeShape comp;

		comp.layers = k.layers;
		depth = slughorn::stamp::splitDeep(probe, comp, 1.0f, k.height / k.width, k.width);
	}

	State &s = state();
	std::unordered_map<std::string, size_t>::iterator it = s.index.find(key);

	if (it != s.index.end()) {
		k.wrap = s.keys[it->second].wrap;
		s.keys[it->second] = std::move(k);
	} else {
		s.index[key] = s.keys.size();
		s.keys.push_back(std::move(k));
	}

	s.dirty = true;

	const KeyData &kd = *findKey(key);

	return "ok key=" + key + " width=" + std::to_string(int(kd.width)) + " height=" + std::to_string(int(kd.height)) +
			" layers=" + std::to_string(kd.layersBefore) + "->" + std::to_string(kd.layers.size()) +
			" curves=" + std::to_string(kd.curvesBefore) + "->" + std::to_string(kd.curvesAfter) +
			" stamp_layers=" + std::to_string(kd.stamps.layers.size()) + " instances=" + std::to_string(instances) +
			" depth=" + std::to_string(depth) + " warnings=" + std::to_string(warnings.size());
}

std::string set_wrap(const std::string &key, bool wrap) {
	State &s = state();
	std::unordered_map<std::string, size_t>::iterator it = s.index.find(key);

	if (it == s.index.end()) {
		return "FAIL: unknown key '" + key + "'";
	}

	if (s.keys[it->second].wrap != wrap) {
		s.keys[it->second].wrap = wrap;
		s.dirty = true;
	}

	return "ok";
}

std::vector<std::string> keys() {
	std::vector<std::string> out;

	for (const KeyData &k : state().keys) {
		out.push_back(k.key);
	}

	return out;
}

bool atlas(Atlas &out, std::string &err) {
	if (!ensureAtlas(err)) {
		return false;
	}

	const State &s = state();
	const slughorn::Atlas &a = *s.atlas;

	const slughorn::Atlas::TextureData &ct = a.getCurveTextureData();
	const slughorn::Atlas::TextureData &bt = a.getBandTextureData();

	out = Atlas{};
	out.tex_width = int(a.getTextureWidth());
	out.curve_format = ct.format == slughorn::Atlas::TextureData::Format::RGBA16F ? "RGBA16F" : "RGBA32F";
	out.curve_height = int(ct.height);
	out.curves = ct.bytes;
	out.band_height = int(bt.height);
	out.bands = bt.bytes;

	std::function<void(const slughorn::Atlas::Shape &, const slughorn::Layer &, float, float)> pushShapeRecord =
			[&](const slughorn::Atlas::Shape &sh, const slughorn::Layer &l, float gradient, float blend) {
		const float rec[16] = {
			float(sh.bandTexX), float(sh.bandTexY), float(sh.bandMaxX), float(sh.bandMaxY),
			sh.bandScaleX, sh.bandScaleY, sh.bandOffsetX, sh.bandOffsetY,
			sh.bearingX, sh.bearingY, sh.width, sh.height,
			l.transform.x - sh.originX, l.transform.y - sh.originY,
			gradient, blend,
		};

		out.layers.insert(out.layers.end(), rec, rec + 16);
		pushLinear(out.layers, l.color);
		out.layers.insert(out.layers.end(), 4, 0.0f);
	};

	int32_t first = 0;

	for (size_t ki = 0; ki < s.keys.size(); ++ki) {
		const KeyData &k = s.keys[ki];
		const Built &b = s.built[ki];

		out.keys.push_back(k.key);

		const slughorn::CompositeShape *comp = a.getCompositeShape(slughorn::Key(k.key));
		int32_t count = 0;

		if (comp) {
			for (const slughorn::Layer &l : comp->layers) {
				if (l.drawMode != slughorn::DrawMode::Visible) {
					continue;
				}

				if (slughorn::stamp::isStampLayer(l)) {
					std::vector<float> rec(LAYER_STRIDE, 0.0f);

					rec[14] = float(b.firstStampLayer + slughorn::stamp::stampIndex(l));
					rec[15] = float(STAMP_BLEND);
					rec[16] = rec[17] = rec[18] = rec[19] = 1.0f;
					out.layers.insert(out.layers.end(), rec.begin(), rec.end());
					++count;
					continue;
				}

				const std::optional<slughorn::Atlas::Shape> sh = a.getShape(l.key);

				if (!sh) {
					continue;
				}

				pushShapeRecord(*sh, l, float(l.gradientId), float(static_cast<uint8_t>(l.blendMode)));
				++count;
			}
		}

		out.key_layers.push_back(first);
		out.key_layers.push_back(count);
		first += count;

		out.key_frames.push_back(k.width);
		out.key_frames.push_back(k.height);
		out.key_frames.push_back(1.0f / k.width);
		out.key_frames.push_back(1.0f);
	}

	// Curve prototypes: band layers after every key's layers; stamp_protos.
	std::vector<uint32_t> protoBase(s.keys.size(), 0);
	uint32_t nproto = 0;

	for (size_t ki = 0; ki < s.keys.size(); ++ki) {
		const Built &b = s.built[ki];

		protoBase[ki] = nproto;

		for (const slughorn::stamp::Proto &p : b.stamps.protos) {
			float layer = -1.0f;

			if (p.kind == slughorn::stamp::Kind::Curve) {
				const std::optional<slughorn::Atlas::Shape> sh = a.getShape(p.key);

				if (sh) {
					slughorn::Layer l;

					l.color = {1.0f, 1.0f, 1.0f, 1.0f};
					layer = float(out.layers.size() / LAYER_STRIDE);
					pushShapeRecord(*sh, l, 0.0f, 0.0f);
				}
			}

			out.stamp_protos.push_back(p.kind == slughorn::stamp::Kind::Curve ? 0.0f : p.kind == slughorn::stamp::Kind::Ellipse ? 1.0f : 2.0f);
			out.stamp_protos.push_back(layer);
			++nproto;
		}
	}

	// Stamp layers: instances, grids, cells, means.
	uint32_t instanceBase = 0;

	for (size_t ki = 0; ki < s.keys.size(); ++ki) {
		const KeyData &k = s.keys[ki];
		const Built &b = s.built[ki];
		const float heightEm = k.height / k.width;

		for (const slughorn::stamp::Layer &layer : b.stamps.layers) {
			const slughorn::stamp::Grid g = slughorn::stamp::buildGrid(a, b.stamps, layer, 1.0f, heightEm, k.width, 32, true, true);

			// Header block at texel B, lists after it, u16 elements counted from 2B.
			const size_t B = out.stamp_cells.size() / 4;
			size_t element = 2 * B + size_t(2) * g.G * g.G; // first list element (absolute)

			out.stamp_cells.resize((B + size_t(g.G) * g.G) * 4, 0);

			for (uint32_t c = 0; c < g.G * g.G; ++c) {
				const std::vector<uint32_t> &list = g.cells[c];

				putU16(out.stamp_cells, 2 * (B + c), uint32_t(element - 2 * B));
				putU16(out.stamp_cells, 2 * (B + c) + 1, uint32_t(list.size()));

				for (uint32_t n : list) {
					putU16(out.stamp_cells, element++, n);
				}
			}

			// End the layer on a texel boundary.
			out.stamp_cells.resize(((out.stamp_cells.size() + 3) / 4) * 4, 0);

			out.stamp_layers.push_back(int32_t(g.G));
			out.stamp_layers.push_back(int32_t(B));
			out.stamp_layers.push_back(int32_t(instanceBase));
			out.stamp_layers.push_back(int32_t(layer.instances.size()));
			out.stamp_layers.push_back(int32_t(g.maxPerCell));

			out.stamp_means.insert(out.stamp_means.end(), g.means.begin(), g.means.end());
			out.stamp_cell_max.insert(out.stamp_cell_max.end(), g.cellMax.begin(), g.cellMax.end());

			for (const slughorn::stamp::Instance &in : layer.instances) {
				const slughorn::stamp::Inverse inv = slughorn::stamp::invert(in.m);

				out.stamp_instances.push_back(inv.a);
				out.stamp_instances.push_back(inv.c);
				out.stamp_instances.push_back(inv.b);
				out.stamp_instances.push_back(inv.d);
				out.stamp_instances.push_back(inv.e);
				out.stamp_instances.push_back(inv.f);
				out.stamp_instances.push_back(float(protoBase[ki] + in.proto));

				const uint32_t paint = (in.gradient && in.gradient <= b.stamps.atlasGradientIds.size()) ? b.stamps.atlasGradientIds[in.gradient - 1] : 0;

				out.stamp_instances.push_back(float(paint));
				pushLinear(out.stamp_instances, in.color);
			}

			instanceBase += uint32_t(layer.instances.size());
		}
	}

	const std::vector<slughorn::GradientInfo> &grads = a.getGradients();

	out.gradients.push_back(float(grads.size()));

	for (const slughorn::GradientInfo &g : grads) {
		float type = 0.0f;

		switch (g.type) {
			case slughorn::GradientInfo::Type::Linear: type = 0.0f; break;
			case slughorn::GradientInfo::Type::Radial: type = 1.0f; break;
			case slughorn::GradientInfo::Type::Sweep: type = 2.0f; break;
			case slughorn::GradientInfo::Type::AffineRadial: type = 3.0f; break;
		}

		const float hdr[11] = {
			type, g.transform.xx, g.transform.yx, g.transform.xy, g.transform.yy, g.transform.dx, g.transform.dy,
			g.innerRadius, g.startAngle, g.endAngle, float(g.stops.size()),
		};

		out.gradients.insert(out.gradients.end(), hdr, hdr + 11);

		for (const slughorn::GradientStop &st : g.stops) {
			out.gradients.push_back(st.t);
			pushLinear(out.gradients, st.color);
		}
	}

	return true;
}

bool mesh(const std::string &key, double alpha_test, Mesh &out, std::string &err) {
	Baked *b = ensureBaked(key, alpha_test, err);

	if (!b) {
		return false;
	}

	const slughorn::bake::BakedMesh &m = b->mesh;

	out = Mesh{};

	const size_t n = m.paintIds.size();

	out.vertices.reserve(n * 3);

	for (size_t i = 0; i < n; ++i) {
		out.vertices.push_back(m.positions[i * 2]);
		out.vertices.push_back(m.positions[i * 2 + 1]);
		out.vertices.push_back(0.0f);
		out.paint.push_back(int32_t(m.paintIds[i]));
	}

	out.param = m.params;
	out.triangles.assign(m.indices.begin(), m.indices.end());
	out.overlay_first = int32_t(m.opaqueIndexCount);
	out.overlay_count = int32_t(m.overlayIndexCount);

	out.paints.push_back(float(m.paints.size()));

	for (const slughorn::bake::Paint &p : m.paints) {
		using PT = slughorn::bake::Paint::Type;

		out.paints.push_back(p.type == PT::Solid ? 0.0f : p.type == PT::Linear ? 1.0f : 2.0f);

		if (p.type == PT::Solid) {
			out.paints.push_back(1.0f);
			out.paints.push_back(0.0f);
			pushLinear(out.paints, p.color);
			continue;
		}

		out.paints.push_back(float(p.stops.size()));

		// Radial: the wire has no inner radius, and t = length(param) - inner; shifting every
		// stop by +inner is exact (pad clamps at the first / last stop either way).
		const float shift = p.type == PT::Radial ? p.innerRadius : 0.0f;

		for (const slughorn::GradientStop &st : p.stops) {
			out.paints.push_back(st.t + shift);
			pushLinear(out.paints, st.color);
		}
	}

	return true;
}

bool cost(const std::string &key, Cost &out, std::string &err) {
	State &s = state();

	if (!ensureAtlas(err)) {
		return false;
	}

	if (!s.index.count(key)) {
		err = "unknown key '" + key + "'";
		return false;
	}

	const size_t ki = s.index.at(key);
	const KeyData &k = s.keys[ki];
	const Built &bt = s.built[ki];

	if (!s.costs.count(key)) {
		Baked *b = ensureBaked(key, 0.0, err);

		if (!b) {
			return false;
		}

		s.costs[key] = slughorn::bake::cost(*s.atlas, bt.comp, b->mesh, k.layersBefore, 1.0f, k.height / k.width, &bt.stamps, k.width);
	}

	const slughorn::bake::Cost &c = s.costs.at(key);

	out = Cost{};
	out.mode = c.mode;
	out.curves = int64_t(c.curves);
	out.curves_before = int64_t(k.curvesBefore);
	out.curves_after = int64_t(k.curvesAfter);
	out.max_band_curves_h = c.maxBandCurvesH;
	out.max_band_curves_v = c.maxBandCurvesV;
	out.slug_work = int64_t(c.slugWork);
	out.slug_work_mean = c.slugWorkMean;
	out.layers_before = int64_t(c.layersBefore);
	out.layers_after = int64_t(c.layersAfter);
	out.stroke_layers = int64_t(c.strokeLayers);
	out.gradient_layers = int64_t(c.gradientLayers);
	out.triangles_before = int64_t(c.trianglesBefore);
	out.triangles_after = int64_t(c.trianglesAfter);
	out.stamp_layers = int64_t(c.stampLayers);
	out.stamp_instances = int64_t(c.stampInstances);
	out.stamp_max_per_cell = int64_t(c.stampMaxPerCell);
	out.stamp_grid = int64_t(c.stampGrid);
	out.stamp_depth = int64_t(bt.depth);
	out.stamp_work = c.stampWork;
	out.tolerance_px = k.tolerancePx;
	out.width = k.width;
	out.height = k.height;

	return true;
}

bool render(const std::string &key, int width, int height, std::vector<float> &out, std::string &err) {
	if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
		err = "render: size out of range";
		return false;
	}

	State &s = state();
	std::unordered_map<std::string, size_t>::iterator it = s.index.find(key);

	if (it == s.index.end()) {
		err = "unknown key '" + key + "'";
		return false;
	}

	if (!ensureAtlas(err)) {
		return false;
	}

	const KeyData &k = s.keys[it->second];
	const Built &b = s.built[it->second];
	const slughorn::render::Image img = slughorn::stamp::renderComposite(*s.atlas, b.comp, b.stamps, uint32_t(width), uint32_t(height),
			0.0f, 0.0f, 1.0f, k.height / k.width, true);

	out.assign(img.data.begin(), img.data.end());

	return true;
}

// ------------------------------------------------------------------------------------- decal
//
// The port's reference (tools/slug_fixture/fixture_guest.gd, _decal) in C++: every input face's
// UVs go through uv_xform (uv * repeat + offset); with wrap the face's UV footprint is tiled by
// whole-unit shifts of the bake. Each baked triangle (shifted) whose box meets the footprint is
// clipped to the face's UV triangle (Sutherland-Hodgman), mapped back onto the face by the face's
// barycentrics, lifted along the (interpolated, or face) normal by lift[base | overlay], and fanned
// into counter-clockwise-outward triangles. Its param interpolates the baked vertices' params by
// the baked triangle's barycentrics; its paint is the baked triangle's first vertex's. Base
// triangles first, overlay after (overlay_from). Past `cap` triangles: capped, nothing else. With
// alpha_test > 0 the key's cutout bake is clipped instead (all base, no overlay): how cards that
// sample one cell of an atlas get exactly that cell's alpha-tested shapes.

namespace {

struct V2 {
	double x = 0, y = 0;
};

V2 operator+(V2 a, V2 b) { return {a.x + b.x, a.y + b.y}; }
V2 operator-(V2 a, V2 b) { return {a.x - b.x, a.y - b.y}; }
V2 operator*(V2 a, double s) { return {a.x * s, a.y * s}; }
double cross(V2 a, V2 b) { return a.x * b.y - a.y * b.x; }

struct V3 {
	double x = 0, y = 0, z = 0;
};

V3 operator+(V3 a, V3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
V3 operator-(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
V3 operator*(V3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
V3 cross3(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
double dot3(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
V3 normalized(V3 a) {
	const double l = std::sqrt(dot3(a, a));
	return l > 0 ? a * (1.0 / l) : a;
}

bool bary(V2 p, V2 a, V2 b, V2 c, V3 &w) {
	const V2 v0 = b - a, v1 = c - a;
	const double d = v0.x * v1.y - v1.x * v0.y;
	if (std::abs(d) < 1e-14) {
		return false;
	}
	const V2 v2 = p - a;
	const double l1 = (v2.x * v1.y - v1.x * v2.y) / d;
	const double l2 = (v0.x * v2.y - v2.x * v0.y) / d;
	w = {1.0 - l1 - l2, l1, l2};
	return true;
}

std::vector<V2> clipToTriangle(std::vector<V2> poly, const V2 tri[3], bool ccw) {
	const double sgn = ccw ? 1.0 : -1.0;

	for (int e = 0; e < 3; ++e) {
		const V2 a = tri[e], b = tri[(e + 1) % 3];
		std::vector<V2> in;
		in.swap(poly);

		for (size_t i = 0; i < in.size(); ++i) {
			const V2 p = in[i], q = in[(i + 1) % in.size()];
			const double sp = cross(b - a, p - a) * sgn;
			const double sq = cross(b - a, q - a) * sgn;

			if (sp >= 0.0) {
				poly.push_back(p);
			}
			if ((sp >= 0.0) != (sq >= 0.0)) {
				poly.push_back(p + (q - p) * (sp / (sp - sq)));
			}
		}

		if (poly.empty()) {
			return poly;
		}
	}

	std::vector<V2> clean;

	for (const V2 &p : poly) {
		if (clean.empty()) {
			clean.push_back(p);
			continue;
		}
		const V2 d = p - clean.back();
		if (d.x * d.x + d.y * d.y > 1e-16) {
			clean.push_back(p);
		}
	}

	if (clean.size() > 1) {
		const V2 d = clean.front() - clean.back();
		if (d.x * d.x + d.y * d.y <= 1e-16) {
			clean.pop_back();
		}
	}

	return clean;
}

// Uniform grid over the bake's UV boxes ([0,1]^2 plus slack) for the per-face queries.
struct Grid {
	static constexpr int N = 64;
	std::vector<std::vector<uint32_t>> cells = std::vector<std::vector<uint32_t>>(N * N);

	static int cell(double v) { return std::clamp(int(std::floor(v * N)), 0, N - 1); }
};

// The surface a bake is clipped onto.
struct Surface {
	const std::vector<float> &v;
	const std::vector<float> &nv;
	const std::vector<float> &uvs;
	const std::vector<int32_t> &f;
	const std::vector<float> &xform;
};

// Clips @p m onto @p s (the procedure described above) into @p out (vertices, normals, paint,
// param, overlay_from). 1: done; 0: past cap (out cleared); -1: bad input (err).
int clipToSurface(const slughorn::bake::BakedMesh &m, const Surface &s, double liftBase, double liftOverlay, int64_t cap,
		Decal &out, std::string &err) {
	const std::vector<float> &v = s.v;
	const std::vector<float> &nv = s.nv;
	const std::vector<float> &uvs = s.uvs;
	const std::vector<int32_t> &f = s.f;
	const std::vector<float> &xform = s.xform;

	if (xform.size() < 5) {
		err = "decal: uv_xform wants 5 floats";
		return -1;
	}

	const size_t nverts = v.size() / 3;

	if (v.size() % 3 || f.size() % 3 || uvs.size() < nverts * 2) {
		err = "decal: vertices 3N, uvs 2N, triangles 3F";
		return -1;
	}

	out.vertices.clear();
	out.normals.clear();
	out.paint.clear();
	out.param.clear();

	const size_t nb = m.indices.size() / 3;
	const size_t ovFirst = m.overlayIndexCount > 0 ? m.opaqueIndexCount : m.indices.size();

	std::function<V2(uint32_t)> bp = [&](uint32_t i) { return V2{m.positions[i * 2], m.positions[i * 2 + 1]}; };
	std::function<V2(uint32_t)> bpar = [&](uint32_t i) { return V2{m.params[i * 2], m.params[i * 2 + 1]}; };

	struct Box {
		double x0, y0, x1, y1;
	};

	std::vector<Box> boxes(nb);
	Grid grid;

	for (size_t t = 0; t < nb; ++t) {
		const V2 a = bp(m.indices[t * 3]), c1 = bp(m.indices[t * 3 + 1]), c2 = bp(m.indices[t * 3 + 2]);
		Box bx{std::min({a.x, c1.x, c2.x}), std::min({a.y, c1.y, c2.y}), std::max({a.x, c1.x, c2.x}), std::max({a.y, c1.y, c2.y})};
		boxes[t] = bx;

		for (int gy = Grid::cell(bx.y0); gy <= Grid::cell(bx.y1); ++gy) {
			for (int gx = Grid::cell(bx.x0); gx <= Grid::cell(bx.x1); ++gx) {
				grid.cells[size_t(gy) * Grid::N + size_t(gx)].push_back(uint32_t(t));
			}
		}
	}

	const bool haveNormals = nv.size() == v.size();
	const V2 rep{xform[0], xform[1]}, off{xform[2], xform[3]};
	const bool wrap = xform[4] > 0.5f;

	std::vector<float> ov3, on3, op2;
	std::vector<int32_t> opaint;
	int64_t tris = 0;

	std::function<V3(int32_t)> P = [&](int32_t i) { return V3{v[size_t(i) * 3], v[size_t(i) * 3 + 1], v[size_t(i) * 3 + 2]}; };
	std::function<V3(int32_t)> N3 = [&](int32_t i) { return V3{nv[size_t(i) * 3], nv[size_t(i) * 3 + 1], nv[size_t(i) * 3 + 2]}; };
	std::function<V2(int32_t)> UV = [&](int32_t i) { return V2{uvs[size_t(i) * 2] * rep.x + off.x, uvs[size_t(i) * 2 + 1] * rep.y + off.y}; };

	std::vector<uint32_t> stamp(nb, 0);
	std::vector<uint32_t> candidates;
	uint32_t stampId = 0;

	for (size_t sf = 0; sf + 2 < f.size(); sf += 3) {
		const int32_t ia = f[sf], ib = f[sf + 1], ic = f[sf + 2];

		if (ia < 0 || ib < 0 || ic < 0 || size_t(ia) >= nverts || size_t(ib) >= nverts || size_t(ic) >= nverts) {
			err = "decal: triangle index out of range";
			return -1;
		}

		const V2 ta = UV(ia), tb = UV(ib), tc = UV(ic);
		const double area = cross(tb - ta, tc - ta);

		if (std::abs(area) < 1e-14) {
			continue;
		}

		const V3 pa = P(ia), pb = P(ib), pc = P(ic);
		const V3 fn = normalized(cross3(pb - pa, pc - pa));
		const V2 face[3] = {ta, tb, tc};

		const double fx0 = std::min({ta.x, tb.x, tc.x}), fy0 = std::min({ta.y, tb.y, tc.y});
		const double fx1 = std::max({ta.x, tb.x, tc.x}), fy1 = std::max({ta.y, tb.y, tc.y});

		const int i0 = wrap ? int(std::floor(fx0)) : 0, i1 = wrap ? int(std::floor(fx1)) : 0;
		const int j0 = wrap ? int(std::floor(fy0)) : 0, j1 = wrap ? int(std::floor(fy1)) : 0;

		for (int i = i0; i <= i1; ++i) {
			for (int j = j0; j <= j1; ++j) {
				const V2 sh{double(i), double(j)};

				// Footprint in the bake's own [0,1] frame for this shift.
				const double qx0 = fx0 - sh.x, qy0 = fy0 - sh.y, qx1 = fx1 - sh.x, qy1 = fy1 - sh.y;

				if (qx1 < -1e-9 || qy1 < -1e-9 || qx0 > 1 + 1e-9 || qy0 > 1 + 1e-9) {
					continue;
				}

				++stampId;
				candidates.clear();

				for (int gy = Grid::cell(qy0); gy <= Grid::cell(qy1); ++gy) {
					for (int gx = Grid::cell(qx0); gx <= Grid::cell(qx1); ++gx) {
						for (uint32_t t : grid.cells[size_t(gy) * Grid::N + size_t(gx)]) {
							if (stamp[t] != stampId) {
								stamp[t] = stampId;
								candidates.push_back(t);
							}
						}
					}
				}

				// Baked order, as the reference walks them: the overlay is painter's-ordered.
				std::sort(candidates.begin(), candidates.end());

				for (uint32_t t : candidates) {
					const Box &bx = boxes[t];

					// Rect2.intersects(include_borders = true)
					if (bx.x0 > qx1 || bx.x1 < qx0 || bx.y0 > qy1 || bx.y1 < qy0) {
						continue;
					}

					const uint32_t b0 = m.indices[t * 3], b1 = m.indices[t * 3 + 1], b2 = m.indices[t * 3 + 2];
					const V2 q[3] = {bp(b0) + sh, bp(b1) + sh, bp(b2) + sh};

					const std::vector<V2> poly = clipToTriangle({q[0], q[1], q[2]}, face, area > 0.0);

					if (poly.size() < 3) {
						continue;
					}

					const bool ovl = t * 3 >= ovFirst;
					const double lf = ovl ? liftOverlay : liftBase;

					std::vector<V3> pts, nrs;
					std::vector<V2> prs;

					for (const V2 &p : poly) {
						V3 w;
						if (!bary(p, ta, tb, tc, w)) {
							w = {1, 0, 0};
						}

						const V3 n = haveNormals ? normalized(N3(ia) * w.x + N3(ib) * w.y + N3(ic) * w.z) : fn;

						pts.push_back(pa * w.x + pb * w.y + pc * w.z + n * lf);
						nrs.push_back(n);

						V3 wb;
						prs.push_back(bary(p, q[0], q[1], q[2], wb) ? bpar(b0) * wb.x + bpar(b1) * wb.y + bpar(b2) * wb.z : bpar(b0));
					}

					std::vector<float> &dv = ovl ? ov3 : out.vertices;
					std::vector<float> &dn = ovl ? on3 : out.normals;
					std::vector<float> &dp = ovl ? op2 : out.param;
					std::vector<int32_t> &dpaint = ovl ? opaint : out.paint;

					for (size_t k = 1; k + 1 < poly.size(); ++k) {
						size_t vv[3] = {0, k, k + 1};

						if (dot3(cross3(pts[k] - pts[0], pts[k + 1] - pts[0]), fn) < 0.0) {
							vv[1] = k + 1;
							vv[2] = k;
						}

						for (size_t mi : vv) {
							dv.insert(dv.end(), {float(pts[mi].x), float(pts[mi].y), float(pts[mi].z)});
							dn.insert(dn.end(), {float(nrs[mi].x), float(nrs[mi].y), float(nrs[mi].z)});
							dp.insert(dp.end(), {float(prs[mi].x), float(prs[mi].y)});
						}

						dpaint.push_back(int32_t(m.paintIds[b0]));

						if (++tris > cap) {
							out.vertices.clear();
							out.normals.clear();
							out.paint.clear();
							out.param.clear();
							return 0;
						}
					}
				}
			}
		}
	}

	out.overlay_from = int32_t(out.paint.size());
	out.vertices.insert(out.vertices.end(), ov3.begin(), ov3.end());
	out.normals.insert(out.normals.end(), on3.begin(), on3.end());
	out.param.insert(out.param.end(), op2.begin(), op2.end());
	out.paint.insert(out.paint.end(), opaint.begin(), opaint.end());

	return 1;
}

} // namespace

bool decal(const std::string &key, const std::vector<float> &v, const std::vector<float> &nv,
		const std::vector<float> &uvs, const std::vector<int32_t> &f, const std::vector<float> &xform,
		const std::vector<float> &lift, int64_t cap, double alpha_test, Decal &out, std::string &err) {
	out = Decal{};

	Baked *b = ensureBaked(key, alpha_test, err);

	if (!b) {
		return false;
	}

	if (lift.size() < 2) {
		err = "decal: lift wants 2 floats";
		return false;
	}

	const int r = clipToSurface(b->mesh, Surface{v, nv, uvs, f, xform}, lift[0], lift[1], cap, out, err);

	if (r < 0) {
		return false;
	}

	out.capped = r == 0;

	return true;
}

// ---------------------------------------------------------------------------------- slug-baked
//
// The complete baseline: every key, every surface, within its budget, never handed to the
// slug-runtime shader. bake::bakeFinal() folds every alpha source into the layer stack and judges
// only the final composite (Opaque / Transparent / AlphaTest, see bake.hpp), and LOD levels
// (bake::lodLevel) trade detail for triangles: each level doubles the flattening / outline
// tolerance and the feature size folded into the faces' local means. A level over the cap is
// first offered to meshoptimizer (simplified toward the cap, colour boundaries kept as seams,
// error at most the next level's tolerance); past every level comes the mean colour. Nothing
// falls back.

namespace {

void paintsWire(const std::vector<slughorn::bake::Paint> &paints, std::vector<float> &out) {
	using PT = slughorn::bake::Paint::Type;

	out.push_back(float(paints.size()));

	for (const slughorn::bake::Paint &p : paints) {
		out.push_back(p.type == PT::Solid ? 0.0f : p.type == PT::Linear ? 1.0f : 2.0f);

		if (p.type == PT::Solid) {
			out.push_back(1.0f);
			out.push_back(0.0f);
			pushLinear(out, p.color);
			continue;
		}

		out.push_back(float(p.stops.size()));

		// Radial: the wire has no inner radius, and t = length(param) - inner; shifting every
		// stop by +inner is exact (pad clamps at the first / last stop either way).
		const float shift = p.type == PT::Radial ? p.innerRadius : 0.0f;

		for (const slughorn::GradientStop &st : p.stops) {
			out.push_back(st.t + shift);
			pushLinear(out, st.color);
		}
	}
}

void toMesh(const slughorn::bake::BakedMesh &m, Mesh &out) {
	out = Mesh{};

	const size_t n = m.paintIds.size();

	out.vertices.reserve(n * 3);

	for (size_t i = 0; i < n; ++i) {
		out.vertices.push_back(m.positions[i * 2]);
		out.vertices.push_back(m.positions[i * 2 + 1]);
		out.vertices.push_back(0.0f);
		out.paint.push_back(int32_t(m.paintIds[i]));
	}

	out.param = m.params;
	out.triangles.assign(m.indices.begin(), m.indices.end());
	out.overlay_first = int32_t(m.opaqueIndexCount);
	out.overlay_count = int32_t(m.overlayIndexCount);
	paintsWire(m.paints, out.paints);
}

// A key spec resolved against the built atlas.
struct FinalSource {
	const KeyData *kc = nullptr; // colour key (nullptr: none, white)
	const Built *bc = nullptr;
	const KeyData *ka = nullptr; // alpha-map key (nullptr: none)
	const Built *ba = nullptr;
	float width = 1, height = 1; // the canvas the bake lives on (the colour key's, else the alpha key's)
	double tolerancePx = 0.25;
};

bool resolveSpec(const std::string &spec, FinalSource &src, std::string &err) {
	State &s = state();

	if (!ensureAtlas(err)) {
		return false;
	}

	const size_t bar = spec.find('|');
	const std::string ck = spec.substr(0, bar);
	const std::string ak = bar == std::string::npos ? std::string() : spec.substr(bar + 1);

	std::function<bool(const std::string &, const KeyData *&, const Built *&)> get = [&](const std::string &k, const KeyData *&kd, const Built *&b) {
		std::unordered_map<std::string, size_t>::iterator it = s.index.find(k);

		if (it == s.index.end()) {
			err = "unknown key '" + k + "'";
			return false;
		}

		kd = &s.keys[it->second];
		b = &s.built[it->second];

		return true;
	};

	if (!ck.empty() && !get(ck, src.kc, src.bc)) {
		return false;
	}

	if (!ak.empty() && !get(ak, src.ka, src.ba)) {
		return false;
	}

	if (!src.kc && !src.ka) {
		err = "empty key spec";
		return false;
	}

	const KeyData *frame = src.kc ? src.kc : src.ka;

	src.width = frame->width;
	src.height = frame->height;
	src.tolerancePx = frame->tolerancePx;

	return true;
}

std::map<std::string, slughorn::bake::BakedMesh> &finalCache() {
	static std::map<std::string, slughorn::bake::BakedMesh> c;
	return c;
}

std::vector<std::string> &finalOrder() {
	static std::vector<std::string> o;
	return o;
}

// One LOD level of the spec's final bake over a canvas window (px), cached (a few at a time: the
// sandbox counts live allocations).
const slughorn::bake::BakedMesh *finalLevel(const std::string &spec, const FinalSource &src, const BakeParams &p, int level,
		const double window[4], size_t maxTriangles, std::string &err) {
	char key[256];

	std::snprintf(key, sizeof key, "%s#%d|%.4f|%.4f|%.4f|%d|%.2f,%.2f,%.2f,%.2f|%zu", spec.c_str(), p.mode, p.alpha_test, p.opacity,
			p.feature_floor_px, level, window[0], window[1], window[2], window[3], maxTriangles);

	std::map<std::string, slughorn::bake::BakedMesh> &cache = finalCache();
	std::vector<std::string> &order = finalOrder();

	order.erase(std::remove(order.begin(), order.end(), std::string(key)), order.end());
	order.push_back(key);

	if (std::map<std::string, slughorn::bake::BakedMesh>::iterator it = cache.find(key); it != cache.end()) {
		return &it->second;
	}

	while (cache.size() >= State::BAKE_CACHE && order.size() > 1) {
		cache.erase(order.front());
		order.erase(order.begin());
	}

	State &s = state();
	slughorn::bake::BakeConfig bc;

	bc.width = src.width;
	bc.height = src.height;
	bc.vUp = true;
	bc.alphaMode = slughorn::bake::AlphaMode(std::clamp(p.mode, 0, 2));
	bc.alphaTest = slug_t(p.alpha_test);
	bc.opacity = slug_t(p.opacity);
	bc.windowX0 = slug_t(window[0]);
	bc.windowY0 = slug_t(window[1]);
	bc.windowX1 = slug_t(window[2]);
	bc.windowY1 = slug_t(window[3]);
	bc.maxTriangles = maxTriangles;
	slughorn::bake::applyLod(bc, slughorn::bake::lodLevel(level, slug_t(src.tolerancePx), slug_t(p.feature_floor_px)));

	slughorn::bake::AlphaSource as;

	if (src.ka) {
		as.atlas = s.atlas.get();
		as.composite = &src.ba->comp;
		as.meta = &src.ba->sources;
		as.stamps = &src.ba->stamps;
		as.width = src.ka->width;
		as.height = src.ka->height;
	}

	static const std::vector<slughorn::bake::LayerSource> noMeta;

	try {
		cache[key] = slughorn::bake::bakeFinal(*s.atlas, src.bc ? &src.bc->comp : nullptr, src.bc ? src.bc->sources : noMeta, bc,
				src.bc ? &src.bc->stamps : nullptr, src.ka ? &as : nullptr);
	} catch (const std::exception &e) {
		err = std::string("bake failed: ") + e.what();
		cache.erase(key);
		return nullptr;
	}

	return &cache[key];
}

// The area-weighted mean of a final bake over its window, as one solid paint: Opaque shows the
// straight colour; Transparent the premultiplied mean; AlphaTest the covered parts' colour, kept
// only when the covered fraction reaches the test. @p keep: whether anything is drawn.
slughorn::bake::Paint meanPaint(const slughorn::bake::BakedMesh &m, const FinalSource &src, const BakeParams &p, bool &keep) {
	double r = 0, g = 0, b = 0, a = 0, covered = 0;

	std::function<slughorn::Color(const slughorn::bake::Paint &, float, float)> colourAt = [&](const slughorn::bake::Paint &pt, float p0, float p1) {
		using PT = slughorn::bake::Paint::Type;

		if (pt.type == PT::Solid) {
			return pt.color;
		}

		slughorn::GradientInfo gi;

		gi.stops = pt.stops;

		const slug_t t = pt.type == PT::Linear ? slug_t(p0) : slug_t(std::sqrt(p0 * p0 + p1 * p1)) - pt.innerRadius;

		return slughorn::render::gradientColor(gi, t);
	};

	for (size_t t = 0; t + 2 < m.indices.size(); t += 3) {
		const uint32_t i0 = m.indices[t], i1 = m.indices[t + 1], i2 = m.indices[t + 2];
		const double ax = m.positions[i0 * 2], ay = m.positions[i0 * 2 + 1];
		const double bx = m.positions[i1 * 2], by = m.positions[i1 * 2 + 1];
		const double cx = m.positions[i2 * 2], cy = m.positions[i2 * 2 + 1];
		const double area = std::abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5 * double(src.width) * double(src.height);
		const float p0 = (m.params[i0 * 2] + m.params[i1 * 2] + m.params[i2 * 2]) / 3.0f;
		const float p1 = (m.params[i0 * 2 + 1] + m.params[i1 * 2 + 1] + m.params[i2 * 2 + 1]) / 3.0f;
		const slughorn::Color c = colourAt(m.paints[m.paintIds[i0]], p0, p1);

		r += area * c.r * c.a;
		g += area * c.g * c.a;
		b += area * c.b * c.a;
		a += area * c.a;
		covered += area;
	}

	const double total = m.canvasArea > 0 ? m.canvasArea : covered;
	slughorn::bake::Paint out;

	out.opaque = true;
	keep = total > 0 && covered > 0;

	if (!keep) {
		return out;
	}

	switch (slughorn::bake::AlphaMode(std::clamp(p.mode, 0, 2))) {
		case slughorn::bake::AlphaMode::Opaque:
		case slughorn::bake::AlphaMode::AlphaTest:
			// Straight colour of what is drawn; AlphaTest keeps it when enough of the window is.
			out.color = {slug_t(a > 0 ? r / a : 0), slug_t(a > 0 ? g / a : 0), slug_t(a > 0 ? b / a : 0), 1};
			keep = p.mode == int(slughorn::bake::AlphaMode::Opaque) || covered / total >= p.alpha_test;
			break;

		case slughorn::bake::AlphaMode::Transparent: {
			const double ma = a / total;

			out.color = {slug_t(a > 0 ? r / a : 0), slug_t(a > 0 ? g / a : 0), slug_t(a > 0 ? b / a : 0), slug_t(ma)};
			out.opaque = ma >= slughorn::bake::FINAL_OPAQUE_ALPHA;
			keep = ma > 0;
			break;
		}
	}

	return out;
}

// The mean as a mesh over the window (2 triangles, UV, v up).
slughorn::bake::BakedMesh meanMesh(const slughorn::bake::Paint &paint, const FinalSource &src, const double window[4]) {
	slughorn::bake::BakedMesh m;
	const double W = src.width, H = src.height;
	const double u0 = window[0] / W, u1 = window[2] / W, v0 = 1.0 - window[3] / H, v1 = 1.0 - window[1] / H;

	m.positions = {float(u0), float(v0), float(u1), float(v0), float(u1), float(v1), float(u0), float(v1)};
	m.paintIds = {0, 0, 0, 0};
	m.params.assign(8, 0.0f);
	m.indices = {0, 1, 2, 0, 2, 3};
	m.paints = {paint};
	m.opaqueIndexCount = 6;
	m.trianglesAfter = 2;

	return m;
}

void fillWindow(const BakeParams &p, const FinalSource &src, double window[4]) {
	const bool given = p.window[2] > p.window[0] && p.window[3] > p.window[1];

	window[0] = given ? std::max(0.0, p.window[0]) : 0.0;
	window[1] = given ? std::max(0.0, p.window[1]) : 0.0;
	window[2] = given ? std::min(double(src.width), p.window[2]) : double(src.width);
	window[3] = given ? std::min(double(src.height), p.window[3]) : double(src.height);
}

// meshoptimizer is the last resort inside a level, tried when the level is within this factor of
// the cap (its error stays under the next level's tolerance, so a level it cannot bring down
// falls through to the next).
constexpr double SIMPLIFY_REACH = 8.0;

static_assert(LOD_MEAN == slughorn::bake::LOD_LEVELS, "slug_api.h LOD_MEAN follows bake::LOD_LEVELS");

// The finest level whose probe fits: level 0 first (where most keys land), then a binary search
// over the rest (a coarser level of a key never needs more triangles, near enough) - a handful
// of bakes instead of up to LOD_LEVELS. -1: none fits.
int searchLevels(const std::function<bool(int)> &probe) {
	if (probe(0)) {
		return 0;
	}

	int lo = 1, hi = slughorn::bake::LOD_LEVELS - 1, best = -1;

	while (lo <= hi) {
		const int mid = (lo + hi) / 2;

		if (probe(mid)) {
			best = mid;
			hi = mid - 1;
		} else {
			lo = mid + 1;
		}
	}

	return best;
}

} // namespace

bool bake(const std::string &key_spec, const BakeParams &p, FinalBake &out, std::string &err) {
	out = FinalBake{};

	FinalSource src;

	if (!resolveSpec(key_spec, src, err)) {
		return false;
	}

	double window[4];

	fillWindow(p, src, window);

	const size_t budget = p.cap > 0 ? size_t(p.cap) * 8 : 0;
	FinalBake best;
	std::vector<Lod> rows;
	bool failed = false;

	std::function<bool(int)> probe = [&](int level) {
		const slughorn::bake::BakedMesh *m = finalLevel(key_spec, src, p, level, window, budget, err);

		if (!m) {
			failed = true;
			return true; // stop the search
		}

		Lod lod;

		lod.level = level;
		lod.triangles = int64_t(m->trianglesAfter);
		lod.surface_triangles = lod.triangles;
		lod.feature_px = m->featurePx;
		lod.tolerance_px = slughorn::bake::lodLevel(level, slug_t(src.tolerancePx)).tolerancePx;
		lod.aborted = m->aborted;

		std::function<bool(const slughorn::bake::BakedMesh &)> accept = [&](const slughorn::bake::BakedMesh &mesh) {
			best = FinalBake{};
			toMesh(mesh, best.mesh);
			best.lod = level;
			best.transparent_area = mesh.transparentArea;
			best.canvas_area = mesh.canvasArea;
			best.folded_features = int64_t(mesh.foldedFeatures);
			best.feature_px = mesh.featurePx;
			rows.push_back(lod);
			return true;
		};

		if (!m->aborted && (p.cap <= 0 || lod.triangles <= p.cap)) {
			return accept(*m);
		}

#ifdef SLUGHORN_HAS_MESHOPT
		if (!m->aborted && double(lod.triangles) <= double(p.cap) * SIMPLIFY_REACH) {
			slughorn::bake::BakedMesh simple = *m;
			const double maxErr = slughorn::bake::lodLevel(level + 1, slug_t(src.tolerancePx)).tolerancePx;

			lod.simplify_error_px = slughorn::bake::simplifyBaked(simple, src.width, src.height, size_t(p.cap), maxErr);
			lod.surface_triangles = int64_t(simple.trianglesAfter);

			if (lod.surface_triangles <= p.cap) {
				return accept(simple);
			}
		}
#endif

		rows.push_back(lod);
		return false;
	};

	const int level = searchLevels(probe);

	if (failed) {
		return false;
	}

	std::sort(rows.begin(), rows.end(), [](const Lod &a, const Lod &b) { return a.level < b.level; });

	if (level >= 0) {
		out = std::move(best);
		out.lods = std::move(rows);
		return true;
	}

	out.lods = std::move(rows);

	const slughorn::bake::BakedMesh *coarsest = finalLevel(key_spec, src, p, slughorn::bake::LOD_LEVELS - 1, window, budget, err);

	if (!coarsest) {
		return false;
	}

	// The mean.
	bool keep = false;
	const slughorn::bake::Paint paint = meanPaint(*coarsest, src, p, keep);
	const slughorn::bake::BakedMesh mean = keep ? meanMesh(paint, src, window) : slughorn::bake::BakedMesh{};

	Lod lod;

	lod.level = LOD_MEAN;
	lod.triangles = lod.surface_triangles = int64_t(mean.trianglesAfter);
	out.lods.push_back(lod);

	toMesh(mean, out.mesh);
	out.lod = LOD_MEAN;
	out.canvas_area = coarsest->canvasArea;
	out.transparent_area = coarsest->transparentArea;

	return true;
}

bool decal_final(const std::string &key_spec, const std::vector<float> &v, const std::vector<float> &nv,
		const std::vector<float> &uvs, const std::vector<int32_t> &f, const std::vector<float> &xform,
		const std::vector<float> &lift, const BakeParams &params, double feature_floor_world, Decal &out, std::string &err) {
	out = Decal{};

	FinalSource src;

	if (!resolveSpec(key_spec, src, err)) {
		return false;
	}

	if (xform.size() < 5 || lift.size() < 2) {
		err = "decal: uv_xform wants 5 floats, lift 2";
		return false;
	}

	const size_t nverts = v.size() / 3;

	if (v.size() % 3 || f.size() % 3 || uvs.size() < nverts * 2) {
		err = "decal: vertices 3N, uvs 2N, triangles 3F";
		return false;
	}

	// The surface's UV footprint (after uv_xform; with wrap, every whole-unit shift folded into
	// [0,1]^2) as a canvas window, and its texel density (world units per UV unit).
	const V2 rep{xform[0], xform[1]}, off{xform[2], xform[3]};
	const bool wrap = xform[4] > 0.5f;
	double u0 = 1e300, v0 = 1e300, u1 = -1e300, v1 = -1e300, area3 = 0, areaUv = 0;

	for (size_t sf = 0; sf + 2 < f.size(); sf += 3) {
		V2 t[3];
		V3 q[3];

		for (int k = 0; k < 3; ++k) {
			const int32_t i = f[sf + size_t(k)];

			if (i < 0 || size_t(i) >= nverts) {
				err = "decal: triangle index out of range";
				return false;
			}

			t[k] = {uvs[size_t(i) * 2] * rep.x + off.x, uvs[size_t(i) * 2 + 1] * rep.y + off.y};
			q[k] = {v[size_t(i) * 3], v[size_t(i) * 3 + 1], v[size_t(i) * 3 + 2]};
		}

		const double a2 = std::abs(cross(t[1] - t[0], t[2] - t[0]));

		if (a2 < 1e-14) {
			continue;
		}

		const V3 c3 = cross3(q[1] - q[0], q[2] - q[0]);

		area3 += std::sqrt(dot3(c3, c3));
		areaUv += a2;

		const double fx0 = std::min({t[0].x, t[1].x, t[2].x}), fx1 = std::max({t[0].x, t[1].x, t[2].x});
		const double fy0 = std::min({t[0].y, t[1].y, t[2].y}), fy1 = std::max({t[0].y, t[1].y, t[2].y});

		if (wrap && (std::floor(fx0) != std::floor(fx1 - 1e-9) || std::floor(fy0) != std::floor(fy1 - 1e-9))) {
			u0 = v0 = 0;
			u1 = v1 = 1;
			continue;
		}

		const double sx = wrap ? std::floor(fx0) : 0.0, sy = wrap ? std::floor(fy0) : 0.0;

		u0 = std::min(u0, fx0 - sx);
		u1 = std::max(u1, fx1 - sx);
		v0 = std::min(v0, fy0 - sy);
		v1 = std::max(v1, fy1 - sy);
	}

	out.world_per_uv = areaUv > 0 ? std::sqrt(area3 / areaUv) : 0.0;

	if (!(u1 > u0 && v1 > v0)) {
		out.overlay_from = 0;
		return true; // nothing of the surface samples the key
	}

	// UV (v up) -> canvas px (y down), padded by two px.
	const double W = src.width, H = src.height;

	BakeParams p = params;

	p.window[0] = std::clamp(u0, 0.0, 1.0) * W - 2.0;
	p.window[2] = std::clamp(u1, 0.0, 1.0) * W + 2.0;
	p.window[1] = (1.0 - std::clamp(v1, 0.0, 1.0)) * H - 2.0;
	p.window[3] = (1.0 - std::clamp(v0, 0.0, 1.0)) * H + 2.0;

	if (feature_floor_world > 0 && out.world_per_uv > 0) {
		p.feature_floor_px = std::max(p.feature_floor_px, feature_floor_world / out.world_per_uv * W);
	}

	double window[4];

	fillWindow(p, src, window);
	out.canvas_area = (window[2] - window[0]) * (window[3] - window[1]);

	const Surface surf{v, nv, uvs, f, xform};
	const int64_t cap = p.cap > 0 ? p.cap : INT64_MAX;
	const size_t budget = p.cap > 0 ? size_t(p.cap) * 8 : 0;
	Decal best;
	std::vector<Lod> rows;
	bool failed = false;

	std::function<bool(int)> probe = [&](int level) {
		const slughorn::bake::BakedMesh *m = finalLevel(key_spec, src, p, level, window, budget, err);

		if (!m) {
			failed = true;
			return true; // stop the search
		}

		Lod lod;

		lod.level = level;
		lod.triangles = int64_t(m->trianglesAfter);
		lod.feature_px = m->featurePx;
		lod.tolerance_px = slughorn::bake::lodLevel(level, slug_t(src.tolerancePx)).tolerancePx;
		lod.aborted = m->aborted;

		if (m->aborted) {
			rows.push_back(lod);
			return false;
		}

		Decal tmp;

		std::function<bool(const slughorn::bake::BakedMesh &)> accept = [&](const slughorn::bake::BakedMesh &mesh) {
			tmp.lod = level;
			tmp.transparent_area = mesh.transparentArea;
			tmp.feature_px = mesh.featurePx;
			paintsWire(mesh.paints, tmp.paints);
			best = std::move(tmp);
			rows.push_back(lod);
			return true;
		};

		// Clipped without a cap first: the count tells meshoptimizer how far to go.
		const int r = clipToSurface(*m, surf, lift[0], lift[1], INT64_MAX, tmp, err);

		if (r < 0) {
			failed = true;
			return true;
		}

		const int64_t clipped = int64_t(tmp.paint.size());

		lod.surface_triangles = clipped;

		if (clipped <= cap) {
			return accept(*m);
		}

#ifdef SLUGHORN_HAS_MESHOPT
		// Within reach of the cap: simplify the window bake toward the cap's share of it (the clip
		// splits triangles, so the window target is the cap scaled by bake / clipped).
		if (double(clipped) <= double(cap) * SIMPLIFY_REACH) {
			const double maxErr = slughorn::bake::lodLevel(level + 1, slug_t(src.tolerancePx)).tolerancePx;
			double share = double(m->trianglesAfter) / double(clipped);

			for (int attempt = 0; attempt < 2; ++attempt, share *= 0.8) {
				slughorn::bake::BakedMesh simple = *m;

				lod.simplify_error_px = slughorn::bake::simplifyBaked(simple, W, H, size_t(std::max(1.0, double(cap) * share * 0.95)), maxErr);

				const int r2 = clipToSurface(simple, surf, lift[0], lift[1], cap, tmp, err);

				if (r2 < 0) {
					failed = true;
					return true;
				}

				if (r2 == 1) {
					lod.surface_triangles = int64_t(tmp.paint.size());
					return accept(simple);
				}
			}
		}
#endif

		rows.push_back(lod);
		return false;
	};

	const int found = searchLevels(probe);

	if (failed) {
		return false;
	}

	std::sort(rows.begin(), rows.end(), [](const Lod &a, const Lod &b) { return a.level < b.level; });

	if (found >= 0) {
		const double worldPerUv = out.world_per_uv, canvasArea = out.canvas_area;

		out = std::move(best);
		out.lods = std::move(rows);
		out.world_per_uv = worldPerUv;
		out.canvas_area = canvasArea;
		return true;
	}

	out.lods = std::move(rows);

	const slughorn::bake::BakedMesh *coarsest = finalLevel(key_spec, src, p, slughorn::bake::LOD_LEVELS - 1, window, budget, err);

	if (!coarsest) {
		return false;
	}

	// The mean: the surface's own faces in the window's mean colour (one triangle a face).
	bool keep = false;
	const slughorn::bake::Paint paint = meanPaint(*coarsest, src, p, keep);
	Lod lod;

	lod.level = LOD_MEAN;
	out.lod = LOD_MEAN;
	out.transparent_area = coarsest->transparentArea;
	out.vertices.clear();
	out.normals.clear();
	out.paint.clear();
	out.param.clear();

	if (keep) {
		const bool haveNormals = nv.size() == v.size();

		for (size_t sf = 0; sf + 2 < f.size(); sf += 3) {
			V3 q[3], n[3];

			for (int k = 0; k < 3; ++k) {
				const size_t i = size_t(f[sf + size_t(k)]);

				q[k] = {v[i * 3], v[i * 3 + 1], v[i * 3 + 2]};
				n[k] = haveNormals ? V3{nv[i * 3], nv[i * 3 + 1], nv[i * 3 + 2]} : V3{};
			}

			const V3 fn = normalized(cross3(q[1] - q[0], q[2] - q[0]));

			for (int k = 0; k < 3; ++k) {
				const V3 nn = haveNormals ? normalized(n[k]) : fn;
				const V3 pt = q[k] + nn * lift[0];

				out.vertices.insert(out.vertices.end(), {float(pt.x), float(pt.y), float(pt.z)});
				out.normals.insert(out.normals.end(), {float(nn.x), float(nn.y), float(nn.z)});
				out.param.insert(out.param.end(), {0.0f, 0.0f});
			}

			out.paint.push_back(0);
		}

		paintsWire({paint}, out.paints);
	} else {
		paintsWire({}, out.paints);
	}

	out.overlay_from = int32_t(out.paint.size());
	lod.surface_triangles = int64_t(out.paint.size());
	out.lods.push_back(lod);

	return true;
}

} // namespace slug
