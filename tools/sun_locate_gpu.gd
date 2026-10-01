# The compute side of tools/sun_locate.gd: every pixel and every candidate sun is GLSL compute on a
# local RenderingDevice; GDScript uploads, dispatches and reads back a few numbers per post.
# Posts are convex parts projected along L into the light plane by their support functions; a
# candidate's cost is the soft-L1 sum of image minus Phi((sd + d) / s) over the posts' windows.
extends RefCounted

const W := 1920
const H := 1080
const NPIX := W * H
const LIST_CAP := 1 << 21
const WIN_CAP := 1 << 21
const NSL := 1024
const HIST := 512
const JOB := 64
const MAX_JOBS := 512
const PARTS_OFF := 64  # vec4 index where primitives start (posts table before it)
const RES := MAX_JOBS * JOB  # par index of the small result area
const GROUND_Y := 0.02
const TB := 2 * WIN_CAP       # vec4 index of the toon entries in win[]
const TK := WIN_CAP / 2       # their keys in wpx[]
const KEYS := 16384           # acc[] index of the toon key counts
const REGION := 32768         # acc[] index of the key -> region table

const HEADER := """
#version 450
#define NPIX %d
#define W %d
#define H %d
#define HIST %d
#define NSL %d
#define JOB %d
#define RES %d
#define PARTS_OFF %d
#define LIST_CAP %d
#define WIN_CAP %d
#define TB %d
#define TK %d
#define KEYS %d
#define REGION %d
#define GROUND_Y 0.02
#define PI 3.14159265358979
layout(std430, set = 0, binding = 0) buffer PosB { vec4 pos[]; };
layout(std430, set = 0, binding = 1) buffer NrmB { vec4 nrm[]; };
layout(std430, set = 0, binding = 2) buffer AlbB { vec4 alb[]; };
layout(std430, set = 0, binding = 3) buffer RelB { float rel[]; };
layout(std430, set = 0, binding = 4) buffer ParB { float par[]; };
layout(std430, set = 0, binding = 5) buffer LstB { uint lst[]; };
layout(std430, set = 0, binding = 6) buffer AccB { int acc[]; };
layout(std430, set = 0, binding = 7) buffer WinB { vec4 win[]; };
layout(std430, set = 0, binding = 8) buffer PrtB { vec4 prt[]; };
layout(std430, set = 0, binding = 9) buffer CstB { float cst[]; };
layout(std430, set = 0, binding = 10) buffer RawB { uint raw[]; };
layout(std430, set = 0, binding = 11) buffer ImgB { uint img[]; };
layout(std430, set = 0, binding = 12) buffer OutB { uint outp[]; };
layout(std430, set = 0, binding = 13) buffer WpxB { uint wpx[]; };
layout(std430, set = 0, binding = 14) buffer MskB { uint msk[]; };
layout(std430, set = 0, binding = 15) buffer ShB { uint shout[]; };
layout(push_constant, std430) uniform PC { ivec4 i0; ivec4 i1; vec4 f0; vec4 f1; vec4 f2; vec4 f3; } pc;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const vec3 UP = vec3(0.0, 1.0, 0.0);
float J(int job, int k) { return par[job * JOB + k]; }
bool ground(uint i) { vec4 p = pos[i]; return p.w > 0.5 && nrm[i].y > 0.97 && abs(p.y - GROUND_Y) < 0.03; }
vec3 srgb_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 sun_dir(float az, float el) { float a = radians(az), e = radians(el); return vec3(-cos(e) * cos(a), sin(e), -cos(e) * sin(a)); }
float phi(float x) {
	// Abramowitz-Stegun 7.1.26, |error| < 1.5e-7
	float z = abs(x) * 0.7071067811865476;
	float t = 1.0 / (1.0 + 0.3275911 * z);
	float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-z * z);
	return x >= 0.0 ? 0.5 * (1.0 + y) : 0.5 * (1.0 - y);
}
float support(int k, vec3 n) {
	vec4 a = prt[PARTS_OFF + 4 * k], c = prt[PARTS_OFF + 4 * k + 1], b = prt[PARTS_OFF + 4 * k + 2];
	int t = int(a.x + 0.5);
	float nh = length(n.xz);
	if (t == 0) {  // vertical frustum: circle r_bot at y0, circle r_top at y1, axis (cx, cz)
		return max(dot(n, vec3(c.x, c.y, c.z)) + a.y * nh, dot(n, vec3(c.x, c.w, c.z)) + a.z * nh);
	} else if (t == 1) {  // ellipsoid r, y scale, upper half only when a.w > 0.5
		if (a.w > 0.5 && n.y < 0.0) return dot(n, c.xyz) + a.y * nh;
		return dot(n, c.xyz) + a.y * length(vec3(n.x, a.z * n.y, n.z));
	} else if (t == 2) {  // box: half extents, turned b.x = cos, b.y = sin about Y
		vec3 ax = vec3(b.x, 0.0, -b.y), az = vec3(b.y, 0.0, b.x);
		return dot(n, c.xyz) + a.y * abs(dot(n, ax)) + a.z * abs(n.y) + a.w * abs(dot(n, az));
	}
	float na = dot(n, b.xyz);
	return dot(n, c.xyz) + 0.5 * a.z * abs(na) + a.y * sqrt(max(0.0, 1.0 - na * na));
}
float post_sd(int post, vec3 g, vec3 e1, vec3 e2) {
	vec4 pt = prt[post];
	int k0 = int(pt.x + 0.5), k1 = k0 + int(pt.y + 0.5);
	float best = -1e9;
	for (int k = k0; k < k1; k++) {
		float m = 1e9;
		for (int j = 0; j < 32; j++) {
			float ph = float(j) * (2.0 * PI / 32.0);
			vec3 n = cos(ph) * e1 + sin(ph) * e2;
			m = min(m, support(k, n) - dot(n, g));
		}
		best = max(best, m);
	}
	return best;
}
void basis(vec3 L, out vec3 e1, out vec3 e2) { e1 = normalize(cross(L, UP)); e2 = cross(e1, L); }
uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16; return x; }
"""

# ---------------------------------------------------------------------------- kernels

const K_DECODE := """
layout(local_size_x = 256) in;
vec4 plane(uint p, uint i) { uint b = (p * uint(NPIX) + i) * 2u; return vec4(unpackHalf2x16(raw[b]), unpackHalf2x16(raw[b + 1u])); }
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	vec4 X = plane(0u, i), Y = plane(1u, i), Z = plane(2u, i), Nn = plane(3u, i), A = plane(4u, i), D = plane(5u, i);
	float x = (X.r * 2048.0 - 1024.0) + X.g, y = (Y.r * 2048.0 - 1024.0) + Y.g, z = (Z.r * 2048.0 - 1024.0) + Z.g;
	vec3 n = Nn.rgb * 2.0 - 1.0;
	n /= max(length(n), 1e-6);
	pos[i] = vec4(x, y, z, X.b > 0.5 ? 1.0 : 0.0);
	nrm[i] = vec4(n, dot(A.rgb, LUMA));
	alb[i] = vec4(A.rgb, D.r * 2048.0 + D.g);
}
"""

# rel = log(numerator / denominator luminance): i0.x 0 img[] (sRGB), 1 raw plane 6; i0.y 0 albedo,
# 1 outp[] (sRGB), 2 raw plane 7
const K_REL := """
layout(local_size_x = 256) in;
vec4 plane(uint p, uint i) { uint b = (p * uint(NPIX) + i) * 2u; return vec4(unpackHalf2x16(raw[b]), unpackHalf2x16(raw[b + 1u])); }
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	float num = pc.i0.x == 0 ? dot(srgb_lin(unpackUnorm4x8(img[i]).rgb), LUMA) : dot(plane(6u, i).rgb, LUMA);
	float den = pc.i0.y == 0 ? nrm[i].w : (pc.i0.y == 1 ? dot(srgb_lin(unpackUnorm4x8(outp[i]).rgb), LUMA) : dot(plane(7u, i).rgb, LUMA));
	rel[i] = log(max(num, 1e-5) / max(den, 1e-4));
}
"""

# i0.x job: list A = ground pixels within r_local of the post's axis; histogram of rel over them
const K_COLLECT := """
layout(local_size_x = 256) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
	int job = pc.i0.x;
	if (i >= uint(NPIX) || !ground(i)) return;
	float dx = pos[i].x - J(job, 0), dz = pos[i].z - J(job, 1);
	if (sqrt(dx * dx + dz * dz) >= J(job, 7)) return;
	uint k = atomicAdd(lst[0], 1u);
	if (k < uint(LIST_CAP)) lst[16u + k] = i;
	int b = clamp(int(floor((rel[i] + 6.0) / 8.0 * float(HIST))), 0, HIST - 1);
	atomicAdd(acc[b], 1);
}
"""

