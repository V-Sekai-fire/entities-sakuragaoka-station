// slug_native -- slug_api.cpp off-sandbox: loads every <key>.svg the port ships, packs the atlas,
// bakes and costs every key and runs one decal per key, checking the wire invariants slug.elf
// promises (core/slug/atlas.gd and baked.gd). Prints one line per key and the heaviest call of
// each kind, which is what sizes the sandbox's execution_timeout.
//
//   slug_native [svg_dir] [--tolerance-px 0.25]

#include "slug_api.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <new>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifndef SLUG_SVG_DIR
#define SLUG_SVG_DIR "."
#endif

namespace fs = std::filesystem;

// Live heap allocations (the sandbox caps them: allocations_max), so the harness can report the
// peak the guest would need.
static std::atomic<int64_t> g_live{0};
static std::atomic<int64_t> g_peak{0};

void *operator new(std::size_t n) {
	void *p = std::malloc(n ? n : 1);
	if (!p) throw std::bad_alloc();
	const int64_t l = ++g_live;
	int64_t pk = g_peak.load();
	while (l > pk && !g_peak.compare_exchange_weak(pk, l)) {}
	return p;
}
void operator delete(void *p) noexcept { if (p) { --g_live; std::free(p); } }
void operator delete(void *p, std::size_t) noexcept { if (p) { --g_live; std::free(p); } }
void *operator new[](std::size_t n) { return operator new(n); }
void operator delete[](void *p) noexcept { operator delete(p); }
void operator delete[](void *p, std::size_t) noexcept { operator delete(p); }

static int g_fail = 0;

// The per-surface budget the baseline test bakes every key into.
static constexpr int64_t BASELINE_CAP = 4096;

static void expect(bool ok, const std::string &what) {
	if (!ok) {
		std::cout << "  FAIL: " << what << std::endl;
		++g_fail;
	}
}

struct Timer {
	std::chrono::steady_clock::time_point t0 = std::chrono::steady_clock::now();
	double ms() const { return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count(); }
};

struct Heaviest {
	double ms = 0;
	std::string key;
	void see(double t, const std::string &k) {
		if (t > ms) {
			ms = t;
			key = k;
		}
	}
};

static double triArea2D(const std::vector<float> &v, size_t stride, int32_t a, int32_t b, int32_t c) {
	const double ax = v[size_t(a) * stride], ay = v[size_t(a) * stride + 1];
	const double bx = v[size_t(b) * stride], by = v[size_t(b) * stride + 1];
	const double cx = v[size_t(c) * stride], cy = v[size_t(c) * stride + 1];
	return ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5;
}

