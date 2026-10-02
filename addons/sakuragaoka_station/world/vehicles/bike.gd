# vehicles/bike.js: the Japanese city bicycle, following L.BIKE: forward +Z, origin on the ground
# midway between the wheel contacts, wheel radius 0.33, wheelbase 1.08, grips (±0.28, 1.02, 0.50),
# saddle top (0, 0.86, -0.22), basket centre (0, 0.92, 0.72). Local +X is the rider's left (bell
# side). A whole bike is one vertex-coloured mesh and one atlas mesh.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const VBS = preload("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
const Atlas = preload("res://addons/sakuragaoka_station/world/vehicles/atlas.gd")

const BIKE_COLORS := {
	"silver": "#c3c7cc", "white": "#e8e6e0", "blue": "#a9c5e2", "mint": "#a7d8c5", "cream": "#efe3c4",
	"red": "#94434d", "navy": "#44507a", "black": "#4a4753", "pink": "#eab3c4", "yellow": "#efd98e", "green": "#7fae8c",
}
const LIGHT := ["#c3c7cc", "#e8e6e0", "#efe3c4", "#efd98e", "#a7d8c5", "#a9c5e2", "#eab3c4"]
const TYRE := "#4a4552"
const RIM := "#c9cdd2"
const CHROME := "#d4d7db"
const STEEL := "#adb2b9"
const DARK := "#4b4852"
const SPOKE := "#cfd3d8"
const AXIS_P := Vector3(0, 0.33, 0.487)


static func lighten(hex, k: float) -> String:
	var c: Color = T.color(hex).lerp(Color(1, 1, 1), k)
	return "#" + T.hex_string(c)


## The chain case outline (z, y): the convex hull of the chainring and rear sprocket circles.
static func chain_case_geo() -> T.Geometry:
	return VBS.cg("bike-chaincase", func():
		var pts := []
		for i in 18:
			var a := i / 18.0 * TAU
			pts.append([-0.06 + cos(a) * 0.125, 0.27 + sin(a) * 0.125])
			pts.append([-0.54 + cos(a) * 0.062, 0.33 + sin(a) * 0.062])
		var h := VBS.hull(pts)
		var g := Geo.extrude_shape(Geo.shape(h), {"depth": 0.03, "bevelEnabled": true, "bevelThickness": 0.008,
			"bevelSize": 0.008, "bevelSegments": 1, "curveSegments": 4})
		g.apply_matrix4(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO))
		g.translate(-0.078, 0, 0)
		return g)


## The steering axis passes through (0, 0.33, 0.487) along (0, sin 70, -cos 70).
static func steer_matrix(a: float) -> Transform3D:
	var u := Vector3(0, sin(deg_to_rad(70.0)), -cos(deg_to_rad(70.0))).normalized()
	return Transform3D(Basis(), AXIS_P) * Transform3D(Basis(u, a), Vector3.ZERO) * Transform3D(Basis(), -AXIS_P)


static func _o(o: Dictionary, k: String, d = null):
	var v = o.get(k)
	return d if v == null else v


