## CIPHER - Volumetric Aura Shader Controller
## Smoothly interpolates shader colors, radius, and uniforms using frame-rate independent lerp.
## Cycles across 12 distinct, vivid, unmistakable listening palettes on Spacebar Push-to-Talk.
extends ColorRect

const IDLE: int = 0
const LISTENING: int = 1
const THINKING: int = 2
const SPEAKING: int = 3

## 12 Highly Distinct, Unmistakable Color Palettes for Push-to-Talk (LISTENING state)
## Spans the entire color wheel: Green, Orange, Pink, Yellow, Turquoise, Coral, Lime, etc.
const LISTENING_PALETTES: Array[Dictionary] = [
	# 1. Radiant Emerald & Sun Gold
	{"core": Vector3(0.10, 0.95, 0.45), "halo": Vector3(0.95, 0.85, 0.20), "glow": Vector3(0.02, 0.20, 0.05)},
	# 2. Vibrant Sunset Orange & Coral
	{"core": Vector3(1.00, 0.55, 0.10), "halo": Vector3(0.95, 0.25, 0.35), "glow": Vector3(0.22, 0.06, 0.02)},
	# 3. Electric Turquoise & Sky Aquamarine
	{"core": Vector3(0.05, 0.92, 0.95), "halo": Vector3(0.20, 0.65, 0.95), "glow": Vector3(0.01, 0.15, 0.22)},
	# 4. Ruby Rose & Hot Pink
	{"core": Vector3(0.95, 0.20, 0.55), "halo": Vector3(1.00, 0.50, 0.70), "glow": Vector3(0.25, 0.03, 0.08)},
	# 5. Neon Lime & Forest Jade
	{"core": Vector3(0.65, 0.98, 0.15), "halo": Vector3(0.15, 0.85, 0.55), "glow": Vector3(0.08, 0.22, 0.02)},
	# 6. Canary Gold & Warm Amber
	{"core": Vector3(1.00, 0.85, 0.15), "halo": Vector3(0.95, 0.55, 0.10), "glow": Vector3(0.22, 0.15, 0.02)},
	# 7. Mint Ice & Seafoam Dew
	{"core": Vector3(0.15, 0.95, 0.70), "halo": Vector3(0.45, 0.90, 0.85), "glow": Vector3(0.02, 0.18, 0.10)},
	# 8. Peach Blossom & Apricot Glow
	{"core": Vector3(0.98, 0.60, 0.45), "halo": Vector3(0.95, 0.80, 0.30), "glow": Vector3(0.20, 0.08, 0.03)},
	# 9. Vivid Orchid & Magenta Fire
	{"core": Vector3(0.85, 0.25, 0.90), "halo": Vector3(0.95, 0.45, 0.60), "glow": Vector3(0.20, 0.03, 0.18)},
	# 10. Arctic Ice Blue & Pure White Glow
	{"core": Vector3(0.35, 0.75, 1.00), "halo": Vector3(0.75, 0.90, 0.98), "glow": Vector3(0.04, 0.10, 0.25)},
	# 11. Crimson Velvet & Spiced Copper
	{"core": Vector3(0.95, 0.22, 0.18), "halo": Vector3(0.95, 0.60, 0.25), "glow": Vector3(0.22, 0.03, 0.02)},
	# 12. Chartreuse & Emerald Glow
	{"core": Vector3(0.80, 0.95, 0.18), "halo": Vector3(0.20, 0.90, 0.65), "glow": Vector3(0.12, 0.20, 0.03)}
]

# Current interpolated state properties (Muted pastel defaults)
var current_color_core: Vector3 = Vector3(0.50, 0.40, 0.72)
var current_color_halo: Vector3 = Vector3(0.30, 0.58, 0.68)
var current_color_glow: Vector3 = Vector3(0.06, 0.08, 0.28)
var current_radius: float = 0.54
var current_orbit_speed: float = 1.1

# Target state properties
var target_color_core: Vector3 = Vector3(0.50, 0.40, 0.72)
var target_color_halo: Vector3 = Vector3(0.30, 0.58, 0.68)
var target_color_glow: Vector3 = Vector3(0.06, 0.08, 0.28)
var target_radius: float = 0.54
var target_orbit_speed: float = 1.1

var current_volume: float = 0.0
var target_volume: float = 0.0
var current_speed: float = 1.0
var target_speed: float = 1.0
var current_glow: float = 1.90
var target_glow: float = 1.90
var active_state: int = 0
var mat: ShaderMaterial
var target_tension: float = 0.0
var current_tension: float = 0.0

# Guaranteed shuffle-deck randomizer for non-repeating palette selection
var palette_deck: Array[int] = []
var last_palette_idx: int = -1

func _ready() -> void:
	randomize()
	_refill_palette_deck()

	mat = material as ShaderMaterial
	if mat:
		_update_targets_for_state(IDLE)
		current_color_core = target_color_core
		current_color_halo = target_color_halo
		current_color_glow = target_color_glow
		current_radius = target_radius
		current_orbit_speed = target_orbit_speed

		mat.set_shader_parameter("color_core", current_color_core)
		mat.set_shader_parameter("color_halo", current_color_halo)
		mat.set_shader_parameter("color_glow", current_color_glow)
		mat.set_shader_parameter("base_radius", current_radius)
		mat.set_shader_parameter("orbit_speed", current_orbit_speed)
		mat.set_shader_parameter("volume", 0.0)
		mat.set_shader_parameter("time_offset", randf() * TAU)
		mat.set_shader_parameter("speed", 1.0)
		mat.set_shader_parameter("glow_intensity", 1.90) # 15% softened brightness
		mat.set_shader_parameter("tension", 0.0)

		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		mat.set_shader_parameter("resolution", vp_size)

	get_viewport().size_changed.connect(_on_viewport_resize)

