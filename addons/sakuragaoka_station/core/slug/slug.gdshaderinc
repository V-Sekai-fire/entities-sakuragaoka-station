// Slug (Lengyel, "GPU-Centered Font Rendering Directly from Glyph Outlines", JCGT 2017) over a
// slughorn atlas loaded by core/slug/atlas.gd: per-pixel coverage of a shape's quadratic curves,
// counted along a horizontal and a vertical ray through the shape's bands, antialiased over one
// pixel from the coordinate's screen derivatives. Ported from slughorn/render.hpp
// (Sampler::renderSampleBanded) and its reference GLSL. A texture key is a run of layers,
// composited source-over in order; a layer is a solid colour or a gradient.
//
//   vec4 c = slug_texture(slug_key, slug_frame, slug_uv, slug_wrap, UV);  // premultiplied
//
// Stamp layers (FX-Map-style instancing, textures from core/slug/stamps.gd): a layer whose data
// texel 3.z is -2 (stamps.gd marks blend mode 100 so) is a run of affine instances of an ellipse, a
// rect or a curve shape, binned into a G x G grid over the key's UV; a pixel walks only its own
// cell's list (<= SLUG_STAMP_MAX), each instance a solid colour or a gradient fixed to it,
// composites source-over in paint order, and fades toward the
// cell's mean colour once the cell's stamps shrink under a pixel (slug_stamp_fade). Keys without
// stamp layers only pay the branch on texel 3.z, which every layer fetches anyway.

#define SLUG_INDIRECTION_SIZE 32
#define SLUG_LAYER_TEXELS 8
#define SLUG_DATA_WIDTH 1024

uniform sampler2D slug_curves : filter_nearest, repeat_disable;
uniform sampler2D slug_bands : filter_nearest, repeat_disable;
uniform sampler2D slug_data : filter_nearest, repeat_disable;
uniform int slug_tex_width = 512;
uniform ivec2 slug_key = ivec2(0, 0);                  // first layer, layer count
uniform vec4 slug_frame = vec4(1.0, -1.0, 0.0, 1.0);   // em = frame.zw + uv * frame.xy
uniform vec4 slug_uv = vec4(1.0, 1.0, 0.0, 0.0);       // texture repeat.xy, offset.zw
uniform bool slug_wrap = false;                         // repeat wrapping, else clamp to edge

#ifndef SLUG_NO_STAMPS
#ifndef SLUG_STAMP_MAX
#define SLUG_STAMP_MAX 32   // the contract's max instances per cell (a test may lower it)
#endif
#define SLUG_STAMP_WIDTH 1024
uniform sampler2D slug_stamps : filter_nearest, repeat_disable;       // RGBA32F, see stamps.gd
uniform sampler2D slug_stamp_cells : filter_nearest, repeat_disable;  // RG16UI as RGBA8, see stamps.gd
// Screen footprint (px) of a cell's largest stamp at which the cell is all mean colour (.x) and
// all stamps (.y); smoothstep between.
uniform vec2 slug_stamp_fade = vec2(0.75, 1.5);
#endif

vec4 slug_fetch_data(int i) {
	return texelFetch(slug_data, ivec2(i % SLUG_DATA_WIDTH, i / SLUG_DATA_WIDTH), 0);
}

// A band texel offset from a shape's block, wrapping onto the following rows as slughorn packs it.
ivec2 slug_loc(ivec2 base, int offset) {
	int x = base.x + offset;
	return ivec2(x % slug_tex_width, base.y + x / slug_tex_width);
}

// The RG16UI band texel, stored as RGBA8 bytes (little-endian pairs).
uvec2 slug_band(ivec2 loc) {
	uvec4 b = uvec4(round(texelFetch(slug_bands, loc, 0) * 255.0));
	return uvec2(b.r | (b.g << 8u), b.b | (b.a << 8u));
}

uint slug_root_code(float y1, float y2, float y3) {
	uint i1 = floatBitsToUint(y1) >> 31u;
	uint i2 = floatBitsToUint(y2) >> 30u;
	uint i3 = floatBitsToUint(y3) >> 29u;
	uint shift = (i2 & 2u) | (i1 & ~2u);
	shift = (i3 & 4u) | (shift & ~4u);
	return (11892u >> shift) & 257u;  // 0x2E74, 0x0101
}

