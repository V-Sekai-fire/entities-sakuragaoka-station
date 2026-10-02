# houses/house.js: the procedural house. Foundation, walls, windows with shutters and grilles, the
# entrance, the balcony, kawara or metal roofs with ridges, fascia, gutters and downpipes, utilities
# and roof antennas, all appended to the module's GB through a Frame.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const GBM = preload("res://addons/sakuragaoka_station/world/houses/gb.gd")

const WALLS := {"plaster": ["plaster", 3], "paint": ["plaster", 3], "siding": ["siding", 1.2], "tile": ["tile", 0.96], "wood": ["wood", 1.2]}
const INTERIORS := ["int_lace", "int_lace", "int_curtain_pink", "int_curtain_green", "int_curtain_blue", "int_blind", "int_blind", "int_dark", "int_room", "int_room"]


static func _lod(S: Dictionary) -> int:
	return S.lod if S.get("lod") != null else 2


static func _sgn(x: float) -> float:
	return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else 0.0)


static func is_free(face: Dictionary, fl: int, u0: float, u1: float) -> bool:
	if not (u0 >= -face.len / 2.0 + 0.3 and u1 <= face.len / 2.0 - 0.3):
		return false
	for q in face.res:
		if q[0] == fl and not (u1 < q[1] or u0 > q[2]) and not (q.size() > 3 and q[3] == "low"):
			return false
	return true


static func reserve(face: Dictionary, fl: int, u0: float, u1: float) -> void:
	face.res.append([fl, u0, u1])


static func build_house(H, F, S: Dictionary) -> Dictionary:
	var M: Dictionary = H.M
	var r = S.rng
	var lod := _lod(S)
	var fy: float = S.floorY
	var gy: float = S.groundMin
	var FH: float = S.fh
	var out := {"faces": [], "vols": [], "ridgeY": 0.0, "doorWorld": null, "porch": null}
	var vols := [{"id": "main", "cx": 0.0, "cz": 0.0, "w": S.w, "d": S.d, "floors": S.floors}]
	if S.get("wing"):
		var wv: Dictionary = S.wing.duplicate()
		wv["id"] = "wing"
		wv["floors"] = S.wing.get("floors", 1) if S.wing.get("floors") else 1
		vols.append(wv)
	out.vols = vols
	for v in vols:
		v["top"] = fy + v.floors * FH
	for v in vols:
		var fh0 := fy - gy + 0.14
		F.boxB(M.concrete, S.foundColor, v.w - 0.04, fh0, v.d - 0.04, v.cx, gy - 0.14, v.cz, {"uv": {"world": 2}})
		F.boxB(M.plainLow, S.flashColor, v.w + 0.035, 0.045, v.d + 0.035, v.cx, fy - 0.03, v.cz)
		var w1: Dictionary = S.wall
		var w2: Dictionary = S.wall2 if S.get("wall2") else S.wall
		var extra := 0.9 if S.roof.type == "flat" else 0.0
		if v.floors == 1 or not S.get("wall2"):
			var ws: Array = WALLS[w1.kind]
			F.boxB(M[ws[0]], w1.color, v.w, v.floors * FH + 0.02 + extra, v.d, v.cx, fy - 0.02, v.cz, {"uv": {"world": ws[1]}})
		else:
			var ws1: Array = WALLS[w1.kind]
			var ws2: Array = WALLS[w2.kind]
			F.boxB(M[ws1[0]], w1.color, v.w, FH + 0.02, v.d, v.cx, fy - 0.02, v.cz, {"uv": {"world": ws1[1]}})
			F.boxB(M[ws2[0]], w2.color, v.w, (v.floors - 1) * FH + extra, v.d, v.cx, fy + FH, v.cz, {"uv": {"world": ws2[1]}})
		if S.get("belt") and v.floors > 1:
			for f in range(1, v.floors):
				F.boxB(M.plain, S.trim, v.w + 0.05, 0.14, v.d + 0.05, v.cx, fy + f * FH - 0.07, v.cz)
		if lod >= 1 and (w1.kind == "siding" or w2.kind == "siding") and S.get("cornerTrim"):
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					F.boxB(M.plain, S.trim, 0.09, v.floors * FH, 0.09, v.cx + sx * (v.w / 2.0 - 0.03), fy, v.cz + sz * (v.d / 2.0 - 0.03))
		H.col(F, v.cx, v.cz, v.w + 0.05, v.d + 0.05, 0, gy - 1, v.top + 3)
	var faces := []
	for v in vols:
		var defs := [
			{"side": "front", "x": v.cx, "z": v.cz + v.d / 2.0, "ry": 0.0, "len": v.w},
			{"side": "back", "x": v.cx, "z": v.cz - v.d / 2.0, "ry": PI, "len": v.w},
			{"side": "right", "x": v.cx + v.w / 2.0, "z": v.cz, "ry": PI / 2.0, "len": v.d},
			{"side": "left", "x": v.cx - v.w / 2.0, "z": v.cz, "ry": -PI / 2.0, "len": v.d},
		]
		for d in defs:
			var fr = F.sub(d.x, 0, d.z, d.ry)
			var face := {"vol": v, "side": d.side, "F": fr, "len": d.len, "ry": d.ry, "x": d.x, "z": d.z, "res": [], "floors": v.floors}
			for o in vols:
				if o == v:
					continue
				var ox0: float = o.cx - o.w / 2.0
				var ox1: float = o.cx + o.w / 2.0
				var oz0: float = o.cz - o.d / 2.0
				var oz1: float = o.cz + o.d / 2.0
				var hit = null
				if d.side == "front" and absf(oz0 - d.z) < 0.05:
					hit = [ox0 - d.x, ox1 - d.x]
				if d.side == "back" and absf(oz1 - d.z) < 0.05:
					hit = [-(ox1 - d.x), -(ox0 - d.x)]
				if d.side == "right" and absf(ox0 - d.x) < 0.05:
					hit = [-(oz1 - d.z), -(oz0 - d.z)]
				if d.side == "left" and absf(ox1 - d.x) < 0.05:
					hit = [oz0 - d.z, oz1 - d.z]
				if hit != null:
					for f in o.floors:
						face.res.append([f, hit[0] - 0.25, hit[1] + 0.25])
				if hit != null and o.floors < v.floors:
					face.res.append([o.floors, hit[0] - 0.1, hit[1] + 0.1, "low"])
			faces.append(face)
	out.faces = faces
	var face_of := func(vid: String, side: String):
		for f in faces:
			if f.vol.id == vid and f.side == side:
				return f
		return null
	var front: Dictionary = face_of.call("main", S.door.get("face", "front") if S.door.get("face") else "front")
	var dw := 1.7 if S.door.style == "door_slide" else 0.92
	var du: float = S.door.u
	reserve(front, 0, du - dw / 2.0 - 0.35, du + dw / 2.0 + 0.35)
	_build_entrance(H, front, du, dw, S, out)
	if S.get("balcony") and S.floors >= 2:
		var b: Dictionary = S.balcony
		var bf: Dictionary = face_of.call("main", b.get("face", "front") if b.get("face") else "front")
		reserve(bf, 1, b.u - b.w / 2.0 - 0.1, b.u + b.w / 2.0 + 0.1)
		_build_balcony(H, bf, b, S, out)
	for face in faces:
		for fl in face.floors:
			if face.vol.id == "wing" and face.side != "front" and face.side != "left" and face.side != "right":
				continue
			_place_windows(H, face, fl, S, r, lod)
	var main_v: Dictionary = vols[0]
	out.ridgeY = _build_roof(H, F, main_v, S.roof, S, out)
	if S.get("wing"):
		var w: Dictionary = vols[1]
		var pr: Dictionary = S.roof.duplicate()
		pr["type"] = "pentWing"
		pr["pitch"] = minf(S.roof.pitch, 0.38)
		pr["over"] = 0.45
		_build_wing_roof(H, F, w, S.wing.attach, pr, S)
	if S.get("skirt") and S.floors >= 2:
		var face: Dictionary = face_of.call("main", "front")
		build_pent(H, face.F, -face.len / 2.0 - 0.25, face.len / 2.0 + 0.25, fy + FH + 0.12, S.skirt.depth, 0.32, S.roof, S, true)
	_build_utilities(H, faces, S, r, lod, out)
	if S.get("antenna") and lod >= 1:
		_build_antenna(H, F, main_v, S, out)
	return out


