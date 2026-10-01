extends SceneTree
func _initialize() -> void:
	var R = load("res://addons/sakuragaoka_station/core/rng.gd")
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tools/reference.json"))
	var ok := true
	for key in ref.rng:
		var r = R.make(int(key) if key == "1" else key)
		var got := []
		for i in 16: got.append(r.f())
		for i in 16:
			if roundi(got[i] * 4294967296.0) != roundi(float(ref.rng[key][i]) * 4294967296.0):
				ok = false
				print("MISMATCH ", key, " ", i, " ", got[i], " vs ", ref.rng[key][i])
	print("rng ok" if ok else "rng FAIL")
	quit()
