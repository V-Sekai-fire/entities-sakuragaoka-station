# houses/lot.js: the lot planner and yard builder. House placement, boundary walls, fences and hedges,
# gates, paving, parking pads, gardens, doorstep and yard props, colliders and service spots.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const House = preload("res://addons/sakuragaoka_station/world/houses/house.gd")

const PAL := {
	"plaster": ["#e8dcc6", "#e3d4b8", "#efe4cf", "#ddd0b8", "#e9dfd0", "#eadbc4", "#ecdcc8"],
	"paint": ["#efe9dc", "#ece8e0", "#f0ebe1", "#e7e3da", "#eee6d8"],
	"siding": ["#b7cddb", "#c2d3de", "#aec6d6", "#bccfdc", "#d8d4c8", "#c9c3b3", "#b9c4b4", "#e6dfcf", "#d3c6b4", "#c8d6cf"],
	"tile": ["#cdd0cd", "#d3d2cc", "#c7c9c6", "#d6cfc4", "#bfc2c1", "#d9d2c6"],
	"wood": ["#6b4f3c", "#5f4636", "#7a5a43"],
	"kawara": ["#4a4f58", "#555a63", "#4f545c", "#56677a", "#5d6f82", "#4d6457", "#4a5f55", "#50565f"],
	"metal": ["#7b8691", "#5c6b78", "#6a5448", "#4f5e57", "#8a8f94", "#6d7680"],
	"frame": ["#4b4d52", "#4b4d52", "#5e4636", "#5e4636", "#8e949b"],
	"gutter": ["#e4dfd2", "#6b5242", "#8e949b", "#4b4d52", "#d8d2c4"],
	"shutter": ["#b9bcbf", "#8e8a82", "#d8d2c4", "#6b5a4c", "#a9aeb3"],
}


static func pick(r, a: Array):
	return a[floori(r.f() * a.size())]


static func wpick(r, items: Array):
	var s := 0.0
	for it in items:
		s += it[1]
	var x: float = r.f() * s
	for it in items:
		x -= it[1]
		if x <= 0.0:
			return it[0]
	return items[items.size() - 1][0]


static func _or(v, d):
	return v if v else d


static func _nn(v, d):
	return v if v != null else d


## A random house spec for a footprint.
static func make_spec(r, o: Dictionary) -> Dictionary:
	var kind: String = _or(o.get("wallKind"), null) if o.get("wallKind") else wpick(r, [["plaster", 30], ["paint", 14], ["siding", 32], ["tile", 12], ["wood", 30 if o.get("traditional") else 6]])
	var wall := {"kind": kind, "color": pick(r, PAL[kind])}
	var wall2 = null
	if o.floors >= 2 and r.f() < 0.22 and kind != "wood":
		var k2 := "siding" if kind == "tile" else ("tile" if kind == "siding" else "siding")
		if kind == "tile":
			wall2 = {"kind": "siding", "color": pick(r, PAL.siding)}
		else:
			wall2 = {"kind": k2, "color": pick(r, PAL[k2])}
		if k2 == "tile":
			wall2 = wall.duplicate()
			wall.kind = "tile"
			wall.color = pick(r, PAL.tile)
	var trad := bool(o.get("traditional"))
	var roof_type: String
	if o.get("roofType"):
		roof_type = o.roofType
	elif trad:
		roof_type = pick(r, ["hip", "hip", "gable"])
	else:
		roof_type = wpick(r, [["hip", 42], ["gable", 36], ["shed", 14], ["flat", 5 if o.get("allowFlat") else 0]])
	var roof_mat: String
	if roof_type == "shed" or roof_type == "flat":
		roof_mat = "metal"
	elif trad:
		roof_mat = "kawara"
	else:
		roof_mat = "kawara" if r.f() < 0.66 else "metal"
	var roof := {"type": roof_type, "mat": roof_mat, "color": pick(r, PAL[roof_mat])}
	if roof_mat == "kawara":
		roof.pitch = 0.42 + r.f() * 0.12
	elif roof_type == "shed":
		roof.pitch = 0.2 + r.f() * 0.1
	else:
		roof.pitch = 0.3 + r.f() * 0.12
	roof.over = 0.55 + r.f() * 0.12 if roof_mat == "kawara" else 0.42 + r.f() * 0.15
	roof.axis = "x" if r.f() < 0.5 else "z"
	roof.reverse = r.f() < 0.3
	var light := kind != "wood"
	var trim: String
	if kind == "wood":
		trim = "#3f3a3c"
	else:
		trim = "#ece8df" if (kind == "siding" or r.f() < 0.5) else "#6b5242"
	var frame: String = "#5e4636" if trad else pick(r, PAL.frame)
	var S := {"rng": r, "wall": wall, "wall2": wall2, "roof": roof, "trim": trim, "traditional": trad, "frameColor": frame, "sillColor": frame}
	S.grilleColor = pick(r, ["#8e949b", "#4b4d52", "#6b5a4c"])
	S.fasciaColor = pick(r, ["#ece8df", "#4f4a4a", "#6b5242", "#8e949b"]) if roof_mat == "metal" else pick(r, ["#ece8df", "#6b5242", "#4f4a4a"])
	S.soffitColor = pick(r, ["#ece8df", "#e6dfd0", "#efe9dc"])
	S.gutterColor = pick(r, PAL.gutter)
	S.flashColor = "#8a8f96"
	S.foundColor = pick(r, ["#bdbcb5", "#c3c1b9", "#b5b3ac"])
	S.shutterColor = pick(r, PAL.shutter)
	S.shutterStyle = "tobukuro" if trad else wpick(r, [["tobukuro", 30], ["roll", 32], ["none", 38]])
	S.shutterClosed = 0.07
	S.hoods = trad or r.f() < 0.18
	S.hoodColor = pick(r, ["#6b7079", "#5a5f66", "#7b8691"])
	S.belt = light and r.f() < 0.45
	S.cornerTrim = r.f() < 0.5
	S.porchColor = pick(r, ["#c9bfb0", "#b9b1a4", "#d6cfc4", "#a9a49b", "#c4b39a"])
	S.canopyColor = pick(r, ["#ece8df", "#d8d2c4", "#6b5242", "#8e949b"])
	S.balconySlab = pick(r, ["#e2ddd2", "#d8d2c4"])
	S.railColor = pick(r, ["#8e949b", "#4b4d52", "#6b5242", "#c9ccd1"])
	S.poleColor = pick(r, ["#8fb3c9", "#c9ccd1", "#a8c7a0"])
	S.bigFront = r.f() < 0.7
	S.antenna = r.f() < _nn(o.get("antennaP"), 0.55)
	S.solar = not trad and roof_type != "flat" and r.f() < 0.1
	S.propane = r.f() < 0.22
	S.interiors = ["int_shoji", "int_lace", "int_shoji", "int_dark", "int_room"] if trad else null
	return S