# two-level EM (a 1-D Gaussian mixture) over the histogram, one thread
const K_LEVELS := """
layout(local_size_x = 1) in;
float bc(int b) { return -6.0 + (float(b) + 0.5) * 8.0 / float(HIST); }
void main() {
	int job = pc.i0.x;
	float n = 0.0, s1 = 0.0, s2 = 0.0;
	for (int b = 0; b < HIST; b++) { float c = float(acc[b]); n += c; s1 += c * bc(b); s2 += c * bc(b) * bc(b); }
	par[job * JOB + 18] = 0.0;
	if (n < 20.0) return;
	float mean = s1 / n, sd = sqrt(max(s2 / n - mean * mean, 0.0));
	float p10 = 0.0, p90 = 0.0, run = 0.0;
	bool g10 = false, g90 = false;
	for (int b = 0; b < HIST; b++) {
		run += float(acc[b]);
		if (!g10 && run >= 0.1 * n) { p10 = bc(b); g10 = true; }
		if (!g90 && run >= 0.9 * n) { p90 = bc(b); g90 = true; }
	}
	vec2 m = vec2(p10, p90), s = vec2(sd / 2.0 + 1e-3), w = vec2(0.5);
	for (int it = 0; it < 30; it++) {
		vec2 rn = vec2(0.0), rx = vec2(0.0), rxx = vec2(0.0);
		for (int b = 0; b < HIST; b++) {
			float c = float(acc[b]);
			if (c == 0.0) continue;
			float x = bc(b);
			vec2 p = w / s * exp(-0.5 * ((x - m) / s) * ((x - m) / s)) + 1e-12;
			vec2 r = p / (p.x + p.y);
			rn += c * r; rx += c * r * x;
		}
		vec2 mn = rx / (rn + 1e-9);
		for (int b = 0; b < HIST; b++) {
			float c = float(acc[b]);
			if (c == 0.0) continue;
			float x = bc(b);
			vec2 p = w / s * exp(-0.5 * ((x - m) / s) * ((x - m) / s)) + 1e-12;
			vec2 r = p / (p.x + p.y);
			rxx += c * r * (x - mn) * (x - mn);
		}
		m = mn;
		s = sqrt(rxx / (rn + 1e-9)) + 1e-3;
		w = rn / (rn.x + rn.y);
	}
	float lo = min(m.x, m.y), hi = max(m.x, m.y);
	par[job * JOB + 16] = lo;
	par[job * JOB + 17] = hi;
	par[job * JOB + 18] = (hi - lo >= 0.25) ? 1.0 : 0.0;
}
"""

# score per candidate angle (one workgroup each) over list A's near annulus; f0 = (first angle, step)
const K_SEARCH := """
layout(local_size_x = 256) in;
shared float red[256][8];
void main() {
	int job = pc.i0.x;
	uint ka = gl_WorkGroupID.x, lid = gl_LocalInvocationID.x;
	float a = pc.f0.x + float(ka) * pc.f0.y, c = cos(a), sn = sin(a);
	float r_lo = J(job, 5), r_hi = J(job, 6), w = J(job, 3), mid = 0.5 * (r_lo + r_hi);
	float lo = J(job, 16), hi = J(job, 17);
	float acc8[8] = float[8](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	uint n = min(lst[0], uint(LIST_CAP));
	for (uint e = lid; e < n; e += 256u) {
		uint i = lst[16u + e];
		float dx = pos[i].x - J(job, 0), dz = pos[i].z - J(job, 1);
		float r = sqrt(dx * dx + dz * dz);
		if (!(r > r_lo && r < r_hi)) continue;
		float along = dx * c + dz * sn, lat = abs(-dx * sn + dz * c);
		int h;
		if (along > r_lo && along < mid) h = 0; else if (along > mid && along < r_hi) h = 1; else continue;
		float s = clamp((hi - rel[i]) / (hi - lo), 0.0, 1.0);
		if (lat < w) { acc8[h * 2] += s; acc8[h * 2 + 1] += 1.0; }
		else if (lat > w + 0.06 && lat < w + 0.30) { acc8[4 + h * 2] += s; acc8[4 + h * 2 + 1] += 1.0; }
	}
	for (int k = 0; k < 8; k++) red[lid][k] = acc8[k];
	barrier();
	for (uint st = 128u; st > 0u; st >>= 1) {
		if (lid < st) for (int k = 0; k < 8; k++) red[lid][k] += red[lid + st][k];
		barrier();
	}
	if (lid == 0u) {
		float sc = 1e9;
		bool ok = true;
		for (int h = 0; h < 2; h++) {
			float kn = red[0][h * 2 + 1], fn = red[0][4 + h * 2 + 1];
			if (kn < 4.0 || fn < 8.0) { ok = false; break; }
			sc = min(sc, red[0][h * 2] / kn - red[0][4 + h * 2] / fn);
		}
		cst[ka] = ok ? sc : -1.0;
	}
}
"""

# first maximum over n angle scores; i0 = (job, n, out slot), f0 = (first angle, step)
const K_PICK_ANGLE := """
layout(local_size_x = 1) in;
void main() {
	int job = pc.i0.x, n = pc.i0.y, slot = pc.i0.z;
	float best = -1.0; int bk = -1;
	for (int k = 0; k < n; k++) if (cst[k] > best) { best = cst[k]; bk = k; }
	par[job * JOB + slot] = bk >= 0 ? pc.f0.x + float(bk) * pc.f0.y : 0.0;
	par[job * JOB + slot + 1] = bk >= 0 ? best : -1.0;
}
"""

# corridor along the strip: list B, and per 5 cm slice the flank shadow and centre-line sums (x65536)
const K_CORR := """
layout(local_size_x = 256) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
	int job = pc.i0.x;
	if (i >= uint(NPIX) || !ground(i)) return;
	float a = J(job, 21), c = cos(a), sn = sin(a);
	float dx = pos[i].x - J(job, 0), dz = pos[i].z - J(job, 1);
	float along = dx * c + dz * sn, lat = -dx * sn + dz * c;
	float r_lo = J(job, 5), reach = J(job, 8), half_w = J(job, 9), w = J(job, 3), rmax = J(job, 2);
	if (!(abs(lat) < half_w && along > r_lo && along < reach)) return;
	uint k = atomicAdd(lst[1], 1u);
	if (k < uint(LIST_CAP)) lst[16u + uint(LIST_CAP) + k] = i;
	int sl = int(floor((along - r_lo) / 0.05));
	if (sl < 0 || sl >= NSL) return;
	float lo = J(job, 16), hi = J(job, 17);
	float s = clamp((hi - rel[i]) / (hi - lo), 0.0, 1.0);
	int base = HIST;
	atomicAdd(acc[base + 2 * NSL + sl], 1);
	if (abs(lat) > rmax + 0.12) { atomicAdd(acc[base + sl], int(s * 65536.0)); atomicAdd(acc[base + NSL + sl], 1); }
	if (abs(lat) < w + 0.2) {
		atomicAdd(acc[base + 3 * NSL + sl], 1);
		if (abs(lat) < max(w, 0.02)) { atomicAdd(acc[base + 4 * NSL + sl], int(s * 65536.0)); atomicAdd(acc[base + 5 * NSL + sl], 1); }
		float ws = max(s - 0.15, 0.0);
		atomicAdd(acc[base + 6 * NSL + sl], int(ws * 65536.0));
		atomicAdd(acc[base + 7 * NSL + sl], int(round(ws * lat * 65536.0)));
	}
}
"""

