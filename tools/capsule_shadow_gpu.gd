# The compute side of tools/capsule_shadow.gd, GLSL on a local RenderingDevice: casters voxelized in
# their own frames, a distance transform, medial seeds, greedy inscribed tapered capsules, then per view
# the original's shadow map replicated, capsules shaded analytically in the light plane, and the metrics.
extends RefCounted

const W := 1920
const H := 1080
const NPIX := W * H
const OI := 32
const OF := 32
const NDIR := 15
const MAXC := 48
const MEDCAP := 1 << 23
const BNDCAP := 1 << 23
const NPLANE := 16
const MAPN := 4096
const NCLS := 9
const NTEST := 10
const HBINS := 66
const SCAN_BLOCK := 1024

const HEADER := """
#version 450
#define NPIX %d
#define W %d
#define H %d
#define OI %d
#define OF %d
#define NDIR %d
#define MAXC %d
#define MEDCAP %d
#define NPLANE %d
#define MAPN %d
#define NCLS %d
#define NTEST %d
#define HBINS %d
#define SCAN_BLOCK %d
#define BIG 1e20
#define IMAX 2147483647
#define PI 3.14159265358979
#define GID (int(gl_GlobalInvocationID.x) + int(gl_GlobalInvocationID.y) * int(gl_NumWorkGroups.x * gl_WorkGroupSize.x))
#define WGID (int(gl_WorkGroupID.x) + int(gl_WorkGroupID.y) * int(gl_NumWorkGroups.x))
layout(std430, set = 0, binding = 0) buffer TriB { vec4 tri[]; };
layout(std430, set = 0, binding = 1) buffer GeoB { float geo[]; };
layout(std430, set = 0, binding = 2) buffer GixB { int gix[]; };
layout(std430, set = 0, binding = 3) buffer ObiB { int obi[]; };
layout(std430, set = 0, binding = 4) buffer ObfB { float obf[]; };
layout(std430, set = 0, binding = 5) buffer AabB { int aab[]; };
layout(std430, set = 0, binding = 6) buffer VoxB { float vox[]; };
layout(std430, set = 0, binding = 7) buffer VflB { uint vfl[]; };
layout(std430, set = 0, binding = 8) buffer ScrB { float scr[]; };
layout(std430, set = 0, binding = 9) buffer MedB { vec4 med[]; };
layout(std430, set = 0, binding = 10) buffer MobB { int mob[]; };
layout(std430, set = 0, binding = 11) buffer CapB { vec4 cap[]; };
layout(std430, set = 0, binding = 12) buffer HstB { float hst[]; };
layout(std430, set = 0, binding = 13) buffer CntB { int cnt[]; };
layout(std430, set = 0, binding = 14) buffer CndB { vec4 cnd[]; };
layout(std430, set = 0, binding = 15) buffer CapwB { vec4 capw[]; };
layout(std430, set = 0, binding = 16) buffer BinB { int bin[]; };
layout(std430, set = 0, binding = 17) buffer PixB { vec4 pix[]; };
layout(std430, set = 0, binding = 18) buffer NrmB { vec4 nrm[]; };
layout(std430, set = 0, binding = 19) buffer OutB { float outp[]; };
layout(std430, set = 0, binding = 20) buffer RawB { uint raw[]; };
layout(std430, set = 0, binding = 21) buffer SmapB { uint smap[]; };
layout(std430, set = 0, binding = 22) buffer SidB { int sid[]; };
layout(std430, set = 0, binding = 23) buffer AccB { uint acc[]; };
layout(std430, set = 0, binding = 24) buffer SelB { int sel[]; };
layout(std430, set = 0, binding = 25) buffer ImgB { uint img[]; };
layout(push_constant, std430) uniform PC { ivec4 i0; ivec4 i1; vec4 f0; vec4 f1; vec4 f2; vec4 f3; } pc;
int f2o(float f) { int i = floatBitsToInt(f); return i >= 0 ? i : i ^ 0x7FFFFFFF; }
float o2f(int i) { return intBitsToFloat(i >= 0 ? i : i ^ 0x7FFFFFFF); }
int find_obj(int field, int x, int o0, int o1) {
	int lo = o0, hi = o1 - 1;
	while (lo < hi) { int mid = (lo + hi + 1) >> 1; if (obi[mid * OI + field] <= x) lo = mid; else hi = mid - 1; }
	return lo;
}
vec3 obv(int o, int k) { int b = o * OF + k; return vec3(obf[b], obf[b + 1], obf[b + 2]); }
vec3 to_local(int o, vec3 x) { vec3 d = x - obv(o, 9); return vec3(dot(obv(o, 12), d), dot(obv(o, 15), d), dot(obv(o, 18), d)); }
vec3 to_vox(int o, vec3 l) { return (l - obv(o, 21)) / obf[o * OF + 24] - 0.5; }
vec3 vox_world(int o, vec3 p) { vec3 l = obv(o, 21) + (p + 0.5) * obf[o * OF + 24]; return obv(o, 9) + obv(o, 12) * l.x + obv(o, 15) * l.y + obv(o, 18) * l.z; }
float dot2(vec3 v) { return dot(v, v); }
float sd_cone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
	vec3 ba = b - a;
	float l2 = dot(ba, ba);
	float rr = r1 - r2;
	if (l2 <= rr * rr + 1e-9) return r1 >= r2 ? length(p - a) - r1 : length(p - b) - r2;
	float a2 = l2 - rr * rr, il2 = 1.0 / l2;
	vec3 pa = p - a;
	float y = dot(pa, ba), z = y - l2;
	float x2 = dot2(pa * l2 - ba * y), y2 = y * y * l2, z2 = z * z * l2;
	float k = sign(rr) * rr * rr * x2;
	if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
	if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
float sd_cone2(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 ba = b - a;
	float h = length(ba);
	if (h <= abs(ra - rb) + 1e-7) return ra >= rb ? length(p - a) - ra : length(p - b) - rb;
	vec2 e = ba / h, pa = p - a;
	vec2 q = vec2(abs(dot(pa, vec2(-e.y, e.x))), dot(pa, e));
	float bb = (ra - rb) / h, aa = sqrt(max(0.0, 1.0 - bb * bb));
	float k = dot(q, vec2(-bb, aa));
	if (k < 0.0) return length(q) - ra;
	if (k > aa * h) return length(q - vec2(0.0, h)) - rb;
	return dot(q, vec2(aa, bb)) - ra;
}
float phi(float x) {
	float z = abs(x) * 0.7071067811865476;
	float t = 1.0 / (1.0 + 0.3275911 * z);
	float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-z * z);
	return x >= 0.0 ? 0.5 * (1.0 + y) : 0.5 * (1.0 - y);
}
float sdh(vec3 p) { p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float sdn(vec3 x) {
	vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(sdh(i), sdh(i + vec3(1, 0, 0)), f.x), mix(sdh(i + vec3(0, 1, 0)), sdh(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(sdh(i + vec3(0, 0, 1)), sdh(i + vec3(1, 0, 1)), f.x), mix(sdh(i + vec3(0, 1, 1)), sdh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
bool dapple(vec3 p) { return sdn(p * 3.1) * 0.62 + sdn(p * 7.3 + 5.1) * 0.38 > 0.66; }
void cas_add(uint i, float v) {
	uint old = acc[i];
	while (true) { uint got = atomicCompSwap(acc[i], old, floatBitsToUint(uintBitsToFloat(old) + v)); if (got == old) break; old = got; }
}
"""

# ---------------------------------------------------------------------------- casters

# world triangles and per-object AABBs (world, then in the object's own frame): i0.x objects, i0.y triangles
const K_TRI := """
layout(local_size_x = 256) in;
vec3 wpos(int o, int v) { vec3 p = vec3(geo[3 * v], geo[3 * v + 1], geo[3 * v + 2]); return obv(o, 0) * p.x + obv(o, 3) * p.y + obv(o, 6) * p.z + obv(o, 9); }
void main() {
	int t = GID;
	if (t >= pc.i0.y) return;
	int o = find_obj(3, t, 0, pc.i0.x);
	int k = t - obi[o * OI + 3], vo = obi[o * OI], io = obi[o * OI + 1];
	ivec3 ix = ivec3(3 * k, 3 * k + 1, 3 * k + 2);
	if (io >= 0) ix = ivec3(gix[io + ix.x], gix[io + ix.y], gix[io + ix.z]);
	vec3 A = wpos(o, vo + ix.x), B = wpos(o, vo + ix.y), C = wpos(o, vo + ix.z);
	if ((obi[o * OI + 4] & 4) != 0) { vec3 s = B; B = C; C = s; }
	tri[3 * t] = vec4(A, float(o));
	tri[3 * t + 1] = vec4(B, 0.0);
	tri[3 * t + 2] = vec4(C, 0.0);
	int a = o * 12;
	vec3 lo = min(A, min(B, C)), hi = max(A, max(B, C));
	atomicMin(aab[a], f2o(lo.x)); atomicMin(aab[a + 1], f2o(lo.y)); atomicMin(aab[a + 2], f2o(lo.z));
	atomicMax(aab[a + 3], f2o(hi.x)); atomicMax(aab[a + 4], f2o(hi.y)); atomicMax(aab[a + 5], f2o(hi.z));
	vec3 la = to_local(o, A), lb = to_local(o, B), lc = to_local(o, C);
	lo = min(la, min(lb, lc)); hi = max(la, max(lb, lc));
	atomicMin(aab[a + 6], f2o(lo.x)); atomicMin(aab[a + 7], f2o(lo.y)); atomicMin(aab[a + 8], f2o(lo.z));
	atomicMax(aab[a + 9], f2o(hi.x)); atomicMax(aab[a + 10], f2o(hi.y)); atomicMax(aab[a + 11], f2o(hi.z));
}
"""