static func _place_windows(H, face: Dictionary, fl: int, S: Dictionary, r, lod: int) -> void:
	var fy: float = S.floorY
	var FH: float = S.fh
	var L: float = face.len
	var role: String = "front" if face.side == "front" else ("back" if face.side == "back" else "side")
	var y0 := fy + fl * FH
	var types := []
	if role == "front":
		if fl == 0:
			types.append_array(["big" if S.get("bigFront") else "std", "std", "mid"])
		else:
			types.append_array(["std", "mid", "std"])
	elif role == "side":
		types.append_array(["mid", "small", "high", "slit", "mid"])
	else:
		types.append_array(["small", "mid", "std", "high"])
	var DIM := {"big": [1.69, 1.95, 0.08], "std": [1.69, 1.15, 0.85], "mid": [1.19, 1.12, 0.88], "small": [0.74, 0.9, 1.05], "high": [0.6, 0.48, 1.62],
		"slit": [0.36, 1.35, 0.7], "bay": [1.69, 1.15, 0.85]}
	var u := -L / 2.0 + 0.45 + r.f() * 0.4
	var guard := 0
	var count := 0
	var max_n := maxi(1, int(floor(L / 2.2)))
	while u < L / 2.0 - 0.5 and guard < 20 and count < max_n:
		guard += 1
		var t: String = types[int(floor(r.f() * types.size()))]
		if fl == 0 and role == "front" and count == 0 and S.get("bigFront"):
			t = "big"
		var w: float = DIM[t][0]
		var h: float = DIM[t][1]
		var sill: float = DIM[t][2]
		var u0 := u
		var u1 := u + w
		if u1 > L / 2.0 - 0.4:
			u += 0.4
			continue
		if not is_free(face, fl, u0 - 0.2, u1 + 0.2):
			u += 0.5
			continue
		var top_y := y0 + sill + h
		if top_y > y0 + FH - 0.25 and not (fl == face.floors - 1):
			u += 0.3
			continue
		reserve(face, fl, u0 - 0.15, u1 + 0.15)
		var kind := t
		if t == "std" and role == "front" and fl == 0 and lod >= 2 and r.f() < 0.18:
			kind = "bay"
		build_window(H, face.F, (u0 + u1) / 2.0, y0 + sill, w, h, kind, S, r, lod, role, fl)
		count += 1
		u = u1 + 0.6 + r.f() * (1.0 if role == "front" else 1.6)


static func _pick_int(r, S: Dictionary) -> String:
	var a: Array = S.interiors if S.get("interiors") else INTERIORS
	return a[int(floor(r.f() * a.size()))]