# one thread: drop slices with another object's shadow on a flank, fit the centre line
const K_CENTRE := """
layout(local_size_x = 1) in;
void main() {
	int job = pc.i0.x;
	float r_lo = J(job, 5), reach = J(job, 8), a0 = J(job, 21);
	int nsl = min(int(ceil((reach - r_lo) / 0.05)) + 1, NSL);
	int base = HIST;
	float kept = 0.0; int dropped = 0;
	float sxy = 0.0, sxx = 0.0, sw = 0.0;
	float bx[NSL], by[NSL], bw[NSL];
	int nb = 0, miss = 0;
	for (int k = 0; k < nsl; k++) {
		float fs = float(acc[base + k]) / 65536.0, fc = float(acc[base + NSL + k]), cc = float(acc[base + 2 * NSL + k]);
		bool bad = (fc >= 3.0 && fs / max(fc, 1.0) > 0.3) || cc < 3.0;
		if (bad) { dropped++; acc[base + 8 * NSL + k] = 1; continue; }
		acc[base + 8 * NSL + k] = 0;
		kept += cc;
		float nc = float(acc[base + 3 * NSL + k]);
		if (nc < 6.0) continue;
		float cs = float(acc[base + 4 * NSL + k]) / 65536.0, cn = float(acc[base + 5 * NSL + k]);
		if (cn == 0.0 || cs / cn < 0.5) {
			miss++;
			if (miss > 6 && nb >= 3) break;
			continue;
		}
		miss = 0;
		float ws = float(acc[base + 6 * NSL + k]) / 65536.0, wl = float(acc[base + 7 * NSL + k]) / 65536.0;
		if (ws <= 0.0) continue;
		bx[nb] = r_lo + 0.05 * float(k) + 0.025; by[nb] = wl / ws; bw[nb] = nc;
		sxy += bw[nb] * bx[nb] * by[nb]; sxx += bw[nb] * bx[nb] * bx[nb]; sw += bw[nb];
		nb++;
	}
	for (int k = nsl; k < NSL; k++) acc[base + 8 * NSL + k] = 1;
	float a1 = a0, se = -1.0, len = 0.0;
	if (nb >= 3) {
		float kk = sxy / sxx;
		a1 = a0 + atan(kk);
		float rr = 0.0, mx2 = 0.0;
		for (int b = 0; b < nb; b++) { float d = by[b] - kk * bx[b]; rr += bw[b] * d * d; mx2 += bx[b] * bx[b]; len = max(len, bx[b] - 0.025 - r_lo); }
		se = sqrt(rr / sw / float(max(1, nb - 1))) / sqrt(mx2 / float(nb));
	}
	// the window ends max(1 m, 0.75 x run) past the strip's dark run, short of other shadows
	float run = r_lo + len;
	float stop = min(reach, run + max(1.0, 0.75 * run));
	kept = 0.0;
	for (int k = 0; k < nsl; k++) {
		if (r_lo + 0.05 * float(k) >= stop) acc[base + 8 * NSL + k] = 1;
		if (acc[base + 8 * NSL + k] == 0) kept += float(acc[base + 2 * NSL + k]);
	}
	par[job * JOB + 23] = a1;
	par[job * JOB + 24] = se;
	par[job * JOB + 25] = float(nb);
	par[job * JOB + 26] = kept;
	par[job * JOB + 27] = float(dropped);
	par[job * JOB + 28] = float(nsl);
	par[job * JOB + 29] = min(1.0, 20000.0 / max(kept, 1.0));
	par[job * JOB + 32] = len;
	par[job * JOB + 33] = stop;
}
"""

# kept list B pixels (hash-thinned to ~20000) -> win[3m..3m+2] = (P, s), (N, post + 32 view + 8192
# window), (view depth, its PSSM split's texel); f0 = split far distances, f1 = their texels
const K_WINDOW := """
layout(local_size_x = 256) in;
void main() {
	uint e = gl_GlobalInvocationID.x;
	int job = pc.i0.x;
	if (e >= min(lst[1], uint(LIST_CAP))) return;
	uint i = lst[16u + uint(LIST_CAP) + e];
	float a = J(job, 21), c = cos(a), sn = sin(a);
	float dx = pos[i].x - J(job, 0), dz = pos[i].z - J(job, 1);
	float along = dx * c + dz * sn;
	int sl = int(floor((along - J(job, 5)) / 0.05));
	if (sl < 0 || sl >= NSL || acc[HIST + 8 * NSL + sl] != 0) return;
	if (float(hash(i * 2654435761u + uint(pc.i0.y)) & 0xffffffu) / 16777216.0 >= J(job, 29)) return;
	uint m = atomicAdd(lst[2], 1u);
	if (m >= uint(WIN_CAP)) return;
	float lo = J(job, 16), hi = J(job, 17);
	float s = clamp((hi - rel[i]) / (hi - lo), 0.0, 1.0);
	float d = alb[i].w;
	float tx = d < pc.f0.x ? pc.f1.x : (d < pc.f0.y ? pc.f1.y : (d < pc.f0.z ? pc.f1.z : pc.f1.w));
	win[3u * m] = vec4(pos[i].xyz, s);
	win[3u * m + 1u] = vec4(nrm[i].xyz, J(job, 10) + 32.0 * J(job, 11) + 8192.0 * float(pc.i0.y));
	win[3u * m + 2u] = vec4(d, tx, 0.0, 0.0);
	wpx[m] = i;
}
"""

# cost per candidate (one workgroup each) over entries [i0.x, i0.y): a grid of i1, f2.z counts around
# f0 / f2.x with steps f1 / f2.y; f2.w bootstrap replicate over windows [i0.z, i0.w); f3.y edge units
# (0 metres, 1 texels of each pixel's PSSM split)
const K_COST := """
layout(local_size_x = 256) in;
shared float red[256];
shared float mult[128];
void main() {
	uint cand = gl_WorkGroupID.x, lid = gl_LocalInvocationID.x;
	int n_az = pc.i1.x, n_el = pc.i1.y, n_d = pc.i1.z, n_b = pc.i1.w, n_s = int(pc.f2.z + 0.5);
	uint q = cand;
	int ia = int(q % uint(n_az)); q /= uint(n_az);
	int ie = int(q % uint(n_el)); q /= uint(n_el);
	int id = int(q % uint(n_d)); q /= uint(n_d);
	int ib = int(q % uint(n_b)); q /= uint(n_b);
	int is = int(q);
	float az = pc.f0.x + (float(ia) - 0.5 * float(n_az - 1)) * pc.f1.x;
	float el = pc.f0.y + (float(ie) - 0.5 * float(n_el - 1)) * pc.f1.y;
	float dd = pc.f0.z + (float(id) - 0.5 * float(n_d - 1)) * pc.f1.z;
	float bb = pc.f0.w + (float(ib) - 0.5 * float(n_b - 1)) * pc.f1.w;
	float ss = exp(pc.f2.x + (float(is) - 0.5 * float(n_s - 1)) * pc.f2.y);
	int k0 = pc.i0.z, nk = pc.i0.w - pc.i0.z;
	if (lid < 128u) mult[lid] = 0.0;
	barrier();
	if (lid == 0u) {
		uint rep = uint(pc.f2.w + 0.5);
		if (rep == 0u) { for (int k = 0; k < nk; k++) mult[k] = 1.0; }
		else { for (int d = 0; d < nk; d++) { uint j = hash(rep * 7919u + uint(d) * 104729u + 17u) % uint(nk); mult[j] += 1.0; } }
	}
	barrier();
	vec3 L = sun_dir(az, el), e1, e2;
	basis(L, e1, e2);
	float fs = pc.f3.x, sum = 0.0;
	// bounds, par[RES + 32 ..]: el, d, b, s as (min, max)
	bool outside = el < par[RES + 32] || el > par[RES + 33] || dd < par[RES + 34] || dd > par[RES + 35]
			|| bb < par[RES + 36] || bb > par[RES + 37] || ss < par[RES + 38] || ss > par[RES + 39];
	for (int e = pc.i0.x + int(lid); e < (outside ? pc.i0.x : pc.i0.y); e += 256) {
		vec4 p = win[3 * e], nq = win[3 * e + 1];
		int code = int(nq.w + 0.5);
		int post = code % 32, wid = code / 8192;
		float wt = mult[wid - k0];
		if (wt == 0.0) continue;
		float unit = pc.f3.y > 0.5 ? win[3 * e + 2].y : 1.0;
		vec3 n = nq.xyz;
		vec3 g = p.xyz + bb * unit * (n - L * dot(n, L));
		float sp = phi((post_sd(post, g, e1, e2) + dd * unit) / ss);
		float r = (p.w - sp) / fs;
		sum += wt * (sqrt(1.0 + r * r) - 1.0);
	}
	red[lid] = sum;
	barrier();
	for (uint st = 128u; st > 0u; st >>= 1) { if (lid < st) red[lid] += red[lid + st]; barrier(); }
	if (lid == 0u) cst[cand] = outside ? 3.4e38 : red[0];
}
"""

# argmin over i0.x candidate costs -> par[RES], par[RES + 1]
const K_ARGMIN := """
layout(local_size_x = 1) in;
void main() {
	float best = 3.4e38; int bk = 0;
	for (int k = 0; k < pc.i0.x; k++) if (cst[k] < best) { best = cst[k]; bk = k; }
	par[RES] = float(bk);
	par[RES + 1] = best;
}
"""

# model tip of post i0.x for f0 = (az, el, d, b): the farthest centre-line point inside (sd > -d); in
# texels each point takes its split's (camera and splits at par[RES + 16 ..])
const K_TIP := """
layout(local_size_x = 256) in;
shared float red[256];
void main() {
	uint lid = gl_LocalInvocationID.x;
	int post = pc.i0.x;
	vec4 pt = prt[post];
	vec3 base = vec3(pc.f1.y, GROUND_Y, pc.f1.z);
	vec3 L = sun_dir(pc.f0.x, pc.f0.y), e1, e2;
	basis(L, e1, e2);
	vec3 u = normalize(vec3(-L.x, 0.0, -L.z));
	vec3 co = vec3(par[RES + 16], par[RES + 17], par[RES + 18]), cf = vec3(par[RES + 19], par[RES + 20], par[RES + 21]);
	float best = 0.0;
	int nstep = int(pc.f1.x / 0.002);
	for (int k = int(lid); k < nstep; k += 256) {
		float t = float(k) * 0.002;
		vec3 p = base + t * u;
		float unit = 1.0;
		if (pc.f1.w > 0.5) {
			float d = dot(p - co, cf);
			unit = d < par[RES + 22] ? par[RES + 26] : (d < par[RES + 23] ? par[RES + 27] : (d < par[RES + 24] ? par[RES + 28] : par[RES + 29]));
		}
		vec3 g = p + pc.f0.w * unit * (UP - L * L.y);
		if (post_sd(post, g, e1, e2) > -pc.f0.z * unit) best = max(best, t);
	}
	red[lid] = best;
	barrier();
	for (uint st = 128u; st > 0u; st >>= 1) { if (lid < st) red[lid] = max(red[lid], red[lid + st]); barrier(); }
	if (lid == 0u) par[RES + 8 + post] = red[0];
}
"""

