# characters.js: the people, cats and sparrows of 桜ヶ丘 (SPEC 十四). Every figure is ONE skinned
# mesh (vertex colours + a small painted atlas), animated as a pure function of t (plus light
# smoothing): breathing, weight shifts, blinking, gestures, a walk cycle, and hair / skirts moved by
# ctx.shared.uWind / uGust through skirt & hair bones.
extends RefCounted

const Cast = preload("res://addons/sakuragaoka_station/world/characters/cast.gd")
const Animals = preload("res://addons/sakuragaoka_station/world/characters/animals.gd")
const DevProps = preload("res://addons/sakuragaoka_station/world/characters/devprops.gd")


func build(ctx):
	# DEV only (?only=...,characters/devprops): grey stand-ins for neighbours' props, built first so the poses
	# (e.g. the crossing girl's grip on her bike) see them exactly like the real neighbours' objects.
	DevProps.dev_props(ctx)
	var actors: Array = []
	actors.append_array(Cast.make_cast(ctx))
	actors.append_array(Animals.make_animals(ctx))
	var cam = ctx.get("camera")
	var st := {"frame": 0}
	ctx.on_update(func(dt, t):
		st.frame += 1
		for a in actors:
			# far-away figures update at a lower rate (poses are functions of t, so this is seamless)
			if a.h and cam and dt > 0:
				var p: Vector3 = a.h.group.position
				var cp: Vector3 = cam.position
				var d2 := (p.x - cp.x) ** 2 + (p.z - cp.z) ** 2
				if d2 > 90 * 90 and (st.frame + a.get("slot", 0)) % 4:
					continue
			a.update.call(t, dt))