## One window unit on a face frame: cu is the centre u, yb the bottom y (local).
static func build_window(H, FF, cu: float, yb: float, w: float, h: float, kind: String, S: Dictionary, r, lod: int, role: String, fl: int) -> void:
	var M: Dictionary = H.M
	var A: Dictionary = H.A
	var fc = S.frameColor
	var frost: bool = kind == "high" or kind == "slit" or (kind == "small" and r.f() < 0.8) or (role == "back" and r.f() < 0.3)
	var cy := yb + h / 2.0
	if kind == "bay":
		var pd := 0.42
		FF.box(M.plain, S.trim, w + 0.24, 0.1, pd + 0.06, cu, yb - 0.05, pd / 2.0)
		FF.box(M.plain, S.trim, w + 0.3, 0.08, pd + 0.14, cu, yb + h + 0.07, pd / 2.0 + 0.03)
		FF.box(M.metal, S.roof.color if S.roof.mat == "metal" else "#6d737c", w + 0.34, 0.05, pd + 0.2, cu, yb + h + 0.14, pd / 2.0 + 0.05, {"rx": 0.18, "uv": {"world": 0.9}})
		for s in [-1, 1]:
			FF.box(M.plain, fc, 0.05, h, pd, cu + s * (w / 2.0 + 0.07), cy, pd / 2.0)
		FF.box(M.atlas, "#ffffff", w, h, 0.01, cu, cy, 0.02, {"uv": {"rect": A.rects[_pick_int(r, S)], "white": A.white}})
		FF.box(M.plain, fc, 0.05, h, 0.05, cu, cy, pd - 0.02)
		FF.box(M.glass, null, w + 0.1, h, 0.005, cu, cy, pd - 0.035, {"shadow": false})
		for s in [-1, 1]:
			FF.box(M.glass, null, 0.005, h, pd - 0.08, cu + s * (w / 2.0 + 0.06), cy, pd / 2.0, {"shadow": false})
		if lod >= 2 and r.f() < 0.7:
			H.props.sill_pot(FF, cu + (r.f() - 0.5) * w * 0.5, yb + 0.02, pd * 0.6)
		return
	var deep := 0.065
	var louver: bool = frost and (kind == "small" or kind == "mid") and r.f() < 0.4
	var inter: String
	if louver:
		inter = "int_louver"
	elif frost:
		inter = "int_frost"
	elif S.get("traditional") and r.f() < 0.5:
		inter = "int_shoji"
	elif r.f() < 0.04:
		inter = "int_warm"
	else:
		inter = _pick_int(r, S)
	var shut_p: float = S.shutterClosed if S.get("shutterClosed") != null else 0.08
	var shut: bool = not frost and (kind == "std" or kind == "big" or kind == "mid") and r.f() < shut_p
	if not shut:
		FF.box(M.atlas, "#ffffff", w - 0.04, h - 0.04, 0.01, cu, cy, 0.02, {"uv": {"rect": A.rects[inter], "white": A.white}, "skip": "rltdb"})
	var fw := 0.055
	FF.box(M.plain, fc, w + 0.02, fw, deep, cu, yb + h - fw / 2.0 + 0.01, deep / 2.0, {"skip": "btrl"})
	FF.box(M.plain, fc, w + 0.02, fw, deep, cu, yb + fw / 2.0 - 0.01, deep / 2.0, {"skip": "bdrl"})
	FF.box(M.plain, fc, fw, h + 0.02, deep, cu - w / 2.0 + fw / 2.0 - 0.01, cy, deep / 2.0, {"skip": "btd"})
	FF.box(M.plain, fc, fw, h + 0.02, deep, cu + w / 2.0 - fw / 2.0 + 0.01, cy, deep / 2.0, {"skip": "btd"})
	if kind != "high" and kind != "slit" and w > 0.7 and not louver:
		FF.box(M.plain, fc, 0.05, h - 0.06, 0.03, cu + 0.012, cy, deep - 0.012, {"skip": "btd"})
	if kind == "big" or kind == "std":
		if r.f() < 0.3:
			FF.box(M.plain, fc, w - 0.08, 0.03, 0.02, cu, yb + h * 0.62, 0.035, {"skip": "brl"})
	if not shut:
		FF.box(M.frost if frost and not louver else M.glass, null, w - 0.06, h - 0.06, 0.004, cu, cy, 0.036, {"shadow": false, "skip": "rltdb"})
	else:
		FF.box(M.shutter, S.shutterColor, w - 0.04, h - 0.04, 0.02, cu, cy, 0.03, {"uv": {"world": 0.5}, "skip": "rltdb"})
	FF.box(M.plain, S.sillColor if S.get("sillColor") else fc, w + 0.1, 0.03, 0.1, cu, yb - 0.02, 0.05, {"skip": "b"})
	var bigish: bool = kind == "std" or kind == "big" or kind == "mid"
	var sb = S.get("shutterStyle")
	if bigish and sb == "tobukuro" and lod >= 1:
		var side := (1 if cu > 0 else -1) * (1 if r.f() < 0.8 else -1)
		var tw := w / 2.0 + 0.04
		FF.box(M.shutter, S.shutterColor, tw, h + 0.12, 0.13, cu + side * (w / 2.0 + tw / 2.0), cy + 0.02, 0.065, {"uv": {"world": 0.5}, "skip": "b"})
		FF.box(M.plain, S.shutterColor, w + tw + 0.04, 0.05, 0.14, cu + side * tw / 2.0, yb + h + 0.09, 0.07, {"skip": "b"})
	elif bigish and sb == "roll" and lod >= 1:
		FF.box(M.plain, S.shutterColor, w + 0.12, 0.26, 0.24, cu, yb + h + 0.14, 0.12, {"skip": "b"})
		for s in [-1, 1]:
			FF.box(M.plain, S.shutterColor, 0.05, h, 0.07, cu + s * (w / 2.0 + 0.035), cy, 0.035, {"skip": "btd"})
	if S.get("hoods") and bigish and lod >= 1 and not (sb == "roll"):
		var tb: bool = sb == "tobukuro"
		FF.box(M.metal, S.hoodColor, w + (w / 2.0 + 0.3 if tb else 0.3), 0.045, 0.42, cu + (((1 if cu > 0 else -1) * w / 4.0) if tb else 0.0), yb + h + 0.22, 0.2, {"rx": 0.22, "uv": {"world": 0.9}})
	if frost and (kind == "small" or kind == "mid") and lod >= 1 and r.f() < 0.75:
		var n := maxi(3, int(T.js_round(w / 0.12)))
		for i in n + 1:
			FF.box(M.plain, S.grilleColor, 0.022, h + 0.06, 0.03, cu - w / 2.0 + i * w / n, cy, 0.1, {"skip": "btdb"})
		FF.box(M.plain, S.grilleColor, w + 0.06, 0.035, 0.05, cu, yb + h + 0.03, 0.09)
		FF.box(M.plain, S.grilleColor, w + 0.06, 0.035, 0.05, cu, yb - 0.02, 0.09)
	if fl >= 1 and kind == "big":
		FF.box(M.plain, S.frameColor, w + 0.1, 0.04, 0.05, cu, yb + 0.95, 0.24)
		for i in 11:
			FF.box(M.plain, S.frameColor, 0.02, 0.9, 0.02, cu - w / 2.0 + i * w / 10.0, yb + 0.5, 0.24, {"skip": "td"})
		for s in [-1, 1]:
			FF.box(M.plain, S.frameColor, 0.04, 0.04, 0.24, cu + s * (w / 2.0 + 0.03), yb + 0.95, 0.12)
	if lod >= 2 and r.f() < 0.55:
		H.decal(FF, "streak", cu, yb - 0.05 - 0.35, w * 0.9, 0.7, 0.012, "#ffffff")
	if lod >= 2 and role == "front" and fl == 0 and kind == "std" and r.f() < 0.25:
		H.props.sill_pot(FF, cu + (r.f() - 0.5) * w * 0.4, yb + 0.0, 0.07)


