# trains.js: two 2-car 桜川電鉄 EMUs (5000形), timetable traffic, doors, lights, interiors, passenger
# silhouettes, petals resting on the roof, dynamic colliders and services.rail.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Builder = preload("res://addons/sakuragaoka_station/world/trains/builder.gd")
const Car = preload("res://addons/sakuragaoka_station/world/trains/car.gd")
const Textures = preload("res://addons/sakuragaoka_station/world/trains/textures.gd")
const Schedule = preload("res://addons/sakuragaoka_station/world/trains/schedule.gd")

const BODY_DEFS := {"paint": {}, "metal": {}, "matte": {}, "interior": {}, "glass": {}, "iLight": {}, "led": {"uv": true}, "head": {}, "tail": {}, "decal": {"uv": true}, "petal": {"uv": true}}
const DOOR_DEFS := {"paint": {}, "glass": {}, "decal": {"uv": true}}
const NO_SHADOW := ["glass", "iLight", "led", "head", "tail", "decal", "petal", "interior"]
const LOD_KEYS := ["interior", "iLight", "petal"]  # hidden when the train is far from the camera
const LOD_FAR := 95.0
const DOOR_SLIDE := 0.66


static func mod(a: float, n: float) -> float:
	return fmod(fmod(a, n) + n, n)


# ------------------------------------------------------------------ materials
## The original patches the toon shader with a sun specular + rim term (uSunW, uSpec); the port
## keeps the parameters on the material for the renderer.
static func spec_mat(ctx, name: String, shin: float, strength: float, lo: float, hi: float):
	var m = ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0, "name": "trains." + name})
	if m.user_data.get("trainSpec"):
		return m
	m.user_data["trainSpec"] = true
	m.user_data["uSunW"] = ctx.shared.uSunDir
	m.user_data["uSpec"] = Vector4(shin, strength, lo, hi)
	m.user_data["programCacheKey"] = "paint|trainSpec"
	return m