# the AABBs as floats into scr[o * 12 ..], area and signed volume into obf: workgroup per object from i0.x
const K_AREA := """
layout(local_size_x = 256) in;
shared float sa[256];
shared float sv[256];
void main() {
	int o = WGID + pc.i0.x, lid = int(gl_LocalInvocationID.x);
	if (o >= pc.i0.y) return;
	if (lid < 12) scr[o * 12 + lid] = o2f(aab[o * 12 + lid]);
	int t0 = obi[o * OI + 3], n = obi[o * OI + 2];
	vec3 c = 0.5 * (vec3(o2f(aab[o * 12]), o2f(aab[o * 12 + 1]), o2f(aab[o * 12 + 2])) + vec3(o2f(aab[o * 12 + 3]), o2f(aab[o * 12 + 4]), o2f(aab[o * 12 + 5])));
	float a = 0.0, v = 0.0;
	for (int k = lid; k < n; k += 256) {
		int t = t0 + k;
		vec3 A = tri[3 * t].xyz - c, B = tri[3 * t + 1].xyz - c, C = tri[3 * t + 2].xyz - c;
		a += 0.5 * length(cross(B - A, C - A));
		v += dot(A, cross(B, C)) / 6.0;
	}
	sa[lid] = a; sv[lid] = v;
	barrier();
	for (int s = 128; s > 0; s >>= 1) { if (lid < s) { sa[lid] += sa[lid + s]; sv[lid] += sv[lid + s]; } barrier(); }
	if (lid == 0) { obf[o * OF + 26] = sa[0]; obf[o * OF + 27] = sv[0]; }
}
"""

# ---------------------------------------------------------------------------- voxels (batch i0.x..i0.y)

# vfl = 0, vox = 0 over i0.z voxels
const K_VCLEAR := """
layout(local_size_x = 256) in;
void main() { int v = GID; if (v >= pc.i0.z) return; vox[v] = 0.0; vfl[v] = 0u; }
"""

# one line along axis i0.w: crossing parity votes inside (bits 8..11) or outside (12..15); an odd line abstains
const K_VROW := """
layout(local_size_x = 64) in;
void main() {
	int l = GID;
	if (l >= pc.i0.z) return;
	int ax = pc.i0.w;
	int o = find_obj(10 + ax, l, pc.i0.x, pc.i0.y), b = o * OI;
	int nx = obi[b + 6], ny = obi[b + 7], nz = obi[b + 8];
	int k = l - obi[b + 10 + ax], base = obi[b + 9], n, stride;
	float h = obf[o * OF + 24];
	vec3 g0 = obv(o, 21);
	ivec2 oa;
	vec2 pq;
	if (ax == 0) { int j = k % ny, kz = k / ny; n = nx; stride = 1; base += (kz * ny + j) * nx; oa = ivec2(1, 2); pq = vec2(g0.y + (float(j) + 0.5) * h, g0.z + (float(kz) + 0.5) * h); }
	else if (ax == 1) { int i = k % nx, kz = k / nx; n = ny; stride = nx; base += kz * ny * nx + i; oa = ivec2(0, 2); pq = vec2(g0.x + (float(i) + 0.5) * h, g0.z + (float(kz) + 0.5) * h); }
	else { int i = k % nx, j = k / nx; n = nz; stride = nx * ny; base += j * nx + i; oa = ivec2(0, 1); pq = vec2(g0.x + (float(i) + 0.5) * h, g0.y + (float(j) + 0.5) * h); }
	pq += vec2(1.13e-4, 0.71e-4) * h;
	float xs[MAXC];
	int nc = 0;
	int t0 = obi[b + 3], nt = obi[b + 2];
	for (int t = t0; t < t0 + nt; t++) {
		vec3 A = to_local(o, tri[3 * t].xyz), B = to_local(o, tri[3 * t + 1].xyz), C = to_local(o, tri[3 * t + 2].xyz);
		vec2 a2 = vec2(A[oa.x], A[oa.y]), b2 = vec2(B[oa.x], B[oa.y]), c2 = vec2(C[oa.x], C[oa.y]);
		if (pq.x < min(a2.x, min(b2.x, c2.x)) || pq.x > max(a2.x, max(b2.x, c2.x)) || pq.y < min(a2.y, min(b2.y, c2.y)) || pq.y > max(a2.y, max(b2.y, c2.y))) continue;
		float d = (b2.x - a2.x) * (c2.y - a2.y) - (b2.y - a2.y) * (c2.x - a2.x);
		if (abs(d) < 1e-14) continue;
		float w0 = ((b2.x - pq.x) * (c2.y - pq.y) - (b2.y - pq.y) * (c2.x - pq.x)) / d;
		float w1 = ((c2.x - pq.x) * (a2.y - pq.y) - (c2.y - pq.y) * (a2.x - pq.x)) / d;
		float w2 = 1.0 - w0 - w1;
		if (w0 < 0.0 || w1 < 0.0 || w2 < 0.0) continue;
		if (nc >= MAXC) { atomicOr(obi[b + 4], 16); return; }
		xs[nc++] = w0 * A[ax] + w1 * B[ax] + w2 * C[ax];
	}
	if ((nc & 1) != 0) { atomicAdd(obi[b + 24], 1); return; }
	for (int i = 1; i < nc; i++) { float x = xs[i]; int j = i - 1; while (j >= 0 && xs[j] > x) { xs[j + 1] = xs[j]; j--; } xs[j + 1] = x; }
	int m = 0;
	float ga = g0[ax];
	for (int q = 0; q < n; q++) {
		float xc = ga + (float(q) + 0.5) * h;
		while (m < nc && xs[m] < xc) m++;
		vfl[base + q * stride] += (m & 1) != 0 ? 0x100u : 0x1000u;
	}
}
"""

# a voxel is inside when more lines voted inside than outside
const K_VDECIDE := """
layout(local_size_x = 256) in;
void main() {
	int v = GID;
	if (v >= pc.i0.z) return;
	uint f = vfl[v];
	bool inside = ((f >> 8) & 15u) > ((f >> 12) & 15u);
	vfl[v] = inside ? 1u : 0u;
	vox[v] = inside ? BIG : 0.0;
}
"""

# every voxel centre within half a voxel of a triangle is inside: triangles i0.z..i0.w (the batch's)
const K_VSHELL := """
layout(local_size_x = 64) in;
vec3 closest_tri(vec3 p, vec3 a, vec3 b, vec3 c) {
	vec3 ab = b - a, ac = c - a, ap = p - a;
	float d1 = dot(ab, ap), d2 = dot(ac, ap);
	if (d1 <= 0.0 && d2 <= 0.0) return a;
	vec3 bp = p - b; float d3 = dot(ab, bp), d4 = dot(ac, bp);
	if (d3 >= 0.0 && d4 <= d3) return b;
	float vc = d1 * d4 - d3 * d2;
	if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) return a + ab * (d1 / (d1 - d3));
	vec3 cp = p - c; float d5 = dot(ab, cp), d6 = dot(ac, cp);
	if (d6 >= 0.0 && d5 <= d6) return c;
	float vb = d5 * d2 - d1 * d6;
	if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) return a + ac * (d2 / (d2 - d6));
	float va = d3 * d6 - d5 * d4;
	if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)));
	float den = 1.0 / (va + vb + vc);
	return a + ab * (vb * den) + ac * (vc * den);
}
void main() {
	int t = GID + pc.i0.z;
	if (t >= pc.i0.w) return;
	int o = int(tri[3 * t].w + 0.5), b = o * OI;
	int nx = obi[b + 6], ny = obi[b + 7], nz = obi[b + 8], base = obi[b + 9];
	vec3 A = to_vox(o, to_local(o, tri[3 * t].xyz)), B = to_vox(o, to_local(o, tri[3 * t + 1].xyz)), C = to_vox(o, to_local(o, tri[3 * t + 2].xyz));
	ivec3 lo = max(ivec3(floor(min(A, min(B, C)) - 0.5)), ivec3(0)), hi = min(ivec3(ceil(max(A, max(B, C)) + 0.5)), ivec3(nx - 1, ny - 1, nz - 1));
	vec3 nrm = cross(B - A, C - A);
	float nl = length(nrm);
	nrm = nl > 0.0 ? nrm / nl : vec3(0.0);
	for (int z = lo.z; z <= hi.z; z++) for (int y = lo.y; y <= hi.y; y++) {
		int x0 = lo.x, x1 = hi.x;
		if (abs(nrm.x) > 0.2) {
			float xa = (dot(nrm, A) - nrm.y * float(y) - nrm.z * float(z)) / nrm.x, w = 0.5 / abs(nrm.x) + 1.0;
			x0 = max(x0, int(floor(xa - w))); x1 = min(x1, int(ceil(xa + w)));
		}
		for (int x = x0; x <= x1; x++) {
			vec3 p = vec3(x, y, z);
			if (dot2(p - closest_tri(p, A, B, C)) <= 0.25) {
				int v = base + (z * ny + y) * nx + x;
				atomicOr(vfl[v], 1u);
				vox[v] = BIG;
			}
		}
	}
}
"""