static func _build_entrance(H, face: Dictionary, du: float, dw: float, S: Dictionary, out: Dictionary) -> void:
	var M: Dictionary = H.M
	var A: Dictionary = H.A
	var FF = face.F
	var r = S.rng
	var fy: float = S.floorY
	var lod := _lod(S)
	var style: String = S.door.style
	var dh := 1.95 if style == "door_slide" else 2.05
	var g_front: float = S.groundFront if S.get("groundFront") != null else 0.0
	var pw := dw + 1.1
	var pd: float = S.door.porchD if S.door.get("porchD") else 1.25
	var porch_top := fy - 0.14
	var steps := maxi(1, int(T.js_round((porch_top - g_front) / 0.17)))
	FF.boxB(M.tile, S.porchColor, pw, porch_top - g_front + 0.12, pd, du, g_front - 0.12, pd / 2.0, {"uv": {"world": 0.96}})
	var sh := (porch_top - g_front) / (steps + 1)
	for i in steps:
		var sd := 0.3 * (steps - i)
		FF.boxB(M.tile, S.porchColor, pw - 0.2, g_front + sh * (i + 1) - (g_front - 0.1), 0.3, du, g_front - 0.1, pd + sd - 0.15, {"uv": {"world": 0.96}})
	H.walk(FF, du, pd / 2.0, pw, pd, 0, porch_top)
	for i in steps:
		H.walk(FF, du, pd + 0.3 * (steps - i) - 0.15, pw - 0.2, 0.3, 0, g_front + sh * (i + 1))
	out.porch = {"F": FF, "u": du, "w": pw, "d": pd + 0.3 * steps, "top": porch_top}
	var fr = S.doorFrame if S.get("doorFrame") else S.frameColor
	FF.box(M.plain, fr, dw + 0.14, 0.07, 0.09, du, porch_top + dh + 0.035, 0.045)
	for s in [-1, 1]:
		FF.box(M.plain, fr, 0.07, dh, 0.09, du + s * (dw / 2.0 + 0.035), porch_top + dh / 2.0, 0.045)
	FF.box(M.atlas, "#ffffff", dw, dh, 0.03, du, porch_top + dh / 2.0, 0.02, {"uv": {"rect": A.rects[style], "white": A.white}})
	out.doorWorld = FF.w(du, porch_top, 0.6)
	if style != "door_slide" and r.f() < 0.5 and lod >= 1:
		var s := -1 if r.f() < 0.5 else 1
		FF.box(M.frost, null, 0.24, dh - 0.1, 0.004, du + s * (dw / 2.0 + 0.2), porch_top + dh / 2.0, 0.03, {"shadow": false})
		FF.box(M.plain, fr, 0.05, dh, 0.08, du + s * (dw / 2.0 + 0.34), porch_top + dh / 2.0, 0.04)
	var cT: String = S.door.canopy if S.door.get("canopy") else "slab"
	var cy := porch_top + dh + 0.3
	if cT == "slab":
		FF.box(M.plain, S.canopyColor, pw + 0.1, 0.12, pd + 0.1, du, cy, (pd + 0.1) / 2.0)
		FF.box(M.plain, S.soffitColor, pw, 0.02, pd, du, cy - 0.07, pd / 2.0)
	elif cT == "roof":
		build_pent(H, FF, du - pw / 2.0 - 0.15, du + pw / 2.0 + 0.15, cy + 0.1, pd + 0.15, 0.45, S.roof, S, false)
	elif cT == "posts":
		FF.box(M.plain, S.canopyColor, pw + 0.3, 0.12, pd + 0.2, du, cy, (pd + 0.2) / 2.0)
		for s in [-1, 1]:
			FF.boxB(M.plain, S.trim, 0.1, cy - porch_top, 0.1, du + s * (pw / 2.0 + 0.05), porch_top, pd + 0.05)
	var ls := -1 if du > 0 else 1
	var lx := du + ls * (dw / 2.0 + 0.32)
	if lod >= 2 and cT != "none" and r.f() < 0.3:
		H.laundry.chime(FF, du - ls * (pw / 2.0 - 0.2), cy - 0.22 if cT == "roof" else cy - 0.1, 0.4)
	FF.box(M.plain, "#4b4d52", 0.14, 0.24, 0.12, lx, porch_top + 1.95, 0.08)
	FF.box(M.lamp, null, 0.1, 0.16, 0.02, lx, porch_top + 1.95, 0.145, {"shadow": false})
	if not S.get("gatePlate"):
		var ix := du - ls * (dw / 2.0 + 0.26)
		H.props.plate(FF, ix, porch_top + 1.55, 0.02, S.plate)
		FF.box(M.atlas, "#ffffff", 0.09, 0.15, 0.03, ix, porch_top + 1.25, 0.015, {"uv": {"rect": A.rects.intercom, "white": A.white}})
		if S.get("wallMailbox"):
			FF.box(M.atlas, "#ffffff", 0.34, 0.26, 0.1, lx, porch_top + 1.1, 0.05, {"uv": {"rect": A.rects[S.wallMailbox], "white": A.white}})
	if lod >= 1:
		H.props.doorstep(FF, du, dw, porch_top, pw, pd, S)


static func _build_balcony(H, face: Dictionary, b: Dictionary, S: Dictionary, _out: Dictionary) -> void:
	var M: Dictionary = H.M
	var FF = face.F
	var r = S.rng
	var fy: float = S.floorY
	var FH: float = S.fh
	var yF := fy + FH
	var bw: float = b.w
	var bd: float = b.depth
	var lod := _lod(S)
	var S2 := S.duplicate()
	S2["shutterStyle"] = "none" if S.get("shutterStyle") == "tobukuro" else S.get("shutterStyle")
	build_window(H, FF, b.u, yF + 0.05, minf(1.69, bw - 0.6), 1.9, "big", S2, r, lod, "balc", 0)
	FF.box(M.plain, S.balconySlab, bw, 0.18, bd, b.u, yF - 0.06, bd / 2.0)
	FF.box(M.plain, S.soffitColor, bw - 0.06, 0.02, bd - 0.06, b.u, yF - 0.155, bd / 2.0)
	var rh := 1.05
	if b.rail == "panel":
		var wm: Dictionary = S.wall2 if S.get("wall2") else S.wall
		var pc = S.balconyPanel if S.get("balconyPanel") else wm.color
		FF.boxB(M.plain, pc, bw, rh, 0.08, b.u, yF + 0.03, bd - 0.04)
		for s in [-1, 1]:
			FF.boxB(M.plain, pc, 0.08, rh, bd - 0.08, b.u + s * (bw / 2.0 - 0.04), yF + 0.03, (bd - 0.08) / 2.0)
		FF.box(M.plain, S.trim, bw + 0.04, 0.05, 0.12, b.u, yF + 0.03 + rh + 0.025, bd - 0.04)
		FF.box(M.plain, "#8f949a", 0.05, 0.05, 0.16, b.u + bw / 2.0 - 0.3, yF - 0.02, bd + 0.06)
	else:
		var c = S.railColor
		FF.box(M.plain, c, bw, 0.05, 0.06, b.u, yF + rh, bd - 0.03)
		FF.box(M.plain, c, bw, 0.04, 0.04, b.u, yF + 0.12, bd - 0.03)
		var n := int(T.js_round(bw / 0.12))
		for i in n + 1:
			FF.box(M.plain, c, 0.022, rh - 0.12, 0.022, b.u - bw / 2.0 + 0.02 + i * (bw - 0.04) / n, yF + 0.12 + (rh - 0.12) / 2.0, bd - 0.03)
		for s in [-1, 1]:
			FF.box(M.plain, c, 0.05, 0.05, bd, b.u + s * (bw / 2.0 - 0.025), yF + rh, bd / 2.0)
			for k in range(1, 5):
				FF.box(M.plain, c, 0.022, rh - 0.12, 0.022, b.u + s * (bw / 2.0 - 0.025), yF + 0.12 + (rh - 0.12) / 2.0, k * bd / 5.0 - 0.02)
	if b.get("posts"):
		var gf: float = S.groundFront if S.get("groundFront") != null else 0.0
		for s in [-1, 1]:
			FF.boxB(M.plain, S.trim, 0.1, yF - 0.15 - gf + 0.1, 0.1, b.u + s * (bw / 2.0 - 0.08), gf - 0.1, bd - 0.1)
	var py := yF + 1.75
	var pz := bd * 0.55
	for s in [-1, 1]:
		var ax: float = b.u + s * (bw / 2.0 - 0.25)
		FF.box(M.plain, "#c9ccd1", 0.04, 0.04, pz + 0.05, ax, py + 0.06, pz / 2.0)
		FF.box(M.plain, "#c9ccd1", 0.04, 0.3, 0.04, ax, py - 0.07, 0.02)
	var x0: float = b.u - bw / 2.0 + 0.15
	var x1: float = b.u + bw / 2.0 - 0.15
	FF.cyl(M.plain, S.poleColor if S.get("poleColor") else "#8fb3c9", 0.016, x1 - x0 + 0.3, (x0 + x1) / 2.0, py + 0.1, pz, {"rz": PI / 2.0, "seg": 6})
	if b.get("laundry"):
		H.laundry.line(FF, x0 + 0.1, x1 - 0.1, py + 0.1, pz, r, b.laundryMix)
	if b.get("futon") and lod >= 1:
		H.props.futon(FF, b.u + (r.f() - 0.5) * (bw - 1.6), yF + rh + 0.05, bd - 0.03, r)
	if lod >= 2:
		if r.f() < 0.6:
			H.props.ac_unit(FF, b.u - bw / 2.0 + 0.55, yF + 0.03, 0.3, 0)
		if r.f() < 0.45:
			H.props.pot(FF, b.u + bw / 2.0 - 0.35, yF + 0.03, bd - 0.3, r, 0.7)
		if b.get("dish"):
			H.props.dish(FF, b.u + bw / 2.0 - 0.3, yF + rh - 0.15, bd + 0.05, 0)
		if b.get("chime"):
			H.laundry.chime(FF, b.u - bw / 2.0 + 0.35, yF + 2.25, 0.35)
		if b.get("koinobori"):
			H.laundry.koinobori_small(FF, b.u + bw / 2.0 - 0.12, yF + rh, bd - 0.05)


