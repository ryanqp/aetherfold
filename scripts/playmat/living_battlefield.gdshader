// =============================================================================
//  LIVING BATTLEFIELD — brings a painted playmat to life (a "cinemagraph")
//  Godot 4.x  ·  canvas_item
//
//  The painting stays the star: every effect moves or lights the real pixels
//  instead of drawing over them, so the art keeps its full detail.
//    water   → flowing ripples, sun glints, shimmer          (mask R)
//    hot     → lava/fire/torch glow that breathes & flickers, heat haze (mask G)
//    foliage → leaves sway in gusts, dappled light moves      (mask B)
//    sky     → slow cloud drift                               (mask A)
//    whole scene → drifting cloud shadows, fog banks, god rays, lightning,
//                  two particle systems (embers, snow, fireflies, motes, spores…)
//  Masks come from ArtMasks (detected from the painting itself).
//  Changing identity dissolves painting A into painting B along a glowing edge.
// =============================================================================
shader_type canvas_item;
render_mode unshaded;

group_uniforms Art;
uniform sampler2D art_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_a : filter_linear_mipmap, repeat_disable;
uniform sampler2D art_b : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_b : filter_linear_mipmap, repeat_disable;
uniform float aspect_a = 1.5;            // image width / height
uniform float aspect_b = 1.5;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0; // 0 = A, 1 = B
uniform vec4 dissolve_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);

group_uniforms Framing;
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform float fit : hint_range(0.0, 1.0) = 1.0;  // 0 = stretch whole image, 1 = cover (crop, no distortion)
uniform vec2 focus = vec2(0.5, 0.5);              // which part stays in view when cropping
uniform int orient : hint_range(0, 2) = 0;        // 0 normal, 1 mirrored, 2 rotated 180° (the rival's side)
uniform float drift : hint_range(0.0, 1.0) = 0.35; // slow "breathing" camera push-in/pan

group_uniforms Effects;
uniform float anim_time = 0.0;
uniform float water_amount : hint_range(0.0, 1.5) = 0.6;
uniform vec2 water_flow = vec2(0.02, 0.01);
uniform float hot_amount : hint_range(0.0, 1.5) = 0.5;
uniform vec4 hot_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float heat_haze : hint_range(0.0, 1.5) = 0.3;
uniform float foliage_amount : hint_range(0.0, 1.5) = 0.5;
uniform float sky_amount : hint_range(0.0, 1.5) = 0.0;
uniform float cloud_shadow : hint_range(0.0, 1.0) = 0.4;
uniform vec2 wind = vec2(1.0, 0.25);
uniform float fog_amount : hint_range(0.0, 1.0) = 0.2;
uniform vec4 fog_color : source_color = vec4(0.85, 0.88, 0.92, 1.0);
uniform float rays_amount : hint_range(0.0, 1.5) = 0.0;
uniform vec4 ray_color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float ray_angle = -0.6;                  // radians; light falls along this direction
uniform float lightning : hint_range(0.0, 1.0) = 0.0;
uniform float breath : hint_range(0.0, 1.0) = 0.3; // gentle overall light swell

group_uniforms Particles;
uniform float p1_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 p1_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float p1_speed = 0.08;   // + rises, - falls
uniform float p1_size = 0.1;
uniform float p1_wobble = 0.3;
uniform float p1_hot_bias : hint_range(0.0, 1.0) = 0.0; // gather near lava/fire
uniform float p2_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 p2_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float p2_speed = 0.015;
uniform float p2_size = 0.14;
uniform float p2_wobble = 0.6;