# observed tip of window i0.x: the last 0.5 crossing of the core's shadow (2 cm bins) within 0.6 m of
# the model tip f1.x, with 10 cm of lit, visible ground beyond it
const K_OBSTIP := """
layout(local_size_x = 256) in;
shared int bs[1024];
shared int bn[1024];
void main() {
	uint lid = gl_LocalInvocationID.x;
	for (uint k = lid; k < 1024u; k += 256u) { bs[k] = 0; bn[k] = 0; }
	barrier();
	float c = cos(pc.f0.x), sn = sin(pc.f0.x), t0 = pc.f1.x - 0.6;
	for (int e = pc.i0.y + int(lid); e < pc.i0.z; e += 256) {
		vec4 p = win[3 * e];
		float dx = p.x - pc.f0.y, dz = p.z - pc.f0.z;
		float along = dx * c + dz * sn, lat = -dx * sn + dz * c;
		if (abs(lat) >= pc.f1.w) continue;
		int b = int(floor((along - t0) / 0.02));
		if (b < 0 || b >= 60) continue;
		atomicAdd(bs[b], int(p.w * 65536.0));
		atomicAdd(bn[b], 1);
	}
	barrier();
	if (lid == 0u) {
		float tip = -1.0;
		for (int b = 59; b >= 0; b--) {
			if (bn[b] == 0) continue;
			float pb = float(bs[b]) / 65536.0 / float(bn[b]);
			if (pb < 0.5) continue;
			int seen = 0; float acc2 = 0.0; int nxt = -1;
			for (int k = b + 1; k < 60 && seen < 5; k++) if (bn[k] > 0) { if (nxt < 0) nxt = k; seen++; acc2 += float(bs[k]) / 65536.0 / float(bn[k]); }
			if (seen >= 3 && nxt - b <= 2 && acc2 / float(seen) < 0.35) {
				float pn = float(bs[nxt]) / 65536.0 / float(bn[nxt]);
				float f = (pb - 0.5) / max(pb - pn, 1e-6);
				tip = t0 + 0.02 * float(b) + 0.01 + f * 0.02 * float(nxt - b);
			}
			break;
		}
		par[RES + 40 + pc.i0.x] = tip;
	}
}
"""

# ---------------------------------------------------------------------------- toon bands
# post-surface pixels away from depth edges, not grazing, lit in the port's mask: win[TB + e] =
# (N, log luminance), wpx[TK + e] = post * 512 + albedo bin; key counts at acc[KEYS + key]
const K_TB_COLLECT := """
layout(local_size_x = 256) in;
vec4 plane(uint p, uint i) { uint b = (p * uint(NPIX) + i) * 2u; return vec4(unpackHalf2x16(raw[b]), unpackHalf2x16(raw[b + 1u])); }
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	vec4 p = pos[i];
	if (p.w < 0.5 || ground(i)) return;
	int post = -1;
	for (int k = 0; k < pc.i0.z; k++) {
		vec4 t = prt[k];
		vec4 c = prt[PARTS_OFF + 4 * int(t.x + 0.5) + 1];
		float r = length(p.xz - c.xz);
		if (r < t.z + 0.015 && p.y > 0.06 && p.y < t.w + 0.02) { post = k; break; }
	}
	if (post < 0) return;
	int x = int(i) % W, y = int(i) / W;
	float d0 = alb[i].w;
	for (int dy = -2; dy <= 2; dy++) for (int dx = -2; dx <= 2; dx++) {
		int xx = clamp(x + dx, 0, W - 1), yy = clamp(y + dy, 0, H - 1);
		uint j = uint(yy * W + xx);
		if (pos[j].w < 0.5 || abs(alb[j].w - d0) > 0.015 * d0) return;
	}
	vec3 n = nrm[i].xyz;
	if (dot(n, normalize(pc.f0.xyz - p.xyz)) < 0.3) return;
	if (pc.i0.y == 1) {
		vec3 ss = plane(6u, i).rgb, sn = plane(7u, i).rgb;
		if (sn.g > 0.004) {
			float lit = clamp(((ss.r / sn.r - 0.477) / 0.523 + (ss.g / sn.g - 0.420) / 0.580) * 0.5, 0.0, 1.0);
			if (lit < 0.9) return;
		}
	}
	vec3 a = pow(clamp(alb[i].rgb, 0.0, 1.0), vec3(1.0 / 2.2));
	ivec3 q = min(ivec3(a * 8.0), ivec3(7));
	int key = post * 512 + q.r + 8 * q.g + 64 * q.b;
	float I = log(max(dot(srgb_lin(unpackUnorm4x8(img[i]).rgb), LUMA), 1e-5));
	uint e = atomicAdd(lst[3], 1u);
	if (e >= uint(WIN_CAP / 2)) return;
	win[uint(TB) + e] = vec4(n, I);
	wpx[uint(TK) + e] = uint(key);
	atomicAdd(acc[KEYS + key], 1);
}
"""

# keys with at least i0.x pixels become regions 0.. (at most 128): acc[REGION + key] = region or -1
const K_TB_REGIONS := """
layout(local_size_x = 1) in;
void main() {
	int nr = 0;
	for (int k = 0; k < 16384; k++) {
		if (acc[KEYS + k] >= pc.i0.x && nr < 128) { acc[REGION + k] = nr; nr++; }
		else acc[REGION + k] = -1;
	}
	par[RES + 4] = float(nr);
}
"""

# per candidate, each region's sum of squares about its band model less a constant: f3.x 0 one level
# per band (edges f2.xyz on N.L), 1 a ramp a + c clamp(N.L / f2.y, 0, 1); f2.w bootstrap replicate
const K_TB_COST := """
layout(local_size_x = 256) in;
shared int s1[128 * 4];
shared int sn[128 * 4];
shared int r1[128 * 4];
shared float red[256];
shared float mult[128];
void main() {
	uint cand = gl_WorkGroupID.x, lid = gl_LocalInvocationID.x;
	int n_az = pc.i1.x, n_el = pc.i1.y;
	int ia = int(cand % uint(n_az)), ie = int(cand / uint(n_az));
	float az = pc.f0.x + (float(ia) - 0.5 * float(n_az - 1)) * pc.f1.x;
	float el = pc.f0.y + (float(ie) - 0.5 * float(n_el - 1)) * pc.f1.y;
	vec3 L = sun_dir(az, el);
	for (uint k = lid; k < 512u; k += 256u) { s1[k] = 0; sn[k] = 0; r1[k] = 0; }
	int nr = int(par[RES + 4] + 0.5);
	if (lid < 128u) mult[lid] = 0.0;
	barrier();
	if (lid == 0u) {
		uint rep = uint(pc.f2.w + 0.5);
		if (rep == 0u) { for (int k = 0; k < nr; k++) mult[k] = 1.0; }
		else { for (int d = 0; d < nr; d++) { uint j = hash(rep * 7919u + uint(d) * 104729u + 31u) % uint(nr); mult[j] += 1.0; } }
	}
	barrier();
	for (int e = pc.i0.x + int(lid); e < pc.i0.y; e += 256) {
		vec4 en = win[TB + e];
		int r = acc[REGION + int(wpx[TK + e])];
		if (r < 0) continue;
		float nl = dot(en.xyz, L);
		if (pc.f3.x < 0.5) {
			int b = nl < pc.f2.x ? 0 : (nl < pc.f2.y ? 1 : (nl < pc.f2.z ? 2 : 3));
			atomicAdd(s1[r * 4 + b], int(round(en.w * 1024.0)));
			atomicAdd(sn[r * 4 + b], 1);
		} else {
			float t = clamp(nl / pc.f2.y, 0.0, 1.0);
			atomicAdd(sn[r * 4], 1);
			atomicAdd(sn[r * 4 + 1], int(round(t * 4096.0)));
			atomicAdd(sn[r * 4 + 2], int(round(t * t * 4096.0)));
			atomicAdd(s1[r * 4], int(round(en.w * 1024.0)));
			atomicAdd(s1[r * 4 + 1], int(round(t * en.w * 1024.0)));
		}
	}
	barrier();
	float acc1 = 0.0;
	if (pc.f3.x < 0.5) {
		for (int k = int(lid); k < nr * 4; k += 256) {
			float c = float(sn[k]);
			if (c > 0.0) { float t = float(s1[k]) / 1024.0; acc1 += mult[k / 4] * t * t / c; }
		}
	} else {
		for (int r = int(lid); r < nr; r += 256) {
			float n0 = float(sn[r * 4]), st = float(sn[r * 4 + 1]) / 4096.0, stt = float(sn[r * 4 + 2]) / 4096.0;
			float y0 = float(s1[r * 4]) / 1024.0, y1 = float(s1[r * 4 + 1]) / 1024.0;
			float det = n0 * stt - st * st;
			if (n0 < 2.0) continue;
			if (det < 1e-3 * n0 * n0) { acc1 += mult[r] * y0 * y0 / n0; continue; }  // one level: no ramp in view
			acc1 += mult[r] * (stt * y0 * y0 - 2.0 * st * y0 * y1 + n0 * y1 * y1) / det;
		}
	}
	red[lid] = acc1;
	barrier();
	for (uint st = 128u; st > 0u; st >>= 1) { if (lid < st) red[lid] += red[lid + st]; barrier(); }
	if (lid == 0u) cst[cand] = -red[0];
}
"""

