# petals/textures.js: petal textures computed analytically (deterministic).
#  - shapeTex  (RGBA, linear data): R = sharp alpha, G = edge mask (1 at the rim), B = vein pattern,
#                                    A = soft/defocused alpha. Used by the custom petal shaders.
#  - colorTex  (RGBA, sRGB):        painted petal (base deeper pink -> pale body) + sharp alpha,
#                                    for the toon ground petals (instance colour tints it).
#  - raftTex   (RGBA, sRGB, 2x2 atlas): dense petal rafts for the river.
#  - patchTex  (RGBA, sRGB, 2x2 atlas): ground carpet patches.
# Texture space: u across the petal (0..1), v from the base/claw (0) to the notched tip (1).
# Each texture is a T.Tex carrying its pixels as a Godot Image in user_data.image.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

# right half of the outline, from the claw (base) up to the bottom of the tip notch
const HALF := [
	[0.0, 0.02], [0.05, 0.045], [0.105, 0.1], [0.175, 0.19], [0.25, 0.3], [0.32, 0.43], [0.378, 0.56],
	[0.418, 0.675], [0.432, 0.77], [0.418, 0.855], [0.378, 0.922], [0.318, 0.966], [0.248, 0.986],
	[0.176, 0.982], [0.112, 0.955], [0.062, 0.915], [0.026, 0.878], [0.0, 0.86],
]


static func _f(a: float, b: float, c: float, d: float, t: float, t2: float, t3: float) -> float:
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)


static func catmull(pts: Array, sub: int) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var p0: Array = pts[maxi(0, i - 1)]
		var p1: Array = pts[i]
		var p2: Array = pts[i + 1]
		var p3: Array = pts[mini(pts.size() - 1, i + 2)]
		for k in sub:
			var t := float(k) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append([_f(p0[0], p1[0], p2[0], p3[0], t, t2, t3), _f(p0[1], p1[1], p2[1], p3[1], t, t2, t3)])
	out.append(pts[pts.size() - 1])
	return out


## Closed outline polygon in (U in -0.5..0.5, V in 0..1).
static func petal_outline() -> Array:
	var r := catmull(HALF, 4)
	var l: Array = r.slice(1, r.size() - 1)
	l.reverse()
	l = l.map(func(p): return [-p[0], p[1]])
	return r + l


