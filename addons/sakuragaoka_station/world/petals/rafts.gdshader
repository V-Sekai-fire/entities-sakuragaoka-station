// petals-rafts: petal rafts on the river from the 2x2 atlas (FLOAT_* with SHEET).
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, alpha_to_coverage;
#define SHEET
#include "res://addons/sakuragaoka_station/world/petals/float.gdshaderinc"
