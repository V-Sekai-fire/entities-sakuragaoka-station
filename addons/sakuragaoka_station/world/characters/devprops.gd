# characters/devprops.js: DEV ONLY grey stand-ins for neighbours' props (bike, café board, vending
# machine, benches, wall) for isolated screenshots (?only=...,characters/devprops). The original
# builds them only when the page URL carries that parameter; the port has no URL, so like the
# original's real scene (no ?only= parameter) it builds nothing.
extends RefCounted


static func build(ctx) -> void:
	dev_props(ctx)


static func dev_props(_ctx) -> void:
	# typeof location === 'undefined' || !location.search: return
	return