int main(int argc, char **argv) {
	std::string dir = SLUG_SVG_DIR;
	std::string jsonPath;
	double tol = 0.25;

	for (int i = 1; i < argc; ++i) {
		const std::string a = argv[i];
		if (a == "--tolerance-px" && i + 1 < argc) {
			tol = std::atof(argv[++i]);
		} else if (a == "--json" && i + 1 < argc) {
			jsonPath = argv[++i];
		} else {
			dir = a;
		}
	}

	std::vector<fs::path> svgs;
	for (const fs::directory_entry &e : fs::directory_iterator(dir)) {
		if (e.path().extension() == ".svg") {
			svgs.push_back(e.path());
		}
	}
	std::sort(svgs.begin(), svgs.end());

	std::cout << "slug_native: " << svgs.size() << " SVGs from " << dir << std::endl;

	Heaviest hLoad, hMesh, hCost, hDecal, hBaseline;
	std::vector<int64_t> lodCount(size_t(slug::LOD_MEAN) + 1, 0);
	std::vector<std::string> lodLines;
	double tAll = 0;

	for (const fs::path &p : svgs) {
		std::ifstream in(p, std::ios::binary);
		std::stringstream ss;
		ss << in.rdbuf();

		Timer t;
		const std::string r = slug::load_svg(p.stem().string(), ss.str(), tol);
		const double ms = t.ms();

		tAll += ms;
		hLoad.see(ms, p.stem().string());
		expect(r.rfind("ok", 0) == 0, p.stem().string() + ": " + r);
	}

	std::cout << "allocations after loads: live " << g_live.load() << " peak " << g_peak.load() << std::endl;

	Timer ta;
	slug::Atlas a;
	std::string err;
	const bool atlasOk = slug::atlas(a, err);
	const double atlasMs = ta.ms();

	expect(atlasOk, "atlas: " + err);

	if (atlasOk) {
		expect(a.curves.size() == size_t(a.tex_width) * a.curve_height * 16, "curve bytes = width * height * 16 (RGBA32F)");
		expect(a.bands.size() == size_t(a.tex_width) * a.band_height * 4, "band bytes = width * height * 4 (RG16UI)");
		expect(a.key_layers.size() == a.keys.size() * 2, "key_layers 2 per key");
		expect(a.key_frames.size() == a.keys.size() * 4, "key_frames 4 per key");
		expect(a.layers.size() % slug::LAYER_STRIDE == 0, "layers stride 24");

		size_t layerTotal = 0;
		for (size_t i = 0; i < a.keys.size(); ++i) {
			expect(size_t(a.key_layers[i * 2]) == layerTotal, a.keys[i] + ": key_layers first is contiguous");
			layerTotal += size_t(a.key_layers[i * 2 + 1]);
		}
		size_t curveProtos = 0;

		for (size_t i = 0; i + 1 < a.stamp_protos.size(); i += 2) curveProtos += a.stamp_protos[i] == 0.0f;

		expect((layerTotal + curveProtos) * slug::LAYER_STRIDE == a.layers.size(), "key_layers counts + curve prototype records = the layer table");

		size_t gi = 1, gn = a.gradients.empty() ? 0 : size_t(a.gradients[0]);
		for (size_t g = 0; g < gn && gi < a.gradients.size(); ++g) {
			const size_t k = size_t(a.gradients[gi + 10]);
			gi += 11 + k * 5;
		}
		expect(gi == a.gradients.size(), "gradients table parses to its end");

		// Stamp wire invariants (core/slug/stamps.gd's checks, plus the encoding limits).
		const size_t nproto = a.stamp_protos.size() / 2, ninst = a.stamp_instances.size() / 12, ncell = a.stamp_cells.size() / 4;
		const size_t nlayers = a.layers.size() / slug::LAYER_STRIDE;
		size_t meanAt = 0, stampLayersSeen = 0, cellsTotal = 0;
		uint32_t maxG = 0, maxPer = 0;

		expect(a.stamp_layers.size() % 5 == 0 && a.stamp_instances.size() % 12 == 0 && a.stamp_protos.size() % 2 == 0, "stamp array strides");

		std::function<uint32_t(size_t)> u16 = [&](size_t element) { return uint32_t(a.stamp_cells[element * 2]) | (uint32_t(a.stamp_cells[element * 2 + 1]) << 8); };

		for (size_t si = 0; si < a.stamp_layers.size() / 5; ++si) {
			const int32_t G = a.stamp_layers[si * 5], B = a.stamp_layers[si * 5 + 1], first = a.stamp_layers[si * 5 + 2];
			const int32_t count = a.stamp_layers[si * 5 + 3], maxc = a.stamp_layers[si * 5 + 4];
			bool ok = G > 0 && B >= 0 && size_t(B) + size_t(G) * G <= ncell && first >= 0 && size_t(first + count) <= ninst && maxc <= 32 && count < 65536;

			for (int32_t c = 0; ok && c < G * G; ++c) {
				const uint32_t start = u16(2 * size_t(B + c)), n = u16(2 * size_t(B + c) + 1);
				const size_t e0 = 2 * size_t(B) + start;

				ok = n <= 32 && (e0 + n + 1) / 2 <= ncell;

				for (uint32_t k = 0; ok && k < n; ++k) ok = u16(e0 + k) < uint32_t(count);

				for (uint32_t k = 1; ok && k < n; ++k) ok = u16(e0 + k) > u16(e0 + k - 1); // paint order
			}

			expect(ok, "stamp layer " + std::to_string(si) + " cells / lists / limits");

			meanAt += size_t(G) * G;
			cellsTotal += size_t(G) * G;
			maxG = std::max<uint32_t>(maxG, uint32_t(G));
			maxPer = std::max<uint32_t>(maxPer, uint32_t(maxc));
			stampLayersSeen++;
		}

		expect(a.stamp_means.size() == meanAt * 4 && a.stamp_cell_max.size() == meanAt, "means / cell max: one per cell");

		for (size_t i = 0; i < ninst; ++i) {
			const size_t pid = size_t(a.stamp_instances[i * 12 + 6]);
			const int kind = pid < nproto ? int(a.stamp_protos[pid * 2]) : -1;
			const int lref = pid < nproto ? int(a.stamp_protos[pid * 2 + 1]) : -1;

			if (pid >= nproto || kind < 0 || kind > 2 || (kind == 0 && (lref < 0 || size_t(lref) >= nlayers)) || a.stamp_instances[i * 12 + 7] < 0) {
				expect(false, "instance " + std::to_string(i) + " prototype / paint");
				break;
			}
		}

		size_t marked = 0;

		for (size_t li = 0; li < nlayers; ++li) {
			if (int(a.layers[li * slug::LAYER_STRIDE + 15]) == slug::STAMP_BLEND) {
				marked++;
				expect(size_t(a.layers[li * slug::LAYER_STRIDE + 14]) < stampLayersSeen, "stamp layer record index in range");
			}
		}

		expect(marked == stampLayersSeen, "one marked layer record per stamp layer");

		std::cout << "stamps: layers=" << stampLayersSeen << " instances=" << ninst << " protos=" << nproto << " cells=" << cellsTotal
				  << " cell texels=" << ncell << " max G=" << maxG << " max per cell=" << maxPer << std::endl;

		std::cout << "atlas: tex_width=" << a.tex_width << " curves " << a.tex_width << "x" << a.curve_height << " " << a.curve_format
				  << " (" << a.curves.size() << " B), bands " << a.tex_width << "x" << a.band_height << " RG16UI (" << a.bands.size()
				  << " B), layers=" << layerTotal << " gradients=" << gn << " (" << atlasMs << " ms)" << std::endl;
	}

	std::cout << "allocations after atlas: live " << g_live.load() << " peak " << g_peak.load() << std::endl;
	std::cout << "key | layers b->a | curves b->a | band h/v | work~ | tris b->a | mode | mesh/cost/decal ms" << std::endl;

	int modes[4] = {0, 0, 0, 0};
	std::ostringstream js;
	js << "{\"tex_width\": " << a.tex_width << ", \"curve_height\": " << a.curve_height << ", \"band_height\": " << a.band_height
	   << ", \"layers\": " << a.layers.size() / slug::LAYER_STRIDE << ", \"gradients\": " << (a.gradients.empty() ? 0 : int(a.gradients[0])) << ", \"keys\": {";
	bool firstKey = true;

	for (const std::string &key : slug::keys()) {
		Timer tm;
		slug::Mesh m;
		const bool meshOk = slug::mesh(key, 0.0, m, err); // bakes on first use
		const double meshMs = tm.ms();
		hMesh.see(meshMs, key);
		expect(meshOk, key + ": mesh: " + err);

		Timer tc;
		slug::Cost c;
		const bool costOk = slug::cost(key, c, err);
		const double costMs = tc.ms();
		hCost.see(costMs, key);
		expect(costOk, key + ": cost: " + err);

		if (!costOk || !meshOk) {
			continue;
		}

		modes[c.mode == "mesh" ? 0 : c.mode == "slug" ? 1 : c.mode == "stamp" ? 3 : 2]++;

		const size_t n = m.vertices.size() / 3;
		expect(m.paint.size() == n && m.param.size() == n * 2, key + ": per-vertex streams");
		expect(size_t(m.overlay_first + m.overlay_count) == m.triangles.size(), key + ": overlay range ends the index list");

		double opaqueArea = 0;
		bool ccw = true, inRange = true;
		for (size_t t = 0; t + 2 < m.triangles.size(); t += 3) {
			const double ar = triArea2D(m.vertices, 3, m.triangles[t], m.triangles[t + 1], m.triangles[t + 2]);
			if (ar < -1e-12) {
				ccw = false;
			}
			if (t < size_t(m.overlay_first)) {
				opaqueArea += ar;
			}
		}
		for (size_t i = 0; i < n; ++i) {
			if (m.vertices[i * 3] < -1e-5f || m.vertices[i * 3] > 1 + 1e-5f || m.vertices[i * 3 + 1] < -1e-5f || m.vertices[i * 3 + 1] > 1 + 1e-5f) {
				inRange = false;
			}
		}
		expect(ccw, key + ": every triangle CCW in UV");
		expect(inRange, key + ": UVs inside [0,1]");
		expect(opaqueArea <= 1.0 + 1e-3, key + ": planar opaque set covers at most the canvas once");

		// Decal onto a unit quad (z = 0, normal +z) whose UVs are the canvas: the clipped base must
		// cover exactly the bake's opaque area.
		const std::vector<float> qv = {0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0};
		const std::vector<float> quv = {0, 0, 1, 0, 1, 1, 0, 1};
		const std::vector<int32_t> qf = {0, 1, 2, 0, 2, 3};
		Timer td;
		slug::Decal d;
		const bool decalOk = slug::decal(key, qv, {}, quv, qf, {1, 1, 0, 0, 0}, {0, 0}, 4000000, 0.0, d, err);
		const double decalMs = td.ms();
		hDecal.see(decalMs, key);
		expect(decalOk && !d.capped, key + ": decal: " + err);

		// A card that samples one cell of a 2 x 2 atlas: a quad whose UVs cover [0.5, 1] x [0.5, 1].
		// The clipped decal of the cutout bake must hold exactly that cell's share of the bake,
		// magnified 4x (the quad is 1 x 1 while the cell is 0.5 x 0.5 in UV).
		{
			slug::Mesh cm;
			slug::Decal cd;
			const std::vector<float> cuv = {0.5f, 0.5f, 1.0f, 0.5f, 1.0f, 1.0f, 0.5f, 1.0f};

			if (slug::mesh(key, 0.5, cm, err) && slug::decal(key, qv, {}, cuv, qf, {1, 1, 0, 0, 0}, {0, 0}, 4000000, 0.5, cd, err) && !cd.capped) {
				double cellArea = 0, decalArea = 0;

				for (size_t t = 0; t + 2 < cm.triangles.size(); t += 3) {
					// Clip each baked triangle to the cell (Sutherland-Hodgman against the 4 edges).
					std::vector<std::pair<double, double>> poly;

					for (int k = 0; k < 3; ++k) poly.push_back({cm.vertices[size_t(cm.triangles[t + size_t(k)]) * 3], cm.vertices[size_t(cm.triangles[t + size_t(k)]) * 3 + 1]});

					for (int e = 0; e < 4 && !poly.empty(); ++e) {
						std::vector<std::pair<double, double>> outp;
						std::function<bool(const std::pair<double, double> &)> inside = [&](const std::pair<double, double> &p) { return e == 0 ? p.first >= 0.5 : e == 1 ? p.first <= 1.0 : e == 2 ? p.second >= 0.5 : p.second <= 1.0; };
						std::function<std::pair<double, double>(const std::pair<double, double> &, const std::pair<double, double> &)> cut =
							[&](const std::pair<double, double> &p, const std::pair<double, double> &q) {
							const double edge = e == 0 ? 0.5 : e == 1 ? 1.0 : e == 2 ? 0.5 : 1.0;
							const double u = (e < 2) ? (edge - p.first) / (q.first - p.first) : (edge - p.second) / (q.second - p.second);
							return std::pair<double, double>{p.first + (q.first - p.first) * u, p.second + (q.second - p.second) * u};
						};

						for (size_t i = 0; i < poly.size(); ++i) {
							const std::pair<double, double> &p = poly[i], &q = poly[(i + 1) % poly.size()];

							if (inside(p)) outp.push_back(p);
							if (inside(p) != inside(q)) outp.push_back(cut(p, q));
						}

						poly = std::move(outp);
					}

					for (size_t i = 1; i + 1 < poly.size(); ++i) {
						cellArea += std::abs((poly[i].first - poly[0].first) * (poly[i + 1].second - poly[0].second) -
								(poly[i + 1].first - poly[0].first) * (poly[i].second - poly[0].second)) * 0.5;
					}
				}

				for (size_t t = 0; t < cd.paint.size(); ++t) {
					decalArea += std::abs(triArea2D(cd.vertices, 3, int32_t(t * 3), int32_t(t * 3 + 1), int32_t(t * 3 + 2)));
				}

				expect(cd.overlay_from == int32_t(cd.paint.size()), key + ": cutout decal has no overlay");
				expect(std::abs(decalArea - 4.0 * cellArea) < 2e-3, key + ": card cell decal area " + std::to_string(decalArea) + " == 4 x cutout area in the cell " + std::to_string(4.0 * cellArea));
			} else {
				expect(false, key + ": cutout mesh / card decal: " + err);
			}
		}

		if (decalOk && !d.capped) {
			double baseArea = 0;
			for (size_t t = 0; t < size_t(d.overlay_from); ++t) {
				baseArea += triArea2D(d.vertices, 3, int32_t(t * 3), int32_t(t * 3 + 1), int32_t(t * 3 + 2));
			}
			expect(std::abs(baseArea - opaqueArea) < 1e-3, key + ": decal base area " + std::to_string(baseArea) + " == bake opaque area " + std::to_string(opaqueArea));
		}

		// slug-baked: the key on a full-canvas quad with a 4096-triangle budget bakes at SOME level
		// within it (cards alpha-tested, the rest opaque), never handed to slug-runtime.
		{
			slug::BakeParams bp;
			slug::Decal fd;

			bp.mode = opaqueArea < 0.95 ? 2 : 0;
			bp.alpha_test = 0.5;
			bp.cap = BASELINE_CAP;

			Timer tb;
			const bool ok = slug::decal_final(key, qv, {}, quv, qf, {1, 1, 0, 0, 0}, {0, 0}, bp, 0.0, fd, err);
			const double bakeMs = tb.ms();

			hBaseline.see(bakeMs, key);
			expect(ok && !fd.capped, key + ": slug-baked decal: " + err);
			expect(ok && int64_t(fd.paint.size()) <= BASELINE_CAP, key + ": slug-baked within " + std::to_string(BASELINE_CAP) + " triangles (" + std::to_string(fd.paint.size()) + ")");
			expect(ok && fd.lod >= 0 && fd.lod <= slug::LOD_MEAN, key + ": slug-baked LOD level");

			if (ok) {
				lodCount[size_t(std::clamp(fd.lod, 0, slug::LOD_MEAN))]++;
				lodLines.push_back(key + " lod " + std::to_string(fd.lod) + " tris " + std::to_string(fd.paint.size()) + " feature_px " + std::to_string(fd.feature_px) +
						" (" + std::to_string(bakeMs) + " ms)");
			}
		}

		js << (firstKey ? "" : ", ") << "\"" << key << "\": {\"mode\": \"" << c.mode << "\", \"curves_after\": " << c.curves_after
		   << ", \"layers_after\": " << c.layers_after << ", \"vertices\": " << n << ", \"triangles\": " << m.triangles.size() / 3
		   << ", \"overlay\": " << m.overlay_count << ", \"opaque_area\": " << opaqueArea << "}";
		firstKey = false;

		char line[512];
		std::snprintf(line, sizeof(line), "%s | %lld->%lld | %lld->%lld | %lld/%lld | %.0f | %lld->%lld | %s | %.0f/%.0f/%.0f",
				key.c_str(), (long long)c.layers_before, (long long)c.layers_after, (long long)c.curves_before, (long long)c.curves_after,
				(long long)c.max_band_curves_h, (long long)c.max_band_curves_v, c.slug_work_mean, (long long)c.triangles_before,
				(long long)c.triangles_after, c.mode.c_str(), meshMs, costMs, decalMs);
		std::cout << line << std::endl;
	}

 	js << "}}";
	if (!jsonPath.empty()) {
		std::ofstream(jsonPath) << js.str();
	}

	// A planted over-budget surface must coarsen, not fail: the heaviest key on a quad with a
	// 500-triangle budget. Control: the legacy (planar) decal with the same cap gives up.
	{
		const std::vector<float> qv = {0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0};
		const std::vector<float> quv = {0, 0, 1, 0, 1, 1, 0, 1};
		const std::vector<int32_t> qf = {0, 1, 2, 0, 2, 3};
		const std::string heavy = "st-gravel";
		slug::BakeParams bp;
		slug::Decal fd, legacy;
		std::string err;

		bp.mode = 0;
		bp.cap = 500;

		const bool ok = slug::decal_final(heavy, qv, {}, quv, qf, {1, 1, 0, 0, 0}, {0, 0}, bp, 0.0, fd, err);

		expect(ok && !fd.capped && int64_t(fd.paint.size()) <= 500 && fd.lod > 0, heavy + " at 500 triangles coarsens (lod " + std::to_string(fd.lod) + ", " +
				std::to_string(fd.paint.size()) + " triangles): " + err);

		const bool lok = slug::decal(heavy, qv, {}, quv, qf, {1, 1, 0, 0, 0}, {0, 0}, 500, 0.0, legacy, err);

		expect(lok && legacy.capped, "control: the legacy decal of " + heavy + " at 500 triangles is capped");

		std::cout << "planted over-budget: " << heavy << " cap 500 -> lod " << fd.lod << ", " << fd.paint.size() << " triangles, feature_px " << fd.feature_px
				  << "; legacy decal capped=" << legacy.capped << std::endl;

		for (const slug::Lod &l : fd.lods) {
			std::cout << "  level " << l.level << ": window " << l.triangles << " surface " << l.surface_triangles << " feature_px " << l.feature_px
					  << " tolerance_px " << l.tolerance_px << " simplify_err " << l.simplify_error_px << (l.aborted ? " (aborted)" : "") << std::endl;
		}
	}

	// Per-surface budgets after UV-footprint clipping: a sign that samples one cell of a text atlas
	// bakes only that cell's glyphs - its window, and so its triangles, are the cell's share.
	{
		const std::vector<float> qv = {0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0};
		const std::vector<float> full = {0, 0, 1, 0, 1, 1, 0, 1};
		const std::vector<float> cell = {0.0f, 0.5f, 0.5f, 0.5f, 0.5f, 1.0f, 0.0f, 1.0f};
		const std::vector<int32_t> qf = {0, 1, 2, 0, 2, 3};
		slug::BakeParams bp;
		slug::Decal whole, part;
		std::string err;

		bp.mode = 2;
		bp.cap = 1000000;

		const bool ok = slug::decal_final("st-atlas-info", qv, {}, full, qf, {1, 1, 0, 0, 0}, {0, 0}, bp, 0.0, whole, err) &&
			slug::decal_final("st-atlas-info", qv, {}, cell, qf, {1, 1, 0, 0, 0}, {0, 0}, bp, 0.0, part, err);

		expect(ok && part.lod == 0 && whole.lod == 0, "st-atlas-info whole / cell bake at level 0: " + err);
		expect(ok && part.paint.size() < whole.paint.size() && part.canvas_area < 0.3 * whole.canvas_area,
				"a one-cell sign bakes only its cell (" + std::to_string(part.paint.size()) + " of " + std::to_string(whole.paint.size()) + " triangles)");
		std::cout << "atlas cell: st-atlas-info top-left cell " << part.paint.size() << " triangles (window " << part.canvas_area << " px^2) vs whole "
				  << whole.paint.size() << " (" << whole.canvas_area << " px^2)" << std::endl;
	}

	// The plaza tree moss: no map, alphaMap plaza-moss, opacity 0.85, transparent - the alpha map
	// folded in: paints carry alpha 0.85 (inside the moss) and nothing is drawn where it is black.
	{
		slug::BakeParams bp;
		slug::FinalBake fb;
		std::string err;

		bp.mode = 1;
		bp.opacity = 0.85;

		const bool ok = slug::bake("|plaza-moss", bp, fb, err);
		float amax = 0.0f;

		for (size_t i = 1; i + 6 < fb.mesh.paints.size();) {
			const int type = int(fb.mesh.paints[i]);
			const int k = int(fb.mesh.paints[i + 1]);

			for (int j = 0; j < k; ++j) amax = std::max(amax, fb.mesh.paints[i + 2 + size_t(j) * 5 + 4]);

			i += 2 + size_t(k) * 5;
			(void)type;
		}

		expect(ok && !fb.mesh.triangles.empty(), "|plaza-moss bakes: " + err);
		expect(std::abs(amax - 0.85f) < 1e-3f, "|plaza-moss: max alpha " + std::to_string(amax) + " == opacity 0.85");
		std::cout << "moss: " << fb.mesh.triangles.size() / 3 << " triangles, max alpha " << amax << std::endl;
	}

	std::cout << "slug-baked (cap " << BASELINE_CAP << " a full-canvas quad): levels";

	for (int l = 0; l <= slug::LOD_MEAN; ++l) std::cout << " " << l << ":" << lodCount[size_t(l)];

	std::cout << std::endl;

	for (const std::string &l : lodLines) std::cout << "  " << l << std::endl;

	std::cout << "modes: mesh=" << modes[0] << " slug=" << modes[1] << " stamp=" << modes[3] << " mean=" << modes[2] << std::endl;
 	std::cout << "allocations: live " << g_live.load() << " peak " << g_peak.load() << std::endl;
	std::cout << "heaviest: load " << hLoad.key << " " << hLoad.ms << " ms (all loads " << tAll << " ms), atlas " << atlasMs
			  << " ms, bake (slug_mesh) " << hMesh.key << " " << hMesh.ms << " ms, cost " << hCost.key << " " << hCost.ms << " ms, decal " << hDecal.key << " " << hDecal.ms
			  << " ms, slug-baked decal " << hBaseline.key << " " << hBaseline.ms << " ms" << std::endl;
	std::cout << (g_fail ? "FAILED: " : "ok: ") << g_fail << " failures" << std::endl;

	return g_fail ? 1 : 0;
}
