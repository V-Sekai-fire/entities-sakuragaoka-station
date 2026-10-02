# vehicles.js: every bicycle in town (plaza racks, shop fronts, the crossing girl's bike, house bike
# spots, bikes leaning on walls), the parked cars (white kei van, pastel kei car, retro taxi) and the
# small car waiting at the level crossing. Each vehicle is one vertex-coloured mesh and one atlas
# mesh (and glass for cars). Publishes ctx.services.vehicles = {bikes, cars}.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Bike = preload("res://addons/sakuragaoka_station/world/vehicles/bike.gd")
const Cars = preload("res://addons/sakuragaoka_station/world/vehicles/cars.gd")


func build(ctx) -> void:
	var L = ctx.L
	var root := T.Group.new()
	root.name = "vehicles"
	ctx.add_static(root)
	var S: Dictionary = L.SPOTS
	var has_street: bool = ctx.services.has("street")
	var svc := {"bikes": [], "cars": []}
	var BC: Dictionary = Bike.BIKE_COLORS

	# The surface height: the terrain, or the highest walkable top at most about 0.4 m up. The
	# original asks its physics; the port's physics only counts colliders, so it falls back as the
	# original's catch does.
	var gy := func(x: float, z: float) -> float:
		var h: float = L.height_at(x, z)
		var g := h
		if ctx.physics.has_method("groundHeight"):
			g = maxf(h, ctx.physics.groundHeight(x, z, h))
		return g

	var place_bike := func(x: float, z: float, rot_y: float, opts: Dictionary, lift: float = 0.0, collide: bool = true):
		var b = Bike.make_bicycle(ctx, opts)
		var fx := sin(rot_y)
		var fz := cos(rot_y)
		var hf: float = gy.call(x + fx * 0.54, z + fz * 0.54) + lift
		var hr: float = gy.call(x - fx * 0.54, z - fz * 0.54) + lift
		var y: float
		var pitch := 0.0
		if absf(hf - hr) < 0.09:
			y = (hf + hr) / 2.0
			pitch = atan2(hr - hf, 1.08)
		else:
			y = minf(hf, hr)
		b.position = Vector3(x, y - 0.004, z)
		b.rotation.y = rot_y
		b.children[0].rotation.x = pitch
		root.add(b)
		if collide:
			ctx.physics.addBox(x, z, 0.64, 1.8, rot_y, y - 0.05, y + 1.1)
		svc.bikes.append({"x": x, "z": z, "y": y, "rotY": rot_y})
		return b

	# plaza bicycle parking (L.PLAZA.bikeRows; plaza builds the racks): 16 of 24 slots
	var lift_p := 0.02 if ctx.services.has("plaza") else 0.0
	var fill := [
		[1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 0],
		[1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1],
	]
	var cfg := [
		{"color": BC.silver, "sticker": "park", "bottleDynamo": true},
		{"color": BC.mint, "childSeat": "rear", "rainCover": "#5b6a8f", "electric": true, "childSeatColor": "#8e959f"},
		{"color": BC.white, "saddleCover": "#eaa3b8", "sticker": "park"},
		{"color": BC.navy, "basketColor": "#4c4a55", "steer": 0.42, "askew": 0.07},
		{"color": BC.cream, "childSeat": "front", "electric": true, "umbrella": true, "childSeatColor": "#b9b3a4"},
		{"color": BC.red, "sticker": "park"},
		{"color": BC.black, "basketColor": "#4c4a55", "saddleCover": "#d8cdb4"},
		{"color": BC.blue, "basketColor": "#e4e2dc", "umbrella": true, "sticker": "park"},
		{"color": BC.silver, "childSeat": "rear", "electric": true, "childSeatColor": "#7a8290"},
		{"color": BC.white, "bottleDynamo": true, "sticker": "park"},
		{"color": BC.mint, "saddleCover": "#9fc9b8", "steer": -0.34, "askew": -0.09},
		{"color": BC.navy, "electric": true, "childSeat": "rear", "rainCover": "#9aa3ad", "childSeatColor": "#5e6778"},
		{"color": BC.cream, "contents": "groceries", "bagColor": "#b9d0c4"},
		{"color": BC.black, "sticker": "park"},
		{"color": BC.red, "saddleCover": "#44507a"},
		{"color": BC.silver, "umbrella": true, "basketColor": "#4c4a55"},
	]
	var k := 0
	var rr = ctx.rng("vehicles-plaza")
	var rows: Array = L.PLAZA.bikeRows
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var i := 0
		var x: float = row.x0
		while x <= row.x1 + 1e-6:
			if fill[ri][i]:
				var c: Dictionary = cfg[k % cfg.size()]
				k += 1
				var ask: float = c.get("askew", 0.0)
				var o := {"seed": "plaza%d" % k}
				o["steer"] = c.steer if c.get("steer") != null else rr.range(-0.12, 0.12)
				o.merge(c, true)
				place_bike.call(x + ask * 0.6, row.z + (0.06 if ask else 0.0), row.rotY + ask, o, lift_p)
			x += row.step
			i += 1

	# shop fronts
	var konbini := [
		{"color": BC.white, "contents": "groceries", "saddleCover": "#eaa3b8"},
		{"color": BC.blue, "steer": 0.18},
	]
	for i in S.konbiniBikes.size():
		var p: Dictionary = S.konbiniBikes[i]
		var o := {"seed": "konbini%d" % i}
		o.merge(konbini[i % 2], true)
		place_bike.call(p.x, p.z, p.rotY, o, 0.01)
	place_bike.call(S.bookstoreBike.x, S.bookstoreBike.z, S.bookstoreBike.rotY,
		{"seed": "book", "color": BC.navy, "basketColor": "#4c4a55", "steer": -0.1, "electric": true}, 0.01)
	# the bicycle shop: three new bikes with price tags
	var new_bikes := [{"color": BC.mint, "tag": "tag1"}, {"color": BC.cream, "tag": "tag2"}, {"color": "#9cc0e6", "tag": "tag3"}]
	for i in S.bikeShopBikes.size():
		var p: Dictionary = S.bikeShopBikes[i]
		var o := {"seed": "shop%d" % i, "isNew": true, "basketColor": "#cfd3d8", "fenderColor": "#d8dbdf", "rackColor": "#d8dbdf",
			"caseColor": new_bikes[i].color, "saddleColor": "#4c4957", "brand": 2 if i == 1 else 1, "steer": 0.0, "crank": 0.4}
		o.merge(new_bikes[i], true)
		place_bike.call(p.x, p.z, p.rotY, o, 0.035)

	# the girl waiting at the crossing (characters stands her on the bike's left)
	var pg: Dictionary = S.crossingGirlBike
	place_bike.call(pg.x, pg.z, pg.rotY, {"seed": "girl", "color": BC.mint, "contents": "bag", "stand": "up", "steer": 0.0,
		"crank": 2.2, "basketColor": "#c4c8cd", "saddleColor": "#5a4438"}, 0.02 if has_street else 0.0)

	# houses' bike spots (fallback: a few spots in front of house lots)
	var spots: Array = []
	if ctx.services.has("houses") and ctx.services.houses.get("bikeSpots") != null:
		spots = ctx.services.houses.bikeSpots
	if spots.is_empty():
		for id in ["W5", "W7", "E4", "E7", "W9", "E9"]:
			var lot = L.lot_by_id(id)
			var f: Dictionary = L.lot_frame(lot)
			var p: Dictionary = L.lot_to_world(lot, 3.2, -2.4)
			spots.append({"x": p.x, "z": p.z, "rotY": f.rotY + PI / 2.0})
	var rh = ctx.rng("vehicles-houses")
	var palette := [BC.silver, BC.white, BC.cream, BC.mint, BC.navy, BC.blue, BC.red, BC.black, BC.pink, BC.green]
	var mx := mini(11, spots.size())
	for i in mx:
		var p: Dictionary = spots[i]
		var near: bool = absf(p.x - L.street_center_x(p.z)) < 22 and p.z > -60 and p.z < 130
		var fam: bool = rh.chance(0.45)
		var o := {"seed": "house%d" % i, "lod": 1 if near else 0, "color": palette[i % palette.size()]}
		o["electric"] = fam and rh.chance(0.7)
		o["childSeat"] = (("rear" if rh.chance(0.65) else "front") if fam else null)
		o["rainCover"] = rh.pick(["#5b6a8f", "#9aa3ad", "#c98fa2"]) if (fam and rh.chance(0.4)) else null
		o["saddleCover"] = rh.pick(["#eaa3b8", "#9fc9b8", "#d8cdb4", "#8fb3d9"]) if rh.chance(0.35) else null
		o["contents"] = "groceries" if rh.chance(0.18) else "none"
		o["umbrella"] = rh.chance(0.2)
		o["steer"] = rh.range(-0.25, 0.25)
		o["bottleDynamo"] = rh.chance(0.4)
		place_bike.call(p.x, p.z, p.rotY, o, 0.01)

	# bikes leaning on walls (kickstand up, handlebar end against the wall)
	var LEAN := 0.14
	var OFF := 0.49
	# (wx, wz) is a point on the wall face, (dir_x, dir_z) the unit normal away from it, along +-1 the facing
	var lean_on := func(wx: float, wz: float, dir_x: float, dir_z: float, along: float, opts: Dictionary):
		var x := wx + dir_x * OFF
		var z := wz + dir_z * OFF
		var rot_y := atan2(-dir_z * along, dir_x * along)
		var lx := cos(rot_y)
		var lz := -sin(rot_y)
		var toward_wall_plus_x := (lx * -dir_x + lz * -dir_z) > 0.0
		var o := {"stand": "up", "lean": -LEAN if toward_wall_plus_x else LEAN}
		o.merge(opts, true)
		return place_bike.call(x, z, rot_y, o, 0.005)
	# the station staff bicycle shed
	if ctx.services.has("station"):
		var staff := [{"i": 0, "color": BC.black, "basketColor": "#4c4a55"}, {"i": 2, "color": BC.silver, "electric": true},
			{"i": 3, "color": BC.navy, "saddleCover": "#8fb3d9", "steer": 0.2}]
		for s in staff:
			var o := {"seed": "staff%d" % s.i, "sticker": null}
			o.merge(s, true)
			place_bike.call(22.75 + 0.62 * s.i, -31.98, PI, o, 0.004)
	# the W3 frontage wall, on the sidewalk
	var lot3 = L.lot_by_id("W3")
	var f3: Dictionary = L.lot_frame(lot3)
	var p3: Dictionary = L.lot_to_world(lot3, 2.4, S.w3Wall.lz + 0.075)
	lean_on.call(p3.x, p3.z, sin(f3.rotY), cos(f3.rotY), 1, {"seed": "lean-w3", "color": BC.red, "saddleCover": "#44507a", "steer": -0.06})
	# a wall of the NW block along R2 (from houses' wallTops, if any)
	var walls := []
	if ctx.services.has("houses"):
		for w in ctx.services.houses.get("wallTops", []):
			if w.len >= 2.0 and w.x > -48 and w.x < -17 and w.z > -8 and w.z < -4.5 and absf(cos(w.rotY)) > 0.9:
				walls.append(w)
	T.stable_sort(walls, func(a, b): return absf(a.x + 24) - absf(b.x + 24))
	if not walls.is_empty():
		var w: Dictionary = walls[0]
		var nx := sin(w.rotY)
		var nz := cos(w.rotY)
		lean_on.call(w.x + 0.8 + nx * 0.1, w.z + nz * 0.1, nx, nz, -1,
			{"seed": "lean-nw", "color": BC.cream, "basketColor": "#4c4a55", "childSeat": "rear", "childSeatColor": "#8e959f"})

	# cars
	var road_lift := 0.02 if has_street else 0.0
	var place_car := func(car, x: float, z: float, rot_y: float):
		var lift := road_lift
		var d: Dictionary = car.user_data.dims
		var fx := sin(rot_y)
		var fz := cos(rot_y)
		var hF: float = L.height_at(x + fx * d.wb / 2.0, z + fz * d.wb / 2.0) + lift
		var hR: float = L.height_at(x - fx * d.wb / 2.0, z - fz * d.wb / 2.0) + lift
		var y := (hF + hR) / 2.0 - 0.012
		car.position = Vector3(x, y, z)
		car.rotation.y = rot_y
		car.user_data.inner.rotation.x = atan2(hR - hF, d.wb)
		root.add(car)
		var zc: float = (d.zF + d.zR) / 2.0
		var ln: float = d.zF - d.zR
		ctx.physics.addBox(x + fx * zc, z + fz * zc, d.W + 0.08, ln, rot_y, y - 0.1, y + d.H)
		svc.cars.append({"name": car.name, "x": x, "z": z, "y": y, "rotY": rot_y, "W": d.W, "L": ln, "roofY": y + d.H})
		return car
	# the white kei van on the west shoulder of the main street (facing north)
	var fv: Dictionary = L.street_frame(S.whiteVan.z, -1, 2.0)
	place_car.call(Cars.make_kei_van(ctx), fv.x, fv.z, atan2(fv.tx, fv.tz))
	place_car.call(Cars.make_kei_car(ctx), S.keiCar.x, S.keiCar.z, S.keiCar.rotY)
	place_car.call(Cars.make_taxi(ctx), S.taxi.x, S.taxi.z, S.taxi.rotY)
	place_car.call(Cars.make_compact(ctx), S.crossingCar.x, S.crossingCar.z, S.crossingCar.rotY)

	ctx.services["vehicles"] = svc