vec2 slug_solve_horiz(vec4 p12, vec2 p3) {
	vec2 a = p12.xy - p12.zw * 2.0 + p3;
	vec2 b = p12.xy - p12.zw;
	float t1;
	float t2;
	if (abs(a.y) < 1.0 / 65536.0) {
		t1 = abs(b.y) >= 1.0 / 65536.0 ? p12.y * (0.5 / b.y) : 0.0;
		t2 = t1;
	} else {
		float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
		t1 = (b.y - d) / a.y;
		t2 = (b.y + d) / a.y;
	}
	return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

vec2 slug_solve_vert(vec4 p12, vec2 p3) {
	vec2 a = p12.xy - p12.zw * 2.0 + p3;
	vec2 b = p12.xy - p12.zw;
	float t1;
	float t2;
	if (abs(a.x) < 1.0 / 65536.0) {
		t1 = abs(b.x) >= 1.0 / 65536.0 ? p12.x * (0.5 / b.x) : 0.0;
		t2 = t1;
	} else {
		float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
		t1 = (b.x - d) / a.x;
		t2 = (b.x + d) / a.x;
	}
	return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

// Coverage of one shape at em-space point rc, ppe pixels per em along x and y.
// shape: bandTexX, bandTexY, bandMaxX, bandMaxY; xf: bandScaleX, bandScaleY, bandOffsetX, bandOffsetY.
float slug_coverage(vec2 rc, vec2 ppe, ivec4 shape, vec4 xf) {
	ivec2 glyph = shape.xy;
	int qy = clamp(int(rc.y * xf.y + xf.w), 0, SLUG_INDIRECTION_SIZE - 1);
	int qx = clamp(int(rc.x * xf.x + xf.z), 0, SLUG_INDIRECTION_SIZE - 1);
	int band_y = int(slug_band(slug_loc(glyph, qy)).x);
	int band_x = int(slug_band(slug_loc(glyph, SLUG_INDIRECTION_SIZE + qx)).x);

	float xcov = 0.0;
	float xwgt = 0.0;
	uvec2 hb = slug_band(slug_loc(glyph, 2 * SLUG_INDIRECTION_SIZE + band_y));
	for (int ci = 0; ci < int(hb.x); ci++) {
		ivec2 cl = ivec2(slug_band(slug_loc(glyph, int(hb.y) + ci)));
		int c0 = cl.y * slug_tex_width + cl.x;
		vec4 p12 = texelFetch(slug_curves, cl, 0) - vec4(rc, rc);
		vec2 p3 = texelFetch(slug_curves, ivec2((c0 + 1) % slug_tex_width, (c0 + 1) / slug_tex_width), 0).xy - rc;
		if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) {
			break;
		}
		uint code = slug_root_code(p12.y, p12.w, p3.y);
		if (code != 0u) {
			vec2 r = slug_solve_horiz(p12, p3) * ppe.x;
			if ((code & 1u) != 0u) {
				xcov += clamp(r.x + 0.5, 0.0, 1.0);
				xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
			}
			if (code > 1u) {
				xcov -= clamp(r.y + 0.5, 0.0, 1.0);
				xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
			}
		}
	}

	float ycov = 0.0;
	float ywgt = 0.0;
	uvec2 vb = slug_band(slug_loc(glyph, 2 * SLUG_INDIRECTION_SIZE + shape.w + 1 + band_x));
	for (int ci = 0; ci < int(vb.x); ci++) {
		ivec2 cl = ivec2(slug_band(slug_loc(glyph, int(vb.y) + ci)));
		int c0 = cl.y * slug_tex_width + cl.x;
		vec4 p12 = texelFetch(slug_curves, cl, 0) - vec4(rc, rc);
		vec2 p3 = texelFetch(slug_curves, ivec2((c0 + 1) % slug_tex_width, (c0 + 1) / slug_tex_width), 0).xy - rc;
		if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) {
			break;
		}
		uint code = slug_root_code(p12.x, p12.z, p3.x);
		if (code != 0u) {
			vec2 r = slug_solve_vert(p12, p3) * ppe.y;
			if ((code & 1u) != 0u) {
				ycov -= clamp(r.x + 0.5, 0.0, 1.0);
				ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
			}
			if (code > 1u) {
				ycov += clamp(r.y + 0.5, 0.0, 1.0);
				ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
			}
		}
	}

	float weighted = abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0);
	return clamp(max(weighted, min(abs(xcov), abs(ycov))), 0.0, 1.0);
}

