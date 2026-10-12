# shopsA/konbini.js: W1, HIDAMARI MART (corner konbini, faces the main street (east) and R3 (north)).
# Lot-local: +z = street (east), +x = north (R3 side). Enterable: automatic doors open as you approach.
# The original also exports two canvas painters (drawProduct, paintShelf) that nothing calls; they
# are canvas work and not ported.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const IntKonbini = preload("res://addons/sakuragaoka_station/world/shopsA/int_konbini.gd")

const TEAL := "#2c9a91"
const TEAL_D := "#227c75"
const YEL := "#f3c14b"
const CREAM := "#f6f3ea"
const INK := "#3a3346"


static func build_konbini(ctx, C) -> Dictionary:
	var M = C.M
	var P = C.P
	var A: Dictionary = C.A
	var S = C.space("W1")
	var k = S.k
	var rr = ctx.rng("shopsA.konbini")
	var FY := 0.30
	var CY := 3.15
	var TOP := 4.35
	var X0 := -6.0
	var X1 := 6.0
	var ZB := -12.0
	var ZF := -2.6
	var WT := 0.2
	var mWall = M.wall("#e8e7e2")
	var _mWall2 = M.wall("#dedcd5")
	var mAlu = M.t("#b8bdc2")
	var _mAluD = M.t("#8f969d")
	var _mTeal = M.t(TEAL)
	var _mYel = M.t(YEL)
	var mIn = M.inner("#efece4", 0.45)
	var mInW = M.inner("#f3f1eb", 0.45)
	var glass = M.glass({"opacity": 0.2})

	# ---------------- ground / foundation
	var mPave = M.concrete("#cfcdc6")
	C.pave(S, -6.5, 6.5, ZF, 0, mPave, {"uv": 2})
	C.pave(S, 6.0, 6.5, -14, ZF, mPave, {"uv": 2})
	C.pave(S, -6.5, 6.5, -14, ZB, mPave, {"uv": 2})
	C.pave(S, -6.5, -6.0, ZB, ZF, mPave, {"uv": 2})
	C.plinth(S, X0 - 0.04, X1 + 0.04, ZB - 0.04, ZF + 0.02, FY, M.concrete("#b4b3ad"), 1)

	# ---------------- shell
	var wallH := TOP - FY
	S.ubox(X1 - X0, wallH, WT, mWall, [0, FY + wallH / 2, ZB + WT / 2], null, 2.5)  # back
	S.ubox(WT, wallH, ZF - ZB, mWall, [X0 + WT / 2, FY + wallH / 2, (ZB + ZF) / 2], null, 2.5)  # south
	var NW0 := -9.1
	var NW1 := -2.9  # north window span (lz)
	S.ubox(WT, wallH, NW0 - ZB, mWall, [X1 - WT / 2, FY + wallH / 2, (ZB + NW0) / 2], null, 2.5)
	S.ubox(WT, wallH, ZF - NW1, mWall, [X1 - WT / 2, FY + wallH / 2, (NW1 + ZF) / 2], null, 2.5)
	var WTOP := 3.05  # top of glazing
	S.ubox(WT, TOP - WTOP, NW1 - NW0, mWall, [X1 - WT / 2, (WTOP + TOP) / 2, (NW0 + NW1) / 2], null, 2.5)
	# front: piers + head wall
	S.ubox(0.3, wallH, WT, mWall, [X0 + 0.15, FY + wallH / 2, ZF - WT / 2], null, 2.5)
	S.ubox(0.3, wallH, WT, mWall, [X1 - 0.15, FY + wallH / 2, ZF - WT / 2], null, 2.5)
	S.ubox(X1 - X0 - 0.6, TOP - WTOP, WT, mWall, [0, (WTOP + TOP) / 2, ZF - WT / 2], null, 2.5)
	# grey skirt band at the foot of the walls
	S.ubox(X1 - X0 + 0.02, 0.16, 0.03, M.t("#a9aaa8"), [0, FY + 0.08, ZB - 0.01])
	S.ubox(0.03, 0.16, ZF - ZB, M.t("#a9aaa8"), [X0 - 0.01, FY + 0.08, (ZB + ZF) / 2])
	# coping
	k.box(X1 - X0 + 0.26, 0.06, 0.3, mAlu, [0, TOP + 0.03, ZF + 0.03])
	k.box(X1 - X0 + 0.06, 0.06, 0.26, mAlu, [0, TOP + 0.03, ZB + 0.1])
	k.box(0.26, 0.06, ZF - ZB + 0.2, mAlu, [X0 + 0.1, TOP + 0.03, (ZB + ZF) / 2])
	k.box(0.3, 0.06, ZF - ZB + 0.24, mAlu, [X1 + 0.03, TOP + 0.03, (ZB + ZF) / 2 + 0.02])
	# roof slab (inside parapet)
	k.box(X1 - X0 - 0.4, 0.1, ZF - ZB - 0.4, M.t("#a8aab0"), [0, 4.0, (ZB + ZF) / 2])

	# ---------------- glazing (front + north)
	var mullion := func(x: float, z: float, h: float, along_z: bool) -> void:
		k.box(0.08 if along_z else 0.07, h, 0.07 if along_z else 0.08, mAlu, [x, FY + h / 2, z])
	var front_panes := [[-5.7, -3.83], [-3.83, -1.97], [-1.97, -0.1], [2.1, 3.9], [3.9, 5.7]]
	var gz := ZF - 0.1
	for ab in front_panes:
		var gl = k.plane(ab[1] - ab[0], WTOP - FY - 0.08, glass, [(ab[0] + ab[1]) / 2, FY + 0.08 + (WTOP - FY - 0.08) / 2, gz])
		gl.cast_shadow = false
	for x in [-5.7, -3.83, -1.97, -0.1, 2.1, 3.9, 5.7]:
		mullion.call(x, gz, WTOP - FY, false)
	k.box(X1 - X0 - 0.6, 0.1, 0.12, mAlu, [0, FY + 0.05, gz])  # bottom rail
	k.box(X1 - X0 - 0.6, 0.08, 0.12, mAlu, [0, WTOP - 0.02, gz])  # head rail
	# door transom
	k.box(2.2, 0.08, 0.1, mAlu, [1.0, FY + 2.24, gz])
	var glt = k.plane(2.2, WTOP - FY - 2.28, glass, [1.0, FY + 2.28 + (WTOP - FY - 2.28) / 2, gz])
	glt.cast_shadow = false
	# north glazing
	var gx := X1 - 0.1
	var north_panes := [[-9.1, -7.03], [-7.03, -4.97], [-4.97, -2.9]]
	for ab in north_panes:
		var gl = k.plane(ab[1] - ab[0], WTOP - FY - 0.08, glass, [gx, FY + 0.08 + (WTOP - FY - 0.08) / 2, (ab[0] + ab[1]) / 2], [0, PI / 2, 0])
		gl.cast_shadow = false
	for z in [-9.1, -7.03, -4.97, -2.9]:
		mullion.call(gx, z, WTOP - FY, true)
	k.box(0.12, 0.1, NW1 - NW0, mAlu, [gx, FY + 0.05, (NW0 + NW1) / 2])
	k.box(0.12, 0.08, NW1 - NW0, mAlu, [gx, WTOP - 0.02, (NW0 + NW1) / 2])

	# ---------------- sign band (lit)
	var bandY0 := 3.22
	var bandY1 := 4.02
	var bandH := bandY1 - bandY0
	k.box(X1 - X0 + 0.18, bandH + 0.06, 0.18, mAlu, [0.09, (bandY0 + bandY1) / 2, ZF + 0.09])
	k.box(0.18, bandH + 0.06, ZF - ZB + 0.18, mAlu, [X1 + 0.09, (bandY0 + bandY1) / 2, (ZB + ZF + 0.18) / 2])
	var PXM := 128  # px per metre of band
	var seg := func(ln: float) -> Dictionary: return A.glow.region(ln * PXM, bandH * PXM)
	var rLogo: Dictionary = seg.call(4.4)
	var r24: Dictionary = seg.call(3.2)
	var rPlainA: Dictionary = seg.call(4.4)
	var fz := ZF + 0.185
	S.card(rPlainA, 4.4, bandH, [-3.8, (bandY0 + bandY1) / 2, fz])
	S.card(rLogo, 4.4, bandH, [0.6, (bandY0 + bandY1) / 2, fz])
	S.card(r24, 3.2, bandH, [4.4, (bandY0 + bandY1) / 2, fz])
	var fx := X1 + 0.185
	var nb0 := ZB
	var nb1 := ZF + 0.18
	# north face: plain | logo | plain (runs from front (+z) to back (-z) = viewer's left to right)
	var nLen := nb1 - nb0
	var nSide := (nLen - 4.4) / 2
	var rPlainN2: Dictionary = seg.call(nSide)
	S.card(rPlainN2, nSide, bandH, [fx, (bandY0 + bandY1) / 2, nb1 - nSide / 2], [0, PI / 2, 0])
	S.card(rLogo, 4.4, bandH, [fx, (bandY0 + bandY1) / 2, nb1 - nSide - 2.2], [0, PI / 2, 0])
	S.card(rPlainN2, nSide, bandH, [fx, (bandY0 + bandY1) / 2, nb0 + nSide / 2], [0, PI / 2, 0])

	# ---------------- entrance canopy with downlights
	var CANY := FY + 2.45
	k.box(3.4, 0.1, 1.15, M.t("#e6e5e0"), [1.0, CANY, ZF + 0.575])
	k.box(3.4, 0.14, 0.04, mAlu, [1.0, CANY, ZF + 1.15])
	for x in [0.0, 1.0, 2.0]:
		k.cyl(0.07, 0.07, 0.01, M.glow("#fff1d8", 1.25), [x, CANY - 0.055, ZF + 0.62], null, 12)
	# auto-door sensor
	k.box(0.4, 0.07, 0.08, M.t("#d9d9d4"), [1.0, FY + 2.32, ZF + 0.02])
	k.box(0.2, 0.03, 0.01, M.t("#3a3346"), [1.0, FY + 2.3, ZF + 0.065])

	# ---------------- automatic doors (dynamic)
	var dg = S.dyn()
	var panels := []
	var dz := ZF - 0.18
	var mDoorGlass = M.glass({"opacity": 0.16})
	var rAuto: Dictionary = A.lit.region(96, 40)
	for s in [-1, 1]:
		var pg := T.Group.new()
		pg.position = Vector3(1.0 + s * 0.5, FY, dz)
		dg.add(pg)
		var kk = ctx.kit(pg)
		kk.box(1.0, 0.06, 0.05, mAlu, [0, 2.17, 0])
		kk.box(1.0, 0.12, 0.05, mAlu, [0, 0.06, 0])
		kk.box(0.05, 2.2, 0.05, mAlu, [-0.475, 1.1, 0])
		kk.box(0.05, 2.2, 0.05, mAlu, [0.475, 1.1, 0])
		var gl = kk.plane(0.9, 2.0, mDoorGlass, [0, 1.12, 0])
		gl.cast_shadow = false
		var st = kk.mesh(C.region_geo(rAuto, 0.24, 0.1), rAuto.m, [s * -0.2, 1.05, 0.004])
		st.cast_shadow = false
		kk.box(0.9, 0.012, 0.004, M.t("#f3c14b"), [0, 1.3, 0.003])
		panels.append({"g": pg, "s": s, "x0": 1.0 + s * 0.5})
	var doorW: Vector3 = S.world(1.0, FY, ZF)
	var state := {"open": 0.0, "prevT": 0}
	var upd := func(dt: float) -> void:
		var p: Vector3 = ctx.player.position
		var d := sqrt((p.x - doorW.x) ** 2 + (p.z - doorW.z) ** 2)
		var target := 1 if d < 2.7 and absf(p.y - doorW.y) < 2.5 else 0
		if dt <= 0.0:
			state.open = float(target)
		else:
			state.open += T.sign(target - state.open) * minf(absf(target - state.open), dt * 1.5)
		var au = ctx.get("audio")
		if target and not state.prevT and dt > 0.0 and au != null and au.has_method("play"):
			au.play("doorChime", {"position": doorW, "volume": 0.45})
		state.prevT = target
		var o: float = state.open
		var e := o * o * (3.0 - 2.0 * o)
		for pn in panels:
			pn.g.position.x = pn.x0 + pn.s * 0.95 * e
	ctx.on_update(upd)
	var dyn_box := func() -> Array:
		if state.open > 0.55:
			return []
		var p: Dictionary = S.to_w(1.0, dz)
		return [{"cx": p.x, "cz": p.z, "w": 2.0 * (1.0 - state.open), "d": 0.1, "rotY": S.f.rotY, "y0": S.f.y + FY, "y1": S.f.y + FY + 2.2}]
	ctx.physics.addDynamic(dyn_box)

	# ---------------- entrance landing, steps, ramp, rails, tactile tiles
	var mStep = M.concrete("#c9c7c0")
	var lgY: float = S.gy(0, -2)
	S.ubox(4.8, FY - lgY + 0.2, 1.2, mStep, [0.2, (FY + lgY - 0.2) / 2, -2.0], null, 2)
	var stepTop := 0.14
	S.ubox(2.6, stepTop - lgY + 0.2, 0.36, mStep, [1.0, (stepTop + lgY - 0.2) / 2, -1.22], null, 2)
	# ramp (lx -4.4 .. -2.2)
	var rampLo: float = S.gy(-4.4, -2.0) + 0.02
	if true:
		var ln := 2.2
		var rise := FY - rampLo
		var ang := atan2(rise, ln)
		var L2 := sqrt(ln * ln + rise * rise)
		S.ubox(L2, 0.12, 1.2, mStep, [-3.3, (FY + rampLo) / 2 - 0.06, -2.0], [0, 0, ang], 2)
		# side skirt under the ramp (street side)
		S.ubox(ln, 0.3, 0.1, mStep, [-3.3, (FY + rampLo) / 2 - 0.25, -1.45], [0, 0, ang], 2)
	# handrail along the ramp + landing edge
	var mRail = M.t("#c3c7cb")
	for x in [-4.3, -3.3, -2.25]:
		var y0: float = rampLo + (FY - rampLo) * ((x + 4.4) / 2.2)
		k.cyl(0.022, 0.022, 0.85, mRail, [x, y0 + 0.425, -1.47], null, 8)
	if true:
		var a := Vector3(-4.3, rampLo + 0.05 + 0.85, -1.47)
		var b := Vector3(-2.25, FY + 0.85, -1.47)
		var ln := a.distance_to(b)
		k.cyl(0.025, 0.025, ln, mRail, [(a.x + b.x) / 2, (a.y + b.y) / 2, -1.47], [0, 0, PI / 2 + atan2(b.y - a.y, b.x - a.x)], 8)
		k.cyl(0.025, 0.025, 1.9, mRail, [-1.3, FY + 0.85, -1.47], [0, 0, PI / 2], 8)
		for x in [-1.3, -0.4]:
			k.cyl(0.022, 0.022, 0.85, mRail, [x, FY + 0.425, -1.47], null, 8)
	# tactile tiles
	var rDots: Dictionary = A.lit.region(64, 64, null, {"bg": "#efc233"})
	var rBars: Dictionary = A.lit.region(64, 64, null, {"bg": "#efc233"})
	var tile := func(reg: Dictionary, x: float, y: float, z: float, rot: float = 0.0) -> void:
		S.card(reg, 0.3, 0.3, [x, y + 0.006, z], [-PI / 2, 0, rot])
	var xx := -0.05
	while xx < 2.2:  # top of the step
		tile.call(rDots, xx + 0.15, FY, -1.58)
		xx += 0.3
	xx = 0.55
	while xx < 1.5:  # before the doors
		tile.call(rDots, xx + 0.15, FY, -2.4)
		xx += 0.3
	tile.call(rDots, 1.0, stepTop, -1.22)  # on step: warning
	var zz := -0.93
	while zz < -0.05:  # guide to the sidewalk
		tile.call(rBars, 1.0, S.gy(1.0, zz) + 0.02, zz + 0.15)
		zz += 0.3
	zz = -2.6
	while zz < -1.5:
		tile.call(rDots, -2.05, FY, zz + 0.15)
		zz += 0.3
	for z in [-2.0, -1.7]:
		tile.call(rDots, -4.57, S.gy(-4.57, z) + 0.02, z)

	# ---------------- bike parking paint (SPOTS.konbiniBikes at lx 4.6 / 3.85)
	var mLine = M.decal("#eeece6")
	for x in [3.475, 4.225, 4.975, 5.725]:
		var y: float = S.gy(x, -1.2) + 0.026
		k.plane(0.06, 2.1, mLine, [x, y, -1.2], [-PI / 2, 0, 0])
	k.plane(2.31, 0.06, mLine, [4.6, S.gy(4.6, -2.28) + 0.026, -2.28], [-PI / 2, 0, 0])
	var rBikeIcon: Dictionary = A.cut.region(128, 96)
	ctx.no_outline(S.card(rBikeIcon, 0.62, 0.46, [5.35, S.gy(5.35, -1.2) + 0.03, -1.3], [-PI / 2, 0, PI / 2]))

	# ---------------- window posters (face the street / R3)
	var pDrink: Dictionary = A.lit.region(220, 310)
	var pBento: Dictionary = A.lit.region(220, 310)
	var pIce: Dictionary = A.lit.region(220, 310)
	var pFair: Dictionary = A.lit.region(220, 310)
	var pKaraage: Dictionary = A.lit.region(220, 310)
	var pz := gz + 0.012
	S.card(pDrink, 0.55, 0.78, [-4.9, FY + 1.55, pz])
	S.card(pBento, 0.55, 0.78, [-2.95, FY + 1.55, pz])
	S.card(pFair, 0.62, 0.88, [3.05, FY + 1.6, pz])
	S.card(pIce, 0.55, 0.78, [4.85, FY + 1.55, pz])
	S.card(pKaraage, 0.55, 0.78, [gx + 0.012, FY + 1.55, -8.1], [0, PI / 2, 0])
	# small stickers on the door-side glass
	var rStick: Dictionary = A.lit.region(200, 120)
	S.card(rStick, 0.3, 0.18, [-0.4, FY + 1.3, pz])
	var r24s: Dictionary = A.lit.region(120, 120)
	S.card(r24s, 0.2, 0.2, [2.4, FY + 1.35, pz])
	# local mascot sticker low on the glass
	var rMascot: Dictionary = A.lit.region(128, 128)
	S.card(rMascot, 0.16, 0.16, [-1.25, FY + 0.95, pz])
	var rATMs: Dictionary = A.lit.region(140, 60)
	S.card(rATMs, 0.28, 0.12, [2.4, FY + 1.08, pz])

	# ---------------- interior shell skins (walls, ceiling) + modelled contents (intKonbini.js)
	var IX0 := X0 + WT
	var IX1 := X1 - WT
	var IZ0 := ZB + WT
	var IZ1 := ZF - WT
	k.plane(IX1 - IX0, IZ1 - IZ0 + 0.1, mInW, [(IX0 + IX1) / 2, CY, (IZ0 + IZ1) / 2], [PI / 2, 0, 0])
	k.plane(IX1 - IX0, CY - FY, mIn, [(IX0 + IX1) / 2, (FY + CY) / 2, IZ0 + 0.005])
	k.plane(IZ1 - IZ0, CY - FY, mIn, [IX0 + 0.005, (FY + CY) / 2, (IZ0 + IZ1) / 2], [0, PI / 2, 0])
	k.plane(NW0 - IZ0, CY - FY, mIn, [IX1 - 0.005, (FY + CY) / 2, (IZ0 + NW0) / 2], [0, -PI / 2, 0])
	k.box(IX1 - IX0, 0.12, 0.02, M.inner("#b9bcc0", 0.2), [(IX0 + IX1) / 2, FY + 0.06, IZ0 + 0.012])
	k.box(0.02, 0.12, IZ1 - IZ0, M.inner("#b9bcc0", 0.2), [IX0 + 0.012, FY + 0.06, (IZ0 + IZ1) / 2])
	IntKonbini.build_konbini_interior(ctx, C, S, {"FY": FY, "CY": CY, "IX0": IX0, "IX1": IX1, "IZ0": IZ0, "IZ1": IZ1, "NW0": NW0, "NW1": NW1,
		"gx": gx, "gz": gz, "TEAL": TEAL, "TEAL_D": TEAL_D, "YEL": YEL, "CREAM": CREAM, "INK": INK})

	# ---------------- exterior: bins, umbrella stand, flags, signs
	if true:
		var x0 := -5.95
		var bw := 0.42
		var z := -2.33
		var BY: float = maxf(S.gy(x0, z), S.gy(x0 + bw * 3, z)) + 0.05
		var padH: float = BY - minf(S.gy(x0, z), S.gy(x0 + bw * 3, z)) + 0.2
		S.ubox(bw * 3 + 0.2, padH, 0.56, M.concrete("#c9c7c0"), [x0 + bw * 1.5, BY - padH / 2, z], null, 2)
		var labels := [["もやせるごみ", "#e36b5d"], ["かん・びん", "#3f7fb5"], ["ペットボトル", "#5a9e58"]]
		k.box(bw * 3 + 0.04, 0.95, 0.44, M.t("#e3e1da"), [x0 + bw * 1.5, BY + 0.475, z])
		k.box(bw * 3 + 0.08, 0.05, 0.48, M.t(TEAL), [x0 + bw * 1.5, BY + 0.975, z])
		for i in labels.size():
			var reg: Dictionary = A.lit.region(96, 96)
			S.card(reg, 0.36, 0.36, [x0 + bw * (i + 0.5), BY + 0.68, z + 0.225])
		S.box(x0 + bw * 1.5, z, bw * 3 + 0.08, 0.48, -1, BY + 1.0)
		P.umbrella_stand(S, 2.35, FY, -2.4, 0, {"umbrellas": ["#7ea6c9", "#e8e6df"]})
		S.box(2.35, -2.4, 0.5, 0.24, -1, FY + 0.6)
		var fSakura: Dictionary = A.lit.region(96, 340)
		var fIce: Dictionary = A.lit.region(96, 340)
		P.nobori(S, -6.15, S.gy(-6.15, -0.45), -0.45, 0.25, fSakura, {"w": 0.42, "h": 1.55})
		P.nobori(S, 2.95, S.gy(2.95, -0.3), -0.3, -0.35, fIce, {"w": 0.42, "h": 1.55})
		S.cyl(-6.15, -0.45, 0.17, -1, 2.2)
		S.cyl(2.95, -0.3, 0.17, -1, 2.2)
		# bicycle parking sign on the corner pier
		var rBikeSign: Dictionary = A.lit.region(120, 96)
		S.card(rBikeSign, 0.3, 0.24, [X1 - 0.15, FY + 1.5, ZF + 0.005])
		# ATM lit box sign on the north wall
		k.box(0.12, 0.5, 0.9, M.t("#e6e5e0"), [X1 + 0.06, 2.3, -10.4])
		var rATMbox: Dictionary = A.glow.region(180, 100)
		S.card(rATMbox, 0.84, 0.46, [X1 + 0.125, 2.3, -10.4], [0, PI / 2, 0])
		# opening-hours plate by the door
		var rHours: Dictionary = A.lit.region(100, 130)
		S.card(rHours, 0.2, 0.26, [-0.25, FY + 1.7, pz])

	# ---------------- back yard + side services
	if true:
		# back door with step
		var bdX := -1.2
		var bST := FY - 0.15
		var bSB: float = S.gy(bdX, -12.3) - 0.2
		S.ubox(1.3, bST - bSB, 0.55, M.concrete("#c4c2bb"), [bdX, (bST + bSB) / 2, ZB - 0.27], null, 2)
		var rStaffD: Dictionary = A.lit.region(96, 32)
		P.back_door(S, bdX, FY, ZB, PI, "#9aa6ad", {"label": rStaffD})
		S.walk(bdX, ZB - 0.27, 1.3, 0.55, bST)
		# AC outdoor units against the back wall
		for xb in [[1.2, true], [2.35, true], [-3.3, false]]:
			var x: float = xb[0]
			var big: bool = xb[1]
			var w := 0.95 if big else 0.8
			var h := 1.1 if big else 0.62
			P.ac_unit(S, x, S.gy(x, -12.35), -12.28, PI, {"w": w, "h": h, "d": 0.34, "ductH": 2.6 if big else 1.4})
			S.box(x, -12.28, w + 0.1, 0.4, -1, h + 0.2)
		# meters and pipes
		P.meter(S, -4.6, 1.6, ZB, PI)
		P.gas_meter(S, -5.3, 1.1, ZB, PI)
		for x in [-4.1, -3.95]:
			P.pipe(S, x, ZB - 0.06, 0.1, TOP - 0.1, 0.03, M.t("#bdbab1"))
		P.downpipe(S, X0 + 0.1, ZB - 0.06, TOP - 0.05, null, [0, 1])
		P.downpipe(S, X1 - 0.12, ZB - 0.06, TOP - 0.05, null, [0, 1])
		# garbage cage with bags
		var cg := {"x0": 3.6, "x1": 5.7, "z0": -13.9, "z1": -12.65}
		var cgc := [(cg.x0 + cg.x1) / 2, (cg.z0 + cg.z1) / 2]
		var cgy: float = S.gy(cgc[0], cgc[1])
		var mCage = M.t("#6f8a7c")
		for q in [[cg.x0, cg.z0], [cg.x1, cg.z0], [cg.x0, cg.z1], [cg.x1, cg.z1]]:
			k.box(0.05, 1.2, 0.05, mCage, [q[0], cgy + 0.6, q[1]])
		for y in [0.05, 1.18]:
			k.box(cg.x1 - cg.x0, 0.04, 0.04, mCage, [cgc[0], cgy + y, cg.z0])
			k.box(cg.x1 - cg.x0, 0.04, 0.04, mCage, [cgc[0], cgy + y, cg.z1])
			k.box(0.04, 0.04, cg.z1 - cg.z0, mCage, [cg.x0, cgy + y, cgc[1]])
			k.box(0.04, 0.04, cg.z1 - cg.z0, mCage, [cg.x1, cgy + y, cgc[1]])
		var rMesh: Dictionary = A.cut.region(128, 128)
		var mesh_card := func(w: float, h: float, pos: Array, rot):
			var m = S.card(rMesh, w, h, pos, rot)
			ctx.no_outline(m)
			return m
		mesh_card.call(cg.x1 - cg.x0, 1.12, [cgc[0], cgy + 0.62, cg.z1], null)
		mesh_card.call(cg.x1 - cg.x0, 1.12, [cgc[0], cgy + 0.62, cg.z0], null)
		mesh_card.call(cg.z1 - cg.z0, 1.12, [cg.x0, cgy + 0.62, cgc[1]], [0, PI / 2, 0])
		mesh_card.call(cg.x1 - cg.x0, cg.z1 - cg.z0, [cgc[0], cgy + 1.2, cgc[1]], [-PI / 2, 0, 0])
		for i in 6:
			var px: float = cg.x0 + 0.35 + (i % 3) * 0.6 + rr.f() * 0.1
			var py: float = cgy + 0.25 + (i / 3) * 0.3
			var pzz: float = cgc[1] + (rr.f() - 0.5) * 0.4
			C.scatter.add("bush", S, [px, py, pzz], [0.28, 0.25, 0.26], rr.pick(["#e8e6df", "#dfe6ea", "#f0ecd8"]))
		S.box(cgc[0], cgc[1], cg.x1 - cg.x0 + 0.06, cg.z1 - cg.z0 + 0.06, -1, 1.3)
		# delivery crates + milk crates + flattened cartons by the back door
		var cy0: float = S.gy(0.1, -12.9)
		for i in 4:
			P.crate(S, 0.05, cy0 + i * 0.16, -12.95, 0.05 * (i % 2), "#3f9a92", {"w": 0.62, "h": 0.16, "d": 0.46})
		for i in 2:
			P.crate(S, -0.55 + i * 0.02, cy0 + i * 0.3, -13.4, 0.1 * i, "#e9c34b" if i else "#4f8fc0", {"bottles": "#f4f1e8" if i else null})
		P.crate(S, 0.7, S.gy(0.7, -13.4), -13.5, -0.3, "#e36b5d")
		for i in 5:
			P.carton(S, -2.35, S.gy(-2.35, -12.2) + i * 0.035, -12.15 - i * 0.003, 0.9, 0.03, 0.62, 0.02 * i)
		k.box(0.9, 0.9, 0.05, M.carton(), [-2.35, S.gy(-2.35, -12.2) + 0.45, -12.08], [0.12, 0, 0])
		S.box(0.0, -13.1, 1.9, 1.0, -1, 0.8)
		# mop & bucket
		k.cyl(0.14, 0.12, 0.28, M.t("#4f8fc0"), [-5.4, S.gy(-5.4, -12.5) + 0.14, -12.5], null, 10)
		k.cyl(0.012, 0.012, 1.3, M.t("#d9d6ce"), [-5.62, S.gy(-5.6, -12.2) + 0.65, -12.15], [0.12, 0, 0.1], 5)
		# side fence closing the yard toward R3 (north)
		var fy: float = S.gy(6.35, -13)
		for z in [-13.95, -12.8]:
			k.box(0.05, 1.5, 0.05, mCage, [6.35, fy + 0.75, z])
		mesh_card.call(1.15, 1.35, [6.35, fy + 0.78, -13.37], [0, PI / 2, 0])
		k.box(0.04, 0.04, 1.15, mCage, [6.35, fy + 1.47, -13.37])
		S.box(6.35, -13.37, 0.08, 1.25, -1, 1.6)
	# south wall: downpipe + meter box (faces the flower shop gap)
	P.downpipe(S, X0 - 0.06, ZF - 0.35, TOP - 0.05, null, [1, 0])
	# roof top: AC condensers + vent
	for q in [[-3.8, -10.4], [-2.6, -10.4], [-1.4, -10.4]]:
		P.ac_unit(S, q[0], 4.05, q[1], 0, {"w": 0.95, "h": 0.8, "d": 0.36, "duct": false})
	k.box(0.6, 0.5, 0.6, M.t("#b9bcc0"), [3.5, 4.3, -9.5])
	k.cyl(0.2, 0.2, 0.3, M.t("#9aa1a8"), [3.5, 4.7, -9.5], null, 10)

	# ---------------- physics: shell
	S.box(0, ZB + WT / 2, X1 - X0, WT, -1, TOP)
	S.box(X0 + WT / 2, (ZB + ZF) / 2, WT, ZF - ZB, -1, TOP)
	S.box(X1 - WT / 2, (ZB + ZF) / 2, WT, ZF - ZB, -1, TOP)
	S.box((X0 + 0.0) / 2, ZF - WT / 2, 0.0 - X0, WT, -1, TOP)
	S.box((2.0 + X1) / 2, ZF - WT / 2, X1 - 2.0, WT, -1, TOP)
	S.box(1.0, ZF - WT / 2, 2.2, WT, FY + 2.25, TOP)
	S.walk(0, (ZB + ZF) / 2, X1 - X0, ZF - ZB, FY)
	S.walk(0.2, -2.0, 4.8, 1.2, FY)
	S.walk(1.0, -1.22, 2.6, 0.36, stepTop)
	S.ramp(-3.3, -2.0, 1.2, 2.2, rampLo, FY, PI / 2)
	S.box(-3.3, -1.47, 2.2, 0.08, -1, FY + 0.9)
	S.box(-1.3, -1.47, 1.9, 0.08, -1, FY + 0.9)

	return {"S": S}
