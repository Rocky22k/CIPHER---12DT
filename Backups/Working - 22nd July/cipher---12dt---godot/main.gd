extends Node

const IDLE = 0
const LISTENING = 1
const THINKING = 2
const SPEAKING = 3

const NOISE_THRESHOLD = 0.003
const MIN_RECORD_SECONDS = 0.8
const SILENCE_WARNING_SECONDS = 25.0
const SILENCE_CHECK_IN_SECONDS = 30.0

var recording = false
var cipher_speaking = false
var effect: AudioEffectRecord
var spectrum: AudioEffectSpectrumAnalyzerInstance
var record_timer = 0.0
var long_silence_timer = 0.0
var last_pitch_ratio = 1.0 # Will be set by pitch analyzer in Task 5
var accumulated_bass = 0.0
var accumulated_treble = 0.0
var pitch_samples = 0

var stt: Node
var llm: Node
var tts: Node
var aura: Node
var subtitle_panel: PanelContainer
var subtitle_label: RichTextLabel
var subtitle_base_y: float = 0.0
var subtitle_tween: Tween
var settings_panel: Panel
var settings_open = false
var settings_stab_slider: HSlider
var settings_stab_label: Label
var settings_sim_slider: HSlider
var settings_sim_label: Label
var mode_indicator_label: Label
var mic_dropdown: OptionButton
var mode_dropdown: OptionButton
var voice_dropdown: OptionButton

func _ready():
	print("-Booting Cipher Audio Backend-")

	stt = $STTManager
	llm = $LLMManager
	tts = $TTSManager
	aura = $Aura

	_build_ui()
	_load_settings()
	_apply_vignette_shader()

	# Create dynamic TTS Voice bus with reverb
	var tts_bus_name = "TTS_Voice"
	var tts_bus_idx = AudioServer.get_bus_index(tts_bus_name)
	if tts_bus_idx == -1:
		var bus_count = AudioServer.bus_count
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, tts_bus_name)
		AudioServer.set_bus_send(bus_count, "Master")

		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.5
		reverb.wet = 0.15
		reverb.damping = 0.5
		reverb.spread = 1.0
		AudioServer.add_bus_effect(bus_count, reverb, 0)

	# Spawn reactive cosmic background particles
	var starfield = load("res://cosmic_starfield.gd").new()
	add_child(starfield)

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
		player.stop()

	stt.transcription_ready_with_metrics.connect(_on_transcription_metrics)
	stt.transcription_failed.connect(_on_transcription_failed)
	llm.response_ready.connect(_on_response)

	# Await a short timer to let the restored device register and settle in Godot's audio driver
	await get_tree().create_timer(0.2).timeout
	_reboot_mic_stream()