# ---------------------------------------------------------------------------- contact sheet
# msk[i] bytes: the oracle's and the port's shadow fraction, then their model shadows

# the rel field's paving pixels as a shadow fraction into msk byte i0.x, levels from job i0.y
const K_MASKW := """
layout(local_size_x = 256) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	uint sh = uint(pc.i0.x) * 8u;
	uint v = 0u;
	if (ground(i)) {
		float lo = J(pc.i0.y, 16), hi = J(pc.i0.y, 17);
		v = uint(clamp((hi - rel[i]) / (hi - lo), 0.0, 1.0) * 255.0 + 0.5);
	}
	msk[i] = (msk[i] & ~(0xffu << sh)) | (v << sh);
}
"""

# a model's shadow near the listed posts (par[RES + 64 ..]) into msk byte i0.x
const K_MASKM := """
layout(local_size_x = 256) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	uint sh = uint(pc.i0.x) * 8u;
	uint v = 0u;
	if (ground(i)) {
		vec3 L = sun_dir(pc.f0.x, pc.f0.y), e1, e2;
		basis(L, e1, e2);
		float unit = 1.0;
		if (pc.f1.y > 0.5) { float d = alb[i].w; unit = d < pc.f2.x ? pc.f3.x : (d < pc.f2.y ? pc.f3.y : (d < pc.f2.z ? pc.f3.z : pc.f3.w)); }
		vec3 n = nrm[i].xyz;
		vec3 g = pos[i].xyz + pc.f0.w * unit * (n - L * dot(n, L));
		float best = 0.0;
		for (int k = 0; k < pc.i0.y; k++) {
			int post = int(par[RES + 64 + k] + 0.5);
			vec4 t = prt[post];
			vec4 c = prt[PARTS_OFF + 4 * int(t.x + 0.5) + 1];
			if (length(pos[i].xz - c.xz) > t.w / max(0.05, tan(radians(pc.f0.y))) + t.z + 0.6) continue;
			best = max(best, phi((post_sd(post, g, e1, e2) + pc.f0.z * unit) / pc.f1.x));
		}
		v = uint(best * 255.0 + 0.5);
	}
	msk[i] = (msk[i] & ~(0xffu << sh)) | (v << sh);
}
"""

# the sheet body: oracle | port with markers, the masks, and a crop; markers at par[RES + 128 ..]:
# kind, panel, x0, y0, x1 (or radius), y1, r + 256 g + 65536 b, width
const K_SHEET := """
layout(local_size_x = 256) in;
vec3 px8(uint w) { return unpackUnorm4x8(w).rgb; }
vec3 sample_half(bool port, int x, int y) {
	vec3 a = vec3(0.0);
	for (int dy = 0; dy < 2; dy++) for (int dx = 0; dx < 2; dx++) {
		uint j = uint(clamp(2 * y + dy, 0, H - 1) * W + clamp(2 * x + dx, 0, W - 1));
		a += port ? px8(outp[j]) : px8(img[j]);
	}
	return a * 0.25;
}
vec3 overlay(uint j, vec3 base) {
	vec4 m = unpackUnorm4x8(msk[j]);
	bool so = m.x > 0.5, sp = m.y > 0.5;
	vec3 c = base * 0.35;
	if (so && sp) c = vec3(0.93);
	else if (so) c = vec3(1.0, 0.16, 0.16);
	else if (sp) c = vec3(0.16, 0.9, 1.0);
	return c;
}
bool contour(uint j, int byte_ix) {
	int x = int(j) % W, y = int(j) / W;
	float c = unpackUnorm4x8(msk[j])[byte_ix];
	bool inside = c > 0.5;
	for (int k = 0; k < 4; k++) {
		int xx = clamp(x + (k == 0 ? 1 : (k == 1 ? -1 : 0)), 0, W - 1), yy = clamp(y + (k == 2 ? 1 : (k == 3 ? -1 : 0)), 0, H - 1);
		if ((unpackUnorm4x8(msk[uint(yy * W + xx)])[byte_ix] > 0.5) != inside) return true;
	}
	return false;
}
vec4 markers(int panel, float sx, float sy, float scale) {
	vec4 o = vec4(0.0);
	for (int k = 0; k < pc.i0.x; k++) {
		int b = RES + 128 + 8 * k;
		int kind = int(par[b] + 0.5), pnl = int(par[b + 1] + 0.5);
		if (panel >= 0 && pnl != 2 && pnl != panel) continue;
		vec2 p = vec2(sx, sy), a = vec2(par[b + 2], par[b + 3]);
		float w = par[b + 7] * scale, d;
		if (kind == 0) {
			vec2 e = vec2(par[b + 4], par[b + 5]);
			vec2 ab = e - a;
			float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
			d = length(p - (a + t * ab));
		} else if (kind == 1) {
			d = abs(length(p - a) - par[b + 4]);
		} else {
			vec2 q = abs(p - a);
			d = max(q.x, q.y) > par[b + 4] ? 1e9 : min(q.x, q.y);
		}
		uint rgb = uint(par[b + 6]);  // an exact integer below 2^24: no rounding offset
		if (d < 0.5 * w + 0.5 * scale) o = vec4(vec3(rgb & 255u, (rgb >> 8) & 255u, (rgb >> 16) & 255u) / 255.0, 1.0);
	}
	return o;
}
void main() {
	uint t = gl_GlobalInvocationID.x;
	if (t >= uint(1920 * 1080)) return;
	int x = int(t) % 1920, y = int(t) / 1920;
	vec3 c;
	if (y < 540) {
		bool port = x >= 960;
		int hx = port ? x - 960 : x;
		c = sample_half(port, hx, y);
		uint j = uint(clamp(2 * y, 0, H - 1) * W + clamp(2 * hx, 0, W - 1));
		if (contour(j, port ? 3 : 2)) c = vec3(1.0, 0.85, 0.1);
		vec4 m = markers(port ? 1 : 0, 2.0 * float(hx) + 0.5, 2.0 * float(y) + 0.5, 2.0);
		c = mix(c, m.rgb, m.a);
	} else if (x < 960) {
		int hy = y - 540;
		uint j = uint(clamp(2 * hy, 0, H - 1) * W + clamp(2 * x, 0, W - 1));
		c = overlay(j, sample_half(false, x, hy));
	} else {
		float sc = pc.f0.x;
		float sx = float(pc.i0.y) + (float(x - 960) + 0.5) * sc, sy = float(pc.i0.z) + (float(y - 540) + 0.5) * sc;
		uint j = uint(clamp(int(sy), 0, H - 1) * W + clamp(int(sx), 0, W - 1));
		c = overlay(j, px8(img[j]));
		if (contour(j, 2)) c = vec3(1.0, 0.55, 0.0);
		if (contour(j, 3)) c = vec3(0.2, 0.4, 1.0);
		vec4 m = markers(-1, sx, sy, sc);
		c = mix(c, m.rgb, m.a);
	}
	shout[t] = packUnorm4x8(vec4(c, 1.0));
}
"""

# |original depth - port depth| (sun_cams.mjs geo_<i>.f32 in raw[]) into a log histogram acc[0..256)
const K_DEPTHCMP := """
layout(local_size_x = 256) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(NPIX)) return;
	int x = int(i) % W, y = int(i) / W;
	uint j = uint((H - 1 - y) * W + x) * 4u + 3u;
	float od = uintBitsToFloat(raw[j]), pd = alb[i].w;
	if (!(od > 0.0) || pos[i].w < 0.5) return;
	float d = abs(pd - od);
	int b = clamp(int(floor((log(max(d, 1e-6)) / log(10.0) + 6.0) / 7.0 * 256.0)), 0, 255);
	atomicAdd(acc[b], 1);
}
"""

