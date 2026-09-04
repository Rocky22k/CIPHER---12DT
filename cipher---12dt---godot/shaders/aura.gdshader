shader_type canvas_item;

// =============================================================================
// CIPHER - Sentient Volumetric Living Orb Fragment Shader
// Inspired by the React Bits <Orb /> WebGL component.
// Features 3D Simplex noise, inverse-square volumetric light attenuation,
// continuous orbiting photon highlight, and smooth interpolated color blending.
// =============================================================================

uniform vec3 color_core = vec3(0.61, 0.26, 1.0);
uniform vec3 color_halo = vec3(0.30, 0.76, 0.91);
uniform vec3 color_glow = vec3(0.06, 0.08, 0.60);
uniform float base_radius : hint_range(0.2, 1.0) = 0.54;
uniform float orbit_speed : hint_range(0.5, 4.0) = 1.2;

uniform float volume : hint_range(0.0, 1.0) = 0.0;
uniform float tension : hint_range(0.0, 1.0) = 0.0; // Vocal pitch tension (0.0 to 1.0)
uniform float speed = 1.0;
uniform float time_offset = 0.0;
uniform float glow_intensity = 1.90;
uniform vec2 resolution = vec2(1920.0, 1080.0);

// --- YIQ Color Space Conversion (Smooth spectral hue rotation for tension) ---
vec3 rgb2yiq(vec3 c) {
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	float i = dot(c, vec3(0.596, -0.274, -0.322));
	float q = dot(c, vec3(0.211, -0.523, 0.312));
	return vec3(y, i, q);
}

vec3 yiq2rgb(vec3 c) {
	float r = c.x + 0.956 * c.y + 0.621 * c.z;
	float g = c.x - 0.272 * c.y - 0.647 * c.z;
	float b = c.x - 1.106 * c.y + 1.703 * c.z;
	return vec3(r, g, b);
}

vec3 adjustHue(vec3 color, float hueDeg) {
	float hueRad = hueDeg * 3.14159265 / 180.0;
	vec3 yiq = rgb2yiq(color);
	float cosA = cos(hueRad);
	float sinA = sin(hueRad);
	float i = yiq.y * cosA - yiq.z * sinA;
	float q = yiq.y * sinA + yiq.z * cosA;
	yiq.y = i;
	yiq.z = q;
	return yiq2rgb(yiq);
}

// --- 3D Simplex & Hash Noise Functions ---
vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.11369, 0.13787));
	p3 += dot(p3, p3.yxz + 19.19);
	return -1.0 + 2.0 * fract(vec3(
		p3.x + p3.y,
		p3.x + p3.z,
		p3.y + p3.z
	) * p3.zyx);
}

float snoise3(vec3 p) {
	const float K1 = 0.333333333;
	const float K2 = 0.166666667;
	vec3 i = floor(p + (p.x + p.y + p.z) * K1);
	vec3 d0 = p - (i - (i.x + i.y + i.z) * K2);
	vec3 e = step(vec3(0.0), d0 - d0.yzx);
	vec3 i1 = e * (1.0 - e.zxy);
	vec3 i2 = 1.0 - e.zxy * (1.0 - e);
	vec3 d1 = d0 - (i1 - K2);
	vec3 d2 = d0 - (i2 - K1);
	vec3 d3 = d0 - 0.5;
	vec4 h = max(0.6 - vec4(
		dot(d0, d0),
		dot(d1, d1),
		dot(d2, d2),
		dot(d3, d3)
	), 0.0);
	vec4 n = h * h * h * h * vec4(
		dot(d0, hash33(i)),
		dot(d1, hash33(i + i1)),
		dot(d2, hash33(i + i2)),
		dot(d3, hash33(i + 1.0))
	);
	return dot(vec4(31.316), n);
}

// --- Inverse-Square Volumetric Light Attenuation ---
float light1(float intensity, float attenuation, float dist) {
	return intensity / (1.0 + dist * attenuation);
}

float light2(float intensity, float attenuation, float dist) {
	return intensity / (1.0 + dist * dist * attenuation);
}

void fragment() {
	// Normalized centered coordinate system scaled to viewport
	float asp = resolution.x / resolution.y;
	vec2 uv = (UV - 0.5) * vec2(asp, 1.0) * 3.4;

	float len = length(uv);
	float invLen = len > 0.0 ? 1.0 / len : 0.0;
	float ang = atan(uv.y, uv.x);

	float t = mod(TIME * speed * 0.45 + time_offset, 3600.0);

	// Tension shifts color hue smoothly toward warm magenta/rose
	float hueShift = tension * 55.0;
	vec3 color1 = adjustHue(color_core, hueShift);
	vec3 color2 = adjustHue(color_halo, hueShift);
	vec3 color3 = adjustHue(color_glow, hueShift);

	float dynRadius = base_radius + (volume * 0.20);
	float noiseScale = 0.65;

	// 3D Simplex noise distortion on the spherical boundary
	float n0 = snoise3(vec3(uv * noiseScale, t * 0.5)) * 0.5 + 0.5;
	float r0 = mix(mix(dynRadius, 1.0, 0.4), mix(dynRadius, 1.0, 0.6), n0);

	// Inverse-square light attenuation corona
	float d0 = distance(uv, (r0 * invLen) * uv);
	float v0 = light1(1.0, 10.0, d0);
	v0 *= smoothstep(r0 * 1.05, r0, len);
	float innerFade = smoothstep(r0 * 0.8, r0 * 0.95, len);
	v0 *= innerFade;

	// Dynamic orbiting specular photon highlight
	float a = t * -orbit_speed;
	vec2 orbitPos = vec2(cos(a), sin(a)) * r0;
	float dOrbit = distance(uv, orbitPos);
	float v1 = light2(1.6, 4.5, dOrbit) * light1(1.0, 50.0, d0);

	// Fluid multi-layer volumetric falloffs
	float v2 = smoothstep(1.0, mix(dynRadius, 1.0, n0 * 0.5), len);
	float v3 = smoothstep(dynRadius * 0.6, mix(dynRadius, 1.0, 0.5), len);

	float cl = cos(ang + t * 2.0) * 0.5 + 0.5;
	vec3 colBase = mix(color1, color2, cl);

	// Volumetric core and ambient lighting synthesis
	vec3 darkCol = mix(color3, colBase, v0);
	darkCol = (darkCol + v1) * v2 * v3;
	darkCol = clamp(darkCol, 0.0, 1.0);

	vec3 lightCol = (colBase + v1) * mix(1.0, v2 * v3, 0.4);
	lightCol = mix(vec3(0.0), lightCol, v0);
	lightCol = clamp(lightCol, 0.0, 1.0);

	vec3 finalCol = mix(darkCol, lightCol, 0.35);

	// Soft perimeter falloff to prevent clipping and protect subtitle area
	float screenDist = length((UV - 0.5) * vec2(asp, 1.0));
	float boundaryFade = 1.0 - smoothstep(0.28, 0.35, screenDist);
	finalCol *= boundaryFade;

	float alpha = max(max(finalCol.r, finalCol.g), finalCol.b);
	alpha = clamp(alpha * glow_intensity, 0.0, 1.0) * boundaryFade;

	COLOR = vec4(finalCol * glow_intensity, alpha);
}