group_uniforms Finish;
uniform float brightness : hint_range(0.2, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.05;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 pulse_color : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

// ---------------------------------------------------------------- noise ----
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash11(i), hash11(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm3(vec2 p) {
	float v = 0.5 * noise2(p);
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 7.1;
	v += 0.25 * noise2(p);
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 3.7;
	v += 0.125 * noise2(p);
	return v / 0.875;
}

// Screen UV → image UV for an image of the given aspect (cover / stretch blend + slow camera drift).
vec2 image_uv(vec2 uv, float img_aspect, float t) {
	float ar = rect_size.x / max(rect_size.y, 1.0);
	vec2 vis = vec2(1.0);
	if (ar > img_aspect) {
		vis.y = mix(1.0, img_aspect / ar, fit);
	} else {
		vis.x = mix(1.0, ar / img_aspect, fit);
	}
	// breathing camera: zoom in up to 3% and pan a little, very slowly
	float z = 1.0 - drift * 0.03 * (0.5 + 0.5 * sin(t * 0.05));
	vis *= z;
	vec2 pan = drift * 0.012 * vec2(sin(t * 0.031), cos(t * 0.043));
	vec2 c = clamp(focus + pan, vis * 0.5, 1.0 - vis * 0.5);
	return c + (uv - 0.5) * vis;
}

// One painting brought to life. m returns its mask (for the global effects).
vec3 living(sampler2D art, sampler2D mask, vec2 iuv, float t, out vec4 m) {
	m = texture(mask, iuv);
	vec4 mb = textureLod(mask, iuv, 2.5);   // blurred mask: glows and haze spill past the edges
	vec2 d = vec2(0.0);

	// water: two layers of flowing ripples displace the painting
	if (water_amount > 0.001) {
		vec2 wp = iuv * vec2(30.0, 44.0) - water_flow * t * 30.0;
		vec2 ripple = vec2(noise2(wp + vec2(t * 0.35, 0.0)), noise2(wp * 1.3 + vec2(3.1, -t * 0.3))) - 0.5;
		d += ripple * 0.0045 * m.r * water_amount;
	}
	// foliage: leaves sway together in gusts
	if (foliage_amount > 0.001) {
		float gust = 0.5 + 0.5 * noise1(t * 0.35 + iuv.x * 2.0);
		d.x += sin(t * 1.7 + iuv.y * 38.0 + iuv.x * 11.0) * 0.0011 * m.b * foliage_amount * (0.4 + gust);
		d.y += cos(t * 1.3 + iuv.x * 31.0) * 0.0006 * m.b * foliage_amount * gust;
	}
	// heat haze shimmers above lava and fire
	if (heat_haze > 0.001) {
		vec2 hp = iuv * vec2(40.0, 25.0) + vec2(0.0, -t * 1.2);
		d += (vec2(noise2(hp), noise2(hp + 9.7)) - 0.5) * 0.004 * mb.g * heat_haze;
	}
	// sky: clouds drift
	if (sky_amount > 0.001) {
		d.x += (noise2(iuv * vec2(4.0, 8.0) + vec2(t * 0.03, 0.0)) - 0.5) * 0.008 * m.a * sky_amount;
	}

	vec3 c = texture(art, iuv + d).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));

	if (water_amount > 0.001) {
		// moving light on the water and sparkling glints on the brighter ripples
		float shim = noise2(iuv * vec2(9.0, 14.0) - water_flow * t * 9.0 + vec2(t * 0.12, 0.0)) - 0.5;
		c *= 1.0 + shim * 0.16 * m.r * water_amount;
		// glints: sparse, soft points of light that flash briefly as the ripples catch the sun
		vec2 gp = iuv * vec2(150.0, 100.0) - water_flow * t * 50.0;
		vec2 gcell = floor(gp);
		vec2 gh = hash22(gcell + 13.0);
		if (gh.x < 0.22) {
			vec2 gc = vec2(0.25 + 0.5 * gh.y, 0.25 + 0.5 * fract(gh.x * 17.3));
			float gd = length((fract(gp) - gc) * vec2(1.0, 1.5));
			float flashg = pow(max(0.0, sin(t * (1.2 + gh.y * 2.5) + gh.x * 40.0)), 12.0);
			float glint = smoothstep(0.2, 0.0, gd) * flashg * smoothstep(0.1, 0.55, lum + 0.15);
			c += vec3(1.0, 0.98, 0.92) * glint * 0.9 * m.r * water_amount;
		}
	}
	if (hot_amount > 0.001) {
		// lava breathes and flows, torches flicker, light spills onto nearby ground
		float flow = noise2(iuv * 14.0 + vec2(0.0, -t * 0.35));
		float flick = 0.7 + 0.3 * noise1(t * 9.0 + iuv.x * 50.0 + iuv.y * 31.0);
		float pulse = (0.55 + 0.6 * flow) * flick;
		c *= 1.0 + m.g * hot_amount * (pulse - 0.55) * 1.1;
		c += hot_color.rgb * mb.g * hot_amount * 0.22 * (0.75 + 0.25 * sin(t * 1.7 + iuv.x * 6.0)) * flick;
	}
	if (foliage_amount > 0.001) {
		float dap = noise2(iuv * 7.0 + vec2(t * 0.06, t * 0.02)) - 0.5;
		c *= 1.0 + dap * 0.14 * m.b * foliage_amount;
	}
	return c;
}

