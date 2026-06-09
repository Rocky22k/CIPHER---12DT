extends Node

var recording: bool = false
var effect: AudioEffectRecord
var silence_timer: float = 0.0
var silence_threshold: float = 2.0

func _ready() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(bus_idx, 0)

func _process(delta: float) -> void:
	var volume_db: float = AudioServer.get_bus_peak_volume_left_db(
		AudioServer.get_bus_index("Record"), 0
	)
	var volume_linear: float = db_to_linear(volume_db)

	print("Volume: %.3f" % volume_linear)

	if volume_linear > 0.02:
		silence_timer = 0.0
		if not recording:
			recording = true
			effect.set_recording_active(true)
			print("--- User speaking ---")
	else:
		silence_timer += delta
		if recording and silence_timer >= silence_threshold:
			recording = false
			effect.set_recording_active(false)
			print("--- Silence detected. Processing. ---")
			var audio_data: AudioStreamWAV = effect.get_recording()
			print("Audio captured. Sample rate: %d" % audio_data.mix_rate)
