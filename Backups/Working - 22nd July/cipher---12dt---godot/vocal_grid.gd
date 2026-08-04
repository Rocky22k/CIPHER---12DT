extends Node2D

var line_color = Color(0.12, 0.12, 0.22, 0.35) # Subtle dark sci-fi blue
var grid_size = 22
var ripple_strength = 150.0
var wave_frequency = 0.04
var wave_speed = 0.8
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

	# Extract frequency-specific volume magnitudes from parent script
	var volume_bass = 0.0
	var volume_mid = 0.0
	var volume_treble = 0.0
	var has_audio = false

	if main_node and "spectrum" in main_node and main_node.spectrum:
		has_audio = true
		var bass_mag = main_node.spectrum.get_magnitude_for_frequency_range(20, 250).length()
		var mid_mag = main_node.spectrum.get_magnitude_for_frequency_range(250, 4000).length()
		var treble_mag = main_node.spectrum.get_magnitude_for_frequency_range(4000, 20000).length()

		volume_bass = clamp(bass_mag * 1.5, 0.0, 1.0)
		volume_mid = clamp(mid_mag * 2.0, 0.0, 1.0)
		volume_treble = clamp(treble_mag * 3.0, 0.0, 1.0)

	var dyn_color = line_color
	var dyn_freq = wave_frequency
	var dyn_speed_mod = 1.0
	var dyn_strength = 0.0

	if has_audio:
		# Shift color dynamically: treble shifts to cyan, bass shifts to purple
		dyn_color = line_color.lerp(Color(0.0, 0.7, 0.9, 0.55), volume_treble).lerp(Color(0.5, 0.1, 0.7, 0.5), volume_bass)
		dyn_color.a = clamp(0.35 + volume_mid * 0.25, 0.15, 0.65)

		# Modulate wave ripples: treble speeds up waves, bass deepens displacement
		dyn_freq = wave_frequency * (1.0 + volume_treble * 0.8)
		dyn_speed_mod = 1.0 + volume_treble * 0.3
		dyn_strength = ripple_strength * volume_bass

	# Draw horizontal lines with sine-distortion
	for i in range(grid_size + 1):
		var points = PackedVector2Array()
		var y = i * step_y
		for j in range(grid_size + 1):
			var x = j * step_x
			var pt = Vector2(x, y)
			var dist = pt.distance_to(center)
			if dist > 0.0 and dyn_strength > 0.01:
				var dir = (pt - center).normalized()
				var wave = sin(dist * dyn_freq - (time * dyn_speed_mod))
				# Dynamic falloff so distortion concentrates near center and ripples out
				var displacement = dir * wave * dyn_strength * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], dyn_color, 1.0)

	# Draw vertical lines with sine-distortion
	for j in range(grid_size + 1):
		var points = PackedVector2Array()
		var x = j * step_x
		for i in range(grid_size + 1):
			var y = i * step_y
			var pt = Vector2(x, y)
			var dist = pt.distance_to(center)
			if dist > 0.0 and dyn_strength > 0.01:
				var dir = (pt - center).normalized()
				var wave = sin(dist * dyn_freq - (time * dyn_speed_mod))
				var displacement = dir * wave * dyn_strength * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], dyn_color, 1.0)
