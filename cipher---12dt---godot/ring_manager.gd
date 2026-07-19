extends Node

var ring_scene = preload("res://pulse_ring.tscn")
var spawn_timer = 0.0
var spawn_interval = 0.15
var is_active = false
var screen_center: Vector2
var active_state = 0

func _ready():
	screen_center = get_viewport().get_visible_rect().size / 2.0

func _process(delta):
	if not is_active:
		return

	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_ring()

func start():
	is_active = true
	spawn_timer = spawn_interval

func stop():
	is_active = false

func set_state(s: int):
	active_state = s

func _spawn_ring():
	var ring = ring_scene.instantiate()
	ring.position = screen_center
	get_parent().add_child(ring)
	ring.set_state_color(active_state)
