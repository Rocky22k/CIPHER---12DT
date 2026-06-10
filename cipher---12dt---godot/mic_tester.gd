extends Node2D

var devices = []
var current_device_index = 0
var is_testing = false
var test_timer = 0.0
var max_test_time = 3.0 # Record 3 seconds per mic
var effect: AudioEffectRecord

func _ready():
	print("--- BEGINNING CLEAN-ROOM MIC DIAGNOSTIC ---")
	devices = AudioServer.get_input_device_list()
	
	if devices.is_empty():
		print("FATAL ERROR: No microphones found. Is audio/driver/enable_input set to true in Project Settings?")
		return
		
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx == -1:
		print("FATAL ERROR: Record bus not found.")
		return
		
	# Find the record effect on the bus
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var fx = AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectRecord:
			effect = fx
			
	if not effect:
		print("FATAL ERROR: AudioEffectRecord not found on Record bus.")
		return
		
	# Bind a fresh microphone stream
	$AudioStreamPlayer2D.stream = AudioStreamMicrophone.new()
	$AudioStreamPlayer2D.play()
	
	print("Found " + str(devices.size()) + " devices. Starting tests...")
	_start_next_test()

func _start_next_test():
	if current_device_index >= devices.size():
		print("--- DIAGNOSTIC COMPLETE ---")
		print("Check your Desktop for the .wav files!")
		get_tree().quit()
		return
		
	var device_name = devices[current_device_index]
	print("\nTesting Device [" + str(current_device_index) + "]: " + device_name)
	
	AudioServer.input_device = device_name
	
	# Small delay to let OS switch devices
	await get_tree().create_timer(0.5).timeout
	
	test_timer = 0.0
	is_testing = true
	effect.set_recording_active(true)
	print("  Recording...")

func _process(delta):
	if not is_testing:
		return
		
	test_timer += delta
	if test_timer >= max_test_time:
		is_testing = false
		effect.set_recording_active(false)
		print("  Recording stopped. Saving file...")
		_save_recording()

func _save_recording():
	var recording = effect.get_recording()
	if recording and not recording.data.is_empty():
		# Format filename safely
		var safe_name = devices[current_device_index].validate_filename()
		
		# Save to desktop using OS method
		var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		var file_path = desktop_path + "/mic_test_" + str(current_device_index) + "_" + safe_name + ".wav"
		
		var err = recording.save_to_wav(file_path)
		if err == OK:
			print("  SUCCESS: Saved to " + file_path)
			print("  Byte Size: " + str(recording.data.size()) + " bytes")
		else:
			print("  ERROR: Failed to save WAV file. Code: " + str(err))
	else:
		print("  FAILURE: Godot returned empty audio data for this device.")
		
	current_device_index += 1
	_start_next_test()