# Living nebula-void background — domain-warped FBM plasma
func _apply_vignette_shader():
	var bg = get_node("Background")
	if bg:
		var bg_shader = Shader.new()
		bg_shader.code = """
shader_type canvas_item;
uniform float time_phase = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(dot(hash2(i + vec2(0,0)), f - vec2(0,0)),
		    dot(hash2(i + vec2(1,0)), f - vec2(1,0)), u.x),
		mix(dot(hash2(i + vec2(0,1)), f - vec2(0,1)),
		    dot(hash2(i + vec2(1,1)), f - vec2(1,1)), u.x), u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * gnoise(p);
		p  *= 2.1;
		a  *= 0.48;
	}
	return v * 0.5 + 0.5;
}

mat2 rot2(float a) {
	float c = cos(a); float s = sin(a);
	return mat2(vec2(c,-s), vec2(s,c));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.778;
	float t = TIME * 0.025 + time_phase;

	// Domain warp layer 1 — slow wide swirls
	vec2 q = vec2(fbm(uv * 1.6 + vec2(0.0,  t)),
	              fbm(uv * 1.6 + vec2(5.2, -t * 0.9)));

	// Domain warp layer 2 — tighter detail
	vec2 r = vec2(fbm(uv * 2.8 + q * 0.9 + vec2(t * 0.6, 1.7)),
	              fbm(uv * 2.8 + q * 0.9 + vec2(8.3, -t * 0.5)));

	float f = fbm(uv * 2.0 + r * 1.1);

	// Dark void palette — deep indigo with purple nebula wisps
	vec3 col = mix(
		vec3(0.01, 0.005, 0.025),    // near-black void
		vec3(0.12, 0.04,  0.24),     // deep indigo
		clamp(f * f * 2.2, 0.0, 1.0)
	);
	col = mix(col,
		vec3(0.22, 0.06, 0.42),      // violet nebula
		clamp(f * f * f * 3.0, 0.0, 1.0)
	);

	// Subtle radial vignette so edges stay deep black
	float edge_fade = 1.0 - smoothstep(0.28, 0.72, length(uv * vec2(0.85, 1.0)));
	col *= edge_fade;

	COLOR = vec4(col, 1.0);
}
		"""
		var bg_mat = ShaderMaterial.new()
		bg_mat.shader = bg_shader
		bg_mat.set_shader_parameter("time_phase", randf() * TAU)
		bg.material = bg_mat