// A layer's gradient colour at shape-em point p, as slughorn's GradientInfo defines it.
vec4 slug_gradient(vec2 p, float type, vec4 m, vec4 m2, int first, int count) {
	float t;
	vec2 c = m2.xy;
	if (type < 0.5) {
		t = m.x * p.x + m.z * p.y + m2.x;                       // xx * x + xy * y + dx
	} else if (type < 1.5) {
		t = (length(p - c) - m2.z) / max(m.x - m2.z, 1e-12);    // outer radius in xx
	} else if (type < 2.5) {
		t = (atan(p.y - c.y, p.x - c.x) - m.x) / (abs(m.z) > 1e-12 ? m.z : 1e-12);  // start xx, span xy
	} else {
		vec2 d = p - c;
		t = length(vec2(m.x * d.x + m.z * d.y, m.y * d.x + m.w * d.y)) - m2.z;
	}
	t = clamp(t, 0.0, 1.0);
	vec4 prev = slug_fetch_data(first + 1);
	float pt = slug_fetch_data(first).x;
	if (t <= pt) {
		return prev;
	}
	for (int i = 1; i < count; i++) {
		float st = slug_fetch_data(first + 2 * i).x;
		vec4 sc = slug_fetch_data(first + 2 * i + 1);
		if (t <= st) {
			return mix(prev, sc, st - pt > 1e-9 ? (t - pt) / (st - pt) : 0.0);
		}
		prev = sc;
		pt = st;
	}
	return prev;
}

#ifndef SLUG_NO_STAMPS
vec4 slug_fetch_stamp(int i) {
	return texelFetch(slug_stamps, ivec2(i % SLUG_STAMP_WIDTH, i / SLUG_STAMP_WIDTH), 0);
}

// One texel of the cell texture as its two 16-bit fields. The encoding lives here and in
// stamps.gd's encode_cells(): RG16UI bytes stored as RGBA8 (little-endian pairs), as slug_band.
uvec2 slug_stamp_cell(int i) {
	uvec4 b = uvec4(round(texelFetch(slug_stamp_cells, ivec2(i % SLUG_STAMP_WIDTH, i / SLUG_STAMP_WIDTH), 0) * 255.0));
	return uvec2(b.r | (b.g << 8u), b.b | (b.a << 8u));
}

// Stamp layer si at canvas-em point em (texture UV w for the grid), dx / dy the em derivatives
// per screen pixel. Premultiplied, over transparent.
vec4 slug_stamp_layer(int si, vec2 em, vec2 w, vec2 dx, vec2 dy) {
	vec4 h0 = slug_fetch_stamp(2 * si);       // G, cell block texel, first instance texel, count
	vec4 h1 = slug_fetch_stamp(2 * si + 1);   // max per cell, mean block texel
	int g = int(h0.x);
	ivec2 c = clamp(ivec2(floor(w * float(g))), ivec2(0), ivec2(g - 1));
	int cell = c.y * g + c.x;
	int base = int(h0.y);
	uvec2 hdr = slug_stamp_cell(base + cell);  // list start (u16 element, from the block), count
	int n = min(int(hdr.y), SLUG_STAMP_MAX);
	int e0 = 2 * base + int(hdr.x);
	int first = int(h0.z);
	vec4 acc = vec4(0.0);
	float fmax = 0.0;
	for (int k = 0; k < SLUG_STAMP_MAX; k++) {
		if (k >= n) {
			break;
		}
		int e = e0 + k;
		uvec2 pr = slug_stamp_cell(e >> 1);
		int t = first + 3 * int((e & 1) == 0 ? pr.x : pr.y);
		vec4 m0 = slug_fetch_stamp(t);       // inverse affine a, b, c, d
		vec4 m1 = slug_fetch_stamp(t + 1);   // e, f, shape (-2 rect, -1 ellipse, else curve layer), paint
		mat2 m = mat2(m0.xy, m0.zw);         // q = (a x + c y + e, b x + d y + f)
		vec2 q = m * em + m1.xy;
		vec2 qx = m * dx;
		vec2 qy = m * dy;
		vec2 l = max(sqrt(qx * qx + qy * qy), vec2(1e-9));  // |grad q.x|, |grad q.y| per pixel
		float cov;
		float fp;
		if (m1.z < -1.5) {
			// rect 0..1: a one-pixel box filter per axis
			vec2 lo = clamp(q / l + 0.5, 0.0, 1.0);
			vec2 hi = clamp((q - 1.0) / l + 0.5, 0.0, 1.0);
			cov = (lo.x - hi.x) * (lo.y - hi.y);
			fp = max(1.0 / l.x, 1.0 / l.y);
		} else if (m1.z < -0.5) {
			// unit circle: |q| - 1 over its screen gradient
			float r = length(q);
			vec2 nrm = q / max(r, 1e-9);
			float gl = max(length(vec2(dot(nrm, qx), dot(nrm, qy))), 1e-9);
			cov = clamp(0.5 - (r - 1.0) / gl, 0.0, 1.0);
			fp = max(2.0 / l.x, 2.0 / l.y);
		} else {
			// a curve shape: layer m1.z's shape, q in that layer's canvas em
			int b = int(m1.z) * SLUG_LAYER_TEXELS;
			vec2 p = q - slug_fetch_data(b + 3).xy;
			vec4 bounds = slug_fetch_data(b + 7);
			vec2 qe = abs(qx) + abs(qy);
			fp = max((bounds.z - bounds.x) / l.x, (bounds.w - bounds.y) / l.y);
			cov = 0.0;
			if (all(greaterThanEqual(p, bounds.xy - qe)) && all(lessThanEqual(p, bounds.zw + qe))) {
				cov = slug_coverage(p, 1.0 / max(qe, vec2(1e-9)), ivec4(slug_fetch_data(b)), slug_fetch_data(b + 1));
			}
		}
		fmax = max(fmax, fp);
		if (cov <= 0.0) {
			continue;
		}
		vec4 col = slug_fetch_stamp(t + 2);
		if (m1.w >= 0.0) {
			// a gradient paint (stamps.gd record: matrix, dx dy inner count, type first-stop), fixed to
			// the instance: evaluated at the prototype-frame point, times the instance colour
			int gi = int(m1.w);
			vec4 g1 = slug_fetch_stamp(gi + 1);
			vec4 g2 = slug_fetch_stamp(gi + 2);
			col *= slug_gradient(q, g2.x, slug_fetch_stamp(gi), g1, int(g2.y), int(g1.w));
		}
		float a = col.a * cov;
		acc = vec4(col.rgb * a, a) + acc * (1.0 - a);
	}
	float keep = smoothstep(slug_stamp_fade.x, slug_stamp_fade.y, fmax);
	if (keep < 1.0) {
		int mi = int(h1.y) + cell;
		vec4 mean = texelFetch(slug_stamp_cells, ivec2(mi % SLUG_STAMP_WIDTH, mi / SLUG_STAMP_WIDTH), 0);
		acc = mix(mean, acc, keep);
	}
	return acc;
}
#endif