# exact squared distance transform along axis i0.w (Felzenszwalb), one line a thread, scratch 3n + 2 a line
const K_EDT := """
layout(local_size_x = 64) in;
void main() {
	int l = GID;
	if (l >= pc.i0.z) return;
	int ax = pc.i0.w;
	int o = find_obj(10 + ax, l, pc.i0.x, pc.i0.y), b = o * OI;
	int nx = obi[b + 6], ny = obi[b + 7], nz = obi[b + 8];
	int k = l - obi[b + 10 + ax], base = obi[b + 9], n, stride;
	if (ax == 0) { int j = k % ny, kz = k / ny; n = nx; stride = 1; base += (kz * ny + j) * nx; }
	else if (ax == 1) { int i = k % nx, kz = k / nx; n = ny; stride = nx; base += kz * ny * nx + i; }
	else { int i = k % nx, j = k / nx; n = nz; stride = nx * ny; base += j * nx + i; }
	int s = obi[b + 13 + ax] + k * (3 * n + 2), sv = s + n, sz = s + 2 * n;
	for (int q = 0; q < n; q++) scr[s + q] = vox[base + q * stride];
	int kk = -1;
	for (int q = 0; q < n; q++) {
		float fq = scr[s + q];
		if (fq >= 0.5 * BIG) continue;
		float qf = float(q);
		if (kk < 0) { kk = 0; scr[sv] = qf; scr[sz] = -BIG; scr[sz + 1] = BIG; continue; }
		float x;
		while (true) {
			float vq = scr[sv + kk], fv = scr[s + int(vq)];
			x = 0.5 * ((fq - fv) / (qf - vq) + qf + vq);
			if (x <= scr[sz + kk] && kk > 0) { kk--; continue; }
			break;
		}
		kk++;
		scr[sv + kk] = qf; scr[sz + kk] = x; scr[sz + kk + 1] = BIG;
	}
	if (kk < 0) return;
	int j = 0;
	for (int q = 0; q < n; q++) {
		float qf = float(q);
		while (scr[sz + j + 1] < qf) j++;
		float vq = scr[sv + j];
		vox[base + q * stride] = (qf - vq) * (qf - vq) + scr[s + int(vq)];
	}
}
"""

# medial voxels (no neighbour's ball holds this one's) into med[0..], boundary voxels into med[MEDCAP..]
const K_MEDIAL := """
layout(local_size_x = 256) in;
void main() {
	int v = GID;
	if (v >= pc.i0.z || (vfl[v] & 1u) == 0u) return;
	int o = find_obj(9, v, pc.i0.x, pc.i0.y), b = o * OI;
	int nx = obi[b + 6], ny = obi[b + 7], lv = v - obi[b + 9];
	int i = lv % nx, j = (lv / nx) % ny, kz = lv / (nx * ny);
	float D = sqrt(vox[v]);
	bool md = true, bd = false;
	for (int dz = -1; dz <= 1; dz++) for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
		if (dx == 0 && dy == 0 && dz == 0) continue;
		int u = v + (dz * ny + dy) * nx + dx;
		if ((vfl[u] & 1u) == 0u) { if (abs(dx) + abs(dy) + abs(dz) == 1) bd = true; continue; }
		if (sqrt(vox[u]) >= D + length(vec3(dx, dy, dz)) - 0.2) md = false;
	}
	if (md) { int m = atomicAdd(cnt[0], 1); if (m < MEDCAP) { med[m] = vec4(i, j, kz, D - 0.5); mob[m] = o; } }
	if (bd) { int m = atomicAdd(cnt[1], 1); if (m < MEDCAP) { med[MEDCAP + m] = vec4(i, j, kz, BIG); mob[MEDCAP + m] = o; } vfl[v] |= 4u; }
}
"""

# ---------------------------------------------------------------------------- greedy capsules

const K_GRESET := """
layout(local_size_x = 64) in;
void main() {
	int o = GID + pc.i0.x;
	if (o >= pc.i0.y) return;
	int b = o * OI;
	obi[b + 19] = -1; obi[b + 18] = IMAX; obi[b + 20] = 0; obi[b + 21] = 0;
}
"""

# the largest uncovered medial ball of each object not done: pass i0.w 0 its radius, 1 its index
const K_SEED := """
layout(local_size_x = 256) in;
void main() {
	int m = GID;
	if (m >= pc.i0.z) return;
	int o = mob[m], b = o * OI;
	float r = med[m].w;
	if (obi[b + 17] != 0 || r < 0.0) return;
	int key = int(r * 1024.0);
	if (pc.i0.w == 0) atomicMax(obi[b + 19], key);
	else if (key == obi[b + 19]) atomicMin(obi[b + 18], m);
}
"""

# from each object's seed, a tapered capsule grown along NDIR directions (13 fixed, 2 from the Hessian)
const K_CAND := """
layout(local_size_x = 64) in;
int gnx, gny, gnz, gbase;
float Dv(int x, int y, int z) {
	if (x < 0 || y < 0 || z < 0 || x >= gnx || y >= gny || z >= gnz) return 0.0;
	return sqrt(vox[gbase + (z * gny + y) * gnx + x]);
}
float Df(vec3 p) {
	vec3 f = floor(p), t = p - f;
	int x = int(f.x), y = int(f.y), z = int(f.z);
	return mix(mix(mix(Dv(x, y, z), Dv(x + 1, y, z), t.x), mix(Dv(x, y + 1, z), Dv(x + 1, y + 1, z), t.x), t.y),
			mix(mix(Dv(x, y, z + 1), Dv(x + 1, y, z + 1), t.x), mix(Dv(x, y + 1, z + 1), Dv(x + 1, y + 1, z + 1), t.x), t.y), t.z);
}
bool inside_grid(vec3 p) { return p.x >= 0.0 && p.y >= 0.0 && p.z >= 0.0 && p.x <= float(gnx - 1) && p.y <= float(gny - 1) && p.z <= float(gnz - 1); }
vec3 hess_dir(vec3 c, int which) {
	float d0 = Df(c);
	mat3 Hm;
	vec3 e[3] = vec3[3](vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1));
	for (int a = 0; a < 3; a++) {
		Hm[a][a] = Df(c + e[a]) + Df(c - e[a]) - 2.0 * d0;
		for (int bq = a + 1; bq < 3; bq++) {
			float v = 0.25 * (Df(c + e[a] + e[bq]) - Df(c + e[a] - e[bq]) - Df(c - e[a] + e[bq]) + Df(c - e[a] - e[bq]));
			Hm[a][bq] = v; Hm[bq][a] = v;
		}
	}
	mat3 V = mat3(1.0);
	for (int sweep = 0; sweep < 8; sweep++) {
		for (int p = 0; p < 2; p++) for (int q = p + 1; q < 3; q++) {
			if (abs(Hm[p][q]) < 1e-9) continue;
			float th = 0.5 * atan(2.0 * Hm[p][q], Hm[q][q] - Hm[p][p]);
			float cs = cos(th), sn = sin(th);
			mat3 J = mat3(1.0);
			J[p][p] = cs; J[q][q] = cs; J[p][q] = sn; J[q][p] = -sn;
			Hm = transpose(J) * Hm * J;
			V = V * J;
		}
	}
	vec3 ev = vec3(Hm[0][0], Hm[1][1], Hm[2][2]);
	int i0 = 0;
	for (int i = 1; i < 3; i++) if (ev[i] > ev[i0]) i0 = i;
	int i1 = i0 == 0 ? 1 : 0;
	for (int i = 0; i < 3; i++) if (i != i0 && ev[i] > ev[i1]) i1 = i;
	vec3 d = V[which == 0 ? i0 : i1];
	return length(d) > 0.0 ? normalize(d) : vec3(1, 0, 0);
}
void main() {
	int g = GID;
	int nob = pc.i0.y - pc.i0.x;
	if (g >= nob * NDIR) return;
	int o = pc.i0.x + g / NDIR, di = g % NDIR, b = o * OI;
	cnd[3 * g + 2] = vec4(-1.0);
	if (obi[b + 17] != 0 || obi[b + 18] == IMAX) return;
	gnx = obi[b + 6]; gny = obi[b + 7]; gnz = obi[b + 8]; gbase = obi[b + 9];
	vec4 sd = med[obi[b + 18]];
	vec3 c0 = sd.xyz;
	vec3 DIRS[13] = vec3[13](vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(1, 1, 0), vec3(1, -1, 0), vec3(1, 0, 1), vec3(1, 0, -1),
			vec3(0, 1, 1), vec3(0, 1, -1), vec3(1, 1, 1), vec3(1, 1, -1), vec3(1, -1, 1), vec3(-1, 1, 1));
	vec3 dir = di < 13 ? normalize(DIRS[di]) : hess_dir(c0, di - 13);
	float r0 = max(abs(sd.w), 0.5), tol = 0.35, st = 0.5;
	float tp = 0.0, tm = 0.0;
	for (int i = 0; i < 40000; i++) { vec3 p = c0 + (tp + st) * dir; if (!inside_grid(p) || Df(p) - 0.5 + tol < r0) break; tp += st; }
	for (int i = 0; i < 40000; i++) { vec3 p = c0 - (tm + st) * dir; if (!inside_grid(p) || Df(p) - 0.5 + tol < r0) break; tm += st; }
	float ext = max(4.0 * r0, 4.0), Tp = tp, Tm = tm;
	for (int i = 0; i < 40000; i++) { vec3 p = c0 + (Tp + st) * dir; if (Tp >= tp + ext || !inside_grid(p) || Df(p) - 0.5 < 0.5) break; Tp += st; }
	for (int i = 0; i < 40000; i++) { vec3 p = c0 - (Tm + st) * dir; if (Tm >= tm + ext || !inside_grid(p) || Df(p) - 0.5 < 0.5) break; Tm += st; }
	const int NS = 160;
	float R[NS];
	int ns = clamp(int((Tp + Tm) / st) + 1, 2, NS);
	float dt = (Tp + Tm) / float(ns - 1);
	for (int i = 0; i < ns; i++) R[i] = Df(c0 + (-Tm + float(i) * dt) * dir) - 0.5 + tol;
	int iu0 = clamp(int(floor((Tm - tm) / dt + 0.5)), 0, ns - 1), iu1 = clamp(int(floor((Tm + tp) / dt + 0.5)), iu0, ns - 1);
	float best = -1.0, ba = 0.0, bs = 0.0;
	int bi0 = iu0, bi1 = iu1;
	for (int sb = 0; sb < 9; sb++) {
		float slope = (float(sb) - 4.0) * 0.1;
		float a = BIG;
		for (int i = iu0; i <= iu1; i++) a = min(a, R[i] - slope * (-Tm + float(i) * dt));
		int i0 = iu0, i1 = iu1;
		if (min(a + slope * (-Tm + float(i0) * dt), a + slope * (-Tm + float(i1) * dt)) < 0.5) continue;
		while (i0 > 0) { float r = a + slope * (-Tm + float(i0 - 1) * dt); if (r > R[i0 - 1] || r < 0.5) break; i0--; }
		while (i1 < ns - 1) { float r = a + slope * (-Tm + float(i1 + 1) * dt); if (r > R[i1 + 1] || r < 0.5) break; i1++; }
		float sc = 0.0;
		for (int i = i0; i <= i1; i++) { float r = a + slope * (-Tm + float(i) * dt); sc += r * r * dt; }
		if (sc > best) { best = sc; ba = a; bs = slope; bi0 = i0; bi1 = i1; }
	}
	if (best < 0.0) return;
	float t0 = -Tm + float(bi0) * dt, t1 = -Tm + float(bi1) * dt;
	cnd[3 * g] = vec4(c0 + t0 * dir, ba + bs * t0);
	cnd[3 * g + 1] = vec4(c0 + t1 * dir, ba + bs * t1);
	cnd[3 * g + 2] = vec4(0.0);
}
"""