func _on_viewport_resize() -> void:
	if mat:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		mat.set_shader_parameter("resolution", vp_size)

func _refill_palette_deck() -> void:
	palette_deck.clear()
	for i in range(LISTENING_PALETTES.size()):
		palette_deck.append(i)
	palette_deck.shuffle()
	# Ensure the first item of the new deck is never identical to the last popped palette
	if last_palette_idx != -1 and palette_deck[0] == last_palette_idx and palette_deck.size() > 1:
		var temp: int = palette_deck[0]
		palette_deck[0] = palette_deck[1]
		palette_deck[1] = temp

func _get_next_listening_palette() -> Dictionary:
	if palette_deck.is_empty():
		_refill_palette_deck()
	var next_idx: int = palette_deck.pop_front()
	last_palette_idx = next_idx
	return LISTENING_PALETTES[next_idx]

func _update_targets_for_state(s: int) -> void:
	match s:
		IDLE:
			# Signature calm baseline: Soft Dusty Lavender, Muted Slate-Cyan, and Deep Slate-Cobalt
			target_color_core = Vector3(0.50, 0.40, 0.72)
			target_color_halo = Vector3(0.30, 0.58, 0.68)
			target_color_glow = Vector3(0.06, 0.08, 0.28)
			target_radius = 0.54
			target_orbit_speed = 1.1
			target_speed = 0.25
			target_glow = 1.85
		LISTENING:
			# Guaranteed random selection from the 12 distinct palettes
			var pal: Dictionary = _get_next_listening_palette()
			target_color_core = pal["core"]
			target_color_halo = pal["halo"]
			target_color_glow = pal["glow"]
			target_radius = 0.65
			target_orbit_speed = 1.6
			target_speed = 0.45
			target_glow = 2.10
			# Fast-snap initial blend so the color change is instantly visible upon Spacebar press
			current_color_core = current_color_core.lerp(target_color_core, 0.65)
			current_color_halo = current_color_halo.lerp(target_color_halo, 0.65)
			current_color_glow = current_color_glow.lerp(target_color_glow, 0.65)
		THINKING:
			# Deep Smoky Indigo Singularity with Muted Plum Halo
			target_color_core = Vector3(0.18, 0.30, 0.68)
			target_color_halo = Vector3(0.42, 0.20, 0.58)
			target_color_glow = Vector3(0.03, 0.04, 0.22)
			target_radius = 0.46
			target_orbit_speed = 2.2
			target_speed = 0.50
			target_glow = 1.95
		SPEAKING:
			# Soft Muted Champagne-Honey with Dusty Amber Undertones
			target_color_core = Vector3(0.88, 0.70, 0.35)
			target_color_halo = Vector3(0.78, 0.48, 0.20)
			target_color_glow = Vector3(0.25, 0.10, 0.04)
			target_radius = 0.58
			target_orbit_speed = 1.3
			target_speed = 0.38
			target_glow = 1.95

func _process(delta: float) -> void:
	if not mat:
		return

	# Smooth color and radius interpolation across state transitions
	current_color_core = current_color_core.lerp(target_color_core, delta * 5.0)
	current_color_halo = current_color_halo.lerp(target_color_halo, delta * 5.0)
	current_color_glow = current_color_glow.lerp(target_color_glow, delta * 5.0)
	current_radius = lerp(current_radius, target_radius, delta * 4.0)
	current_orbit_speed = lerp(current_orbit_speed, target_orbit_speed, delta * 4.0)

	# Smooth volume damping (reacts naturally to voice without harsh spikes)
	current_volume = lerp(current_volume, target_volume, delta * 4.0)

	# Dynamic ambient breathing glow
	var ambient_breath: float = sin(Time.get_ticks_msec() * 0.0008) * 0.10
	current_speed = lerp(current_speed, target_speed, delta * 4.0)
	current_glow = lerp(current_glow, target_glow + ambient_breath + (current_volume * 0.4), delta * 4.0)
	current_tension = lerp(current_tension, target_tension, delta * 3.0)

	mat.set_shader_parameter("color_core", current_color_core)
	mat.set_shader_parameter("color_halo", current_color_halo)
	mat.set_shader_parameter("color_glow", current_color_glow)
	mat.set_shader_parameter("base_radius", current_radius)
	mat.set_shader_parameter("orbit_speed", current_orbit_speed)
	mat.set_shader_parameter("volume", current_volume)
	mat.set_shader_parameter("speed", current_speed)
	mat.set_shader_parameter("glow_intensity", current_glow)
	mat.set_shader_parameter("tension", current_tension)

func set_volume(v: float) -> void:
	target_volume = clamp(v, 0.0, 1.0)

func set_state(s: int) -> void:
	if active_state != s:
		active_state = s
		_update_targets_for_state(s)
