shader_type canvas_item;

uniform float volume : hint_range(0.0, 1.0) = 0.0;
uniform int state = 0;
uniform float time_offset = 0.0;
uniform float speed = 1.0;
uniform float glow_intensity = 2.8;
uniform float tension : hint_range(0.0, 1.0) = 0.0;
uniform vec2 resolution = vec2(1920.0, 1080.0);

// --- Noise foundations ---
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(dot(hash2(i + vec2(0,0)), f - vec2(0,0)),
		    dot(hash2(i + vec2(1,0)), f - vec2(1,0)), u.x),
		mix(dot(hash2(i + vec2(0,1)), f - vec2(0,1)),
		    dot(hash2(i + vec2(1,1)), f - vec2(1,1)), u.x), u.y
	);
}

// 3-octave FBM for organic plasma texture
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2  s = vec2(1.0);
	for (int i = 0; i < 3; i++) {
		v += a * gnoise(p * s);
		s  *= 2.1;
		a  *= 0.48;
	}
	return v;
}

// Rotation matrix
mat2 rot(float a) {
	float c = cos(a); float s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

void fragment() {
	// Aspect-correct UV centered at 0,0
	float asp = resolution.x / resolution.y;
	vec2 uv = UV - 0.5;
	uv.x *= asp;

	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	float t = TIME * speed * 0.1 + time_offset;

	// --- Base breathing ---
	float breath  = sin(TIME * 0.35 + time_offset) * 0.5 + 0.5;
	float wobble1 = fbm(uv * 2.8 + vec2(t * 0.7, -t * 0.5)) * 0.07;
	float wobble2 = fbm(uv * 5.2 - vec2(t * 0.4, t * 0.6)) * 0.04;

	float base_r = 0.13 + breath * 0.018 + wobble1;

	// --- State-specific radius & color ---
	float core_r  = base_r;
	float mid_r   = base_r * 1.55;
	float outer_r = base_r * 2.4;

	// Color palette
	vec3 c_idle    = vec3(0.28, 0.04, 0.62);
	vec3 c_tense   = vec3(0.88, 0.06, 0.48);
	vec3 c_listen  = vec3(0.0,  0.78, 0.92);
	vec3 c_think   = vec3(0.04, 0.18, 0.86);
	vec3 c_speak   = vec3(1.0,  0.62, 0.08);
	vec3 c_outer   = vec3(0.18, 0.04, 0.32);

	vec3 core_col  = mix(c_idle, c_tense, tension);
	vec3 mid_col   = mix(c_outer, c_tense * 0.5, tension * 0.4);
	vec3 outer_col = c_outer;
	float mid_str  = 0.28;
	float outer_str = 0.14;

	if (state == 1) {
		// LISTENING — outer shell expands with voice, inner snaps to cyan
		float vb = volume;
		float speed_boost = 1.0 + tension * 2.5;
		float wl = fbm(uv * 3.0 + vec2(t * speed_boost, -t * speed_boost * 0.8)) * 0.12;
		core_r  = base_r + vb * 0.38 + wl;
		mid_r   = base_r * 1.6 + vb * 0.55;
		outer_r = base_r * 2.6 + vb * 0.75 + wobble2;

		core_col  = mix(mix(c_idle, c_tense, tension), c_listen, clamp(vb * 2.8, 0.0, 1.0));
		mid_col   = mix(c_outer, c_listen * 0.55, clamp(vb * 2.2, 0.0, 1.0));
		outer_col = mix(c_outer, c_listen * 0.2, clamp(vb * 1.4, 0.0, 1.0));
		mid_str   = 0.22;
		outer_str = 0.10;

	} else if (state == 2) {
		// THINKING — 6-lobe collapse-spin, shells tighten inward
		float spin = sin(angle * 6.0 + TIME * speed * 0.28) * 0.5 + 0.5;
		core_r  = base_r * 0.82 + spin * 0.035 + wobble1 * 0.6;
		mid_r   = base_r * 1.1 + spin * 0.02;
		outer_r = base_r * 1.5;

		core_col  = c_think;
		mid_col   = c_think * 0.4;
		outer_col = c_think * 0.12;
		mid_str   = 0.35;
		outer_str = 0.16;

	} else if (state == 3) {
		// SPEAKING — warm gold, radial waves ripple outward
		float waves = sin(dist * 22.0 - TIME * speed * 0.45) * 0.5 + 0.5;
		float wave2 = sin(dist * 14.0 - TIME * speed * 0.3 + 1.5) * 0.5 + 0.5;
		core_r  = base_r + 0.04 + waves * 0.028 + wobble1;
		mid_r   = base_r * 1.65 + wave2 * 0.025;
		outer_r = base_r * 2.5 + waves * 0.04 + wobble2;

		core_col  = c_speak;
		mid_col   = mix(c_speak * 0.6, vec3(0.9, 0.3, 0.05), 0.4);
		outer_col = c_speak * 0.15;
		mid_str   = 0.30;
		outer_str = 0.14;
	}

	// --- Filament layer (neural sparks around core edge) ---
	vec2 fil_uv = rot(t * 0.18) * uv;
	float filament = fbm(fil_uv * 7.0 + vec2(t * 1.2, -t)) * 0.5 + 0.5;
	float fil_ring  = smoothstep(core_r * 0.9, core_r * 1.1, dist) *
	                  (1.0 - smoothstep(core_r * 1.1, core_r * 1.5, dist));
	float fil_intensity = filament * fil_ring * 0.6;

	// --- Three shell compositing ---
	// Outer halo — wide, soft
	float outer = smoothstep(outer_r + 0.22, outer_r - 0.04, dist) * outer_str;

	// Mid shell — medium softness
	float mid_edge_in  = smoothstep(mid_r - 0.08, mid_r - 0.02, dist);
	float mid_edge_out = smoothstep(mid_r + 0.10, mid_r, dist);
	float mid = mid_edge_out * (1.0 - mid_edge_in * 0.4) * mid_str;

	// Core — tightest, brightest
	float core = smoothstep(core_r + 0.01, core_r - 0.08, dist);

	// Combine
	vec3 col = outer_col * outer
	         + mid_col   * mid
	         + core_col  * core
	         + core_col  * fil_intensity;

	col *= glow_intensity;
	float alpha = clamp(outer + mid + core + fil_intensity * 0.5, 0.0, 1.0);

	COLOR = vec4(col, alpha);
}
