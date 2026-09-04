shader_type canvas_item;

// =============================================================================
// CIPHER - Continuous Cyclical Aurora Flow Background Shader
// Harmonized with the central living orb's cosmic palette.
// Cascades from the Top-Right cluster across the Top-Left and Center,
// continuously circulating toward the Bottom-Left and looping seamlessly.
// =============================================================================

uniform float time_phase = 0.0;
uniform float speed : hint_range(0.1, 2.0) = 0.42;
uniform float amplitude : hint_range(0.1, 2.5) = 1.20;
uniform float valence : hint_range(0.0, 1.0) = 0.5;

// 2D Hash for fine analog film grain
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Simplex noise helper
vec3 permute(vec3 x) {
	return mod(((x * 34.0) + 1.0) * x, 289.0);
}

// 2D Simplex Noise
float snoise(vec2 v) {
	const vec4 C = vec4(
		0.211324865405187,
		0.366025403784439,
		-0.577350269189626,
		0.024390243902439
	);
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod(i, 289.0);

	vec3 p = permute(
		permute(i.y + vec3(0.0, i1.y, 1.0))
		+ i.x + vec3(0.0, i1.x, 1.0)
	);

	vec3 m = max(
		0.5 - vec3(
			dot(x0, x0),
			dot(x12.xy, x12.xy),
			dot(x12.zw, x12.zw)
		),
		0.0
	);
	m = m * m;
	m = m * m;

	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

void fragment() {
	vec2 uv = UV;

	// Continuous time parameter ensuring fluid movement
	float t = mod(TIME * speed * 0.70 + time_phase, 3600.0);

	// Primary flow coordinate: Top-Right (origin) to Bottom-Left
	float flowPrimary = ((1.0 - uv.x) * 0.60) + (uv.y * 0.65);

	// Multi-layered cyclical wave displacement
	vec2 p1 = vec2(uv.x * 2.0 - (t * 0.25), uv.y * 1.5 + (t * 0.30));
	vec2 p2 = vec2(-uv.x * 1.4 - (t * 0.20), uv.y * 2.2 - (t * 0.16));
	vec2 p3 = vec2(uv.x * 3.0 + (t * 0.12), -uv.y * 1.8 + (t * 0.22));

	float w1 = snoise(p1) * 0.55 * amplitude;
	float w2 = snoise(p2 + vec2(1.8, 3.4)) * 0.30 * amplitude;
	float w3 = snoise(p3 + vec2(4.2, -1.5)) * 0.18 * amplitude;
	float totalWave = w1 + w2 + w3;

	// Full top-banner and corner coverage
	float topBannerWeight = 1.0 - smoothstep(0.0, 0.85, uv.y);
	float topCornerWeight = max(uv.x * 0.45, (1.0 - uv.x) * 0.40);
	float clusterDensity = exp(totalWave * 0.80) * (0.85 + topBannerWeight * 0.60 + topCornerWeight * 0.35);

	// Harmonized Cosmic Palette (In direct color harmony with the living orb)
	vec3 cSpace    = vec3(0.015, 0.010, 0.028); // Deep space base
	vec3 cMidnight = mix(vec3(0.06, 0.07, 0.22), vec3(0.10, 0.07, 0.26), valence); // Midnight Indigo
	vec3 cWisteria = mix(vec3(0.25, 0.14, 0.42), vec3(0.35, 0.18, 0.48), valence); // Dusty Wisteria / Amethyst
	vec3 cSkyTeal  = mix(vec3(0.12, 0.42, 0.52), vec3(0.18, 0.46, 0.48), valence); // Muted Sky-Cyan Mist
	vec3 cPaleLilac= mix(vec3(0.32, 0.40, 0.58), vec3(0.42, 0.40, 0.55), valence); // Soft Cosmic Lilac

	// Smooth color ramp along the cascade
	float rampPos = clamp(flowPrimary + (totalWave * 0.25), 0.0, 1.1);
	vec3 rampColor;
	if (rampPos < 0.30) {
		rampColor = mix(cPaleLilac, cSkyTeal, rampPos / 0.30);
	} else if (rampPos < 0.65) {
		rampColor = mix(cSkyTeal, cWisteria, (rampPos - 0.30) / 0.35);
	} else if (rampPos < 0.95) {
		rampColor = mix(cWisteria, cMidnight, (rampPos - 0.65) / 0.30);
	} else {
		rampColor = mix(cMidnight, cSpace, (rampPos - 0.95) / 0.15);
	}

	// Soft fade out at bottom-left edge to protect subtitles
	float bottomEdge = smoothstep(0.95, 0.70, uv.y);
	float bottomLeftCutoff = smoothstep(0.0, 0.45, length(vec2(uv.x * 1.2, 1.0 - uv.y)));
	float legibilityMask = max(bottomEdge, bottomLeftCutoff);

	float auroraAlpha = smoothstep(0.12, 0.85, clusterDensity) * legibilityMask;
	auroraAlpha = clamp(auroraAlpha * 0.75, 0.0, 0.78);

	vec3 auroraColor = rampColor * clusterDensity;
	vec3 finalColor = mix(cSpace, cSpace + auroraColor, auroraAlpha);

	// Subtle analog film grain to eliminate digital color banding
	float grain = (hash21(FRAGCOORD.xy + mod(TIME, 60.0) * 11.0) - 0.5) * 0.016;
	finalColor += vec3(grain);

	COLOR = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
