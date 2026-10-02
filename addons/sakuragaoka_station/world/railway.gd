# railway.js: the railway corridor. Track (ballast bed, rails, sleepers, fasteners, joints, a crossover
# with two turnouts), catenary, signals animated from ctx.services.rail, km posts, speed signs,
# equipment, troughs, walkway, drainage, fences with colliders, signs and swaying corridor weeds.
# Publishes ctx.services.railway.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const RailTex = preload("res://addons/sakuragaoka_station/world/railway/tex.gd")
const Track = preload("res://addons/sakuragaoka_station/world/railway/track.gd")
const Catenary = preload("res://addons/sakuragaoka_station/world/railway/catenary.gd")
const Trackside = preload("res://addons/sakuragaoka_station/world/railway/trackside.gd")
const Weeds = preload("res://addons/sakuragaoka_station/world/railway/weeds.gd")
const Merge = preload("res://addons/sakuragaoka_station/world/railway/merge.gd")


static func make_env(L) -> Dictionary:
	var R: Dictionary = L.RAIL
	var HG: float = R.gauge / 2.0 + 0.0325
	return {
		"L": L, "R": R, "HG": HG, "zA": R.zA, "zB": R.zB, "X0": R.xMin, "X1": R.xMax,
		"rails": {"SaZ": R.zA + HG, "NaZ": R.zA - HG, "SbZ": R.zB + HG, "NbZ": R.zB - HG},
		"xo": {"xa": 66.0, "xb": 114.0},
		"cross": [L.CROSSING.zone.x0, L.CROSSING.zone.x1],
		"walk": [L.PLATFORM.walkCrossing.x0, L.PLATFORM.walkCrossing.x1],
		"station": [L.PLATFORM.south.x0, 50.0],
	}


func build(ctx):
	var L = ctx.L
	var root := T.Group.new()
	root.name = "railway"
	ctx.add_static(root)
	var E := make_env(L)
	var TX := RailTex.new(ctx)
	var track := Track.build_track(ctx, root, TX, E)
	var cat := Catenary.build_catenary(ctx, root, TX, E)
	var side := Trackside.build_trackside(ctx, root, TX, E, track, cat)
	var weeds := Weeds.build_weeds(ctx, root, TX, E, track, cat, side)
	var merged := Merge.premerge(root)

	var P: float = L.TRAIN.get("period", 120.0)
	var SA: Dictionary = L.SCHEDULE.A
	var SB: Dictionary = L.SCHEDULE.B
	var WINDOWS := {
		"A-start": [[SA.doors[1] + 0.5, SA.depart + 12]],
		"A-home": [[SA.arriveFromEast[0] - 8, SA.arriveFromEast[0] + 12]],
		"B-start": [[SB.doors[1] + 0.5, SB.depart + 10]],
		"B-home": [[P - 4, P], [0, SB.passCrossing[0] - 4]],
	}
	var in_win := func(id: String, ph: float) -> bool:
		for ab in WINDOWS[id]:
			if ph >= ab[0] and ph <= ab[1]:
				return true
		return false
	var passed := func(tr: Dictionary, sx: float) -> bool:
		var half: float = (tr.get("length") if tr.get("length") else 36.0) / 2.0
		var dir: float = tr.get("dir") if tr.get("dir") else (-1.0 if tr.get("track") == "A" else 1.0)
		return tr.x + half < sx - 1 if dir < 0 else tr.x - half > sx + 1
	var signal_green := func(s: Dictionary, t: float) -> bool:
		var ph := fmod(fmod(t, P) + P, P)
		if not in_win.call(s.id, ph):
			return false
		var rail = ctx.services.get("rail")
		var trains = rail.get("trains") if rail is Dictionary else null
		if trains is Array:
			var tr = null
			for q in trains:
				if q and q.get("track") == s.track:
					tr = q
					break
			if tr and (tr.get("x") is float or tr.get("x") is int) and is_finite(tr.x):
				if passed.call(tr, s.x):
					return false
				if s.kind == "start" and (tr.get("doorsOpen") if tr.get("doorsOpen") else 0.0) > 0.05:
					return false
		return true
	ctx.on_update(func(_dt, t):
		for s in side.signals:
			var g: bool = signal_green.call(s, t)
			if g != s.state:
				s.state = g
				s.litG.visible = g
				s.litR.visible = not g)
	for s in side.signals:
		var g: bool = signal_green.call(s, 0.0)
		s.state = g
		s.litG.visible = g
		s.litR.visible = not g

	var cat_poles := []
	for p in cat.poles:
		cat_poles.append({"x": p.x, "type": "centre" if p.type == "C" else "portal", "z": [-43.0] if p.type == "C" else [cat.zSouthPole, cat.zNorthPole]})
	var signals := []
	for s in side.signals:
		signals.append({"id": s.id, "x": s.x, "z": s.z, "track": s.track, "green": func(): return s.state})
	ctx.services["railway"] = {
		"catenaryPoles": cat_poles,
		"contactWireY": Catenary.CONTACT_Y, "messengerY": Catenary.MESSENGER_Y,
		"signals": signals,
		"crossover": {"x0": E.xo.xa, "x1": E.xo.xb},
		"fences": {"southZ": side.S.fence, "northZ": side.zs.call(side.S.fence, -1), "ranges": side.STRIP_X},
		"ballastY": E.ballastY,
		"stats": {"stones": track.stoneCount, "weeds": weeds.count, "merged": merged, "atlasFill": TX.atlas_fill(), "atlasFallbacks": TX.atlas_fallbacks},
	}