# a candidate's gain: inside, uncovered voxels within half a voxel of it; workgroup per candidate
const K_GAIN := """
layout(local_size_x = 256) in;
shared int sg[256];
void main() {
	int g = WGID, lid = int(gl_LocalInvocationID.x);
	if (g >= (pc.i0.y - pc.i0.x) * NDIR) return;
	int o = pc.i0.x + g / NDIR, b = o * OI;
	if (cnd[3 * g + 2].x < 0.0) { if (lid == 0) cnd[3 * g + 2].y = -1.0; return; }
	int nx = obi[b + 6], ny = obi[b + 7], nz = obi[b + 8], base = obi[b + 9];
	vec4 P = cnd[3 * g], Q = cnd[3 * g + 1];
	ivec3 lo = max(ivec3(floor(min(P.xyz - P.w, Q.xyz - Q.w) - 1.0)), ivec3(0)), hi = min(ivec3(ceil(max(P.xyz + P.w, Q.xyz + Q.w) + 1.0)), ivec3(nx - 1, ny - 1, nz - 1));
	ivec3 e = hi - lo + 1;
	int nv = e.x * e.y * e.z, gain = 0;
	for (int k = lid; k < nv; k += 256) {
		ivec3 p = lo + ivec3(k % e.x, (k / e.x) % e.y, k / (e.x * e.y));
		if ((vfl[base + (p.z * ny + p.y) * nx + p.x] & 3u) != 1u) continue;
		if (sd_cone(vec3(p), P.xyz, Q.xyz, P.w, Q.w) <= 0.5) gain++;
	}
	sg[lid] = gain;
	barrier();
	for (int s = 128; s > 0; s >>= 1) { if (lid < s) sg[lid] += sg[lid + s]; barrier(); }
	if (lid == 0) cnd[3 * g + 2].y = float(sg[0]);
}
"""

# keep each object's best candidate (f0.x the least gain); its seed is spent either way
const K_PICK := """
layout(local_size_x = 64) in;
void main() {
	int o = GID + pc.i0.x;
	if (o >= pc.i0.y) return;
	int b = o * OI;
	if (obi[b + 17] != 0) return;
	int seed = obi[b + 18];
	if (seed == IMAX) { obi[b + 17] = 1; return; }
	med[seed].w = -abs(med[seed].w) - 1e-6;
	int best = -1;
	float bg = 0.0;
	for (int d = 0; d < NDIR; d++) { int g = (o - pc.i0.x) * NDIR + d; float gg = cnd[3 * g + 2].y; if (gg > bg) { bg = gg; best = g; } }
	if (best < 0 || bg < pc.f0.x) return;
	int k = obi[b + 16];
	if (k >= obi[b + 25]) { obi[b + 17] = 1; return; }
	int co = obi[b + 26] + k;
	cap[2 * co] = cnd[3 * best];
	cap[2 * co + 1] = cnd[3 * best + 1];
	obi[b + 16] = k + 1;
	obi[b + 20] = 1;
}
"""

# the new capsule's voxels covered: workgroup per object
const K_COVER := """
layout(local_size_x = 256) in;
void main() {
	int o = WGID + pc.i0.x, lid = int(gl_LocalInvocationID.x), b = o * OI;
	if (o >= pc.i0.y || obi[b + 20] == 0) return;
	int nx = obi[b + 6], ny = obi[b + 7], nz = obi[b + 8], base = obi[b + 9];
	int co = obi[b + 26] + obi[b + 16] - 1;
	vec4 P = cap[2 * co], Q = cap[2 * co + 1];
	ivec3 lo = max(ivec3(floor(min(P.xyz - P.w, Q.xyz - Q.w) - 1.0)), ivec3(0)), hi = min(ivec3(ceil(max(P.xyz + P.w, Q.xyz + Q.w) + 1.0)), ivec3(nx - 1, ny - 1, nz - 1));
	ivec3 e = hi - lo + 1;
	int nv = e.x * e.y * e.z;
	for (int k = lid; k < nv; k += 256) {
		ivec3 p = lo + ivec3(k % e.x, (k / e.x) % e.y, k / (e.x * e.y));
		if (sd_cone(vec3(p), P.xyz, Q.xyz, P.w, Q.w) <= 0.5) atomicOr(vfl[base + (p.z * ny + p.y) * nx + p.x], 2u);
	}
}
"""

# medial balls inside the new capsule are covered; boundary voxels take their distance to it (i0.w 0 medial, 1 boundary)
const K_MCOVER := """
layout(local_size_x = 256) in;
void main() {
	int m = GID;
	if (m >= pc.i0.z) return;
	int e = pc.i0.w == 0 ? m : MEDCAP + m;
	int o = mob[e], b = o * OI;
	if (obi[b + 20] == 0) return;
	int co = obi[b + 26] + obi[b + 16] - 1;
	vec4 P = cap[2 * co], Q = cap[2 * co + 1], M = med[e];
	float s = sd_cone(M.xyz, P.xyz, Q.xyz, P.w, Q.w);
	if (pc.i0.w == 0) {
		if (M.w >= 0.0 && s + M.w <= 0.5) med[e].w = -M.w - 1e-6;
	} else {
		float r = min(M.w, max(0.0, s + 0.5));
		med[e].w = r;
		atomicMax(obi[b + 21], int(min(r, 1e6) * 1000.0));
	}
}
"""

# record the object's distance from surface to capsules after this capsule (metres); done at f0.y
const K_HREC := """
layout(local_size_x = 64) in;
void main() {
	int o = GID + pc.i0.x;
	if (o >= pc.i0.y) return;
	int b = o * OI;
	if (obi[b + 20] == 0) return;
	float hm = float(obi[b + 21]) / 1000.0 * obf[o * OF + 24];
	hst[obi[b + 26] + obi[b + 16] - 1] = hm;
	if (hm <= pc.f0.y) obi[b + 17] = 1;
}
"""

# capsules to world: (p1, r1), (p2, r2), (object, class, flags, index in object) for i0.x..i0.y objects
const K_CAPW := """
layout(local_size_x = 64) in;
void main() {
	int o = GID + pc.i0.x;
	if (o >= pc.i0.y) return;
	int b = o * OI;
	float h = obf[o * OF + 24];
	for (int k = 0; k < obi[b + 16]; k++) {
		int co = obi[b + 26] + k;
		vec4 P = cap[2 * co], Q = cap[2 * co + 1];
		capw[3 * co] = vec4(vox_world(o, P.xyz), P.w * h);
		capw[3 * co + 1] = vec4(vox_world(o, Q.xyz), Q.w * h);
		capw[3 * co + 2] = vec4(float(o), float(obi[b + 5]), float(obi[b + 4]), float(k));
	}
}
"""

# per object, its capsule count at each of i0.w tolerances in f-array scr[0..]: k = first with H <= delta,
# 0 when its bounding radius is within delta; sums into cnt[16 + i]
const K_ALLOC := """
layout(local_size_x = 64) in;
void main() {
	int o = GID;
	if (o >= pc.i0.x) return;
	int b = o * OI;
	if ((obi[b + 4] & 64) == 0 || (obi[b + 4] & 32) != 0) return;
	int n = obi[b + 16], ho = obi[b + 26];
	float rad = obf[o * OF + 28];
	for (int i = 0; i < pc.i0.w; i++) {
		float d = scr[i];
		int k = 0;
		if (rad > d) {
			k = n;
			int lo = 0, hi = n - 1;
			while (lo <= hi) { int mid = (lo + hi) >> 1; if (hst[ho + mid] <= d) { k = mid + 1; hi = mid - 1; } else lo = mid + 1; }
		}
		atomicAdd(cnt[16 + i], k);
		if (i == pc.i1.x) sel[o] = k;
	}
}
"""