# Dynamically generate clean dropdown menus and subtitle overlay live
func _build_ui():
	# Aesthetic Subtitle Panel Container
	var ui_canvas = CanvasLayer.new()
	add_child(ui_canvas)

	subtitle_panel = PanelContainer.new()
	var screen_size = get_viewport().get_visible_rect().size
	subtitle_panel.position = Vector2(screen_size.x * 0.15, screen_size.y * 0.82)
	subtitle_panel.size = Vector2(screen_size.x * 0.7, screen_size.y * 0.12)
	subtitle_base_y = subtitle_panel.position.y

	var panel_style = StyleBoxEmpty.new()
	subtitle_panel.add_theme_stylebox_override("panel", panel_style)
	ui_canvas.add_child(subtitle_panel)

	# Subtitle RichTextLabel — fixed size, no layout jitter
	subtitle_label = RichTextLabel.new()
	subtitle_label.bbcode_enabled = false
	subtitle_label.fit_content = false
	subtitle_label.clip_contents = false
	subtitle_label.scroll_active = false
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	subtitle_label.add_theme_color_override("default_color", Color(0.94, 0.91, 0.99))
	subtitle_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	subtitle_label.add_theme_constant_override("shadow_offset_x", 0)
	subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	subtitle_label.add_theme_constant_override("shadow_outline_size", 6)
	subtitle_label.add_theme_font_size_override("normal_font_size", 21)

	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.modulate.a = 0.0

	# Settings canvas (reuse same layer)
	var settings_canvas = ui_canvas

	# Settings glyph — semi-transparent, reveals on hover
	var toggle_btn = Button.new()
	toggle_btn.text = "⚙"
	toggle_btn.position = Vector2(16, 16)
	toggle_btn.custom_minimum_size = Vector2(40, 40)
	toggle_btn.modulate.a = 0.18
	settings_canvas.add_child(toggle_btn)
	toggle_btn.pressed.connect(_toggle_settings)
	toggle_btn.mouse_entered.connect(func(): toggle_btn.modulate.a = 0.85)
	toggle_btn.mouse_exited.connect(func(): toggle_btn.modulate.a = 0.18)

	var btn_style2 = StyleBoxEmpty.new()
	toggle_btn.add_theme_stylebox_override("normal", btn_style2)
	toggle_btn.add_theme_stylebox_override("hover", btn_style2)
	toggle_btn.add_theme_stylebox_override("pressed", btn_style2)
	toggle_btn.add_theme_stylebox_override("focus", btn_style2)
	toggle_btn.add_theme_color_override("font_color", Color(0.78, 0.72, 0.92))
	toggle_btn.add_theme_font_size_override("font_size", 26)

	# Settings Slide-out Panel — modern dark glass
	settings_panel = Panel.new()
	settings_panel.position = Vector2(-340, 0)
	settings_panel.size = Vector2(320, get_viewport().get_visible_rect().size.y)

	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.02, 0.09, 0.92)
	p_style.border_width_right = 1
	p_style.border_color = Color(0.28, 0.12, 0.45, 0.35)
	p_style.corner_radius_top_right = 12
	p_style.corner_radius_bottom_right = 12
	settings_panel.add_theme_stylebox_override("panel", p_style)
	settings_canvas.add_child(settings_panel)

	# Settings close button (top-right of settings panel)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.position = Vector2(275, 12)
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.flat = true
	settings_panel.add_child(close_btn)
	close_btn.pressed.connect(_toggle_settings)
	close_btn.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	close_btn.add_theme_font_size_override("font_size", 24)

	# Sub-nodes inside Settings Panel:
	# 1. Mode selection label and OptionButton
	var mode_label = Label.new()
	mode_label.text = "mode"
	mode_label.position = Vector2(28, 36)
	mode_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	mode_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(mode_label)

	mode_dropdown = OptionButton.new()
	mode_dropdown.add_item("Sanctuary (Casual)")
	mode_dropdown.add_item("Scenario (Formal)")
	mode_dropdown.position = Vector2(20, 55)
	mode_dropdown.size = Vector2(260, 35)
	settings_panel.add_child(mode_dropdown)
	mode_dropdown.item_selected.connect(_on_mode_selected)

	# 2. Voice selection label and OptionButton
	var voice_label = Label.new()
	voice_label.text = "voice"
	voice_label.position = Vector2(28, 118)
	voice_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	voice_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(voice_label)

	voice_dropdown = OptionButton.new()
	voice_dropdown.add_item("Bella")
	voice_dropdown.add_item("Charlie")
	voice_dropdown.add_item("Chris")
	voice_dropdown.add_item("River")
	voice_dropdown.add_item("Antoni")
	voice_dropdown.position = Vector2(20, 135)
	voice_dropdown.size = Vector2(260, 35)
	settings_panel.add_child(voice_dropdown)
	voice_dropdown.item_selected.connect(_on_voice_selected)

	# 3. ElevenLabs stability slider and label
	var stab_label = Label.new()
	stab_label.text = "stability  " + ("%.2f" % tts.voice_stability)
	stab_label.position = Vector2(28, 200)
	stab_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	stab_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(stab_label)
	settings_stab_label = stab_label

	var stab_slider = HSlider.new()
	stab_slider.min_value = 0.0
	stab_slider.max_value = 1.0
	stab_slider.step = 0.01
	stab_slider.value = tts.voice_stability
	stab_slider.position = Vector2(20, 215)
	stab_slider.size = Vector2(260, 20)
	settings_panel.add_child(stab_slider)
	settings_stab_slider = stab_slider
	stab_slider.value_changed.connect(func(val):
		stab_label.text = "stability  " + ("%.2f" % val)
		tts.voice_stability = val
	)

	settings_sim_label = Label.new()
	settings_sim_label.text = "similarity  " + ("%.2f" % tts.voice_similarity_boost)
	settings_sim_label.position = Vector2(28, 258)
	settings_sim_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	settings_sim_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(settings_sim_label)

	var sim_slider = HSlider.new()
	sim_slider.min_value = 0.0
	sim_slider.max_value = 1.0
	sim_slider.step = 0.01
	sim_slider.value = tts.voice_similarity_boost
	sim_slider.position = Vector2(20, 270)
	sim_slider.size = Vector2(260, 20)
	settings_panel.add_child(sim_slider)
	settings_sim_slider = sim_slider
	sim_slider.value_changed.connect(func(val):
		settings_sim_label.text = "similarity  " + ("%.2f" % val)
		tts.voice_similarity_boost = val
	)

	# 4. Mic input
	var mic_label = Label.new()
	mic_label.text = "microphone"
	mic_label.position = Vector2(28, 318)
	mic_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	mic_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(mic_label)

	mic_dropdown = OptionButton.new()
	mic_dropdown.position = Vector2(20, 335)
	mic_dropdown.size = Vector2(260, 35)
	mic_dropdown.clip_text = true
	var devices = AudioServer.get_input_device_list()
	for d in devices:
		mic_dropdown.add_item(d)
	var current_dev = AudioServer.input_device
	for i in range(mic_dropdown.item_count):
		if mic_dropdown.get_item_text(i) == current_dev:
			mic_dropdown.select(i)
			break
	settings_panel.add_child(mic_dropdown)
	mic_dropdown.item_selected.connect(_on_mic_selected)

	# Mode indicator — bottom-center, always visible, never intrudes
	mode_indicator_label = Label.new()
	var scr_sz2 = get_viewport().get_visible_rect().size
	mode_indicator_label.position = Vector2(scr_sz2.x * 0.5 - 80, scr_sz2.y - 32)
	mode_indicator_label.size = Vector2(160, 20)
	mode_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_indicator_label.modulate.a = 0.38
	var mode_ind_style = LabelSettings.new()
	mode_ind_style.font_size = 11
	mode_ind_style.font_color = Color(0.72, 0.66, 0.88)
	mode_ind_style.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	mode_ind_style.shadow_offset = Vector2(1, 1)
	mode_indicator_label.label_settings = mode_ind_style
	mode_indicator_label.text = "S A N C T U A R Y"
	settings_canvas.add_child(mode_indicator_label)

