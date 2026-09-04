## CIPHER - Harmonic Pulse Ring Manager
## Spawns subtle state-reactive acoustic pulse rings during voice events.
extends Node

var ring_scene: PackedScene = preload("res://scenes/pulse_ring.tscn")
var spawn_timer: float = 0.0
var spawn_interval: float = 0.15
var is_active: bool = false
var screen_center: Vector2
var active_state: int = 0
var current_wpm: float = 130.0

func _ready() -> void:
	screen_center = get_viewport().get_visible_rect().size / 2.0

func _process(delta: float) -> void:
	if not is_active:
		return

	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_ring()

func start() -> void:
	is_active = true
	spawn_timer = spawn_interval

func stop() -> void:
	is_active = false

func set_state(s: int) -> void:
	active_state = s

func set_wpm(wpm: float) -> void:
	current_wpm = wpm

func _spawn_ring() -> void:
	if not ring_scene:
		return
	var ring = ring_scene.instantiate()
	if ring:
		ring.position = screen_center
		get_parent().add_child(ring)
		if ring.has_method("set_state_color"):
			ring.set_state_color(active_state)
		if ring.has_method("set_wpm"):
			ring.set_wpm(current_wpm)
