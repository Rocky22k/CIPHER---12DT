## CIPHER — Vocal Grid Sine Wave Displacement Layer
## Generates a reactive background coordinate lattice that displaces dynamically
## based on multi-band audio spectrum frequencies (bass displacement, treble speed modulation).
extends Node2D

var line_color: Color = Color(0.12, 0.12, 0.22, 0.35)
var grid_size: int = 22
var ripple_strength: float = 150.0
var wave_frequency: float = 0.04
var wave_speed: float = 0.8
var time: float = 0.0

@onready var main_node: Node = get_parent()

func _process(delta: float) -> void:
	time += delta * wave_speed
	queue_redraw()

func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = screen_size / 2.0
	var step_x: float = screen_size.x / float(grid_size)
	var step_y: float = screen_size.y / float(grid_size)

	var volume_bass: float = 0.0
	var volume_mid: float = 0.0
	var volume_treble: float = 0.0
	var has_audio: bool = false

	if main_node and "spectrum" in main_node and main_node.spectrum:
		has_audio = true
		var bass_mag: float = main_node.spectrum.get_magnitude_for_frequency_range(20, 250).length()
		var mid_mag: float = main_node.spectrum.get_magnitude_for_frequency_range(250, 4000).length()
		var treble_mag: float = main_node.spectrum.get_magnitude_for_frequency_range(4000, 20000).length()

		volume_bass = clamp(bass_mag * 1.5, 0.0, 1.0)
		volume_mid = clamp(mid_mag * 2.0, 0.0, 1.0)
		volume_treble = clamp(treble_mag * 3.0, 0.0, 1.0)

	var dyn_color: Color = line_color
	var dyn_freq: float = wave_frequency
	var dyn_speed_mod: float = 1.0
	var dyn_strength: float = 0.0

	if has_audio:
		dyn_color = line_color.lerp(Color(0.0, 0.7, 0.9, 0.55), volume_treble).lerp(Color(0.5, 0.1, 0.7, 0.5), volume_bass)
		dyn_color.a = clamp(0.35 + volume_mid * 0.25, 0.15, 0.65)
		dyn_freq = wave_frequency * (1.0 + volume_treble * 0.8)
		dyn_speed_mod = 1.0 + volume_treble * 0.3
		dyn_strength = ripple_strength * volume_bass

	# Horizontal lattice lines
	for i in range(grid_size + 1):
		var points: PackedVector2Array = PackedVector2Array()
		var y: float = i * step_y
		for j in range(grid_size + 1):
			var x: float = j * step_x
			var pt: Vector2 = Vector2(x, y)
			var dist: float = pt.distance_to(center)
			if dist > 0.0 and dyn_strength > 0.01:
				var dir: Vector2 = (pt - center).normalized()
				var wave: float = sin(dist * dyn_freq - (time * dyn_speed_mod))
				var displacement: Vector2 = dir * wave * dyn_strength * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], dyn_color, 1.0)

	# Vertical lattice lines
	for j in range(grid_size + 1):
		var points: PackedVector2Array = PackedVector2Array()
		var x: float = j * step_x
		for i in range(grid_size + 1):
			var y: float = i * step_y
			var pt: Vector2 = Vector2(x, y)
			var dist: float = pt.distance_to(center)
			if dist > 0.0 and dyn_strength > 0.01:
				var dir: Vector2 = (pt - center).normalized()
				var wave: float = sin(dist * dyn_freq - (time * dyn_speed_mod))
				var displacement: Vector2 = dir * wave * dyn_strength * (1.0 / (1.0 + dist * 0.004))
				pt += displacement
			points.append(pt)

		for k in range(points.size() - 1):
			draw_line(points[k], points[k+1], dyn_color, 1.0)
