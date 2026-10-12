# petals/trains.js: train state for the petal gust field. Reads ctx.services.rail.trains every frame;
# if the trains module is absent, falls back to a kinematic estimate of L.SCHEDULE (so the swirls
# still happen). Returns up to 4 entries: {x (centre), z (track), v (signed m/s along X), half (half
# length), doors (0..1), side (+1 = doors/platform on +Z side, -1 = on -Z side)}.
extends RefCounted

var ctx
var L
var half_len: float
var stop_x: float
var period: float


static func create(c):
	var tr = load("res://addons/sakuragaoka_station/world/petals/trains.gd").new()
	tr.ctx = c
	tr.L = c.L
	tr.half_len = c.L.TRAIN.cars * c.L.TRAIN.carLen / 2.0
	tr.stop_x = c.L.TRAIN.stopCenterX
	tr.period = c.L.TRAIN.period
	return tr


func z_of(track) -> float:
	return L.RAIL.zB if track == "B" else L.RAIL.zA


func side_of(track) -> float:
	return -1.0 if track == "B" else 1.0  # A stops at the south platform (+Z), B at the north (-Z)


static func doors_in(t: float, a: float, b: float) -> float:
	return minf(1.0, maxf(0.0, t - a)) * minf(1.0, maxf(0.0, b - t))


static func _fin(v) -> bool:
	return v != null and (v is float or v is int) and is_finite(float(v))


func fallback(t_abs: float) -> Array:
	var P := period
	var t := fmod(fmod(t_abs, P) + P, P)
	var out: Array = []
	# --- train A: westbound on track A (moves -X)
	if true:
		var S: Dictionary = L.SCHEDULE.A
		var x = null
		var v := 0.0
		var doors := 0.0
		var a := 0.9
		var vmax := 16.0
		if t >= S.stopped[0] and t < S.stopped[1]:
			x = stop_x
			v = 0.0
			doors = doors_in(t, S.doors[0], S.doors[1])
		elif t >= S.depart and t < S.arriveFromEast[0]:
			var dt: float = t - S.depart
			var tA := vmax / a
			if dt < tA:
				x = stop_x - 0.5 * a * dt * dt
				v = -a * dt
			else:
				x = stop_x - 0.5 * a * tA * tA - vmax * (dt - tA)
				v = -vmax
		elif t >= S.arriveFromEast[0]:
			var dt: float = S.arriveFromEast[1] - t
			var ad: float = vmax / (S.arriveFromEast[1] - S.arriveFromEast[0])
			x = stop_x + 0.5 * ad * dt * dt
			v = -ad * dt
		if x != null and x > -460.0 and x < 460.0:
			out.append({"x": x, "z": z_of("A"), "v": v, "half": half_len, "doors": doors, "side": side_of("A")})
	# --- train B: eastbound on track B (moves +X)
	if true:
		var S: Dictionary = L.SCHEDULE.B
		var x = null
		var v := 0.0
		var doors := 0.0
		var t_stop: float = S.stop
		var a := 0.716
		var ad := 0.9
		var vmax := 20.0
		if t < t_stop:
			var dt := t_stop - t  # decelerating arrival from the west
			var tA := vmax / a
			if dt < tA:
				x = stop_x - 0.5 * a * dt * dt
				v = a * dt
			else:
				x = stop_x - 0.5 * a * tA * tA - vmax * (dt - tA)
				v = vmax
		elif t < S.depart:
			x = stop_x
			v = 0.0
			doors = doors_in(t, S.doors[0], S.doors[1])
		else:
			var dt: float = t - S.depart
			var tA := vmax / ad
			if dt < tA:
				x = stop_x + 0.5 * ad * dt * dt
				v = ad * dt
			else:
				x = stop_x + 0.5 * ad * tA * tA + vmax * (dt - tA)
				v = vmax
		if x != null and x > -460.0 and x < 460.0:
			out.append({"x": x, "z": z_of("B"), "v": v, "half": half_len, "doors": doors, "side": side_of("B")})
	return out


func read(t: float) -> Array:
	var rail = ctx.services.get("rail")
	var list = rail.get("trains") if rail != null else null
	if list is Array and not list.is_empty():
		var out: Array = []
		for tr in list:
			if tr == null or not _fin(tr.get("x")) or tr.get("visible") == false:
				continue
			var cx: float = (tr.front + tr.tail) / 2.0 if _fin(tr.get("front")) and _fin(tr.get("tail")) and absf(tr.front - tr.tail) > 1.0 else tr.x
			if absf(cx) > 600.0:
				continue
			var dr = tr.get("dir")
			var dir := -1.0 if dr != null and (dr == -1 or dr < 0) else 1.0
			var sp: float = absf(tr.speed) if _fin(tr.get("speed")) else 0.0
			out.append({
				"x": cx, "z": tr.z if _fin(tr.get("z")) else z_of(tr.get("track")), "v": dir * sp,
				"half": (tr.length if _fin(tr.get("length")) else half_len * 2.0) / 2.0,
				"doors": maxf(0.0, minf(1.0, tr.doorsOpen if tr.get("doorsOpen") else 0.0)), "side": side_of(tr.get("track")),
			})
			if out.size() >= 4:
				break
		return out
	return fallback(t)