static func _roof_mats(H, R: Dictionary) -> Dictionary:
	var M: Dictionary = H.M
	if R.mat == "metal":
		return {"top": M.metal, "topS": 0.9, "edge": null, "ridge": M.plain, "t": 0.1}
	return {"top": M.kawara, "topS": 1.0, "edge": M.kawaraEdge, "ridge": M.ridge, "t": 0.2}


## The main roof over a volume. Returns the ridge y.
static func _build_roof(H, F, v: Dictionary, R: Dictionary, S: Dictionary, out: Dictionary) -> float:
	var M: Dictionary = H.M
	var top: float = v.top
	var rm := _roof_mats(H, R)
	var tv: float = rm.t
	var p: float = R.pitch
	var o: float = R.over
	var col = R.color
	var ridge_col = R.ridgeColor if R.get("ridgeColor") else R.color
	var type: String = R.type
	var lod := _lod(S)
	var W: float = v.w
	var D: float = v.d
	var cx: float = v.cx
	var cz: float = v.cz
	var along_z: bool = (type == "gable" and R.get("axis") == "z") or (type == "hip" and D > W)
	var RF = F.sub(cx, 0, cz, PI / 2.0) if along_z else F.sub(cx, 0, cz, 0)
	if along_z:
		var t := W
		W = D
		D = t
	var og := minf(o, 0.42) if type == "gable" else o
	var hx := W / 2.0 + og
	var hz := D / 2.0 + o
	var yE := top + tv - o * p
	var ridge_y := top
	var top_s: float = rm.topS
	var add_plane := func(pts: Array, sgn: float):
		var sl := GBM.slab(pts, tv, func(q): return Vector2(q[0] / (1.2 * top_s), -absf(hz - sgn * q[2]) * sqrt(1 + p * p) / 1.0))
		H.gb.mesh(rm.top, col, sl.p, sl.n, sl.u, sl.i, RF.M(0, 0, 0))
	var add_side_plane := func(pts: Array, sgn: float):
		var sl := GBM.slab(pts, tv, func(q): return Vector2(q[2] / (1.2 * top_s), -absf(hx - sgn * q[0]) * sqrt(1 + p * p)))
		H.gb.mesh(rm.top, col, sl.p, sl.n, sl.u, sl.i, RF.M(0, 0, 0))
	var trim_c = S.fasciaColor
	var soff = S.soffitColor
	var gut = S.gutterColor
	var gutters: bool = S.get("gutters") != false
	var eave_line := func(x0: float, x1: float, z: float, dir: float):
		var L := x1 - x0
		var xm := (x0 + x1) / 2.0
		RF.box(M.plain, trim_c, L, 0.19, 0.04, xm, yE - tv - 0.05, z - dir * 0.02)
		var sz := (absf(z) - D / 2.0) - 0.04
		RF.box(M.plain, soff, L - 0.04, 0.02, sz, xm, yE - tv - 0.12, dir * (D / 2.0 + sz / 2.0))
		if rm.edge != null and lod >= 1:
			RF.box(rm.edge, col, L, 0.1, 0.07, xm, yE - 0.05, z - dir * 0.02, {"uv": {"world": 0.3, "worldV": 0.1}})
		if gutters:
			RF.box(M.plain, gut, L, 0.09, 0.11, xm, yE - tv - 0.06, z + dir * 0.06)
	var eave_line_z := func(z0: float, z1: float, x: float, dir: float):
		var L := z1 - z0
		var zm := (z0 + z1) / 2.0
		RF.box(M.plain, trim_c, 0.04, 0.19, L, x - dir * 0.02, yE - tv - 0.05, zm)
		var sx := (absf(x) - W / 2.0) - 0.04
		RF.box(M.plain, soff, sx, 0.02, L - 0.04, dir * (W / 2.0 + sx / 2.0), yE - tv - 0.12, zm)
		if rm.edge != null and lod >= 1:
			RF.box(rm.edge, col, 0.07, 0.1, L, x - dir * 0.02, yE - 0.05, zm, {"uv": {"world": 0.3, "worldV": 0.1}})
		if gutters:
			RF.box(M.plain, gut, 0.11, 0.09, L, x + dir * 0.06, yE - tv - 0.06, zm)
	if type == "hip":
		var rl := maxf(0.0, hx - hz)
		var yR := yE + hz * p
		ridge_y = yR
		add_plane.call([[-hx, yE, hz], [hx, yE, hz], [rl, yR, 0], [-rl, yR, 0]], 1.0)
		add_plane.call([[hx, yE, -hz], [-hx, yE, -hz], [-rl, yR, 0], [rl, yR, 0]], -1.0)
		add_side_plane.call([[hx, yE, hz], [hx, yE, -hz], [rl, yR, 0]], 1.0)
		add_side_plane.call([[-hx, yE, -hz], [-hx, yE, hz], [-rl, yR, 0]], -1.0)
		eave_line.call(-hx, hx, hz, 1.0)
		eave_line.call(-hx, hx, -hz, -1.0)
		eave_line_z.call(-hz + 0.05, hz - 0.05, hx, 1.0)
		eave_line_z.call(-hz + 0.05, hz - 0.05, -hx, -1.0)
		var rw := 0.26 if rm.edge != null else 0.16
		var rh := 0.2 if rm.edge != null else 0.08
		if rl > 0.05:
			RF.beam(rm.ridge, ridge_col, [-rl - 0.1, yR + rh / 2.0 - 0.03, 0], [rl + 0.1, yR + rh / 2.0 - 0.03, 0], rw, rh, {"uv": {"world": 0.6, "worldV": 0.2}})
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				RF.beam(rm.ridge, ridge_col, [sx * hx, yE + rh / 2.0 - 0.02, sz * hz], [sx * rl, yR + rh / 2.0 - 0.03, 0], rw * 0.8, rh * 0.85, {"uv": {"world": 0.6, "worldV": 0.2}})
		if rm.edge != null and rl > 0.05:
			for sx in [-1, 1]:
				RF.box(M.plain, ridge_col, 0.12, 0.34, 0.34, sx * (rl + 0.12), yR + 0.14, 0)
		_downpipe(H, RF, hx - 0.1, hz + 0.06, W / 2.0, D / 2.0, yE - tv - 0.06, S, 1)
		_downpipe(H, RF, -hx + 0.1, -hz - 0.06, -W / 2.0, -D / 2.0, yE - tv - 0.06, S, -1)
	elif type == "gable":
		var yR := yE + hz * p
		ridge_y = yR
		add_plane.call([[-hx, yE, hz], [hx, yE, hz], [hx, yR, 0], [-hx, yR, 0]], 1.0)
		add_plane.call([[hx, yE, -hz], [-hx, yE, -hz], [-hx, yR, 0], [hx, yR, 0]], -1.0)
		eave_line.call(-hx, hx, hz, 1.0)
		eave_line.call(-hx, hx, -hz, -1.0)
		var wm: Dictionary = S.wall2 if S.get("wall2") else S.wall
		var mk: String = WALLS[wm.kind][0]
		var s: float = WALLS[wm.kind][1]
		for sx in [-1, 1]:
			var pts := [[sx * W / 2.0, top - 0.01, D / 2.0], [sx * W / 2.0, top - 0.01, -D / 2.0], [sx * W / 2.0, top + (D / 2.0) * p, 0]]
			var pg := GBM.poly(pts, [sx, 0, 0], func(q): return Vector2(q[2] / s, q[1] / s))
			H.gb.mesh(M[mk], wm.color, pg.p, pg.n, pg.u, pg.i, RF.M(0, 0, 0))
			for sz in [-1, 1]:
				RF.beam(M.plain, trim_c, [sx * (hx + 0.015), yE - tv * 0.6, sz * hz], [sx * (hx + 0.015), yR - tv * 0.6, 0], 0.045, 0.26, {"extend": 0.1})
				if rm.edge != null and lod >= 1:
					RF.beam(rm.ridge, ridge_col, [sx * (hx - 0.08), yE + 0.05, sz * hz], [sx * (hx - 0.08), yR + 0.05, 0], 0.2, 0.08, {"uv": {"world": 0.6, "worldV": 0.2}})
			if lod >= 1:
				RF.box(M.plain, S.trim, 0.04, 0.34, 0.5, sx * (W / 2.0 + 0.02), top + (D / 2.0) * p * 0.45, 0)
		var rw := 0.28 if rm.edge != null else 0.18
		var rh := 0.22 if rm.edge != null else 0.08
		RF.beam(rm.ridge, ridge_col, [-hx - 0.05, yR + rh / 2.0 - 0.03, 0], [hx + 0.05, yR + rh / 2.0 - 0.03, 0], rw, rh, {"uv": {"world": 0.6, "worldV": 0.2}})
		if rm.edge != null:
			for sx in [-1, 1]:
				RF.box(M.plain, ridge_col, 0.12, 0.4, 0.4, sx * (hx + 0.02), yR + 0.14, 0)
		_downpipe(H, RF, hx - 0.1, hz + 0.06, W / 2.0, D / 2.0, yE - tv - 0.06, S, 1)
		_downpipe(H, RF, -hx + 0.1, -hz - 0.06, -W / 2.0, -D / 2.0, yE - tv - 0.06, S, -1)
	elif type == "shed":
		var s := -1.0 if R.get("reverse") else 1.0
		var y_low := yE
		var y_high := yE + 2.0 * hz * p
		ridge_y = y_high
		var pts := [[-hx, y_low, s * hz], [hx, y_low, s * hz], [hx, y_high, -s * hz], [-hx, y_high, -s * hz]]
		var sl := GBM.slab(pts, tv, func(q): return Vector2(q[0] / (1.2 * top_s), -(hz - s * q[2]) * sqrt(1 + p * p)))
		H.gb.mesh(rm.top, col, sl.p, sl.n, sl.u, sl.i, RF.M(0, 0, 0))
		eave_line.call(-hx, hx, s * hz, s)
		RF.box(M.plain, trim_c, W + 2.0 * og, 0.25, 0.04, 0, y_high - tv - 0.02, -s * (hz + 0.02))
		var wm: Dictionary = S.wall2 if S.get("wall2") else S.wall
		var mk: String = WALLS[wm.kind][0]
		var ws: float = WALLS[wm.kind][1]
		for sx in [-1, 1]:
			var pts2 := [[sx * W / 2.0, top - 0.01, s * D / 2.0], [sx * W / 2.0, top - 0.01, -s * D / 2.0], [sx * W / 2.0, top + D * p, -s * D / 2.0]]
			var pg := GBM.poly(pts2, [sx, 0, 0], func(q): return Vector2(q[2] / ws, q[1] / ws))
			H.gb.mesh(M[mk], wm.color, pg.p, pg.n, pg.u, pg.i, RF.M(0, 0, 0))
			RF.beam(M.plain, trim_c, [sx * (hx + 0.015), y_low - tv * 0.6, s * hz], [sx * (hx + 0.015), y_high - tv * 0.6, -s * hz], 0.045, 0.24, {"extend": 0.05})
		RF.boxB(M[mk], wm.color, W, D * p, 0.02, 0, top - 0.01, -s * (D / 2.0 - 0.011), {"uv": {"world": ws}})
		var rv := -1.0 if R.get("reverse") else 1.0
		_downpipe(H, RF, rv * (hx - 0.1), s * (hz + 0.06), rv * W / 2.0, s * D / 2.0, yE - tv - 0.06, S, s)
	elif type == "flat":
		RF.boxB(M.plain, S.trim, W + 0.1, 0.12, D + 0.1, 0, top + 0.9, 0)
		ridge_y = top + 1.0
	if S.get("solar") and (type == "hip" or type == "gable") and lod >= 1:
		var pw := minf(W * 0.7, 5)
		var ph := minf(hz * 0.7, 2.6)
		var zc := hz * 0.5
		var yc := yE + (hz - zc) * p + 0.08
		RF.box(H.M.atlas, "#ffffff", pw, 0.05, ph, 0, yc, zc, {"rx": atan(p), "uv": {"rect": H.A.rects.solar, "white": H.A.white, "faces": "all"}})
	out.roofFrame = RF
	out.roofHx = hx
	out.roofHz = hz
	out.roofYE = yE
	out.roofP = p
	out.alongZ = along_z
	return ridge_y


