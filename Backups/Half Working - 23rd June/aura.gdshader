shader_type canvas_item;

uniform float volume : hint_range(0.0, 1.0) = 0.0;
uniform int state = 0; // 0=IDLE, 1=LISTENING, 2=THINKING, 3=SPEAKING
uniform float time_offset = 0.0;
uniform float speed = 1.0;
uniform float glow_intensity = 2.5;

// Aspect ratio correction (16:9)
const float aspect = 16.0 / 9.0;

// Organic noise algorithm for dynamic flames
vec2 random2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float n = mix(mix(dot(-1.0 + 2.0 * random2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                      dot(-1.0 + 2.0 * random2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
                  mix(dot(-1.0 + 2.0 * random2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                      dot(-1.0 + 2.0 * random2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
    return 0.5 + 0.5 * n;
}

void fragment() {
    // Aratio correction
    vec2 uv = UV;
    uv.x = (uv.x - 0.5) * aspect + 0.5;

    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);

    // Add wobbly distortion - slowed down for calming aesthetic
    float t = TIME * 0.08 * speed + time_offset;
    float wobble = noise(uv * 3.0 + vec2(t, -t)) * 0.08;

    // Breathing pulsation - slowed down from 0.8 to 0.4
    float breath = sin(TIME * 0.4 + time_offset) * 0.5 + 0.5;
    float base_radius = 0.15 + breath * 0.02 + wobble;

    float radius = base_radius;

    // Colors
    vec3 color_idle = vec3(0.3, 0.05, 0.6); // Deep Purple
    vec3 color_listen = vec3(0.0, 0.8, 0.9); // Bright Cyan
    vec3 color_think = vec3(0.05, 0.2, 0.8); // Deep Blue
    vec3 color_speak = vec3(1.0, 0.6, 0.1); // Warm Gold

    vec3 color = color_idle;

    if (state == 1) {
        float vol_boost = volume * 0.4;
        radius = base_radius + vol_boost + wobble * 2.0;
        color = mix(color_idle, color_listen, clamp(volume * 3.0, 0.0, 1.0));
    } else if (state == 2) {
        float angle = atan(uv.y - 0.5, uv.x - 0.5);
        // Spinning thinking rotation - slowed down from 0.6 to 0.25
        float spin = sin(angle * 4.0 + TIME * 0.25 * speed) * 0.5 + 0.5;
        radius = base_radius - 0.02 + spin * 0.04 + wobble;
        color = color_think;
    } else if (state == 3) {
        // Rippling speaking waves - slowed down from 1.0 to 0.4
        float waves = sin(dist * 20.0 - TIME * 0.4 * speed) * 0.5 + 0.5;
        radius = base_radius + 0.05 + waves * 0.03 + wobble;
        color = color_speak;
    }

    float core = smoothstep(radius, radius - 0.05, dist);
    float halo = smoothstep(radius + 0.25, radius, dist) * 0.4;

    vec3 final_color = color * (core + halo) * glow_intensity;
    float alpha = core + halo;

    COLOR = vec4(final_color, clamp(alpha, 0.0, 1.0));
}
