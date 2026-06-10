extends ColorRect

# These match the shader's state uniform exactly.
const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

var current_volume = 0.0
var target_volume = 0.0
var mat: ShaderMaterial

func _ready():
	mat = material
	mat.set_shader_parameter("state", IDLE)
	mat.set_shader_parameter("volume", 0.0)
	mat.set_shader_parameter("time_offset", randf() * TAU)

func _process(delta):
	# Smooth the volume so the Aura doesn't jump around
	current_volume = lerp(current_volume, target_volume, delta * 8.0)
	mat.set_shader_parameter("volume", current_volume)

func set_volume(v: float):
	target_volume = clamp(v, 0.0, 1.0)

func set_state(s: int):
	mat.set_shader_parameter("state", s)