func _on_viewport_resize():
	var screen_size = get_viewport().get_visible_rect().size
	if subtitle_panel:
		subtitle_panel.position = Vector2(screen_size.x * 0.15, screen_size.y * 0.82)
		subtitle_panel.size = Vector2(screen_size.x * 0.7, screen_size.y * 0.12)
	if settings_panel:
		settings_panel.size.y = screen_size.y
		if not settings_open:
			settings_panel.position.x = -340
		else:
			settings_panel.position.x = 0
	if mode_indicator_label:
		mode_indicator_label.position = Vector2(screen_size.x * 0.5 - 80, screen_size.y - 32)

func _process(delta):
	var volume = 0.0
	var bass = 0.0
	var treble = 0.0
	if spectrum:
		var magnitude = spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(magnitude, 0.0, 1.0)
		bass = spectrum.get_magnitude_for_frequency_range(80, 250).length()
		treble = spectrum.get_magnitude_for_frequency_range(1000, 4000).length()

	aura.set_volume(volume * 15.0)

	var is_pushing_to_talk = Input.is_physical_key_pressed(KEY_SPACE)

	# Strict PTT Speech Interruption handling (also interrupts during THINKING/LLM generation)
	if cipher_speaking or aura.active_state == THINKING:
		if is_pushing_to_talk:
			_interrupt_cipher()
		return

	# Strict PTT recording check
	if is_pushing_to_talk:
		long_silence_timer = 0.0
		aura.target_tension = 0.0
		if not recording:
			recording = true
			record_timer = 0.0
			accumulated_bass = 0.0
			accumulated_treble = 0.0
			pitch_samples = 0
			if effect:
				effect.set_recording_active(true)
			aura.set_state(LISTENING)
		else:
			record_timer += delta
			accumulated_bass += bass
			accumulated_treble += treble
			pitch_samples += 1
			if bass > 0.0001:
				var ratio = treble / bass
				aura.target_tension = clamp((ratio - 0.5) / 1.5, 0.0, 1.0)
	else:
		if recording:
			recording = false
			aura.target_tension = 0.0
			if effect:
				effect.set_recording_active(false)
				var audio_data = effect.get_recording()
				# Releasing spacebar immediately submits user speech
				if record_timer >= MIN_RECORD_SECONDS:
					if accumulated_bass > 0.01:
						last_pitch_ratio = accumulated_treble / accumulated_bass
					stt.send_audio(audio_data)
					aura.set_state(THINKING)
				else:
					aura.set_state(IDLE)

	if not recording and not cipher_speaking:
		long_silence_timer += delta
		if long_silence_timer >= SILENCE_WARNING_SECONDS and long_silence_timer < SILENCE_CHECK_IN_SECONDS:
			var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5
			aura.target_tension = pulse
		elif long_silence_timer >= SILENCE_CHECK_IN_SECONDS:
			long_silence_timer = 0.0
			aura.target_tension = 0.0
			_cipher_checks_in()

	tts.set_vocal_tension(aura.current_tension)

