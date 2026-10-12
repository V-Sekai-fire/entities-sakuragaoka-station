# houses/apartment.js: a two-storey wooden apartment, four units per floor, a rear external corridor
# with walkable steel stairs, front balconies with partitions and laundry, a bike shelter and mailboxes.
extends RefCounted

const GBM = preload("res://addons/sakuragaoka_station/world/houses/gb.gd")
const House = preload("res://addons/sakuragaoka_station/world/houses/house.gd")
const Lot = preload("res://addons/sakuragaoka_station/world/houses/lot.gd")


## F: the lot frame at the frontage centre (+z toward the lane); local x in [-w/2, w/2], z in [-depth, 0].
static func build_apartment(H, F, w: float, depth: float, r) -> Dictionary:
	var M: Dictionary = H.M
	var A: Dictionary = H.A
	var P = H.props
	var gy := func(x: float, z: float) -> float: return H.gy(F, x, z)
	var res := {"bikeSpots": [], "gardenSpots": [], "wallTops": []}
	var FH := 2.8
	var bx0 := -w / 2.0 + 2.6
	var bx1 := w / 2.0 - 0.5
	var bz1 := -2.6
	var bz0 := bz1 - 6.0
	var cz0 := bz0 - 1.25
	var gmax := -1e9
	var gmin := 1e9
	for xz in [[bx0, bz0], [bx1, bz0], [bx0, bz1], [bx1, bz1], [bx0 - 1.3, cz0], [bx1, cz0]]:
		var g: float = gy.call(xz[0], xz[1])
		gmax = maxf(gmax, g)
		gmin = minf(gmin, g)
	var fy := gmax + 0.35
	var top := fy + 2 * FH
	var wall_c := "#e9e1cf"
	var trim := "#6b5242"
	var steel := "#5b5450"
	var bw := bx1 - bx0
	var bd := bz1 - bz0
	var bcx := (bx0 + bx1) / 2.0
	var bcz := (bz0 + bz1) / 2.0
	var S := {"rng": r, "floorY": fy, "fh": FH, "groundMin": gmin, "lod": 2, "frameColor": "#8e949b", "sillColor": "#8e949b", "grilleColor": "#8e949b",
		"shutterColor": "#b9bcbf", "shutterStyle": "none", "trim": trim, "interiors": null, "roof": {"mat": "metal", "color": "#6d7680"}, "wall": {"kind": "siding", "color": wall_c}}
	F.boxB(M.concrete, "#bdbcb5", bw - 0.04, fy - gmin + 0.14, bd - 0.04, bcx, gmin - 0.14, bcz, {"uv": {"world": 2}})
	F.boxB(M.siding, wall_c, bw, 2 * FH + 0.02, bd, bcx, fy - 0.02, bcz, {"uv": {"world": 1.2}})
	F.boxB(M.plain, trim, bw + 0.05, 0.16, bd + 0.05, bcx, fy + FH - 0.08, bcz)
	H.col(F, bcx, bcz, bw + 0.05, bd + 0.05, 0, gmin - 1, top + 2)
	var o := 0.45
	var p := 0.22
	var tv := 0.1
	var hx := bw / 2.0 + 0.35
	var hz := bd / 2.0 + o
	var yE := top + tv - o * p
	var yR := yE + hz * p
	var RF = F.sub(bcx, 0, bcz, 0)
	for s in [1, -1]:
		var pts := [[-hx, yE, s * hz], [hx, yE, s * hz], [hx, yR, 0], [-hx, yR, 0]]
		var sl := GBM.slab(pts, tv, func(q): return Vector2(q[0] / 1.08, -(hz - s * q[2]) * 1.02))
		H.gb.mesh(M.metal, "#6d7680", sl.p, sl.n, sl.u, sl.i, RF.M(0, 0, 0))
		RF.box(M.plain, "#e9e6df", 2 * hx, 0.2, 0.04, 0, yE - tv - 0.05, s * (hz - 0.02))
		RF.box(M.plain, "#e9e6df", 2 * hx - 0.04, 0.02, o - 0.04, 0, yE - tv - 0.12, s * (bd / 2.0 + o / 2.0))
		RF.box(M.plain, "#8e949b", 2 * hx, 0.09, 0.1, 0, yE - tv - 0.06, s * (hz + 0.05))
	for sx in [-1, 1]:
		var pg := GBM.poly([[sx * bw / 2.0, top - 0.01, bd / 2.0], [sx * bw / 2.0, top - 0.01, -bd / 2.0], [sx * bw / 2.0, top + bd / 2.0 * p, 0]], [sx, 0, 0], func(q): return Vector2(q[2] / 1.2, q[1] / 1.2))
		H.gb.mesh(M.siding, wall_c, pg.p, pg.n, pg.u, pg.i, RF.M(0, 0, 0))
		for sz in [-1, 1]:
			RF.beam(M.plain, "#e9e6df", [sx * (hx + 0.015), yE - 0.06, sz * hz], [sx * (hx + 0.015), yR - 0.06, 0], 0.045, 0.22, {"extend": 0.1})
	RF.beam(M.plain, "#6d7680", [-hx, yR + 0.02, 0], [hx, yR + 0.02, 0], 0.2, 0.06)
	var WF = F.sub(bx0, 0, bcz, -PI / 2.0)
	WF.box(M.atlas, "#ffffff", 2.2, 0.55, 0.04, 0, fy + 2 * FH - 0.6, 0.02, {"uv": {"rect": A.rects.apt_sign, "white": A.white}})
	House.build_window(H, WF, -1.6, fy + FH + 1.0, 0.74, 0.9, "small", S, r, 2, "side", 1)
	House.build_window(H, WF, -1.6, fy + 1.0, 0.74, 0.9, "small", S, r, 2, "side", 0)
	var n := 4
	var uw := bw / n
	var FR = F.sub(bcx, 0, bz1, 0)
	var BK = F.sub(bcx, 0, bz0, PI)
	var S_none := S.duplicate()
	S_none["shutterStyle"] = "none"
	for fl in 2:
		var y0 := fy + fl * FH
		for i in n:
			var uc := -bw / 2.0 + uw * (i + 0.5)
			var room := str((fl + 1) * 100 + i + 1)
			House.build_window(H, FR, uc - 0.35, y0 + 0.08, 1.69, 1.9, "big", S_none, r, 2, "balc", 0)
			var ub := -uc
			BK.box(M.plain, "#8e949b", 0.98, 2.06, 0.06, ub + 0.55, y0 + 1.03, 0.03)
			BK.box(M.atlas, "#ffffff", 0.86, 1.98, 0.03, ub + 0.55, y0 + 1.0, 0.05, {"uv": {"rect": A.rects.door_steel, "white": A.white}})
			BK.box(M.atlas, "#ffffff", 0.22, 0.11, 0.02, ub + 0.55, y0 + 2.22, 0.02, {"uv": {"rect": A.rects["room" + room], "white": A.white}})
			House.build_window(H, BK, ub - 0.65, y0 + 1.05, 0.74, 0.8, "small", S, r, 2, "back", fl)
			BK.box(M.plain, "#d6d0c2", 0.5, 0.9, 0.12, ub + 1.28, y0 + 1.3, 0.06)
			BK.box(M.plain, "#8e949b", 0.46, 0.02, 0.02, ub + 1.28, y0 + 1.3, 0.125)
			BK.box(M.lampDim, null, 0.16, 0.06, 0.16, ub + 0.55, y0 + FH - 0.12, 0.6, {"shadow": false})
			if fl == 1:
				var BF = FR
				BF.box(M.plain, "#dcd6c8", uw, 0.16, 0.95, uc, y0 - 0.06, 0.475)
				BF.boxB(M.plain, "#d8d2c4", uw, 1.0, 0.07, uc, y0 + 0.03, 0.915)
				BF.box(M.plain, trim, uw, 0.05, 0.1, uc, y0 + 1.06, 0.915)
				if i < n - 1:
					BF.boxB(M.plain, "#cfd6da", 0.04, 1.8, 0.9, uc + uw / 2.0, y0 + 0.03, 0.45)
				var py := y0 + 1.8
				BF.cyl(M.plain, "#8fb3c9", 0.016, uw - 0.4, uc, py, 0.55, {"rz": PI / 2.0, "seg": 6})
				for s in [-1, 1]:
					BF.box(M.plain, "#c9ccd1", 0.03, 0.03, 0.6, uc + s * (uw / 2.0 - 0.25), py + 0.02, 0.3)
				if r.f() < 0.75:
					H.laundry.line(BF, uc - uw / 2.0 + 0.3, uc + uw / 2.0 - 0.3, py, 0.55, r, "apartment")
				if r.f() < 0.8:
					P.ac_unit(BF, uc + uw / 2.0 - 0.55, y0 + 0.03, 0.3, 0)
				if r.f() < 0.3:
					P.futon(BF, uc - 0.3, y0 + 1.08, 0.915, r)
				if r.f() < 0.4:
					P.dish(BF, uc - uw / 2.0 + 0.3, y0 + 0.85, 1.0, 0)
			else:
				FR.boxB(M.plain, "#8e949b", 0.04, 0.8, 0.04, uc + uw / 2.0 - 0.05, gy.call(bcx + uc + uw / 2.0, bz1 + 1.2), 1.2)
				if r.f() < 0.8:
					P.ac_unit(FR, uc + uw / 2.0 - 0.6, gy.call(bcx + uc, bz1 + 0.3), 0.3, 0)
				if r.f() < 0.5:
					P.pot(FR, uc - 0.9, gy.call(bcx + uc - 0.9, bz1 + 0.6), 0.6, r, 1)
	H.sloped_wall(F, bx0, bx1, bz1 + 1.3, 0.75, 0.05, M.plain, "#8e949b", 0, 0, 0.1)
	var yC := fy + FH
	var cxb := bx1
	var czm := (bz0 + cz0) / 2.0
	F.box(M.plain, "#cfcac0", cxb - bx0, 0.2, bz0 - cz0, (bx0 + cxb) / 2.0, yC - 0.1, czm)
	F.boxB(M.plain, "#dcd6c8", cxb - bx0, 1.0, 0.08, (bx0 + cxb) / 2.0, yC, cz0 + 0.04)
	F.box(M.plain, steel, cxb - bx0 + 0.04, 0.05, 0.12, (bx0 + cxb) / 2.0, yC + 1.02, cz0 + 0.04)
	for k in 5:
		var x := bx0 + 0.1 + k * (cxb - bx0 - 0.2) / 4.0
		F.boxB(M.plain, steel, 0.12, yC - 0.2 - gy.call(x, cz0 + 0.1), 0.12, x, gy.call(x, cz0 + 0.1), cz0 + 0.12)
		H.col(F, x, cz0 + 0.12, 0.14, 0.14, 0, gy.call(x, cz0) - 0.5, yC)
	H.walk(F, (bx0 + cxb) / 2.0, czm, cxb - bx0, bz0 - cz0, 0, yC)
	H.col(F, (bx0 + cxb) / 2.0, cz0 + 0.04, cxb - bx0, 0.1, 0, yC - 0.3, yC + 1.05)
	var sx := bx0 - 0.68
	var swd := 1.0
	var sz1 := bz0 - 0.05
	var g0: float = gy.call(sx, bz0 + 3.9)
	var rise := yC - g0
	var n_st := int(GBM.T.js_round(rise / 0.19))
	var run := n_st * 0.25
	var sz_start := sz1 + run
	F.box(M.plain, "#cfcac0", swd + 0.1, 0.18, bz0 - cz0, sx, yC - 0.09, czm)
	H.walk(F, sx, czm, swd + 0.1, bz0 - cz0, 0, yC)
	for i in n_st:
		var yT := g0 + rise * (i + 1) / n_st
		var zc := sz_start - 0.25 * (i + 0.5)
		F.box(M.plain, "#a9a49b", swd, 0.04, 0.27, sx, yT - 0.02, zc)
		F.box(M.plain, steel, swd, 0.19, 0.02, sx, yT - 0.1, zc + 0.125)
	for s in [-1, 1]:
		F.beam(M.plain, steel, [sx + s * (swd / 2.0 + 0.02), g0 - 0.05, sz_start], [sx + s * (swd / 2.0 + 0.02), yC - 0.05, sz1], 0.05, 0.24)
		F.beam(M.plain, steel, [sx + s * (swd / 2.0 + 0.03), g0 + 0.9, sz_start], [sx + s * (swd / 2.0 + 0.03), yC + 0.9, sz1], 0.04, 0.05)
		for k in 6:
			var t := k / 5.0
			var zz := sz_start + (sz1 - sz_start) * t
			var yy := g0 + rise * t
			F.box(M.plain, steel, 0.025, 0.9, 0.025, sx + s * (swd / 2.0 + 0.03), yy + 0.45, zz)
	F.boxB(M.plain, steel, 0.12, yC - g0, 0.12, sx - swd / 2.0, g0, sz1 - 0.05)
	F.boxB(M.plain, steel, 0.12, yC - g0, 0.12, sx - swd / 2.0, g0, cz0 + 0.06)
	var pc: Vector3 = F.w(sx, 0, (sz_start + sz1) / 2.0)
	H.ctx.physics.addWalkRamp(pc.x, pc.z, swd, run, F.ry + PI, pc.y + g0, pc.y + yC)
	for s in [-1, 1]:
		var pc2: Vector3 = F.w(sx + s * (swd / 2.0 + 0.05), 0, (sz_start + sz1) / 2.0)
		H.ctx.physics.addBox(pc2.x, pc2.z, 0.08, run, F.ry, pc2.y + g0 - 0.5, pc2.y + yC + 1.0)
	H.col(F, sx - swd / 2.0 - 0.05, czm, 0.08, bz0 - cz0, 0, yC - 0.3, yC + 1.05)
	var mbx := bx0 - 0.9
	var mbz := bz1 + 0.2
	F.boxB(M.atlas, "#ffffff", 0.9, 0.45, 0.3, mbx, gy.call(mbx, mbz) + 0.8, mbz, {"uv": {"rect": A.rects.posts, "white": A.white}})
	F.boxB(M.plain, "#8e949b", 0.06, 0.8, 0.06, mbx - 0.4, gy.call(mbx, mbz), mbz)
	F.boxB(M.plain, "#8e949b", 0.06, 0.8, 0.06, mbx + 0.4, gy.call(mbx, mbz), mbz)
	var shx0 := bx0 + 0.3
	var shx1 := bx0 + 5.6
	var shz := -1.2
	for x in [shx0, shx1]:
		for z in [shz - 0.8, shz + 0.8]:
			F.boxB(M.plain, "#8e949b", 0.07, 2.1, 0.07, x, gy.call(x, z) - 0.05, z)
			H.colC(F, x, z, 0.06, gy.call(x, z) - 0.5, gy.call(x, z) + 2.1)
	var shY := maxf(gy.call(shx0, shz), gy.call(shx1, shz)) + 2.1
	F.box(M.plain, "#8e949b", shx1 - shx0 + 0.1, 0.08, 0.08, (shx0 + shx1) / 2.0, shY, shz - 0.8)
	F.box(M.plain, "#8e949b", shx1 - shx0 + 0.1, 0.08, 0.08, (shx0 + shx1) / 2.0, shY, shz + 0.8)
	F.box(M.poly, null, shx1 - shx0 + 0.3, 0.02, 1.9, (shx0 + shx1) / 2.0, shY + 0.07, shz, {"noOutline": true, "rx": 0.05})
	H.ground_rect(F, shx0 - 0.2, shz - 1.0, shx1 + 0.2, shz + 1.0, M.concrete, "#c9c7c0", 0.04, 2)
	for k in 4:
		var x := shx0 + 0.8 + k * 1.2
		var pw: Vector3 = F.w(x, 0, shz)
		res.bikeSpots.append({"x": pw.x, "z": pw.z, "rotY": F.ry + PI})
	H.ground_rect(F, -w / 2.0 + 0.05, -depth + 0.05, w / 2.0 - 0.05, -0.05, M.gravel, "#d6d0c4", 0.02, 1.5)
	H.ground_rect(F, bx0 - 1.3, cz0, bx1, bz0, M.concrete, "#c9c7c0", 0.035, 2)
	H.ground_rect(F, sx - 0.7, bz0, sx + 0.7, -0.05, M.concrete, "#c9c7c0", 0.035, 2)
	Lot.boundary_seg(H, F, sx + 0.8, w / 2.0 - 0.06, -0.15, "low", 0.5, "#c9c7c0", r, gy, 2, null, true)
	Lot.boundary_seg(H, F, -w / 2.0 + 0.06, -w / 2.0 + 0.5, -0.15, "low", 0.5, "#c9c7c0", r, gy, 2, null, true)
	Lot.boundary_seg_z(H, F, w / 2.0 - 0.07, -0.3, -depth + 0.08, "block", 1.1, "#c9c7c0", r, gy)
	Lot.boundary_seg(H, F, -w / 2.0 + 0.07, w / 2.0 - 0.07, -depth + 0.08, "mesh", 1.2, "#c9c7c0", r, gy, 2, null, false)
	P.gomi_station(F, w / 2.0 - 1.4, gy.call(w / 2.0 - 1.4, -0.8), -0.8, r)
	H.col(F, w / 2.0 - 1.4, -0.8, 1.9, 1.0, 0, gy.call(w / 2.0 - 1.4, -0.8) - 0.5, gy.call(w / 2.0 - 1.4, -0.8) + 1.1)
	return res
