// The lighting lab's fixer (tools/lighting_lab.gd --fit): fits the toon model to the target renders
// from one port state's reference passes. The ramp thresholds are a step function, which L-BFGS-B
// cannot fit, so an exact dynamic programme over the 16-bit dot(N, L) bins places them; L-BFGS-B
// (contract-lbfgsb, CPU backend) fits the smooth block on every geometry pixel. They alternate
// until no bin changes band.
//   lighting_fit <dir> <target> <passes> <views> t0 t1 t2 l0 l1 l2 l3 gain sky.rgb ground.rgb
// Colours are linear. The result is one JSON line on stdout.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "lbfgsb.h"
#include "vec_cpu.h"

namespace {

const double kPi = 3.14159265358979323846;
const double kSun = 2.75 / kPi;
const double kHemi = 1.62 / kPi;
const double kQ = 65535.0;
// The smooth block: sun gain, levels 0-2, sky rgb, ground rgb. Level 3 stays the port's, fixing
// the gain's scale.
const int kN = 10;

struct Px {
	float alb[3];
	float sh;
	float u;
	uint16_t q;
	uint8_t t[3];
};

struct Bin {
	uint16_t q;
	uint32_t begin;
	uint32_t end;
};

struct Fit {
	std::vector<Px> px;
	std::vector<uint32_t> order;
	std::vector<Bin> bins;
	double l3 = 1.0;
	unsigned threads = 1;
};

struct Ppm {
	int w = 0;
	int h = 0;
	std::vector<uint8_t> rgb;
};

bool read_ppm(const std::string &path, Ppm &img) {
	FILE *f = std::fopen(path.c_str(), "rb");
	if (f == nullptr) {
		return false;
	}
	int maxv = 0;
	bool ok = std::fscanf(f, "P6 %d %d %d", &img.w, &img.h, &maxv) == 3 && maxv == 255 && std::fgetc(f) != EOF;
	if (ok) {
		img.rgb.resize(size_t(img.w) * size_t(img.h) * 3);
		ok = std::fread(img.rgb.data(), 1, img.rgb.size(), f) == img.rgb.size();
	}
	std::fclose(f);
	return ok;
}

double to_linear(double s) {
	return s <= 0.04045 ? s / 12.92 : std::pow((s + 0.055) / 1.055, 2.4);
}

// One channel as the viewport stores it, 255 srgb(clamp(lin)), and its slope in codes per unit.
double encode(double lin, double &slope) {
	if (lin <= 0.0 || lin >= 1.0) {
		slope = 0.0;
		return lin <= 0.0 ? 0.0 : 255.0;
	}
	if (lin <= 0.0031308) {
		slope = 255.0 * 12.92;
		return slope * lin;
	}
	double p = std::pow(lin, 1.0 / 2.4);
	slope = 255.0 * 1.055 / 2.4 * p / lin;
	return 255.0 * (1.055 * p - 0.055);
}

template <typename F>
void parallel(unsigned nt, size_t n, F fn) {
	std::vector<std::thread> pool;
	for (unsigned t = 0; t < nt; ++t) {
		pool.emplace_back(fn, t, n * t / nt, n * (t + 1) / nt);
	}
	for (std::thread &th : pool) {
		th.join();
	}
}

int band_of(const double tv[3], double q) {
	return q < tv[0] ? 0 : (q < tv[1] ? 1 : (q < tv[2] ? 2 : 3));
}

// Mean squared 8-bit error over every channel of every geometry pixel, its gradient, and per
// parameter the steepest slope of any pixel channel, which sets that parameter's tolerance.
double objective(const Fit &fit, const std::vector<uint8_t> &band, const double *x, double *grad, double *slope) {
	const unsigned nt = fit.threads;
	const size_t stride = 1 + 2 * kN;
	std::vector<double> acc(size_t(nt) * stride, 0.0);
	parallel(nt, fit.px.size(), [&](unsigned t, size_t i0, size_t i1) {
		double *a = &acc[size_t(t) * stride];
		const double lev[4] = { x[1], x[2], x[3], fit.l3 };
		const double s = kSun * x[0];
		for (size_t i = i0; i < i1; ++i) {
			const Px &p = fit.px[i];
			const int b = band[i];
			const double sun = s * lev[b] * p.sh;
			for (int c = 0; c < 3; ++c) {
				const double e = sun + kHemi * (x[7 + c] + (x[4 + c] - x[7 + c]) * p.u);
				double d = 0.0;
				const double r = encode(p.alb[c] * e, d) - p.t[c];
				const double k = d * p.alb[c];
				double dm[kN] = {};
				dm[0] = k * kSun * lev[b] * p.sh;
				if (b < 3) {
					dm[1 + b] = k * s * p.sh;
				}
				dm[4 + c] = k * kHemi * p.u;
				dm[7 + c] = k * kHemi * (1.0 - p.u);
				a[0] += r * r;
				for (int j = 0; j < kN; ++j) {
					a[1 + j] += 2.0 * r * dm[j];
					a[1 + kN + j] = std::max(a[1 + kN + j], std::fabs(dm[j]));
				}
			}
		}
	});
	const double n3 = 3.0 * double(fit.px.size());
	double f = 0.0;
	for (int j = 0; j < kN; ++j) {
		grad[j] = 0.0;
		if (slope != nullptr) {
			slope[j] = 0.0;
		}
	}
	for (unsigned t = 0; t < nt; ++t) {
		const double *a = &acc[size_t(t) * stride];
		f += a[0];
		for (int j = 0; j < kN; ++j) {
			grad[j] += a[1 + j];
			if (slope != nullptr) {
				slope[j] = std::max(slope[j], a[1 + kN + j]);
			}
		}
	}
	for (int j = 0; j < kN; ++j) {
		grad[j] /= n3;
	}
	return f / n3;
}

// The band of every occupied dot(N, L) bin, non-decreasing in dot(N, L), that minimises the
// objective with the smooth block held: exact, by dynamic programming over the bins.
std::vector<uint8_t> place(const Fit &fit, const double *x) {
	const size_t nb = fit.bins.size();
	std::vector<double> cost(nb * 4, 0.0);
	parallel(fit.threads, nb, [&](unsigned, size_t j0, size_t j1) {
		const double lev[4] = { x[1], x[2], x[3], fit.l3 };
		const double s = kSun * x[0];
		for (size_t j = j0; j < j1; ++j) {
			for (uint32_t o = fit.bins[j].begin; o < fit.bins[j].end; ++o) {
				const Px &p = fit.px[fit.order[o]];
				double hemi[3];
				for (int c = 0; c < 3; ++c) {
					hemi[c] = kHemi * (x[7 + c] + (x[4 + c] - x[7 + c]) * p.u);
				}
				for (int k = 0; k < 4; ++k) {
					double sum = 0.0;
					for (int c = 0; c < 3; ++c) {
						double d = 0.0;
						const double r = encode(p.alb[c] * (s * lev[k] * p.sh + hemi[c]), d) - p.t[c];
						sum += r * r;
					}
					cost[4 * j + k] += sum;
				}
			}
		}
	});
	std::vector<double> best(nb * 4);
	std::vector<uint8_t> from(nb * 4, 0);
	for (int k = 0; k < 4; ++k) {
		best[k] = cost[k];
	}
	for (size_t j = 1; j < nb; ++j) {
		for (int k = 0; k < 4; ++k) {
			int arg = 0;
			for (int kp = 1; kp <= k; ++kp) {
				if (best[4 * (j - 1) + kp] < best[4 * (j - 1) + arg]) {
					arg = kp;
				}
			}
			best[4 * j + k] = cost[4 * j + k] + best[4 * (j - 1) + arg];
			from[4 * j + k] = uint8_t(arg);
		}
	}
	std::vector<uint8_t> binband(nb);
	int k = 0;
	for (int kp = 1; kp < 4; ++kp) {
		if (best[4 * (nb - 1) + kp] < best[4 * (nb - 1) + k]) {
			k = kp;
		}
	}
	for (size_t j = nb; j-- > 0;) {
		binband[j] = uint8_t(k);
		k = from[4 * j + k];
	}
	return binband;
}

std::vector<uint8_t> pixel_bands(const Fit &fit, const std::vector<uint8_t> &binband) {
	std::vector<uint8_t> band(fit.px.size());
	for (size_t j = 0; j < fit.bins.size(); ++j) {
		for (uint32_t o = fit.bins[j].begin; o < fit.bins[j].end; ++o) {
			band[fit.order[o]] = binband[j];
		}
	}
	return band;
}

// A threshold stays where the port had it unless the programme bands some bin other than the one
// it sits in differently; then it moves to the midpoint between the last bin below and the first
// above. Thresholds are in 16-bit bin units.
void thresholds(const Fit &fit, const std::vector<uint8_t> &binband, const double *start, double *tv) {
	for (int k = 0; k < 3; ++k) {
		double lo = -1.0;
		double hi = -1.0;
		int mismatched = 0;
		bool only_own = true;
		for (size_t j = 0; j < fit.bins.size(); ++j) {
			const double q = fit.bins[j].q;
			const bool below = binband[j] <= k;
			if (below) {
				lo = q;
			} else if (hi < 0.0) {
				hi = q;
			}
			if (below != (q < start[k])) {
				++mismatched;
				only_own = only_own && q == std::round(start[k]);
			}
		}
		if (mismatched == 0 || (mismatched == 1 && only_own)) {
			tv[k] = start[k];
		} else if (lo >= 0.0 && hi >= 0.0) {
			tv[k] = 0.5 * (lo + hi);
		} else {
			tv[k] = lo < 0.0 ? hi - 0.5 : lo + 0.5;
		}
		if (k > 0) {
			tv[k] = std::max(tv[k], tv[k - 1]);
		}
	}
}

std::string fit_smooth(const Fit &fit, const std::vector<uint8_t> &band, double *x, int &evals) {
	VecCpu v;
	Lbfgsb s(v);
	float x0[kN];
	float lb[kN];
	float ub[kN];
	for (int j = 0; j < kN; ++j) {
		x0[j] = float(x[j]);
		lb[j] = 0.0f;
		ub[j] = j == 0 ? 4.0f : (j < 4 ? 1.5f : 1.0f);
	}
	LbfgsbParams p;
	p.max_iterations = 200;
	Lbfgsb::Status st = s.start(kN, x0, lb, ub, p);
	std::vector<float> xf;
	while (st != Lbfgsb::CONVERGED && st != Lbfgsb::FAIL) {
		if (st == Lbfgsb::NEED_EVAL || st == Lbfgsb::TRY) {
			s.readX(xf);
			double xd[kN];
			double g[kN];
			for (int j = 0; j < kN; ++j) {
				xd[j] = xf[j];
			}
			const double f = objective(fit, band, xd, g, nullptr);
			float gf[kN];
			for (int j = 0; j < kN; ++j) {
				gf[j] = float(g[j]);
			}
			s.setGradient(gf);
			++evals;
			st = s.next(f);
		} else {
			st = s.next();
		}
	}
	if (st == Lbfgsb::FAIL) {
		return std::string("FAIL ") + s.error();
	}
	s.readX(xf);
	for (int j = 0; j < kN; ++j) {
		x[j] = xf[j];
	}
	return std::string("CONVERGED ") + s.reason();
}

} // namespace