## Builds one residential lot. D: {F (frame at the frontage centre, +z toward the road), w, depth,
## seed, lod, walls {left, right, back}, layout?, floors?, gardenSpot?, ...}.
static func build_lot(H, D: Dictionary) -> Dictionary:
	var ctx = H.ctx
	var M: Dictionary = H.M
	var P = H.props
	var r = ctx.rng("lot-" + str(D.seed))
	var F = D.F
	var W: float = D.w
	var Dp: float = D.depth
	var lod: int = _nn(D.get("lod"), 2)
	H.lod = lod
	var gy := func(x: float, z: float) -> float: return H.gy(F, x, z)
	var res := {"gardenSpots": [], "bikeSpots": [], "wallTops": []}
	var layout: String = D.layout if D.get("layout") else wpick(r, [["yard", 40], ["sidePark", 38], ["frontPark", 22 if Dp >= 13 else 0]])
	if W < 8.2 and layout == "sidePark":
		layout = "yard"
	var floors: int = D.floors if D.get("floors") else wpick(r, [[1, 8], [2, 74], [3, 18 if layout == "sidePark" and W < 10 else 6]])
	var hx0: float
	var hx1: float
	var hz0: float
	var hz1: float
	var park = null
	var gapA := 0.9 + r.f() * 0.35
	var gapB := 0.9 + r.f() * 0.35
	var rear := 1.4 + r.f() * 1.0 if Dp > 12.5 else 1.0 + r.f() * 0.5
	var setback: float
	if layout == "frontPark":
		setback = 5.6 + r.f() * 0.5
		hx0 = -W / 2.0 + gapA
		hx1 = W / 2.0 - gapB
		park = {"x0": -W / 2.0 + 0.25, "x1": minf(W / 2.0 - 1.4, -W / 2.0 + 0.25 + (5.4 if W > 9.5 else 2.8)), "z0": -setback + 0.3, "z1": -0.05, "side": 0}
	elif layout == "sidePark":
		setback = 1.7 + r.f() * 1.4
		var ps := -1 if r.f() < 0.5 else 1
		var pw := 2.75
		if ps < 0:
			park = {"x0": -W / 2.0 + 0.2, "x1": -W / 2.0 + 0.2 + pw, "z0": -5.6, "z1": -0.05}
			hx0 = park.x1 + 0.4
			hx1 = W / 2.0 - gapB
		else:
			park = {"x0": W / 2.0 - 0.2 - pw, "x1": W / 2.0 - 0.2, "z0": -5.6, "z1": -0.05}
			hx1 = park.x0 - 0.4
			hx0 = -W / 2.0 + gapA
		park["side"] = ps
	else:
		setback = 2.4 + r.f() * 2.3 if Dp > 12.5 else 1.8 + r.f() * 1.2
		hx0 = -W / 2.0 + gapA
		hx1 = W / 2.0 - gapB
	hz1 = -setback
	hz0 = -Dp + rear
	var max_d := 9.5 if floors == 1 else 9.0
	if hz1 - hz0 > max_d:
		hz0 = hz1 - max_d
	if hx1 - hx0 > 8.8:
		var cut := (hx1 - hx0) - 8.8 + r.f() * 0.8
		if r.f() < 0.5:
			hx0 += cut
		else:
			hx1 -= cut
	var hw := hx1 - hx0
	var hd := hz1 - hz0
	var hcx := (hx0 + hx1) / 2.0
	var hcz := (hz0 + hz1) / 2.0
	var S := make_spec(r, {"floors": floors, "traditional": D.get("traditional"), "roofType": D.get("roofType"), "allowFlat": floors >= 2 and hw < 7.5, "antennaP": D.get("antennaP")})
	S.w = hw
	S.d = hd
	S.floors = floors
	S.fh = 2.85
	S.lod = lod
	var HF = F.sub(hcx, 0, hcz, 0)
	var gmin := 1e9
	var gmax := -1e9
	for xz in [[hx0, hz0], [hx1, hz0], [hx0, hz1], [hx1, hz1], [hcx, hcz]]:
		var g: float = gy.call(xz[0], xz[1])
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
	S.floorY = gmax + 0.45 + (0.08 if S.traditional else 0.0)
	S.groundMin = gmin
	S.groundFront = gy.call(hcx, hz1 + 1)
	var du: float
	if layout == "sidePark":
		du = -hw / 2.0 + 0.95 if park.side < 0 else hw / 2.0 - 0.95
	else:
		du = (-1 if r.f() < 0.5 else 1) * (hw / 2.0 - 1.0 - r.f() * 0.6)
	var d_style: String = "door_slide" if S.traditional else wpick(r, [["door_wood", 40], ["door_white", 22], ["door_grey", 28], ["door_slide", 10]])
	if d_style == "door_slide":
		du = (T.sign(du) if du != 0.0 else 1.0) * minf(absf(du), hw / 2.0 - 1.35)
	var canopy: String = wpick(r, [["slab", 50], ["roof", 60 if S.traditional else 22], ["posts", 12]])
	S.door = {"u": du, "style": d_style, "canopy": canopy, "porchD": 1.15 + r.f() * 0.3}
	if floors >= 2 and lod >= 1 and r.f() < _nn(D.get("wingP"), 0.32) and hw > 6.2 and setback > 2.6 and layout != "frontPark":
		var ww := minf(3.6, hw * 0.45)
		var wd := minf(1.5, setback - 1.3)
		if wd > 0.9:
			var sgn := -1 if du > 0 else 1
			S.wing = {"cx": sgn * (hw / 2.0 - ww / 2.0), "cz": hd / 2.0 + wd / 2.0, "w": ww, "d": wd, "floors": 1, "attach": "front"}
	if floors >= 2 and r.f() < _nn(D.get("balconyP"), 0.72):
		var bw := minf(hw - 0.4, 2.8 + r.f() * 1.8)
		var bu := (r.f() - 0.5) * (hw - bw)
		if S.get("wing"):
			bu = -T.sign(S.wing.cx) * (hw / 2.0 - bw / 2.0 - 0.1)
		var over_door := absf(bu - du) < bw / 2.0 + 0.7
		if over_door:
			S.door.canopy = "slab" if S.door.canopy == "roof" else S.door.canopy
		var mix: String = pick(r, ["balcony", "student", "family", "sheets", "balcony"])
		var b := {"u": bu, "w": bw}
		b.depth = 0.85 + r.f() * 0.2
		b.rail = "panel" if r.f() < (0.5 if lod >= 2 else 0.8) else "bars"
		b.laundry = r.f() < _nn(D.get("laundryP"), 0.62)
		b.laundryMix = mix
		b.futon = r.f() < 0.22
		b.dish = r.f() < 0.3
		b.chime = r.f() < 0.12
		b.koinobori = r.f() < 0.06
		b.posts = false
		S.balcony = b
	if S.traditional and floors >= 2 and r.f() < 0.7 and not S.get("wing"):
		S.skirt = {"depth": 0.75 + r.f() * 0.25}
	var plate_name: String
	if D.get("plate"):
		plate_name = D.plate
	elif r.f() < 0.33:
		plate_name = "plateV%d" % (1 + 3 * int(floor(r.f() * 8)))
	else:
		plate_name = "plateH%d" % [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17][int(floor(r.f() * 12))]
	S.plate = plate_name
	S.wallMailbox = pick(r, ["mailbox", "mailbox_dark", "mailbox", "mailbox_red"])
	S.baseY = HF.origin().y
	var front_style: String
	if D.get("frontStyle"):
		front_style = D.frontStyle
	elif layout == "frontPark":
		front_style = pick(r, ["low", "low", "fence"])
	else:
		front_style = wpick(r, [["block", 26], ["plasterWall", 18], ["fence", 22], ["hedge", 18], ["low", 10], ["lattice", 6]])
	var has_gate: bool = front_style != "low" or r.f() < 0.5
	S.gatePlate = has_gate and front_style != "hedge" and r.f() < 0.8
	var gate_x := hcx + du
	var gate_w := 1.15
	var openings := []
	if park != null:
		openings.append([park.x0 - 0.05, park.x1 + 0.05, "park"])
	if has_gate:
		openings.append([gate_x - gate_w / 2.0 - 0.2, gate_x + gate_w / 2.0 + 0.2, "gate"])
	else:
		openings.append([gate_x - 0.8, gate_x + 0.8, "open"])
	openings = T.stable_sort(openings, func(a, b): return a[0] - b[0])
	var ops := []
	for o in openings:
		var last = ops[ops.size() - 1] if ops.size() > 0 else null
		if last != null and o[0] <= last[1] + 0.3:
			last[1] = maxf(last[1], o[1])
			last[2] += "+" + o[2]
		else:
			ops.append(o.duplicate())
	var segs := []
	var cur := -W / 2.0 + 0.06
	for o in ops:
		if o[0] - cur > 0.25:
			segs.append([cur, o[0]])
		cur = maxf(cur, o[1])
	if W / 2.0 - 0.06 - cur > 0.25:
		segs.append([cur, W / 2.0 - 0.06])
	var fz: float = _nn(D.get("frontZ"), -0.15)
	var wall_col: String
	if front_style == "block":
		wall_col = pick(r, ["#c9c7c0", "#d8d2c4", "#bdbcb5", "#e3dccd"])
	elif front_style == "plasterWall":
		wall_col = pick(r, PAL.plaster)
	else:
		wall_col = "#c9c7c0"
	var wh: float
	match front_style:
		"block": wh = 1.0 + r.f() * 0.3
		"plasterWall": wh = 1.1 + r.f() * 0.25
		"fence": wh = 0.5
		"low": wh = 0.42
		"lattice": wh = 0.35
		_: wh = 0.3
	for sg in segs:
		boundary_seg(H, F, sg[0], sg[1], fz, front_style, wh, wall_col, r, gy, lod, res, true)
	var gate_op = null
	for o in ops:
		if String(o[2]).contains("gate"):
			gate_op = o
			break
	if has_gate and gate_op != null:
		var pillar_col: String = wall_col if front_style == "plasterWall" else pick(r, ["#d8d2c4", "#bdb6a8", "#e3dccd", "#9d9c96", "#c9bfb0"])
		var pkind: String = "plaster" if front_style == "plasterWall" else pick(r, ["tile", "plaster", "tile"])
		var ph := maxf(1.35, wh + 0.2)
		var gxL := gate_x - gate_w / 2.0 - 0.15
		var gxR := gate_x + gate_w / 2.0 + 0.15
		for px in [gxL, gxR]:
			var g: float = gy.call(px, fz)
			F.boxB(M[House.WALLS[pkind][0]], pillar_col, 0.3, ph + 0.12, 0.3, px, g - 0.12, fz, {"uv": {"world": House.WALLS[pkind][1]}})
			F.boxB(M.plain, "#8f8c84", 0.36, 0.05, 0.36, px, g + ph, fz)
			H.col(F, px, fz, 0.3, 0.3, 0, g - 0.5, g + ph)
		var pp := gxR
		var g2: float = gy.call(pp, fz)
		if S.gatePlate:
			P.plate(F.sub(pp, 0, fz + 0.15, 0), 0, g2 + 1.1, 0.0, plate_name)
			F.box(M.atlas, "#ffffff", 0.09, 0.15, 0.03, pp, g2 + 0.82, fz + 0.165, {"uv": {"rect": H.A.rects.intercom, "white": H.A.white}})
			F.box(M.atlas, "#ffffff", 0.3, 0.24, 0.08, gxL, gy.call(gxL, fz) + 1.0, fz + 0.18, {"uv": {"rect": H.A.rects[S.wallMailbox], "white": H.A.white}})
			if r.f() < 0.3:
				F.box(M.plain, "#e9e5da", 0.2, 0.03, 0.05, gxL + 0.02, gy.call(gxL, fz) + 1.14, fz + 0.24, {"rz": 0.2})
			if lod >= 2 and r.f() < 0.35:
				F.box(M.atlas, "#ffffff", 0.13, 0.08, 0.01, pp, g2 + 0.55, fz + 0.155, {"uv": {"rect": H.A.rects["sticker_dog" if r.f() < 0.5 else "sticker_nosale"], "white": H.A.white}})
		if r.f() < 0.35:
			F.box(M.plain, "#4b4d52", 0.16, 0.2, 0.16, gxL, gy.call(gxL, fz) + ph + 0.15, fz)
			F.box(M.lampDim, null, 0.12, 0.14, 0.12, gxL, gy.call(gxL, fz) + ph + 0.17, fz, {"shadow": false})
		var open := r.f() < 0.45
		var lw := gate_w / 2.0 - 0.02
		for s in [-1, 1]:
			var hinge := gate_x + s * gate_w / 2.0
			var ang := s * 1.2 if open else 0.0
			var GF = F.sub(hinge, gy.call(hinge, fz), fz, -ang)
			GF.box(M.atlasCut, "#ffffff", lw, 1.0, 0.03, -s * lw / 2.0, 0.55, 0, {"uv": {"rect": H.A.rects.gate_alu, "white": H.A.white, "faces": "front+back"}, "noOutline": true})
			GF.box(M.plain, "#5c4a3e", 0.04, 1.0, 0.04, -s * 0.02, 0.55, 0)
		if not open:
			H.col(F, gate_x, fz, gate_w, 0.12, 0, gy.call(gate_x, fz) - 0.5, gy.call(gate_x, fz) + 1.05)
	var side_style: String = D.sideStyle if D.get("sideStyle") else pick(r, ["block", "block", "mesh", "mesh", "block"])
	var side_h := 0.9 + r.f() * 0.35 if side_style == "block" else 1.0
	var side_col: String = pick(r, ["#c9c7c0", "#bdbcb5", "#d8d2c4"])
	var side_z0 := fz - 0.15
	var side_z1 := -Dp + 0.08
	var walls: Dictionary = D.get("walls", {})
	if walls.get("left") != false:
		boundary_seg_z(H, F, -W / 2.0 + 0.07, side_z0, side_z1, side_style, side_h, side_col, r, gy)
	if walls.get("right"):
		boundary_seg_z(H, F, W / 2.0 - 0.07, side_z0, side_z1, side_style, side_h, side_col, r, gy)
	if walls.get("back") != false:
		var back_h: float = D.backH if D.get("backH") else (1.2 if side_style == "block" else 1.0)
		boundary_seg(H, F, -W / 2.0 + 0.07, W / 2.0 - 0.07, -Dp + 0.08, D.backStyle if D.get("backStyle") else side_style, back_h, side_col, r, gy, lod, null, false)
	var front_cover: String = "gravel" if D.get("traditional") else pick(r, ["gravel", "gravel", "lawn", "soil"])
	var fc_mat = M.lawn if front_cover == "lawn" else (M.soil if front_cover == "soil" else M.gravel)
	var fc_col := "#b9cf98" if front_cover == "lawn" else ("#cdbfa6" if front_cover == "soil" else "#d6d0c4")
	H.ground_rect(F, -W / 2.0 + 0.05, -Dp + 0.05, W / 2.0 - 0.05, fz - 0.1, fc_mat, fc_col, 0.02, 2.0 if front_cover == "lawn" else 1.5)
	H.ground_rect(F, -W / 2.0 + 0.02, fz - 0.1, W / 2.0 - 0.02, 0, M.concrete, "#c9c7c0", 0.03, 2)
	var porch_front_z: float = hz1 + (S.door.porchD if S.door.porchD else 1.2) + 0.55
	var apz0 := minf(porch_front_z, fz - 0.1)
	var apz1 := fz - 0.1
	if apz1 - apz0 > 0.2 and not (park != null and gate_x > park.x0 - 0.5 and gate_x < park.x1 + 0.5):
		if D.get("traditional") or (r.f() < 0.25 and front_cover != "soil"):
			P.stepping_stones(F, gate_x, apz1 - 0.3, gate_x + (r.f() - 0.5) * 0.3, apz0 + 0.2, gy, r)
		else:
			H.ground_rect(F, gate_x - 0.6, apz0, gate_x + 0.6, apz1, M.paver, pick(r, ["#d8d0c2", "#cfc6b6", "#c9c3b8", "#d9cdbd"]), 0.04, 1.2)
	if park != null:
		var pz0: float = park.z0 if layout == "frontPark" else maxf(park.z0, hz0 + 0.5)
		H.ground_rect(F, park.x0, pz0, park.x1, park.z1, M.concrete, pick(r, ["#c9c7c0", "#cdcbc3", "#c3c1b9"]), 0.05, 2)
		if r.f() < 0.5:
			for t in [0.33, 0.66]:
				H.ground_rect(F, park.x0 + 0.1, pz0 + (park.z1 - pz0) * t - 0.07, park.x1 - 0.1, pz0 + (park.z1 - pz0) * t + 0.07, M.lawn, "#a9c48a", 0.058, 2)
		elif lod >= 2:
			H.decal(F.sub(0, 0, 0, 0), "stain", (park.x0 + park.x1) / 2.0, 0, 1.0, 1.0, 0, "#ffffff", {"floor": true, "z": (pz0 + park.z1) / 2.0, "gy": gy})
		if r.f() < 0.35 and lod >= 1:
			_carport(H, F, park.x0, park.x1, pz0, park.z1, gy, r)
		var bx: float
		if park.side:
			bx = park.x1 - 0.5 if park.side < 0 else park.x0 + 0.5
		else:
			bx = park.x1 - 0.5
		var bz := maxf(pz0 + 1.2, hz1 - 1.2)
		if bz < park.z1 - 0.5:
			var w: Vector3 = F.w(bx, 0, bz)
			res.bikeSpots.append({"x": w.x, "z": w.z, "rotY": F.ry + (0.0 if r.f() < 0.5 else PI)})
	var hout := House.build_house(H, HF, S)
	if hout.porch != null and lod >= 1:
		var side := -1 if du > 0 else 1
		var bxl: float = hcx + du + side * ((hout.porch.w / 2.0) + 1.0)
		if bxl > hx0 + 0.5 and bxl < hx1 - 0.5 and r.f() < 0.6 and not (park != null and bxl > park.x0 - 0.8 and bxl < park.x1 + 0.8):
			var w: Vector3 = F.w(bxl, 0, hz1 + 0.5)
			res.bikeSpots.append({"x": w.x, "z": w.z, "rotY": F.ry + PI / 2.0 * (1 if r.f() < 0.5 else -1)})
	var keep: Array = D.get("keep", []).duplicate()
	if D.get("gardenSpot") and layout != "frontPark" and setback > 2.3:
		var sx: float = -park.side if park != null else (-1 if du > 0 else 1)
		var gx := sx * (W / 2.0 - 1.55)
		var gz := fz - minf(1.6, (setback - 0.3) / 2.0) - 0.1
		if not (gx - 1.2 < hx1 and gx + 1.2 > hx0 and gz - 1.2 < hz1):
			keep.append({"x": gx, "z": gz, "r": 1.4})
			var w: Vector3 = F.w(gx, 0, gz)
			res.gardenSpots.append({"x": w.x, "z": w.z, "r": 1.3})
			H.ground_rect(F, gx - 1.2, gz - 1.1, gx + 1.2, minf(gz + 1.1, fz - 0.12), M.lawn, "#b5cc93", 0.028, 2)
	var is_kept := func(x: float, z: float, rr: float = 0.5) -> bool:
		for k in keep:
			if Vector2(k.x - x, k.z - z).length() < k.r + rr:
				return true
		return false
	if lod >= 1:
		_garden_planting(H, F, {"W": W, "Dp": Dp, "fz": fz, "hx0": hx0, "hx1": hx1, "hz0": hz0, "hz1": hz1, "park": park, "gateX": gate_x, "gateW": gate_w,
			"frontStyle": front_style, "setback": setback, "traditional": bool(D.get("traditional")), "lod": lod, "du": du, "hcx": hcx}, r, gy, is_kept)
	if lod >= 1:
		var rear_depth := hz0 - (-Dp)
		if rear_depth > 1.6 and r.f() < 0.4:
			var lx := hcx + (r.f() - 0.5) * (hw - 3)
			P.laundry_stand(F, lx, hz0 - rear_depth / 2.0, gy, 2.4, r, r.f() < 0.7)
		if rear_depth > 1.3 and r.f() < 0.45:
			var sx := hcx + (-1 if r.f() < 0.5 else 1) * (hw / 2.0 - 1.2)
			var sw := 1.5 + r.f() * 0.4
			P.shed(F.sub(sx, 0, -Dp + 0.62, 0), 0, gy.call(sx, -Dp + 0.6), 0, r, sw)
			H.col(F, sx, -Dp + 0.62, 1.8, 0.95, 0, gy.call(sx, -Dp + 0.6) - 0.5, gy.call(sx, -Dp + 0.6) + 1.95)
		if r.f() < 0.45:
			var bx := gate_x + (-1 if gate_x > 0 else 1) * (gate_w / 2.0 + 0.9)
			if bx > -W / 2.0 + 0.6 and bx < W / 2.0 - 0.6 and not is_kept.call(bx, fz - 0.55) and not (park != null and bx > park.x0 - 0.3 and bx < park.x1 + 0.3):
				P.bins(F, bx, gy.call(bx, fz - 0.55), fz - 0.55, r, 1 + int(floor(r.f() * 2)))
		if lod >= 2 and r.f() < 0.5:
			var fx := hx0 - 0.35
			if fx > -W / 2.0 + 0.3:
				P.faucet(F.sub(fx, 0, hz1 - 1.2, PI / 2.0), 0, gy.call(fx, hz1 - 1.2), 0, r)
		if lod >= 2 and r.f() < 0.35:
			var g0: float = gy.call(hx1 + 0.3, hz1 - 0.7)
			P.broom(F.sub(hx1 + 0.02, 0, hz1 - 0.7, PI / 2.0), 0, g0, 0)
			if r.f() < 0.6:
				P.dustpan(F.sub(hx1 + 0.02, 0, hz1 - 1.15, PI / 2.0), 0, g0, 0.2)
		if lod >= 2 and r.f() < 0.2:
			P.toys(F, hcx + (r.f() - 0.5) * 2, gy.call(hcx, hz1 + 0.9), hz1 + 0.9, r)
	res.house = hout
	res.S = S
	res.layout = layout
	res.houseRect = {"hx0": hx0, "hx1": hx1, "hz0": hz0, "hz1": hz1}
	return res