# sum over pixels of |img - outp| in RGB (8-bit codes) into acc[0], acc[1] (low, high 16 bits a pixel each)
const K_MAD := """
layout(local_size_x = 256) in;
shared uint red[256];
void main() {
	uint i = gl_GlobalInvocationID.x, lid = gl_LocalInvocationID.x;
	uint v = 0u;
	if (i < uint(NPIX)) {
		uvec4 a = uvec4(unpackUnorm4x8(img[i]) * 255.0 + 0.5), b = uvec4(unpackUnorm4x8(outp[i]) * 255.0 + 0.5);
		v = uint(abs(int(a.r) - int(b.r)) + abs(int(a.g) - int(b.g)) + abs(int(a.b) - int(b.b)));
	}
	red[lid] = v;
	barrier();
	for (uint st = 128u; st > 0u; st >>= 1) { if (lid < st) red[lid] += red[lid + st]; barrier(); }
	if (lid == 0u) atomicAdd(acc[(gl_WorkGroupID.x & 1u)], int(red[0]));
}
"""

var rd: RenderingDevice
var shaders := {}
var pipes := {}
var bufs := {}
var _sets := {}
var posts: Array = []    # [{name, kind, x, z, top, r_shaft, r_max, prims: [[type, ...]]}]
var ok := true
var edge_units := 0.0     # 0: edge model in metres; 1: in texels of each pixel's PSSM split
var split_far := [1e9, 1e9, 1e9, 1e9]
var split_texel := [1.0, 1.0, 1.0, 1.0]


func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()
	assert(rd != null, "sun_locate: no RenderingDevice (run with a GPU driver, not --headless)")
	var hdr := HEADER % [NPIX, W, H, HIST, NSL, JOB, RES, PARTS_OFF, LIST_CAP, WIN_CAP, TB, TK, KEYS, REGION]
	var kernels := {"decode": K_DECODE, "rel": K_REL, "collect": K_COLLECT, "levels": K_LEVELS, "search": K_SEARCH,
			"pick_angle": K_PICK_ANGLE, "corr": K_CORR, "centre": K_CENTRE, "window": K_WINDOW, "cost": K_COST,
			"argmin": K_ARGMIN, "tip": K_TIP, "obstip": K_OBSTIP, "tb_collect": K_TB_COLLECT, "tb_regions": K_TB_REGIONS,
			"tb_cost": K_TB_COST, "maskw": K_MASKW, "maskm": K_MASKM, "sheet": K_SHEET, "depthcmp": K_DEPTHCMP, "mad": K_MAD}
	for k in kernels:
		var src := RDShaderSource.new()
		src.source_compute = hdr + kernels[k]
		var spirv := rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("sun_locate: kernel %s: %s" % [k, spirv.compile_error_compute])
			ok = false
			continue
		shaders[k] = rd.shader_create_from_spirv(spirv)
		pipes[k] = rd.compute_pipeline_create(shaders[k])
	var sizes := {"pos": NPIX * 16, "nrm": NPIX * 16, "alb": NPIX * 16, "rel": NPIX * 4, "par": (RES + 8192) * 4,
			"lst": (16 + 2 * LIST_CAP) * 4, "acc": 65536 * 4, "win": WIN_CAP * 48, "prt": 4096 * 16,
			"cst": 65536 * 4, "raw": 8 * NPIX * 8, "img": NPIX * 4, "outp": NPIX * 4, "wpx": WIN_CAP * 4, "msk": NPIX * 4,
			"shout": 1920 * 1080 * 4}
	for k in sizes:
		var b := PackedByteArray()
		b.resize(sizes[k])
		bufs[k] = rd.storage_buffer_create(sizes[k], b)


func release() -> void:
	for k in _sets:
		if rd.uniform_set_is_valid(_sets[k]):
			rd.free_rid(_sets[k])
	for k in pipes:
		rd.free_rid(pipes[k])
	for k in shaders:
		rd.free_rid(shaders[k])
	for k in bufs:
		rd.free_rid(bufs[k])
	rd.free()


func _uset(kernel: String) -> RID:
	if not _sets.has(kernel):
		var us := []
		var names := ["pos", "nrm", "alb", "rel", "par", "lst", "acc", "win", "prt", "cst", "raw", "img", "outp", "wpx", "msk", "shout"]
		for b in names.size():
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding = b
			u.add_id(bufs[names[b]])
			us.append(u)
		_sets[kernel] = rd.uniform_set_create(us, shaders[kernel], 0)
	return _sets[kernel]


## One dispatch, synchronous. pc: [i0 (4 ints), i1 (4 ints), f0..f3 (16 floats)].
func run(kernel: String, groups: int, i0 := [0, 0, 0, 0], i1 := [0, 0, 0, 0], f := []) -> void:
	var ii := PackedInt32Array(i0)
	ii.resize(4)
	var jj := PackedInt32Array(i1)
	jj.resize(4)
	ii.append_array(jj)
	var pcb := ii.to_byte_array()
	var ff := PackedFloat32Array(f)
	ff.resize(16)
	pcb.append_array(ff.to_byte_array())
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipes[kernel])
	rd.compute_list_bind_uniform_set(list, _uset(kernel), 0)
	rd.compute_list_set_push_constant(list, pcb, pcb.size())
	rd.compute_list_dispatch(list, groups, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()


func floats(buf: String, offset: int, count: int) -> PackedFloat32Array:
	return rd.buffer_get_data(bufs[buf], offset * 4, count * 4).to_float32_array()


func uints(buf: String, offset: int, count: int) -> PackedInt32Array:
	return rd.buffer_get_data(bufs[buf], offset * 4, count * 4).to_int32_array()


func put_floats(buf: String, offset: int, values: PackedFloat32Array) -> void:
	var b := values.to_byte_array()
	rd.buffer_update(bufs[buf], offset * 4, b.size(), b)


func clear(buf: String, offset_bytes := 0, size_bytes := -1) -> void:
	if size_bytes < 0:
		size_bytes = {"lst": (16 + 2 * LIST_CAP) * 4, "acc": 65536 * 4, "cst": 65536 * 4}[buf] - offset_bytes
	rd.buffer_clear(bufs[buf], offset_bytes, size_bytes)


# ---------------------------------------------------------------------------- loading

## The port's .f16 passes at view i into raw planes 0..5 (and the sun-alone ones into 6, 7), decoded.
func load_view(dir: String, i: int, sun_passes := false) -> void:
	var names := ["posx", "posy", "posz", "normal", "albedo", "dist"]
	if sun_passes:
		names += ["sun_shadow", "sun_noshadow"]
	for p in names.size():
		var bytes := FileAccess.get_file_as_bytes(dir.path_join("%s_%d.f16" % [names[p], i]))
		var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBH, bytes)
		img.convert(Image.FORMAT_RGBAH)
		var d := img.get_data()
		rd.buffer_update(bufs.raw, p * NPIX * 8, d.size(), d)
	run("decode", (NPIX + 255) / 256)


## An sRGB PNG into img[] (numerator) or outp[] (denominator).
func load_png(path: String, into := "img") -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.get_width() != W or img.get_height() != H:
		return false
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	rd.buffer_update(bufs[into], 0, d.size(), d)
	return true


func make_rel(num: int, den: int) -> void:
	run("rel", (NPIX + 255) / 256, [num, den, 0, 0])


# ---------------------------------------------------------------------------- posts

## Posts as convex primitives into prt[]: a table, then 4 vec4 per primitive from PARTS_OFF.
func set_posts(defs: Array) -> void:
	posts = defs
	var table := PackedFloat32Array()
	var prims := PackedFloat32Array()
	var k := 0
	for p in defs:
		table.append_array([k, p.prims.size(), p.r_max, p.top])
		for q in p.prims:
			prims.append_array(_prim(q, p.x, p.z))
			k += 1
	table.resize(PARTS_OFF * 4)
	put_floats("prt", 0, table)
	put_floats("prt", PARTS_OFF * 4, prims)


static func _prim(q: Array, x: float, z: float) -> PackedFloat32Array:
	match q[0]:
		"vcyl":  # [vcyl, r_top, r_bot, y0, y1]
			return PackedFloat32Array([0, q[2], q[1], 0, x, q[3], z, q[4], 0, 0, 0, 0, 0, 0, 0, 0])
		"ell":  # [ell, r, [cx, cy, cz], sy, upper]
			return PackedFloat32Array([1, q[1], q[3], 1.0 if q[4] else 0.0, x + q[2][0], q[2][1], z + q[2][2], 0, 0, 0, 0, 0, 0, 0, 0, 0])
		"box":  # [box, [w, h, d], [cx, cy, cz], rot_y]
			return PackedFloat32Array([2, q[1][0] / 2.0, q[1][1] / 2.0, q[1][2] / 2.0, x + q[2][0], q[2][1], z + q[2][2], 0,
					cos(q[3]), sin(q[3]), 0, 0, 0, 0, 0, 0])
		"disc":  # [disc, r, thickness, [cx, cy, cz], [ax, ay, az]]
			return PackedFloat32Array([3, q[1], q[2], 0, x + q[3][0], q[3][1], z + q[3][2], 0, q[4][0], q[4][1], q[4][2], 0, 0, 0, 0, 0])
	return PackedFloat32Array()


# ---------------------------------------------------------------------------- per post

