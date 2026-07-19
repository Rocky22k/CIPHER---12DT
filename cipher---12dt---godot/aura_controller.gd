extends ColorRect

const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

var current_volume = 0.0
var target_volume = 0.0
var current_speed = 1.0
var target_speed = 1.0
var current_glow = 2.8
var target_glow = 2.8
var active_state = 0
var mat: ShaderMaterial
var target_tension = 0.0
var current_tension = 0.0

func _ready():
	mat = material
	mat.set_shader_parameter("state", IDLE)
	mat.set_shader_parameter("volume", 0.0)
	mat.set_shader_parameter("time_offset", randf() * TAU)
	mat.set_shader_parameter("speed", 1.0)
	mat.set_shader_parameter("glow_intensity", 2.8)
	mat.set_shader_parameter("tension", 0.0)
	# Set resolution so the shader can do correct aspect correction
	var vp_size = get_viewport().get_visible_rect().size
	mat.set_shader_parameter("resolution", vp_size)
	get_viewport().size_changed.connect(_on_viewport_resize)

func _on_viewport_resize():
	var vp_size = get_viewport().get_visible_rect().size
	mat.set_shader_parameter("resolution", vp_size)

func _process(delta):
	current_volume = lerp(current_volume, target_volume, delta * 8.0)
	mat.set_shader_parameter("volume", current_volume)

	match active_state:
		IDLE:
			target_speed = 0.22
			target_glow = 2.4 + sin(Time.get_ticks_msec() * 0.0007) * 0.25
		LISTENING:
			target_speed = 0.38 + current_volume * 0.5
			target_glow = 2.6 + current_volume * 1.4
		THINKING:
			target_speed = 0.55
			target_glow = 2.7 + sin(Time.get_ticks_msec() * 0.0012) * 0.18
		SPEAKING:
			target_speed = 0.42
			target_glow = 2.55 + current_volume * 1.1

	current_speed   = lerp(current_speed,   target_speed,   delta * 5.0)
	current_glow    = lerp(current_glow,    target_glow,    delta * 4.5)
	current_tension = lerp(current_tension, target_tension, delta * 3.5)

	mat.set_shader_parameter("speed",          current_speed)
	mat.set_shader_parameter("glow_intensity", current_glow)
	mat.set_shader_parameter("tension",        current_tension)

func set_volume(v: float):
	target_volume = clamp(v, 0.0, 1.0)

func set_state(s: int):
	active_state = s
	mat.set_shader_parameter("state", s)
