# shopsB.js: traditional Showa-era shops on the main street (桜ヶ丘駅前商店街):
#   E2 和菓子処 桜月堂 (wagashi), E3 よろず屋 山田商店 (general store),
#   E5 らーめん 春風 (ramen), W6 サイクル丸山 (bicycle shop).
# Everything is built in lot-local frames (layout lotFrame); see world/shopsB/*.gd. The original's
# font preload only waits for web fonts before drawing its canvases, which the port does not draw.
extends RefCounted

const Common = preload("res://addons/sakuragaoka_station/world/shopsB/common.gd")
const Inst = preload("res://addons/sakuragaoka_station/world/shopsB/inst.gd")
const Optimize = preload("res://addons/sakuragaoka_station/world/shopsB/optimize.gd")
const Wagashi = preload("res://addons/sakuragaoka_station/world/shopsB/wagashi.gd")
#GENERAL
#RAMEN
#BIKE


## Returns null, or the error that stopped the build (as the original throws).
func build(ctx):
	var L = ctx.L
	var K = Common.new(ctx)
	K.I = Inst.new(ctx, K)
	Wagashi.build_wagashi(ctx, K, L.lot_by_id("E2"))
	#BUILDS
	K.I.finish()
	Optimize.consolidate(ctx, K, {})
	return null