## A boundary segment along local x from a to b at z: block, plasterWall, fence, hedge, low, lattice or mesh.
static func boundary_seg(H, F, a: float, b: float, z: float, style: String, h: float, col, r, gy: Callable, lod: int, res, _is_front: bool) -> void:
	var M: Dictionary = H.M
	var P = H.props
	var L := b - a
	if L < 0.2:
		return
	var t := 0.55 if style == "hedge" else 0.15
	var xm := (a + b) / 2.0
	var g0: float = gy.call(a, z)
	var g1: float = gy.call(b, z)
	var gm: float = gy.call(xm, z)
	if style == "block" or style == "plasterWall" or style == "low":
		var plaster := style == "plasterWall"
		H.sloped_wall(F, a, b, z, h, t, M.plaster if plaster else M.block, col, 3.0 if plaster else 1.6, 3.0 if plaster else 0.8)
		H.sloped_wall(F, a - 0.02, b + 0.02, z, h + 0.05, t + 0.05, M.plain, "#8f8c84" if plaster else "#b3b1aa", 0, 0, h)
		if style == "low" and lod >= 1:
			var n := maxi(1, int(T.js_round(L / 1.1)))
			for i in n:
				var x := a + (i + 0.5) * L / n
				var rad := 0.32 + r.f() * 0.12
				P.bush(F, x, gy.call(x, z - 0.45), z - 0.45, rad, r, {"pal": "green", "flowers": "azalea" if r.f() < 0.5 else null, "fn": 5})
		if lod >= 2 and r.f() < 0.7 and style != "low":
			H.decal(F, "moss", xm, gm + 0.12, L * 0.9, 0.3, z + t / 2.0 + 0.006, "#ffffff")
		if lod >= 2 and r.f() < 0.3 and style == "block":
			H.decal(F, "crack", a + L * (0.2 + r.f() * 0.6), gm + h * 0.5, 0.35, 0.5, z + t / 2.0 + 0.006, "#ffffff")
		H.col(F, xm, z, L, t + 0.04, 0, minf(g0, g1) - 0.5, maxf(g0, g1) + h)
		if res != null and h >= 0.9 and L > 1.2:
			var p: Vector3 = F.w(xm, 0, z)
			res.wallTops.append({"x": p.x, "z": p.z, "y": snappedf(H.L.height_at(p.x, p.z) + h + 0.05, 0.001), "rotY": F.ry, "len": snappedf(L, 0.01)})
	elif style == "fence":
		var bh := 0.45
		H.sloped_wall(F, a, b, z, bh, 0.15, M.block, col, 1.6, 0.8)
		H.sloped_wall(F, a - 0.02, b + 0.02, z, bh + 0.04, 0.19, M.plain, "#b3b1aa", 0, 0, bh)
		var fc: String = pick(r, ["#5c4a3e", "#4b4d52", "#8e949b", "#6b5242"])
		var n := maxi(1, int(T.js_round(L / 1.9)))
		for i in n + 1:
			var x := a + 0.05 + i * (L - 0.1) / n
			F.boxB(M.plain, fc, 0.05, 0.78, 0.05, x, gy.call(x, z) + bh + 0.04, z)
		for k in 6:
			H.sloped_wall(F, a + 0.05, b - 0.05, z, bh + 0.12 + k * 0.12 + 0.05, 0.02, M.plain, fc, 0, 0, bh + 0.12 + k * 0.12)
		H.col(F, xm, z, L, 0.2, 0, minf(g0, g1) - 0.5, maxf(g0, g1) + 1.3)
	elif style == "hedge":
		H.sloped_wall(F, a, b, z + 0.2, 0.28, 0.16, M.block, "#c9c7c0", 1.6, 0.8)
		var hh := 1.05 + r.f() * 0.35
		P.hedge(F, a + 0.05, b - 0.05, z - 0.12, hh, 0.55, r, "dark" if r.f() < 0.3 else "green", gy)
		H.col(F, xm, z - 0.1, L, 0.6, 0, minf(g0, g1) - 0.5, maxf(g0, g1) + 1.3)
	elif style == "lattice":
		H.sloped_wall(F, a, b, z, 0.3, 0.16, M.concrete, "#bdbcb5", 2, 2)
		var wc: String = pick(r, ["#6b4f3c", "#8a6446", "#5f4636"])
		var n := int(T.js_round(L / 0.11))
		for i in n + 1:
			var x := a + 0.03 + i * (L - 0.06) / n
			F.boxB(M.plain, wc, 0.035, 1.3, 0.05, x, gy.call(x, z) + 0.3, z)
		H.sloped_wall(F, a, b, z, 1.66, 0.08, M.plain, wc, 0, 0, 1.6)
		H.col(F, xm, z, L, 0.2, 0, minf(g0, g1) - 0.5, maxf(g0, g1) + 1.7)
	elif style == "mesh":
		_mesh_fence(H, F, a, b, z, h, r, gy)
		H.col(F, xm, z, L, 0.12, 0, minf(g0, g1) - 0.5, maxf(g0, g1) + h)


