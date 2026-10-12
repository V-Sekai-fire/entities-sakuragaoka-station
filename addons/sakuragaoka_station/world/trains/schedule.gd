# trains/schedule.js: train traffic, pure functions of the simulation time t (120 s loop, see
# layout.js SCHEDULE).
#
# Train A: westbound on track A (moves -X, dest 花見台). Stopped centred at x=17 for t∈[0,48],
#          doors 2..44, departs 48 (0.8 m/s²), crosses x=-12 ≈52–59, exits west;
#          the next A comes in from the far east (cruise 20 m/s, 0.75 m/s² brake) and stops at 120≡0.
# Train B: eastbound on track B (moves +X, dest 春日野). Cruises in from the far west at 18 m/s,
#          brakes at 0.611 m/s² so it passes the crossing slowly (~7→4 m/s) during ≈19–27,
#          stops centred at x=17 at 32, doors 34..70, departs 76 east (0.8 m/s²).
# The original imports TRAIN, RAIL and SCHEDULE from layout.js; the port's layout is per build, so
# one instance holds the derived constants and CFG.
extends RefCounted

var PERIOD: float                     # 120
var TRAIN_LEN: float                  # 36 (body + couplers ≈ 36.3)
var HALF: float
var LIMIT: float                      # |x| beyond which the train is hidden (stays on the rails)
var CFG: Dictionary


func _init(L) -> void:
	var TRAIN: Dictionary = L.TRAIN
	var RAIL: Dictionary = L.RAIL
	var SCHEDULE: Dictionary = L.SCHEDULE
	PERIOD = TRAIN.period
	TRAIN_LEN = TRAIN.cars * TRAIN.carLen
	HALF = TRAIN_LEN / 2.0
	LIMIT = RAIL.xMax - HALF
	CFG = {
		"A": {
			"id": "A", "track": "A", "z": RAIL.zA, "dir": -1.0, "stopX": TRAIN.stopCenterX,
			"arriveT": 0.0, "departT": float(SCHEDULE.A.depart), "doors": SCHEDULE.A.doors,
			"acc": 0.8, "vmax": 25.0, "vc": 20.0, "brake": 0.75,
			"dest": "花見台", "destEn": "Hanamidai", "platform": 1,
		},
		"B": {
			"id": "B", "track": "B", "z": RAIL.zB, "dir": 1.0, "stopX": TRAIN.stopCenterX,
			"arriveT": float(SCHEDULE.B.stop), "departT": float(SCHEDULE.B.depart), "doors": SCHEDULE.B.doors,
			"acc": 0.8, "vmax": 25.0, "vc": 18.0, "brake": 2.0 * 11.0 / 36.0,  # 0.611: tail clears x=-12 at t≈26
			"dest": "春日野", "destEn": "Kasugano", "platform": 2,
		},
	}


static func mod(a: float, n: float) -> float:
	return fmod(fmod(a, n) + n, n)


static func clamp01(v: float) -> float:
	return maxf(0.0, minf(1.0, v))


static func _ease(v: float) -> float:
	v = clamp01(v)
	return v * v * (3.0 - 2.0 * v)


static func brake_dist(sig: float, vc: float, b: float) -> float:
	var Tb := vc / b
	return 0.5 * b * sig * sig if sig <= Tb else 0.5 * b * Tb * Tb + vc * (sig - Tb)


static func brake_speed(sig: float, vc: float, b: float) -> float:
	return minf(vc, b * sig)


static func acc_dist(tau: float, a: float, vmax: float) -> float:
	var Ta := vmax / a
	return 0.5 * a * tau * tau if tau <= Ta else 0.5 * a * Ta * Ta + vmax * (tau - Ta)


static func acc_speed(tau: float, a: float, vmax: float) -> float:
	return minf(vmax, a * tau)


## Door opening 0..1 at cycle time tm. Opening takes 1.8 s, closing 2.2 s.
static func doors_at(cfg: Dictionary, tm: float) -> float:
	var o: float = cfg.doors[0]
	var c: float = cfg.doors[1]
	if tm < o or tm > c + 2.2:
		return 0.0
	return _ease((tm - o) / 1.8) * (1.0 - _ease((tm - c) / 2.2))