# ---------------------------------------------------------------------------- scan (exclusive, in place over bin[i0.x .. i0.x + i0.y))

const K_SCAN1 := """
layout(local_size_x = 256) in;
shared int sh[SCAN_BLOCK];
void main() {
	int lid = int(gl_LocalInvocationID.x), blk = WGID;
	int base = pc.i0.x + blk * SCAN_BLOCK;
	for (int k = 0; k < 4; k++) { int i = blk * SCAN_BLOCK + lid * 4 + k; sh[lid * 4 + k] = i < pc.i0.y ? bin[pc.i0.x + i] : 0; }
	barrier();
	if (lid == 0) {
		int s = 0;
		for (int i = 0; i < SCAN_BLOCK; i++) { int v = sh[i]; sh[i] = s; s += v; }
		bin[pc.i0.z + blk] = s;
	}
	barrier();
	for (int k = 0; k < 4; k++) { int i = blk * SCAN_BLOCK + lid * 4 + k; if (i < pc.i0.y) bin[pc.i0.x + i] = sh[lid * 4 + k]; }
}
"""

const K_SCAN2 := """
layout(local_size_x = 1) in;
void main() {
	int s = 0;
	for (int i = 0; i < pc.i0.w; i++) { int v = bin[pc.i0.z + i]; bin[pc.i0.z + i] = s; s += v; }
	bin[pc.i0.z + pc.i0.w] = s;
}
"""

const K_SCAN3 := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= pc.i0.y) return;
	bin[pc.i0.x + i] += bin[pc.i0.z + i / SCAN_BLOCK];
}
"""

# ---------------------------------------------------------------------------- light-plane bins of the shading capsules

# capsule c of the selected set: cells its light-plane footprint (plus 4 sigma) covers. i0.x capsules,
# i0.y grid side, i0.z pass (0 count, 1 fill), i0.w cell list base; f0 = (umin, vmin, cell, pad);
# f1.xyz = light dir, f2.xyz = lx, f3.xyz = ly. Selected capsule ids in sel[SELOFF..] (i1.x)
const K_BIN := """
layout(local_size_x = 64) in;
void main() {
	int c = GID;
	if (c >= pc.i0.x) return;
	int id = sel[pc.i1.x + c];
	vec4 A = capw[3 * id], B = capw[3 * id + 1];
	vec3 lx = pc.f2.xyz, ly = pc.f3.xyz;
	vec2 a = vec2(dot(A.xyz, lx), dot(A.xyz, ly)), bq = vec2(dot(B.xyz, lx), dot(B.xyz, ly));
	float pad = pc.f0.w;
	vec2 lo = min(a - A.w, bq - B.w) - pad, hi = max(a + A.w, bq + B.w) + pad;
	int n = pc.i0.y;
	vec2 gmax = pc.f0.xy + float(n) * pc.f0.z;
	if (hi.x < pc.f0.x || hi.y < pc.f0.y || lo.x > gmax.x || lo.y > gmax.y) return;
	if (pc.i0.z == 0) atomicAdd(cnt[10], 1);
	ivec2 c0 = clamp(ivec2(floor((lo - pc.f0.xy) / pc.f0.z)), ivec2(0), ivec2(n - 1)), c1 = clamp(ivec2(floor((hi - pc.f0.xy) / pc.f0.z)), ivec2(0), ivec2(n - 1));
	vec2 dir = bq - a;
	float len = length(dir);
	vec2 e = len > 1e-6 ? dir / len : vec2(1.0, 0.0);
	float rmax = max(A.w, B.w) + pad;
	for (int y = c0.y; y <= c1.y; y++) for (int x = c0.x; x <= c1.x; x++) {
		vec2 cc = pc.f0.xy + (vec2(x, y) + 0.5) * pc.f0.z;
		vec2 pa = cc - a;
		float t = clamp(dot(pa, e), 0.0, len);
		if (length(pa - e * t) > rmax + 0.7072 * pc.f0.z) continue;
		int cell = y * n + x;
		if (pc.i0.z == 0) atomicAdd(bin[cell], 1);
		else { int slot = atomicAdd(bin[n * n + 1 + cell], 1); bin[pc.i0.w + slot] = id; }
	}
}
"""

# per object: ids of its first sel[o] capsules appended at sel[i0.y ..], their count in cnt[9]
const K_SELECT := """
layout(local_size_x = 64) in;
void main() {
	int o = GID;
	if (o >= pc.i0.x) return;
	int k = sel[o];
	if (k <= 0) return;
	int at = atomicAdd(cnt[9], k), co = obi[o * OI + 26];
	for (int j = 0; j < k; j++) sel[pc.i0.y + at + j] = co + j;
}
"""

const K_COPY := """
layout(local_size_x = 256) in;
void main() { int i = GID; if (i >= pc.i0.z) return; bin[pc.i0.y + i] = bin[pc.i0.x + i]; }
"""

const K_NOP := """
layout(local_size_x = 256) in;
void main() { }
"""

# ---------------------------------------------------------------------------- per-view inputs

# the port's passes (raw planes: posx, posy, posz, normal, sun_shadow, sun_noshadow) into pix, nrm and
# plane 5 (the Godot map's own visibility, -1 where the sun leaves nothing to compare)
const K_DECODE := """
layout(local_size_x = 256) in;
vec4 plane(uint p, uint i) { uint b = (p * uint(NPIX) + i) * 2u; return vec4(unpackHalf2x16(raw[b]), unpackHalf2x16(raw[b + 1u])); }
void main() {
	uint i = uint(GID);
	if (i >= uint(NPIX)) return;
	vec4 X = plane(0u, i), Y = plane(1u, i), Z = plane(2u, i), Nn = plane(3u, i), S1 = plane(4u, i), S0 = plane(5u, i);
	pix[i] = vec4((X.r * 2048.0 - 1024.0) + X.g, (Y.r * 2048.0 - 1024.0) + Y.g, (Z.r * 2048.0 - 1024.0) + Z.g, X.b > 0.5 ? 1.0 : 0.0);
	vec3 n = Nn.rgb * 2.0 - 1.0;
	nrm[i] = vec4(n / max(length(n), 1e-6), 0.0);
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	float l1 = dot(S1.rgb, LUMA), l0 = dot(S0.rgb, LUMA);
	outp[5 * NPIX + int(i)] = l0 > pc.f0.x ? clamp(l1 / l0, 0.0, 1.0) : -1.0;
}
"""

# an original mask (float32 RGBA rows from the bottom, in raw) into plane i0.x: receivers v, others -1
const K_TRUTH := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX) return;
	int x = i % W, y = i / W, s = ((H - 1 - y) * W + x) * 4;
	vec3 c = vec3(uintBitsToFloat(raw[s]), uintBitsToFloat(raw[s + 1]), uintBitsToFloat(raw[s + 2]));
	bool rec = abs(c.r - c.g) < 1e-6 && abs(c.g - c.b) < 1e-6;
	outp[pc.i0.x * NPIX + i] = rec ? clamp(c.r, 0.0, 1.0) : -1.0;
}
"""

# ---------------------------------------------------------------------------- the original's shadow map, replicated

# smap = far, sid = -1 over MAPN^2
const K_MCLEAR := """
layout(local_size_x = 256) in;
void main() { int i = GID; if (i >= MAPN * MAPN) return; smap[i] = 0x7F7FFFFFu; sid[i] = -1; }
"""

# rasterize triangles i0.x..i0.y of in-box casters: pass i0.z 0 depth (atomicMin), 1 the object at the
# winning depth. f0 = (map origin u, v, texel, centre depth offset), f1.xyz light dir, f2.xyz lx, f3.xyz ly, f3.w box centre . L
const K_MRAST := """
layout(local_size_x = 64) in;
void main() {
	int t = GID + pc.i0.x;
	if (t >= pc.i0.y) return;
	int o = int(tri[3 * t].w + 0.5), fl = obi[o * OI + 4];
	if ((fl & 64) == 0 || (fl & 32) != 0) return;
	vec3 L = pc.f1.xyz, lx = pc.f2.xyz, ly = pc.f3.xyz;
	vec3 A = tri[3 * t].xyz, B = tri[3 * t + 1].xyz, C = tri[3 * t + 2].xyz;
	vec3 nt = cross(B - A, C - A);
	if ((fl & 1) == 0 && dot(nt, L) >= 0.0) return;
	float tx = pc.f0.z;
	vec2 a = (vec2(dot(A, lx), dot(A, ly)) - pc.f0.xy) / tx, b = (vec2(dot(B, lx), dot(B, ly)) - pc.f0.xy) / tx, c = (vec2(dot(C, lx), dot(C, ly)) - pc.f0.xy) / tx;
	vec3 dz = pc.f0.w - vec3(dot(A, L), dot(B, L), dot(C, L));
	if (max(dz.x, max(dz.y, dz.z)) < 1.0 || min(dz.x, min(dz.y, dz.z)) > 520.0) return;
	float ar = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
	if (abs(ar) < 1e-12) return;
	ivec2 lo = max(ivec2(floor(min(a, min(b, c)))), ivec2(0)), hi = min(ivec2(ceil(max(a, max(b, c)))), ivec2(MAPN - 1));
	bool blob = (fl & 2) != 0;
	for (int y = lo.y; y <= hi.y; y++) for (int x = lo.x; x <= hi.x; x++) {
		vec2 p = vec2(x, y) + 0.5;
		float w0 = ((b.x - p.x) * (c.y - p.y) - (b.y - p.y) * (c.x - p.x)) / ar;
		float w1 = ((c.x - p.x) * (a.y - p.y) - (c.y - p.y) * (a.x - p.x)) / ar;
		float w2 = 1.0 - w0 - w1;
		if (w0 < 0.0 || w1 < 0.0 || w2 < 0.0) continue;
		float d = w0 * dz.x + w1 * dz.y + w2 * dz.z;
		if (d < 1.0 || d > 520.0) continue;
		if (blob && dapple(w0 * A + w1 * B + w2 * C)) continue;
		int i = y * MAPN + x;
		if (pc.i0.z == 0) atomicMin(smap[i], floatBitsToUint(d));
		else if (floatBitsToUint(d) == smap[i]) sid[i] = o;
	}
}
"""

