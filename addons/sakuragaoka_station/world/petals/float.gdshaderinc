// petals/shaders.js FLOAT_VERT / FLOAT_FRAG: petals floating on water (single petals, or SHEET =
// river rafts from a 2x2 atlas), drifting along their flow line. Per-instance data (see
// petals/shaders.gd node()): aA = INSTANCE_CUSTOM, aB = COLOR, aC = (MODEL_MATRIX[0].xyz,
// MODEL_MATRIX[2].x), aD = (MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].y). Sun shadow-map lookup not
// ported (petalShadow() = 1).

uniform float uTime; uniform float uResY; uniform float uFar; uniform vec3 uSunDir;
uniform vec3 uSunCol; uniform vec3 uSkyCol; uniform vec3 uGndCol;
uniform sampler2D uTex : source_color, filter_linear_mipmap, repeat_disable; uniform vec3 uColA; uniform vec3 uColB;
varying vec2 vUv; varying vec3 vN; varying vec3 vW; varying float vTint;

void vertex(){
	vec4 aA = INSTANCE_CUSTOM;
	vec4 aB = COLOR;
	vec4 aC = vec4(MODEL_MATRIX[0].xyz, MODEL_MATRIX[2].x);
	vec4 aD = vec4(MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].y);
	float s = mod(aC.w + aD.x * uTime, aB.w);
	vec3 dir = aB.xyz; vec2 nrm = normalize(vec2(-dir.z, dir.x) + vec2(1e-5, 0.0));
	vec3 P = aA.xyz + dir * s;
	P.xz += nrm * aD.y * sin(s * 0.05 + aD.z) + nrm * aD.y * 0.35 * sin(uTime * 0.11 + aA.w * 6.2831);
	float fl = min(2.0, aB.w * 0.15);
	float fade = smoothstep(0.0, fl, s) * (1.0 - smoothstep(aB.w - fl, aB.w, s));
	float yaw = aC.z + 0.25 * sin(uTime * 0.07 + aA.w * 6.2831) + s * 0.004 * (aA.w - 0.5);
	float cy = cos(yaw), sy = sin(yaw);
	vec3 lp = vec3(VERTEX.x * aC.x, VERTEX.y, VERTEX.z * aC.y) * fade;
	vec3 rp = vec3(cy*lp.x + sy*lp.z, lp.y, -sy*lp.x + cy*lp.z);
	P.y += 0.004 * sin(uTime * 0.9 + P.x * 0.6 + aA.w * 6.0);
	float cell = floor(aD.w);
	vTint = fract(aD.w);
#ifdef SHEET
	vUv = UV * 0.5 + vec2(mod(cell, 2.0), floor(cell / 2.0)) * 0.5;
#else
	vUv = UV;
#endif
	vec3 nrmW = normalize(vec3(0.06 * sin(aA.w * 40.0), 1.0, 0.06 * cos(aA.w * 31.0)));
	vec4 worldPosition = vec4(P + rp, 1.0);
	vW = worldPosition.xyz; vN = nrmW;
	vec4 mvPosition = VIEW_MATRIX * worldPosition;
	VERTEX = mvPosition.xyz;
	NORMAL = mat3(VIEW_MATRIX) * nrmW;
	if (fade < 0.01 || -mvPosition.z > uFar) { POSITION = vec4(0.0, 0.0, 2.0, 1.0); }
	else POSITION = PROJECTION_MATRIX * mvPosition;
}

float petalShadow(){ return 1.0; }
float toonBand(float ndl){ return ndl < 0.0 ? 0.0 : (ndl < 0.12 ? 0.42 : (ndl < 0.42 ? 0.8 : 1.0)); }

void fragment(){
	vec4 tx = texture(uTex, vUv);
	if (tx.a < 0.08) discard;
	vec3 alb = tx.rgb * mix(uColA, uColB, vTint) * 0.94;
	vec3 N = normalize(vN);
	float ndl = dot(N, uSunDir);
	float sh = petalShadow();
	vec3 amb = mix(uGndCol, uSkyCol, 0.5 + 0.5 * N.y) * (1.0 / PI);
	// petals on water catch sky light from everywhere: shade softens instead of going purple
	vec3 col = alb * (amb * 1.5 + uSunCol * (1.0 / PI) * mix(0.62, 1.0, sh) * toonBand(ndl));
	// wet, slightly cooler where it touches the water
	col = mix(col, col * vec3(0.9, 0.93, 1.02), 0.35 * (1.0 - tx.a));
	ALBEDO = col;
	ROUGHNESS = 0.7;  // the no-outline layer (core/composite.gd NO_OUTLINE_ROUGHNESS)
	ALPHA = tx.a;
	// the original's alpha to coverage takes the alpha as the covered share of each pixel; Godot's
	// alpha_to_coverage with a scissor writes alpha 1, so the share is drawn by alpha hashing
	ALPHA_HASH_SCALE = 1.0;
}
