extends Node

const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

const NOISE_THRESHOLD = 0.003
const MIN_RECORD_SECONDS = 0.8
const LONG_SILENCE_SECONDS = 60.0

var recording = false
var cipher_speaking = false
var effect: AudioEffectRecord
var spectrum: AudioEffectSpectrumAnalyzerInstance
var record_timer = 0.0
var long_silence_timer = 0.0

var stt: Node
var llm: Node
var tts: Node
var aura: Node
var rings: Node
var mic_dropdown: OptionButton
var subtitle_label: Label

func _ready():
	print("-Booting Cipher Audio Backend-")

	stt = $STTManager
	llm = $LLMManager
	tts = $TTSManager
	aura = $Aura
	rings = $RingManager

	_build_ui()
	_apply_vignette_shader()
	get_viewport().size_changed.connect(_on_viewport_resize)

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

	stt.transcription_ready.connect(_on_transcription)
	stt.transcription_failed.connect(_on_transcription_failed)
	llm.response_ready.connect(_on_response)

# Dynamically compile and apply a subtle radial vignette void background
func _apply_vignette_shader():
	var bg = get_node("Background")
	if bg:
		var bg_shader = Shader.new()
		bg_shader.code = """
		shader_type canvas_item;
		void fragment() {
			vec2 uv = UV - 0.5;
			float dist = length(uv);
			vec3 center_color = vec3(0.03, 0.02, 0.07); // Deep dark violet void
			vec3 edge_color = vec3(0.0, 0.0, 0.0); // Black
			vec3 final_color = mix(center_color, edge_color, smoothstep(0.1, 0.6, dist));
			COLOR = vec4(final_color, 1.0);
		}
		"""
		var bg_mat = ShaderMaterial.new()
		bg_mat.shader = bg_shader
		bg.material = bg_mat

# Dynamically generate clean dropdown menus and subtitle overlay live
func _build_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# Mic Dropdown (Left aligned)
	mic_dropdown = OptionButton.new()
	mic_dropdown.position = Vector2(20, 20)
	mic_dropdown.custom_minimum_size = Vector2(200, 40)
	canvas.add_child(mic_dropdown)

	var devices = AudioServer.get_input_device_list()
	for d in devices:
		mic_dropdown.add_item(d)
	mic_dropdown.item_selected.connect(_on_mic_selected)

	# Subtitle Overlay
	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	var screen_size = get_viewport().get_visible_rect().size
	subtitle_label.position = Vector2(screen_size.x * 0.1, screen_size.y * 0.8)
	subtitle_label.size = Vector2(screen_size.x * 0.8, screen_size.y * 0.15)

	# Clean high-contrast dropshadow styling for accessibility over the shader
	subtitle_label.add_theme_color_override("font_color", Color.WHITE)
	subtitle_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	subtitle_label.add_theme_constant_override("shadow_outline_size", 4)
	subtitle_label.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle_label.add_theme_constant_override("outline_size", 8)
	subtitle_label.add_theme_font_size_override("font_size", 22)

	subtitle_label.modulate.a = 0.0 # Hidden initially
	canvas.add_child(subtitle_label)

func _on_viewport_resize():
	var screen_size = get_viewport().get_visible_rect().size
	if subtitle_label:
		subtitle_label.position = Vector2(screen_size.x * 0.1, screen_size.y * 0.8)
		subtitle_label.size = Vector2(screen_size.x * 0.8, screen_size.y * 0.15)

func _on_mic_selected(index: int):
	var device_name = mic_dropdown.get_item_text(index)
	AudioServer.input_device = device_name
	print("Hardware overridden. Switched to: " + device_name)

func _process(delta):
	var volume = 0.0
	if spectrum:
		var magnitude = spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(magnitude, 0.0, 1.0)

	aura.set_volume(volume * 15.0)

	var is_pushing_to_talk = Input.is_physical_key_pressed(KEY_SPACE)

	# Strict PTT Speech Interruption handling
	if cipher_speaking:
		if is_pushing_to_talk:
			_interrupt_cipher()
		return

	# Strict PTT recording check
	if is_pushing_to_talk:
		long_silence_timer = 0.0
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
		if recording:
			recording = false
			rings.stop()
			if effect:
				effect.set_recording_active(false)
				var audio_data = effect.get_recording()
				# Releasing spacebar immediately submits user speech
				if record_timer >= MIN_RECORD_SECONDS:
					stt.send_audio(audio_data)
					aura.set_state(THINKING)
				else:
					aura.set_state(IDLE)

	if not recording and not cipher_speaking:
		long_silence_timer += delta
		if long_silence_timer >= LONG_SILENCE_SECONDS:
			long_silence_timer = 0.0
			_cipher_checks_in()

func _interrupt_cipher():
	print("Speech Interruption triggered by PTT spacebar input.")
	if tts.speech_finished.is_connected(_on_speech_done):
		tts.speech_finished.disconnect(_on_speech_done)

	cipher_speaking = false
	tts.interrupt()
	_hide_subtitles()

	# Transition directly to recording user input
	recording = true
	record_timer = 0.0
	long_silence_timer = 0.0
	if effect:
		effect.set_recording_active(true)
	aura.set_state(LISTENING)
	rings.start()

func _show_subtitles(text: String):
	subtitle_label.text = text
	var tween = create_tween()
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.4)

func _hide_subtitles():
	var tween = create_tween()
	tween.tween_property(subtitle_label, "modulate:a", 0.0, 0.6)

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

	# Show subtitles
	_show_subtitles(reply)

	if not tts.speech_finished.is_connected(_on_speech_done):
		tts.speech_finished.connect(_on_speech_done, CONNECT_ONE_SHOT)
	tts.speak(reply)

func _on_speech_done():
	# Clean up only if we weren't interrupted by user speaking first
	if cipher_speaking:
		cipher_speaking = false
		aura.set_state(IDLE)
		_hide_subtitles()
