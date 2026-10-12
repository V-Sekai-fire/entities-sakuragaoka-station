# shopsA/intKonbini.js: W1 HIDAMARI MART interior, all modelled: tiled floor, ceiling fixtures and AC
# cassettes, gondolas with individually instanced products, end caps, reach-in coolers with doors,
# handles and drinks, open chilled case (bento, onigiri, sandwiches), register counter (POS, card
# readers, printers, scanners), hot-snack warmer, steamer, self coffee machine + cup stacks, back
# counter with microwaves, ATM, copier, multimedia ticket terminal, magazine rack with single
# magazines, basket stack, eat-in counter, back-room door. Only printed things (labels, screens,
# signs, price rails) are textures (blank atlas regions here).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const GM = preload("res://addons/sakuragaoka_station/world/shopsA/geom.gd")

## product templates (sizes in metres; w = diameter for round things)
const TPL := {
	"bagL": {"kind": "bag", "w": [0.2, 0.24], "h": [0.27, 0.29], "d": 0.075, "vars": [0, 1, 2, 3, 6, 7, 9], "deep": 2, "n": [2, 3]},
	"bagM": {"kind": "bag", "w": [0.15, 0.18], "h": [0.21, 0.24], "d": 0.06, "vars": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11], "deep": 2, "n": [2, 4]},
	"bagS": {"kind": "bag", "w": [0.1, 0.12], "h": [0.15, 0.17], "d": 0.045, "vars": [4, 5, 6, 8, 11], "deep": 2, "n": [2, 4]},
	"bread": {"kind": "bag", "w": [0.17, 0.2], "h": [0.1, 0.13], "d": [0.14, 0.16], "vars": [12, 13, 14, 15], "deep": 2, "n": [2, 3], "stack": 2},
	"boxL": {"kind": "pbox", "w": [0.17, 0.22], "h": [0.2, 0.25], "d": [0.06, 0.08], "vars": [0, 2, 3, 14, 15], "deep": 2, "n": [2, 3]},
	"boxM": {"kind": "pbox", "w": [0.1, 0.14], "h": [0.13, 0.17], "d": [0.04, 0.06], "vars": [0, 1, 2, 4, 5, 6, 12, 13, 15], "deep": 2, "n": [2, 4]},
	"boxS": {"kind": "pbox", "w": [0.06, 0.08], "h": [0.08, 0.1], "d": 0.03, "vars": [1, 5, 6, 13, 4], "deep": 2, "n": [3, 5], "stack": 2},
	"cupL": {"kind": "cupmen", "lo": "cupLo", "w": 0.13, "h": 0.1, "vars": [0, 1, 2, 3, 4, 5, 6, 7], "deep": 2, "n": [2, 3], "stack": 2},
	"cup": {"kind": "cupmen", "lo": "cupLo", "w": 0.1, "h": 0.085, "vars": [0, 1, 2, 3, 4, 5, 6, 7], "deep": 2, "n": [2, 4], "stack": 2},
	"retort": {"kind": "pbox", "w": 0.14, "h": 0.19, "d": 0.04, "vars": [7, 11], "deep": 2, "n": [3, 4]},
	"tissue": {"kind": "pbox", "w": 0.24, "h": 0.09, "d": 0.12, "vars": [8], "deep": 2, "n": [3, 4], "stack": 3},
	"mask": {"kind": "pbox", "w": 0.18, "h": 0.1, "d": 0.09, "vars": [9], "deep": 2, "n": [2, 3], "stack": 2},
	"paste": {"kind": "pbox", "w": 0.19, "h": 0.045, "d": 0.04, "vars": [10], "deep": 2, "n": [2, 3], "stack": 4},
	"bottleL": {"kind": "pet", "lo": "petLo", "w": 0.1, "h": 0.31, "vars": [0, 3, 7, 11, 2], "deep": 2, "n": [2, 3]},
	"detergent": {"kind": "pet", "lo": "petLo", "w": 0.085, "h": 0.24, "vars": [3, 7, 12, 15], "deep": 2, "n": [2, 3]},
	"canF": {"kind": "can", "lo": "canLo", "w": 0.085, "h": 0.045, "vars": [8, 13, 3, 11], "deep": 2, "n": [3, 4], "stack": 3},
	"pet": {"kind": "pet", "lo": "petLo", "w": 0.066, "h": 0.205, "vars": [0, 1, 3, 5, 7], "deep": 2, "n": [2, 3]},
	"can": {"kind": "can", "lo": "canLo", "w": 0.066, "h": 0.122, "vars": [0, 1, 2, 3, 4], "deep": 2, "n": [3, 4]},
	"canL": {"kind": "can", "lo": "canLo", "w": 0.066, "h": 0.165, "vars": [2, 3, 10, 11], "deep": 2, "n": [2, 3]},
	"carton": {"kind": "carton", "w": 0.07, "h": 0.2, "d": 0.07, "vars": [0, 1, 2, 3, 4, 5, 6], "deep": 2, "n": [2, 3]},
	"cartonS": {"kind": "carton", "w": 0.06, "h": 0.12, "d": 0.045, "vars": [0, 1, 2, 6], "deep": 2, "n": [3, 4]},
}

static var _pad = null