## A boundary along local z at x (side walls), through a frame rotated a quarter turn.
static func boundary_seg_z(H, F, x: float, z0: float, z1: float, style: String, h: float, col, r, gy: Callable) -> void:
	var SF = F.sub(x, 0, 0, PI / 2.0)
	boundary_seg(H, SF, -z0, -z1, 0, style, h, col, r, func(u: float, w: float) -> float: return gy.call(x + w, -u), 1, null, false)


static func _mesh_fence(H, F, a: float, b: float, z: float, h: float, r, gy: Callable) -> void:
	var M: Dictionary = H.M
	var c: String = pick(r, ["#5f8f6a", "#6b7f8f", "#8e949b"])
	var L := b - a
	var n := maxi(1, int(T.js_round(L / 2.0)))
	H.sloped_wall(F, a, b, z, 0.12, 0.12, M.concrete, "#b9b8b2", 2, 2)
	for i in n + 1:
		var x := a + 0.03 + i * (L - 0.06) / n
		F.boxB(M.plain, c, 0.045, h, 0.045, x, gy.call(x, z), z)
	H.sloped_wall(F, a, b, z, h, 0.035, M.plain, c, 0, 0, h - 0.035)
	H.sloped_wall(F, a, b, z, 0.2, 0.03, M.plain, c, 0, 0, 0.16)
	H.mesh_panel(F, a, b, z, 0.2, h - 0.04, c)


