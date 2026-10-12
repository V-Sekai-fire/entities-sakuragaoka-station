# trains/people.js: simple anime-proportioned figures for inside the trains (seen through tinted
# glass -> silhouettes). Built from rounded boxes / spheres into a Buckets key. Local frame:
# origin = seat point (sit) or floor point (stand), facing local +Z.
extends RefCounted

const Builder = preload("res://addons/sakuragaoka_station/world/trains/builder.gd")

const OUTFITS := {
	"sailor": {"top": "#3d4a6e", "bottom": "#3d4a6e", "collar": "#ecebe6", "ribbon": "#d9546a", "legs": "#2f2c38", "skirt": true},
	"blazer": {"top": "#4a5372", "bottom": "#5a5f6e", "collar": "#ecebe6", "ribbon": "#8a3a4a", "legs": "#2f2c38", "skirt": true},
	"gakuran": {"top": "#2f3140", "bottom": "#2f3140", "collar": "#2f3140", "legs": "#2f3140"},
	"suit": {"top": "#4b4e5a", "bottom": "#4b4e5a", "collar": "#e9e9ea", "ribbon": "#5a6f9a", "legs": "#4b4e5a"},
	"coat": {"top": "#b9a78a", "bottom": "#6d6a74", "collar": "#e8e0d0", "legs": "#6d6a74"},
	"cardigan": {"top": "#b8a3c4", "bottom": "#8e8a96", "collar": "#efe9e4", "legs": "#8e8a96", "skirt": true},
	"hoodie": {"top": "#8fa3b5", "bottom": "#4f5566", "collar": "#8fa3b5", "legs": "#4f5566"},
	"pinkKnit": {"top": "#e3a9b8", "bottom": "#d9cfc0", "collar": "#f1e6e0", "legs": "#6c6674", "skirt": true},
	"staff": {"top": "#2f3a5c", "bottom": "#2f3a5c", "collar": "#e9eaf0", "ribbon": "#c9a04a", "legs": "#2f3a5c", "cap": "#2f3a5c"},
}
const SKIN := ["#efd3c0", "#e9c9b2", "#f2dccb"]
const HAIR := ["#3a3240", "#4a3a36", "#5b4638", "#6b5a52", "#b8b2b8"]


