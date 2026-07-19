extends Node2D

var stars = []
var count = 200
@onready var main_node = get_parent()

func _ready():
	z_index = -1
	var screen_size = get_viewport_rect().size
	for i in range(count):
		var layer = randf()  # 0=far, 1=near — deeper stars move slower
		stars.append({
			"pos": Vector2(randf() * screen_size.x, randf() * screen_size.y),
			"speed": randf_range(4.0, 22.0) * (0.3 + layer * 0.7),
			"size": randf_range(0.5, 1.8) * (0.4 + layer * 0.6),
			"base_alpha": randf_range(0.08, 0.45) * (0.5 + layer * 0.5),
			"twinkle_phase": randf() * TAU,
			"twinkle_speed": randf_range(0.4, 1.8),
			"alpha": 0.0,
		})

func _process(delta):
	var screen_size = get_viewport_rect().size
	var center = screen_size / 2.0

	var volume = 0.0
	if main_node and "spectrum" in main_node and main_node.spectrum:
		var mag = main_node.spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(mag * 15.0, 0.0, 1.0)

	var t = Time.get_ticks_msec() * 0.001

	for s in stars:
		s.pos.x -= s.speed * delta * (1.0 + volume * 1.8)

		# Gentle volume-driven pull toward center
		if volume > 0.015:
			var dir = (center - s.pos).normalized()
			var dist = s.pos.distance_to(center)
			if dist > 60.0:
				s.pos += dir * volume * 55.0 * delta * (1.0 / (1.0 + dist * 0.002))

		# Full 4-edge wrap — no stars are ever lost
		if s.pos.x < -2.0:
			s.pos.x = screen_size.x + 2.0
			s.pos.y = randf() * screen_size.y
		elif s.pos.x > screen_size.x + 2.0:
			s.pos.x = -2.0
			s.pos.y = randf() * screen_size.y
		if s.pos.y < -2.0:
			s.pos.y = screen_size.y + 2.0
		elif s.pos.y > screen_size.y + 2.0:
			s.pos.y = -2.0

		# Twinkling — subtle sine oscillation on alpha
		var twinkle = sin(t * s.twinkle_speed + s.twinkle_phase) * 0.5 + 0.5
		s.alpha = lerp(s.base_alpha * (0.6 + twinkle * 0.4), 0.92, volume)

	queue_redraw()

func _draw():
	for s in stars:
		var col = Color(0.82, 0.78, 0.97, s.alpha)
		draw_circle(s.pos, s.size, col)
