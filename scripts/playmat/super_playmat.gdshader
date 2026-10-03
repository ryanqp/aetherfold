// =============================================================================
//  SUPER PLAYMAT — procedural Magic: The Gathering color-identity playmat
//  Godot 4.x  ·  canvas_item  ·  no textures, no video
//
//  One shader renders all 32 color identities. The palette (5 color slots) and
//  a handful of "personality" layers are fed in by SuperPlaymat.gd:
//
//     White  → radiant light rays          Blue  → flowing caustic ripples
//     Black  → breathing void tendrils     Red   → rising embers
//     Green  → living vein network         Colorless → iridescent crystal shimmer
//
//  Changing identity cross-fades palette A → palette B with a radial
//  shockwave (driven by `transition`), then the script commits B into A.
// =============================================================================
shader_type canvas_item;
// (TAU, PI are Godot built-ins)
render_mode unshaded;

group_uniforms Palette;
uniform vec4 palette_a[5] : source_color;
uniform vec4 palette_b[5] : source_color;
uniform vec4 accent_a : source_color = vec4(1.0);
uniform vec4 accent_b : source_color = vec4(1.0);
uniform float transition : hint_range(0.0, 1.0) = 0.0;

group_uniforms Personality;
uniform float warp_strength : hint_range(0.0, 3.0) = 1.0;
uniform float ripple_amount : hint_range(0.0, 1.5) = 0.0;  // Blue
uniform float cell_amount : hint_range(0.0, 1.5) = 0.0;    // Green (+ Colorless facets)
uniform float ray_amount : hint_range(0.0, 1.5) = 0.0;     // White
uniform float ember_amount : hint_range(0.0, 1.5) = 0.0;   // Red
uniform float void_amount : hint_range(0.0, 1.5) = 0.0;    // Black
uniform float shimmer_amount : hint_range(0.0, 1.5) = 0.0; // Colorless

group_uniforms Layout;
uniform float anim_time = 0.0;                    // seconds, driven by script (pausable)
uniform vec2 rect_size = vec2(1920.0, 1080.0);    // node size, for aspect correction
uniform float pattern_scale : hint_range(0.5, 6.0) = 2.2;
uniform bool flip = false;                        // rotate 180° (opponent's half)
uniform float sigil_amount : hint_range(0.0, 1.0) = 0.35;
uniform float seam_glow : hint_range(0.0, 1.0) = 0.0; // glow along local top edge

group_uniforms Finish;
uniform int quality : hint_range(0, 2) = 2;       // 0 = 3 octaves … 2 = 5 octaves
uniform float brightness : hint_range(0.2, 2.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.02;
uniform vec4 pulse_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.0;
group_uniforms;


// ---------------------------------------------------------------- noise ----
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	int octaves = 3 + clamp(quality, 0, 2);
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		v += amp * vnoise(p);
		norm += amp;
		p = rot * p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v / norm;
}

// Distance to the nearest Voronoi edge (F2 - F1). Animated cell centers.
float voronoi_edge(vec2 x, float t) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			o = 0.5 + 0.4 * sin(t + TAU * o);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

// Sparse rising sparks, two parallax layers.
float embers(vec2 p, float t) {
	float acc = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float s = 9.0 + fl * 7.0;
		vec2 gp = p * s + vec2(0.0, t * (1.1 + fl * 0.5));
		vec2 cell = floor(gp);
		vec2 fc = fract(gp);
		vec2 h = hash22(cell + fl * 31.7);
		if (h.x > 0.78) {
			vec2 center = vec2(0.2 + 0.6 * h.y, 0.5 + 0.3 * sin(t * 1.5 + h.x * 40.0));
			float d = length(fc - center);
			float flick = 0.55 + 0.45 * sin(t * 6.0 + h.y * 60.0);
			acc += (1.0 - smoothstep(0.0, 0.12 - fl * 0.03, d)) * flick;
		}
	}
	return acc;
}

// ------------------------------------------------------------- palette ----
// Cyclic 5-stop gradient. use_b selects the incoming palette.
vec3 sample_palette(float t, bool use_b) {
	t = fract(t) * 5.0;
	int i0 = min(int(t), 4);
	int i1 = (i0 + 1) % 5;
	float f = smoothstep(0.0, 1.0, fract(t));
	vec3 c0 = use_b ? palette_b[i0].rgb : palette_a[i0].rgb;
	vec3 c1 = use_b ? palette_b[i1].rgb : palette_a[i1].rgb;
	return mix(c0, c1, f);
}