// A key's layers composited source-over at canvas-em point em; premultiplied RGBA. w: the texture
// UV after wrapping (the stamp grid's coordinate); dx, dy: em per screen pixel along x and y.
vec4 slug_layers(ivec2 key, vec2 em, vec2 w, vec2 dx, vec2 dy) {
	vec4 acc = vec4(0.0);
	vec2 ppe = 1.0 / max(abs(dx) + abs(dy), vec2(1e-9));
	vec2 margin = 1.0 / max(ppe, vec2(1e-6));
	for (int l = 0; l < key.y; l++) {
		int b = (key.x + l) * SLUG_LAYER_TEXELS;
		vec4 d3 = slug_fetch_data(b + 3);
		vec2 p = em - d3.xy;
#ifndef SLUG_NO_STAMPS
		if (d3.z < -1.5) {
			vec4 s = slug_stamp_layer(int(d3.w), p, w, dx, dy);
			acc = s + acc * (1.0 - s.a);
			continue;
		}
#endif
		vec4 bounds = slug_fetch_data(b + 7);
		if (any(lessThan(p, bounds.xy - margin)) || any(greaterThan(p, bounds.zw + margin))) {
			continue;
		}
		float cov = slug_coverage(p, ppe, ivec4(slug_fetch_data(b)), slug_fetch_data(b + 1));
		if (cov <= 0.0) {
			continue;
		}
		vec4 col = slug_fetch_data(b + 2);
		if (d3.z > -0.5) {
			vec4 m2 = slug_fetch_data(b + 5);
			vec4 g = slug_gradient(p, d3.z, slug_fetch_data(b + 4), m2, int(d3.w), int(m2.w));
			col = vec4(g.rgb, g.a * col.a);
		}
		float a = col.a * cov;
		acc = vec4(col.rgb * a, a) + acc * (1.0 - a);
	}
	return acc;
}

// A texture key sampled at a mesh UV (three.js convention), through the texture's repeat/offset.
// Derivatives come from the unwrapped coordinate so a repeat seam does not blur.
vec4 slug_texture(ivec2 key, vec4 frame, vec4 uvx, bool wrap, vec2 uv) {
	vec2 tuv = uv * uvx.xy + uvx.zw;
	vec2 e = tuv * frame.xy;
	vec2 w = wrap ? fract(tuv) : clamp(tuv, 0.0, 1.0);
	return slug_layers(key, frame.zw + w * frame.xy, w, dFdx(e), dFdy(e));
}

// Premultiplied to straight colour, as a canvas texture stores it.
vec4 slug_unpremultiply(vec4 c) {
	return c.a > 1e-5 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);
}