## Post k's strip in the current rel field, or {} when it casts none; window_id >= 0 adds its window.
func measure(job: int, k: int, view: int, window_id: int) -> Dictionary:
	var p: Dictionary = posts[k]
	var r_lo: float = p.r_max + 0.12
	var r_hi: float = r_lo + maxf(0.4, minf(1.0, 0.5 * p.top))
	var reach := minf(p.top / tan(deg_to_rad(10.0)), 25.0)
	var rec := PackedFloat32Array()
	rec.resize(JOB)
	rec[0] = p.x; rec[1] = p.z; rec[2] = p.r_max; rec[3] = p.r_shaft; rec[4] = p.top; rec[5] = r_lo
	rec[6] = r_hi; rec[7] = r_lo + 2.5; rec[8] = reach; rec[9] = p.r_max + 0.35; rec[10] = k; rec[11] = view
	put_floats("par", job * JOB, rec)
	rd.buffer_clear(bufs.lst, 0, 8)  # list A and B counts; lst[2] counts the engine's window entries
	clear("acc")
	run("collect", (NPIX + 255) / 256, [job, 0, 0, 0])
	run("levels", 1, [job, 0, 0, 0])
	var lv := floats("par", job * JOB + 16, 3)
	if lv[2] < 0.5:
		return {}
	run("search", 360, [job, 360, 0, 0], [], [0.0, deg_to_rad(1.0)])
	run("pick_angle", 1, [job, 360, 19, 0], [], [0.0, deg_to_rad(1.0)])
	var co := floats("par", job * JOB + 19, 2)
	if co[1] < 0.3:
		return {}
	var start: float = co[0] - deg_to_rad(1.5)
	run("search", 61, [job, 61, 0, 0], [], [start, deg_to_rad(0.05)])
	run("pick_angle", 1, [job, 61, 21, 0], [], [start, deg_to_rad(0.05)])
	rd.buffer_clear(bufs.lst, 4, 4)
	clear("acc", HIST * 4)
	run("corr", (NPIX + 255) / 256, [job, 0, 0, 0])
	run("centre", 1, [job, 0, 0, 0])
	var r := floats("par", job * JOB, JOB)
	var out := {"post": p.name, "kind": p.kind, "view": view, "post_index": k, "job": job,
		"levels_log": [r[16], r[17]], "score": r[22], "dir_search_rad": r[21], "dir_rad": r[23],
		"dir_se_rad": r[24] if r[24] >= 0.0 else null, "centre_bins": int(r[25]), "window_px": int(r[26]),
		"slices_dropped": int(r[27]), "slices": int(r[28]), "shaft_strip_m": r[32], "r_lo": r_lo, "reach": reach, "window_end_m": r[33]}
	if window_id >= 0:
		var before := uints("lst", 2, 1)[0]
		run("window", (LIST_CAP + 255) / 256, [job, window_id, 0, 0], [], split_far + split_texel)
		var after := uints("lst", 2, 1)[0]
		out["win"] = [before, mini(after, WIN_CAP)]
	return out


# ---------------------------------------------------------------------------- the fit

## The best of a grid of candidates over entries [e0, e1), and which parameters sat on its edge.
## Physical bounds: elevation 10..70 deg, and the edge model within what a shadow map does.
func set_bounds() -> void:
	var b := [10.0, 70.0, -0.05, 0.08, -0.05, 0.15, 0.0005, 0.08]
	if edge_units > 0.5:
		b = [10.0, 70.0, -2.0, 3.0, -1.0, 6.0, 0.0005, 0.08]
	put_floats("par", RES + 32, PackedFloat32Array(b))


func grid(e0: int, e1: int, k0: int, k1: int, g: Dictionary, rep := 0, fs := 0.2) -> Dictionary:
	var n: int = g.n_az * g.n_el * g.n_d * g.n_b * g.n_s
	run("cost", n, [e0, e1, k0, k1], [g.n_az, g.n_el, g.n_d, g.n_b],
			[g.az, g.el, g.d, g.b, g.st_az, g.st_el, g.st_d, g.st_b, g.ls, g.st_ls, float(g.n_s), float(rep), fs, edge_units, 0, 0])
	run("argmin", 1, [n, 0, 0, 0])
	var r := floats("par", RES, 2)
	var q := int(r[0])
	var idx := []
	for c in [g.n_az, g.n_el, g.n_d, g.n_b, g.n_s]:
		idx.append(q % c)
		q /= c
	var out := {"cost": r[1], "edge": {}}
	var keys := ["az", "el", "d", "b", "ls"]
	var counts := [g.n_az, g.n_el, g.n_d, g.n_b, g.n_s]
	for j in 5:
		out[keys[j]] = g[keys[j]] + (idx[j] - 0.5 * (counts[j] - 1)) * g["st_" + keys[j]]
		out.edge[keys[j]] = counts[j] > 1 and (idx[j] == 0 or idx[j] == counts[j] - 1)
	return out


## The sun (and, unless nuis is given, the edge model), coarse to fine; elevation and the normal-bias
## shift b are searched as a pair, since a shorter shadow is either.
func fit(e0: int, e1: int, k0: int, k1: int, start: Dictionary, nuis = null, rep := 0, rounds := 12, free_b := false) -> Dictionary:
	var cur := {"az": start.az, "el": start.el, "d": start.get("d", 0.0), "b": start.get("b", 0.0),
		"ls": start.get("ls", log(0.03)), "cost": 0.0}
	if nuis != null:
		cur.d = nuis.d
		cur.b = nuis.b
		cur.ls = nuis.ls
	var st := {"az": 0.5, "el": 1.0, "d": 0.01, "b": 0.02, "ls": 0.35}
	if edge_units > 0.5:
		st.d = 0.5
		st.b = 1.0
	var with_b := nuis == null or free_b
	for r in rounds:
		var g := {"az": cur.az, "el": cur.el, "d": cur.d, "b": cur.b, "ls": cur.ls, "n_az": 7, "n_el": 9, "n_d": 1,
			"n_b": 9 if with_b else 1, "n_s": 1, "st_az": st.az, "st_el": st.el, "st_d": 0.0, "st_b": st.b if with_b else 0.0, "st_ls": 0.0}
		var best := grid(e0, e1, k0, k1, g, rep)
		cur.az = best.az
		cur.el = best.el
		cur.b = best.b
		cur.cost = best.cost
		var shrink := {}
		for k in ["az", "el"]:
			shrink[k] = not best.edge[k]
		shrink.b = with_b and not best.edge.b
		if nuis == null:
			g = {"az": cur.az, "el": cur.el, "d": cur.d, "b": cur.b, "ls": cur.ls, "n_az": 1, "n_el": 1, "n_d": 7, "n_b": 7,
				"n_s": 5, "st_az": 0.0, "st_el": 0.0, "st_d": st.d, "st_b": st.b, "st_ls": st.ls}
			best = grid(e0, e1, k0, k1, g, rep)
			cur.d = best.d
			cur.b = best.b
			cur.ls = best.ls
			cur.cost = best.cost
			shrink.d = not best.edge.d
			shrink.b = shrink.b and not best.edge.b
			shrink.ls = not best.edge.ls
		for k in shrink:
			if shrink[k]:
				st[k] *= 0.5
	cur["steps"] = st
	return cur


## The cost's curvature in (az, el) by central differences.
func curvature(e0: int, e1: int, k0: int, k1: int, cur: Dictionary, h_az: float, h_el: float) -> Dictionary:
	var g := {"az": cur.az, "el": cur.el, "d": cur.d, "b": cur.b, "ls": cur.ls, "n_az": 3, "n_el": 3, "n_d": 1, "n_b": 1,
		"n_s": 1, "st_az": h_az, "st_el": h_el, "st_d": 0.0, "st_b": 0.0, "st_ls": 0.0}
	run("cost", 9, [e0, e1, k0, k1], [3, 3, 1, 1],
			[g.az, g.el, g.d, g.b, g.st_az, g.st_el, 0.0, 0.0, g.ls, 0.0, 1.0, 0.0, 0.2, edge_units, 0, 0])
	var c := floats("cst", 0, 9)  # index = ia + 3 * ie
	var faa: float = (c[2 + 3] - 2.0 * c[1 + 3] + c[0 + 3]) / (h_az * h_az)
	var fee: float = (c[1 + 6] - 2.0 * c[1 + 3] + c[1 + 0]) / (h_el * h_el)
	var fae: float = (c[2 + 6] - c[0 + 6] - c[2 + 0] + c[0 + 0]) / (4.0 * h_az * h_el)
	return {"faa": faa, "fee": fee, "fae": fae, "c0": c[4]}


## The camera a view's tips are measured from (origin and forward), for edge models in texels.
func set_tip_camera(origin: Vector3, forward: Vector3) -> void:
	put_floats("par", RES + 16, PackedFloat32Array([origin.x, origin.y, origin.z, forward.x, forward.y, forward.z] + split_far + split_texel))


