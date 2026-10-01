# sakura/canopy.js: blossom masses. A crown's flower clusters (pads) become one implicit field (a sum
# of soft ellipsoidal kernels; keep-out boxes and floors carve it), polygonised with surface nets into
# a welded smooth mesh and billow-displaced into rounded flower clumps. The same per-vertex data seeds
# the alpha-tested blossom cards.
#
# Per vertex: normal = smooth canopy envelope; uv and colour.b = full shading normal; colour.r = tone
# (quantised into 4 pink bands by the shader); colour.g = peach + 2 * palette.
extends RefCounted

const U = preload("res://addons/sakuragaoka_station/world/sakura/util.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

## prepared kernel record: cx cy cz, inverse rotation rows (m00 m01 m02 m10 m11 m12 m20 m21 m22),
## ix iy iyb iz, R, w
const PS := 18


## A flower cluster. Optional fields keep the original's defaults (core 1, kScale 1, yScale 1.12,
## weight 1, identity q, jit 0, peach 0).
class Pad extends RefCounted:
	var c: U.V
	var rx := 0.0
	var ry := 0.0
	var rz := 0.0
	var layer := 0
	var seed := 0.0
	var jit := 0.0
	var peach := 0.0
	var q: U.Q = null
	var core := 1.0
	var k_scale := 1.0
	var y_scale := 1.12
	var weight := 1.0
	var lobe: Lobe = null
	var twig_dir: U.V = null


class Lobe extends RefCounted:
	var c: U.V
	var rx := 0.0
	var ry := 0.0
	var rz := 0.0
	var jit := 0.0


static func prepare_pads(pads: Array, sup: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(pads.size() * PS)
	var o := 0
	for pd in pads:
		var core: float = pd.core
		var k: float = pd.k_scale * sup
		var sx: float = pd.rx * core * k
		var sz: float = pd.rz * core * k
		var sy: float = pd.ry * (0.4 + 0.6 * core) * k * pd.y_scale
		var e: PackedFloat64Array = (pd.q if pd.q != null else U.Q.new()).inverse_rotation_elements()
		out[o] = pd.c.x
		out[o + 1] = pd.c.y
		out[o + 2] = pd.c.z
		out[o + 3] = e[0]
		out[o + 4] = e[4]
		out[o + 5] = e[8]
		out[o + 6] = e[1]
		out[o + 7] = e[5]
		out[o + 8] = e[9]
		out[o + 9] = e[2]
		out[o + 10] = e[6]
		out[o + 11] = e[10]
		out[o + 12] = 1.0 / (sx * sx)
		out[o + 13] = 1.0 / (sy * sy)
		out[o + 14] = 1.0 / (sy * sy * 0.72)
		out[o + 15] = 1.0 / (sz * sz)
		out[o + 16] = maxf(sx, maxf(sy, sz))
		out[o + 17] = pd.weight
		o += PS
	return out


## kernel value (0..1) of prepared pad record o at (x, y, z)
static func kern(P: PackedFloat64Array, o: int, x: float, y: float, z: float) -> float:
	var R := P[o + 16]
	var dx := x - P[o]
	var dy := y - P[o + 1]
	var dz := z - P[o + 2]
	if dx > R or dx < -R or dy > R or dy < -R or dz > R or dz < -R:
		return 0.0
	var lx := P[o + 3] * dx + P[o + 4] * dy + P[o + 5] * dz
	var ly := P[o + 6] * dx + P[o + 7] * dy + P[o + 8] * dz
	var lz := P[o + 9] * dx + P[o + 10] * dy + P[o + 11] * dz
	var d2 := lx * lx * P[o + 12] + ly * ly * (P[o + 14] if ly < 0.0 else P[o + 13]) + lz * lz * P[o + 15]
	if d2 >= 1.0:
		return 0.0
	var t := 1.0 - d2
	return t * t * t * P[o + 17]


# ------------------------------------------------------------------------------------------ surface nets

## Returns [pos (float32), idx].
static func surface_nets(F: PackedFloat32Array, nx: int, ny: int, nz: int, x0: float, y0: float, z0: float, h: float) -> Array:
	var sy := nx
	var sz := nx * ny
	var cx := nx - 1
	var cy := ny - 1
	var cz := nz - 1
	var cell := PackedInt32Array()
	cell.resize(cx * cy * cz)
	cell.fill(-1)
	var pos := PackedFloat64Array()
	for k in cz:
		for j in cy:
			var row := j * sy + k * sz
			for i in cx:
				var b := i + row
				var v0 := F[b]
				var v1 := F[b + 1]
				var v2 := F[b + sy]
				var v3 := F[b + 1 + sy]
				var v4 := F[b + sz]
				var v5 := F[b + 1 + sz]
				var v6 := F[b + sy + sz]
				var v7 := F[b + 1 + sy + sz]
				var i0 := v0 > 0.0
				var i1 := v1 > 0.0
				var i2 := v2 > 0.0
				var i3 := v3 > 0.0
				var i4 := v4 > 0.0
				var i5 := v5 > 0.0
				var i6 := v6 > 0.0
				var i7 := v7 > 0.0
				if i0 == i1 and i0 == i2 and i0 == i3 and i0 == i4 and i0 == i5 and i0 == i6 and i0 == i7:
					continue
				var px := 0.0
				var py := 0.0
				var pz := 0.0
				var n := 0
				# the 12 edges in the original's order: x edges, y edges, z edges
				if i0 != i1:
					px += v0 / (v0 - v1)
					n += 1
				if i2 != i3:
					px += v2 / (v2 - v3)
					py += 1.0
					n += 1
				if i4 != i5:
					px += v4 / (v4 - v5)
					pz += 1.0
					n += 1
				if i6 != i7:
					px += v6 / (v6 - v7)
					py += 1.0
					pz += 1.0
					n += 1
				if i0 != i2:
					py += v0 / (v0 - v2)
					n += 1
				if i1 != i3:
					px += 1.0
					py += v1 / (v1 - v3)
					n += 1
				if i4 != i6:
					py += v4 / (v4 - v6)
					pz += 1.0
					n += 1
				if i5 != i7:
					px += 1.0
					py += v5 / (v5 - v7)
					pz += 1.0
					n += 1
				if i0 != i4:
					pz += v0 / (v0 - v4)
					n += 1
				if i1 != i5:
					px += 1.0
					pz += v1 / (v1 - v5)
					n += 1
				if i2 != i6:
					py += 1.0
					pz += v2 / (v2 - v6)
					n += 1
				if i3 != i7:
					px += 1.0
					py += 1.0
					pz += v3 / (v3 - v7)
					n += 1
				cell[i + j * cx + k * cx * cy] = pos.size() / 3
				pos.append(x0 + (i + px / n) * h)
				pos.append(y0 + (j + py / n) * h)
				pos.append(z0 + (k + pz / n) * h)
	var idx := PackedInt32Array()
	var cxy := cx * cy
	for k in nz:
		for j in ny:
			for i in nx:
				var b := i + j * sy + k * sz
				var in0 := F[b] > 0.0
				var sg := 1 if in0 else -1
				if i < cx and j > 0 and k > 0 and j < cy and k < cz and in0 != (F[b + 1] > 0.0):
					_quad(pos, idx, cell[i + (j - 1) * cx + (k - 1) * cxy], cell[i + j * cx + (k - 1) * cxy], cell[i + j * cx + k * cxy], cell[i + (j - 1) * cx + k * cxy], 0, sg)
				if j < cy and i > 0 and k > 0 and i < cx and k < cz and in0 != (F[b + sy] > 0.0):
					_quad(pos, idx, cell[(i - 1) + j * cx + (k - 1) * cxy], cell[i + j * cx + (k - 1) * cxy], cell[i + j * cx + k * cxy], cell[(i - 1) + j * cx + k * cxy], 1, sg)
				if k < cz and i > 0 and j > 0 and i < cx and j < cy and in0 != (F[b + sz] > 0.0):
					_quad(pos, idx, cell[(i - 1) + (j - 1) * cx + k * cxy], cell[i + (j - 1) * cx + k * cxy], cell[i + j * cx + k * cxy], cell[(i - 1) + j * cx + k * cxy], 2, sg)
	return [PackedFloat32Array(Array(pos)), idx]


static func _quad(pos: PackedFloat64Array, idx: PackedInt32Array, a: int, b: int, c: int, d: int, axis: int, sign: int) -> void:
	if a < 0 or b < 0 or c < 0 or d < 0:
		return
	# orientation check against the outward direction (inside -> outside along the edge axis)
	var ux := pos[c * 3] - pos[a * 3]
	var uy := pos[c * 3 + 1] - pos[a * 3 + 1]
	var uz := pos[c * 3 + 2] - pos[a * 3 + 2]
	var wx := pos[d * 3] - pos[b * 3]
	var wy := pos[d * 3 + 1] - pos[b * 3 + 1]
	var wz := pos[d * 3 + 2] - pos[b * 3 + 2]
	var nrm := 0.0
	if axis == 0:
		nrm = uy * wz - uz * wy
	elif axis == 1:
		nrm = uz * wx - ux * wz
	else:
		nrm = ux * wy - uy * wx
	if nrm * sign < 0.0:
		var t := b
		b = d
		d = t
	var acx := pos[a * 3] - pos[c * 3]
	var acy := pos[a * 3 + 1] - pos[c * 3 + 1]
	var acz := pos[a * 3 + 2] - pos[c * 3 + 2]
	var bdx := pos[b * 3] - pos[d * 3]
	var bdy := pos[b * 3 + 1] - pos[d * 3 + 1]
	var bdz := pos[b * 3 + 2] - pos[d * 3 + 2]
	if acx * acx + acy * acy + acz * acz < bdx * bdx + bdy * bdy + bdz * bdz:
		idx.append_array([a, b, c, a, c, d])
	else:
		idx.append_array([a, b, d, b, c, d])


static func vertex_normals(pos: PackedFloat32Array, idx: PackedInt32Array, out: PackedFloat32Array) -> void:
	out.fill(0.0)
	var t := 0
	var ni := idx.size()
	while t < ni:
		var a := idx[t] * 3
		var b := idx[t + 1] * 3
		var c := idx[t + 2] * 3
		var ux := pos[b] - pos[a]
		var uy := pos[b + 1] - pos[a + 1]
		var uz := pos[b + 2] - pos[a + 2]
		var vx := pos[c] - pos[a]
		var vy := pos[c + 1] - pos[a + 1]
		var vz := pos[c + 2] - pos[a + 2]
		var nx := uy * vz - uz * vy
		var ny := uz * vx - ux * vz
		var nz := ux * vy - uy * vx
		out[a] += nx
		out[a + 1] += ny
		out[a + 2] += nz
		out[b] += nx
		out[b + 1] += ny
		out[b + 2] += nz
		out[c] += nx
		out[c + 1] += ny
		out[c + 2] += nz
		t += 3
	var q := 0
	var no := out.size()
	while q < no:
		var l := U.hypot3(out[q], out[q + 1], out[q + 2])
		if l == 0.0:
			l = 1.0
		out[q] /= l
		out[q + 1] /= l
		out[q + 2] /= l
		q += 3


static func smooth(pos: PackedFloat32Array, idx: PackedInt32Array, iters: int, lam: float) -> void:
	var n := pos.size() / 3
	var acc := PackedFloat32Array()
	acc.resize(n * 3)
	var cnt := PackedFloat32Array()
	cnt.resize(n)
	var ni := idx.size()
	for it in iters:
		acc.fill(0.0)
		cnt.fill(0.0)
		var t := 0
		while t < ni:
			for e in 3:
				var a := idx[t + e]
				var b := idx[t + (e + 1) % 3]
				acc[a * 3] += pos[b * 3]
				acc[a * 3 + 1] += pos[b * 3 + 1]
				acc[a * 3 + 2] += pos[b * 3 + 2]
				cnt[a] += 1.0
				acc[b * 3] += pos[a * 3]
				acc[b * 3 + 1] += pos[a * 3 + 1]
				acc[b * 3 + 2] += pos[a * 3 + 2]
				cnt[b] += 1.0
			t += 3
		for q in n:
			var cq := cnt[q]
			if cq != 0.0:
				for c in 3:
					pos[q * 3 + c] += lam * (acc[q * 3 + c] / cq - pos[q * 3 + c])


## The blossom-mass surface of a crown, or null. pads: [Pad]. o: {h, canopy, noise, spec, amp, freq,
## smooth, iso, support, cavityDown, weights, groundY, toneBias}.
static func blossom_surface(pads: Array, o: Dictionary) -> Surface:
	var h: float = o.h
	var iso: float = o.get("iso", 0.17)
	var sup: float = o.get("support", 1.5)
	var spec: Dictionary = o.spec
	var canopy = o.canopy
	var noise: U.ValueNoise = o.noise
	var PP := prepare_pads(pads, sup)
	var npp := pads.size()
	if npp == 0:
		return null
	var x0 := INF
	var y0 := INF
	var z0 := INF
	var x1 := -INF
	var y1 := -INF
	var z1 := -INF
	for pi in npp:
		var b := pi * PS
		var R := PP[b + 16]
		x0 = minf(x0, PP[b] - R)
		x1 = maxf(x1, PP[b] + R)
		y0 = minf(y0, PP[b + 1] - R)
		y1 = maxf(y1, PP[b + 1] + R)
		z0 = minf(z0, PP[b + 2] - R)
		z1 = maxf(z1, PP[b + 2] + R)
	x0 -= 2.0 * h
	y0 -= 2.0 * h
	z0 -= 2.0 * h
	var nx := ceili((x1 - x0) / h) + 3
	var ny := ceili((y1 - y0) / h) + 3
	var nz := ceili((z1 - z0) / h) + 3
	var nxy := nx * ny
	var F := PackedFloat32Array()
	F.resize(nx * ny * nz)
	# splat kernels
	for pi in npp:
		var b := pi * PS
		var pcx := PP[b]
		var pcy := PP[b + 1]
		var pcz := PP[b + 2]
		var m00 := PP[b + 3]
		var m01 := PP[b + 4]
		var m02 := PP[b + 5]
		var m10 := PP[b + 6]
		var m11 := PP[b + 7]
		var m12 := PP[b + 8]
		var m20 := PP[b + 9]
		var m21 := PP[b + 10]
		var m22 := PP[b + 11]
		var kix := PP[b + 12]
		var kiy := PP[b + 13]
		var kiyb := PP[b + 14]
		var kiz := PP[b + 15]
		var R := PP[b + 16]
		var kw := PP[b + 17]
		var i0 := maxi(0, floori((pcx - R - x0) / h))
		var i1 := mini(nx - 1, ceili((pcx + R - x0) / h))
		var j0 := maxi(0, floori((pcy - R - y0) / h))
		var j1 := mini(ny - 1, ceili((pcy + R - y0) / h))
		var k0 := maxi(0, floori((pcz - R - z0) / h))
		var k1 := mini(nz - 1, ceili((pcz + R - z0) / h))
		for k in range(k0, k1 + 1):
			var dz := (z0 + k * h) - pcz
			if dz > R or dz < -R:
				continue
			for j in range(j0, j1 + 1):
				var dy := (y0 + j * h) - pcy
				if dy > R or dy < -R:
					continue
				var row := j * nx + k * nxy
				for i in range(i0, i1 + 1):
					var dx := (x0 + i * h) - pcx
					if dx > R or dx < -R:
						continue
					var lx := m00 * dx + m01 * dy + m02 * dz
					var ly := m10 * dx + m11 * dy + m12 * dz
					var lz := m20 * dx + m21 * dy + m22 * dz
					var d2 := lx * lx * kix + ly * ly * (kiyb if ly < 0.0 else kiy) + lz * lz * kiz
					if d2 >= 1.0:
						continue
					var t := 1.0 - d2
					var v := t * t * t * kw
					if v != 0.0:
						F[row + i] += v
	# iso offset and carving (floor per column)
	var floor_at = spec.get("floorAt")
	var has_floor: bool = floor_at != null
	var has_ceil: bool = spec.has("ceilY")
	var ceil_y: float = spec.get("ceilY", 0.0)
	var boxes := PackedFloat64Array()
	for bx in spec.get("keepOut", []):
		boxes.append_array([bx.x0, bx.x1, bx.y0, bx.y1, bx.z0, bx.z1])
	var nb := boxes.size()
	for k in nz:
		var z := z0 + k * h
		for i in nx:
			var x := x0 + i * h
			var fy: float = floor_at.call(x, z) if has_floor else 0.0
			for j in ny:
				var id := i + j * nx + k * nxy
				var f: float = F[id] - iso
				if f > -0.5:
					var y := y0 + j * h
					var pen := 0.0
					if has_floor:
						var d := fy + 0.12 - y
						if d > -0.35:
							pen = maxf(pen, (d + 0.35) / 0.5)
					if has_ceil:
						var d := y - (ceil_y - 0.1)
						if d > -0.35:
							pen = maxf(pen, (d + 0.35) / 0.5)
					var bi := 0
					while bi < nb:
						var d := minf(minf(minf(x - boxes[bi], boxes[bi + 1] - x), minf(y - boxes[bi + 2], boxes[bi + 3] - y)), minf(z - boxes[bi + 4], boxes[bi + 5] - z))
						if d > -0.3:
							pen = maxf(pen, (d + 0.3) / 0.45)
						bi += 6
					if pen > 0.0:
						f -= pen
				if i == 0 or j == 0 or k == 0 or i == nx - 1 or j == ny - 1 or k == nz - 1:
					f = -1.0
				F[id] = f
	var S := surface_nets(F, nx, ny, nz, x0, y0, z0, h)
	var pos: PackedFloat32Array = S[0]
	var idx: PackedInt32Array = S[1]
	var n := pos.size() / 3
	if n == 0:
		return null
	smooth(pos, idx, o.get("smooth", 2) if o.get("smooth") != null else 2, 0.45)
	var nT := PackedFloat32Array()
	nT.resize(n * 3)
	vertex_normals(pos, idx, nT)

	# billow displacement: rounded flower-clump bumps (|noise|) with soft creases, weaker in the cavity
	var A: float = o.get("amp", 0.2) if o.get("amp") != null else 0.2
	var fr: float = o.get("freq", 1.3) if o.get("freq") != null else 1.3
	var crease := PackedFloat32Array()
	crease.resize(n)
	var outer_w := PackedFloat32Array()
	outer_w.resize(n)
	var ccx: float = canopy.cx
	var ccy: float = canopy.cy
	var ccz: float = canopy.cz
	var crx: float = canopy.Rx
	var cry: float = canopy.Ry
	var crz: float = canopy.Rz
	var weeping: bool = canopy.weeping
	for q in n:
		var x := pos[q * 3]
		var y := pos[q * 3 + 1]
		var z := pos[q * 3 + 2]
		var ex := (x - ccx) / crx
		var ey := ((y - ccy) / cry) * 0.45 + 0.28 if weeping else (y - ccy) / cry + 0.16
		var ez := (z - ccz) / crz
		var el := sqrt(ex * ex + ey * ey + ez * ez)
		var inv := 1.0 / (el if el != 0.0 else 1.0)
		ex *= inv
		ey *= inv
		ez *= inv
		var s := nT[q * 3] * ex + nT[q * 3 + 1] * ey + nT[q * 3 + 2] * ez
		var w := U.clamp01((s + 0.3) / 0.6)
		outer_w[q] = w
		var b1 := absf(noise.n3(x * fr + 3.1, y * fr * 1.3 - 1.7, z * fr + 8.3))
		var b2 := absf(noise.n3(x * fr * 2.3 - 5.2, y * fr * 2.6 + 2.9, z * fr * 2.3 + 1.1))
		var bump := minf(1.0, b1 * 1.55) * 0.75 + minf(1.0, b2 * 1.5) * 0.25
		crease[q] = bump
		var d := A * (0.7 + 0.3 * w) * (bump - 0.45)
		pos[q * 3] += nT[q * 3] * d
		pos[q * 3 + 1] += nT[q * 3 + 1] * d
		pos[q * 3 + 2] += nT[q * 3 + 2] * d
	vertex_normals(pos, idx, nT)

	# per-vertex cluster data (tone jitter, peach, lobe normal) from the pad kernels. Pads are looked up
	# through a coarse grid but always summed in their original order, so the sums are the original's.
	var nS := PackedFloat32Array()
	nS.resize(n * 3)
	var tone := PackedFloat32Array()
	tone.resize(n)
	var peach := PackedFloat32Array()
	peach.resize(n)
	var hb := PackedFloat32Array()
	hb.resize(n)
	var gy: float = o.get("groundY", 0.0)
	var cav_down: float = o.get("cavityDown", 1.6)
	var W: Dictionary = o.get("weights", {"t": 0.62, "l": 0.23, "c": 0.15, "up": 0.06})
	var wt: float = W.t
	var wl: float = W.l
	var wc: float = W.c
	var wup: float = W.up
	var tone_bias: float = o.get("toneBias", 0.0)
	var grid := PadGrid.new(PP, npp, x0, y0, z0, x1, y1, z1)
	for q in n:
		var x := pos[q * 3]
		var y := pos[q * 3 + 1]
		var z := pos[q * 3 + 2]
		var sk := 0.0
		var sj := 0.0
		var sp := 0.0
		var km := 0.0
		var nlx := 0.0
		var nly := 0.0
		var nlz := 0.0
		for pi in grid.near(x, y, z):
			var kv := kern(PP, pi * PS, x, y, z)
			if kv == 0.0:
				continue
			var pd: Pad = pads[pi]
			sk += kv
			sj += kv * pd.jit
			sp += kv * pd.peach
			if kv > km:
				km = kv
			var L := pd.lobe
			if L != null:
				nlx += kv * (x - L.c.x) / L.rx
				nly += kv * ((y - L.c.y) / L.ry + 0.12)
				nlz += kv * (z - L.c.z) / L.rz
			else:
				nlx += kv * (x - PP[pi * PS])
				nly += kv * (y - PP[pi * PS + 1])
				nlz += kv * (z - PP[pi * PS + 2])
		var jit := sj / sk if sk > 1e-5 else 0.0
		var pch := sp / sk if sk > 1e-5 else 0.0
		# cluster dominance: ~1 on a clump body, ~0.5 in the crease where two clusters fuse
		var dom := km / sk if sk > 1e-5 else 1.0
		var ex := (x - ccx) / crx
		var ey := ((y - ccy) / cry) * 0.45 + 0.28 if weeping else (y - ccy) / cry + 0.16
		var ez := (z - ccz) / crz
		var el := sqrt(ex * ex + ey * ey + ez * ez)
		var inv := 1.0 / (el if el != 0.0 else 1.0)
		ex *= inv
		ey *= inv
		ez *= inv
		if nlx * nlx + nly * nly + nlz * nlz < 1e-8:
			nlx = ex
			nly = ey
			nlz = ez
		else:
			var ll := sqrt(nlx * nlx + nly * nly + nlz * nlz)
			var li := 1.0 / (ll if ll != 0.0 else 1.0)
			nlx *= li
			nly *= li
			nlz *= li
		var ntx := nT[q * 3]
		var nty := nT[q * 3 + 1]
		var ntz := nT[q * 3 + 2]
		var w := outer_w[q]
		# outer surface: soft blend of surface / lobe / canopy normals; cavity: true normal bent downward
		var sx := ntx * wt + nlx * wl + ex * wc
		var sy := nty * wt + nly * wl + ey * wc + wup
		var sz := ntz * wt + nlz * wl + ez * wc
		var sl := sqrt(sx * sx + sy * sy + sz * sz)
		var si := 1.0 / (sl if sl != 0.0 else 1.0)
		sx *= si
		sy *= si
		sz *= si
		var cxv := ntx
		var cyv := nty - cav_down
		var czv := ntz
		var cl := U.hypot3(cxv, cyv, czv)
		if cl == 0.0:
			cl = 1.0
		sx = sx * w + (cxv / cl) * (1.0 - w)
		sy = sy * w + (cyv / cl) * (1.0 - w)
		sz = sz * w + (czv / cl) * (1.0 - w)
		sl = sqrt(sx * sx + sy * sy + sz * sz)
		si = 1.0 / (sl if sl != 0.0 else 1.0)
		sx *= si
		sy *= si
		sz *= si
		nS[q * 3] = sx
		nS[q * 3 + 1] = sy
		nS[q * 3 + 2] = sz
		# tone: canopy tone and clump jitter; paler on clump tops and up-facing, deeper in creases and the cavity
		var cr := crease[q]
		tone[q] = U.clamp01(canopy.tone_t(x, y, z, jit) + 0.07 * sy + (0.22 + 0.07 * (1.0 - w)) * (cr - 0.5) + 0.24 * (dom - 0.72) + 0.02 * w - 0.07 * (1.0 - w) + tone_bias)
		peach[q] = pch
		hb[q] = y - gy
	var out := Surface.new()
	out.n = n
	out.pos = pos
	out.nT = nT
	out.nS = nS
	out.tone = tone
	out.peach = peach
	out.outer = outer_w
	out.crease = crease
	out.hb = hb
	out.idx = idx
	out.canopy = canopy
	return out


## Pads bucketed on a coarse grid by their kernel boxes; near() lists a point's candidates in their
## original order.
class PadGrid extends RefCounted:
	var gx0 := 0.0
	var gy0 := 0.0
	var gz0 := 0.0
	var cs := 1.0
	var gnx := 1
	var gny := 1
	var gnz := 1
	var cells: Array = []
	var empty := PackedInt32Array()

	func _init(PP: PackedFloat64Array, npp: int, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
		var rmax := 0.0
		for pi in npp:
			rmax = maxf(rmax, PP[pi * 18 + 16])
		cs = maxf(0.5, rmax)
		gx0 = x0 - 1.0
		gy0 = y0 - 1.0
		gz0 = z0 - 1.0
		gnx = int((x1 - gx0) / cs) + 3
		gny = int((y1 - gy0) / cs) + 3
		gnz = int((z1 - gz0) / cs) + 3
		cells.resize(gnx * gny * gnz)
		for c in cells.size():
			cells[c] = PackedInt32Array()
		for pi in npp:
			var b := pi * 18
			var R := PP[b + 16]
			var a0 := maxi(0, int((PP[b] - R - gx0) / cs))
			var a1 := mini(gnx - 1, int((PP[b] + R - gx0) / cs))
			var c0 := maxi(0, int((PP[b + 1] - R - gy0) / cs))
			var c1 := mini(gny - 1, int((PP[b + 1] + R - gy0) / cs))
			var e0 := maxi(0, int((PP[b + 2] - R - gz0) / cs))
			var e1 := mini(gnz - 1, int((PP[b + 2] + R - gz0) / cs))
			for kk in range(e0, e1 + 1):
				for jj in range(c0, c1 + 1):
					for ii in range(a0, a1 + 1):
						cells[ii + jj * gnx + kk * gnx * gny].append(pi)

	func near(x: float, y: float, z: float) -> PackedInt32Array:
		var ii := int((x - gx0) / cs)
		var jj := int((y - gy0) / cs)
		var kk := int((z - gz0) / cs)
		if ii < 0 or jj < 0 or kk < 0 or ii >= gnx or jj >= gny or kk >= gnz:
			return empty
		return cells[ii + jj * gnx + kk * gnx * gny]


## A built blossom-mass surface.
class Surface extends RefCounted:
	var n := 0
	var pos: PackedFloat32Array
	var nT: PackedFloat32Array
	var nS: PackedFloat32Array
	var tone: PackedFloat32Array
	var peach: PackedFloat32Array
	var outer: PackedFloat32Array
	var crease: PackedFloat32Array
	var hb: PackedFloat32Array
	var idx: PackedInt32Array
	var canopy

	func tris() -> int:
		return idx.size() / 3

	## one welded surface on the outline layer
	func emit(B: U.GeoBuilder) -> void:
		var base := B.count
		var pal_id: float = canopy.pal_id
		var ccx: float = canopy.cx
		var ccy: float = canopy.cy
		var ccz: float = canopy.cz
		var crx: float = canopy.Rx
		var cry: float = canopy.Ry
		var crz: float = canopy.Rz
		var weeping: bool = canopy.weeping
		for q in n:
			var x := pos[q * 3]
			var y := pos[q * 3 + 1]
			var z := pos[q * 3 + 2]
			var ex := (x - ccx) / crx
			var ey := ((y - ccy) / cry) * 0.45 + 0.28 if weeping else (y - ccy) / cry + 0.16
			var ez := (z - ccz) / crz
			var el := sqrt(ex * ex + ey * ey + ez * ez)
			var inv := 1.0 / (el if el != 0.0 else 1.0)
			B.v(x, y, z, ex * inv, ey * inv, ez * inv, nS[q * 3], nS[q * 3 + 2], tone[q], peach[q] + 2.0 * pal_id, nS[q * 3 + 1])
		for t in idx.size():
			B.i.append(base + idx[t])


# ------------------------------------------------------------------------------------------ cards

## One alpha-tested card centred on c (cx, cy, cz) facing pn. col: rgb Array or Callable(V) -> rgb;
## nrm: U.V or Callable(V) -> U.V.
static func emit_card(B: U.GeoBuilder, cx: float, cy: float, cz: float, pnx: float, pny: float, pnz: float, size: float, rot: float, cell: Array, col, nrm, aspect: float = 1.0) -> void:
	var rux := 0.31
	var ruy := 0.93
	var ruz := 0.2
	if absf(pnx * rux + pny * ruy + pnz * ruz) > 0.9:
		rux = 0.9
		ruy = 0.1
		ruz = 0.4
	var t1x := pny * ruz - pnz * ruy
	var t1y := pnz * rux - pnx * ruz
	var t1z := pnx * ruy - pny * rux
	var l1 := sqrt(t1x * t1x + t1y * t1y + t1z * t1z)
	var i1 := 1.0 / (l1 if l1 != 0.0 else 1.0)
	t1x *= i1
	t1y *= i1
	t1z *= i1
	var t2x := pny * t1z - pnz * t1y
	var t2y := pnz * t1x - pnx * t1z
	var t2z := pnx * t1y - pny * t1x
	var l2 := sqrt(t2x * t2x + t2y * t2y + t2z * t2z)
	var i2 := 1.0 / (l2 if l2 != 0.0 else 1.0)
	t2x *= i2
	t2y *= i2
	t2z *= i2
	var cr := cos(rot)
	var sr := sin(rot)
	var ax := t1x * cr + t2x * sr
	var ay := t1y * cr + t2y * sr
	var az := t1z * cr + t2z * sr
	var bx := -t1x * sr + t2x * cr
	var by := -t1y * sr + t2y * cr
	var bz := -t1z * sr + t2z * cr
	var hw := size * 0.5 * aspect
	var hh := size * 0.5
	var base := B.count
	var col_fn: bool = col is Callable
	var nrm_fn: bool = nrm is Callable
	var vv := U.V.new()
	for corner in [[-1.0, -1.0, 0.0, 0.0], [1.0, -1.0, 1.0, 0.0], [1.0, 1.0, 1.0, 1.0], [-1.0, 1.0, 0.0, 1.0]]:
		var sx: float = corner[0]
		var sy: float = corner[1]
		vv.set3(cx + ax * hw * sx + bx * hh * sy, cy + ay * hw * sx + by * hh * sy, cz + az * hw * sx + bz * hh * sy)
		var nn: U.V = nrm.call(vv) if nrm_fn else nrm
		var cc: Array = col.call(vv) if col_fn else col
		B.v(vv.x, vv.y, vv.z, nn.x, nn.y, nn.z, cell[0] + corner[2] * 0.5, cell[1] + corner[3] * 0.5, cc[0], cc[1], cc[2])
	B.t(base, base + 1, base + 2)
	B.t(base, base + 2, base + 3)


static func rand_unit(r: Rng, out: U.V) -> U.V:
	var z := r.f() * 2.0 - 1.0
	var a := r.f() * PI * 2.0
	var s := sqrt(1.0 - z * z)
	return out.set3(cos(a) * s, z, sin(a) * s)


static func mix_peach(c: Array, peach_col: Array, k: float) -> Array:
	return U.mix3(c, peach_col, minf(1.0, k * 0.8)) if k > 0.01 else c


## Dresses a blossom surface with alpha-tested blossom cards (area-weighted random samples): lace on
## the outer surface, a few hanging sprays on the lower rim, sparse down-facing cover in the cavity.
## o: {r, CELL, cardBase, pal, peachCol, leafCol, cov, covIn, hangP, nearBoost (Callable or null), leafP}
static func dress_surface(cards: U.GeoBuilder, S: Surface, o: Dictionary) -> int:
	var r: Rng = o.r
	var CELL: Dictionary = o.CELL
	var card_base: float = o.cardBase
	var pal: Array = o.pal
	var pos := S.pos
	var idx := S.idx
	var near_boost = o.get("nearBoost")
	var size2 := card_base * card_base
	var cov_in: float = o.covIn
	var cov_out: float = o.cov
	var hang_p: float = o.get("hangP", 0.25) if o.get("hangP") != null else 0.25
	var leaf_p: float = o.get("leafP", 0.045)
	var tmp := U.V.new()
	var nsv := U.V.new()
	var made := 0
	var t := 0
	var ni := idx.size()
	while t < ni:
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		t += 3
		var ux := pos[b * 3] - pos[a * 3]
		var uy := pos[b * 3 + 1] - pos[a * 3 + 1]
		var uz := pos[b * 3 + 2] - pos[a * 3 + 2]
		var vx := pos[c * 3] - pos[a * 3]
		var vy := pos[c * 3 + 1] - pos[a * 3 + 1]
		var vz := pos[c * 3 + 2] - pos[a * 3 + 2]
		var area := 0.5 * U.hypot3(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
		var w := (S.outer[a] + S.outer[b] + S.outer[c]) / 3.0
		var hbv := (S.hb[a] + S.hb[b] + S.hb[c]) / 3.0
		var up_n := (S.nS[a * 3 + 1] + S.nS[b * 3 + 1] + S.nS[c * 3 + 1]) / 3.0
		var nb: float = near_boost.call(hbv) if near_boost != null else 1.0
		var cov := (cov_in + (cov_out - cov_in) * w) * nb * (1.0 + 0.35 * U.clamp01(up_n * 1.5) * w)
		var expect := (area * cov) / size2
		while expect > 0.0:
			if expect < 1.0 and r.f() > expect:
				break
			expect -= 1.0
			# random barycentric point
			var s1 := r.f()
			var s2 := r.f()
			if s1 + s2 > 1.0:
				s1 = 1.0 - s1
				s2 = 1.0 - s2
			var s0 := 1.0 - s1 - s2
			var pcx := pos[a * 3] * s0 + pos[b * 3] * s1 + pos[c * 3] * s2
			var pcy := pos[a * 3 + 1] * s0 + pos[b * 3 + 1] * s1 + pos[c * 3 + 1] * s2
			var pcz := pos[a * 3 + 2] * s0 + pos[b * 3 + 2] * s1 + pos[c * 3 + 2] * s2
			var ntx := S.nT[a * 3] * s0 + S.nT[b * 3] * s1 + S.nT[c * 3] * s2
			var nty := S.nT[a * 3 + 1] * s0 + S.nT[b * 3 + 1] * s1 + S.nT[c * 3 + 1] * s2
			var ntz := S.nT[a * 3 + 2] * s0 + S.nT[b * 3 + 2] * s1 + S.nT[c * 3 + 2] * s2
			var ntl := sqrt(ntx * ntx + nty * nty + ntz * ntz)
			var nti := 1.0 / (ntl if ntl != 0.0 else 1.0)
			ntx *= nti
			nty *= nti
			ntz *= nti
			var nsx := S.nS[a * 3] * s0 + S.nS[b * 3] * s1 + S.nS[c * 3] * s2
			var nsy := S.nS[a * 3 + 1] * s0 + S.nS[b * 3 + 1] * s1 + S.nS[c * 3 + 1] * s2
			var nsz := S.nS[a * 3 + 2] * s0 + S.nS[b * 3 + 2] * s1 + S.nS[c * 3 + 2] * s2
			var nsl := sqrt(nsx * nsx + nsy * nsy + nsz * nsz)
			var nsi := 1.0 / (nsl if nsl != 0.0 else 1.0)
			nsv.set3(nsx * nsi, nsy * nsi, nsz * nsi)
			var tn := S.tone[a] * s0 + S.tone[b] * s1 + S.tone[c] * s2
			var pch := S.peach[a] * s0 + S.peach[b] * s1 + S.peach[c] * s2
			var cr := S.crease[a] * s0 + S.crease[b] * s1 + S.crease[c] * s2
			var size := card_base * (0.72 + r.f() * 0.46)
			var outer := w > 0.5
			var hang := outer and nty < -0.35 and r.f() < hang_p
			if hang:
				# hanging spray: a vertical card below the lower rim
				pcx += ntx * (size * 0.15)
				pcy += nty * (size * 0.15)
				pcz += ntz * (size * 0.15)
				pcy -= size * (0.3 + r.f() * 0.2)
				var ang := r.f() * 6.28
				var pny := (r.f() - 0.5) * 0.3
				var pnx := cos(ang)
				var pnz := sin(ang)
				var pl := sqrt(pnx * pnx + pny * pny + pnz * pnz)
				var pli := 1.0 / (pl if pl != 0.0 else 1.0)
				var col: Array = mix_peach(U.band_color(pal, tn - 0.02 + (r.f() - 0.5) * 0.12), o.peachCol, pch)
				var hrot := PI / 2.0 + (r.f() - 0.5) * 0.9
				var hcell: Array = CELL.spray if r.f() < 0.6 else CELL.loose
				emit_card(cards, pcx, pcy, pcz, pnx * pli, pny * pli, pnz * pli, size, hrot, hcell, col, nsv, 0.8)
				made += 1
				continue
			# lace: pushed out of the surface (more on clump tops), random tilt biased outward
			var push := size * ((0.14 if outer else -0.02) + r.f() * 0.3 + cr * 0.12)
			pcx += ntx * push
			pcy += nty * push
			pcz += ntz * push
			var k0 := 0.8 if outer else 1.0
			rand_unit(r, tmp)
			var qx := ntx * k0 + tmp.x * 0.85
			var qy := nty * k0 + tmp.y * 0.85
			var qz := ntz * k0 + tmp.z * 0.85
			var ql := sqrt(qx * qx + qy * qy + qz * qz)
			var qi := 1.0 / (ql if ql != 0.0 else 1.0)
			var roll := r.f()
			var leaf := roll < leaf_p
			var cell: Array = CELL.leaf if leaf else (CELL.dense if roll < 0.5 else (CELL.loose if roll < 0.78 else CELL.spray))
			var col2: Array = o.leafCol if leaf else mix_peach(U.band_color(pal, tn + (0.03 if outer else -0.02) + (r.f() - 0.5) * 0.14), o.peachCol, pch)
			emit_card(cards, pcx, pcy, pcz, qx * qi, qy * qi, qz * qi, size, r.f() * PI * 2.0, cell, col2, nsv)
			made += 1
	return made
