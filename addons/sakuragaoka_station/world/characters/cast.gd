# characters/cast.js: the people of 桜ヶ丘. Specs (look) + behaviours (deterministic idle / gestures
# / walking).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Sk = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")
const Anim = preload("res://addons/sakuragaoka_station/world/characters/anim.gd")
const Hm = preload("res://addons/sakuragaoka_station/world/characters/human.gd")
const Gear = preload("res://addons/sakuragaoka_station/world/characters/gear.gd")

const STEP_HEIGHT := 0.45

# ------------------------------------------------------------------ palettes
const HAIR := {
	"blue": {"top": "#4a4660", "base": "#3f3c52", "tip": "#3b374b", "hi": "#716f90", "hi2": "#9a98b8"},
	"dark": {"top": "#5d4743", "base": "#4f3c3e", "tip": "#47383c", "hi": "#8c706a", "hi2": "#b3978c"},
	"chestnut": {"top": "#8d6552", "base": "#785642", "tip": "#6a4b3d", "hi": "#b89076", "hi2": "#d6b59a"},
	"soft": {"top": "#9b7662", "base": "#876550", "tip": "#775a49", "hi": "#c3a187", "hi2": "#dcc0a6"},
	"gray": {"top": "#bdb9c3", "base": "#aca8b4", "tip": "#a19dab", "hi": "#dbd8e0", "hi2": "#e6e3ea"},
	"black": {"top": "#49404a", "base": "#403840", "tip": "#3c343e", "hi": "#6f6470", "hi2": "#948896"},
}
const SKIN := {"fair": "#f6dccb", "warm": "#f3d5c1", "tan": "#ebc8b0", "old": "#efd2c1"}

const STRIPES := {"base": "#44507a", "line": "#eeebe6", "bands": [[0.74, 0.8], [0.86, 0.91]]}
const PLAID := {"base": "#6c7690", "band": "#8c96ad", "dark": "#4d5670", "line": "#c7b27e"}
const UNIFORM := {"navy": "#434e6d", "navyDark": "#3a4461", "shirt": "#eceae5"}


static func face_f(o: Dictionary = {}) -> Dictionary:
	var f := {"skin": SKIN.fair, "ink": "#3b3144", "eyeP": 24, "eyeT": -12, "eyeW": 20, "eyeH": 22, "irisDark": "#4a3346", "irisMid": "#7d5b62", "irisLight": "#c69f8f",
		"lash": 1, "lidTop": -0.5, "iris": 0.37, "irisH": 0.46, "brow": "#5c4448", "browW": 1.7, "browGap": 3.5, "browArch": 2.4, "noseT": -32, "mouthT": -52, "mouthW": 9, "smile": 0.3, "blush": 0.75, "blushLines": true}
	f.merge(o, true)
	return f


static func face_m(o: Dictionary = {}) -> Dictionary:
	var f := {"eyeW": 19, "eyeH": 15, "lash": 0.5, "lidTop": -0.48, "iris": 0.36, "irisH": 0.5, "browW": 2.6, "browArch": 1.2, "browGap": 3, "blush": 0.25, "blushLines": false, "mouthW": 10, "smile": 0.1}
	f.merge(o, true)
	return face_f(f)


# ------------------------------------------------------------------ factory helpers
static func person(ctx, spec: Dictionary):
	var h = Hm.Human.new(ctx, spec)
	ctx.add(h.group)
	return h


static func collider(ctx, x: float, z: float, y: float, r: float = 0.24, hgt: float = 1.65) -> void:
	ctx.physics.addCylinder(x, z, r, y, y + hgt)


## physics.js groundHeight: the highest walkable top (walk box or ramp) under (x, z) not above
## feet + STEP_HEIGHT, else the terrain. Reads ctx.physics's records.
static func ground_height(ctx, x: float, z: float, feet_y: float = 1e9) -> float:
	if ctx.physics.has_method("groundHeight"):
		return ctx.physics.groundHeight(x, z, feet_y)
	var g: float = ctx.L.height_at(x, z)
	for it in ctx.physics.items:
		if it[0] != "walk" and it[0] != "ramp":
			continue
		var dx: float = x - it[1]
		var dz: float = z - it[2]
		var c := cos(it[5])
		var s := sin(it[5])
		var lx := dx * c - dz * s
		var lz := dx * s + dz * c
		if absf(lx) > it[3] or absf(lz) > it[4]:
			continue
		var top: float = it[9] if it[0] == "walk" else it[10] + (it[11] - it[10]) * (lz / (2.0 * it[4]) + 0.5)
		if top <= feet_y + STEP_HEIGHT and top > g:
			g = top
	return g


## ground under a spot (walk boxes of plaza/street/station included)
static func ground_at(ctx, x: float, z: float) -> float:
	var g0: float = ctx.L.height_at(x, z)
	return ground_height(ctx, x, z, g0 + 0.2)


## Is there a small object (e.g. the vehicles module's bicycle) whose bounds contain world point p?
## Used so the crossing girl only grips a handlebar that actually exists.
static func something_at(ctx, p: Vector3, pad: float = 0.2, max_size: float = 3.0) -> bool:
	var st := {"found": false}
	for root in [ctx.static_root, ctx.dynamic_root]:
		if not root or st.found:
			continue
		root.update_matrix_world(true)
		root.traverse(func(o):
			if st.found or not o.is_mesh or o.is_instanced or not o.geometry:
				return
			var g: T.Geometry = o.geometry
			if g.bounding_box == null:
				g.compute_bounding_box()
			if g.bounding_box == null:
				return
			var box: AABB = o.matrix_world * (g.bounding_box as AABB)
			var size := box.size
			if maxf(size.x, maxf(size.y, size.z)) > max_size:
				return
			box = box.grow(pad)
			if box.has_point(p):
				st.found = true)
	return st.found