## The wing roof: a pent leaning against the host face of the main volume.
static func _build_wing_roof(H, F, w: Dictionary, host: String, R: Dictionary, S: Dictionary) -> void:
	var fy: float = S.floorY
	var top: float = fy + S.fh * w.floors
	var FF
	var L0: float
	var L1: float
	var depth: float
	if host == "front":
		FF = F.sub(0, 0, w.cz - w.d / 2.0, 0)
		L0 = w.cx - w.w / 2.0
		L1 = w.cx + w.w / 2.0
		depth = w.d
	elif host == "back":
		FF = F.sub(0, 0, w.cz + w.d / 2.0, PI)
		L0 = -(w.cx + w.w / 2.0)
		L1 = -(w.cx - w.w / 2.0)
		depth = w.d
	elif host == "right":
		FF = F.sub(w.cx - w.w / 2.0, 0, 0, PI / 2.0)
		L0 = -(w.cz + w.d / 2.0)
		L1 = -(w.cz - w.d / 2.0)
		depth = w.w
	else:
		FF = F.sub(w.cx + w.w / 2.0, 0, 0, -PI / 2.0)
		L0 = w.cz - w.d / 2.0
		L1 = w.cz + w.d / 2.0
		depth = w.w
	var p: float = R.pitch
	var rise := depth * p
	build_pent(H, FF, L0 - 0.4, L1 + 0.4, top + rise + 0.05, depth + 0.45, p, S.roof, S, true, {"closeSides": true, "top": top, "depth": depth})