float particles(vec2 p, float t, float speed, float density, float size, float wobble, float salt) {
	float acc = 0.0;
	for (int l = 0; l < 2; l++) {
		float fl = float(l);
		float sc = 9.0 + fl * 7.0;
		vec2 gp = p * sc + vec2(sin(t * 0.25 + fl * 2.0) * wobble, -t * speed * sc * (0.75 + fl * 0.35));
		vec2 cell = floor(gp);
		vec2 f = fract(gp);
		vec2 h = hash22(cell + salt + fl * 17.0);
		if (h.x < density) {
			vec2 c = vec2(0.2 + 0.6 * h.y, 0.2 + 0.6 * fract(h.x * 13.7));
			c += 0.15 * wobble * vec2(sin(t * 1.1 + h.y * 30.0), cos(t * 0.9 + h.x * 20.0));
			float tw = 0.55 + 0.45 * sin(t * (1.5 + h.y * 3.0) + h.x * 50.0);
			float r = length(f - c);
			acc += (smoothstep(size * (1.0 - fl * 0.3), 0.0, r) + smoothstep(size * 3.0, 0.0, r) * 0.25) * tw;
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = UV;
	if (orient == 1) {
		uv.x = 1.0 - uv.x;
	} else if (orient == 2) {
		uv = vec2(1.0) - uv;
	}
	float t = anim_time;
	float ar = rect_size.x / max(rect_size.y, 1.0);

	// --- the painting(s) -----------------------------------------------------
	vec2 iuv_a = image_uv(uv, aspect_a, t);
	vec4 m;
	vec3 col = living(art_a, mask_a, iuv_a, t, m);
	float edge_glow = 0.0;
	if (dissolve > 0.001) {
		vec2 iuv_b = image_uv(uv, aspect_b, t);
		vec4 mb;
		vec3 col_b = living(art_b, mask_b, iuv_b, t, mb);
		// a soft, cloudy wave that spreads out from the middle of the mat
		vec2 cq = (uv - 0.5) * vec2(ar, 1.0);
		float n = length(cq) / (0.5 * length(vec2(ar, 1.0))) * 0.65 + fbm3(cq * 2.2 + 3.0) * 0.35;
		float edge = dissolve * 1.3 - 0.15;
		float w = smoothstep(edge + 0.07, edge - 0.07, n);
		col = mix(col, col_b, w);
		m = mix(m, mb, w);
		edge_glow = exp(-abs(n - edge) * 22.0) * sin(PI * clamp(dissolve, 0.0, 1.0)) * 0.55;
	}

	// --- light & weather over the whole scene ---------------------------------
	vec2 sp = uv * vec2(ar, 1.0);   // aspect-correct screen space (height = 1)
	if (cloud_shadow > 0.001) {
		float cs = fbm3(sp * 1.1 - wind * t * 0.018);
		col *= 1.0 - cloud_shadow * 0.32 * smoothstep(0.48, 0.75, cs);
	}
	if (rays_amount > 0.001) {
		vec2 dir = vec2(cos(ray_angle), sin(ray_angle));
		float across = dot(sp, vec2(-dir.y, dir.x));
		float along = dot(sp, dir);
		float beams = noise1(across * 7.0 + t * 0.04) * noise1(across * 17.0 - t * 0.025 + 4.0);
		beams = smoothstep(0.15, 0.55, beams) * (0.6 + 0.4 * sin(t * 0.3 + across * 3.0));
		col += ray_color.rgb * beams * rays_amount * 0.16 * smoothstep(-0.2, 0.8, 1.0 - along * 0.5);
	}
	if (fog_amount > 0.001) {
		float f = fbm3(sp * vec2(1.4, 2.2) - wind * t * 0.03);
		float bank = f * (0.55 + 0.45 * smoothstep(0.2, 0.75, length(UV - 0.5) * 1.4));
		col = mix(col, fog_color.rgb, clamp(fog_amount * smoothstep(0.35, 0.85, bank) * 0.75, 0.0, 0.7));
	}
	float flash = 0.0;
	if (lightning > 0.001) {
		float slot = floor(t * 0.4);
		float ph = fract(t * 0.4);
		float hit = step(hash11(slot * 3.1 + 0.5), lightning * 0.35);
		flash = hit * smoothstep(0.0, 0.01, ph) * (1.0 - smoothstep(0.02, 0.1, ph)) * (0.6 + 0.4 * step(0.5, fract(ph * 50.0)));
		col = mix(col, col * 1.6 + vec3(0.15, 0.17, 0.25), flash * 0.6);
	}
	col *= 1.0 + breath * 0.04 * sin(t * 0.45);

	// --- particles ------------------------------------------------------------
	if (p1_amount > 0.001) {
		float bias = mix(1.0, 0.25 + 1.5 * textureLod(mask_a, iuv_a, 4.0).g, p1_hot_bias);
		col += p1_color.rgb * particles(sp, t, p1_speed, p1_amount * 0.3, p1_size, p1_wobble, 1.0) * bias;
	}
	if (p2_amount > 0.001) {
		col += p2_color.rgb * particles(sp + 5.3, t, p2_speed, p2_amount * 0.22, p2_size, p2_wobble, 7.0) * 0.75;
	}

	// --- transition edge, finish ------------------------------------------------
	col += dissolve_color.rgb * edge_glow * 1.2;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	col = mix(col, pulse_color.rgb, pulse_amount * 0.35 * (0.4 + 0.6 * smoothstep(0.0, 0.7, length(UV - 0.5))));
	float vig = length((UV - 0.5) * 2.0) / 1.41421;
	col *= 1.0 - vignette_strength * smoothstep(0.45, 1.0, vig);
	COLOR = vec4(max(col * brightness, vec3(0.0)), 1.0);
}
