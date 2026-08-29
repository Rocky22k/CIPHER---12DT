## CIPHER — Parallax Chromatic Deep Starfield
## Generates a multi-layered parallax starfield with realistic stellar color temperatures,
## gentle volume-reactive gravitational drift, and subtle diffraction flares.
extends Node2D

var stars: Array[Dictionary] = []
var count: int = 220
@onready var main_node: Node = get_parent()

func _ready() -> void:
	z_index = -1
	var screen_size: Vector2 = get_viewport_rect().size
	for i in range(count):
		var layer: float = randf() # 0.0 = deep background, 1.0 = foreground
		var hue_pick: float = randf()
		var star_color: Color

		# Chromatic stellar temperature distribution
		if hue_pick < 0.60:
			star_color = Color(0.86, 0.83, 0.98) # Silver-violet
		elif hue_pick < 0.85:
			star_color = Color(0.68, 0.89, 0.98) # Cyan-white
		else:
			star_color = Color(0.98, 0.86, 0.62) # Warm celestial amber

		stars.append({
			"pos": Vector2(randf() * screen_size.x, randf() * screen_size.y),
			"speed": randf_range(2.5, 16.0) * (0.25 + layer * 0.75),
			"size": randf_range(0.6, 1.8) * (0.35 + layer * 0.65),
			"base_alpha": randf_range(0.10, 0.50) * (0.4 + layer * 0.6),
			"twinkle_phase": randf() * TAU,
			"twinkle_speed": randf_range(0.5, 2.0),
			"color": star_color,
			"layer": layer,
			"alpha": 0.0,
		})

func _process(delta: float) -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = screen_size / 2.0

	var volume: float = 0.0
	if main_node and "spectrum" in main_node and main_node.spectrum:
		var mag: float = main_node.spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(mag * 12.0, 0.0, 1.0)

	var t: float = Time.get_ticks_msec() * 0.001

	for s in stars:
		# Horizontal drift with voice-reactive acceleration
		s.pos.x -= s.speed * delta * (1.0 + volume * 1.5)

		# Gentle volume-driven gravitational drift toward the central aura
		if volume > 0.02:
			var dir: Vector2 = (center - s.pos).normalized()
			var dist: float = s.pos.distance_to(center)
			if dist > 80.0:
				s.pos += dir * volume * 45.0 * delta * (1.0 / (1.0 + dist * 0.002))

		# Seamless 4-edge screen wrapping
		if s.pos.x < -4.0:
			s.pos.x = screen_size.x + 4.0
			s.pos.y = randf() * screen_size.y
		elif s.pos.x > screen_size.x + 4.0:
			s.pos.x = -4.0
			s.pos.y = randf() * screen_size.y

		if s.pos.y < -4.0:
			s.pos.y = screen_size.y + 4.0
			s.pos.y = randf() * screen_size.y
		elif s.pos.y > screen_size.y + 4.0:
			s.pos.y = -4.0

		# Twinkling calculation (smooth harmonic cosine)
		var twinkle: float = cos(t * s.twinkle_speed + s.twinkle_phase) * 0.5 + 0.5
		s.alpha = lerp(s.base_alpha * (0.65 + twinkle * 0.35), 0.92, volume)

	queue_redraw()

func _draw() -> void:
	for s in stars:
		var col: Color = Color(s.color.r, s.color.g, s.color.b, s.alpha)
		draw_circle(s.pos, s.size, col)

		# Subtle 4-point diffraction flare on foreground stars (inspired by React Bits <Galaxy />)
		if s.layer > 0.75 and s.alpha > 0.35:
			var flare_len: float = s.size * 2.8
			var flare_col: Color = Color(s.color.r, s.color.g, s.color.b, s.alpha * 0.25)
			draw_line(s.pos - Vector2(flare_len, 0), s.pos + Vector2(flare_len, 0), flare_col, 1.0)
			draw_line(s.pos - Vector2(0, flare_len), s.pos + Vector2(0, flare_len), flare_col, 1.0)