int main(int argc, char **argv) {
	if (argc != 19) {
		std::fprintf(stderr, "usage: %s <dir> <target> <passes> <views> t0 t1 t2 l0 l1 l2 l3 gain sky.rgb ground.rgb\n", argv[0]);
		return 2;
	}
	const std::string dir = argv[1];
	const std::string target = argv[2];
	const std::string passes = argv[3];
	const int views = std::atoi(argv[4]);
	double start[14];
	for (int i = 0; i < 14; ++i) {
		start[i] = std::strtod(argv[5 + i], nullptr);
	}
	Fit fit;
	fit.l3 = start[6];
	fit.threads = std::max(1u, std::thread::hardware_concurrency());
	for (int v = 0; v < views; ++v) {
		Ppm t;
		Ppm alb;
		Ppm light;
		Ppm ndl;
		const std::string s = std::to_string(v);
		if (!read_ppm(dir + "/" + target + "_" + s + ".ppm", t) || !read_ppm(dir + "/" + passes + "_albedo_" + s + ".ppm", alb) ||
				!read_ppm(dir + "/" + passes + "_light_" + s + ".ppm", light) || !read_ppm(dir + "/" + passes + "_ndl_" + s + ".ppm", ndl) ||
				alb.rgb.size() != t.rgb.size() || light.rgb.size() != t.rgb.size() || ndl.rgb.size() != t.rgb.size()) {
			std::fprintf(stderr, "lighting_fit: view %d's images are missing or differ in size\n", v);
			return 1;
		}
		for (size_t i = 0; i < t.rgb.size(); i += 3) {
			if (alb.rgb[i] == 0 && alb.rgb[i + 1] == 0 && alb.rgb[i + 2] == 0) {
				continue;
			}
			Px p;
			for (int c = 0; c < 3; ++c) {
				p.alb[c] = float(to_linear(alb.rgb[i + c] / 255.0));
				p.t[c] = t.rgb[i + c];
			}
			p.sh = light.rgb[i + 1] / 255.0f;
			p.u = light.rgb[i + 2] / 255.0f;
			p.q = uint16_t(ndl.rgb[i] * 256 + ndl.rgb[i + 1]);
			fit.px.push_back(p);
		}
	}
	if (fit.px.empty()) {
		std::fprintf(stderr, "lighting_fit: no geometry pixels\n");
		return 1;
	}
	std::vector<uint32_t> count(65537, 0);
	for (const Px &p : fit.px) {
		++count[p.q + 1];
	}
	for (int q = 0; q < 65536; ++q) {
		count[q + 1] += count[q];
		if (count[q + 1] > count[q]) {
			fit.bins.push_back(Bin{ uint16_t(q), count[q], count[q + 1] });
		}
	}
	fit.order.resize(fit.px.size());
	std::vector<uint32_t> next(count.begin(), count.end() - 1);
	for (uint32_t i = 0; i < fit.px.size(); ++i) {
		fit.order[next[fit.px[i].q]++] = i;
	}

	double tv_start[3];
	for (int k = 0; k < 3; ++k) {
		tv_start[k] = (0.5 * start[k] + 0.5) * kQ;
	}
	const double x0[kN] = { start[7], start[3], start[4], start[5], start[8], start[9], start[10], start[11], start[12], start[13] };
	double x[kN];
	std::copy(x0, x0 + kN, x);
	std::vector<uint8_t> band(fit.px.size());
	for (size_t i = 0; i < fit.px.size(); ++i) {
		band[i] = uint8_t(band_of(tv_start, fit.px[i].q));
	}
	double g[kN];
	const double f_start = objective(fit, band, x, g, nullptr);

	std::vector<uint8_t> binband;
	std::vector<uint8_t> fitted;
	std::string status = "none";
	int rounds = 0;
	int evals = 0;
	for (int r = 0; r < 20; ++r) {
		binband = place(fit, x);
		std::vector<uint8_t> b = pixel_bands(fit, binband);
		if (r > 0 && b == fitted) {
			break;
		}
		status = fit_smooth(fit, b, x, evals);
		fitted = b;
		++rounds;
		if (status.rfind("FAIL", 0) == 0) {
			break;
		}
	}

	double tv[3];
	thresholds(fit, binband, tv_start, tv);
	double slope[kN];
	objective(fit, fitted, x, g, slope);
	double applied[kN];
	bool changed[kN];
	for (int j = 0; j < kN; ++j) {
		const double tol = slope[j] > 0.0 ? 0.5 / slope[j] : 1e30;
		changed[j] = std::fabs(x[j] - x0[j]) > tol;
		applied[j] = changed[j] ? x[j] : x0[j];
	}
	std::vector<uint8_t> applied_band(fit.px.size());
	for (size_t i = 0; i < fit.px.size(); ++i) {
		applied_band[i] = uint8_t(band_of(tv, fit.px[i].q));
	}
	const double f_applied = objective(fit, applied_band, applied, g, nullptr);

	std::string moved;
	const bool thr_moved = tv[0] != tv_start[0] || tv[1] != tv_start[1] || tv[2] != tv_start[2];
	const bool lev_moved = changed[1] || changed[2] || changed[3];
	const bool sky_moved = changed[4] || changed[5] || changed[6];
	const bool ground_moved = changed[7] || changed[8] || changed[9];
	const char *names[5] = { "thresholds", "levels", "sun_gain", "sky", "ground" };
	const bool flags[5] = { thr_moved, lev_moved, changed[0], sky_moved, ground_moved };
	for (int i = 0; i < 5; ++i) {
		if (flags[i]) {
			moved += std::string(moved.empty() ? "" : ",") + "\"" + names[i] + "\"";
		}
	}
	std::printf("{\"status\":\"%s\",\"rounds\":%d,\"evals\":%d,\"pixels\":%zu,\"bins\":%zu,\"f_start\":%.9g,\"f_fit\":%.9g,"
				"\"f_applied\":%.9g,\"changed\":[%s],\"thresholds\":[%.9g,%.9g,%.9g],\"levels\":[%.9g,%.9g,%.9g,%.9g],"
				"\"sun_gain\":%.9g,\"sky\":[%.9g,%.9g,%.9g],\"ground\":[%.9g,%.9g,%.9g],"
				"\"fit\":[%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g]}\n",
			status.c_str(), rounds, evals, fit.px.size(), fit.bins.size(), f_start, objective(fit, fitted, x, g, nullptr), f_applied,
			moved.c_str(), 2.0 * tv[0] / kQ - 1.0, 2.0 * tv[1] / kQ - 1.0, 2.0 * tv[2] / kQ - 1.0, applied[1], applied[2], applied[3],
			fit.l3, applied[0], applied[4], applied[5], applied[6], applied[7], applied[8], applied[9], x[0], x[1], x[2], x[3], x[4],
			x[5], x[6], x[7], x[8], x[9]);
	return status.rfind("CONVERGED", 0) == 0 ? 0 : 1;
}
