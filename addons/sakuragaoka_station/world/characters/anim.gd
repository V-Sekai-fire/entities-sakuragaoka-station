# characters/anim.js: the pose driver for Human rigs. Reset, planted-feet leg IK, arm FK/IK,
# look-at, breathing, blinking, wind on hair chains & skirt bones. All deterministic from (t, dt).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Sk = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")
const Self = preload("res://addons/sakuragaoka_station/world/characters/anim.gd")

const UP := Vector3(0, 1, 0)
const DOWN := Vector3(0, -1, 0)
const ARM_BEND := Vector3(0, 0, 1)
const LEG_BEND := Vector3(0, 0, -1)
const TAU_BREATH := PI * 2.0 / 4.3
const ORDERS := {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ, "YZX": EULER_ORDER_YZX, "ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}


static func euler_quat(x: float, y: float, z: float, order: String = "XYZ") -> Quaternion:
	return Basis.from_euler(Vector3(x, y, z), ORDERS[order]).get_rotation_quaternion()


static func rot(bone, x: float = 0.0, y: float = 0.0, z: float = 0.0, order: String = "XYZ") -> void:
	Sk.set_quat(bone, euler_quat(x, y, z, order))


static func rot_mul(bone, x: float = 0.0, y: float = 0.0, z: float = 0.0, order: String = "XYZ") -> void:
	Sk.set_quat(bone, Sk.get_quat(bone) * euler_quat(x, y, z, order))


static func _nn(o: Dictionary, k: String, d):
	var v = o.get(k)
	return d if v == null else v


class Driver extends RefCounted:
	var ctx
	var h
	var b: Dictionary
	var seed := 1.0
	var blinkP := 0.0
	var look := {"yaw": 0.0, "pitch": 0.0}
	var lookInit := false
	var feet = null
	var windScale := 1.0
	var hairAmp := 1.0
	var skirtAmp := 1.0
	var rotY := 0.0

	func _init(c, hh, o: Dictionary = {}) -> void:
		ctx = c
		h = hh
		b = hh.b
		seed = _nn(o, "seed", 1.0)
		blinkP = 2.8 + fmod(seed * 0.713, 1.0) * 2.4
		windScale = _nn(o, "wind", 1.0)
		hairAmp = _nn(o, "hairAmp", 1.0)
		skirtAmp = _nn(o, "skirtAmp", 1.0)

	static func _nn(o: Dictionary, k: String, d):
		var v = o.get(k)
		return d if v == null else v

	## Place the character root in the world.
	func place(x: float, y: float, z: float, rot_y: float) -> void:
		var g = h.group
		g.position = Vector3(x, y, z)
		g.set_rotation(0.0, rot_y, 0.0)
		g.update_matrix_world(true)
		rotY = rot_y

	func reset() -> void:
		for bone in h.rest:
			bone.position = h.rest[bone].p
			bone.quat = Quaternion.IDENTITY

	## local (character space) -> world
	func W(x: float, y: float, z: float) -> Vector3:
		return h.group.matrix_world * Vector3(x, y, z)

	func breathe(t: float, amt: float = 1.0) -> void:
		var s := sin(t * TAU_BREATH + seed)
		Self.rot_mul(b.chest, -0.012 * s * amt, 0, 0)
		Self.rot_mul(b.clavL, 0, 0, 0.012 * s * amt)
		Self.rot_mul(b.clavR, 0, 0, -0.012 * s * amt)

	## Standing legs: planted feet in character space, hips offset/tilt.
	func stand(o: Dictionary = {}) -> void:
		var P: Dictionary = h.P
		var fx: float = P.hipJx * _nn(o, "stance", 1.08)
		var L: Array = o.footL if o.get("footL") else [fx, P.ankle, _nn(o, "fzL", 0.01)]
		var R: Array = o.footR if o.get("footR") else [-fx, P.ankle, _nn(o, "fzR", 0.0)]
		b.hips.position.x += o.get("hx", 0.0) if o.get("hx") else 0.0
		b.hips.position.y += o.get("hy", 0.0) if o.get("hy") else 0.0
		b.hips.position.z += o.get("hz", 0.0) if o.get("hz") else 0.0
		Self.rot_mul(b.hips, o.get("hrx", 0.0) if o.get("hrx") else 0.0, o.get("hry", 0.0) if o.get("hry") else 0.0, o.get("hrz", 0.0) if o.get("hrz") else 0.0)
		h.group.update_matrix_world(true)
		leg("L", L, _nn(o, "toeL", 0.14), o.get("kneeL"))
		leg("R", R, -_nn(o, "toeR", 0.14), o.get("kneeR"))

	func leg(n: String, foot: Array, yaw: float = 0.0, knee = null) -> void:
		var s := 1.0 if n == "L" else -1.0
		var tgt := W(foot[0], foot[1], foot[2])
		var k0: float = knee[0] if knee != null and knee[0] != null else 0.05
		var k1: float = knee[1] if knee != null and knee[1] != null else 1.0
		var pole := W(foot[0] + s * k0, foot[1] + 0.45, foot[2] + k1)
		Sk.ik2(b["thigh" + n], b["shin" + n], b["foot" + n].user_data.rest, tgt, pole, LEG_BEND)
		# foot flat, yawed
		var q2: Quaternion = Sk.world_quat(h.group)
		var q3 := Self.euler_quat(foot[3] if foot.size() > 3 and foot[3] else 0.0, yaw, 0.0, "YXZ")
		Sk.set_world_quat(b["foot" + n], q2 * q3)

	## Arm FK: fwd (raise forward), out (abduct), twist, elbow (flex), hand [x, y, z]
	func arm(n: String, fwd: float = 0.0, out: float = 0.0, twist: float = 0.0, elbow: float = 0.0, hand = null) -> void:
		var s := 1.0 if n == "L" else -1.0
		Self.rot(b["uarm" + n], -fwd, s * twist, s * out, "XZY")
		Self.rot(b["farm" + n], -elbow, 0, 0)
		if hand:
			Self.rot(b["hand" + n], hand[0], s * (hand[1] if hand[1] else 0.0), s * (hand[2] if hand[2] else 0.0))

	## Arm IK to a world point (wrist). pole: world elbow hint.
	func arm_ik(n: String, target: Vector3, pole: Vector3) -> void:
		Sk.ik2(b["uarm" + n], b["farm" + n], b["hand" + n].user_data.rest, target, pole, ARM_BEND)

	## Look at a world point (distributes over neck/head), smoothed.
	func look_at(target: Vector3, dt: float, o: Dictionary = {}) -> void:
		Sk.update_world(b.chest)
		var v: Vector3 = b.chest.matrix_world.affine_inverse() * target
		var hy: float = h.bind_pos(b.head)[1] - h.bind_pos(b.chest)[1] + 0.1
		var yaw := atan2(v.x, v.z)
		var pitch := -atan2(v.y - hy, Sk.hypot(v.x, v.z))
		yaw = Sk.clamp_(yaw, -_nn(o, "maxYaw", 1.2), _nn(o, "maxYaw", 1.2))
		pitch = Sk.clamp_(pitch, -_nn(o, "maxUp", 0.6), _nn(o, "maxDown", 0.7))
		look_yp(yaw, pitch, dt, o)

	func look_yp(yaw: float, pitch: float, dt: float, o: Dictionary = {}) -> void:
		var k: float = 1.0 - exp(-dt * _nn(o, "speed", 3.0)) if lookInit and dt > 0.0 else 1.0
		if not lookInit and dt == 0.0:
			look.yaw = yaw
			look.pitch = pitch
		look.yaw = Sk.lerp_(look.yaw, yaw, k)
		look.pitch = Sk.lerp_(look.pitch, pitch, k)
		lookInit = true
		Self.rot_mul(b.neck, look.pitch * 0.3, look.yaw * 0.35, 0, "YXZ")
		Self.rot_mul(b.head, look.pitch * 0.7, look.yaw * 0.65, o.get("tilt", 0.0) if o.get("tilt") else 0.0, "YXZ")

	func blink(t: float, talk: bool = false) -> void:
		var ph := fmod(t + seed * 1.37, blinkP)
		var dbl := posmod(int(floorf((t + seed * 1.37) / blinkP)), 4) == 2
		var closed := ph < 0.12 or (dbl and ph > 0.24 and ph < 0.34)
		h.set_face("blink" if closed else ("talk" if talk else "open"))

	## Wind + gravity on hair chains and skirt bones. strength ~0..1.5
	func wind(t: float, _dt: float, o: Dictionary = {}) -> void:
		var Wv: Vector2 = ctx.shared.uWind
		var gust: float = ctx.shared.uGust
		var stren: float = (0.35 + 0.95 * gust) * windScale * _nn(o, "boost", 1.0)
		var w := Vector3(Wv.x, 0.0, Wv.y) * stren
		# ---- hair
		if h.hairChains.size():
			var q2: Quaternion = Sk.world_quat(b.head).inverse()
			for ch in h.hairChains:
				var g: Vector3 = q2 * DOWN                  # gravity in head space
				var v: Vector3 = q2 * w                     # wind in head space
				var amp: float = (ch.get("amp") if ch.get("amp") else 1.0) * hairAmp
				var bid: float = ch.b1.user_data.id
				var wob := Sk.wave(t * 1.6, seed + bid * 0.37) * 0.35 + Sk.wave(t * 3.1, bid) * 0.12
				# hang direction: mostly gravity, pushed by the wind
				var v2 := (g + v * (0.32 * amp)).normalized()
				v2.x += wob * 0.1 * amp * (0.5 + gust)
				v2.z += Sk.wave(t * 1.3, bid * 0.7) * 0.05 * amp
				# hair lies on the back / shoulders: it cannot swing forward into the body
				var max_fwd: float = _nn(ch, "maxFwd", 0.08)
				if v2.z > max_fwd:
					v2.z = max_fwd
				if v2.y > -0.35:
					v2.y = -0.35
				v2 = v2.normalized()
				var q := T.quat_from_unit_vectors(DOWN, v2)
				ch.b1.quat = Quaternion.IDENTITY.slerp(q, 0.75)
				# tip: a bit more wind + lag
				var v3: Vector3 = q.inverse() * v
				var a2 := (0.12 + 0.35 * gust) * amp * Sk.clamp_(v3.length(), 0.0, 1.5) + wob * 0.12 * amp
				ch.b2.quat = Sk.tilt_quat(v3.x + 1e-4, v3.z, a2)
		# ---- skirt
		if h.skirtBones.size():
			var q2: Quaternion = Sk.world_quat(b.hips).inverse()
			var v: Vector3 = q2 * w
			var g: Vector3 = q2 * DOWN
			var wl := Sk.hypot(v.x, v.z)
			if wl == 0.0:
				wl = 1e-6
			var wx := v.x / wl
			var wz := v.z / wl
			var sa := skirtAmp
			var legs = o.get("legs")
			for sb in h.skirtBones:
				var ph: float = sb.user_data.ph
				var dx := sin(ph)
				var dz := cos(ph)
				var dot := dx * wx + dz * wz
				var flutter := Sk.wave(t * 2.3, ph * 3.0 + seed) * 0.5 + Sk.wave(t * 4.1, ph * 5.0) * 0.25
				var flare: float = _nn(o, "flare", 0.04) + maxf(0.0, dot) * wl * 0.22 * sa + flutter * 0.045 * sa * (0.4 + gust) - maxf(0.0, -dot) * wl * 0.05 * sa
				flare = maxf(-0.05, flare)
				var tx := dx * flare + wx * wl * 0.06 * sa + g.x * 0.9
				var tz := dz * flare + wz * wl * 0.06 * sa + g.z * 0.9
				# gravity: keep hanging when the hips tilt
				if legs:
					for lg in legs:
						# lg: {x: side (-1..1), a: forward angle}. Smooth falloff round the hem so neighbouring panels never split.
						var side := Sk.clamp_(1.0 - absf(dx - lg.x * 0.5) * 0.6, 0.35, 1.0)
						if lg.a > 0:
							tz += lg.a * pow(0.5 + 0.5 * dz, 1.4) * side * 0.9
						else:
							tz += lg.a * pow(0.5 - 0.5 * dz, 1.4) * side * 0.6
				var a := Sk.hypot(tx, tz)
				sb.quat = Sk.tilt_quat(tx, tz, a)