# per pixel: the original's PCF soft lookup at p + n * normalBias (plane 6) and the top caster at the
# centre texel when it shadows there (plane 7); f0.w bias metres, i0.w = 1 also searches i1.x texels around
# a lit pixel for the nearest shadowing caster
const K_MSHADE := """
layout(local_size_x = 256) in;
float cmp(ivec2 t, float z) { t = clamp(t, ivec2(0), ivec2(MAPN - 1)); return z <= uintBitsToFloat(smap[t.y * MAPN + t.x]) ? 1.0 : 0.0; }
void main() {
	int i = GID;
	if (i >= NPIX) return;
	outp[6 * NPIX + i] = -1.0;
	outp[7 * NPIX + i] = -1.0;
	outp[14 * NPIX + i] = -1.0;
	vec4 P = pix[i];
	if (P.w < 0.5) return;
	vec3 L = pc.f1.xyz, lx = pc.f2.xyz, ly = pc.f3.xyz;
	vec3 q = P.xyz + nrm[i].xyz * pc.f2.w;
	vec2 x = (vec2(dot(q, lx), dot(q, ly)) - pc.f0.xy) / pc.f0.z;
	float z = pc.f3.w - dot(q, L) - pc.f0.w;
	if (x.x < 0.0 || x.y < 0.0 || x.x > float(MAPN) || x.y > float(MAPN) || z > 520.0) { outp[6 * NPIX + i] = 1.0; return; }
	vec2 f = fract(x + 0.5);
	ivec2 u = ivec2(floor(x - f));
	float s = cmp(u, z) + cmp(u + ivec2(1, 0), z) + cmp(u + ivec2(0, 1), z) + cmp(u + ivec2(1, 1), z)
		+ mix(cmp(u + ivec2(-1, 0), z), cmp(u + ivec2(2, 0), z), f.x) + mix(cmp(u + ivec2(-1, 1), z), cmp(u + ivec2(2, 1), z), f.x)
		+ mix(cmp(u + ivec2(0, -1), z), cmp(u + ivec2(0, 2), z), f.y) + mix(cmp(u + ivec2(1, -1), z), cmp(u + ivec2(1, 2), z), f.y)
		+ mix(mix(cmp(u + ivec2(-1, -1), z), cmp(u + ivec2(2, -1), z), f.x), mix(cmp(u + ivec2(-1, 2), z), cmp(u + ivec2(2, 2), z), f.x), f.y);
	outp[6 * NPIX + i] = s / 9.0;
	ivec2 c = clamp(ivec2(floor(x)), ivec2(0), ivec2(MAPN - 1));
	int ci = c.y * MAPN + c.x;
	if (z > uintBitsToFloat(smap[ci])) { outp[7 * NPIX + i] = float(sid[ci]); outp[14 * NPIX + i] = z + pc.f0.w - uintBitsToFloat(smap[ci]); return; }
	if (pc.i0.w == 0) return;
	int R = pc.i1.x, bestd = 1 << 30, besto = -1;
	for (int dy = -R; dy <= R; dy++) for (int dx = -R; dx <= R; dx++) {
		int d2 = dx * dx + dy * dy;
		if (d2 >= bestd || d2 > R * R) continue;
		ivec2 t = c + ivec2(dx, dy);
		if (t.x < 0 || t.y < 0 || t.x >= MAPN || t.y >= MAPN) continue;
		int ti = t.y * MAPN + t.x;
		if (z > uintBitsToFloat(smap[ti])) { bestd = d2; besto = sid[ti]; }
	}
	if (besto >= 0) outp[7 * NPIX + i] = float(besto) + 0.25;
}
"""

# occluder distance along L at the replica's penumbra pixels (planes 6, 14): 16 bins a decade from 1 cm into acc[0..63]
const K_THIST := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX) return;
	float v = outp[6 * NPIX + i], t = outp[14 * NPIX + i];
	if (v <= 0.02 || v >= 0.98 || t <= 0.0) return;
	atomicAdd(acc[clamp(int(log(t / 0.01) / log(10.0) * 16.0), 0, 63)], 1u);
}
"""

# ---------------------------------------------------------------------------- capsules, shaded in the light plane

# per pixel: q = p + n * normalBias + L * depth bias; each capsule of q's cell clipped to t > 0, its signed
# distance in the light plane over sigma (cone: t * tan, or the filter's constant) through Phi; canopy
# capsules let light through where the original's dapple discards their receiver-side surface.
# f0 = (umin, vmin, cell, normal bias), f1 = (L, depth bias), f2 = (lx, tan cone), f3 = (ly, sigma filter);
# i0.x grid side, i0.y list base, i0.z output plane (vis), i0.w = 1 also writes sd (11) and argmin object (12);
# i1.x mode 0 cone, 1 filter; i1.y texel for the dapple taps (bits of float)
const K_CSHADE := """
layout(local_size_x = 128) in;
vec2 entry_exit(vec3 q, vec3 L, vec4 A, vec4 B, float tc) {
	float lo = max(0.0, tc - 4.0 * max(A.w, B.w) - length(B.xyz - A.xyz)), t = lo;
	for (int k = 0; k < 24; k++) { float d = sd_cone(q + L * t, A.xyz, B.xyz, A.w, B.w); if (d < 1e-3) break; t += d; }
	float t2 = t + 2.0 * max(A.w, B.w) + length(B.xyz - A.xyz);
	for (int k = 0; k < 24; k++) { float d = sd_cone(q + L * t2, A.xyz, B.xyz, A.w, B.w); if (d < 1e-3) break; t2 -= d; }
	return vec2(t, max(t, t2));
}
void main() {
	int i = GID;
	if (i >= NPIX) return;
	int pl = pc.i0.z;
	vec4 P = pix[i];
	if (P.w < 0.5) { outp[pl * NPIX + i] = -1.0; return; }
	vec3 L = pc.f1.xyz, lx = pc.f2.xyz, ly = pc.f3.xyz;
	vec3 q = P.xyz + nrm[i].xyz * pc.f0.w + L * pc.f1.w;
	vec2 uv = vec2(dot(q, lx), dot(q, ly));
	int n = pc.i0.x;
	ivec2 cc = ivec2(floor((uv - pc.f0.xy) / pc.f0.z));
	float msol = 1e9, mcan = 1e9, sdmin = 1e9;
	int arg = -1;
	vec2 iv[8];
	int niv = 0, ntest = 0;
	if (cc.x >= 0 && cc.y >= 0 && cc.x < n && cc.y < n) {
		int cell = cc.y * n + cc.x, b0 = bin[cell], b1 = bin[cell + 1];
		for (int e = b0; e < b1; e++) {
			int id = bin[pc.i0.y + e];
			vec4 A = capw[3 * id], B = capw[3 * id + 1];
			vec3 a3 = A.xyz - q, b3 = B.xyz - q;
			float ta = dot(a3, L), tb = dot(b3, L);
			if (ta + A.w <= 0.0 && tb + B.w <= 0.0) continue;
			ntest++;
			float ra = A.w, rb = B.w;
			if (ta < 0.0 || tb < 0.0) {
				float u = ta / (ta - tb);
				vec3 m3 = mix(a3, b3, u);
				float rm = mix(ra, rb, u);
				if (ta < 0.0) { a3 = m3; ra = rm; ta = 0.0; } else { b3 = m3; rb = rm; tb = 0.0; }
			}
			vec2 a2 = vec2(dot(a3, lx), dot(a3, ly)), b2 = vec2(dot(b3, lx), dot(b3, ly));
			float sd = sd_cone2(vec2(0.0), a2, b2, ra, rb);
			vec2 ab = b2 - a2;
			float u = clamp(dot(-a2, ab) / max(dot(ab, ab), 1e-12), 0.0, 1.0);
			float tc = mix(ta, tb, u);
			float sig = pc.i1.x == 0 ? max(2e-3, tc * pc.f2.w) : pc.f3.w;
			float zz = sd / sig;
			bool can = int(capw[3 * id + 2].y + 0.5) == 5;
			if (can) {
				mcan = min(mcan, zz);
				if (sd < 0.0 && niv < 8) iv[niv++] = entry_exit(q, L, vec4(a3 + q, ra), vec4(b3 + q, rb), tc);
			} else msol = min(msol, zz);
			if (sd < sdmin) { sdmin = sd; arg = id; }
		}
	}
	float hole = 1.0;
	if (niv > 0) {
		for (int a = 1; a < niv; a++) { vec2 x = iv[a]; int j = a - 1; while (j >= 0 && iv[j].x > x.x) { iv[j + 1] = iv[j]; j--; } iv[j + 1] = x; }
		float tx = uintBitsToFloat(uint(pc.i1.y));
		float through = 0.0;
		for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
			vec3 off = (lx * float(dx) + ly * float(dy)) * tx;
			float pass_ = 1.0, end = -1.0;
			for (int a = 0; a < niv; a++) {
				if (iv[a].x <= end) { end = max(end, iv[a].y); continue; }
				end = iv[a].y;
				if (!dapple(q + off + L * iv[a].x)) { pass_ = 0.0; break; }
			}
			through += pass_;
		}
		hole = through / 9.0;
	}
	float v = phi(msol) * (1.0 - (1.0 - phi(mcan)) * (1.0 - hole));
	outp[pl * NPIX + i] = v;
	if (pc.i0.w == 1) { outp[11 * NPIX + i] = sdmin; outp[12 * NPIX + i] = arg >= 0 ? capw[3 * arg + 2].x : -1.0; }
	atomicAdd(cnt[8], ntest);
}
"""

# ---------------------------------------------------------------------------- metrics

# class of each pixel's top caster (plane 7) into plane 8, and the comparable-receiver mask into plane 13:
# a receiver in the canonical truth (plane 0), a valid port position, and the Godot map defined (plane 5)
const K_CLASS := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX) return;
	float o = outp[7 * NPIX + i];
	outp[8 * NPIX + i] = o >= 0.0 ? float(obi[int(o) * OI + 5]) : -1.0;
	bool ok = outp[i] >= 0.0 && pix[i].w > 0.5 && outp[5 * NPIX + i] >= 0.0;
	outp[13 * NPIX + i] = ok ? 1.0 : 0.0;
}
"""

