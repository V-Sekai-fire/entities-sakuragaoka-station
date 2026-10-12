// petals-soft: the few very close, defocused petals (FALL_* with SOFT): blended, no depth write.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never;
#define SOFT
#include "res://addons/sakuragaoka_station/world/petals/fall.gdshaderinc"
