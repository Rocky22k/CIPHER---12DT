extends Node2D

var line_color = Color(0.12, 0.12, 0.22, 0.35) # Subtle dark sci-fi blue
var grid_size = 22
var ripple_strength = 280.0
var wave_frequency = 0.04
var wave_speed = 6.0
var time = 0.0

@onready var main_node = get_parent()

func _process(delta):
	time += delta * wave_speed
	queue_redraw()

func _draw():
	var screen_size = get_viewport_rect().size
	var center = screen_size / 2.0
	var step_x = screen_size.x / float(grid_size)
	var step_y = screen_size.y / float(grid_size)

	# Extract volume magnitude from parent script
	var volume = 0.0
	if main_node and "spectrum" in main_node and main_node.spectrum:
		var magnitude = main_node.spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(magnitude, 0.0, 1.0)

	# Draw horizontal lines with sine-distortion
	for i in range(grid_size + 1):
		var points = PackedVector2Array()
		var y = i * step_y
		for j in range(grid_size + 1):
			var x = j * step_x
			var pt = Vector2(x, y)
			var dist = pt.distance_to(center)
			if dist > 0.0 and volume > 0.001:
				var dir = (pt - center).normalized()
				var wave = sin(dist * wave_frequency - time)
				# Dynamic falloff so distortion concentrates near center and ripples out
				var displacement = dir * wave * ripple_strength * volume * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], line_color, 1.0)

	# Draw vertical lines with sine-distortion
	for j in range(grid_size + 1):
		var points = PackedVector2Array()
		var x = j * step_x
		for i in range(grid_size + 1):
			var y = i * step_y
			var pt = Vector2(x, y)
			var dist = pt.distance_to(center)
			if dist > 0.0 and volume > 0.001:
				var dir = (pt - center).normalized()
				var wave = sin(dist * wave_frequency - time)
				var displacement = dir * wave * ripple_strength * volume * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], line_color, 1.0)
