# plaza/signs.js: the plaza's sign, poster and board canvases. The port draws none of them (textured
# signs are blank), but the station-area map still places its shop labels from the layout's lots:
# a labelled lot that is missing fails the plaza here, as it does in the original.
extends RefCounted

## [name, width, height, key]
const SIGNS := [
	["map", 1024, 768, "plaza-map"], ["plazaGuide", 512, 384, "plaza-guide"], ["tourist", 1024, 768, "plaza-tourist"],
	["notice", 1024, 640, "plaza-notice"], ["noticeHeader", 512, 80, "plaza-notice-hdr"], ["busRound", 256, 256, "plaza-busround"],
	["busTable", 256, 448, "plaza-bustable"], ["shelterFascia", 1024, 96, "plaza-shelter-fascia"], ["shelterAd", 256, 512, "plaza-shelter-ad"],
	["routeMap", 512, 224, "plaza-routemap"], ["taxi", 256, 320, "plaza-taxi"], ["bikeSign", 512, 144, "plaza-bikesign"],
	["bikeNotice", 256, 320, "plaza-bikenotice"], ["slotNums", 512, 64, "plaza-slotnums"], ["monument", 512, 176, "plaza-monument"],
	["monumentPlate", 256, 112, "plaza-monument-plate"], ["postFront", 128, 160, "plaza-postfront"], ["postTimes", 128, 96, "plaza-posttimes"],
	["phoneSign", 256, 64, "plaza-phonesign"], ["phoneBook", 128, 96, "plaza-phonebook"], ["phoneNotice", 128, 128, "plaza-phonenotice"],
	["binBurn", 128, 128, "plaza-bin-burn"], ["binCan", 128, 128, "plaza-bin-can"], ["binPet", 128, 128, "plaza-bin-pet"],
	["clock", 256, 256, "plaza-clock"], ["clockPlate", 256, 64, "plaza-clockplate"], ["manhole", 256, 256, "plaza-manhole"],
	["grate", 128, 128, "plaza-grate"],
]

## The shops the map board labels at their lots (signs.js shopLabel).
const MAP_SHOPS := ["W1", "W2", "W4", "E1", "E2", "E3"]


## {name: texture, ..., mapLabels: [{id, x, z}]}, or {error: message} when a labelled lot is missing.
static func make_signs(ctx, _tx: Dictionary) -> Dictionary:
	var L = ctx.L
	var labels := []
	for id in MAP_SHOPS:
		var lot = L.lot_by_id(id)
		if lot == null:
			return {"error": "plaza map board: no lot %s for its shop label (signs.js shopLabel)" % id}
		labels.append({"id": id, "x": -11.8 if lot.side < 0 else 11.8, "z": (lot.z0 + lot.z1) / 2.0})
	var S := {}
	for s in SIGNS:
		S[s[0]] = ctx.tex.draw(s[1], s[2], null, {"key": s[3]})
	S["mapLabels"] = labels
	return S
