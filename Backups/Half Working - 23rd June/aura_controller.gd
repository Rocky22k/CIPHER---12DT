extends ColorRect

const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

var current_volume = 0.0
var target_volume = 0.0
var current_speed = 1.0
var target_speed = 1.0
var current_glow = 2.5
var target_glow = 2.5
var active_state = 0
var mat: ShaderMaterial

func _ready():
	mat = material
	mat.set_shader_parameter("state", IDLE)
	mat.set_shader_parameter("volume", 0.0)
	mat.set_shader_parameter("time_offset", randf() * TAU)
	mat.set_shader_parameter("speed", 1.0)
	mat.set_shader_parameter("glow_intensity", 2.5)

func _process(delta):
	# Volume smoothing so the Aura doesn't jump around
	current_volume = lerp(current_volume, target_volume, delta * 8.0)
	mat.set_shader_parameter("volume", current_volume)

	# Determine target speed and glow based on active state
	match active_state:
		IDLE:
			target_speed = 0.2
			target_glow = 2.2 + sin(Time.get_ticks_msec() * 0.0008) * 0.2
		LISTENING:
			target_speed = 0.4 + current_volume * 0.4
			target_glow = 2.4 + current_volume * 1.2
		THINKING:
			target_speed = 0.6
			target_glow = 2.6 + sin(Time.get_ticks_msec() * 0.0015) * 0.15
		SPEAKING:
			target_speed = 0.4
			target_glow = 2.5 + current_volume * 1.0

	# Smoothly interpolate parameters
	current_speed = lerp(current_speed, target_speed, delta * 5.0)
	current_glow = lerp(current_glow, target_glow, delta * 5.0)

	# Set shader parameters
	mat.set_shader_parameter("speed", current_speed)
	mat.set_shader_parameter("glow_intensity", current_glow)

func set_volume(v: float):
	target_volume = clamp(v, 0.0, 1.0)

func set_state(s: int):
	active_state = s
	mat.set_shader_parameter("state", s)