## A pent roof on a face frame from u0 to u1, high edge at y against the wall, projecting d.
static func build_pent(H, FF, u0: float, u1: float, y: float, d: float, p: float, R: Dictionary, S: Dictionary, gutter: bool, o: Dictionary = {}) -> void:
	var M: Dictionary = H.M
	var rm := _roof_mats(H, R)
	var tv := minf(rm.t, 0.16)
	var y_low := y - d * p
	var top_s: float = rm.topS
	var pts := [[u0, y + tv, 0], [u1, y + tv, 0], [u1, y_low + tv, d], [u0, y_low + tv, d]]
	var sl := GBM.slab(pts, tv, func(q): return Vector2(q[0] / (1.2 * top_s), -(d - q[2]) * sqrt(1 + p * p)))
	H.gb.mesh(rm.top, R.color, sl.p, sl.n, sl.u, sl.i, FF.M(0, 0, 0))
	var L := u1 - u0
	var um := (u0 + u1) / 2.0
	FF.box(M.plain, S.fasciaColor, L, 0.17, 0.04, um, y_low - 0.02, d - 0.02)
	if rm.edge != null:
		FF.box(rm.edge, R.color, L, 0.09, 0.07, um, y_low + tv - 0.04, d - 0.02, {"uv": {"world": 0.3, "worldV": 0.09}})
	FF.box(M.plain, S.soffitColor, L - 0.06, 0.02, d - 0.06, um, y_low - 0.1, d / 2.0)
	if gutter and S.get("gutters") != false:
		FF.box(M.plain, S.gutterColor, L, 0.08, 0.1, um, y_low - 0.05, d + 0.05)
	FF.box(M.plain, S.flashColor, L, 0.06, 0.05, um, y + tv + 0.02, 0.02)
	if o.get("closeSides"):
		var wm: Dictionary = S.wall
		var mk: String = WALLS[wm.kind][0]
		var s: float = WALLS[wm.kind][1]
		var dd: float = o.depth
		for uu in [u0 + 0.4, u1 - 0.4]:
			var pts2 := [[uu, o.top - 0.01, 0], [uu, o.top - 0.01, dd], [uu, y - 0.02, 0]]
			var pg := GBM.poly(pts2, [-1 if uu < um else 1, 0, 0], func(q): return Vector2(q[2] / s, q[1] / s))
			H.gb.mesh(M[mk], wm.color, pg.p, pg.n, pg.u, pg.i, FF.M(0, 0, 0))
		FF.box(M.ridge if rm.edge != null else M.plain, R.color, L, 0.1, 0.16, um, y + tv + 0.05, 0.06, {"uv": {"world": 0.6, "worldV": 0.2}})


static func _downpipe(H, RF, gx: float, gz: float, wx: float, wz: float, gy_top: float, S: Dictionary, dir: float) -> void:
	var M: Dictionary = H.M
	var c = S.gutterColor
	var g0: float = S.groundMin - 0.02
	var px := wx - _sgn(wx) * 0.12
	var pz := wz + dir * 0.06
	RF.beam(M.plain, c, [gx, gy_top - 0.05, gz], [px, gy_top - 0.45, pz], 0.06, 0.06)
	RF.cyl(M.plain, c, 0.032, gy_top - 0.45 - g0, px, (gy_top - 0.45 + g0) / 2.0, pz, {"seg": 6})
	for k in range(1, 4):
		RF.box(M.plain, c, 0.09, 0.03, 0.08, px, g0 + (gy_top - g0) * k / 4.0, pz - dir * 0.03)
	RF.box(M.concrete, "#b8b6ae", 0.3, 0.06, 0.3, px, g0 + 0.03, pz + dir * 0.05, {"uv": {"world": 2}})