## Full state of a train at absolute time t.
## x = centre, v = speed (m/s, >= 0), s = odometer along travel (m, for wheel rotation),
## phase: 'stopped' | 'departing' | 'arriving' | 'hidden'.
func state_at(cfg: Dictionary, t: float) -> Dictionary:
	var tm := mod(t, PERIOD)
	var cyc := floorf(t / PERIOD)
	var dwell := mod(cfg.departT - cfg.arriveT, PERIOD)
	var ta := mod(tm - cfg.arriveT, PERIOD)       # time since the last arrival
	var st := {"id": cfg.id, "cfg": cfg, "tm": tm, "x": cfg.stopX, "v": 0.0, "s": 0.0, "braking": false, "phase": "stopped", "visible": true, "doors": 0.0, "stopped": true}
	# odometer: every cycle the train runs "one lap"; s grows monotonically (only used for wheels)
	var lap := 1000.0
	var cyc_arr := floorf((t - cfg.arriveT) / PERIOD)
	if ta <= dwell:
		st.s = cyc_arr * lap
		st.doors = doors_at(cfg, tm)
		return st
	st.stopped = false
	var tau := ta - dwell                          # time since departure
	var sig := mod(cfg.arriveT - tm, PERIOD)        # time until the next arrival
	var s_dep := acc_dist(tau, cfg.acc, cfg.vmax)
	var x_dep: float = cfg.stopX + cfg.dir * s_dep
	var d_arr := brake_dist(sig, cfg.vc, cfg.brake)
	var x_arr: float = cfg.stopX - cfg.dir * d_arr
	if absf(x_dep) <= LIMIT:
		st.phase = "departing"
		st.x = x_dep
		st.v = acc_speed(tau, cfg.acc, cfg.vmax)
		st.s = cyc_arr * lap + s_dep
	elif absf(x_arr) <= LIMIT:
		st.phase = "arriving"
		st.x = x_arr
		st.v = brake_speed(sig, cfg.vc, cfg.brake)
		st.braking = sig <= cfg.vc / cfg.brake
		st.s = (cyc_arr + 1.0) * lap - d_arr
	else:
		st.phase = "hidden"
		st.visible = false
		st.x = cfg.dir * 1e4
		st.v = 0.0
		st.s = 0.0
	var _unused := cyc
	return st


## Front (leading end) and tail x of a state.
func front_x(st: Dictionary) -> float:
	return st.x + st.cfg.dir * HALF


func tail_x(st: Dictionary) -> float:
	return st.x - st.cfg.dir * HALF


# ------------------------------------------------------------------ level crossing logic
const ZONE := 4.0          # crossing half-zone (m)
const LEAD_T := 25.0       # warning lead time for approaching trains (s)
const LEAD_D := 260.0      # ... but only once the front is this close (m)
const PRE_DEPART := 8.0    # stopped train: warning starts this long before departure


## Crossing warning contribution of one train at crossing x (time t). Returns 0 | 1.
func crossing_for(cfg: Dictionary, x: float, t: float) -> int:
	var st := state_at(cfg, t)
	if st.visible:
		var f := front_x(st)
		var tl := tail_x(st)
		var lo := minf(f, tl)
		var hi := maxf(f, tl)
		if hi >= x - ZONE and lo <= x + ZONE:
			return 1                                       # occupying the crossing
	var edge: float = x - cfg.dir * ZONE                   # where the front enters the zone
	var is_before := func(s: Dictionary) -> bool: return cfg.dir * (front_x(s) - edge) < 0.0
	# A stopped train only warns from PRE_DEPART s before it leaves (station-stop logic).
	var horizon := LEAD_T
	if st.stopped:
		var to_depart := mod(cfg.departT - st.tm, PERIOD)
		if to_depart > PRE_DEPART:
			return 0
		horizon = to_depart + LEAD_T
	# Step forward along the deterministic timetable: does the front, moving toward x, enter the zone?
	var before: bool = is_before.call(st) if st.visible else false
	var dt := 0.25
	var k := 1
	while k * dt <= horizon:
		var tt := t + k * dt
		var s2 := state_at(cfg, tt)
		k += 1
		if not s2.visible:
			before = false
			continue
		if s2.stopped:
			if not st.stopped:
				return 0                   # it will stop before reaching the crossing -> no warning yet
			before = is_before.call(s2)
			continue
		var b2: bool = is_before.call(s2)
		if before and not b2:
			if st.stopped:
				return 1                   # departing toward x within PRE_DEPART s
			var dist: float = cfg.dir * (edge - front_x(st))
			return 1 if st.visible and dist <= LEAD_D else 0
		before = b2
	return 0
