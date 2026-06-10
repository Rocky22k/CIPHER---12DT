extends Node

const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

const NOISE_THRESHOLD = 0.003 
const SILENCE_CUTOFF = 2.0
const MIN_RECORD_SECONDS = 0.8
const LONG_SILENCE_SECONDS = 60.0

var recording = false
var cipher_speaking = false
var effect: AudioEffectRecord
var spectrum: AudioEffectSpectrumAnalyzerInstance
var silence_timer = 0.0
var record_timer = 0.0
var long_silence_timer = 0.0

var stt: Node
var llm: Node
var tts: Node
var aura: Node
var rings: Node
var mic_dropdown: OptionButton

func _ready():
	print("--- Booting Cipher Audio Backend ---")
	_build_ui()
	
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx != -1:
		var fx_count = AudioServer.get_bus_effect_count(bus_idx)
		for i in range(fx_count):
			var fx = AudioServer.get_bus_effect(bus_idx, i)
			if fx is AudioEffectRecord:
				effect = fx
				
		spectrum = AudioServer.get_bus_effect_instance(bus_idx, 1)

	var player = $AudioStreamPlayer
	if player:
		player.stream = AudioStreamMicrophone.new()
		player.play()
	
	stt = $STTManager
	llm = $LLMManager
	tts = $TTSManager
	aura = $Aura
	rings = $RingManager

	stt.transcription_ready.connect(_on_transcription)
	stt.transcription_failed.connect(_on_transcription_failed)
	llm.response_ready.connect(_on_response)

# Dynamically generate a dropdown menu to select microphones live
func _build_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	mic_dropdown = OptionButton.new()
	mic_dropdown.position = Vector2(20, 20)
	mic_dropdown.custom_minimum_size = Vector2(300, 40)
	canvas.add_child(mic_dropdown)
	
	var devices = AudioServer.get_input_device_list()
	for d in devices:
		mic_dropdown.add_item(d)
		
	mic_dropdown.item_selected.connect(_on_mic_selected)

func _on_mic_selected(index: int):
	var device_name = mic_dropdown.get_item_text(index)
	AudioServer.input_device = device_name
	print("Hardware overridden. Switched to: " + device_name)
	
	# Reboot the capture stream on the new device
	var player = $AudioStreamPlayer
	if player:
		player.stop()
		player.stream = AudioStreamMicrophone.new()
		player.play()

func _process(delta):
	var volume = 0.0
	if spectrum:
		var magnitude = spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(magnitude, 0.0, 1.0)
	
	aura.set_volume(volume * 15.0) 
	
	if cipher_speaking:
		return

	var is_pushing_to_talk = Input.is_physical_key_pressed(KEY_SPACE)

	if volume > NOISE_THRESHOLD or is_pushing_to_talk:
		long_silence_timer = 0.0
		silence_timer = 0.0

		if not recording:
			recording = true
			record_timer = 0.0
			if effect:
				effect.set_recording_active(true)
			aura.set_state(LISTENING)
			rings.start()
		else:
			record_timer += delta
	else:
		silence_timer += delta

		if recording and silence_timer >= SILENCE_CUTOFF:
			recording = false
			rings.stop()

			if record_timer >= MIN_RECORD_SECONDS:
				if effect:
					effect.set_recording_active(false)
					var audio_data = effect.get_recording()
					stt.send_audio(audio_data)
				aura.set_state(THINKING)
			else:
				if effect:
					effect.set_recording_active(false)
				aura.set_state(IDLE)

	if not recording and not cipher_speaking:
		long_silence_timer += delta
		if long_silence_timer >= LONG_SILENCE_SECONDS:
			long_silence_timer = 0.0
			_cipher_checks_in()

func _cipher_checks_in():
	aura.set_state(THINKING)
	llm.say_silently("The user has been quiet for a while. Gently check in with one short, warm sentence.")

func _on_transcription(text: String):
	print("You said: " + text)
	llm.ask(text)

func _on_transcription_failed():
	recording = false
	aura.set_state(IDLE)

func _on_response(reply: String):
	print("Cipher: " + reply)
	cipher_speaking = true
	aura.set_state(SPEAKING)
	tts.speech_finished.connect(_on_speech_done, CONNECT_ONE_SHOT)
	tts.speak(reply)

func _on_speech_done():
	cipher_speaking = false
	aura.set_state(IDLE)
