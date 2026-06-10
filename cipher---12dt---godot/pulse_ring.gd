extends Node2D

var radius = 20.0
var expand_speed = 300.0 
var fade_speed = 1.0
var ring: Line2D

func _ready():
	ring = $Ring
	ring.width = 3.0
	ring.antialiased = true
	_draw_circle()

func _process(delta):
	radius += expand_speed * delta
	# Slow down as it expands like a real shockwave
	expand_speed = lerp(expand_speed, 50.0, delta * 2.0) 
	
	var alpha = ring.default_color.a - fade_speed * delta
	if alpha <= 0.0:
		queue_free()
		return
		
	ring.default_color.a = alpha
	_draw_circle()

func _draw_circle():
	ring.clear_points()
	var points = 64 # High-res circle
	for i in range(points + 1):
		var angle = (float(i) / float(points)) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * radius)