## The cost's Hessian in (az, el, b) by central differences, for errors with b profiled out.
func curvature3(e0: int, e1: int, k0: int, k1: int, cur: Dictionary, h: Array) -> Dictionary:
	run("cost", 27, [e0, e1, k0, k1], [3, 3, 1, 3],
			[cur.az, cur.el, cur.d, cur.b, h[0], h[1], 0.0, h[2], cur.ls, 0.0, 1.0, 0.0, 0.2, edge_units, 0, 0])
	var c := floats("cst", 0, 27)  # index = ia + 3 ie + 9 ib
	var at := func(i: int, j: int, k: int) -> float: return c[(i + 1) + 3 * (j + 1) + 9 * (k + 1)]
	var H := []
	var idx := [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
	for p in 3:
		var row := []
		for q in 3:
			var u: Array = idx[p]
			var w: Array = idx[q]
			var v: float
			if p == q:
				v = (at.call(u[0], u[1], u[2]) - 2.0 * at.call(0, 0, 0) + at.call(-u[0], -u[1], -u[2])) / (h[p] * h[p])
			else:
				v = (at.call(u[0] + w[0], u[1] + w[1], u[2] + w[2]) - at.call(u[0] - w[0], u[1] - w[1], u[2] - w[2])
						- at.call(-u[0] + w[0], -u[1] + w[1], -u[2] + w[2]) + at.call(-u[0] - w[0], -u[1] - w[1], -u[2] - w[2])) / (4.0 * h[p] * h[q])
			row.append(v)
		H.append(row)
	return {"H": H, "c0": at.call(0, 0, 0)}


func tip(post_index: int, az: float, el: float, d: float, b: float, reach: float) -> float:
	var p: Dictionary = posts[post_index]
	run("tip", 1, [post_index, 0, 0, 0], [], [az, el, d, b, reach, p.x, p.z, edge_units])
	return floats("par", RES + 8 + post_index, 1)[0]


func obs_tip(window_id: int, e0: int, e1: int, dir_rad: float, post_index: int, model_tip: float, core: float) -> float:
	var p: Dictionary = posts[post_index]
	run("obstip", 1, [window_id, e0, e1, 0], [], [dir_rad, p.x, p.z, 0.0, model_tip, 0.0, 0.0, core])
	return floats("par", RES + 40 + window_id, 1)[0]


## Godot's PSSM split far distances and texels for a camera (renderer_scene_cull.cpp's bounding radius).
static func godot_splits(yfov_deg: float, aspect: float, near: float, max_distance: float, offsets: Array, atlas: int) -> Dictionary:
	var dist := [near]
	for o in offsets:
		dist.append(near + o * (max_distance - near))
	dist.append(max_distance)
	var side := atlas / 2.0
	var far := []
	var texel := []
	var t := tan(deg_to_rad(yfov_deg) / 2.0)
	for i in 4:
		var n: float = dist[i]
		var f: float = dist[i + 1]
		var c := Vector3(0, 0, -(n + f) / 2.0)
		var r := 0.0
		for z in [n, f]:
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					r = maxf(r, c.distance_to(Vector3(sx * z * t * aspect, sy * z * t, -z)))
		r *= side / (side - 2.0)
		far.append(f)
		texel.append(2.0 * r / side)
	return {"far": far, "texel": texel}


# ---------------------------------------------------------------------------- toon bands

## Starts a toon-band collection (entries and key counts cleared).
func tb_begin() -> void:
	rd.buffer_clear(bufs.lst, 12, 4)
	rd.buffer_clear(bufs.acc, KEYS * 4, 16384 * 4)


## Collects the current view's post-surface pixels of the image in img[]; returns the entry range.
func tb_collect(view_origin: Vector3, use_mask: bool) -> Array:
	var before := uints("lst", 3, 1)[0]
	run("tb_collect", (NPIX + 255) / 256, [0, 1 if use_mask else 0, posts.size(), 0], [], [view_origin.x, view_origin.y, view_origin.z, 0.0])
	return [before, mini(uints("lst", 3, 1)[0], WIN_CAP / 2)]


func tb_regions(min_px: int) -> int:
	run("tb_regions", 1, [min_px, 0, 0, 0])
	return int(floats("par", RES + 4, 1)[0])


## Best (az, el) of a band model over entries [e0, e1), coarse to fine from a wide grid.
func tb_fit(e0: int, e1: int, edges: Array, rep := 0, start = null, ramp := false) -> Dictionary:
	var cur := {"az": -25.0, "el": 35.0}
	var st := {"az": 2.0, "el": 2.0}
	var n := [9, 9]
	if start == null:
		cur = {"az": -25.0, "el": 36.0}
		st = {"az": 5.0, "el": 5.0}
		n = [27, 13]
	else:
		cur = {"az": start.az, "el": start.el}
	var best := {}
	for r in 10:
		run("tb_cost", n[0] * n[1], [e0, e1, 0, 0], [n[0], n[1], 0, 0],
				[cur.az, cur.el, 0, 0, st.az, st.el, 0, 0, edges[0], edges[1], edges[2], float(rep), 1.0 if ramp else 0.0, 0, 0, 0])
		run("argmin", 1, [n[0] * n[1], 0, 0, 0])
		var res := floats("par", RES, 2)
		var ia: int = int(res[0]) % int(n[0])
		var ie: int = int(res[0]) / int(n[0])
		cur.az += (ia - 0.5 * (n[0] - 1)) * st.az
		cur.el += (ie - 0.5 * (n[1] - 1)) * st.el
		best = {"az": cur.az, "el": cur.el, "cost": res[1]}
		var edge_a: bool = ia == 0 or ia == n[0] - 1
		var edge_e: bool = ie == 0 or ie == n[1] - 1
		if n[0] != 9:
			n = [9, 9]
			st = {"az": 1.25, "el": 1.25}
			continue
		if not edge_a:
			st.az *= 0.5
		if not edge_e:
			st.el *= 0.5
	return best


# ---------------------------------------------------------------------------- contact sheet

## The image in rel[] as a shadow fraction over the view's paving, into a msk byte.
func mask_image(byte_ix: int, job: int) -> void:
	var rec := PackedFloat32Array()
	rec.resize(JOB)
	rec[0] = 0.0
	rec[1] = 0.0
	rec[7] = 1e6
	put_floats("par", job * JOB, rec)
	rd.buffer_clear(bufs.lst, 0, 4)
	clear("acc")
	run("collect", (NPIX + 255) / 256, [job, 0, 0, 0])
	run("levels", 1, [job, 0, 0, 0])
	run("maskw", (NPIX + 255) / 256, [byte_ix, job, 0, 0])


func mask_model(byte_ix: int, post_ids: Array, sun: Dictionary, godot: bool) -> void:
	put_floats("par", RES + 64, PackedFloat32Array(post_ids))
	run("maskm", (NPIX + 255) / 256, [byte_ix, post_ids.size(), 0, 0], [],
			[sun.az, sun.el, sun.d, sun.b, sun.s, 1.0 if godot else 0.0, 0.0, 0.0] + split_far + split_texel)


## Draws the sheet body for the current view; markers: [[kind, panel, x0, y0, x1, y1, rgb, width]].
func sheet(markers: Array, crop: Rect2, scale: float) -> Image:
	var f := PackedFloat32Array()
	for m in markers:
		var c: Color = m[6]
		f.append_array([m[0], m[1], m[2], m[3], m[4], m[5], float(c.r8 + 256 * c.g8 + 65536 * c.b8), m[7]])
	if f.size():
		put_floats("par", RES + 128, f)
	run("sheet", (1920 * 1080 + 255) / 256, [markers.size(), int(crop.position.x), int(crop.position.y), 0], [], [scale])
	var d := rd.buffer_get_data(bufs.shout)
	return Image.create_from_data(1920, 1080, false, Image.FORMAT_RGBA8, d)


## Median and 95th percentile of |original depth - port depth| (m) over the pixels both see.
func depth_check(geo_path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(geo_path)
	if bytes.size() != NPIX * 16:
		return {}
	rd.buffer_update(bufs.raw, 0, bytes.size(), bytes)
	clear("acc")
	run("depthcmp", (NPIX + 255) / 256)
	var h := uints("acc", 0, 256)
	var n := 0
	for c in h:
		n += c
	var out := {"pixels": n}
	for q in [["median_m", 0.5], ["p95_m", 0.95]]:
		var run_ := 0
		for b in 256:
			run_ += h[b]
			if run_ >= q[1] * n:
				out[q[0]] = pow(10.0, (b + 0.5) / 256.0 * 7.0 - 6.0)
				break
	return out


## Mean absolute difference of two 1920 x 1080 PNGs over every pixel and RGB channel, 0..255.
func mad(a: String, b: String) -> float:
	if not load_png(a, "img") or not load_png(b, "outp"):
		return -1.0
	rd.buffer_clear(bufs.acc, 0, 8)
	run("mad", (NPIX + 255) / 256)
	var t := uints("acc", 0, 2)
	return (float(t[0]) + float(t[1])) / (NPIX * 3.0)