## {...a, ...b}
static func mix(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	for k in b:
		r[k] = b[k]
	return r


static func white(r, lo: float = 0.9) -> Color:
	var v: float = lo + r.f() * (1.0 - lo)
	return Color(v, v, v)


static func rng_range(v, r) -> float:
	if v is Array:
		return v[0] + r.f() * (v[1] - v[0])
	return v


## fill a shelf row in group-local space: x0..x1 along the shelf, products face +z, front edge at zf
static func fill(G, g, x0: float, x1: float, y: float, zf: float, zb: float, tpls: Array, r, o: Dictionary = {}) -> void:
	var x := x0
	var tries := 0
	while x < x1 - 0.03 and tries < 8:
		var t: Dictionary = r.pick(tpls)
		var w := rng_range(t.w, r)
		var h := rng_range(t.h, r)
		var d := rng_range(t.d, r) if t.has("d") else w
		var tn = t.get("n")
		var n: int = r.rint(tn[0] if tn != null else 1, tn[1] if tn != null else 3)
		var v = r.pick(o.vars if o.get("vars") else t.vars)
		var placed := 0
		for f in n:
			if x + w > x1:
				break
			var xc := x + w / 2.0
			var z := zf - d / 2.0 - 0.004
			var deep: int = o.deep if o.get("deep") != null else (t.deep if t.get("deep") != null else 2)
			var stack: int = t.stack if t.get("stack") != null else 1
			var dd := 0
			while dd < deep and z - d / 2.0 >= zb - 1e-3:
				var kind: String = t.lo if dd > 0 and t.get("lo") else t.kind
				for s in stack:
					if o.get("maxH") and (s + 1) * h > o.maxH:
						break
					var px: float = xc + (r.f() - 0.5) * 0.004
					var pz: float = z + (r.f() - 0.5) * 0.004
					var col := white(r)
					var ry: float = (r.f() - 0.5) * 0.07
					G.add(kind, g, [px, y + s * (h + 0.001), pz], [w, h, d], col, [0, ry, 0], v)
				z -= d + 0.005
				dd += 1
			x += w + 0.004
			placed += 1
		if not placed:
			tries += 1
			continue
		tries = 0
		x += 0.008 + r.f() * 0.01


static func build_konbini_interior(ctx, C, S, D: Dictionary) -> void:
	var M = C.M
	var A: Dictionary = C.A
	var G = C.G
	var k = S.k
	var FY: float = D.FY
	var CY: float = D.CY
	var IX0: float = D.IX0
	var IX1: float = D.IX1
	var IZ0: float = D.IZ0
	var IZ1: float = D.IZ1
	var gx: float = D.gx
	var TEAL: String = D.TEAL
	var YEL: String = D.YEL
	var rr = ctx.rng("kb.int2")
	G.set_shop("W1", 0.42)

	# materials (interior warm self-light quantised by albedo)
	var mWhite = M.inner("#eceae4", 0.32)
	var mShelf = M.inner("#e2e0d9", 0.32)
	var mBase = M.inner("#cfccc4", 0.25)
	var mKick = M.inner("#8f969d", 0.2)
	var mMetal = M.inner("#b8bdc2", 0.28)
	var mDark = M.inner("#4f5358", 0.16)
	var mInk = M.inner("#3a3346", 0.1)
	var mTealI = M.inner(TEAL, 0.28)
	var mYelI = M.inner(YEL, 0.3)
	var mPeg = M.inner("#dcd9d1", 0.3)
	var mBody = M.inner("#e6e6e2", 0.3)
	var mGlass = ctx.mat.glass({"opacity": 0.05, "streaks": false, "tint": "#c9d6de"})
	var mLamp = M.glow("#fff3dc", 1.3)
	var mLed = M.glow("#f4f9ff", 1.2)
	var mPink = M.inner("#f7d3de", 0.35)
	var mCounter = M.inner("#f1efe9", 0.32)
	var mTop = M.inner("#d6d2c8", 0.3)

	# printed price rail (flat graphic): one strip reused on every shelf edge
	var rRail: Dictionary = A.inner.region(512, 24, null, {"bg": "#f7f5ef"})
	var rail := func(kk, ln: float, y: float, z: float) -> void:
		var x := -ln / 2.0
		while x < ln / 2.0 - 0.05:
			var w := minf(1.2, ln / 2.0 - x)
			S.card(rRail, w - 0.01, 0.036, [x + w / 2.0, y, z], null, null, kk)
			x += 1.2

	# ---------------- floor: grout base + individual tiles
	if true:
		var cx := (IX0 + IX1) / 2.0
		var cz := (IZ0 + IZ1) / 2.0
		var fl = k.plane(IX1 - IX0, IZ1 - IZ0, M.inner("#b9b6ae", 0.2), [cx, FY + 0.002, cz], [-PI / 2, 0, 0])
		fl.cast_shadow = false
		var ts := 0.4
		var gap := 0.008
		var ix := 0
		var x := IX0
		while x < IX1 - 1e-3:
			var iz := 0
			var z := IZ0
			while z < IZ1 - 1e-3:
				var w := minf(ts, IX1 - x) - gap
				var d := minf(ts, IZ1 - z) - gap
				var base := 0.93 if (ix + iz) % 2 else 0.9
				var s: float = base + rr.f() * 0.04
				var c0 := T.color("#f1efe8")
				G.add("tile", S, [x + gap / 2.0 + w / 2.0, FY + 0.005, z + gap / 2.0 + d / 2.0], [w, 1, d], Color(c0.r * s, c0.g * s, c0.b * s))
				z += ts
				iz += 1
			x += ts
			ix += 1
		# entrance mat (woven, raised a little)
		k.box(1.7, 0.012, 0.75, M.inner("#4f5a66", 0.12), [1.0, FY + 0.012, -3.25])
		var rMat: Dictionary = A.inner.region(200, 80)
		S.card(rMat, 1.6, 0.64, [1.0, FY + 0.0185, -3.25], [-PI / 2, 0, 0])

	# ---------------- ceiling: light fixtures, AC cassettes, detectors, speakers, camera domes, mirror
	if true:
		var mFix = M.inner("#f3f1eb", 0.45)
		for z in [-4.1, -6.1, -8.1, -10.1]:
			for x in [-4.2, -1.6, 1.0, 3.6]:
				k.box(1.62, 0.055, 0.3, mFix, [x, CY - 0.028, z])
				k.box(1.5, 0.02, 0.22, mLamp, [x, CY - 0.062, z])
				for s in [-1, 1]:
					k.box(0.04, 0.03, 0.3, mMetal, [x + s * 0.79, CY - 0.07, z])
		for q in [[-0.3, -7.1], [3.6, -7.1]]:
			var x: float = q[0]
			var z: float = q[1]
			k.box(0.92, 0.035, 0.92, mFix, [x, CY - 0.018, z])
			for i in 7:
				k.box(0.5, 0.012, 0.03, M.inner("#c9c9c4", 0.28), [x, CY - 0.04, z - 0.21 + i * 0.07])
			for e in [[0, 0.37, 0], [0, -0.37, 0], [0.37, 0, PI / 2], [-0.37, 0, PI / 2]]:
				var dx: float = e[0]
				var dz: float = e[1]
				k.box(0.62, 0.012, 0.08, M.inner("#dcdad3", 0.3), [x + dx, CY - 0.05, z + dz], [T.sign(dz) * 0.5 if dz else 0.0, e[2], -T.sign(dx) * 0.5 if dx else 0.0])
		for q in [[-2.9, -5.1], [2.3, -9.1], [4.9, -4.2]]:
			k.cyl(0.06, 0.07, 0.035, mWhite, [q[0], CY - 0.018, q[1]], null, 12)
			k.cyl(0.012, 0.012, 0.012, M.glow("#ff7a6a", 1.0), [q[0] + 0.035, CY - 0.04, q[1]], null, 6)
		for q in [[-1.6, -9.1], [3.6, -5.1]]:
			k.cyl(0.11, 0.11, 0.015, mWhite, [q[0], CY - 0.008, q[1]], null, 16)
			k.cyl(0.08, 0.08, 0.004, M.inner("#b9bcc0", 0.2), [q[0], CY - 0.017, q[1]], null, 16)
		for q in [[-5.5, -3.2], [5.45, -11.45]]:
			k.cyl(0.09, 0.09, 0.02, mWhite, [q[0], CY - 0.01, q[1]], null, 14)
			k.mesh(Geo.sphere(0.075, 12, 6, 0, PI * 2, PI / 2, PI / 2), M.inner("#3f3d45", 0.1), [q[0], CY - 0.02, q[1]])
		# convex security mirror in the back corner
		var mg = S.k.group([-1.5, 2.86, IZ0 + 0.03], 0)
		var km = ctx.kit(mg)
		km.box(0.04, 0.04, 0.18, mMetal, [0, 0, 0.09])
		km.mesh(Geo.sphere(0.28, 16, 8, 0, PI * 2, 0, 0.55), M.inner("#c7d2da", 0.45), [0, 0, 0.18 - 0.24], [PI / 2, 0, 0])
		km.mesh(Geo.torus(0.146, 0.012, 5, 20), M.inner("#e9a23b", 0.3), [0, 0, 0.185])

	# ---------------- gondolas
	var GH := 1.42
	var LEV := [0.13, 0.46, 0.79, 1.12]
	var rPOP: Dictionary = A.inner.region(200, 90)
	var rNew: Dictionary = A.inner.region(120, 60)
	var PLAN := {
		"snacks": [[TPL.bagL], [TPL.bagM], [TPL.bagM, TPL.boxM], [TPL.bagS, TPL.boxS]],
		"sweets": [[TPL.boxL], [TPL.boxM], [TPL.bagS, TPL.boxM], [TPL.boxS]],
		"noodle": [[TPL.cupL], [TPL.cup], [TPL.retort, TPL.boxM], [TPL.bagM]],
		"bread": [[TPL.bread], [TPL.bread], [TPL.boxM, TPL.bagS], [TPL.bagM, TPL.boxS]],
		"daily": [[TPL.tissue], [TPL.detergent], [TPL.paste, TPL.mask], "pegs"],
		"grocery": [[TPL.bottleL], [TPL.canF], [TPL.boxM, TPL.retort], "pegs"],
	}
	var peg_row := func(g, x0: float, x1: float, y_hook: float, z_back: float, r, vars: Array) -> void:
		var x := x0 + 0.07
		while x < x1 - 0.06:
			G.add("stem", g, [x, y_hook, z_back], [0.007, 0.17, 0.007], "#c9ced3", [PI / 2, 0, 0])
			var v = r.pick(vars)
			var n: int = r.rint(2, 4)
			for j in n:
				var col := white(r)
				var ry: float = (r.f() - 0.5) * 0.08
				var rz: float = (r.f() - 0.5) * 0.03
				G.add("blister", g, [x, y_hook - 0.14, z_back + 0.15 - j * 0.028], [0.092, 0.14, 0.012], col, [0, ry, rz], v)
			x += 0.13
	var gondola := func(cx: float, z0: float, z1: float, plans: Array) -> void:
		var ln := z1 - z0
		var cz := (z0 + z1) / 2.0
		k.box(0.05, GH - 0.13, ln, mPeg, [cx, FY + 0.13 + (GH - 0.13) / 2.0, cz])
		k.box(0.12, 0.035, ln + 0.04, mWhite, [cx, FY + GH + 0.017, cz])
		var nm := maxi(2, int(T.js_round(ln / 1.25)))
		var ml := ln / nm
		for i in nm + 1:
			k.box(0.07, GH, 0.04, mWhite, [cx, FY + GH / 2.0, z0 + i * ml])
		var sds := [-1, 1]
		for si in 2:
			var sd: int = sds[si]
			var g = S.k.group([cx, FY, cz], sd * PI / 2.0)
			var kg = ctx.kit(g)
			kg.box(ln, 0.13, 0.42, mBase, [0, 0.065, 0.245])
			kg.box(ln, 0.1, 0.012, mKick, [0, 0.05, 0.458])
			for li in range(1, 4):
				var y: float = LEV[li]
				kg.box(ln - 0.01, 0.02, 0.4, mShelf, [0, y - 0.01, 0.245])
				kg.box(ln, 0.044, 0.014, mTealI if li % 2 else mYelI, [0, y - 0.014, 0.448])
				rail.call(kg, ln, y - 0.014, 0.458)
				for i in nm + 1:
					kg.box(0.018, 0.07, 0.36, mMetal, [-ln / 2.0 + i * ml, y - 0.055, 0.22])
			rail.call(kg, ln, 0.08, 0.465)
			var plan: Array = plans[si]
			var r = ctx.rng("kb.g|%s|%d" % [GM.js_str(cx), sd])
			for m2 in nm:
				var mx0 := -ln / 2.0 + m2 * ml + 0.03
				var mx1 := -ln / 2.0 + (m2 + 1) * ml - 0.03
				for li in 4:
					var lv = plan[li]
					if lv is String and lv == "pegs":
						peg_row.call(g, mx0, mx1, LEV[li] + 0.27, 0.04, r, [0, 1, 2, 3, 4, 5, 6, 7])
						continue
					fill(G, g, mx0, mx1, LEV[li], 0.44, 0.06, lv, r, {"maxH": ((LEV[li + 1] - LEV[li]) if li < 3 else (GH - LEV[li])) - 0.03})
		# front end cap (faces the entrance)
		if true:
			var ec = S.k.group([cx, FY, z1], 0)
			var ke = ctx.kit(ec)
			var D2 := 0.34
			for s in [-1, 1]:
				ke.box(0.03, GH, D2, mWhite, [s * 0.435, GH / 2.0, D2 / 2.0])
			ke.box(0.84, GH - 0.13, 0.02, mPink, [0, 0.13 + (GH - 0.13) / 2.0, 0.012])
			ke.box(0.87, 0.13, D2, mBase, [0, 0.065, D2 / 2.0])
			ke.box(0.87, 0.1, 0.012, mKick, [0, 0.05, D2 + 0.002])
			for y in [0.52, 0.9]:
				ke.box(0.84, 0.02, D2 - 0.02, mShelf, [0, y - 0.01, D2 / 2.0])
				ke.box(0.86, 0.044, 0.014, mPink, [0, y - 0.014, D2 - 0.002])
			ke.box(0.9, 0.3, 0.03, mPink, [0, GH + 0.2, 0.02])
			S.card(rPOP, 0.6, 0.27, [0, GH + 0.2, 0.037], null, null, ke)
			S.card(rNew, 0.24, 0.12, [0.3, 1.2, D2 - 0.05], [0, -0.2, 0], null, ke)
			var r = ctx.rng("kb.ec" + GM.js_str(cx))
			fill(G, ec, -0.41, 0.41, 0.13, D2 - 0.02, 0.03, [mix(TPL.pet, {"vars": [10]}), mix(TPL.carton, {"vars": [7]})], r, {"deep": 3})
			fill(G, ec, -0.41, 0.41, 0.52, D2 - 0.02, 0.03, [mix(TPL.boxM, {"vars": [12, 13]})], r, {"deep": 3})
			fill(G, ec, -0.41, 0.41, 0.9, D2 - 0.02, 0.03, [mix(TPL.bagM, {"vars": [10]}), mix(TPL.boxS, {"vars": [13]})], r, {"deep": 2, "maxH": 0.3})
		# back end cap (thin peg display facing the coolers)
		if true:
			var bc = S.k.group([cx, FY, z0], PI)
			var kb = ctx.kit(bc)
			kb.box(0.86, GH - 0.13, 0.02, mPeg, [0, 0.13 + (GH - 0.13) / 2.0, 0.01])
			kb.box(0.86, 0.13, 0.16, mBase, [0, 0.065, 0.08])
			var r = ctx.rng("kb.bc" + GM.js_str(cx))
			for y in [0.55, 0.85, 1.15]:
				peg_row.call(bc, -0.43, 0.43, y + 0.2, 0.02, r, [0, 2, 3, 5, 6, 7])
		S.box(cx, cz + 0.07, 0.92, ln + 0.54, -1, FY + GH + 0.4)
	gondola.call(-2.65, -9.8, -4.6, [PLAN.snacks, PLAN.sweets])
	gondola.call(-0.2, -9.8, -4.6, [PLAN.noodle, PLAN.bread])
	gondola.call(2.3, -9.8, -4.6, [PLAN.daily, PLAN.grocery])

	# hanging category signs (printed boards on wires)
	for e in [["お菓子", "#e8506a", -1.45, -6.6], ["日用品・食品", TEAL, 1.05, -6.6], ["ドリンク", "#3f7fb5", 1.6, -10.5], ["お弁当・おにぎり", "#e9a23b", -3.6, -10.5]]:
		var x: float = e[2]
		var z: float = e[3]
		var reg: Dictionary = A.inner.region(256, 64)
		k.box(1.12, 0.3, 0.02, mWhite, [x, 2.62, z - 0.005])
		S.card(reg, 1.1, 0.28, [x, 2.62, z + 0.007])
		S.card(reg, 1.1, 0.28, [x, 2.62, z - 0.017], [0, PI, 0])
		for dx in [-0.45, 0.45]:
			ctx.wires.add([S.world(x + dx, CY, z), S.world(x + dx, 2.77, z)], {"width": 0.006, "color": "#6d6a80"})

	# ---------------- reach-in coolers (back wall): 8 glass doors
	if true:
		var x0 := -1.4
		var x1 := 4.6
		var n := 8
		var dw := (x1 - x0) / n
		var FZ := -11.02
		var zb := IZ0
		var cx := (x0 + x1) / 2.0
		var depth := FZ - zb
		var sets := ["お茶", "紙パック", "水・炭酸", "ジュース", "スポーツ", "乳飲料", "コーヒー", "エナジー"]
		var mCab = M.inner("#dcdfe2", 0.3)
		k.box(x1 - x0 + 0.1, 0.2, depth + 0.04, mKick, [cx, FY + 0.1, (FZ + zb) / 2.0 + 0.02])
		k.box(x1 - x0 + 0.1, 0.4, depth + 0.1, mCab, [cx, FY + 2.42, (FZ + zb) / 2.0 + 0.05])
		for x in [x0 - 0.03, x1 + 0.03]:
			k.box(0.05, 2.62, depth + 0.1, mCab, [x, FY + 1.31, (FZ + zb) / 2.0 + 0.05])
		k.plane(x1 - x0, 2.02, M.inner("#eef1f2", 0.52), [cx, FY + 1.21, zb + 0.012])
		k.box(x1 - x0, 0.03, depth, M.inner("#c9ced3", 0.3), [cx, FY + 0.215, (FZ + zb) / 2.0])
		var hReg := {}
		for nm in sets:
			if not hReg.has(nm):
				hReg[nm] = A.glow.region(128, 28)
		var PETV := {"お茶": [0, 1, 2, 11], "水・炭酸": [3, 4, 15, 10], "ジュース": [5, 8, 13, 14], "スポーツ": [7, 3, 12, 4], "乳飲料": [12, 6], "コーヒー": [9, 6], "エナジー": [10, 8]}
		var CANV := {"水・炭酸": [8, 7, 1], "ジュース": [9, 6, 5, 14], "コーヒー": [2, 3, 10, 11], "エナジー": [4, 0, 1, 15, 12], "スポーツ": [7, 8]}
		for i in n:
			var xc := x0 + dw * (i + 0.5)
			var nm: String = sets[i]
			var dg = S.k.group([xc, FY, FZ], 0)
			var kd = ctx.kit(dg)
			# door: frame, glass, handle with stand-offs, gasket strip
			var dh := 2.02
			var y0 := 0.2
			kd.box(dw - 0.012, 0.055, 0.045, mDark, [0, y0 + 0.028, 0.03])
			kd.box(dw - 0.012, 0.07, 0.045, mDark, [0, y0 + dh - 0.035, 0.03])
			for s in [-1, 1]:
				kd.box(0.045, dh, 0.045, mDark, [s * (dw / 2.0 - 0.028), y0 + dh / 2.0, 0.03])
			kd.plane(dw - 0.1, dh - 0.12, mGlass, [0, y0 + dh / 2.0, 0.035]).cast_shadow = false
			var hs := -1 if i % 2 else 1
			var hx := hs * (dw / 2.0 - 0.085)
			kd.cyl(0.013, 0.013, 0.78, mMetal, [hx, y0 + 1.05, 0.105], null, 8)
			for yy in [0.72, 1.38]:
				kd.cyl(0.008, 0.008, 0.06, mMetal, [hx, y0 + yy, 0.075], [PI / 2, 0, 0], 6)
			S.card(hReg[nm], dw - 0.08, 0.18, [0, y0 + dh + 0.12, 0.105], null, null, kd)
			# shelves + drinks (behind the glass: z < 0)
			var r = ctx.rng("kb.cool%d" % i)
			for s in 5:
				var y := y0 + 0.03 + s * 0.39
				if s > 0:
					kd.box(dw - 0.05, 0.014, 0.62, mMetal, [0, y - 0.007, -0.36])
				kd.box(dw - 0.05, 0.03, 0.01, M.inner("#f7f5ef", 0.45), [0, y - 0.005, -0.045])
				S.card(rRail, dw - 0.06, 0.028, [0, y - 0.005, -0.039], null, null, kd)
				var hMax := 0.36
				var tp: Array
				if nm == "乳飲料":
					tp = [TPL.carton] if s < 2 else ([TPL.cartonS] if s < 4 else [mix(TPL.pet, {"vars": PETV[nm]})])
				elif nm == "コーヒー" or nm == "エナジー":
					tp = [mix(TPL.pet, {"vars": PETV[nm]})] if s == 0 else ([mix(TPL.canL, {"vars": CANV[nm]})] if s < 3 else [mix(TPL.can, {"vars": CANV[nm]})])
				elif nm == "ジュース":
					tp = [mix(TPL.carton, {"vars": [3, 4, 5]})] if s == 4 else ([mix(TPL.can, {"vars": CANV[nm]})] if s == 3 else [mix(TPL.pet, {"vars": PETV[nm]})])
				elif nm == "水・炭酸":
					tp = [mix(TPL.can, {"vars": CANV[nm]})] if s == 4 else [mix(TPL.pet, {"vars": PETV[nm]})]
				elif nm == "紙パック":
					tp = [mix(TPL.bottleL, {"vars": [0, 2, 3]})] if s < 2 else ([mix(TPL.carton, {"vars": [5, 6, 0]})] if s < 4 else [mix(TPL.cartonS, {"vars": [0, 1, 2, 6]})])
				elif nm == "スポーツ" and s >= 3:
					tp = [mix(TPL.can, {"vars": CANV[nm]})]
				else:
					tp = [mix(TPL.pet, {"vars": PETV[nm]})]
				fill(G, dg, -dw / 2.0 + 0.035, dw / 2.0 - 0.035, y + 0.004, -0.06, -0.5, tp, r, {"maxH": hMax, "deep": 2 if s < 3 else 1})
		for i in range(1, n):
			k.box(0.02, 2.02, 0.03, mLed, [x0 + dw * i, FY + 1.21, FZ - 0.06])
		S.box(cx, (FZ + zb) / 2.0 + 0.06, x1 - x0 + 0.1, depth + 0.16, -1, FY + 2.62)

	# ---------------- open chilled case: bento / onigiri / sandwiches / desserts
	if true:
		var x0 := -5.7
		var x1 := -1.6
		var z0 := IZ0
		var z1 := -11.1
		var cx := (x0 + x1) / 2.0
		var w := x1 - x0
		k.box(w, 0.55, z1 - z0, mBody, [cx, FY + 0.275, (z0 + z1) / 2.0])
		k.box(w, 0.09, 0.05, mMetal, [cx, FY + 0.5, z1 + 0.02])
		for i in 40:
			k.box(0.05, 0.012, 0.03, mDark, [x0 + 0.06 + i * (w - 0.12) / 39.0, FY + 0.556, z1 - 0.02])
		k.box(w, 1.55, 0.1, mBody, [cx, FY + 0.55 + 0.775, z0 + 0.05])
		for x in [x0 + 0.025, x1 - 0.025]:
			k.box(0.05, 1.9, z1 - z0, mBody, [x, FY + 0.55 + 0.95 - 0.2, (z0 + z1) / 2.0])
		k.box(w + 0.02, 0.22, 0.68, mTealI, [cx, FY + 2.12, z0 + 0.34])
		var rOpenH: Dictionary = A.glow.region(360, 40)
		S.card(rOpenH, 2.6, 0.2, [cx, FY + 2.12, z0 + 0.685])
		k.box(w - 0.1, 0.02, 0.06, mLed, [cx, FY + 2.0, z0 + 0.6])
		var shelves := [[0.98, 0.5], [1.34, 0.43], [1.7, 0.36]]
		for sh in shelves:
			var y: float = sh[0]
			var d: float = sh[1]
			k.box(w - 0.1, 0.02, d, M.inner("#dfe3e5", 0.4), [cx, FY + y - 0.01, z0 + 0.1 + d / 2.0])
			k.box(w - 0.1, 0.035, 0.012, M.inner("#f7f5ef", 0.45), [cx, FY + y - 0.02, z0 + 0.1 + d + 0.004])
			S.card(rRail, w - 0.12, 0.03, [cx, FY + y - 0.02, z0 + 0.1 + d + 0.011])
			k.box(w - 0.14, 0.012, 0.04, mLed, [cx, FY + y - 0.03, z0 + 0.14 + d * 0.5])
		var g = S.k.group([cx, FY, 0], 0)
		var r = ctx.rng("kb.open2")
		fill(G, g, -w / 2.0 + 0.07, w / 2.0 - 0.07, 0.56, z1 - 0.04, z0 + 0.12, [{"kind": "bento", "w": [0.2, 0.22], "h": 0.055, "d": 0.16, "vars": [0, 1, 2, 3, 4, 5, 6, 7], "deep": 3, "n": [2, 3], "stack": 2}], r)
		var shz := func(i: int) -> float: return z0 + 0.1 + shelves[i][1]
		fill(G, g, -w / 2.0 + 0.07, w / 2.0 - 0.07, shelves[0][0] + 0.004, shz.call(0) - 0.01, z0 + 0.12, [{"kind": "onigiri", "w": 0.1, "h": 0.092, "d": 0.035, "vars": [0, 1, 2, 3, 4, 5, 6, 7], "deep": 5, "n": [3, 4]}], r)
		fill(G, g, -w / 2.0 + 0.07, w / 2.0 - 0.07, shelves[1][0] + 0.004, shz.call(1) - 0.01, z0 + 0.12, [{"kind": "sando", "w": 0.13, "h": 0.12, "d": 0.055, "vars": [0, 1, 2, 3], "deep": 4, "n": [2, 3]}], r)
		fill(G, g, -w / 2.0 + 0.07, w / 2.0 - 0.07, shelves[2][0] + 0.004, shz.call(2) - 0.01, z0 + 0.12, [mix(TPL.boxS, {"vars": [12, 13, 5], "deep": 4}), mix(TPL.cartonS, {"vars": [0, 1, 6, 7]})], r)
		S.box(cx, (z0 + z1) / 2.0, w, z1 - z0 + 0.04, -1, FY + 2.25)

	# ---------------- register counter
	if true:
		var x0 := -4.9
		var x1 := -4.2
		var z0 := -8.6
		var z1 := -4.2
		var cx := (x0 + x1) / 2.0
		var cz := (z0 + z1) / 2.0
		var ln := z1 - z0
		k.box(x1 - x0, 0.96, ln, mCounter, [cx, FY + 0.48, cz])
		k.box(0.02, 0.1, ln, mTealI, [x1 + 0.005, FY + 0.8, cz])
		k.box(0.02, 0.035, ln, mYelI, [x1 + 0.005, FY + 0.72, cz])
		k.box(0.04, 0.1, ln, mKick, [x1 - 0.02, FY + 0.05, cz])
		k.rbox(x1 - x0 + 0.14, 0.05, ln + 0.08, 0.02, mTop, [cx + 0.05, FY + 0.985, cz])
		var ty := FY + 1.01
		var rScreen: Dictionary = A.glow.region(96, 64)
		var rCust: Dictionary = A.glow.region(96, 48)
		var rPad: Dictionary = A.inner.region(64, 96)
		var rEM: Dictionary = A.glow.region(64, 64)
		for z in [-5.9, -7.6]:
			# cash drawer + POS body
			k.box(0.42, 0.11, 0.44, mDark, [cx - 0.08, ty + 0.055, z])
			k.box(0.01, 0.03, 0.2, mMetal, [cx + 0.135, ty + 0.05, z])
			k.rbox(0.3, 0.1, 0.34, 0.02, M.inner("#5d646c", 0.16), [cx - 0.1, ty + 0.16, z])
			# clerk screen on a stand (faces -x)
			k.cyl(0.02, 0.02, 0.14, mDark, [cx - 0.12, ty + 0.27, z], null, 8)
			var sg = S.k.group([cx - 0.14, ty + 0.4, z], -PI / 2)
			var ks = ctx.kit(sg)
			ks.box(0.34, 0.24, 0.035, mInk, [0, 0, 0], [-0.22, 0, 0])
			S.card(rScreen, 0.3, 0.2, [0, 0.004, 0.019], [-0.22, 0, 0], null, ks)
			# customer display (faces +x) on a pole
			k.cyl(0.012, 0.012, 0.3, mDark, [cx + 0.02, ty + 0.36, z + 0.12], null, 6)
			var cg = S.k.group([cx + 0.03, ty + 0.54, z + 0.12], PI / 2)
			var kc = ctx.kit(cg)
			kc.box(0.2, 0.11, 0.035, mInk, [0, 0, 0], [-0.1, 0, 0])
			S.card(rCust, 0.18, 0.09, [0, 0, 0.019], [-0.1, 0, 0], null, kc)
			# card reader on swivel stand (faces +x)
			k.cyl(0.035, 0.045, 0.03, mDark, [cx + 0.24, ty + 0.015, z - 0.18], null, 10)
			var pg = S.k.group([cx + 0.24, ty + 0.05, z - 0.18], PI / 2)
			var kp = ctx.kit(pg)
			kp.rbox(0.085, 0.17, 0.03, 0.01, mInk, [0, 0.07, 0], [-0.5, 0, 0])
			S.card(rPad, 0.07, 0.13, [0, 0.075, 0.017], [-0.5, 0, 0], null, kp)
			# e-money pad, receipt printer (+ paper), scanner in cradle, coin tray
			k.box(0.12, 0.025, 0.12, mInk, [cx + 0.22, ty + 0.013, z + 0.2])
			S.card(rEM, 0.1, 0.1, [cx + 0.22, ty + 0.027, z + 0.2], [-PI / 2, 0, PI / 2])
			k.rbox(0.18, 0.13, 0.15, 0.02, M.inner("#e8e8e4", 0.34), [cx - 0.2, ty + 0.065, z - 0.3])
			k.box(0.004, 0.06, 0.08, M.inner("#fbfbf8", 0.5), [cx - 0.1, ty + 0.14, z - 0.3], [0, 0, -0.3])
			k.box(0.05, 0.06, 0.07, mDark, [cx + 0.04, ty + 0.03, z - 0.34])
			var sc = S.k.group([cx + 0.04, ty + 0.08, z - 0.34], 0)
			var ksc = ctx.kit(sc)
			ksc.box(0.035, 0.11, 0.04, mInk, [0, 0.02, 0], [0, 0, 0.2])
			ksc.box(0.06, 0.05, 0.07, mInk, [0.03, 0.08, 0], [0, 0, -0.4])
			ksc.box(0.004, 0.03, 0.05, M.glow("#ff6a5a", 1.0), [0.062, 0.07, 0], [0, 0, -0.4])
			k.box(0.16, 0.012, 0.12, M.inner("#b48a62", 0.3), [cx + 0.25, ty + 0.006, z + 0.02])
		# hot-snack warmer (glass case, two trays of individual fried snacks)
		if true:
			var z := -5.02
			var hw := 0.64
			var hd := 0.46
			var hh := 0.5
			var bx := cx + 0.02
			k.box(hd, 0.06, hw, mMetal, [bx, ty + 0.03, z])
			k.box(hd, 0.06, hw, mMetal, [bx, ty + hh - 0.03, z])
			for q in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				k.box(0.025, hh, 0.025, mMetal, [bx + q[0] * (hd / 2.0 - 0.012), ty + hh / 2.0, z + q[1] * (hw / 2.0 - 0.012)])
			k.box(hd - 0.04, 0.012, hw - 0.04, mLamp, [bx, ty + hh - 0.065, z])
			k.plane(hw - 0.04, hh - 0.12, M.glass({"opacity": 0.2}), [bx + hd / 2.0, ty + hh / 2.0, z], [0, PI / 2, 0]).cast_shadow = false
			for s in [-1, 1]:
				k.plane(hd - 0.04, hh - 0.12, M.glass({"opacity": 0.2}), [bx, ty + hh / 2.0, z + s * hw / 2.0], [0, 0, 0]).cast_shadow = false
			k.box(0.02, hh - 0.08, hw - 0.04, M.inner("#e9e6de", 0.4), [bx - hd / 2.0 + 0.01, ty + hh / 2.0, z])
			var hg = S.k.group([bx, ty, z], PI / 2)
			var rs = ctx.rng("kb.hot")
			for e in [[0.07, "chicken"], [0.25, "mixed"]]:
				var ly: float = e[0]
				var items: String = e[1]
				ctx.kit(hg).box(hw - 0.06, 0.012, hd - 0.08, mMetal, [0, ly, 0], [-0.12, 0, 0])
				for i in 6:
					var x := -hw / 2.0 + 0.07 + i * (hw - 0.14) / 5.0
					if items == "chicken":
						for j in 2:
							var px: float = x + (rs.f() - 0.5) * 0.01
							var colr = rs.pick(["#c98a4a", "#d99a50", "#b87a3a"])
							var ry: float = rs.f() * 3
							G.add("blob", hg, [px, ly + 0.01 + j * 0.012, 0.07 - j * 0.12], [0.085, 0.045, 0.1], colr, [0, ry, 0])
					elif i < 2:
						G.add("mcup", hg, [x, ly + 0.01, 0.04], [0.07, 0.08, 0.05], "#d9463b")
						for j in 3:
							G.add("blob", hg, [x + (j - 1) * 0.018, ly + 0.08, 0.04], [0.03, 0.028, 0.03], "#c98a4a")
					elif i < 4:
						for j in 2:
							G.add("blob", hg, [x, ly + 0.01, 0.07 - j * 0.12], [0.08, 0.035, 0.06], "#d9a05a", [0, 0.3, 0])
					else:
						G.add("blob", hg, [x, ly + 0.01, 0.02], [0.05, 0.04, 0.16], "#e8c48a", [0, 0, 0])
						G.add("blob", hg, [x, ly + 0.035, 0.02], [0.028, 0.028, 0.18], "#c9574a")
				S.card(rRail, hw - 0.06, 0.02, [0, ly - 0.006, hd / 2.0 - 0.035], null, null, ctx.kit(hg))
			var rHotS: Dictionary = A.glow.region(160, 30)
			S.card(rHotS, 0.5, 0.09, [bx + hd / 2.0 + 0.003, ty + hh - 0.03, z], [0, PI / 2, 0])
		# steamer (glass box, white buns)
		if true:
			var z := -6.75
			var bx := cx + 0.02
			var sw := 0.38
			var sd := 0.4
			var shh := 0.42
			k.box(sd, 0.05, sw, mMetal, [bx, ty + 0.025, z])
			k.box(sd, 0.04, sw, mMetal, [bx, ty + shh - 0.02, z])
			for q in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				k.box(0.02, shh, 0.02, mMetal, [bx + q[0] * (sd / 2.0 - 0.01), ty + shh / 2.0, z + q[1] * (sw / 2.0 - 0.01)])
			k.box(sd - 0.04, shh - 0.08, sw - 0.04, M.glass({"opacity": 0.3}), [bx, ty + shh / 2.0, z]).cast_shadow = false
			var hg = S.k.group([bx, ty, z], PI / 2)
			for ly in [0.06, 0.22]:
				ctx.kit(hg).box(sw - 0.05, 0.01, sd - 0.06, mMetal, [0, ly, 0])
				for i in 3:
					for j in 2:
						G.add("blob", hg, [-0.1 + i * 0.1, ly + 0.005, 0.07 - j * 0.12], [0.085, 0.06, 0.085], "#f2d0a0" if ly > 0.1 and i == 2 else "#f4f1ea")
			var rMan: Dictionary = A.glow.region(120, 30)
			S.card(rMan, 0.3, 0.075, [bx + sd / 2.0 + 0.003, ty + shh - 0.02, z], [0, PI / 2, 0])
		# donut case
		if true:
			var z := -8.2
			k.box(0.4, 0.02, 0.34, mMetal, [cx, ty + 0.01, z])
			k.box(0.4, 0.3, 0.34, M.glass({"opacity": 0.22}), [cx, ty + 0.17, z]).cast_shadow = false
			var dcols := ["#d99a4a", "#f7d3de", "#8a5a44", "#f2c230", "#f4ecd8", "#d99a4a"]
			for i in 6:
				k.mesh(Geo.torus(0.035, 0.016, 6, 12), M.inner(dcols[i], 0.35), [cx - 0.1 + (i % 2) * 0.2, ty + 0.04 + (i / 2) * 0.09, z - 0.08 + (i % 3) * 0.08], [PI / 2, 0, 0])
		# self-serve coffee machine (faces the customers, +x)
		if true:
			var z := -4.45
			var bx := cx + 0.0
			var cg = S.k.group([bx, ty, z], PI / 2)
			var kc = ctx.kit(cg)
			kc.rbox(0.36, 0.64, 0.42, 0.03, M.inner("#3f3a44", 0.14), [0, 0.32, -0.02])
			kc.box(0.3, 0.2, 0.02, M.inner("#2f2a35", 0.1), [0, 0.46, 0.2])
			var rCof: Dictionary = A.glow.region(96, 64)
			S.card(rCof, 0.26, 0.17, [0, 0.46, 0.212], null, null, kc)
			kc.box(0.24, 0.2, 0.12, M.inner("#1f1c24", 0.05), [0, 0.2, 0.15])
			kc.cyl(0.018, 0.012, 0.05, mMetal, [0, 0.28, 0.14], null, 8)
			kc.box(0.2, 0.015, 0.1, mMetal, [0, 0.105, 0.15])
			for i in 5:
				kc.box(0.18, 0.004, 0.008, M.inner("#6d747c", 0.2), [0, 0.114, 0.11 + i * 0.02])
			kc.box(0.2, 0.12, 0.2, M.glass({"opacity": 0.35, "tint": "#6b4a37"}), [0, 0.7, -0.08]).cast_shadow = false
			kc.box(0.18, 0.08, 0.18, M.inner("#4a2c1e", 0.1), [0, 0.68, -0.08])
			kc.box(0.21, 0.015, 0.21, mInk, [0, 0.765, -0.08])
			G.add("mcup", cg, [0, 0.115, 0.14], [0.08, 0.1, 0.08], "#f4f1e8")
		# coffee side station at the counter end: cup stacks, lids, stirrers, sugar/milk, trash slot
		if true:
			var sx0 := -4.85
			var sx1 := -4.25
			var sz0 := -4.18
			var sz1 := -3.72
			var scx := (sx0 + sx1) / 2.0
			var scz := (sz0 + sz1) / 2.0
			k.box(sx1 - sx0, 0.95, sz1 - sz0, mCounter, [scx, FY + 0.475, scz])
			k.rbox(sx1 - sx0 + 0.04, 0.04, sz1 - sz0 + 0.04, 0.015, mTop, [scx, FY + 0.97, scz])
			k.box(0.2, 0.06, 0.012, mInk, [scx + 0.12, FY + 0.8, sz1 + 0.002])
			var st := FY + 0.99
			for e in [[scx - 0.18, scz - 0.12, 12, "#f4f1e8"], [scx - 0.08, scz - 0.12, 10, "#f4f1e8"], [scx - 0.18, scz + 0.02, 9, "#e8d5c0"], [scx - 0.08, scz + 0.02, 11, "#dfe6ea"]]:
				var x: float = e[0]
				var z: float = e[1]
				k.cyl(0.05, 0.05, 0.3, M.glass({"opacity": 0.3}), [x, st + 0.15, z], null, 12).cast_shadow = false
				for i in int(e[2]):
					G.add("mcup", S, [x, st + 0.01 + i * 0.022, z], [0.075, 0.095, 0.075], e[3])
			for i in 14:
				G.add("cyl", S, [scx + 0.1, st + i * 0.006, scz - 0.12], [0.085, 0.005, 0.085], "#f4f1e8")
			k.cyl(0.03, 0.03, 0.12, M.inner("#b48a62", 0.3), [scx + 0.2, st + 0.06, scz - 0.12], null, 10)
			for i in 9:
				G.add("cyl6", S, [scx + 0.2 + cos(i) * 0.015, st + 0.1, scz - 0.12 + sin(i) * 0.015], [0.004, 0.1, 0.004], "#e8dcc6", [(i % 3 - 1) * 0.08, 0, (i % 2 - 0.5) * 0.12])
			k.box(0.18, 0.06, 0.12, M.inner("#b48a62", 0.3), [scx + 0.14, st + 0.03, scz + 0.08])
			for i in 10:
				G.add("pbox", S, [scx + 0.08 + (i % 5) * 0.028, st + 0.03, scz + 0.05 + (i / 5) * 0.05], [0.022, 0.05, 0.03], white(rr), [0.2, 0, 0], 15 if i % 2 else 9)
			S.box(scx, scz, sx1 - sx0 + 0.04, sz1 - sz0 + 0.04, -1, FY + 1.3)
		S.box(cx + 0.04, cz, x1 - x0 + 0.12, ln + 0.08, -1, FY + 1.05)
		var rRegi: Dictionary = A.inner.region(128, 48)
		k.box(0.02, 0.21, 0.52, mWhite, [x1 + 0.09, 2.62, -6.6])
		S.card(rRegi, 0.5, 0.19, [x1 + 0.101, 2.62, -6.6], [0, PI / 2, 0])
		ctx.wires.add([S.world(x1 + 0.09, CY, -6.85), S.world(x1 + 0.09, 2.72, -6.85)], {"width": 0.006, "color": "#6d6a80"})
		ctx.wires.add([S.world(x1 + 0.09, CY, -6.35), S.world(x1 + 0.09, 2.72, -6.35)], {"width": 0.006, "color": "#6d6a80"})

	# ---------------- back counter behind the clerks: microwaves, hot-water pot, upper shelves of small goods
	if true:
		var bx0 := IX0
		var bx1 := -5.36
		var z0 := -8.6
		var z1 := -4.2
		var bcx := (bx0 + bx1) / 2.0
		var cz := (z0 + z1) / 2.0
		var ln := z1 - z0
		k.box(bx1 - bx0, 0.92, ln, mCounter, [bcx, FY + 0.46, cz])
		k.box(bx1 - bx0 + 0.02, 0.035, ln, mTop, [bcx + 0.01, FY + 0.935, cz])
		for i in 4:
			k.box(0.012, 0.8, ln / 4.0 - 0.02, M.inner("#e6e3db", 0.32), [bx1 + 0.006, FY + 0.47, z0 + (i + 0.5) * ln / 4.0])
			k.box(0.02, 0.1, 0.02, mMetal, [bx1 + 0.015, FY + 0.75, z0 + (i + 0.5) * ln / 4.0 + 0.35])
		var top := FY + 0.95
		for z in [-7.9, -7.3]:
			var mg = S.k.group([bcx + 0.02, top, z], PI / 2)
			var km = ctx.kit(mg)
			km.rbox(0.52, 0.31, 0.4, 0.02, M.inner("#e8e8e4", 0.34), [0, 0.155, 0])
			km.box(0.34, 0.22, 0.01, M.inner("#2f2a35", 0.1), [-0.06, 0.16, 0.2])
			km.box(0.3, 0.18, 0.004, M.glass({"opacity": 0.3}), [-0.06, 0.16, 0.207]).cast_shadow = false
			km.box(0.1, 0.24, 0.01, M.inner("#d9d6ce", 0.3), [0.19, 0.16, 0.2])
			km.box(0.06, 0.02, 0.006, M.glow("#9ff0c0", 0.9), [0.19, 0.24, 0.206])
			km.box(0.02, 0.2, 0.03, mMetal, [0.12, 0.16, 0.215])
			for i in 6:
				km.box(0.02, 0.014, 0.004, M.inner("#8f969d", 0.2), [0.17 + (i % 2) * 0.04, 0.2 - (i / 2) * 0.035, 0.206])
		k.cyl(0.1, 0.11, 0.3, M.inner("#e8e8e4", 0.34), [bcx, top + 0.15, -6.5], null, 14)
		k.cyl(0.08, 0.1, 0.05, M.inner("#b8bdc2", 0.28), [bcx, top + 0.325, -6.5], null, 14)
		k.box(0.06, 0.04, 0.04, mDark, [bcx + 0.11, top + 0.2, -6.5])
		for i in 3:
			k.cyl(0.05, 0.05, 0.1, M.inner("#f4f1e8", 0.45), [bcx, top + 0.05 + i * 0.1, -5.6], [0, 0, 0], 12)
		# upper open shelves with small boxes (medicine, prepaid cards, stationery)
		var ux := IX0 + 0.16
		k.box(0.02, 0.92, ln, M.inner("#e3e1da", 0.3), [IX0 + 0.01, FY + 1.96, cz])
		for zz in [z0 + 0.01, z1 - 0.01]:
			k.box(0.3, 0.92, 0.02, M.inner("#e3e1da", 0.3), [ux, FY + 1.96, zz])
		k.box(0.32, 0.03, ln, mShelf, [ux + 0.01, FY + 1.5, cz])
		var sg = S.k.group([ux + 0.02, FY, cz], PI / 2)
		var r2 = ctx.rng("kb.back2")
		for e in [[1.52, [TPL.boxS]], [1.8, [mix(TPL.boxS, {"vars": [9, 10, 8]})]], [2.1, [{"kind": "blister", "w": 0.09, "h": 0.13, "d": 0.012, "vars": [0, 1, 2, 5], "deep": 4, "n": [3, 5]}]]]:
			var y: float = e[0]
			if y > 1.6:
				ctx.kit(sg).box(ln - 0.02, 0.02, 0.28, mShelf, [0, y - 0.01, 0.0])
			fill(G, sg, -ln / 2.0 + 0.05, ln / 2.0 - 0.05, y, 0.13, -0.12, e[1], r2, {"maxH": 0.26})
		k.box(0.3, 0.03, ln, mShelf, [ux, FY + 2.4, cz])
		S.box(bcx, cz, bx1 - bx0 + 0.04, ln, -1, FY + 2.4)

	# ---------------- back-room door (south wall): frame, steel leaf, window, push/kick plates
	if true:
		var z := -10.25
		var x := IX0 + 0.01
		var dg = S.k.group([x, FY, z], PI / 2)
		var kd = ctx.kit(dg)
		kd.box(0.08, 2.12, 0.05, mMetal, [-0.47, 1.06, 0.02])
		kd.box(0.08, 2.12, 0.05, mMetal, [0.47, 1.06, 0.02])
		kd.box(1.02, 0.08, 0.05, mMetal, [0, 2.08, 0.02])
		kd.box(0.86, 2.02, 0.04, M.inner("#b9c3c8", 0.28), [0, 1.01, 0.03])
		kd.box(0.3, 0.3, 0.01, mMetal, [0.18, 1.55, 0.055])
		kd.plane(0.24, 0.24, M.glass({"opacity": 0.45, "frost": true}), [0.18, 1.55, 0.061]).cast_shadow = false
		kd.box(0.1, 0.3, 0.006, M.inner("#dfe3e5", 0.4), [-0.3, 1.05, 0.053])
		kd.box(0.8, 0.22, 0.006, M.inner("#dfe3e5", 0.4), [0, 0.13, 0.053])
		var rStaff: Dictionary = A.inner.region(160, 48)
		S.card(rStaff, 0.4, 0.12, [0.18, 1.85, 0.056], null, null, kd)

	# ---------------- eat-in counter along the north window, stools, bins
	if true:
		var z0 := -7.6
		var z1 := -3.6
		var cz := (z0 + z1) / 2.0
		k.rbox(0.48, 0.045, z1 - z0, 0.015, M.inner("#b48a62", 0.3), [5.54, FY + 1.0, cz])
		for z in [z0 + 0.2, cz, z1 - 0.2]:
			k.box(0.04, 1.0, 0.04, mMetal, [5.72, FY + 0.5, z])
		k.box(0.02, 0.4, z1 - z0, M.inner("#e6e3db", 0.32), [5.74, FY + 0.78, cz])
		for z in [-4.2, -5.4, -6.6]:
			k.cyl(0.17, 0.16, 0.06, M.inner(TEAL, 0.3), [5.0, FY + 0.73, z], null, 16)
			k.cyl(0.025, 0.025, 0.7, mMetal, [5.0, FY + 0.35, z], null, 8)
			k.cyl(0.2, 0.22, 0.03, mMetal, [5.0, FY + 0.015, z], null, 14)
			k.mesh(Geo.torus(0.13, 0.01, 5, 14), mMetal, [5.0, FY + 0.28, z], [PI / 2, 0, 0])
			S.cyl(5.0, z, 0.2, -1, FY + 0.76)
		k.box(0.14, 0.12, 0.1, M.inner("#e8e4da", 0.3), [5.6, FY + 1.08, -5.0])
		k.box(0.1, 0.02, 0.08, M.inner("#fbfbf8", 0.5), [5.6, FY + 1.15, -5.0])
		var rEat: Dictionary = A.inner.region(160, 48)
		S.card(rEat, 0.6, 0.18, [gx - 0.012, FY + 2.2, -5.6], [0, -PI / 2, 0])
		S.box(5.55, cz, 0.5, z1 - z0, -1, FY + 1.05)
		# two bins (burnable / bottles) at the end of the counter
		for z in [-7.8, -8.09]:
			k.box(0.36, 0.78, 0.27, M.inner("#e3e1da", 0.3), [5.55, FY + 0.39, z])
			k.box(0.02, 0.1, 0.18, M.inner("#3a3346", 0.1), [5.36, FY + 0.66, z])
			var reg: Dictionary = A.inner.region(64, 32)
			S.card(reg, 0.2, 0.1, [5.365, FY + 0.5, z], [0, -PI / 2, 0])
		S.box(5.55, -7.945, 0.38, 0.58, -1, FY + 0.8)

	# ---------------- multimedia ticket terminal, ATM, copier (north-east corner)
	if true:
		# ticket / payment kiosk
		var tg = S.k.group([5.42, FY, -8.5], -PI / 2)
		var kt = ctx.kit(tg)
		kt.rbox(0.5, 1.02, 0.42, 0.03, M.inner("#e6e8ea", 0.34), [0, 0.51, 0])
		kt.box(0.5, 0.06, 0.5, M.inner(TEAL, 0.28), [0, 1.35, -0.02])
		kt.box(0.46, 0.3, 0.1, M.inner("#e6e8ea", 0.34), [0, 1.14, 0.08], [-0.6, 0, 0])
		var rKi: Dictionary = A.glow.region(128, 96)
		S.card(rKi, 0.36, 0.26, [0, 1.15, 0.135], [-0.6, 0, 0], null, kt)
		kt.box(0.2, 0.02, 0.02, mInk, [0, 0.82, 0.211])
		kt.box(0.12, 0.04, 0.02, mInk, [0.12, 0.95, 0.211])
		kt.box(0.3, 0.08, 0.04, M.inner("#b8bdc2", 0.28), [0, 0.62, 0.22])
		var rKs: Dictionary = A.inner.region(128, 32)
		S.card(rKs, 0.44, 0.055, [0, 1.35, 0.232], null, null, kt)
		S.box(5.42, -8.5, 0.5, 0.56, -1, FY + 1.4)
		# ATM
		var ag = S.k.group([5.45, FY, -10.9], -PI / 2)
		var ka = ctx.kit(ag)
		ka.rbox(0.62, 1.55, 0.6, 0.03, M.inner("#c9ced3", 0.28), [0, 0.775, 0])
		for s in [-1, 1]:
			ka.box(0.03, 0.7, 0.2, M.inner("#b8bdc2", 0.28), [s * 0.3, 1.1, 0.38])
		ka.box(0.56, 0.36, 0.14, M.inner("#9aa1a8", 0.22), [0, 1.08, 0.33], [-0.35, 0, 0])
		var rATMscr: Dictionary = A.glow.region(80, 64)
		S.card(rATMscr, 0.28, 0.22, [0, 1.13, 0.41], [-0.35, 0, 0], null, ka)
		S.card(atm_pad(A), 0.11, 0.1, [0.2, 0.98, 0.44], [-1.0, 0, 0], null, ka)
		ka.box(0.12, 0.012, 0.02, mInk, [0.2, 1.24, 0.305])
		ka.box(0.2, 0.05, 0.03, mInk, [-0.08, 0.86, 0.31])
		ka.box(0.3, 0.1, 0.04, M.inner("#5d646c", 0.16), [0, 0.72, 0.31])
		ka.box(0.62, 0.3, 0.62, M.inner("#3f7fb5", 0.28), [0, 1.7, 0])
		var rATMh: Dictionary = A.glow.region(96, 40)
		S.card(rATMh, 0.45, 0.19, [0, 1.7, 0.312], null, null, ka)
		S.box(5.45, -10.9, 0.64, 0.64, -1, FY + 1.9)
		# copier + coin unit
		var cg = S.k.group([5.35, FY, -9.65], -PI / 2)
		var kc = ctx.kit(cg)
		kc.rbox(0.64, 0.86, 0.6, 0.02, M.inner("#e6e6e2", 0.34), [0, 0.43, 0])
		for i in 3:
			kc.box(0.58, 0.005, 0.01, M.inner("#9aa1a8", 0.22), [0, 0.2 + i * 0.2, 0.301])
			kc.box(0.14, 0.02, 0.02, M.inner("#9aa1a8", 0.22), [0, 0.15 + i * 0.2, 0.31])
		kc.box(0.6, 0.12, 0.56, M.inner("#dcdcd8", 0.32), [0, 0.92, -0.02])
		kc.box(0.52, 0.06, 0.4, M.inner("#cfcfca", 0.3), [0, 1.01, -0.04])
		kc.box(0.36, 0.02, 0.24, M.inner("#f4f4f0", 0.4), [0, 1.05, -0.06], [0.08, 0, 0])
		kc.box(0.4, 0.05, 0.16, M.inner("#5d646c", 0.16), [0, 0.9, 0.3], [0.5, 0, 0])
		var rCp: Dictionary = A.glow.region(64, 32)
		S.card(rCp, 0.12, 0.06, [-0.08, 0.93, 0.385], [-1.07, 0, 0], null, kc)
		kc.box(0.3, 0.012, 0.22, M.inner("#f4f4f0", 0.4), [0.2, 0.62, 0.02])
		kc.box(0.2, 0.5, 0.28, M.inner("#c9ced3", 0.28), [0.44, 0.95, 0.12])
		kc.box(0.04, 0.012, 0.012, mInk, [0.44, 1.08, 0.265])
		kc.box(0.05, 0.03, 0.012, M.glow("#ffd9a0", 0.9), [0.44, 1.0, 0.265])
		S.box(5.35, -9.65, 0.66, 0.92, -1, FY + 1.1)

	# ---------------- magazine rack along the front window (magazines face into the shop)
	if true:
		var x0 := 2.75
		var x1 := 5.55
		var z := -3.05
		var w := x1 - x0
		var cx := (x0 + x1) / 2.0
		var rg = S.k.group([cx, FY, z], PI)  # local +z = into the shop
		var kr = ctx.kit(rg)
		kr.box(w, 1.05, 0.03, M.inner("#e3e1da", 0.3), [0, 0.525, -0.19])
		kr.box(w, 0.12, 0.44, M.inner("#cfccc4", 0.25), [0, 0.06, 0])
		for s in [-1, 1]:
			kr.box(0.03, 1.05, 0.44, M.inner("#d9d6ce", 0.3), [s * w / 2.0, 0.525, 0])
		var r = ctx.rng("kb.mag2")
		var n := floori(w / 0.235)
		var sp := (w - 0.06) / n
		for t in 3:
			var y := 0.3 + t * 0.29
			var zz := 0.1 - t * 0.085
			kr.box(w - 0.04, 0.015, 0.14, mShelf, [0, y - 0.008, zz], [0.25, 0, 0])
			kr.box(w - 0.04, 0.05, 0.012, mTealI, [0, y + 0.015, zz + 0.075])
			for i in n:
				var v: int = r.rint(0, 31)
				var nn: int = r.rint(2, 4)
				for j in nn:
					var px: float = -w / 2.0 + 0.03 + sp * (i + 0.5) + (r.f() - 0.5) * 0.01
					var col := white(r)
					var ry: float = (r.f() - 0.5) * 0.04
					G.add("mag", rg, [px, y + 0.004, zz + 0.045 - j * 0.011], [0.2, 0.275, 0.009], col, [-0.26, ry, 0], v)
		for i in n:
			var v: int = r.rint(0, 31)
			for j in 3:
				G.add("cover", rg, [-w / 2.0 + 0.03 + sp * (i + 0.5), 0.12, 0.14 - j * 0.03], [0.13, 0.16, 0.028], white(r), [-0.1, 0, 0], v)
		var rMagSign: Dictionary = A.inner.region(160, 40)
		kr.box(0.84, 0.22, 0.02, mTealI, [0, 1.16, -0.18])
		S.card(rMagSign, 0.8, 0.2, [0, 1.16, -0.168], null, null, kr)
		S.box(cx, z, w, 0.46, -1, FY + 1.05)

	# ---------------- basket stack by the door
	if true:
		var bx := 2.36
		var bz := -3.08
		var mB = M.inner(TEAL, 0.3)
		var mR = M.inner("#e9e6de", 0.34)
		k.box(0.5, 0.05, 0.38, mDark, [bx, FY + 0.025, bz])
		for i in 7:
			var g = S.k.group([bx, FY + 0.05 + i * 0.038, bz], 0)
			var kb = ctx.kit(g)
			var bw := 0.46
			var bd := 0.32
			var bh := 0.22
			kb.box(bw - 0.06, 0.012, bd - 0.06, mB, [0, 0.006, 0])
			for b in 3:
				var y := 0.035 + b * 0.068
				var t := y / bh
				var ww := bw - 0.06 + t * 0.06
				var dd := bd - 0.06 + t * 0.06
				kb.box(ww, 0.04, 0.01, mB, [0, y, dd / 2.0], [-0.12, 0, 0])
				kb.box(ww, 0.04, 0.01, mB, [0, y, -dd / 2.0], [0.12, 0, 0])
				kb.box(0.01, 0.04, dd, mB, [ww / 2.0, y, 0], [0, 0, 0.12])
				kb.box(0.01, 0.04, dd, mB, [-ww / 2.0, y, 0], [0, 0, -0.12])
			kb.box(bw, 0.02, 0.018, mR, [0, bh, bd / 2.0])
			kb.box(bw, 0.02, 0.018, mR, [0, bh, -bd / 2.0])
			kb.box(0.018, 0.02, bd, mR, [bw / 2.0, bh, 0])
			kb.box(0.018, 0.02, bd, mR, [-bw / 2.0, bh, 0])
			if i == 6:
				for s in [-1, 1]:
					kb.mesh(Geo.torus(0.1, 0.008, 4, 10, PI), mR, [s * 0.12, bh + 0.005, 0], [0, PI / 2, s * 0.35])
		var rBk: Dictionary = A.inner.region(96, 32)
		k.box(0.01, 0.6, 0.01, mMetal, [bx + 0.2, FY + 0.6, bz - 0.14])
		S.card(rBk, 0.18, 0.06, [bx + 0.2, FY + 0.95, bz - 0.13])
		S.box(bx, bz, 0.5, 0.38, -1, FY + 0.55)

	# ---------------- seasonal sakura-fair display under the front window (south of the door)
	if true:
		var x0 := -5.5
		var x1 := -0.5
		var z := -3.0
		var cx := (x0 + x1) / 2.0
		var w := x1 - x0
		var mD = M.inner("#f4f1ea", 0.34)
		k.box(w, 0.42, 0.44, mD, [cx, FY + 0.21, z])
		k.box(w, 0.3, 0.2, mD, [cx, FY + 0.57, z + 0.11])
		k.box(w, 0.02, 0.46, mPink, [cx, FY + 0.43, z])
		k.box(w, 0.02, 0.22, mPink, [cx, FY + 0.73, z + 0.11])
		var dg = S.k.group([cx, FY, z], PI)  # products face into the shop
		var r = ctx.rng("kb.sakura2")
		fill(G, dg, -w / 2.0 + 0.05, w / 2.0 - 0.05, 0.44, 0.2, 0.02, [mix(TPL.pet, {"vars": [10], "n": [3, 4]}), mix(TPL.boxM, {"vars": [12, 13]}), mix(TPL.bagM, {"vars": [10]}), mix(TPL.carton, {"vars": [7]})], r, {"deep": 2, "maxH": 0.26})
		fill(G, dg, -w / 2.0 + 0.05, w / 2.0 - 0.05, 0.74, -0.03, -0.2, [mix(TPL.boxS, {"vars": [12, 13]}), mix(TPL.canL, {"vars": [12]})], r, {"deep": 2, "maxH": 0.2})
		k.cyl(0.07, 0.05, 0.36, M.inner("#e9e4d8", 0.35), [-0.8, FY + 0.75 + 0.18, z + 0.12], null, 12)
		var vg = S.k.group([-0.8, FY + 1.1, z + 0.12])
		for i in 5:
			var a := i * 1.3
			var ln := 0.5 + (i % 3) * 0.12
			var tilt := 0.35 + (i % 2) * 0.2
			var br := T.Group.new()
			br.rotation = Vector3(sin(a) * tilt, 0, cos(a) * tilt)
			vg.add(br)
			var kb = ctx.kit(br)
			kb.cyl(0.006, 0.01, ln, M.t("#6a5048"), [0, ln / 2.0, 0], null, 5)
			for j in 8:
				G.add("bud", br, [0.02 if j % 2 else -0.02, ln * (0.3 + j * 0.085), (j % 3 - 1) * 0.02], [0.05, 0.042, 0.05], "#f7d3de" if j % 3 else "#fbe9ef", [j, j * 2, 0])
		k.box(0.02, 0.3, 0.02, M.t("#b8bdc2"), [-3.0, FY + 0.87, z + 0.12])
		S.card(rPOP, 0.5, 0.23, [-3.0, FY + 1.1, z + 0.108], [0, PI, 0])
		S.card(rPOP, 0.5, 0.23, [-3.0, FY + 1.1, z + 0.132])
		S.box(cx, z - 0.02, w, 0.46, -1, FY + 0.9)

	# ---------------- fire extinguisher by the door (moved clear of the baskets)
	if true:
		var ex := -0.25
		var ez := -2.97
		k.cyl(0.075, 0.075, 0.42, M.t("#d9463b"), [ex, FY + 0.25, ez], null, 12)
		k.sphere(0.075, M.t("#d9463b"), [ex, FY + 0.46, ez], 10)
		k.box(0.05, 0.08, 0.05, M.t("#3a3346"), [ex, FY + 0.56, ez])
		k.box(0.1, 0.02, 0.03, M.t("#3a3346"), [ex + 0.04, FY + 0.6, ez])
		k.cyl(0.012, 0.012, 0.36, M.t("#3a3346"), [ex - 0.08, FY + 0.38, ez], [0, 0, 0.12], 5)
		k.cyl(0.08, 0.08, 0.03, M.t("#8a8e94"), [ex, FY + 0.03, ez], null, 12)
		S.cyl(ex, ez, 0.09, -1, FY + 0.6)


## small keypad graphic shared by the ATM (cached module-wide, as the original)
static func atm_pad(A: Dictionary) -> Dictionary:
	if _pad != null:
		return _pad
	_pad = A.inner.region(64, 64)
	return _pad