# sum |plane - truth| and count per (test, class) over the comparable mask; tests are planes in i0, i1
# (-1 unused), the truth plane f0.x, the slot f0.y: acc[((slot * NTEST + test) * NCLS + class) * 2] (sum, count)
const K_ACC := """
layout(local_size_x = 256) in;
shared uint ss[8 * NCLS];
shared uint sn[8 * NCLS];
void main() {
	int i = GID, lid = int(gl_LocalInvocationID.x);
	for (int k = lid; k < 8 * NCLS; k += 256) { ss[k] = 0u; sn[k] = 0u; }
	barrier();
	int tp[8] = int[8](pc.i0.x, pc.i0.y, pc.i0.z, pc.i0.w, pc.i1.x, pc.i1.y, pc.i1.z, pc.i1.w);
	if (i < NPIX && outp[13 * NPIX + i] > 0.5) {
		float tr = outp[int(pc.f0.x) * NPIX + i];
		int c = int(outp[8 * NPIX + i]);
		c = c < 0 ? NCLS - 1 : min(c, NCLS - 2);
		for (int k = 0; k < 8; k++) {
			if (tp[k] < 0) continue;
			float v = outp[tp[k] * NPIX + i];
			if (v < 0.0) continue;
			atomicAdd(sn[k * NCLS + c], 1u);
			atomicAdd(ss[k * NCLS + c], uint(abs(v - tr) * 4096.0 + 0.5));
		}
	}
	barrier();
	int slot = int(pc.f0.y + 0.5);
	for (int k = lid; k < 8 * NCLS; k += 256) {
		if (sn[k] == 0u) continue;
		uint base = uint(((slot * NTEST + k / NCLS) * NCLS + k % NCLS) * 2);
		cas_add(base, float(ss[k]) / 4096.0);
		atomicAdd(acc[base + 1u], sn[k]);
	}
}
"""

# edge displacement: at each truth (plane f0.x) 0.5 crossing between a pixel and its right or lower
# neighbour, the test plane's own crossing searched along the truth's gradient within i1.y pixels; the
# world distance between them into a 0.5 cm histogram per (test, class): HBINS - 2 overflow, HBINS - 1 not
# found. Signed sum (+ when the test's shadow is larger) into the histogram's tail. Tests in i0 (-1 unused).
# Histogram base i1.x: acc[i1.x + ((test * NCLS + class) * (HBINS + 2))]
const K_EDGE := """
layout(local_size_x = 256) in;
float tv(int pl, ivec2 p) { if (p.x < 0 || p.y < 0 || p.x >= W || p.y >= H) return -1.0; int j = p.y * W + p.x; return outp[13 * NPIX + j] > 0.5 ? outp[pl * NPIX + j] : -1.0; }
vec3 wp(vec2 p) {
	ivec2 a = clamp(ivec2(floor(p)), ivec2(0), ivec2(W - 1, H - 1));
	return pix[a.y * W + a.x].xyz;
}
void main() {
	int i = GID;
	if (i >= NPIX) return;
	int tr = int(pc.f0.x);
	ivec2 p = ivec2(i % W, i / W);
	float v0 = tv(tr, p);
	if (v0 < 0.0) return;
	int c = int(outp[8 * NPIX + i]);
	c = c < 0 ? NCLS - 1 : min(c, NCLS - 2);
	int tp[4] = int[4](pc.i0.x, pc.i0.y, pc.i0.z, pc.i0.w);
	for (int nb = 0; nb < 2; nb++) {
		ivec2 q = p + (nb == 0 ? ivec2(1, 0) : ivec2(0, 1));
		float v1 = tv(tr, q);
		if (v1 < 0.0 || (v0 - 0.5) * (v1 - 0.5) > 0.0 || v0 == v1) continue;
		vec2 x0 = vec2(p) + (vec2(q - p)) * ((0.5 - v0) / (v1 - v0));
		vec2 g = vec2(tv(tr, p + ivec2(1, 0)) - tv(tr, p - ivec2(1, 0)), tv(tr, p + ivec2(0, 1)) - tv(tr, p - ivec2(0, 1)));
		if (length(g) < 1e-6) g = vec2(q - p) * (v1 - v0);
		g = normalize(g);
		vec3 w0 = wp(x0 + 0.5);
		for (int k = 0; k < 4; k++) {
			if (tp[k] < 0) continue;
			int found = 0;
			float bestS = 1e9;
			vec2 bx = x0;
			for (int s = -pc.i1.y; s < pc.i1.y; s++) {
				vec2 a = x0 + g * float(s), b2 = x0 + g * float(s + 1);
				float va = tv(tp[k], ivec2(floor(a + 0.5))), vb = tv(tp[k], ivec2(floor(b2 + 0.5)));
				if (va < 0.0 || vb < 0.0 || (va - 0.5) * (vb - 0.5) > 0.0 || va == vb) continue;
				float f = (0.5 - va) / (vb - va), sx = float(s) + f;
				if (abs(sx) < abs(bestS)) { bestS = sx; bx = x0 + g * sx; found = 1; }
			}
			uint hb = uint(pc.i1.x + (k * NCLS + c) * (HBINS + 2));
			if (found == 0) { atomicAdd(acc[hb + uint(HBINS - 1)], 1u); continue; }
			float dist = length(wp(bx + 0.5) - w0);
			int bin = min(int(dist / 0.005), HBINS - 2);
			atomicAdd(acc[hb + uint(bin)], 1u);
			cas_add(hb + uint(HBINS), bestS > 0.0 ? dist : -dist);
			atomicAdd(acc[hb + uint(HBINS + 1)], 1u);
		}
	}
}
"""

# building contact: ground pixels (n.y > 0.8) outside a building footprint (scr[i1.x + 8 * k]: centre x, z,
# half x, half z, cos, sin, bottom y, top y; i1.y footprints), within f0.y m of its base edge (band) and of
# its corner (corner); |test - truth| and (test - truth) summed per test: acc[i1.z + (test * 2 + zone) * 3]
const K_CONTACT := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX || outp[13 * NPIX + i] < 0.5 || nrm[i].y < 0.8) return;
	vec3 p = pix[i].xyz;
	float dband = 1e9, dcorner = 1e9;
	for (int k = 0; k < pc.i1.y; k++) {
		int s = pc.i1.x + 8 * k;
		float by = scr[s + 6];
		if (abs(p.y - by) > 0.2) continue;
		vec2 d = p.xz - vec2(scr[s], scr[s + 1]);
		vec2 l = vec2(scr[s + 4] * d.x + scr[s + 5] * d.y, -scr[s + 5] * d.x + scr[s + 4] * d.y);
		vec2 e = abs(l) - vec2(scr[s + 2], scr[s + 3]);
		float out_ = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
		if (out_ <= 0.0) continue;
		dband = min(dband, out_);
		dcorner = min(dcorner, length(abs(l) - vec2(scr[s + 2], scr[s + 3])));
	}
	float tr = outp[int(pc.f0.x) * NPIX + i];
	int tp[4] = int[4](pc.i0.x, pc.i0.y, pc.i0.z, pc.i0.w);
	for (int zone = 0; zone < 2; zone++) {
		if ((zone == 0 ? dband : dcorner) > pc.f0.y) continue;
		for (int k = 0; k < 4; k++) {
			if (tp[k] < 0) continue;
			float v = outp[tp[k] * NPIX + i];
			if (v < 0.0) continue;
			uint b = uint(pc.i1.z + (k * 2 + zone) * 3);
			cas_add(b, abs(v - tr));
			cas_add(b + 1u, v - tr);
			atomicAdd(acc[b + 2u], 1u);
		}
	}
}
"""

# thin casters' shadows: pixels whose top caster (plane 7, exact, not a near-edge attribution) is object o
# and the truth is in shadow count into sel[i1.x + 3 * o]; also when plane i0.x (capsules) and i0.y (map)
# keep them in shadow
const K_SURV := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX || outp[13 * NPIX + i] < 0.5) return;
	float of = outp[7 * NPIX + i];
	if (of < 0.0 || fract(of) > 0.1) return;
	int o = int(of);
	if (outp[int(pc.f0.x) * NPIX + i] >= 0.5) return;
	atomicAdd(sel[pc.i1.x + 3 * o], 1);
	if (outp[pc.i0.x * NPIX + i] < 0.5) atomicAdd(sel[pc.i1.x + 3 * o + 1], 1);
	if (pc.i0.y >= 0 && outp[pc.i0.y * NPIX + i] < 0.5) atomicAdd(sel[pc.i1.x + 3 * o + 2], 1);
}
"""