## o: { pose:'sit'|'stand', h, outfit, hair, skin, style:'short'|'long'|'bob'|'pony',
## acc:'phone'|'book'|'bag'|'none', strap: bool, lookDown }.
static func person(B, key: String, pos: Array, rot_y: float, o: Dictionary = {}) -> void:
	var f: Dictionary = OUTFITS.get(o.get("outfit"), OUTFITS.coat) if o.get("outfit") != null else OUTFITS.coat
	var s: float = (o.get("h") if o.get("h") else 1.62) / 1.62
	var skin = o.get("skin") if o.get("skin") else SKIN[0]
	var hair = o.get("hair") if o.get("hair") else HAIR[0]
	var rbox := func(k: String, w: float, h: float, d: float, r: float, p: Array, c, rot = null) -> void:
		B.rbox(k, w, h, d, r, p, c, rot, 1)
	B.push(Builder.M(pos, [0, rot_y, 0]))
	var sit: bool = o.get("pose") == "sit"
	# --- lower body
	var hip_y: float
	var torso_y: float
	if sit:
		hip_y = 0.06 * s
		rbox.call(key, 0.34 * s, 0.15 * s, 0.34 * s, 0.05 * s, [0, hip_y, 0], f.bottom)
		for sx in [-1, 1]:
			rbox.call(key, 0.14 * s, 0.13 * s, 0.4 * s, 0.05 * s, [sx * 0.085 * s, 0.07 * s, 0.2 * s], f.bottom if f.get("skirt") else f.legs)
			rbox.call(key, 0.11 * s, 0.4 * s, 0.12 * s, 0.045 * s, [sx * 0.085 * s, -0.16 * s, 0.38 * s], f.legs)
			rbox.call(key, 0.1 * s, 0.07 * s, 0.2 * s, 0.03 * s, [sx * 0.085 * s, -0.4 * s, 0.44 * s], "#3a3346")
		torso_y = 0.38 * s
	else:
		hip_y = 0.86 * s
		for sx in [-1, 1]:
			rbox.call(key, 0.12 * s, 0.8 * s, 0.13 * s, 0.05 * s, [sx * 0.08 * s, 0.44 * s, 0], f.legs)
			rbox.call(key, 0.1 * s, 0.07 * s, 0.22 * s, 0.03 * s, [sx * 0.08 * s, 0.035 * s, 0.04 * s], "#3a3346")
		if f.get("skirt"):
			B.cyl(key, 0.17 * s, 0.24 * s, 0.34 * s, [0, 0.74 * s, 0], f.bottom, null, 10)
		else:
			rbox.call(key, 0.33 * s, 0.22 * s, 0.22 * s, 0.06 * s, [0, 0.84 * s, 0], f.bottom)
		torso_y = 1.18 * s
	# --- torso
	var lean := -0.08 if sit else 0.0
	rbox.call(key, 0.36 * s, 0.5 * s, 0.22 * s, 0.08 * s, [0, torso_y, -0.05 * s if sit else 0.0], f.top, [lean, 0, 0])
	if f.get("collar"):
		rbox.call(key, 0.3 * s, 0.05 * s, 0.24 * s, 0.02 * s, [0, torso_y + 0.24 * s, (-0.05 if sit else 0.0) * s], f.collar)
	if f.get("ribbon"):
		B.box(key, 0.08 * s, 0.1 * s, 0.03 * s, [0, torso_y + 0.16 * s, (0.06 if sit else 0.11) * s], f.ribbon)
	# --- head
	var hy := torso_y + 0.44 * s
	var hz := -0.06 * s if sit else 0.0
	var down := 0.03 if o.get("lookDown") else 0.0
	B.sphere(key, 0.105 * s, [0, hy - down, hz + down], skin, 8)
	B.sphere(key, 0.118 * s, [0, hy + 0.03 * s - down, hz - 0.02 * s], hair, 8, [1, 0.92, 1])
	var style = o.get("style") if o.get("style") else "short"
	if style == "long":
		rbox.call(key, 0.24 * s, 0.34 * s, 0.1 * s, 0.05 * s, [0, hy - 0.14 * s, hz - 0.08 * s], hair)
	if style == "bob":
		rbox.call(key, 0.25 * s, 0.16 * s, 0.2 * s, 0.07 * s, [0, hy - 0.05 * s, hz - 0.03 * s], hair)
	if style == "pony":
		B.sphere(key, 0.06 * s, [0, hy - 0.02 * s, hz - 0.15 * s], hair, 8)
	if f.get("cap"):
		B.cyl(key, 0.115 * s, 0.12 * s, 0.07 * s, [0, hy + 0.09 * s, hz], f.cap, null, 12)
		B.box(key, 0.16 * s, 0.015 * s, 0.09 * s, [0, hy + 0.06 * s, hz + 0.12 * s], "#2a2f40")
		B.box(key, 0.05 * s, 0.03 * s, 0.01 * s, [0, hy + 0.1 * s, hz + 0.118 * s], "#d9b54a")
	# --- arms
	var sh_y := torso_y + 0.2 * s
	for sx in [-1, 1]:
		var x: float = sx * 0.21 * s
		if not sit and o.get("strap") and sx == 1:
			rbox.call(key, 0.09 * s, 0.62 * s, 0.09 * s, 0.04 * s, [x + 0.02 * s, sh_y + 0.3 * s, 0.02 * s], f.top, [0, 0, -0.08 * sx])
			B.sphere(key, 0.045 * s, [x + 0.04 * s, sh_y + 0.63 * s, 0.02 * s], o.get("glove") if o.get("glove") else skin, 8)
		elif o.get("acc") == "phone" or o.get("acc") == "book" or o.get("hands"):
			rbox.call(key, 0.085 * s, 0.28 * s, 0.09 * s, 0.04 * s, [x, sh_y - 0.13 * s, (-0.02 if sit else 0.02) * s], f.top, [0.3, 0, 0])
			rbox.call(key, 0.08 * s, 0.08 * s, 0.26 * s, 0.035 * s, [x * 0.75, sh_y - 0.28 * s, 0.14 * s], f.top, [-0.35, 0, 0])
		else:
			rbox.call(key, 0.085 * s, 0.52 * s, 0.09 * s, 0.04 * s, [x, sh_y - 0.25 * s, 0.02 * s if sit else 0.0], f.top, [-0.5 if sit else 0.0, 0, 0.05 * sx])
	if o.get("acc") == "phone":
		B.box(key, 0.07 * s, 0.13 * s, 0.012 * s, [0, sh_y - 0.22 * s, 0.28 * s], "#3d4452", [-0.7, 0, 0])
	if o.get("acc") == "book":
		B.box(key, 0.2 * s, 0.14 * s, 0.03 * s, [0, sh_y - 0.24 * s, 0.27 * s], "#e9e3d6", [-0.8, 0, 0])
	if o.get("acc") == "bag":
		rbox.call(key, 0.32 * s, 0.22 * s, 0.12 * s, 0.04 * s, [0, 0.2 * s if sit else 0.9 * s, 0.3 * s if sit else 0.16 * s], o.get("bagColor") if o.get("bagColor") else "#4a4252")
	if o.get("acc") == "backpack":
		rbox.call(key, 0.3 * s, 0.38 * s, 0.16 * s, 0.06 * s, [0, torso_y, -0.18 * s], o.get("bagColor") if o.get("bagColor") else "#6a8aa8")
	B.pop()


static func pick_look(r) -> Dictionary:
	var outfits := ["sailor", "blazer", "gakuran", "suit", "coat", "cardigan", "hoodie", "pinkKnit"]
	var outfit: String = r.pick(outfits)
	var female: bool = ["sailor", "blazer", "cardigan", "pinkKnit"].has(outfit) or (outfit == "coat" and r.chance(0.6))
	var h: float = r.range(1.5, 1.62) if female else r.range(1.62, 1.76)
	var hair = HAIR[4] if outfit == "cardigan" and r.chance(0.6) else r.pick(HAIR.slice(0, 4))
	var skin = r.pick(SKIN)
	var style = r.pick(["long", "bob", "pony", "long"]) if female else "short"
	var acc = r.pick(["phone", "phone", "book", "bag", "none", "backpack"])
	var bag_color = r.pick(["#4a4252", "#8a5a4a", "#6a8aa8", "#c98a9a", "#5f7a5a"])
	return {"outfit": outfit, "h": h, "hair": hair, "skin": skin, "style": style, "acc": acc, "bagColor": bag_color}
