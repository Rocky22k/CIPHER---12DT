extends Node2D

var stars = []
var count = 55
@onready var main_node = get_parent()

func _ready():
	z_index = -1 # Render in the background void
	var screen_size = get_viewport_rect().size
	for i in range(count):
		stars.append({
			"pos": Vector2(randf() * screen_size.x, randf() * screen_size.y),
			"speed": randf_range(10.0, 40.0),
			"size": randf_range(1.0, 3.0),
			"base_alpha": randf_range(0.15, 0.55),
			"alpha": 0.0
		})

func _process(delta):
	var screen_size = get_viewport_rect().size
	var center = screen_size / 2.0

	var volume = 0.0
	if main_node and "spectrum" in main_node and main_node.spectrum:
		var mag = main_node.spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(mag * 15.0, 0.0, 1.0)

	for s in stars:
		# Horizontal drift
		s.pos.x -= s.speed * delta * (1.0 + volume * 2.0)

		# Gravitational pull towards core
		if volume > 0.01:
			var dir = (center - s.pos).normalized()
			var dist = s.pos.distance_to(center)
			if dist > 80.0:
				s.pos += dir * volume * 75.0 * delta * (1.0 / (1.0 + dist * 0.001))

		# Screen wrapping
		if s.pos.x < 0:
			s.pos.x = screen_size.x
			s.pos.y = randf() * screen_size.y

		s.alpha = lerp(s.base_alpha, 0.95, volume)

	queue_redraw()

func _draw():
	for s in stars:
		var col = Color(0.8, 0.75, 0.95, s.alpha)
		draw_circle(s.pos, s.size, col)
