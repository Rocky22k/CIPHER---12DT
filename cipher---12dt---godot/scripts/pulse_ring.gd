extends Node2D

var radius = 20.0
var expand_speed = 220.0
var initial_alpha = 0.35
var ring: Line2D

func _ready():
	ring = $Ring
	ring.width = 2.5
	ring.antialiased = true
	_draw_circle()

func set_wpm(wpm: float):
	# Feature 14: Fast speech = faster expanding rings; slow speech = slow drifting rings
	expand_speed = lerp(120.0, 320.0, clamp(wpm / 200.0, 0.0, 1.0))

func set_state_color(state: int):
	match state:
		1: # LISTENING - cyan-teal
			ring.default_color = Color(0.1, 0.85, 0.95, 0.35)
		3: # SPEAKING - warm gold
			ring.default_color = Color(1.0, 0.72, 0.2, 0.30)
		2: # THINKING - sapphire
			ring.default_color = Color(0.15, 0.35, 0.92, 0.30)
		_: # IDLE - soft violet
			ring.default_color = Color(0.55, 0.25, 0.85, 0.25)

func _process(delta):
	radius += expand_speed * delta
	expand_speed = lerp(expand_speed, 18.0, delta * 1.8)

	# Feature 12: Exponential alpha decay curve
	ring.default_color.a *= pow(0.12, delta)
	if ring.default_color.a <= 0.01:
		queue_free()
		return

	_draw_circle()

func _draw_circle():
	ring.clear_points()
	for i in range(129):
		var angle = (float(i) / 128.0) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * radius)