func _interrupt_cipher():
	print("Speech Interruption triggered by PTT spacebar input.")
	if tts.speech_finished.is_connected(_on_speech_done):
		tts.speech_finished.disconnect(_on_speech_done)

	cipher_speaking = false
	llm.interrupt()
	tts.interrupt()

	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
	subtitle_label.visible_characters = -1

	# Transition directly to recording user input
	recording = true
	record_timer = 0.0
	long_silence_timer = 0.0
	if effect:
		effect.set_recording_active(true)
	aura.set_state(LISTENING)

func _show_subtitles(text: String):
	if subtitle_panel.modulate.a > 0.05:
		_drift_out_subtitles(func(): _begin_typewriter(text))
	else:
		_begin_typewriter(text)

func _begin_typewriter(text: String):
	subtitle_panel.position.y = subtitle_base_y
	subtitle_label.text = text
	subtitle_label.visible_characters = 0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(subtitle_panel, "modulate:a", 1.0, 0.25)

	var char_count = text.length()
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
	subtitle_tween = create_tween()
	subtitle_tween.tween_property(subtitle_label, "visible_characters", char_count, clamp(char_count * 0.028, 0.8, 6.0))

func _drift_out_subtitles(on_complete: Callable):
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_y = subtitle_base_y - 38.0
	tween.tween_property(subtitle_panel, "position:y", target_y, 0.45)
	tween.tween_property(subtitle_panel, "modulate:a", 0.0, 0.45)
	
	tween.chain().tween_callback(func():
		on_complete.call()
	)

func _hide_subtitles():
	var tween = create_tween()
	tween.tween_property(subtitle_panel, "modulate:a", 0.0, 0.5)

func _cipher_checks_in():
	aura.set_state(THINKING)
	llm.say_silently("The user has been quiet for a while. Gently check in with one short, warm sentence.")

func _on_transcription_metrics(text: String, filler_count: int, wpm: float):
	print("You said: " + text)

	# Determine vocal tension classification
	var tension_str = "Moderate"
	if last_pitch_ratio > 1.3:
		tension_str = "High"
	elif last_pitch_ratio < 0.8:
		tension_str = "Low"

	# Determine pace classification
	var pace_str = "Ideal"
	if wpm > 160.0:
		pace_str = "Fast"
	elif wpm < 110.0:
		pace_str = "Slow"

	var telemetry_text = "[System Telemetry: Pace: %s (%d WPM), Hesitations: %d, Vocal Tension: %s] User says: %s" % [pace_str, int(wpm), filler_count, tension_str, text]
	print("Sending to LLM with telemetry: ", telemetry_text)
	llm.ask(telemetry_text)

func _on_transcription_failed():
	recording = false
	last_pitch_ratio = 1.0
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

func _toggle_settings():
	settings_open = !settings_open
	var tween = create_tween()
	var target_x = 0 if settings_open else -340
	tween.tween_property(settings_panel, "position:x", target_x, 0.3)