# a contact sheet: 2 x 2 tiles at half size, planes i0 (top left, top right, bottom left, bottom right),
# grey visibility; non-receivers dark blue
const K_SHEET := """
layout(local_size_x = 256) in;
void main() {
	int i = GID;
	if (i >= NPIX) return;
	int x = i % W, y = i / W, tile = (y >= H / 2 ? 2 : 0) + (x >= W / 2 ? 1 : 0);
	int sx = (x % (W / 2)) * 2, sy = (y % (H / 2)) * 2;
	int pl = tile == 0 ? pc.i0.x : tile == 1 ? pc.i0.y : tile == 2 ? pc.i0.z : pc.i0.w;
	float s = 0.0, n = 0.0;
	for (int dy = 0; dy < 2; dy++) for (int dx = 0; dx < 2; dx++) {
		int j = (sy + dy) * W + sx + dx;
		float v = outp[pl * NPIX + j];
		if (v >= 0.0 && outp[13 * NPIX + j] > 0.5) { s += v; n += 1.0; }
	}
	vec3 c = n > 0.0 ? vec3(pow(s / n, 1.0 / 2.2)) : vec3(0.08, 0.1, 0.22);
	img[i] = packUnorm4x8(vec4(c, 1.0));
}
"""

var rd: RenderingDevice
var shaders := {}
var pipes := {}
var bufs := {}
var sizes := {}
var _set: RID
var ok := true
var log_lines := []

const BUFS := ["tri", "geo", "gix", "obi", "obf", "aab", "vox", "vfl", "scr", "med", "mob", "cap", "hst", "cnt", "cnd", "capw",
		"bin", "pix", "nrm", "outp", "raw", "smap", "sid", "acc", "sel", "img"]


func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()
	assert(rd != null, "capsule_shadow: no RenderingDevice (run with a GPU driver, not --headless)")
	var hdr := HEADER % [NPIX, W, H, OI, OF, NDIR, MAXC, MEDCAP, NPLANE, MAPN, NCLS, NTEST, HBINS, SCAN_BLOCK]
	var kernels := {"tri": K_TRI, "area": K_AREA, "vclear": K_VCLEAR, "vrow": K_VROW, "vdecide": K_VDECIDE, "vshell": K_VSHELL,
			"edt": K_EDT, "medial": K_MEDIAL, "greset": K_GRESET, "seed": K_SEED, "cand": K_CAND, "gain": K_GAIN, "pick": K_PICK,
			"cover": K_COVER, "mcover": K_MCOVER, "hrec": K_HREC, "capw": K_CAPW, "alloc": K_ALLOC, "scan1": K_SCAN1,
			"scan2": K_SCAN2, "scan3": K_SCAN3, "bin": K_BIN, "decode": K_DECODE, "truth": K_TRUTH, "mclear": K_MCLEAR,
			"mrast": K_MRAST, "mshade": K_MSHADE, "cshade": K_CSHADE, "class": K_CLASS, "acc": K_ACC, "edge": K_EDGE,
			"contact": K_CONTACT, "surv": K_SURV, "sheet": K_SHEET,
			"select": K_SELECT, "copy": K_COPY, "nop": K_NOP, "thist": K_THIST}
	for k in kernels:
		var src := RDShaderSource.new()
		src.source_compute = hdr + kernels[k]
		var spirv := rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("capsule_shadow: kernel %s: %s" % [k, spirv.compile_error_compute])
			ok = false
			continue
		shaders[k] = rd.shader_create_from_spirv(spirv)
		pipes[k] = rd.compute_pipeline_create(shaders[k])
	for k in BUFS:
		alloc(k, 16)
	alloc("cnt", 4096 * 4)
	alloc("pix", NPIX * 16)
	alloc("nrm", NPIX * 16)
	alloc("outp", NPIX * NPLANE * 4)
	alloc("raw", NPIX * 16)
	alloc("smap", MAPN * MAPN * 4)
	alloc("sid", MAPN * MAPN * 4)
	alloc("img", NPIX * 4)
	alloc("med", (MEDCAP * 2) * 16)
	alloc("mob", (MEDCAP * 2) * 4)


func release() -> void:
	if _set.is_valid() and rd.uniform_set_is_valid(_set):
		rd.free_rid(_set)
	for k in pipes:
		rd.free_rid(pipes[k])
	for k in shaders:
		rd.free_rid(shaders[k])
	for k in bufs:
		rd.free_rid(bufs[k])
	rd.free()


## (Re)creates a storage buffer of at least n bytes; the uniform set is rebuilt on next use.
func alloc(name: String, n: int) -> void:
	n = maxi(16, (n + 15) / 16 * 16)
	if sizes.get(name, 0) == n:
		return
	if bufs.has(name):
		if _set.is_valid() and rd.uniform_set_is_valid(_set):
			rd.free_rid(_set)
		_set = RID()
		rd.free_rid(bufs[name])
	bufs[name] = rd.storage_buffer_create(n)
	sizes[name] = n


func _uset() -> RID:
	if not (_set.is_valid() and rd.uniform_set_is_valid(_set)):
		var us := []
		for b in BUFS.size():
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding = b
			u.add_id(bufs[BUFS[b]])
			us.append(u)
		_set = rd.uniform_set_create(us, shaders.values()[0], 0)
	return _set


static func _pc(i0: Array, i1: Array, f: Array) -> PackedByteArray:
	var ii := PackedInt32Array(i0)
	ii.resize(4)
	var jj := PackedInt32Array(i1)
	jj.resize(4)
	ii.append_array(jj)
	var b := ii.to_byte_array()
	var ff := PackedFloat32Array(f)
	ff.resize(16)
	b.append_array(ff.to_byte_array())
	return b


## Dispatches in one submission, a barrier between each: [[kernel, groups, i0, i1, f], ...].
func runs(list: Array) -> void:
	var cl := rd.compute_list_begin()
	var first := true
	for d in list:
		if d[1] <= 0:
			continue
		if not first:
			rd.compute_list_add_barrier(cl)
		first = false
		var pcb := _pc(d[2] if d.size() > 2 else [], d[3] if d.size() > 3 else [], d[4] if d.size() > 4 else [])
		rd.compute_list_bind_compute_pipeline(cl, pipes[d[0]])
		rd.compute_list_bind_uniform_set(cl, _uset(), 0)
		rd.compute_list_set_push_constant(cl, pcb, pcb.size())
		var g: int = d[1]
		rd.compute_list_dispatch(cl, mini(g, 65535), maxi(1, (g + 65534) / 65535), 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()


func run(kernel: String, groups: int, i0 := [], i1 := [], f := []) -> void:
	runs([[kernel, groups, i0, i1, f]])


func ints(buf: String, offset: int, count: int) -> PackedInt32Array:
	return rd.buffer_get_data(bufs[buf], offset * 4, count * 4).to_int32_array()


func floats(buf: String, offset: int, count: int) -> PackedFloat32Array:
	return rd.buffer_get_data(bufs[buf], offset * 4, count * 4).to_float32_array()


func put(buf: String, offset: int, data: PackedByteArray) -> void:
	if data.size() > 0:
		rd.buffer_update(bufs[buf], offset * 4, data.size(), data)


func zero(buf: String, offset := 0, count := -1) -> void:
	var n: int = sizes[buf] - offset * 4 if count < 0 else count * 4
	rd.buffer_clear(bufs[buf], offset * 4, (n + 3) / 4 * 4)


## The port's buffers at view i (tools/sun_locate.gd's .f16 passes) decoded into pix, nrm and plane 5.
func load_port(dir: String, i: int, sun_floor: float) -> void:
	var names := ["posx", "posy", "posz", "normal", "sun_shadow", "sun_noshadow"]
	alloc("raw", NPIX * 8 * names.size())
	for p in names.size():
		var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBH, FileAccess.get_file_as_bytes(dir.path_join("%s_%d.f16" % [names[p], i])))
		img.convert(Image.FORMAT_RGBAH)
		put("raw", p * NPIX * 2, img.get_data())
	run("decode", (NPIX + 255) / 256, [], [], [sun_floor])


## An original mask (tools/oracle/sun_mask.mjs) into plane pl; false when the file is missing.
func load_truth(path: String, pl: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	alloc("raw", NPIX * 16)
	put("raw", 0, FileAccess.get_file_as_bytes(path))
	run("truth", (NPIX + 255) / 256, [pl])
	return true


## Exclusive prefix sum over bin[off .. off + n), the total at bin[off + n]; block sums at bin[tmp ..].
func scan(off: int, n: int, tmp: int) -> int:
	var blocks := (n + SCAN_BLOCK - 1) / SCAN_BLOCK
	runs([["scan1", blocks, [off, n, tmp]], ["scan2", 1, [off, n, tmp, blocks]], ["scan3", (n + 255) / 256, [off, n, tmp]]])
	var total := ints("bin", tmp + blocks, 1)[0]
	put("bin", off + n, PackedInt32Array([total]).to_byte_array())
	return total


## GPU milliseconds a dispatch list takes, from CPU time around reps submissions less as many empty ones.
func time_runs(list: Array, reps := 10) -> float:
	runs(list)
	var t0 := Time.get_ticks_usec()
	for r in reps:
		runs(list)
	var t1 := Time.get_ticks_usec()
	for r in reps:
		run("nop", 1)
	var t2 := Time.get_ticks_usec()
	return maxf(0.0, float((t1 - t0) - (t2 - t1)) / reps / 1000.0)