// ------------------------------------------------------------ fragment ----
void fragment() {
	vec2 uv = flip ? vec2(1.0) - UV : UV;
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);   // centered, height = 1 unit
	float t = anim_time;
	float r = length(p);

	// --- Domain-warped aether (3 fbm calls total) ---
	vec2 sp = p * pattern_scale;
	vec2 q = vec2(
		fbm(sp + vec2(0.0, t * 0.06)),
		fbm(sp + vec2(5.2, 1.3) - vec2(t * 0.045, 0.0))
	);
	float f = fbm(sp + warp_strength * 2.0 * q + vec2(t * 0.04, -t * 0.03));

	float band_t = f * 1.35 + q.x * 0.35 + t * 0.01;
	vec3 col_a = sample_palette(band_t, false);
	vec3 col_b = sample_palette(band_t, true);

	// --- Radial reveal for identity transitions ---
	float max_r = length(vec2(aspect, 1.0)) * 0.5;
	float front = transition * (max_r + 0.4) - 0.2;
	float rr = r + (q.y - 0.5) * 0.15;              // ragged, organic wavefront
	float reveal = 1.0 - smoothstep(front - 0.12, front, rr);
	float active = step(0.001, transition) * step(transition, 0.999);
	float wavefront = (1.0 - abs(reveal - 0.5) * 2.0) * active;

	vec3 base = mix(col_a, col_b, reveal);
	vec3 accent = mix(accent_a.rgb, accent_b.rgb, reveal);

	// --- Depth shading + glowing seams between color bands ---
	float depth = smoothstep(0.15, 0.85, f);
	vec3 col = base * mix(0.45, 1.15, depth);
	float bf = fract(band_t * 5.0);
	float boundary = 1.0 - smoothstep(0.0, 0.08, min(bf, 1.0 - bf));
	col += accent * boundary * 0.10;

	// --- Personality layers (each skipped entirely when its amount is 0) ---
	if (ripple_amount > 0.001) {          // BLUE: caustics
		float c = abs(sin((f + q.y * 0.5) * 18.0 + t * 0.9));
		c = pow(1.0 - c, 6.0);
		col += accent * c * ripple_amount * 0.35;
	}

	if (cell_amount > 0.001) {            // GREEN: living veins
		float e = voronoi_edge(sp * 1.6 + q * 1.2, t * 0.25);
		float vein = 1.0 - smoothstep(0.0, 0.08, e);
		col = mix(col, col * 0.55, vein * cell_amount * 0.6);
		col += accent * vein * cell_amount * 0.18 * depth;
	}

	if (ray_amount > 0.001) {             // WHITE: radiance
		float ang = atan(p.y, p.x);
		float wob = vnoise(vec2(cos(ang), sin(ang)) * 2.5 + t * 0.05) * 4.0;
		float rays = 0.5 + 0.5 * sin(ang * 14.0 + t * 0.08 + wob);
		rays = pow(rays, 3.0) * (1.0 - smoothstep(0.0, 0.9, r));
		col += accent * rays * ray_amount * 0.28;
		col += accent * (1.0 - smoothstep(0.0, 0.5, r)) * ray_amount * 0.12;
	}

	if (void_amount > 0.001) {            // BLACK: breathing void
		float v = 1.0 - smoothstep(0.15, 0.55, f + (q.x - 0.5) * 0.3);
		float breathe = 0.75 + 0.25 * sin(t * 0.5);
		col *= 1.0 - v * void_amount * 0.55 * breathe;
		float rim = v * (1.0 - v) * 4.0;  // faint glow on the void's edge
		col += accent * rim * void_amount * 0.08;
	}

	if (ember_amount > 0.001) {           // RED: rising embers + heat
		col += accent * embers(p, t) * ember_amount * 0.9;
		col += accent * smoothstep(0.1, 0.5, p.y) * ember_amount * 0.07;
	}

	if (shimmer_amount > 0.001) {         // COLORLESS: iridescence
		vec3 irid = 0.5 + 0.5 * cos(TAU * (f * 2.0 + q.x + vec3(0.0, 0.33, 0.67) + t * 0.02));
		float spec = pow(depth, 4.0);
		col = mix(col, col * 0.7 + irid * 0.4, shimmer_amount * spec * 0.35);
	}

	// --- Center sigil (anti-aliased rings, dashed inner ring slowly turning) ---
	if (sigil_amount > 0.001) {
		float aa = fwidth(r) * 1.5;
		float ring_r = 0.32;
		float ring = 1.0 - smoothstep(0.0, aa + 0.002, abs(r - ring_r));
		float ring2 = 1.0 - smoothstep(0.0, aa + 0.0015, abs(r - ring_r * 0.84));
		float ang = atan(p.y, p.x);
		float dashes = step(0.45, fract(ang * 36.0 / TAU + t * 0.01));
		col += accent * (ring + ring2 * dashes) * sigil_amount * 0.5;
	}

	// --- Seam glow (local top edge — the board's center line in split mode) ---
	if (seam_glow > 0.001) {
		float seam = exp(-uv.y * 18.0);
		col += accent * seam * seam_glow * (0.6 + 0.4 * sin(t * 1.2));
	}

	// --- Transition shockwave, gameplay pulse, finish ---
	col += accent * wavefront * 0.6;
	col = mix(col, pulse_color.rgb, pulse_amount * 0.35 * (0.4 + 0.6 * smoothstep(0.0, 0.7, r)));

	float vig = length((uv - 0.5) * 2.0) / 1.41421;
	col *= 1.0 - vignette_strength * smoothstep(0.4, 1.0, vig);
	col += (hash12(FRAGCOORD.xy + fract(t * 13.37) * 100.0) - 0.5) * grain_strength;

	COLOR = vec4(max(col * brightness, vec3(0.0)), 1.0);
}