static func make_materials(ctx, tex: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var led = mat.emissive("#ffffff", 1.3, {"map": tex.led})
	led.polygonOffset = true
	led.polygonOffsetFactor = -2
	led.polygonOffsetUnits = -4
	return {
		"paint": spec_mat(ctx, "paint", 26, 0.2, 0.5, 0.62),
		"metal": spec_mat(ctx, "metal", 70, 0.5, 0.45, 0.55),
		"matte": mat.toon("#ffffff", {"vertexColors": true, "paint": 0}),
		"interior": mat.toon("#ffffff", {"vertexColors": true, "paint": 0, "emissive": "#40301f", "emissiveIntensity": 1, "name": "trains.interior"}),
		"glass": mat.glass({"tint": "#8ca5b9", "opacity": 0.3}),
		"iLight": mat.emissive("#fff4e2", 1.15),
		"led": led,
		"head": mat.emissive("#fff8ee", 2.4),
		"tail": mat.emissive("#ff3a36", 1.9),
		"lamp": mat.emissive("#ff5040", 1.6),
		"decal": mat.decal("#ffffff", {"map": tex.decal, "paint": 0}),
		"petal": mat.foliage("#ffffff", tex.petal, {"vertexColors": true, "paint": 0}),
	}


# ------------------------------------------------------------------ one train (2 cars)
static func build_train(ctx, S, id: String, tex: Dictionary, MAT: Dictionary) -> Dictionary:
	var cfg: Dictionary = S.CFG[id]
	var B := Builder.Buckets.new(BODY_DEFS)
	var d_neg := Builder.Buckets.new(DOOR_DEFS)
	var d_pos := Builder.Buckets.new(DOOR_DEFS)
	var rng = ctx.rng("trains." + id)
	var wheelsets := []
	var lamps := []
	for c in 2:
		var car_sign := 1 if c == 0 else -1
		var car_m := Builder.M([car_sign * 9, 0, 0], [0, 0.0 if c == 0 else PI, 0])
		B.push(car_m); d_neg.push(car_m); d_pos.push(car_m)
		var ws := []
		var lp := []
		Car.build_car(B, {
			"lit": "head" if c == 0 else "tail", "animSide": -1 if c == 0 else 1, "carSign": car_sign, "doorsNeg": d_neg, "doorsPos": d_pos,
			"uv": {"dec": tex.dec, "led": tex.ledUV},
			"numFront": "num" + str((0 if id == "A" else 2) + c), "numSide": "num" + str((4 if id == "A" else 6) + c),
			"destKey": "dest" + id, "runKey": "run" + id, "lcdKey": "lcd" + id, "sideKey": "side" + id,
			"panto": c == 1, "motor": c == 1, "rng": rng, "crew": "driver" if c == 0 else "conductor", "jakurei": c == 1,
			"wheelsets": ws, "lamps": lp,
		})
		B.pop(); d_neg.pop(); d_pos.pop()
		for w in ws:
			wheelsets.append(car_m * Vector3(w[0], w[1], w[2]))
		for l in lp:
			lamps.append(car_m * Vector3(l[0], l[1], l[2]))
	# ---- gangway between the cars (train frame, x ∈ [-0.2, 0.2])
	B.box("matte", 0.44, 2.02, 1.12, [0, 2.3, 0], "#5d5f6b")
	for i in 5:
		var x := -0.16 + i * 0.08
		for whdyz in [[0.035, 2.1, 0.04, 2.3, -0.6], [0.035, 2.1, 0.04, 2.3, 0.6], [0.035, 0.04, 1.24, 3.33, 0]]:
			B.box("matte", whdyz[0], whdyz[1], whdyz[2], [x, whdyz[3], whdyz[4]], "#6a6c78" if i % 2 else "#51535e")
	B.box("metal", 0.5, 0.03, 0.96, [0, 1.3, 0], "#9aa1a8")
	B.box("metal", 0.56, 0.12, 0.14, [0, 0.9, 0], "#50555e")
	for z in [-0.95, -0.72, 0.8]:
		B.tube("matte", [[0.2, 1.1, z], [0.1, 0.84, z * 1.02], [-0.1, 0.84, z * 1.02], [-0.2, 1.1, z]], 0.028, "#2f3038", 12, 6)
	B.tube("matte", [[0.62, Car.roof_y(0.62) + 0.085, 0.62], [0.28, 3.97, 0.62], [-0.28, 3.97, 0.62], [-0.62, Car.roof_y(0.62) + 0.085, 0.62]], 0.024, "#3a3a44", 12, 6)

	var group := T.Group.new()
	group.name = "train-" + id
	var lod := []
	var add_meshes := func(buckets, parent, mats: Dictionary) -> void:
		var merged: Dictionary = buckets.merge()
		for k in merged:
			var mesh := T.MeshObj.new(merged[k], mats[k])
			if LOD_KEYS.has(k) and buckets == B:
				lod.append(mesh)
			mesh.name = "train%s-%s" % [id, k]
			mesh.cast_shadow = not NO_SHADOW.has(k)
			mesh.receive_shadow = k != "glass" and k != "iLight" and k != "led" and k != "head" and k != "tail"
			if k == "petal":
				ctx.no_outline(mesh)
			parent.add(mesh)
	add_meshes.call(B, group, MAT)
	# far LOD: one warm-grey box per car stands in for the saloon + cab behind the tinted glass
	var P := Builder.Buckets.new({"interior": {}})
	for sg in [1, -1]:
		P.box("interior", Car.XS - 0.1 - Car.XE - 0.1, 2.1, 2.6, [sg * (9 + (Car.XS - 0.1 + Car.XE + 0.1) / 2), 1.3 + 1.05, 0], "#8d8279")
	var proxy := T.MeshObj.new(P.merge().interior, MAT.interior)
	proxy.name = "train" + id + "-farInterior"
	proxy.visible = false
	proxy.receive_shadow = true
	group.add(proxy)
	var g_neg := T.Group.new()
	var g_pos := T.Group.new()
	g_neg.name = "doorsNeg"
	g_pos.name = "doorsPos"
	add_meshes.call(d_neg, g_neg, MAT)
	add_meshes.call(d_pos, g_pos, MAT)
	group.add(g_neg, g_pos)
	# car side lamps (lit while the doors are open)
	var lamp_geo := []
	for p in lamps:
		var g: T.Geometry = Builder.geo_box().clone().scale(0.075, 0.075, 0.012)
		g.translate(p.x, p.y, p.z)
		lamp_geo.append(g)
	var lamp_mesh := T.MeshObj.new(Geo.merge_geometries(lamp_geo, false), MAT.lamp)
	lamp_mesh.name = "train%s-lamps" % id
	lamp_mesh.visible = false
	group.add(lamp_mesh)
	group.rotation.y = 0.0 if cfg.dir > 0 else PI
	group.position = Vector3(cfg.stopX, 0, cfg.z)
	ctx.add(group)
	return {"id": id, "cfg": cfg, "group": group, "gNeg": g_neg, "gPos": g_pos, "lampMesh": lamp_mesh, "lod": lod, "proxy": proxy, "far": false,
		"wheelsets": wheelsets, "tris": B.tris + d_neg.tris + d_pos.tris, "st": S.state_at(cfg, 0), "sound": Vector3(cfg.stopX, 1.6, cfg.z), "run": null}


static func wheelset_geometry() -> T.Geometry:
	var B := Builder.Buckets.new({"w": {}})
	var RX := [PI / 2, 0, 0]
	for s in [-1, 1]:
		var z: float = s * 0.56
		B.cyl("w", Car.WHEEL_R, Car.WHEEL_R, 0.12, [0, 0, z], "#a8adb3", RX, 26, true)
		B.cyl("w", 0.46, 0.46, 0.024, [0, 0, z - s * 0.066], "#6a6f77", RX, 26)
		B.add("w", Builder.geo_circle(26), Builder.M([0, 0, z + s * 0.06], [0, 0.0 if s > 0 else PI, 0], [Car.WHEEL_R * 2, Car.WHEEL_R * 2, 1]), "#5d6169")
		B.add("w", Builder.geo_circle(26), Builder.M([0, 0, z - s * 0.06], [0, PI if s > 0 else 0.0, 0], [Car.WHEEL_R * 2, Car.WHEEL_R * 2, 1]), "#5d6169")
		B.cyl("w", 0.36, 0.36, 0.122, [0, 0, z], "#555960", RX, 22, true)
		B.cyl("w", 0.14, 0.15, 0.2, [0, 0, z + s * 0.04], "#7a8088", RX, 14)
		for k in 3:
			var a := k * PI * 2 / 3
			B.box("w", 0.07, 0.05, 0.012, [cos(a) * 0.26, sin(a) * 0.26, z + s * 0.066], "#8e949c", [0, 0, a])
	B.cyl("w", 0.075, 0.075, 1.02, [0, 0, 0], "#6a6f77", RX, 12)
	return B.merge().w


# ------------------------------------------------------------------ build
func build(ctx):
	var L = ctx.L
	var S := Schedule.new(L)
	var CFG: Dictionary = S.CFG
	var PERIOD: float = S.PERIOD
	var tex := Textures.create_train_textures(ctx)
	var MAT := make_materials(ctx, tex)
	var trains := []
	for id in ["A", "B"]:
		trains.append(build_train(ctx, S, id, tex, MAT))

	# wheelsets (instanced, rotate with the odometer)
	var ws_geo := wheelset_geometry()
	var n_ws := 0
	for tr in trains:
		n_ws += tr.wheelsets.size()
	var wheels := T.InstancedMesh.new(ws_geo, MAT.metal, n_ws)
	wheels.name = "train-wheelsets"
	wheels.cast_shadow = true
	wheels.receive_shadow = true
	wheels.frustum_culled = false
	wheels.user_data["dynamicDraw"] = true  # instanceMatrix.setUsage(THREE.DynamicDrawUsage)
	ctx.add(wheels)
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)

	# ---------------- services.rail
	var pub := []
	for tr in trains:
		pub.append({"id": tr.id, "track": tr.cfg.track, "x": tr.cfg.stopX, "z": tr.cfg.z, "length": S.TRAIN_LEN, "dir": tr.cfg.dir, "speed": 0.0, "doorsOpen": 0.0, "stopped": true, "visible": true, "front": 0.0, "tail": 0.0, "braking": false, "dest": tr.cfg.dest})
	var memo := {"map": {}, "t": NAN}
	var cross := func(x: float) -> Array:
		var t: float = ctx.time if ctx.time else 0.0
		if t != memo.t:
			memo.map.clear()
			memo.t = t
		var key := int(T.js_round(x * 100))
		var v = memo.map.get(key)
		if not v:
			v = []
			for tr in trains:
				v.append(S.crossing_for(tr.cfg, x, t))
			memo.map[key] = v
		return v
	var crossing_active := func(x: float) -> bool:
		for v in cross.call(x):
			if v:
				return true
		return false
	var crossing_approach := func(x: float) -> Dictionary:
		var v: Array = cross.call(x)
		var o := {"fromWest": false, "fromEast": false}
		for i in trains.size():
			if v[i]:
				if trains[i].cfg.dir > 0:
					o.fromWest = true
				else:
					o.fromEast = true
		return o
	var state_at := func(id: String, t: float) -> Dictionary:
		return S.state_at(CFG[id], t)
	var rail := {
		"trains": pub,
		"crossingActive": crossing_active,
		"crossingApproach": crossing_approach,
		"stateAt": state_at,
	}
	ctx.services["rail"] = rail

	# ---------------- physics: one moving box per visible train
	ctx.physics.addDynamic(func():
		var out := []
		for tr in trains:
			var s: Dictionary = S.state_at(tr.cfg, ctx.time if ctx.time else 0.0)
			if s.visible:
				out.append({"cx": s.x, "cz": tr.cfg.z, "w": S.TRAIN_LEN + 0.4, "d": 2.86, "rotY": 0.0, "y0": 0.2, "y1": 4.2})
		return out)

	# ---------------- audio (the port has no audio service; ctx.audio is absent, so every call is a no-op as in the original's guard)
	var au = ctx.get("audio")
	var safe := func(f: Callable):
		return f.call()
	for tr in trains:
		tr.run = safe.call(func(): return au.loop("trainRun", {"position": func(): return tr.sound, "volume": 0.9}) if au and au.has_method("loop") else null)
	var PLAT := {"A": Vector3(17, L.PLATFORM.y + 2.2, (L.PLATFORM.south.z0 + L.PLATFORM.south.z1) / 2), "B": Vector3(17, L.PLATFORM.y + 2.2, (L.PLATFORM.north.z0 + L.PLATFORM.north.z1) / 2)}
	var door_pos := func(id: String) -> Vector3: return Vector3(17, 2.2, CFG[id].z + (1.4 if id == "A" else -1.4))
	var play := func(name: String, opts: Dictionary):
		return safe.call(func(): return au.play(name, opts) if au and au.has_method("play") else null)
	var train_pos := func(id: String) -> Vector3:
		for tr in trains:
			if tr.id == id:
				return tr.sound
		return Vector3.ZERO
	var events := [
		# Train A (1番線, 花見台行き)
		{"at": 0.8, "fn": func(): play.call("announce", {"text": "さくらがおか、さくらがおかです。ご乗車ありがとうございます。", "position": PLAT.A})},
		{"at": float(CFG.A.doors[0]), "fn": func(): play.call("doorOpen", {"position": door_pos.call("A")})},
		{"at": 36.0, "fn": func(): play.call("departMelody", {"position": PLAT.A})},
		{"at": 40.2, "fn": func(): play.call("announce", {"text": "1番線、ドアが閉まります。ご注意ください。", "position": PLAT.A})},
		{"at": 42.0, "fn": func(): play.call("doorChime", {"position": door_pos.call("A")})},
		{"at": float(CFG.A.doors[1]), "fn": func(): play.call("doorClose", {"position": door_pos.call("A")})},
		{"at": 108.0, "fn": func(): play.call("announce", {"text": "まもなく、1番線に、花見台行きの電車がまいります。黄色い線の内側でお待ちください。", "position": PLAT.A})},
		{"at": mod(CFG.A.arriveT - 8 / CFG.A.brake, PERIOD), "fn": func(): play.call("trainBrake", {"position": train_pos.call("A")})},
		# Train B (2番線, 春日野行き)
		{"at": 12.0, "fn": func(): play.call("announce", {"text": "まもなく、2番線に、春日野行きの電車がまいります。黄色い線の内側でお待ちください。", "position": PLAT.B})},
		{"at": mod(CFG.B.arriveT - 8 / CFG.B.brake, PERIOD), "fn": func(): play.call("trainBrake", {"position": train_pos.call("B")})},
		{"at": 32.8, "fn": func(): play.call("announce", {"text": "さくらがおか、さくらがおかです。春日野行きです。", "position": PLAT.B})},
		{"at": float(CFG.B.doors[0]), "fn": func(): play.call("doorOpen", {"position": door_pos.call("B")})},
		{"at": 64.0, "fn": func(): play.call("departMelody", {"position": PLAT.B})},
		{"at": 66.2, "fn": func(): play.call("announce", {"text": "2番線、ドアが閉まります。ご注意ください。", "position": PLAT.B})},
		{"at": 68.0, "fn": func(): play.call("doorChime", {"position": door_pos.call("B")})},
		{"at": float(CFG.B.doors[1]), "fn": func(): play.call("doorClose", {"position": door_pos.call("B")})},
	]
	var prev := {"t": null}

	# ---------------- per-frame
	var listener := {"v": Vector3.ZERO}
	var update := func(_dt: float, t: float) -> void:
		var wi := 0
		var player = ctx.get("player")
		var pp = player.get("position") if player is Dictionary else null
		listener.v = pp if pp != null else listener.v
		for i in trains.size():
			var tr: Dictionary = trains[i]
			var s: Dictionary = S.state_at(tr.cfg, t)
			tr.st = s
			var g: T.Group = tr.group
			g.visible = s.visible
			if s.visible:
				g.position = Vector3(s.x, 0, tr.cfg.z)
			var d: float = s.doors
			var gn: T.Group = tr.gNeg
			var gp: T.Group = tr.gPos
			gn.position.x = -DOOR_SLIDE * d
			gp.position.x = DOOR_SLIDE * d
			tr.lampMesh.visible = d > 0.01
			# wheels
			var tt := Transform3D(Basis(Vector3.UP, g.rotation.y), g.position)
			var ang: float = -s.s / Car.WHEEL_R
			for w in tr.wheelsets:
				if not s.visible:
					wheels.set_matrix_at(wi, zero)
					wi += 1
					continue
				var rr := Transform3D(Basis(Vector3(0, 0, 1), ang), w)
				wheels.set_matrix_at(wi, tt * rr)
				wi += 1
			# sound source: nearest point of the train to the listener
			# distance LOD (camera to the nearest point of the train)
			var cam = ctx.get("camera")
			if s.visible and cam:
				var cp: Vector3 = cam.position
				var lo := minf(S.front_x(s), S.tail_x(s))
				var hi := maxf(S.front_x(s), S.tail_x(s))
				var far: bool = Vector2(cp.x - maxf(lo, minf(hi, cp.x)), cp.z - tr.cfg.z).length() > LOD_FAR
				if far != tr.far:
					tr.far = far
					for m in tr.lod:
						m.visible = not far
					tr.proxy.visible = far
			if s.visible:
				tr.sound = Vector3(maxf(minf(S.front_x(s), S.tail_x(s)), minf(maxf(S.front_x(s), S.tail_x(s)), listener.v.x)), 1.4, tr.cfg.z)
			else:
				tr.sound = Vector3(tr.cfg.dir * 2000, 1.4, tr.cfg.z)
			if tr.run and tr.run.has_method("setParam"):
				tr.run.setParam("speed", s.v if s.visible else 0.0)
			# publish
			var p: Dictionary = pub[i]
			p.x = s.x if s.visible else tr.cfg.dir * 1e4
			p.speed = s.v
			p.doorsOpen = d
			p.stopped = s.stopped
			p.visible = s.visible
			p.front = S.front_x(s)
			p.tail = S.tail_x(s)
			p.braking = s.braking
		# timetable sound events (only in real time, never in big jumps)
		if prev.t != null and t > prev.t and t - prev.t < 1.0:
			var a := mod(prev.t, PERIOD)
			var b := mod(t, PERIOD)
			for e in events:
				var hit: bool = (e.at > a and e.at <= b) if a <= b else (e.at > a or e.at <= b)
				if hit:
					e.fn.call()
		prev.t = t
	ctx.on_update(update)
	update.call(0.0, ctx.time if ctx.time else 0.0)
	prev.t = null