# ------------------------------------------------------------------ the cast
static func make_cast(ctx) -> Array:
	var L = ctx.L
	var S: Dictionary = L.SPOTS
	var actors: Array = []
	var rail_train := func(track: String):
		var r = ctx.services.get("rail")
		if not r or not r.get("trains"):
			return null
		for t in r.trains:
			if t.track == track:
				return t
		return null
	var W := func(d, x: float, y: float, z: float) -> Vector3: return d.W(x, y, z)

	# ============================================================ 1. station staff (gate)
	if true:
		var spot: Dictionary = S.stationStaffGate
		var y: float = L.STATION.floorY
		var h = person(ctx, staff_spec("staffGate", 1.7, 11, HAIR.black))
		var d = Anim.Driver.new(ctx, h, {"seed": 11})
		var rot_y := 0.0 # faces the gate aisle / entrance (south)
		collider(ctx, spot.x, spot.z, y)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(spot.x, y, spot.z, rot_y)
			d.reset()
			var c := fmod(t, 22.0)
			var bow := Sk.smooth(8, 8.6, c) * (1.0 - Sk.smooth(9.4, 10.2, c))      # small nod to a passenger
			var paper := Sk.smooth(14, 15, c) * (1.0 - Sk.smooth(19, 20, c))        # checks the counter
			d.stand({"hx": 0.012 * sin(t * 0.45), "hrz": 0.012 * sin(t * 0.45), "hrx": 0.1 * bow + 0.05 * paper})
			Anim.rot_mul(h.b.spine, 0.12 * bow + 0.12 * paper, 0, 0)
			Anim.rot_mul(h.b.chest, 0.08 * bow, 0, 0)
			d.breathe(t)
			d.arm("L", 0.08 + 0.5 * paper, 0.1, 0, 0.25 + 0.9 * paper, [0, 0, 0])
			d.arm("R", 0.08 + 0.45 * paper, 0.1, 0, 0.25 + 1.0 * paper, [0, 0, 0])
			var yaw := 0.5 * sin(t * 0.21) + 0.25 * Sk.wave(t * 0.3, 3)
			d.look_yp(yaw * (1.0 - paper), 0.08 + 0.5 * paper + 0.3 * bow, dt, {"speed": 2})
			d.blink(t)})

	# ============================================================ 2. station staff (platform): watches the train, raises a hand
	if true:
		var spot: Dictionary = S.stationStaffPlatform
		var y: float = spot.y
		var h = person(ctx, staff_spec("staffPlat", 1.73, 12, HAIR.dark, {"point": true}))
		var d = Anim.Driver.new(ctx, h, {"seed": 12})
		var rot_y := PI + 0.35 # faces the track (north), turned a little toward the train's front (west)
		collider(ctx, spot.x, spot.z, y)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(spot.x, y, spot.z, rot_y)
			d.reset()
			var c := fmod(t, 120.0)
			# pointing check (指差確認) and the departure "all clear" hand
			var point := Sk.smooth(16, 16.6, c) * (1.0 - Sk.smooth(19, 19.8, c)) + Sk.smooth(40, 40.6, c) * (1.0 - Sk.smooth(42.6, 43.3, c))
			var raise := Sk.smooth(44.5, 45.2, c) * (1.0 - Sk.smooth(48.2, 49, c)) + Sk.smooth(72, 72.7, c) * (1.0 - Sk.smooth(75.6, 76.4, c))
			d.stand({"hx": 0.015 * sin(t * 0.37 + 1), "hrz": 0.015 * sin(t * 0.37 + 1), "stance": 1.3})
			d.breathe(t)
			# arms: left hand behind the back, right arm points / raises
			d.arm("L", -0.32, 0.14, -1.2, 1.4, [0.2, 0, 0])
			var fwd_r := Sk.lerp_(0.1, 1.45, point) + raise * 2.55
			var out_r := Sk.lerp_(0.12, 0.35, point) + raise * 0.15
			d.arm("R", minf(fwd_r, 2.7), out_r, 0, Sk.lerp_(0.2, 0.05, maxf(point, raise)) + raise * 0.1, [0, 0, 0])
			# look along the train (toward its front, west) or at the far track
			var tr = rail_train.call("A")
			var yaw := 0.35 * sin(t * 0.13) + 0.2
			if tr and absf(tr.x - spot.x) < 40:
				yaw = Sk.clamp_(atan2(-(tr.x - tr.dir * tr.length * 0.45 - spot.x), 2.5) * -1.0, -1.1, 1.1) * 0.6
			if point > 0.2:
				yaw = Sk.lerp_(yaw, 0.1, point)
			d.look_yp(yaw, 0.04, dt, {"speed": 1.5})
			d.blink(t)})

	# ============================================================ 3. schoolgirl with her bike at the crossing
	if true:
		var bs: Dictionary = S.crossingGirlBike
		var BK: Dictionary = L.BIKE
		# bike-local frame (+x = the bike's left). She stands close beside the frame, ~0.3 m behind the bar,
		# so her left hand reaches the left grip and her right hand rests on the bar beside the stem.
		var bl := func(lx: float, lz: float) -> Dictionary: return {"x": bs.x + lx * cos(bs.rotY) + lz * sin(bs.rotY), "z": bs.z - lx * sin(bs.rotY) + lz * cos(bs.rotY)}
		var spot: Dictionary = bl.call(0.36, 0.2)
		var y := ground_at(ctx, spot.x, spot.z)
		var by := ground_at(ctx, bs.x, bs.z)
		# only grip the handlebar if the vehicles module really parked her bike there
		var bar_c := Vector3(bs.x + sin(bs.rotY) * BK.handlebar.z, by + BK.handlebar.y, bs.z + cos(bs.rotY) * BK.handlebar.z)
		var has_bike := something_at(ctx, bar_c, 0.15)
		var h = person(ctx, {
			"key": "crossGirl", "sex": "f", "height": 1.57, "seed": 21, "skin": SKIN.fair,
			"face": face_f({"irisDark": "#3e3a58", "irisMid": "#5f6488", "irisLight": "#a9b0cc"}),
			"hair": {"style": "pony", "fringe": {"n": 7, "span": 60, "tip": 3, "skew": 7, "w": 0.052}, "side": {"long": 0.07, "w": 0.03}, "ponytail": {"len": 0.36, "th": 30, "w": 0.07, "tie": "#c86a78"}, "hairlineBack": -62},
			"hairTex": HAIR.blue, "stripes": STRIPES,
			"outfit": {"top": "sailor", "topColor": "#eeebe6", "scarf": "#c9707c", "bottom": "pleats", "bottomColor": "#4b5576", "hem": 0.53, "pleats": 18,
				"socks": {"color": "#454d6a", "top": 0.78}, "shoes": {"color": "#5b4336", "sole": "#4a3a36"}},
			"hands": {"L": "grip", "R": "relax"} if has_bike else {"L": "relax", "R": "hold"},
			"props": [func(hh): Gear.shoulder_bag(hh, {"color": "#475072", "charm": "#f2b5c8"}), func(hh): Gear.watch(hh, "L", "#b88a8a")],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 21, "hairAmp": 1.1})
		var rot_y: float = bs.rotY - 0.42 if has_bike else bs.rotY - 0.15   # beside the bike, turned toward it
		collider(ctx, spot.x, spot.z, y)
		var grip := func(sx: float) -> Vector3:
			var lx: float = sx * BK.handlebar.halfW
			var lz: float = BK.handlebar.z
			var c := cos(bs.rotY)
			var s := sin(bs.rotY)
			return Vector3(bs.x + lx * c + lz * s, by + BK.handlebar.y, bs.z - lx * s + lz * c)
		var gL: Vector3 = grip.call(1.0)
		var bp: Dictionary = bl.call(0.07, BK.handlebar.z - 0.01)
		var bar_p := Vector3(bp.x, by + BK.handlebar.y, bp.z)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(spot.x, y, spot.z, rot_y)
			d.reset()
			var sh := sin(t * 0.31 + 0.4)
			d.stand({"hx": 0.018 * sh, "hrz": 0.02 * sh, "hry": 0.08, "hz": 0.01, "footL": [0.1, h.P.ankle, -0.04], "footR": [-0.075, h.P.ankle, 0.06], "toeL": 0.25, "toeR": 0.05})
			Anim.rot_mul(h.b.spine, 0.06, 0.12, 0)
			Anim.rot_mul(h.b.chest, 0.04, 0.08, 0)
			d.breathe(t)
			if has_bike:
				# hands on the grips (wrist a little behind/above the grip)
				var tgt_l := gL + Vector3(0.0, 0.03, 0.035)
				var tgt_r := bar_p + Vector3(0, 0.045, 0.03)
				d.arm_ik("L", tgt_l, d.W(0.45, 0.95, -0.45))
				d.arm_ik("R", tgt_r, d.W(-0.5, 0.9, -0.5))
				Anim.rot(h.b.handL, 0.35, 0.3, -0.5)
				Anim.rot(h.b.handR, 0.9, -0.5, 0.2)
			else:
				# no bike in the scene: waits with her right hand on the bag strap, left arm hanging
				d.arm("L", 0.04, 0.1, 0, 0.18, [0, 0, 0])
				d.arm("R", 0.3, 0.05, -0.55, 1.55, [0.1, 0.2, 0])
			# watch the train passing the crossing (B, eastbound) or glance at the warning lights
			var tr = rail_train.call("B")
			var look: Vector3
			if tr and tr.x > -45 and tr.x < 25:
				look = Vector3(Sk.clamp_(tr.x, -30, 10), 2.0, L.RAIL.zB)
			else:
				look = Vector3(-11.2 + 2.5 * sin(t * 0.17), 1.8 + 0.6 * sin(t * 0.23), -42 - 2 * cos(t * 0.11))
			d.look_at(look, dt, {"speed": 2.5, "maxYaw": 1.0, "maxUp": 0.35})
			d.wind(t, dt)
			d.blink(t)})

	# ============================================================ 4. pedestrians waiting at the crossing
	if true:
		var base: Dictionary = S.crossingPedestrians
		var pw := {"x": base.x + 0.35, "z": base.z + 0.12}
		var pm := {"x": base.x - 0.55, "z": base.z - 0.28}
		var yw := ground_at(ctx, pw.x, pw.z)
		var ym := ground_at(ctx, pm.x, pm.z)
		var hw = person(ctx, {
			"key": "pedWoman", "sex": "f", "height": 1.6, "seed": 31, "skin": SKIN.warm,
			"face": face_f({"eyeH": 19, "lidTop": -0.46, "irisMid": "#7a5a50", "irisLight": "#b8957c", "blush": 0.5, "smile": 0.2}),
			"hair": {"fringe": {"n": 6, "span": 58, "tip": 8, "skew": 14, "w": 0.056, "part": 4, "partAt": -10}, "hairlineSide": -60, "hairlineBack": -74, "flare": 0.14, "side": {"w": 0.04}},
			"hairTex": HAIR.chestnut,
			"outfit": {"top": "cardigan", "topColor": "#e6c9c6", "band": "#dcbab8", "shirt": "#f0ebdf", "vAng": 30, "vY": 0.95, "bottom": "skirt", "bottomColor": "#d8c8aa", "hem": 0.24, "flare": 0.13, "legs": "#ecd0bc", "shoes": {"color": "#8a6a58", "sole": "#6a5448"}},
			"hands": {"R": "hold"},
			"props": [func(hh): Gear.hand_bag(hh, "R", {"w": 0.34, "h": 0.3, "d": 0.1, "color": "#b9c3a6", "handle": "#a7b194", "drop": 0.05, "logo": "#d9dccb"})],
		})
		var hm = person(ctx, {
			"key": "pedMan", "sex": "m", "height": 1.74, "seed": 32, "skin": SKIN.warm, "ears": true,
			"face": face_m({"irisMid": "#5d4a44", "irisLight": "#8f7564", "eyeH": 14, "browW": 2.8}),
			"hair": {"fringe": {"n": 5, "span": 50, "tip": 18, "skew": 16, "w": 0.06, "part": 6, "partAt": -14, "edgeDrop": 10}, "hairlineSide": -8, "hairlineBack": -64, "volume": 1.07, "crown": [[160, 20, 10, 0.06], [-160, 20, -10, 0.06]]},
			"hairTex": HAIR.dark,
			"outfit": {"top": "jacket", "topColor": "#a4a8b0", "lapel": "#9a9ea7", "shirt": "#eceae6", "tie": "#5b6e90", "buttons": "#6f737b", "vAng": 30, "vY": 0.72, "bottom": "trousers", "bottomColor": "#8f939b", "belt": "#4e4a4c", "pockets": true,
				"shoes": {"color": "#4f4444", "sole": "#3f3838"}},
			"hands": {"L": "hold", "R": "hold"},
			"props": [func(hh): Gear.hand_bag(hh, "L", {"w": 0.4, "h": 0.29, "d": 0.08, "color": "#5d4e48", "handle": "#4f423d", "drop": 0.02, "handleW": 0.016}), func(hh): Gear.phone(hh, "R")],
		})
		var dw = Anim.Driver.new(ctx, hw, {"seed": 31})
		var dm = Anim.Driver.new(ctx, hm, {"seed": 32})
		collider(ctx, pw.x, pw.z, yw)
		collider(ctx, pm.x, pm.z, ym, 0.26, 1.75)
		actors.append({"h": hw, "update": func(t: float, dt: float) -> void:
			dw.place(pw.x, yw, pw.z, PI - 0.12)
			dw.reset()
			var sh := sin(t * 0.27 + 2)
			dw.stand({"hx": 0.02 * sh, "hrz": 0.022 * sh, "footL": [0.075, hw.P.ankle, 0.02], "footR": [-0.085, hw.P.ankle, -0.03]})
			dw.breathe(t)
			dw.arm("R", 0.02, 0.1, 0, 0.12, [0, 0, 0])
			dw.arm("L", 0.16, 0.04, -0.75, 1.45, [0.1, 0.3, 0])   # left hand resting at the cardigan's front, at the waist
			var tr = rail_train.call("B")
			var look: Vector3
			if tr and tr.x > -60 and tr.x < 40:
				look = Vector3(Sk.clamp_(tr.x, -40, 30), 2.4, L.RAIL.zB)
			else:
				look = Vector3(-12, 2.4 + sin(t * 0.2), -44)
			dw.look_at(look, dt, {"speed": 2})
			dw.wind(t, dt)
			dw.blink(t)})
		actors.append({"h": hm, "update": func(t: float, dt: float) -> void:
			dm.place(pm.x, ym, pm.z, PI + 0.25)
			dm.reset()
			var sh := sin(t * 0.23)
			dm.stand({"hx": 0.015 * sh, "hrz": 0.015 * sh, "stance": 1.15})
			dm.breathe(t)
			dm.arm("L", 0.02, 0.06, 0, 0.1, [0, 0, 0])
			var phone_up := 1.0 - Sk.smooth(9, 10, fmod(t, 16.0)) * (1.0 - Sk.smooth(13, 14, fmod(t, 16.0)))  # looks up at the crossing now and then
			dm.arm("R", 0.55 * phone_up + 0.05, 0.05, -0.2, 1.7 * phone_up + 0.1, [0.3 * phone_up, 0, 0])
			dm.look_yp(0.1 * (1.0 - phone_up) + 0.05, Sk.lerp_(-0.08, 0.72, phone_up), dt, {"speed": 2.5})
			dm.blink(t)})

	# ============================================================ 5. reader on platform bench B1
	if true:
		var bn: Dictionary = L.PLATFORM.benchB1
		var floor_y: float = L.PLATFORM.y
		var seat := floor_y + 0.44
		var bx: float = bn.x
		var bz: float = bn.z
		var brot: float = bn.rotY
		var h = person(ctx, {
			"key": "reader", "sex": "m", "height": 1.72, "seed": 41, "skin": SKIN.fair, "ears": true,
			"face": face_m({"irisMid": "#5f5258", "irisLight": "#8f8088", "eyeH": 14, "lidTop": -0.4}),
			"hair": {"fringe": {"n": 6, "span": 56, "tip": 6, "skew": 10, "w": 0.055, "edgeDrop": 14}, "hairlineSide": -18, "hairlineBack": -68, "volume": 1.08, "side": {"w": 0.028}, "crown": [[150, -10, 20, 0.06], [-150, -10, -20, 0.06], [180, -20, 0, 0.07]]},
			"hairTex": HAIR.dark,
			"outfit": {"top": "sweater", "topColor": "#afbfa3", "band": "#9fb094", "shirtCollar": "#eeebe4", "bottom": "trousers", "bottomColor": "#cdbd9f", "belt": null,
				"shoes": {"color": "#e4e1db", "sole": "#cfc9c1", "accent": "#8a9fb8", "type": "sneaker"}},
			"hands": {"L": "hold", "R": "hold"},
			"props": [func(hh): Gear.glasses(hh, {"color": "#6b5a57"}), func(hh): hh._book = Gear.book(hh, {"cover": "#c7836a"}),
				func(hh): # messenger bag beside him on the bench (root bone)
					hh.add(Geo.box(1, 1, 1).translate(0, 0.5, 0).scale(0.36, 0.26, 0.1), {"bone": hh.b.root, "color": "#7c8aa0", "matrix": Transform3D(Basis.from_euler(Vector3(-0.25, 0.3, 0), EULER_ORDER_XYZ), Vector3(-0.52, 0.44 + 0.002, -0.05))})],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 41})
		var bk: Dictionary = h._book
		collider(ctx, bx, bz, floor_y, 0.3, 1.3)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(bx, floor_y, bz, brot)
			d.reset()
			var P: Dictionary = h.P
			var b: Dictionary = h.b
			# pelvis on the seat, slightly back
			b.hips.position = Vector3(0, seat - floor_y + 0.075 + (P.hip - P.hipJy), -0.1)
			Anim.rot_mul(b.hips, -0.08, 0, 0)
			h.group.update_matrix_world(true)
			d.leg("L", [0.11, P.ankle, 0.34], 0.12, [0.1, 1])
			d.leg("R", [-0.12, P.ankle, 0.4], -0.08, [0.1, 1])
			Anim.rot_mul(b.spine, 0.16, 0, 0)
			Anim.rot_mul(b.chest, 0.12, 0, 0)
			d.breathe(t, 0.8)
			# book in front of the chest, tilted toward the face
			var turn_c := fmod(t, 15.0)
			var turn := Sk.smooth(11.6, 12.6, turn_c)
			bk.book.position = Vector3(0, 0.23, 0.3)
			Anim.rot(bk.book, -1.05 + 0.03 * sin(t * 0.4), 0, 0.02 * sin(t * 0.3))
			Anim.rot(bk.page, 0, -turn * 2.9, 0)
			h.group.update_matrix_world(true)
			Sk.update_world(bk.book)
			var eL: Vector3 = bk.book.matrix_world * Vector3(-bk.W * 0.95, -bk.H * 0.18, -0.02)
			var lift := sin(Sk.clamp_((turn_c - 11.1) / 2.0, 0.0, 1.0) * PI)
			var eR: Vector3
			if turn_c > 11.2 and turn_c < 13.1:
				Sk.update_world(bk.page)
				eR = bk.page.matrix_world * Vector3(bk.W * 0.85, -bk.H * 0.25, 0.02)
			else:
				eR = bk.book.matrix_world * Vector3(bk.W * 0.95, -bk.H * 0.2, -0.02)
			eR.y += lift * 0.02
			d.arm_ik("L", eL, d.W(0.45, 0.8, -0.3))
			d.arm_ik("R", eR, d.W(-0.45, 0.8, -0.3))
			Anim.rot(b.handL, -0.3, 0.9, -0.2)
			Anim.rot(b.handR, -0.3, -0.9, 0.2)
			var tmp: Vector3 = bk.book.matrix_world * Vector3.ZERO
			d.look_at(tmp, dt, {"speed": 4, "maxDown": 0.9})
			# eyes lowered (reading)
			d.h.set_face("blink" if fmod(t + 3.1, 4.6) < 0.12 else "down")})

	# ============================================================ 6. café staff arranging the chalkboard
	if true:
		var board: Dictionary = S.cafeBoard
		var h = person(ctx, {
			"key": "cafe", "sex": "f", "height": 1.6, "seed": 51, "skin": SKIN.fair,
			"face": face_f({"irisMid": "#6e5448", "irisLight": "#b3927b", "smile": 0.6, "eyeH": 21}),
			"hair": {"fringe": {"n": 7, "span": 60, "tip": 10, "skew": 18, "w": 0.05, "part": 5, "partAt": 15}, "side": {"w": 0.03, "long": 0.02}, "ponytail": {"len": 0.2, "th": -8, "w": 0.06, "tie": "#8a6a58"}, "hairlineBack": -50},
			"hairTex": HAIR.dark,
			"outfit": {"top": "shirt", "topColor": "#efece6", "rolled": true, "collar": "#efece6", "tucked": true, "bottom": "trousers", "bottomColor": "#6d6862", "belt": "#5a4a44",
				"apron": {"color": "#6f7a61", "strap": "#5f694f", "hem": 0.42, "pocket": "#65705a"}, "shoes": {"color": "#6a5046", "sole": "#4f3e38"}},
			"hands": {"L": "hold", "R": "hold"},
			"props": [func(hh): Gear.chalk(hh, "R")],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 51})
		# the A-frame (shopsA): group at the board spot, rotY = café lot frame + (PI/2 - 0.4), leaves 0.56 x 0.9,
		# feet 0.2 m in front of / behind the centre. Probe where the front leaf's top bar really is.
		var e1: Dictionary = L.lot_frame(L.lot_by_id("E1"))
		var b_rot: float = e1.rotY + PI / 2.0 - 0.4
		var by := ground_at(ctx, board.x, board.z)
		var bc := cos(b_rot)
		var bsn := sin(b_rot)
		var BW := func(lx: float, ly: float, lz: float) -> Vector3: return Vector3(board.x + lx * bc + lz * bsn, by + ly, board.z - lx * bsn + lz * bc)
		var leaf_ang := atan2(0.2, 0.9)
		var z_top := 0.2 + 0.9 * sin(leaf_ang)                    # leaves splay outward at the top (as built today)
		if not something_at(ctx, BW.call(0.0, 0.88, z_top), 0.04, 1.2) and something_at(ctx, BW.call(0.0, 0.88, 0.2 - 0.9 * sin(leaf_ang)), 0.04, 1.2):
			z_top = 0.2 - 0.9 * sin(leaf_ang)
		var leaf_z := func(ly: float) -> float: return 0.2 + (z_top - 0.2) * Sk.clamp_(ly / 0.9, 0.0, 1.0)
		# she stands at the board's front-right corner (a little closer than the nominal spot so she can reach it)
		var me: Vector3 = BW.call(0.37, 0, 0.6)
		var px := me.x
		var pz := me.z
		var y := ground_at(ctx, px, pz)
		var aim: Vector3 = BW.call(0.0, 0, 0.25)
		var rot_y := atan2(aim.x - px, aim.z - pz)
		collider(ctx, px, pz, y)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(px, y, pz, rot_y)
			d.reset()
			var c := fmod(t, 16.0)
			# 0-6 s: straightens the board (both hands on the top bar) · 6.5-9.5 s: steps back, hands on hips, checks it
			# 9.5-14.5 s: adds a line with the chalk (left hand steadies the frame)
			var back := Sk.smooth(6, 6.8, c) * (1.0 - Sk.smooth(9.2, 10, c))
			var write := Sk.smooth(9.6, 10.4, c) * (1.0 - Sk.smooth(14.2, 15, c))
			var hold := 1.0 - back
			var bend := hold * (0.3 + 0.2 * write)
			var sh := sin(t * 0.33)
			d.stand({"hz": -0.03 * bend - 0.04 * back, "hx": 0.012 * sh, "hrz": 0.015 * sh, "hrx": 0.1 * bend, "footL": [0.085, h.P.ankle, 0.06], "footR": [-0.09, h.P.ankle, -0.07], "toeL": 0.1, "toeR": 0.25})
			Anim.rot_mul(h.b.spine, 0.3 * bend, -0.06 * write, 0)
			Anim.rot_mul(h.b.chest, 0.22 * bend, -0.08 * write, 0)
			d.breathe(t)
			var nudge := 0.01 * sin(t * 2.2) * (1.0 - write)
			var tL: Vector3 = BW.call(-0.02 + nudge, 0.925, leaf_z.call(0.9) + 0.012)
			var tR: Vector3 = BW.call(0.23 + nudge, 0.925, leaf_z.call(0.9) + 0.012)
			if write > 0:
				var wx := 0.045 * sin(t * 6.1) + 0.02 * sin(t * 13.7)
				var wy := 0.02 * sin(t * 3.3 + 1)
				var wyL := 0.77 + wy
				var tW: Vector3 = BW.call(0.1 + wx, wyL, leaf_z.call(wyL) + 0.06)
				tR = tR.lerp(tW, write)
			# hands-on-hips wrist positions (elbows out) blend into the board targets
			var rest_l: Vector3 = d.W(0.185, h.P.waist - 0.02, -0.03)
			var rest_r: Vector3 = d.W(-0.185, h.P.waist - 0.02, -0.03)
			d.arm_ik("L", rest_l.lerp(tL, hold), d.W(Sk.lerp_(0.75, 0.55, hold), 1.0, Sk.lerp_(-0.6, -0.35, hold)))
			d.arm_ik("R", rest_r.lerp(tR, hold), d.W(Sk.lerp_(-0.75, -0.55, hold), 1.0, Sk.lerp_(-0.6, -0.35, hold)))
			Anim.rot(h.b.handL, -0.4 * hold, 0.3 * hold, 0.5 * back)
			Anim.rot(h.b.handR, -0.5 * hold, -0.4 * hold, -0.5 * back)
			var look: Vector3 = BW.call(0.05, 0.7 + 0.1 * back, leaf_z.call(0.7))
			d.look_at(look, dt, {"speed": 3, "maxDown": 0.9, "tilt": 0.12 * back})
			d.wind(t, dt)
			d.blink(t)})

	# ============================================================ 7. elderly lady with shopping bags walking the east sidewalk
	if true:
		var A: Dictionary = S.elderly.path[0]
		var Bp: Dictionary = S.elderly.path[1]
		var h = person(ctx, {
			"key": "elder", "sex": "f", "height": 1.47, "width": 1.12, "belly": 0.1, "headK": 1.05, "seed": 61, "skin": SKIN.old,
			"face": face_f({"skin": SKIN.old, "closed": false, "eyeW": 18, "eyeH": 13, "lidTop": -0.3, "lash": 0.4, "iris": 0.4, "irisH": 0.55, "irisMid": "#5e4d48", "irisLight": "#8a766c", "blush": 0.35, "blushLines": false, "wrinkles": true, "smile": 0.7, "brow": "#9a9097", "browW": 1.8, "browGap": 4}),
			"hair": {"fringe": {"n": 6, "span": 62, "tip": 18, "skew": 26, "w": 0.06, "part": 8, "partAt": 0, "edgeDrop": 6}, "hairlineSide": -18, "hairlineBack": -44, "volume": 1.1, "bun": {"r": 0.042, "th": 12, "pin": "#8f6a5a"}},
			"hairTex": HAIR.gray,
			"outfit": {"top": "cardigan", "topColor": "#b8a9c1", "band": "#a797b1", "shirt": "#ebe4d6", "vAng": 26, "vY": 0.85, "jHemY": 0.7, "bottom": "trousers", "bottomColor": "#77707f", "shoes": {"color": "#6a5a58", "sole": "#51464a"}},
			"hands": {"L": "hold", "R": "hold"},
			"props": [func(hh): Gear.glasses(hh, {"color": "#9a8478"}),
				func(hh): Gear.hand_bag(hh, "R", {"w": 0.34, "h": 0.3, "d": 0.13, "color": "#c9bb96", "handle": "#b3a47f", "drop": 0.04, "leek": true, "greens": "#9dbb75"}),
				func(hh): Gear.hand_bag(hh, "L", {"w": 0.2, "h": 0.2, "d": 0.1, "color": "#c9a37a", "band": "#e8dcc6", "handle": "#9c7a58", "drop": 0.03})],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 61})
		var len := Sk.hypot(Bp.x - A.x, Bp.z - A.z)
		var ux: float = (Bp.x - A.x) / len
		var uz: float = (Bp.z - A.z) / len
		var v := 0.38
		var turn_t := 2.6
		var rest_t := 1.2
		var leg_t := len / v
		var period := 2.0 * (leg_t + turn_t + rest_t)
		# detour around the utility pole on the east sidewalk (R1E z=23)
		var pole_z = null
		for p in L.POLE_RUNS.R1E:
			if p.z > minf(A.z, Bp.z) and p.z < maxf(A.z, Bp.z):
				pole_z = p
				break
		var stride := 0.5
		var lift := 0.045
		var state := {"x": A.x, "z": A.z, "y": ground_at(ctx, A.x, A.z), "yaw": 0.0}
		var path_pos := func(s: float) -> Array:
			var x: float = A.x + ux * s
			var z: float = A.z + uz * s
			if pole_z != null:
				var dz: float = z - pole_z.z
				x += exp(-(dz * dz) / 1.4) * maxf(0.0, 0.55 - absf(x - pole_z.x))
			return [x, z]
		ctx.physics.addDynamic(func(): return [{"cx": state.x, "cz": state.z, "w": 0.46, "d": 0.46, "rotY": state.yaw, "y0": state.y, "y1": state.y + 1.5}])
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			var c := fmod(t, period)
			# phases: walk A->B, rest, turn, walk B->A, rest, turn
			var s: float
			var dir := 0
			var turning := 0.0
			var walking := 0.0
			var yaw: float
			var head_a := atan2(ux, uz)
			var head_b := atan2(-ux, -uz)
			if c < leg_t:
				s = c * v
				dir = 1
				walking = 1.0
				yaw = head_a
			elif c < leg_t + rest_t:
				s = len
				dir = 1
				yaw = head_a
			elif c < leg_t + rest_t + turn_t:
				s = len
				turning = (c - leg_t - rest_t) / turn_t
				yaw = head_a + PI * Sk.smooth(0, 1, turning)
			elif c < 2 * leg_t + rest_t + turn_t:
				s = len - (c - leg_t - rest_t - turn_t) * v
				dir = -1
				walking = 1.0
				yaw = head_b
			elif c < 2 * leg_t + 2 * rest_t + turn_t:
				s = 0.0
				yaw = head_b
			else:
				s = 0.0
				turning = (c - 2 * leg_t - 2 * rest_t - turn_t) / turn_t
				yaw = head_b + PI * Sk.smooth(0, 1, turning)
			var xz: Array = path_pos.call(s)
			var x: float = xz[0]
			var z: float = xz[1]
			var gy := ground_height(ctx, x, z, state.y + 0.2)
			state.x = x
			state.z = z
			state.y = gy
			state.yaw = yaw
			d.place(x, gy, z, yaw)
			d.reset()
			var P: Dictionary = h.P
			var b: Dictionary = h.b
			# gait: distance travelled drives the feet
			var dist: float = ((s if dir > 0 else 2.0 * len - s) if walking else 0.0)
			var ph: float = dist / stride if walking else turning * 2.0
			var bob := absf(sin(ph * PI)) if walking else 0.0
			b.hips.position.y += -0.012 + 0.012 * bob
			b.hips.position.x += 0.018 * sin(ph * PI) * (1.0 if walking else 0.3)
			Anim.rot_mul(b.hips, 0.08, 0.05 * sin(ph * PI) * walking, 0.03 * sin(ph * PI) * walking)
			h.group.update_matrix_world(true)
			var foot := func(n: String, off: float) -> Array:
				var sgn := 1.0 if n == "L" else -1.0
				var p := fmod(fmod(ph + off, 2.0) + 2.0, 2.0) # 0..2: 0..1.2 stance, 1.2..2 swing
				var zf: float
				var yf: float = P.ankle
				if not walking and not turning:
					zf = sgn * 0.02
				elif p < 1.2:
					zf = Sk.lerp_(stride * 0.3, -stride * 0.3, p / 1.2)
				else:
					var q := (p - 1.2) / 0.8
					zf = Sk.lerp_(-stride * 0.3, stride * 0.3, Sk.smooth(0, 1, q))
					yf += lift * sin(q * PI)
				if turning:
					zf *= 0.3
				return [sgn * P.hipJx * 1.1, yf, zf]
			d.leg("L", foot.call("L", 0.0), 0.18, [0.1, 1])
			d.leg("R", foot.call("R", 1.0), -0.18, [0.1, 1])
			Anim.rot_mul(b.spine, 0.2, 0, 0)
			Anim.rot_mul(b.chest, 0.16, -0.05 * sin(ph * PI) * walking, 0)
			d.breathe(t, 1.3)
			# arms hang with the bags, slight swing
			var sw := 0.1 * sin(ph * PI) if walking else 0.0
			d.arm("L", -0.15 + sw, 0.14, 0.1, 0.18, [0, 0, 0])
			d.arm("R", -0.15 - sw, 0.16, -0.1, 0.18, [0, 0, 0])
			d.look_yp(0.3 * Sk.wave(t * 0.2, 6) * (1.0 - walking * 0.5), -0.25 + 0.05 * bob, dt, {"speed": 2})
			# skirt follows the legs
			d.wind(t, dt)
			d.blink(t)})

	# ============================================================ 8. boy at the vending machine
	if true:
		var spot: Dictionary = S.vendingBoy
		var y := ground_at(ctx, spot.x, spot.z)
		var h = person(ctx, {
			"key": "boy", "sex": "m", "height": 1.5, "width": 0.88, "shoulder": 0.84, "headK": 1.08, "seed": 71, "skin": SKIN.warm, "ears": true,
			"face": face_m({"eyeH": 17, "eyeW": 19, "irisMid": "#5a4a46", "irisLight": "#937a6a", "blush": 0.4, "lidTop": -0.52}),
			"hair": {"fringe": {"n": 6, "span": 58, "tip": 10, "skew": -10, "w": 0.058, "edgeDrop": 12}, "hairlineSide": -16, "hairlineBack": -66, "volume": 1.1, "crown": [[170, 10, 25, 0.06], [-150, 5, -25, 0.06], [120, 0, 30, 0.05], [-110, 0, -25, 0.05]], "ahoge": true},
			"hairTex": HAIR.black,
			"outfit": {"top": "hoodie", "topColor": "#c9ccd0", "band": "#b7bbc1", "bottom": "shorts", "bottomColor": "#56627c", "socks": {"color": "#e9e6e0"},
				"shoes": {"color": "#e3e0da", "sole": "#c9c3bb", "accent": "#d0786a", "type": "sneaker"}},
			"hands": {"L": "hold", "R": "point"},
			"props": [func(hh): Gear.backpack(hh, {"color": "#6f8ea6", "pocket": "#63809a", "strap": "#56708a"})],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 71})
		collider(ctx, spot.x, spot.z, y, 0.24, 1.5)
		var vm = null
		for vv in L.VENDING:
			if vv.id == "V1a":
				vm = vv
				break
		var face: float = vm.z + 0.375 # machine front (faces south)
		var buttons := [[-0.22, 1.02], [0.02, 1.02], [0.12, 1.3], [-0.1, 1.3]]
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(spot.x, y, spot.z, spot.rotY)
			d.reset()
			var c := fmod(t, 8.4)
			var i := posmod(int(floorf(t / 2.1)), buttons.size())
			var fr := fmod(t, 2.1) / 2.1
			var bt: Array = buttons[i]
			var nb: Array = buttons[(i + 1) % buttons.size()]
			var m := Sk.smooth(0.7, 1, fr)
			var bx := Sk.lerp_(bt[0], nb[0], m)
			var byy := Sk.lerp_(bt[1], nb[1], m)
			var reach := 1.0 - Sk.smooth(6.2, 6.8, c) * (1.0 - Sk.smooth(7.7, 8.3, c))     # pulls the hand back to think
			var sh := sin(t * 0.4)
			d.stand({"hx": 0.012 * sh, "hrz": 0.02 * sh, "hz": 0.02 * reach, "footL": [0.08, h.P.ankle, 0.03], "footR": [-0.09, h.P.ankle, -0.02]})
			Anim.rot_mul(h.b.spine, 0.05 * reach, 0, 0)
			d.breathe(t)
			var tR := Vector3(vm.x - bx * cos(0.0), y + byy, face + 0.07)
			var rest: Vector3 = d.W(-0.16, 0.95, 0.25)
			d.arm_ik("R", rest.lerp(tR, reach), d.W(-0.45, 0.8, -0.2))
			Anim.rot(h.b.handR, -0.2, 0, 0)
			# left hand: coins at the chest / scratching the head while deciding
			var think := 1.0 - reach
			d.arm("L", 0.45 + 1.9 * think, 0.12 + 0.3 * think, -0.45 + 0.85 * think, 1.8 + 0.3 * think, [0.3, 0, 0])
			var look := Vector3(vm.x - bx * 0.6, y + 1.35 - 0.1 * think, vm.z)
			d.look_at(look, dt, {"speed": 3, "tilt": 0.12 * think})
			d.blink(t)})

	# ============================================================ 9. three students chatting by the tree bench
	if true:
		var c0: Dictionary = S.plazaStudents
		var ppl := [{"dx": -0.45, "dz": 0.3}, {"dx": 0.45, "dz": 0.38}, {"dx": 0.02, "dz": -0.5}]
		var cx: float = c0.x + (ppl[0].dx + ppl[1].dx + ppl[2].dx) / 3.0
		var cz: float = c0.z + (ppl[0].dz + ppl[1].dz + ppl[2].dz) / 3.0
		var specs := [
			{"key": "stuA", "sex": "f", "height": 1.55, "seed": 81, "skin": SKIN.fair, "variants": ["open", "blink", "talk", "laugh"],
				"face": face_f({"irisMid": "#6a5250", "irisLight": "#b49488", "eyeH": 23}),
				"hair": {"fringe": {"n": 7, "span": 60, "tip": 2, "skew": 5, "w": 0.05}, "side": {"long": 0.1, "w": 0.032}, "back": {"len": 0.3, "n": 7, "span": 108, "w": 0.075, "spread": 0.2}, "hairlineBack": -62,
					"accessory": func(hh): Gear.hair_clip(hh, 44, 36, "#f0c46a")},
				"hairTex": HAIR.dark, "stripes": STRIPES,
				"outfit": {"top": "sailor", "topColor": "#eeebe6", "scarf": "#c9707c", "bottom": "pleats", "bottomColor": "#4b5576", "hem": 0.54, "pleats": 18, "socks": {"color": "#454d6a", "top": 0.78}, "shoes": {"color": "#5b4336", "sole": "#4a3a36"}},
				"hands": {"L": "relax", "R": "hold"},
				"props": [func(hh): Gear.hand_bag(hh, "R", {"w": 0.36, "h": 0.26, "d": 0.09, "color": "#5b5062", "handle": "#4e4555", "drop": 0.0, "yaw": 0})]},
			{"key": "stuB", "sex": "f", "height": 1.59, "seed": 82, "skin": SKIN.warm, "variants": ["open", "blink", "talk", "laugh"],
				"face": face_f({"irisMid": "#5d6480", "irisLight": "#a3abc6", "eyeH": 21, "smile": 0.5}),
				"hair": {"fringe": {"n": 7, "span": 60, "tip": 4, "skew": -8, "w": 0.052}, "hairlineSide": -62, "hairlineBack": -72, "flare": 0.16, "side": {"w": 0.036}},
				"hairTex": HAIR.soft, "plaid": PLAID,
				"outfit": {"top": "blazer", "topColor": "#5a6380", "lapel": "#535c78", "shirt": "#eeebe6", "ribbon": "#b85f6c", "buttons": "#c9b27a", "emblem": "#c9b27a", "vAng": 30, "vY": 0.95, "jHemY": 0.8,
					"bottom": "pleats", "plaid": true, "bottomColor": "#6c7690", "hem": 0.53, "pleats": 16, "socks": {"color": "#454d6a", "top": 0.78}, "shoes": {"color": "#5b4336", "sole": "#4a3a36"}},
				"hands": {"L": "relax", "R": "relax"},
				"props": [func(hh): Gear.shoulder_bag(hh, {"color": "#6a6f86", "flap": "#61667c"})]},
			{"key": "stuC", "sex": "m", "height": 1.7, "seed": 83, "skin": SKIN.fair, "ears": true, "variants": ["open", "blink", "talk", "laugh"],
				"face": face_m({"irisMid": "#4f4a5e", "irisLight": "#86809a", "eyeH": 15}),
				"hair": {"fringe": {"n": 6, "span": 58, "tip": 5, "skew": 12, "w": 0.06, "edgeDrop": 14}, "hairlineSide": -20, "hairlineBack": -68, "volume": 1.11, "crown": [[160, 5, 25, 0.065], [-160, 0, -25, 0.065], [110, -5, 30, 0.05], [-115, -5, -30, 0.05]], "ahoge": true, "side": {"w": 0.026}},
				"hairTex": HAIR.blue,
				"outfit": {"top": "blazer", "topColor": "#5a6380", "lapel": "#535c78", "shirt": "#eeebe6", "tie": "#8a5260", "buttons": "#c9b27a", "emblem": "#c9b27a", "vAng": 30, "vY": 0.75, "bottom": "trousers", "bottomColor": "#555c70", "belt": "#3f3a40",
					"shoes": {"color": "#4f4444", "sole": "#3f3838"}},
				"hands": {"L": "fist", "R": "relax"}},
		]
		var hs: Array = []
		for i in specs.size():
			var sp: Dictionary = specs[i]
			var x: float = c0.x + ppl[i].dx
			var z: float = c0.z + ppl[i].dz
			var y := ground_at(ctx, x, z)
			var h = person(ctx, sp)
			var d = Anim.Driver.new(ctx, h, {"seed": sp.seed, "hairAmp": 1.1})
			collider(ctx, x, z, y)
			hs.append({"h": h, "d": d, "x": x, "y": y, "z": z, "rotY": atan2(cx - x, cz - z)})
		var heads: Array = hs.map(func(o): return Vector3(o.x, o.y + 1.45, o.z))
		# conversation script (period 12 s): speaker index per slot, laugh moments
		var slots := [0, 0, 1, 1, 2, 0, 1, 2, 2, 1, 0, 1]
		actors.append({"h": hs[0].h, "update": func(t: float, dt: float) -> void:
			var slot := int(floorf(fmod(t, 12.0)))
			var speaker: int = slots[slot]
			var laugh := Sk.smooth(7.6, 7.9, fmod(t, 12.0)) * (1.0 - Sk.smooth(9.0, 9.6, fmod(t, 12.0)))
			for i in hs.size():
				var o: Dictionary = hs[i]
				var h = o.h
				var d = o.d
				var talking := speaker == i and laugh < 0.5
				d.place(o.x, o.y, o.z, o.rotY + (-0.1 if i == 2 else 0.05))
				d.reset()
				var sh := sin(t * (0.3 + i * 0.05) + i * 2)
				d.stand({"hx": 0.02 * sh, "hrz": 0.022 * sh, "hry": 0.04 * sh, "footL": [0.07 + 0.01 * i, h.P.ankle, 0.02 * (i - 1)], "footR": [-0.08, h.P.ankle, -0.02 * (i - 1)]})
				d.breathe(t + i)
				Anim.rot_mul(h.b.spine, -0.06 * laugh + 0.04 * (1.0 if talking else 0.0), 0, 0)
				var g := sin(t * 3.1 + i) if talking else 0.0
				if i == 0: # sailor girl: bag in both hands in front, one hand gestures while talking
					d.arm("R", 0.18, 0.05, -0.1, 0.5, [0, 0, 0])
					d.arm("L", 0.25 + (0.35 + 0.15 * g if talking else 0.0) + laugh * 0.6, 0.02, -0.4, 0.9 + (0.6 if talking else 0.0) + laugh * 1.0, [0, 0, 0])
				elif i == 1: # blazer girl: animated gestures, hand to mouth when laughing
					d.arm("L", 0.1, 0.12, 0, 0.3, [0, 0, 0])
					d.arm("R", 0.2 + (0.45 + 0.2 * g if talking else 0.0) + laugh * 0.95, 0.12, 0.3 - laugh * 0.7, 0.6 + (0.7 + 0.3 * g if talking else 0.0) + laugh * 1.5, [0.2, 0, 0])
				else: # blazer boy: hand in pocket, other hand scratches his head when laughing
					d.arm("L", -0.05, 0.22, 0.2, 0.75, [0, 0, 0])
					d.arm("R", 0.15 + (0.3 + 0.2 * g if talking else 0.0) + laugh * 2.4, 0.2 + laugh * 0.5, 0, 0.5 + (0.5 if talking else 0.0) + laugh * 1.4, [0, 0, 0])
				# look at the speaker (or at a friend when speaking)
				var tgt: Vector3 = heads[(i + 1 + posmod(int(floorf(t / 3.0)), 2)) % 3] if speaker == i else heads[speaker]
				d.look_at(tgt, dt, {"speed": 3, "tilt": (0.06 * sin(t * 1.3) if talking else 0.04) - laugh * 0.08})
				Anim.rot_mul(h.b.head, -0.12 * laugh, 0, 0)
				d.wind(t, dt)
				var blk := fmod(t + i * 1.9, 3.1 + i * 0.7) < 0.12
				h.set_face("laugh" if laugh > 0.5 else ("blink" if blk else ("talk" if talking and sin(t * 11 + i) > -0.2 else "open")))})

	# ============================================================ 10. girl under the big tree, hair & skirt in the breeze
	if true:
		var spot: Dictionary = S.treeGirl
		var y := ground_at(ctx, spot.x, spot.z)
		var tree = null
		var sak = ctx.services.get("sakura")
		var trees: Array = sak.get("trees") if sak and sak.get("trees") else []
		for tr in trees:
			var dd := Sk.hypot(tr.x - L.PLAZA.tree.x, tr.z - L.PLAZA.tree.z)
			if dd < 3 and (tree == null or dd < tree.dd):
				tree = tr.duplicate()
				tree["dd"] = dd
		var canopy := Vector3(tree.x, tree.y, tree.z) if tree != null else Vector3(L.PLAZA.tree.x, 6.0, L.PLAZA.tree.z)
		var h = person(ctx, {
			"key": "treeGirl", "sex": "f", "height": 1.58, "seed": 91, "skin": SKIN.fair,
			"face": face_f({"irisDark": "#4a3a4e", "irisMid": "#7b6272", "irisLight": "#c7a7ae", "eyeH": 23, "smile": 0.35}),
			"hair": {"fringe": {"n": 7, "span": 62, "tip": 0, "skew": -6, "w": 0.05}, "side": {"long": 0.16, "w": 0.033}, "back": {"len": 0.5, "n": 7, "span": 108, "w": 0.09, "spread": 0.2, "taper": 0.2}, "hairlineBack": -64},
			"hairTex": HAIR.chestnut,
			"outfit": {"top": "blouse", "topColor": "#f1ece2", "collar": "#f1ece2", "tucked": true, "bottom": "skirt", "bottomColor": "#a9bdd3", "hem": 0.3, "flare": 0.16, "legs": "#f2d8c7", "shoes": {"color": "#8b6a5c", "sole": "#6a5248"}},
			"hands": {"L": "relax", "R": "relax"},
			"props": [func(hh): Gear.shoulder_bag(hh, {"color": "#d9c7a6", "flap": "#cdb996", "strap": "#b89f7c"})],
		})
		var d = Anim.Driver.new(ctx, h, {"seed": 91, "hairAmp": 1.15, "skirtAmp": 1.5, "wind": 1.2})
		collider(ctx, spot.x, spot.z, y)
		actors.append({"h": h, "update": func(t: float, dt: float) -> void:
			d.place(spot.x, y, spot.z, spot.rotY)
			d.reset()
			var gust: float = ctx.shared.uGust
			var sh := sin(t * 0.25)
			d.stand({"hx": 0.015 * sh, "hrz": 0.02 * sh, "footL": [0.075, h.P.ankle, 0.04], "footR": [-0.08, h.P.ankle, -0.03], "toeL": 0.2})
			Anim.rot_mul(h.b.spine, -0.06, 0, 0)
			Anim.rot_mul(h.b.chest, -0.08, 0, 0)
			d.breathe(t)
			# holds her hair back when the gust is strong
			var hold := Sk.smooth(0.5, 0.68, gust)
			d.arm("L", 0.05, 0.1, 0, 0.2, [0, 0, 0])
			d.look_at(canopy, dt, {"speed": 1.2, "maxUp": 0.75, "tilt": 0.1 * sin(t * 0.21)})
			d.arm("R", 0.05, 0.08, 0, 0.12, [0, 0, 0])
			if hold > 0.001:
				# hand holding the hair back beside the right ear
				var hd: Dictionary = h.P.head
				Sk.update_world(h.b.head)
				var ear: Vector3 = h.b.head.matrix_world * Vector3(-hd.rx * 1.25, hd.cy - hd.ry * 0.15, hd.cz - hd.rz * 0.25)
				var rest: Vector3 = d.W(-0.19, 0.78, 0.03)
				d.arm_ik("R", rest.lerp(ear, hold), d.W(-0.6, 1.1, -0.2))
				Anim.rot(h.b.handR, -0.3 * hold, 0, -0.9 * hold)
			d.wind(t, dt, {"boost": 1.0})
			d.blink(t)})

	return actors