func _on_mode_selected(index: int):
	if index == 0:
		llm.set_mode("Sanctuary")
		tts.set_voice_parameters(0.42, 0.75, 0.3)
		if mode_indicator_label:
			mode_indicator_label.text = "S A N C T U A R Y"
	else:
		llm.set_mode("Scenario")
		tts.set_voice_parameters(0.75, 0.85, 0.1)
		if mode_indicator_label:
			mode_indicator_label.text = "S C E N A R I O"

	# Update the stability and similarity sliders to match the defaults for this mode
	if settings_stab_slider and settings_stab_label:
		settings_stab_slider.value = tts.voice_stability
		settings_stab_label.text = "stability  " + ("%.2f" % tts.voice_stability)
	if settings_sim_slider and settings_sim_label:
		settings_sim_slider.value = tts.voice_similarity_boost
		settings_sim_label.text = "similarity  " + ("%.2f" % tts.voice_similarity_boost)
	_save_settings()

func _on_voice_selected(index: int):
	var voice_ids = [
		"EXAVITQu4vr4xnSDxMaL", # Bella
		"IKne3meq5aSn9XLyUdCD", # Charlie
		"iP95p4xoKVk53GoZ742B", # Chris
		"SAz9YHcvj6GT2YYXdXww", # River
		"ErXwobaYiN019PkySvjV", # Antoni
	]
	tts.set_voice_id(voice_ids[index])
	_save_settings()

func _on_mic_selected(index: int):
	var device_name = mic_dropdown.get_item_text(index)
	AudioServer.input_device = device_name
	_save_settings()
	print("Mic switched to: " + device_name)
	await get_tree().create_timer(0.2).timeout
	_reboot_mic_stream()

func _reboot_mic_stream() -> void:
	var player = $AudioStreamPlayer
	if player:
		player.stop()
		player.stream = AudioStreamMicrophone.new()
		player.play()

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "input_device", AudioServer.input_device)
	if mode_dropdown:
		config.set_value("session", "conversational_mode", mode_dropdown.selected)
	if voice_dropdown:
		config.set_value("session", "voice_profile", voice_dropdown.selected)
	config.set_value("session", "voice_stability", tts.voice_stability)
	config.set_value("session", "voice_similarity", tts.voice_similarity_boost)
	var err = config.save("user://settings.cfg")
	if err == OK:
		print("Settings saved successfully.")
	else:
		print("Failed to save settings: ", err)

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		var saved_device = config.get_value("audio", "input_device", "")
		var devices = AudioServer.get_input_device_list()
		if saved_device != "" and saved_device in devices:
			AudioServer.input_device = saved_device
			print("Restored audio input device: ", saved_device)
			if mic_dropdown:
				for i in range(mic_dropdown.item_count):
					if mic_dropdown.get_item_text(i) == saved_device:
						mic_dropdown.select(i)
						break

		var saved_mode = config.get_value("session", "conversational_mode", 0)
		if mode_dropdown:
			mode_dropdown.select(saved_mode)
			_on_mode_selected(saved_mode)

		var saved_voice = config.get_value("session", "voice_profile", 0)
		if voice_dropdown:
			voice_dropdown.select(saved_voice)
			_on_voice_selected(saved_voice)

		var saved_stab = config.get_value("session", "voice_stability", -1.0)
		if saved_stab >= 0.0:
			tts.voice_stability = saved_stab
			if settings_stab_slider:
				settings_stab_slider.value = saved_stab
			if settings_stab_label:
				settings_stab_label.text = "stability  " + ("%.2f" % saved_stab)

		var saved_sim = config.get_value("session", "voice_similarity", -1.0)
		if saved_sim >= 0.0:
			tts.voice_similarity_boost = saved_sim
			if settings_sim_slider:
				settings_sim_slider.value = saved_sim
			if settings_sim_label:
				settings_sim_label.text = "similarity  " + ("%.2f" % saved_sim)
	else:
		print("No settings file found, using defaults: ", AudioServer.input_device)
