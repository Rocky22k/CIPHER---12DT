extends Node2D
# CIPHER: Real-time vocal pitch gauge - 120-degree arc at bottom-right
# Reads treble/bass ratio from parent main.gd spectrum instance.

@onready var main_node = get_parent()
var smoothed_ratio = 0.5  # 0.0=full bass, 1.0=full treble

const ARC_RADIUS = 38.0
const ARC_DEGREES = 120.0
const ARC_START_ANGLE = 150.0  # degrees, bottom-right orientation
const POINT_COUNT = 40

func _ready():
	z_index = 2
	print("[PitchGauge] Vocal pitch gauge node initialized.")

func _process(delta):
	if main_node and "spectrum" in main_node and main_node.spectrum:
		var bass = main_node.spectrum.get_magnitude_for_frequency_range(80, 250).length()
		var treble = main_node.spectrum.get_magnitude_for_frequency_range(1000, 4000).length()
		var raw_ratio = 0.5
		if bass > 0.0001:
			raw_ratio = clamp((treble / bass - 0.5) / 1.5, 0.0, 1.0)
		smoothed_ratio = lerp(smoothed_ratio, raw_ratio, delta * 5.0)
	queue_redraw()

func _draw():
	var screen_size = get_viewport_rect().size
	var center = Vector2(screen_size.x - 58.0, screen_size.y - 58.0)

	# Background arc track
	var track_color = Color(0.18, 0.14, 0.28, 0.30)
	_draw_arc_line(center, ARC_RADIUS, ARC_START_ANGLE, ARC_START_ANGLE + ARC_DEGREES, track_color, 2.0)

	# Fill arc - length proportional to smoothed_ratio
	var fill_degrees = smoothed_ratio * ARC_DEGREES
	# Color shifts: bass = indigo (calm), treble = magenta (tense)
	var fill_color = Color(0.28, 0.04, 0.62, 0.75).lerp(Color(0.88, 0.06, 0.48, 0.85), smoothed_ratio)
	_draw_arc_line(center, ARC_RADIUS, ARC_START_ANGLE, ARC_START_ANGLE + fill_degrees, fill_color, 2.5)

func _draw_arc_line(center: Vector2, r: float, start_deg: float, end_deg: float, color: Color, width: float):
	var points = PackedVector2Array()
	var steps = POINT_COUNT
	for i in range(steps + 1):
		var angle = deg_to_rad(lerp(start_deg, end_deg, float(i) / float(steps)))
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width)