# ------------------------------------------------------------------ uniformed station staff
static func staff_spec(key: String, height: float, seed: int, hair_tex: Dictionary, o: Dictionary = {}) -> Dictionary:
	return {
		"key": key, "sex": "m", "height": height, "seed": seed, "skin": SKIN.warm, "ears": true,
		"face": face_m({"irisMid": "#5a4c48", "irisLight": "#8a766a", "eyeH": 14, "lidTop": -0.45}),
		"hair": {"fringe": {"n": 5, "span": 52, "tip": 14, "skew": 10, "w": 0.05, "edgeDrop": 6}, "hairlineSide": -14, "hairlineBack": -62, "volume": 1.035},
		"hairTex": hair_tex,
		"outfit": {"top": "staff", "topColor": UNIFORM.navy, "lapel": UNIFORM.navyDark, "shirt": UNIFORM.shirt, "tie": "#39425c", "buttons": "#d3b268", "vAng": 26, "vY": 0.8, "emblem": "#e39bb5", "nameTag": "#efece6",
			"bottom": "trousers", "bottomColor": UNIFORM.navyDark, "belt": "#353046", "gloves": "#eceae6", "shoes": {"color": "#443c42", "sole": "#39333a"}},
		"hands": {"L": "relax", "R": "point" if o.get("point") else "relax"},
		"props": [func(hh): Gear.staff_cap(hh, {"color": "#3e4968", "band": "#343d58", "visor": "#2f3548"})],
	}