static func _carport(H, F, x0: float, x1: float, z0: float, z1: float, gy: Callable, r) -> void:
	var M: Dictionary = H.M
	var c: String = pick(r, ["#8e949b", "#5c4a3e", "#c9ccd1"])
	var hh := 2.3
	var px := x0 + 0.1
	var zA := z0 + 0.4
	var zB := z1 - 0.4
	for zz in [zA, zB]:
		F.boxB(M.plain, c, 0.08, hh, 0.08, px, gy.call(px, zz) - 0.1, zz)
		H.colC(F, px, zz, 0.07, gy.call(px, zz) - 0.5, gy.call(px, zz) + hh)
	var top := maxf(gy.call(px, zA), gy.call(px, zB)) + hh
	F.box(M.plain, c, 0.1, 0.14, z1 - z0 - 0.2, px, top, (z0 + z1) / 2.0)
	F.box(M.plain, c, x1 - x0 + 0.2, 0.08, 0.08, (x0 + x1) / 2.0 + 0.05, top + 0.12, z0 + 0.2)
	F.box(M.plain, c, x1 - x0 + 0.2, 0.08, 0.08, (x0 + x1) / 2.0 + 0.05, top + 0.12, z1 - 0.2)
	for k in range(1, 4):
		F.box(M.plain, c, x1 - x0 + 0.1, 0.05, 0.05, (x0 + x1) / 2.0 + 0.05, top + 0.14, z0 + 0.2 + k * (z1 - z0 - 0.4) / 4.0)
	F.box(M.poly, null, x1 - x0 + 0.25, 0.02, z1 - z0 - 0.2, (x0 + x1) / 2.0 + 0.05, top + 0.18, (z0 + z1) / 2.0, {"shadow": true, "noOutline": true})