static func make_sdf(N: int) -> PackedFloat32Array:
	var poly := petal_outline()
	var n := poly.size()
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	for p in poly:
		px.append(p[0])
		py.append(p[1])
	var sdf := PackedFloat32Array()
	sdf.resize(N * N)
	for j in N:
		var v := (j + 0.5) / N
		for i in N:
			var u := (i + 0.5) / N - 0.5
			var dmin := 1e9
			var inside := false
			var m := n - 1
			for k in n:
				var ax := px[m]
				var ay := py[m]
				var bx := px[k]
				var by := py[k]
				if ((ay > v) != (by > v)) and u < (bx - ax) * (v - ay) / (by - ay) + ax:
					inside = not inside
				var ex := bx - ax
				var ey := by - ay
				var wx := u - ax
				var wy := v - ay
				var t := maxf(0.0, minf(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
				var dx := wx - ex * t
				var dy := wy - ey * t
				var d := dx * dx + dy * dy
				if d < dmin:
					dmin = d
				m = k
			sdf[j * N + i] = (-1.0 if inside else 1.0) * sqrt(dmin)
	return sdf


static func sstep(a: float, b: float, x: float) -> float:
	var t := maxf(0.0, minf(1.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)


static func vein_at(u: float, v: float) -> float:
	var a := atan2(u, v + 0.1)
	var lines := pow(0.5 + 0.5 * cos(a * 26.0), 8.0)
	var crease := exp(-(u * u) / 0.0009) * 0.6
	return minf(1.0, (lines * 0.8 + crease) * sstep(0.08, 0.4, v) * (1.0 - sstep(0.78, 0.95, v)))


static func _rnd(x: float) -> int:
	return floori(x + 0.5)


static func data_tex(data: PackedByteArray, N: int, srgb: bool, key: String) -> T.Tex:
	var t := T.Tex.new()
	t.uuid = key
	t.width = N
	t.height = N
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	t.user_data["image"] = img
	t.user_data["key"] = key
	t.colorSpace = "srgb" if srgb else "none"
	t.minFilter = "linearMipmapLinear"
	t.magFilter = "linear"
	t.wrap_s = "clamp"
	t.wrap_t = "clamp"
	t.anisotropy = 4
	return t


class Stamp:
	var sdf: PackedFloat32Array
	var N: int
	var px := 16.0

	## Anti-aliased coverage from the bilinear signed distance (px = stamp size in pixels).
	func sharp(u: float, v: float) -> float:  # u in -0.5..0.5, v in 0..1
		var fx := (u + 0.5) * N - 0.5
		var fy := v * N - 0.5
		var i := floori(fx)
		var j := floori(fy)
		if i < 0 or j < 0 or i >= N - 1 or j >= N - 1:
			return 0.0
		var tx := fx - i
		var ty := fy - j
		var o := j * N + i
		var d := (sdf[o] * (1.0 - tx) + sdf[o + 1] * tx) * (1.0 - ty) + (sdf[o + N] * (1.0 - tx) + sdf[o + N + 1] * tx) * ty
		return maxf(0.0, minf(1.0, 0.5 - d * px))


static func _blob_dens(blobs: Array, x: float, y: float, k: float) -> float:
	var s := 0.0
	for b in blobs:
		var dx: float = (x - b.x) / b.rx
		var dy: float = (y - b.y) / b.ry
		s += exp(-(dx * dx + dy * dy) * k)
	return minf(1.0, s)


static func create_petal_textures(rng: Rng) -> Dictionary:
	var N := 128
	var sdf := make_sdf(N)
	var shape := PackedByteArray()
	shape.resize(N * N * 4)
	var color := PackedByteArray()
	color.resize(N * N * 4)
	var aa := 1.3 / N
	# painted colours (sRGB 0..1): claw (base) a deeper pink, body pale, tip lightest
	var c_base := [0.93, 0.66, 0.76]
	var c_body := [0.975, 0.925, 0.945]
	var c_tip := [0.985, 0.95, 0.96]
	for j in N:
		var v := (j + 0.5) / N
		for i in N:
			var u := (i + 0.5) / N - 0.5
			var d: float = sdf[j * N + i]
			var sharp := maxf(0.0, minf(1.0, 0.5 - d / aa))
			var edge := 1.0 - sstep(0.0, 0.11, -d)
			var vein := vein_at(u, v)
			var soft := sstep(0.12, -0.16, d)
			var o := (j * N + i) * 4
			shape[o] = _rnd(sharp * 255.0)
			shape[o + 1] = _rnd(edge * 255.0)
			shape[o + 2] = _rnd(vein * 255.0)
			shape[o + 3] = _rnd(soft * 255.0)
			var kb := 1.0 - sstep(0.02, 0.36, v)
			var kt := sstep(0.7, 1.0, v)
			for c in 3:
				var x: float = c_body[c] * (1.0 - kb) + c_base[c] * kb
				x = x * (1.0 - kt * 0.6) + c_tip[c] * kt * 0.6
				x *= 1.0 - 0.05 * vein
				x *= 1.0 + 0.02 * edge  # very slightly lighter rim
				color[o + c] = _rnd(minf(1.0, x) * 255.0)
			# colour texture alpha: slightly dilated so mip levels don't darken the rim
			color[o + 3] = _rnd(sharp * 255.0)
	# bleed rim colours outward (avoid dark fringes in mipmaps where alpha = 0)
	for j in N:
		for i in N:
			var o := (j * N + i) * 4
			if color[o + 3] > 0:
				continue
			color[o] = _rnd(c_body[0] * 255.0)
			color[o + 1] = _rnd(c_body[1] * 255.0)
			color[o + 2] = _rnd(c_body[2] * 255.0)
	var shape_tex := data_tex(shape, N, false, "petals-shape")
	var color_tex := data_tex(color, N, true, "petals-color")

	var st := Stamp.new()
	st.sdf = sdf
	st.N = N
	# --------------------------------------------------------------- river rafts 2x2 atlas
	var RN := 512
	var CELL := 256
	var raft := PackedByteArray()
	raft.resize(RN * RN * 4)
	var acc := PackedFloat32Array()  # premultiplied accumulation
	acc.resize(RN * RN * 4)
	for cell in 4:
		var ox := (cell % 2) * CELL
		var oy := (cell / 2) * CELL
		# organic blob: union of 3-6 ellipses elongated along u (the flow direction)
		var blobs: Array = []
		# cells 0,1: rounded clumps; cells 2,3: long ribbons that gather along the banks
		var ribbon := cell >= 2
		var nb := 5 + floori(rng.f() * 3.0) if ribbon else 3 + floori(rng.f() * 4.0)
		for b in nb:
			if ribbon:
				var bx := 0.12 + (b + rng.f() * 0.6) / nb * 0.78
				var by := 0.5 + (rng.f() - 0.5) * 0.12
				var brx := 0.1 + rng.f() * 0.1
				var bry := 0.045 + rng.f() * 0.04
				blobs.append({"x": bx, "y": by, "rx": brx, "ry": bry})
			else:
				var bx := 0.5 + (rng.f() - 0.5) * 0.46
				var by := 0.5 + (rng.f() - 0.5) * 0.3
				var brx := 0.14 + rng.f() * 0.2
				var bry := 0.08 + rng.f() * 0.1
				blobs.append({"x": bx, "y": by, "rx": brx, "ry": bry})
		# underlying sheet where the raft is dense (so no water shows through its core)
		for py in CELL:
			for px in CELL:
				var x := (px + 0.5) / CELL
				var y := (py + 0.5) / CELL
				var edge_fade := minf(1.0, minf(minf(x, 1.0 - x), minf(y, 1.0 - y)) / 0.08)
				var a := maxf(0.0, minf(1.0, (_blob_dens(blobs, x, y, 1.6) * edge_fade - 0.62) / 0.12))
				if a <= 0.0:
					continue
				var o := ((oy + py) * RN + ox + px) * 4
				var m := 0.9 + 0.06 * sin(px * 0.21 + py * 0.13) * sin(py * 0.17 - px * 0.07)
				acc[o] = 0.95 * m * a
				acc[o + 1] = 0.83 * m * a
				acc[o + 2] = 0.87 * m * a
				acc[o + 3] = a
		var stamps := 3200
		for k in stamps:
			var x := 0.05 + rng.f() * 0.9
			var y := 0.05 + rng.f() * 0.9
			var dn := _blob_dens(blobs, x, y, 1.6)
			if rng.f() > dn * 1.25:
				continue
			var size := (0.03 + rng.f() * 0.02) * CELL  # petal length in px
			st.px = size
			var ang := rng.f() * PI * 2.0
			var ca := cos(ang)
			var sa := sin(ang)
			var tone: float = rng.f()
			var col := [0.97 - tone * 0.05, 0.9 - tone * 0.17, 0.93 - tone * 0.12]
			var dim := 0.9 + rng.f() * 0.1 - (1.0 - dn) * 0.05
			var cx := ox + x * CELL
			var cy := oy + y * CELL
			var R := size * 0.6
			for py in range(floori(cy - R), ceili(cy + R) + 1):
				if py < oy or py >= oy + CELL:
					continue
				for px in range(floori(cx - R), ceili(cx + R) + 1):
					if px < ox or px >= ox + CELL:
						continue
					var dx := (px + 0.5 - cx) / size
					var dy := (py + 0.5 - cy) / size
					var lu := (dx * ca + dy * sa) / 0.8
					var lv := (-dx * sa + dy * ca) + 0.5
					var a := st.sharp(lu, lv)
					if a <= 0.0:
						continue
					var shade := dim * (1.0 - 0.12 * (1.0 - lv))  # a touch deeper at the claw
					var o := (py * RN + px) * 4
					var inv := 1.0 - a
					acc[o] = acc[o] * inv + col[0] * shade * a
					acc[o + 1] = acc[o + 1] * inv + col[1] * shade * a
					acc[o + 2] = acc[o + 2] * inv + col[2] * shade * a
					acc[o + 3] = acc[o + 3] * inv + a
	for i in RN * RN:
		var o := i * 4
		var a: float = acc[o + 3]
		if a > 0.001:
			raft[o] = _rnd(minf(1.0, acc[o] / a) * 255.0)
			raft[o + 1] = _rnd(minf(1.0, acc[o + 1] / a) * 255.0)
			raft[o + 2] = _rnd(minf(1.0, acc[o + 2] / a) * 255.0)
		else:
			raft[o] = 242
			raft[o + 1] = 220
			raft[o + 2] = 228
		raft[o + 3] = _rnd(minf(1.0, a) * 255.0)
	var raft_tex := data_tex(raft, RN, true, "petals-raft")

	# --------------------------------------------------------------- ground carpet patches, 2x2 atlas
	# cells 0,1: clumpy drifts; cells 2,3: wind-combed streaks (elongated along u). Loose petals at the
	# ragged edges, overlapping petals in the core, no solid sheet (the paving shows between).
	var PN := 1024
	var PC := 512
	var pacc := PackedFloat32Array()
	pacc.resize(PN * PN * 4)
	for cell in 4:
		var ox := (cell % 2) * PC
		var oy := (cell / 2) * PC
		var streaky := cell >= 2
		var blobs: Array = []
		var nb := 3 + floori(rng.f() * 2.0) if streaky else 4 + floori(rng.f() * 4.0)
		for b in nb:
			if streaky:
				var bx := 0.5 + (rng.f() - 0.5) * 0.4
				var by := 0.5 + (rng.f() - 0.5) * 0.3
				var brx := 0.2 + rng.f() * 0.18
				var bry := 0.12 + rng.f() * 0.12
				blobs.append({"x": bx, "y": by, "rx": brx, "ry": bry})
			else:
				var bx := 0.5 + (rng.f() - 0.5) * 0.46
				var by := 0.5 + (rng.f() - 0.5) * 0.46
				var brx := 0.08 + rng.f() * 0.14
				var bry := 0.07 + rng.f() * 0.12
				blobs.append({"x": bx, "y": by, "rx": brx, "ry": bry})
		# streak cells are laid on patches 3x longer than wide: stamp petals 3x taller in v so they
		# come out undistorted on the ground
		var AV := 3.0 if streaky else 1.0
		var stamps := 3800 if streaky else 2600
		for k in stamps:
			var x := 0.04 + rng.f() * 0.92
			var y := 0.04 + rng.f() * 0.92
			var dn := _blob_dens(blobs, x, y, 1.3)
			if rng.f() > dn * 1.1 + 0.012:
				continue
			var size := (0.015 + rng.f() * 0.007 if streaky else 0.026 + rng.f() * 0.012) * PC
			st.px = size
			var ang: float
			if streaky:
				var a0 := (rng.f() - 0.5) * 1.4
				ang = a0 + (0.0 if rng.f() < 0.5 else PI)
			else:
				ang = rng.f() * PI * 2.0
			var ca := cos(ang)
			var sa := sin(ang)
			var tone: float = rng.f()
			var aged: bool = rng.f() < 0.05
			var col := [0.84, 0.7, 0.66] if aged else [0.975 - tone * 0.04, 0.9 - tone * 0.2, 0.93 - tone * 0.14]
			var dim := 0.93 + rng.f() * 0.07
			var cx := ox + x * PC
			var cy := oy + y * PC
			var R := size * 0.6
			for py in range(floori(cy - R * AV), ceili(cy + R * AV) + 1):
				if py < oy + 1 or py >= oy + PC - 1:
					continue
				for px in range(floori(cx - R), ceili(cx + R) + 1):
					if px < ox + 1 or px >= ox + PC - 1:
						continue
					var dx := (px + 0.5 - cx) / size
					var dy := (py + 0.5 - cy) / (size * AV)
					var lu := (dx * ca + dy * sa) / 0.78
					var lv := (-dx * sa + dy * ca) + 0.5
					var a := st.sharp(lu, lv)
					if a <= 0.0:
						continue
					var shade := dim * (1.0 - 0.14 * (1.0 - lv))
					var o := (py * PN + px) * 4
					var inv := 1.0 - a
					# a hint of contact shadow where a petal overlaps another
					var under := 0.94 if pacc[o + 3] > 0.5 else 1.0
					pacc[o] = pacc[o] * inv * under + col[0] * shade * a
					pacc[o + 1] = pacc[o + 1] * inv * under + col[1] * shade * a
					pacc[o + 2] = pacc[o + 2] * inv * under + col[2] * shade * a
					pacc[o + 3] = pacc[o + 3] * inv + a
	var pdat := PackedByteArray()
	pdat.resize(PN * PN * 4)
	for i in PN * PN:
		var o := i * 4
		var a: float = pacc[o + 3]
		if a > 0.001:
			pdat[o] = _rnd(minf(1.0, pacc[o] / a) * 255.0)
			pdat[o + 1] = _rnd(minf(1.0, pacc[o + 1] / a) * 255.0)
			pdat[o + 2] = _rnd(minf(1.0, pacc[o + 2] / a) * 255.0)
		else:
			pdat[o] = 244
			pdat[o + 1] = 214
			pdat[o + 2] = 224
		pdat[o + 3] = _rnd(minf(1.0, a) * 255.0)
	var patch_tex := data_tex(pdat, PN, true, "petals-patch")
	return {"shapeTex": shape_tex, "colorTex": color_tex, "raftTex": raft_tex, "patchTex": patch_tex}