## makeBicycle(ctx, opts): a group. opts as the original: color, seed, lod, steer, crank, stand, lean,
## basket, basketColor, contents, childSeat, rainCover, saddleCover, umbrella, electric, isNew, tag,
## sticker, brand, saddleColor, fenderColor, rackColor, caseColor, childSeatColor, bagColor,
## batteryColor, lampColor, hubDynamo, bottleDynamo.
static func make_bicycle(ctx, o: Dictionary = {}):
	var r = ctx.rng("bike|" + str(_o(o, "seed", 1)))
	var M: Dictionary = Atlas.get_mats(ctx)
	var lod: int = _o(o, "lod", 1)
	var frame: String = _o(o, "color", BIKE_COLORS.silver)
	var V = VBS.VB.new()
	var D = VBS.VB.new()
	var saddle_c: String = _o(o, "saddleColor") if o.get("saddleColor") != null else r.pick(["#5a4438", "#48444f", "#6b5143", "#4c4957"])
	var grip_c := saddle_c
	var fender_c: String
	if o.get("fenderColor") != null:
		fender_c = o.fenderColor
	else:
		fender_c = CHROME if (o.get("isNew", false) or r.chance(0.7)) else frame
	var rack_c: String = o.rackColor if o.get("rackColor") != null else (CHROME if r.chance(0.6) else DARK)
	var case_c: String
	if o.get("caseColor") != null:
		case_c = o.caseColor
	else:
		case_c = frame if r.chance(0.5) else r.pick([CHROME, DARK])
	var basket_c: String
	if o.get("basketColor") != null:
		basket_c = o.basketColor
	else:
		basket_c = "#c4c8cd" if r.chance(0.55) else r.pick(["#4c4a55", "#e4e2dc", frame])
	var lock_c: String = "#47444e" if r.chance(0.6) else "#bfc3c8"
	var tub_r := 0.03 if o.get("electric", false) else 0.024
	var t_seg := 24 if lod else 16
	var t_rad := 5 if lod else 4

	var wheel := func(z: float, front: bool) -> void:
		V.torus(0.312, 0.0195, TYRE, [0, 0.33, z], [0, PI / 2.0, 0], t_rad, t_seg)
		V.torus(0.289, 0.009, RIM, [0, 0.33, z], [0, PI / 2.0, 0], 4, 20 if lod else 14)
		var hub := 0.038 if (front and o.get("hubDynamo", false)) else 0.024
		V.cyl(hub, hub, 0.11, STEEL, [0, 0.33, z], [0, 0, PI / 2.0], 8)
		if not front:
			V.cyl(0.05, 0.05, 0.03, DARK, [-0.05, 0.33, z], [0, 0, PI / 2.0], 10)
		var seg := 20 if lod else 14
		D.add(VBS.cg("bike-spokedisc", func(): return Geo.circle(0.287, seg)), SPOKE,
			VBS.mtx([0, 0.33, z], [0, PI / 2.0, 0]), null, Atlas.uv_into(Atlas.R.spokes))
	var fender_prof := [[-0.028, 0.005], [0.028, 0.005], [0.028, -0.005], [-0.028, -0.005]]

	# rear and frame (does not steer)
	wheel.call(-0.54, false)
	V.add(VBS.cg("bike-fenderR%d" % lod, func(): return VBS.arc_sweep(0.347, fender_prof, 0.95, 3.85, 16 if lod else 10)), fender_c, VBS.mtx([0, 0.33, -0.54]))
	V.bar([0, 0.105, -0.80], [0, 0.03, -0.80], 0.05, 0.005, DARK)
	V.box(0.04, 0.05, 0.012, "#d9463b", [0, 0.345, -0.899])
	V.tube([[0, 0.74, 0.338], [0, 0.60, 0.25], [0, 0.45, 0.15], [0, 0.34, 0.05], [0, 0.285, -0.02], [0, 0.27, -0.06]], tub_r, frame, 12 if lod else 8, 7 if lod else 5)
	V.rod([0, 0.683, 0.358], [0, 0.878, 0.287], 0.027, frame, 10)
	V.rod([0, 0.27, -0.06], [0, 0.752, -0.216], 0.02, frame, 10)
	V.rod([0, 0.73, -0.209], [0, 0.805, -0.232], 0.0125, CHROME, 6)
	V.tube([[0, 0.36, 0.07], [0, 0.45, -0.045], [0, 0.56, -0.15]], 0.013, frame, 5, 5)
	for s in [-1.0, 1.0]:
		V.rod([s * 0.035, 0.27, -0.08], [s * 0.062, 0.33, -0.54], 0.011, frame, 6)
		V.rod([s * 0.022, 0.70, -0.20], [s * 0.062, 0.335, -0.535], 0.0095, frame, 6)
	V.cyl(0.03, 0.03, 0.075, frame, [0, 0.27, -0.06], [0, 0, PI / 2.0], 10)
	if o.get("isNew", false):
		V.tube([[0, 0.752, 0.33], [0, 0.617, 0.244], [0, 0.468, 0.146], [0, 0.36, 0.05]], 0.009, lighten(frame, 0.55), 10, 5)
	V.add(chain_case_geo(), case_c, null)
	var case_light: bool = case_c == CHROME or LIGHT.has(case_c)
	var bi = o.get("brand")
	if bi == null:
		bi = 3 if o.get("electric", false) else r.pick([1, 2])
	D.add(VBS.cg("plane", func(): return Geo.plane(1, 1)), "#ffffff", VBS.mtx([-0.1215, 0.30, -0.30], [0, -PI / 2.0, 0], [0.22, 0.055, 1]), null,
		Atlas.uv_into(Atlas.R[("brandD" if case_light else "brandW") + str(bi)]))
	# crank and pedals
	var ca: float = o.crank if o.get("crank") != null else r.range(0, TAU)
	var cz := cos(ca) * 0.165
	var cy := sin(ca) * 0.165
	V.rod([-0.132, 0.27, -0.06], [0.1, 0.27, -0.06], 0.012, STEEL, 6)
	V.bar([-0.132, 0.27, -0.06], [-0.132, 0.27 + cy, -0.06 + cz], 0.014, 0.024, STEEL)
	V.bar([0.1, 0.27, -0.06], [0.1, 0.27 - cy, -0.06 - cz], 0.014, 0.024, STEEL)
	for pp in [[-0.19, 0.27 + cy, -0.06 + cz], [0.158, 0.27 - cy, -0.06 - cz]]:
		V.box(0.095, 0.026, 0.07, DARK, pp)
		V.box(0.02, 0.02, 0.072, "#e79a3c", [pp[0] + T.sign(pp[0]) * 0.04, pp[1], pp[2]])
	# saddle and springs
	if o.get("saddleCover") != null:
		V.rbox(0.235, 0.072, 0.30, 0.034, o.saddleCover, [0, 0.826, -0.225], null, 1)
		V.rbox(0.24, 0.022, 0.305, 0.01, lighten(o.saddleCover, -0.0), [0, 0.795, -0.225], null, 1)
	else:
		V.sph(1, saddle_c, [0, 0.83, -0.255], 12 if lod else 8, [0.108, 0.032, 0.125])
		V.sph(1, saddle_c, [0, 0.828, -0.135], 8, [0.06, 0.028, 0.10])
		V.rbox(0.19, 0.022, 0.2, 0.01, DARK, [0, 0.805, -0.24], null, 1)
	for s in [-1.0, 1.0]:
		V.cyl(0.016, 0.016, 0.045, DARK, [s * 0.055, 0.782, -0.305], null, 6)
	V.box(0.13, 0.02, 0.2, DARK, [0, 0.795, -0.24])
	# rear rack
	var RY := 0.735
	for x in [-0.075, 0.0, 0.075]:
		V.box(0.014, 0.014, 0.54, rack_c, [x, RY, -0.535])
	for z in [-0.29, -0.45, -0.62, -0.795]:
		V.box(0.164, 0.012, 0.014, rack_c, [0, RY, z])
	for s in [-1.0, 1.0]:
		V.rod([s * 0.075, RY, -0.79], [s * 0.066, 0.336, -0.545], 0.006, rack_c, 4)
		V.rod([s * 0.075, RY, -0.52], [s * 0.066, 0.336, -0.535], 0.006, rack_c, 4)
		V.rod([s * 0.05, RY, -0.275], [s * 0.024, 0.705, -0.205], 0.006, rack_c, 4)
	# ring lock on the seat stays
	V.rbox(0.10, 0.065, 0.105, 0.02, lock_c, [0, 0.587, -0.312], [0.723, 0, 0], 1)
	V.cyl(0.012, 0.012, 0.014, CHROME, [-0.054, 0.595, -0.31], [0, 0, PI / 2.0], 6)
	V.box(0.004, 0.03, 0.05, "#e58aa6", [0.051, 0.583, -0.315], [0.723, 0, 0])
	# two-leg stand
	if _o(o, "stand", "down") == "down":
		for s in [-1.0, 1.0]:
			V.rod([s * 0.07, 0.318, -0.556], [s * 0.135, 0.014, -0.632], 0.0085, STEEL, 5)
			V.box(0.05, 0.012, 0.045, DARK, [s * 0.135, 0.006, -0.632])
		V.rod([-0.132, 0.045, -0.628], [0.132, 0.045, -0.628], 0.007, STEEL, 5)
		V.rod([-0.085, 0.26, -0.575], [0.085, 0.26, -0.575], 0.006, STEEL, 4)
	else:
		for s in [-1.0, 1.0]:
			V.rod([s * 0.07, 0.318, -0.556], [s * 0.118, 0.44, -0.885], 0.0085, STEEL, 5)
		V.rod([-0.118, 0.44, -0.888], [0.118, 0.44, -0.888], 0.007, STEEL, 5)
	# registration and parking stickers on the seat tube (left side)
	D.add(VBS.cg("plane", func(): return Geo.plane(1, 1)), "#ffffff", VBS.mtx([0.0215, 0.47, -0.125], [-0.314, PI / 2.0, 0], [0.05, 0.025, 1]), null, Atlas.uv_into(Atlas.R.reg))
	if o.get("sticker") == "park":
		D.add(VBS.cg("plane", func(): return Geo.plane(1, 1)), "#ffffff", VBS.mtx([0.0215, 0.40, -0.103], [-0.314, PI / 2.0, 0], [0.05, 0.025, 1]), null, Atlas.uv_into(Atlas.R.park))
	if lod:
		V.tube([[0.20, 1.0, 0.525], [0.12, 0.9, 0.42], [0.03, 0.78, 0.35], [-0.028, 0.6, 0.25], [-0.03, 0.45, 0.155], [-0.03, 0.33, 0.04], [-0.05, 0.3, -0.2], [-0.06, 0.315, -0.44], [-0.07, 0.33, -0.5]], 0.0042, DARK, 14, 3)
	if o.get("electric", false):
		V.rbox(0.085, 0.30, 0.062, 0.02, _o(o, "batteryColor", "#4d4a56"), [0, 0.54, -0.196], [-0.314, 0, 0], 1)
		V.box(0.086, 0.04, 0.064, "#9aa1a8", [0, 0.405, -0.155], [-0.314, 0, 0])
		V.rbox(0.10, 0.12, 0.17, 0.03, DARK, [0, 0.235, -0.07], null, 1)
	# rear child seat (and rain canopy)
	if o.get("childSeat") == "rear":
		var cs: String = _o(o, "childSeatColor", "#8e959f")
		V.rbox(0.33, 0.07, 0.30, 0.025, cs, [0, RY + 0.05, -0.52], null, 1)
		V.rbox(0.36, 0.44, 0.06, 0.03, cs, [0, RY + 0.25, -0.70], [0.12, 0, 0], 1)
		for s in [-1.0, 1.0]:
			V.rbox(0.045, 0.2, 0.30, 0.02, cs, [s * 0.165, RY + 0.14, -0.52], null, 1)
			V.rbox(0.02, 0.22, 0.20, 0.01, cs, [s * 0.108, 0.52, -0.47], null, 1)
			V.box(0.07, 0.015, 0.06, DARK, [s * 0.14, 0.44, -0.42])
		V.rbox(0.31, 0.05, 0.26, 0.02, "#5b5f6b", [0, RY + 0.09, -0.52], null, 1)
		V.rod([-0.14, RY + 0.24, -0.38], [0.14, RY + 0.24, -0.38], 0.012, DARK, 6)
		if o.get("rainCover") != null:
			var rc: String = o.rainCover
			V.rbox(0.44, 0.36, 0.50, 0.07, rc, [0, RY + 0.21, -0.53], null, 2)
			V.sph(1, rc, [0, RY + 0.36, -0.53], 12, [0.215, 0.27, 0.245])
			V.rbox(0.45, 0.035, 0.51, 0.015, lighten(rc, 0.3), [0, RY + 0.035, -0.53], null, 1)
			for s in [-1.0, 1.0]:
				V.rbox(0.012, 0.2, 0.28, 0.005, "#d6dfe5", [s * 0.221, RY + 0.25, -0.52], null, 1)
			V.rbox(0.28, 0.2, 0.012, 0.005, "#d6dfe5", [0, RY + 0.25, -0.281], null, 1)
			V.box(0.30, 0.025, 0.006, "#e9ecef", [0, RY + 0.17, -0.781])
			V.rbox(0.05, 0.04, 0.02, 0.008, "#e8c547", [0.13, RY + 0.12, -0.279], null, 1)

	# front assembly (steers)
	var SM := steer_matrix(_o(o, "steer", 0.0))
	V.push(SM)
	D.push(SM)
	wheel.call(0.54, true)
	V.add(VBS.cg("bike-fenderF%d" % lod, func(): return VBS.arc_sweep(0.347, fender_prof, 0.22, 3.45, 16 if lod else 10)), fender_c, VBS.mtx([0, 0.33, 0.54]))
	V.box(0.035, 0.045, 0.01, "#f1efe6", [0, 0.52, 0.845], [-0.6, 0, 0])
	V.box(0.12, 0.03, 0.05, frame, [0, 0.683, 0.36], [-0.349, 0, 0])
	for s in [-1.0, 1.0]:
		V.tube([[s * 0.045, 0.68, 0.36], [s * 0.047, 0.52, 0.42], [s * 0.048, 0.40, 0.49], [s * 0.048, 0.33, 0.54]], 0.011, frame, 6, 5)
	V.box(0.05, 0.035, 0.03, DARK, [0, 0.705, 0.395], [-0.349, 0, 0])
	if o.get("bottleDynamo", false):
		V.cyl(0.018, 0.018, 0.07, CHROME, [0.05, 0.575, 0.428], [-0.43, 0, 0], 8)
	V.rod([0, 0.86, 0.293], [0, 0.966, 0.256], 0.0145, CHROME, 8)
	V.cyl(0.02, 0.02, 0.07, CHROME, [0, 0.966, 0.262], [0, 0, PI / 2.0], 8)
	var half := [[0.045, 0.966, 0.265], [0.085, 0.969, 0.33], [0.105, 0.976, 0.44], [0.135, 0.986, 0.535], [0.18, 1.0, 0.552], [0.215, 1.011, 0.525], [0.228, 1.015, 0.508]]
	var hbar := []
	for i in range(half.size() - 1, -1, -1):
		hbar.append([-half[i][0], half[i][1], half[i][2]])
	hbar.append([0, 0.966, 0.262])
	hbar.append_array(half)
	V.tube(hbar, 0.0115, CHROME, 26 if lod else 16, 5 if lod else 4)
	for s in [-1.0, 1.0]:
		V.rod([s * 0.226, 1.015, 0.51], [s * 0.338, 1.022, 0.49], 0.0175, grip_c, 8)
		V.box(0.022, 0.022, 0.03, DARK, [s * 0.212, 1.012, 0.52])
		V.bar([s * 0.215, 1.006, 0.54], [s * 0.325, 0.998, 0.575], 0.012, 0.02, CHROME if s < 0 else DARK)
	V.sph(0.027, CHROME, [0.158, 1.018, 0.553], 8, [1, 0.62, 1])
	V.cyl(0.008, 0.01, 0.02, DARK, [0.158, 1.0, 0.553], null, 6)
	if lod:
		V.tube([[-0.20, 1.0, 0.525], [-0.14, 0.93, 0.47], [-0.05, 0.80, 0.43], [0, 0.72, 0.40]], 0.0042, DARK, 8, 3)
	if o.get("electric", false):
		V.rbox(0.07, 0.035, 0.05, 0.01, "#3f3d47", [0.075, 0.99, 0.35], [0.4, 0, 0], 1)
	if o.get("umbrella", false):
		V.rod([-0.05, 0.968, 0.30], [-0.05, 1.34, 0.285], 0.008, DARK, 5)
		V.torus(0.028, 0.006, DARK, [-0.05, 1.345, 0.285], [PI / 2.0, 0, 0], 4, 10)
		V.box(0.03, 0.05, 0.02, DARK, [-0.05, 1.31, 0.285])
	# basket (or front child seat)
	if o.get("childSeat") == "front":
		var cs: String = _o(o, "childSeatColor", "#9aa0ab")
		V.rbox(0.28, 0.08, 0.25, 0.025, cs, [0, 0.84, 0.72], null, 1)
		V.rbox(0.30, 0.32, 0.05, 0.022, cs, [0, 1.0, 0.605], [-0.1, 0, 0], 1)
		for s in [-1.0, 1.0]:
			V.rbox(0.04, 0.13, 0.22, 0.015, cs, [s * 0.14, 0.92, 0.72], null, 1)
		V.rbox(0.25, 0.045, 0.2, 0.015, "#5b5f6b", [0, 0.885, 0.72], null, 1)
		V.rbox(0.26, 0.05, 0.05, 0.02, cs, [0, 1.0, 0.845], null, 1)
		for s in [-1.0, 1.0]:
			V.rod([s * 0.12, 0.99, 0.845], [s * 0.12, 0.88, 0.85], 0.01, cs, 5)
			V.box(0.07, 0.015, 0.06, DARK, [s * 0.09, 0.60, 0.70])
			V.rod([s * 0.09, 0.60, 0.70], [s * 0.1, 0.82, 0.71], 0.007, STEEL, 4)
		V.rod([0, 0.966, 0.27], [0, 0.93, 0.59], 0.012, STEEL, 5)
	elif _o(o, "basket", "wire") == "wire":
		var bx := 0.18
		var y0 := 0.80
		var y1 := 1.04
		var z0 := 0.59
		var z1 := 0.85
		for y in [y0, y1]:
			V.rod([-bx, y, z0], [bx, y, z0], 0.0055, basket_c, 4)
			V.rod([-bx, y, z1], [bx, y, z1], 0.0055, basket_c, 4)
			V.rod([-bx, y, z0], [-bx, y, z1], 0.0055, basket_c, 4)
			V.rod([bx, y, z0], [bx, y, z1], 0.0055, basket_c, 4)
		for x in [-bx, bx]:
			for z in [z0, z1]:
				V.rod([x, y0, z], [x, y1, z], 0.005, basket_c, 4)
		var P: T.Geometry = VBS.cg("plane", func(): return Geo.plane(1, 1))
		var W := 0.36
		var H := 0.24
		var Dd := 0.26
		var U := 0.36
		D.add(P, basket_c, VBS.mtx([0, 0.92, z1], null, [W, H, 1]), null, Atlas.uv_into(Atlas.R.basket, [0, 0, W / U, H / U]))
		D.add(P, basket_c, VBS.mtx([0, 0.92, z0], null, [W, H, 1]), null, Atlas.uv_into(Atlas.R.basket, [0, 0, W / U, H / U]))
		D.add(P, basket_c, VBS.mtx([bx, 0.92, 0.72], [0, PI / 2.0, 0], [Dd, H, 1]), null, Atlas.uv_into(Atlas.R.basket, [0, 0, Dd / U, H / U]))
		D.add(P, basket_c, VBS.mtx([-bx, 0.92, 0.72], [0, PI / 2.0, 0], [Dd, H, 1]), null, Atlas.uv_into(Atlas.R.basket, [0, 0, Dd / U, H / U]))
		D.add(P, basket_c, VBS.mtx([0, y0, 0.72], [-PI / 2.0, 0, 0], [W, Dd, 1]), null, Atlas.uv_into(Atlas.R.basket, [0, 0, W / U, Dd / U]))
		V.bar([0, 0.966, 0.27], [0, 0.985, 0.59], 0.03, 0.006, CHROME)
		for s in [-1.0, 1.0]:
			V.rod([s * 0.12, y0, 0.83], [s * 0.05, 0.335, 0.54], 0.005, CHROME, 4)
		var lamp_c: String = o.lampColor if o.get("lampColor") != null else (CHROME if r.chance(0.5) else DARK)
		V.cyl(0.03, 0.034, 0.085, lamp_c, [0, 0.755, 0.815], [PI / 2.0, 0, 0], 10)
		V.cyl(0.027, 0.027, 0.01, "#f4efcf", [0, 0.755, 0.86], [PI / 2.0, 0, 0], 10)
		V.rod([0, 0.79, 0.80], [0, 0.755, 0.80], 0.008, lamp_c, 4)
		if o.get("contents") == "bag":
			V.rbox(0.30, 0.23, 0.10, 0.02, "#3f4766", [0, 0.935, 0.705], [-0.16, 0, 0], 1)
			V.torus(0.055, 0.008, "#34394f", [0.0, 1.052, 0.69], [-0.16, 0, 0], 4, 10, PI)
			D.add(P, "#ffffff", VBS.mtx([0, 0.93, 0.652], [-0.16 + PI, 0, 0], [0.09, 0.09, 1]), null, Atlas.uv_into(Atlas.R.bag, [0.15, 0.2, 0.85, 0.9]))
			D.add(P, "#ffffff", VBS.mtx([0.13, 0.975, 0.635], [0, PI, 0], [0.05, 0.05, 1]), null, Atlas.uv_into(Atlas.R.charm))
			V.rod([0.13, 1.03, 0.64], [0.13, 1.0, 0.64], 0.002, "#e5d9b8", 3)
		elif o.get("contents") == "groceries":
			V.rbox(0.27, 0.19, 0.2, 0.04, _o(o, "bagColor", "#d9c7a8"), [0, 0.9, 0.72], null, 1)
			V.cyl(0.018, 0.018, 0.3, "#eef0e4", [0.06, 1.03, 0.66], [-0.55, 0, 0.25], 6)
			V.cyl(0.02, 0.012, 0.26, "#7fae62", [0.1, 1.18, 0.55], [-0.55, 0, 0.25], 6)
			V.rbox(0.1, 0.08, 0.06, 0.02, "#e9c56a", [-0.07, 1.0, 0.76], null, 1)
		if o.get("isNew", false):
			D.add(P, "#ffffff", VBS.mtx([0.01, 0.93, z1 + 0.012], [0.04, 0, 0.05], [0.118, 0.118, 1]), null, Atlas.uv_into(Atlas.R[_o(o, "tag", "tag1")]))
			V.rod([0.0, 1.04, z1 + 0.005], [0.008, 0.99, z1 + 0.011], 0.0015, "#e5e0d4", 3)
			D.add(P, "#ffffff", VBS.mtx([-bx - 0.004, 0.955, 0.72], [0, -PI / 2.0, 0], [0.09, 0.045, 1]), null, Atlas.uv_into(Atlas.R.seibi))
	V.pop()
	D.pop()

	var group := T.Group.new()
	group.name = "bicycle"
	var inner := T.Group.new()
	inner.rotation.z = _o(o, "lean", 0.0)
	group.add(inner)
	var m1 := T.MeshObj.new(V.build(), M.vcol)
	m1.cast_shadow = true
	m1.receive_shadow = true
	inner.add(m1)
	var g2 = D.build()
	if g2 != null:
		var m2 := T.MeshObj.new(g2, M.atlas)
		m2.cast_shadow = true
		m2.receive_shadow = true
		ctx.no_outline(m2)
		inner.add(m2)
	group.user_data["tris"] = V.tris + D.tris
	return group
