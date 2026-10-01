# mulberry32, exactly as src/core/ctx.js: a string key is hashed FNV-1a style with Math.imul, so
# the same key gives the same stream in both. The world seed re-keys every stream as "<seed>:<key>";
# seed 1 keeps the original keys.
extends RefCounted

var _a := 0


static func make(key, seed: int = 1) -> RefCounted:
	var r = load("res://addons/sakuragaoka_station/core/rng.gd").new()
	if seed != 1:
		key = "%d:%s" % [seed, str(key)]
	r._a = to_i32(hash_key(key))
	return r


static func to_i32(x: int) -> int:
	x &= 0xFFFFFFFF
	return x - 0x100000000 if x >= 0x80000000 else x


static func imul(a: int, b: int) -> int:
	var bu := b & 0xFFFFFFFF
	var lo := (a & 0xFFFF) * bu
	var hi := (((a >> 16) & 0xFFFF) * bu) & 0xFFFF
	return to_i32(lo + (hi << 16))


static func hash_key(key) -> int:
	if key is String:
		var h := 2166136261
		for i in key.length():
			h = imul(to_i32(h) ^ key.unicode_at(i), 16777619) & 0xFFFFFFFF
		return h
	return int(key) & 0xFFFFFFFF


## The next value in [0, 1).
func f() -> float:
	_a = to_i32(_a + 0x6D2B79F5)
	var t := imul(_a ^ ((_a & 0xFFFFFFFF) >> 15), 1 | _a)
	t = to_i32(to_i32(t + imul(t ^ ((t & 0xFFFFFFFF) >> 7), 61 | t)) ^ t)
	return float((t ^ ((t & 0xFFFFFFFF) >> 14)) & 0xFFFFFFFF) / 4294967296.0


func range(lo: float, hi: float) -> float:
	return lo + (hi - lo) * f()


func rint(lo, hi) -> int:
	return floori(lo + (hi - lo + 1) * f())


func pick(arr):
	return arr[floori(f() * arr.size())]


func chance(p: float) -> bool:
	return f() < p