static func _garden_planting(H, F, o: Dictionary, r, gy: Callable, is_kept: Callable) -> void:
	var P = H.props
	var W: float = o.W
	var fz: float = o.fz
	var hx0: float = o.hx0
	var hx1: float = o.hx1
	var hz1: float = o.hz1
	var park = o.park
	var lod: int = o.lod
	var du: float = o.du
	var hcx: float = o.hcx
	var z_in := fz - 0.55
	var in_park := func(x: float) -> bool: return park != null and x > park.x0 - 0.4 and x < park.x1 + 0.4
	var near_gate := func(x: float) -> bool: return absf(x - o.gateX) < o.gateW / 2.0 + 0.6
	if o.frontStyle != "hedge" and o.frontStyle != "low":
		var x := -W / 2.0 + 0.6
		while x < W / 2.0 - 0.5:
			if not (in_park.call(x) or near_gate.call(x) or is_kept.call(x, z_in)) and not (z_in < hz1 + 0.4):
				var t := r.f()
				if t < 0.4:
					P.bush(F, x, gy.call(x, z_in), z_in, 0.35 + r.f() * 0.15, r, {"pal": "green", "flowers": "azalea", "fn": 7})
				elif t < 0.6:
					P.bush(F, x, gy.call(x, z_in), z_in, 0.4 + r.f() * 0.15, r, {"pal": "dark"})
				elif t < 0.72:
					P.nandina(F, x, gy.call(x, z_in), z_in, 1.0, r)
				elif t < 0.8 and lod >= 2:
					P.bush(F, x, gy.call(x, z_in), z_in, 0.45, r, {"pal": "green", "flowers": "hydrangea", "fn": 5, "fsize": 0.18})
			x += 0.9 + r.f() * 0.8
	if o.setback > 2.4:
		var sx := -1 if du > 0 else 1
		var tx := hcx + sx * ((hx1 - hx0) / 2.0 - 0.8)
		var tz := (fz + hz1) / 2.0 - 0.1
		if not in_park.call(tx) and not is_kept.call(tx, tz, 1.0) and not near_gate.call(tx):
			if o.traditional or r.f() < 0.3:
				P.pine(F, tx, gy.call(tx, tz), tz, 1.1 + r.f() * 0.5, r)
			else:
				var s := 1.0 + r.f() * 0.5
				P.tree(F, tx, gy.call(tx, tz), tz, s, r, pick(r, ["maple", "olive", "osmanthus", "camellia", "round"]))
		if o.traditional and lod >= 2:
			var lx := hcx - sx * 1.2
			var lz := (fz + hz1) / 2.0
			if not is_kept.call(lx, lz, 0.6) and not near_gate.call(lx):
				P.lantern(F, lx, gy.call(lx, lz), lz)
	var base_z := hz1 + 0.45
	var x2 := hx0 + 0.5
	while x2 < hx1 - 0.4:
		if not (absf(x2 - (hcx + du)) < 1.3 or in_park.call(x2) or is_kept.call(x2, base_z)) and not (base_z > fz - 0.4):
			if r.f() < 0.55:
				var rad := 0.28 + r.f() * 0.12
				var pal := "green" if r.f() < 0.5 else "dark"
				P.bush(F, x2, gy.call(x2, base_z), base_z, rad, r, {"pal": pal, "flowers": "azalea" if r.f() < 0.3 else null, "fn": 4})
			elif lod >= 2 and r.f() < 0.4:
				P.planter(F, x2, gy.call(x2, base_z), base_z, 0.7 + r.f() * 0.3, r)
		x2 += 1.2 + r.f() * 1.2
	if o.traditional and lod >= 2 and r.f() < 0.8:
		var bx := hx1 - 0.9
		var bz := hz1 + 0.6
		if not is_kept.call(bx, bz) and base_z < fz - 0.8:
			P.bonsai_shelf(F, bx, gy.call(bx, bz), bz, r)