static func _build_utilities(H, faces: Array, S: Dictionary, r, lod: int, out: Dictionary) -> void:
	var P = H.props
	var sides := []
	for f in faces:
		if f.vol.id == "main" and (f.side == "left" or f.side == "right" or f.side == "back"):
			sides.append(f)
	var g0: float = S.groundMin
	var find_spot := func(face: Dictionary, w: float, fl: int = 0, pref: int = 0):
		var L: float = face.len
		for k in 14:
			var u: float
			if pref != 0:
				u = pref * (L / 2.0 - 0.5 - w / 2.0) - pref * k * 0.35
			else:
				u = -L / 2.0 + 0.5 + w / 2.0 + r.f() * (L - 1.0 - w)
			if u - w / 2.0 < -L / 2.0 + 0.3 or u + w / 2.0 > L / 2.0 - 0.3:
				continue
			if is_free(face, fl, u - w / 2.0, u + w / 2.0):
				reserve(face, fl, u - w / 2.0, u + w / 2.0)
				return u
		return null
	var side_f := []
	for f in sides:
		if f.side != "back":
			side_f.append(f)
	var mf = null
	var mi := int(floor(r.f() * side_f.size()))
	if mi < side_f.size():
		mf = side_f[mi]
	elif sides.size() > 0:
		mf = sides[0]
	if mf != null:
		var pref := -1 if mf.side == "right" else 1
		var u = find_spot.call(mf, 0.4, 0, pref)
		if u != null:
			P.elec_meter(mf.F, u, S.floorY + 1.3)
	var gi := int(floor(r.f() * sides.size()))
	var gf = sides[gi] if gi < sides.size() else null
	if gf != null and lod >= 1:
		var u = find_spot.call(gf, 0.45)
		if u != null:
			if S.get("propane"):
				P.propane(gf.F, u, g0)
			else:
				P.gas_meter(gf.F, u, S.floorY + 0.55, g0)
		var u2 = find_spot.call(gf, 0.55)
		if u2 != null and lod >= 2:
			P.water_heater(gf.F, u2, S.floorY + 0.7)
	var nAC := (1 + int(floor(r.f() * 2.4))) if lod >= 2 else (1 if lod >= 1 else 0)
	for i in nAC:
		var fi := int(floor(r.f() * sides.size()))
		if fi >= sides.size():
			break
		var f: Dictionary = sides[fi]
		var u = find_spot.call(f, 0.95)
		if u == null:
			continue
		var to: float = S.floorY + S.fh + 2.2 if f.floors > 1 and r.f() < 0.6 else S.floorY + 2.1
		P.ac_unit(f.F, u, g0 - 0.0, 0.33, to)
		out["acCount"] = out.get("acCount", 0) + 1
	if lod >= 2:
		for i in 2:
			var fi := int(floor(r.f() * sides.size()))
			if fi >= sides.size():
				continue
			var f: Dictionary = sides[fi]
			var fl := 1 if f.floors > 1 and r.f() < 0.5 else 0
			var u = find_spot.call(f, 0.3, fl)
			if u != null:
				P.vent_hood(f.F, u, S.floorY + fl * S.fh + 2.1)
	if lod >= 1:
		for f in faces:
			if f.vol.floors < 1:
				continue
			var n := int(floor(f.len / 3.0))
			for k in n:
				var u: float = -f.len / 2.0 + (k + 0.5) * f.len / n
				var blocked := false
				for q in f.res:
					if q[0] == 0 and not (u + 0.25 < q[1] or u - 0.25 > q[2]):
						blocked = true
						break
				if blocked:
					continue
				f.F.box(H.M.atlas, "#ffffff", 0.34, 0.12, 0.02, u, S.floorY - 0.2, -0.01, {"uv": {"rect": H.A.rects.vent, "white": H.A.white}})
	if lod >= 2 and r.f() < 0.5 and mf != null:
		var u = find_spot.call(mf, 0.3, 0)
		if u != null:
			mf.F.box(H.M.atlas, "#ffffff", 0.3, 0.125, 0.012, u, S.floorY + 1.95, 0.006, {"uv": {"rect": H.A.rects["addr%d" % int(floor(r.f() * 6))], "white": H.A.white}})
	if lod >= 2:
		for f in faces:
			if f.vol.id != "main" or f.side == "front":
				continue
			if r.f() < 0.6:
				H.decal(f.F, "dirt", (r.f() - 0.5) * f.len * 0.3, S.floorY - 0.18, f.len * 0.8, 0.5, 0.03, "#ffffff")


static func _build_antenna(H, _F, _v: Dictionary, S: Dictionary, out: Dictionary) -> void:
	var M: Dictionary = H.M
	var ctx = H.ctx
	var r = S.rng
	var RF = out.roofFrame
	var yR: float = out.ridgeY
	var ax := (r.f() - 0.5) * maxf(0.2, (out.roofHx - out.roofHz)) * 1.2
	var h := 2.2 + r.f() * 1.2
	RF.cyl(M.plain, "#9aa1a8", 0.022, h + 0.3, ax, yR + h / 2.0 - 0.05, 0, {"seg": 6})
	RF.box(M.plain, "#8b9199", 0.3, 0.05, 0.3, ax, yR + 0.12, 0)
	var az: float = H.antenna_az - RF.ry
	var add_yagi := func(yy: float, ln: float, n: int, ew: float):
		var c := cos(az)
		var s := sin(az)
		var Pf := func(a: float, b: float, y: float): return RF.w(ax + a * c + b * s, y, -a * s + b * c)
		ctx.wires.add([Pf.call(-ln * 0.35, 0.0, yy), Pf.call(ln * 0.65, 0.0, yy)], {"width": 0.03, "color": "#8a9098"})
		for i in n:
			var a := -ln * 0.3 + i * ln * 0.9 / (n - 1)
			var e := ew * (1.0 - i / (n * 1.6))
			ctx.wires.add([Pf.call(a, -e / 2.0, yy), Pf.call(a, e / 2.0, yy)], {"width": 0.015, "color": "#9aa1a8"})
	add_yagi.call(yR + h - 0.1, 1.6, 9, 0.5)
	if r.f() < 0.5:
		add_yagi.call(yR + h - 0.7, 1.0, 5, 0.9)
	var top: Vector3 = RF.w(ax, yR + h - 0.5, 0)
	for ab in [[1.3, 0.9], [-1.3, 0.9], [0, -1.2]]:
		var q: Vector3 = RF.w(ax + ab[0], out.roofYE + (out.roofHz - absf(ab[1])) * out.roofP + 0.25, ab[1])
		ctx.wires.add([top, q], {"width": 0.008, "color": "#7d828b"})
	if r.f() < 0.35:
		var DF = RF.sub(ax, yR + 0.9, 0, H.dish_az - RF.ry)
		H.props.dish(DF, 0, 0, 0.1, 0)
