# The port's quality settings, mirroring the original's ?q= levels (src/main.js QUALITY, read by
# core/renderer.js for the colour pass's MSAA and by core/sky.js for the sun's shadow map):
#   level   msaa  shadow map  shadow box  pixel ratio      petals
#   high    4x    4096        +-75 m      min(dpr, 1.5)    1.0    (the original's desktop default)
#   medium  4x    2048        +-60 m      min(dpr, 1.0)    0.6    (its touch default)
#   low     off   2048        +-45 m      min(dpr, 0.75)   0.35
# Applied here: MSAA on the 3D viewport and the directional shadow map size (Godot's default 4096 is
# the original's high). Not applied: the shadow box (the original fits one +-S orthographic box in
# front of the camera, Godot splits its directional shadow over a distance, so the numbers do not
# carry over), the pixel ratio (shot mode, which every parity render uses, forces it to 1; at
# dpr 1 it is 1 for high and medium anyway) and petals (no petal module is ported yet).
# The slug_runtime setting joins these when it lands.
#   Quality.apply(get_viewport(), "high")
#   tools: --q=high|medium|low (realize_check, engine_floor)
extends RefCounted

const LEVELS := {
	"high": {"msaa": 4, "shadow_map": 4096, "shadow_size": 75.0, "pixel_ratio": 1.5, "petals": 1.0},
	"medium": {"msaa": 4, "shadow_map": 2048, "shadow_size": 60.0, "pixel_ratio": 1.0, "petals": 0.6},
	"low": {"msaa": 0, "shadow_map": 2048, "shadow_size": 45.0, "pixel_ratio": 0.75, "petals": 0.35},
}
const DEFAULT := "high"


static func level(name: String) -> Dictionary:
	return LEVELS.get(name, LEVELS[DEFAULT])


static func msaa_mode(samples: int) -> Viewport.MSAA:
	match samples:
		2:
			return Viewport.MSAA_2X
		4:
			return Viewport.MSAA_4X
		8:
			return Viewport.MSAA_8X
	return Viewport.MSAA_DISABLED


## Applies a level to the viewport the station renders in; returns the level's settings.
static func apply(vp: Viewport, name: String) -> Dictionary:
	var q := level(name)
	if vp != null:
		vp.msaa_3d = msaa_mode(int(q.msaa))
	RenderingServer.directional_shadow_atlas_set_size(int(q.shadow_map), true)
	return q
