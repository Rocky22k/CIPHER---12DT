## CIPHER - Main Architecture Coordinator & Audio-Visual Engine
## Coordinates the bio-reactive pipeline: STT Audio Gating -> Groq LLM -> ElevenLabs TTS
## Manages state synchronization, dynamic audio bus routing, and UI presentation.
extends Node

const IDLE: int = 0
const LISTENING: int = 1
const THINKING: int = 2
const SPEAKING: int = 3

const NOISE_THRESHOLD: float = 0.003
const MIN_RECORD_SECONDS: float = 0.8
const SILENCE_WARNING_SECONDS: float = 25.0
const SILENCE_CHECK_IN_SECONDS: float = 30.0

var recording: bool = false
var cipher_speaking: bool = false
var effect: AudioEffectRecord
var spectrum: AudioEffectSpectrumAnalyzerInstance
var record_timer: float = 0.0
var long_silence_timer: float = 0.0
var last_pitch_ratio: float = 1.0
var accumulated_bass: float = 0.0
var accumulated_treble: float = 0.0
var pitch_samples: int = 0

var stt: Node
var llm: Node
var tts: Node
var aura: Node
var subtitle_panel: PanelContainer
var subtitle_label: RichTextLabel
var subtitle_base_y: float = 0.0
var subtitle_tween: Tween
var hint_label: Label
var hint_shown: bool = false
var settings_panel: Panel
var settings_open: bool = false
var settings_stab_slider: HSlider
var settings_stab_label: Label
var settings_sim_slider: HSlider
var settings_sim_label: Label
var mode_indicator_label: Label
var mic_dropdown: OptionButton
var mode_dropdown: OptionButton
var voice_dropdown: OptionButton
var tts_spectrum: AudioEffectSpectrumAnalyzerInstance
var session_utterance_count: int = 0
var mic_muted: bool = false
var session_valence: float = 0.5
var silence_warning_seconds: float = 25.0
var silence_check_in_seconds: float = 30.0
var last_subtitle_text: String = ""
var last_wpm: float = 130.0

func _ready() -> void:
	stt = $STTManager
	llm = $LLMManager
	tts = $TTSManager
	aura = $Aura

	_build_ui()
	_load_settings()
	_apply_velvety_background_shader()

	# Create dynamic TTS Voice bus with reverb for acoustic depth
	var tts_bus_name: String = "TTS_Voice"
	var tts_bus_idx: int = AudioServer.get_bus_index(tts_bus_name)
	if tts_bus_idx == -1:
		var bus_count: int = AudioServer.bus_count
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, tts_bus_name)
		AudioServer.set_bus_send(bus_count, "Master")
		AudioServer.set_bus_volume_db(bus_count, 0.0)
		AudioServer.set_bus_mute(bus_count, false)

		var reverb: AudioEffectReverb = AudioEffectReverb.new()
		reverb.room_size = 0.5
		reverb.wet = 0.15
		reverb.damping = 0.5
		reverb.spread = 1.0
		AudioServer.add_bus_effect(bus_count, reverb, 0)

		var tts_sa: AudioEffectSpectrumAnalyzer = AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_count, tts_sa, 1)

	var tts_b_idx: int = AudioServer.get_bus_index("TTS_Voice")
	if tts_b_idx != -1:
		tts_spectrum = AudioServer.get_bus_effect_instance(tts_b_idx, 1)

	# Deep chromatic starfield layer
	var starfield = load("res://scripts/cosmic_starfield.gd").new()
	add_child(starfield)

	get_viewport().size_changed.connect(_on_viewport_resize)

	# Hook into the microphone input bus for real-time frequency analysis
	var bus_idx: int = AudioServer.get_bus_index("Record")
	if bus_idx != -1:
		var fx_count: int = AudioServer.get_bus_effect_count(bus_idx)
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

	if tts.has_signal("speech_started"):
		tts.speech_started.connect(_on_speech_started)
	if tts.has_signal("voice_unavailable"):
		tts.voice_unavailable.connect(_on_voice_unavailable)

	# Delayed onboarding hint fade-in (2.0s after clean launch)
	get_tree().create_timer(2.0).timeout.connect(func():
		if not hint_shown and hint_label:
			var ht = create_tween()
			ht.tween_property(hint_label, "modulate:a", 0.65, 0.8)
	)

	# Allow hardware audio driver to settle before initializing microphone stream
	await get_tree().create_timer(0.2).timeout
	_reboot_mic_stream()

## Applies the smooth, undulating Aurora horizon shader from shaders/background.gdshader.
func _apply_velvety_background_shader() -> void:
	var bg = get_node_or_null("Background")
	if bg:
		var bg_shader = load("res://shaders/background.gdshader")
		if bg_shader:
			var bg_mat = ShaderMaterial.new()
			bg_mat.shader = bg_shader
			bg_mat.set_shader_parameter("time_phase", randf() * TAU)
			bg_mat.set_shader_parameter("speed", 0.35)
			bg_mat.set_shader_parameter("amplitude", 0.85)
			bg_mat.set_shader_parameter("blend", 0.45)
			bg_mat.set_shader_parameter("valence", 0.5)
			bg.material = bg_mat

func _build_ui() -> void:
	var ui_canvas: CanvasLayer = CanvasLayer.new()
	add_child(ui_canvas)

	# Subtitle Container positioned comfortably in the lower area with auto-scrolling
	subtitle_panel = PanelContainer.new()
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	subtitle_panel.position = Vector2(screen_size.x * 0.12, screen_size.y * 0.82)
	subtitle_panel.size = Vector2(screen_size.x * 0.76, screen_size.y * 0.13)
	subtitle_base_y = subtitle_panel.position.y

	var panel_style: StyleBoxEmpty = StyleBoxEmpty.new()
	subtitle_panel.add_theme_stylebox_override("panel", panel_style)
	ui_canvas.add_child(subtitle_panel)

	subtitle_label = RichTextLabel.new()
	subtitle_label.bbcode_enabled = true
	subtitle_label.fit_content = false
	subtitle_label.clip_contents = true
	subtitle_label.scroll_active = true
	subtitle_label.scroll_following = true # Auto-scrolls vertically as text reveals
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	subtitle_label.add_theme_color_override("default_color", Color(0.96, 0.94, 1.0))
	subtitle_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	subtitle_label.add_theme_constant_override("shadow_offset_x", 0)
	subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	subtitle_label.add_theme_constant_override("shadow_outline_size", 6)
	subtitle_label.add_theme_font_size_override("normal_font_size", 20)

	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.modulate.a = 0.0

	var settings_canvas = ui_canvas

	# Settings toggle button (Top-left gear icon)
	var toggle_btn: Button = Button.new()
	toggle_btn.text = "⚙"
	toggle_btn.position = Vector2(16, 16)
	toggle_btn.custom_minimum_size = Vector2(40, 40)
	toggle_btn.modulate.a = 0.18
	toggle_btn.focus_mode = Control.FOCUS_NONE
	settings_canvas.add_child(toggle_btn)
	toggle_btn.pressed.connect(_toggle_settings)
	toggle_btn.mouse_entered.connect(func(): toggle_btn.modulate.a = 0.85)
	toggle_btn.mouse_exited.connect(func(): toggle_btn.modulate.a = 0.18)

	var btn_style2: StyleBoxEmpty = StyleBoxEmpty.new()
	toggle_btn.add_theme_stylebox_override("normal", btn_style2)
	toggle_btn.add_theme_stylebox_override("hover", btn_style2)
	toggle_btn.add_theme_stylebox_override("pressed", btn_style2)
	toggle_btn.add_theme_stylebox_override("focus", btn_style2)
	toggle_btn.add_theme_color_override("font_color", Color(0.78, 0.72, 0.92))
	toggle_btn.add_theme_font_size_override("font_size", 26)

	# Settings slide-out panel (Dark glass aesthetic)
	settings_panel = Panel.new()
	settings_panel.position = Vector2(-340, 0)
	settings_panel.size = Vector2(320, get_viewport().get_visible_rect().size.y)

	var p_style: StyleBoxFlat = StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.02, 0.09, 0.92)
	p_style.border_width_right = 1
	p_style.border_color = Color(0.28, 0.12, 0.45, 0.35)
	p_style.corner_radius_top_right = 12
	p_style.corner_radius_bottom_right = 12
	settings_panel.add_theme_stylebox_override("panel", p_style)
	settings_canvas.add_child(settings_panel)

	var close_btn: Button = Button.new()
	close_btn.text = "×"
	close_btn.position = Vector2(275, 12)
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	settings_panel.add_child(close_btn)
	close_btn.pressed.connect(_close_settings)
	close_btn.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	close_btn.add_theme_font_size_override("font_size", 24)

	var mode_label: Label = Label.new()
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
	mode_dropdown.focus_mode = Control.FOCUS_NONE
	settings_panel.add_child(mode_dropdown)
	mode_dropdown.item_selected.connect(_on_mode_selected)

	var voice_label: Label = Label.new()
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
	voice_dropdown.focus_mode = Control.FOCUS_NONE
	settings_panel.add_child(voice_dropdown)
	voice_dropdown.item_selected.connect(_on_voice_selected)

	var stab_label: Label = Label.new()
	stab_label.text = "stability  " + ("%.2f" % tts.voice_stability)
	stab_label.position = Vector2(28, 200)
	stab_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	stab_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(stab_label)
	settings_stab_label = stab_label

	var stab_slider: HSlider = HSlider.new()
	stab_slider.min_value = 0.0
	stab_slider.max_value = 1.0
	stab_slider.step = 0.01
	stab_slider.value = tts.voice_stability
	stab_slider.position = Vector2(20, 215)
	stab_slider.size = Vector2(260, 20)
	stab_slider.focus_mode = Control.FOCUS_NONE
	settings_panel.add_child(stab_slider)
	settings_stab_slider = stab_slider
	stab_slider.value_changed.connect(func(val: float):
		stab_label.text = "stability  " + ("%.2f" % val)
		tts.voice_stability = val
	)

	settings_sim_label = Label.new()
	settings_sim_label.text = "similarity  " + ("%.2f" % tts.voice_similarity_boost)
	settings_sim_label.position = Vector2(28, 258)
	settings_sim_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	settings_sim_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(settings_sim_label)

	var sim_slider: HSlider = HSlider.new()
	sim_slider.min_value = 0.0
	sim_slider.max_value = 1.0
	sim_slider.step = 0.01
	sim_slider.value = tts.voice_similarity_boost
	sim_slider.position = Vector2(20, 270)
	sim_slider.size = Vector2(260, 20)
	sim_slider.focus_mode = Control.FOCUS_NONE
	settings_panel.add_child(sim_slider)
	settings_sim_slider = sim_slider
	sim_slider.value_changed.connect(func(val: float):
		settings_sim_label.text = "similarity  " + ("%.2f" % val)
		tts.voice_similarity_boost = val
	)

	var mic_label: Label = Label.new()
	mic_label.text = "microphone"
	mic_label.position = Vector2(28, 318)
	mic_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.72))
	mic_label.add_theme_font_size_override("font_size", 11)
	settings_panel.add_child(mic_label)

	mic_dropdown = OptionButton.new()
	mic_dropdown.position = Vector2(20, 335)
	mic_dropdown.size = Vector2(260, 35)
	mic_dropdown.clip_text = true
	mic_dropdown.focus_mode = Control.FOCUS_NONE
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	for d in devices:
		mic_dropdown.add_item(d)
	var current_dev: String = AudioServer.input_device
	for i in range(mic_dropdown.item_count):
		if mic_dropdown.get_item_text(i) == current_dev:
			mic_dropdown.select(i)
			break
	settings_panel.add_child(mic_dropdown)
	mic_dropdown.item_selected.connect(_on_mic_selected)

	# Mode indicator (bottom-center)
	mode_indicator_label = Label.new()
	var scr_sz2: Vector2 = get_viewport().get_visible_rect().size
	mode_indicator_label.position = Vector2(scr_sz2.x * 0.5 - 80, scr_sz2.y - 32)
	mode_indicator_label.size = Vector2(160, 20)
	mode_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_indicator_label.modulate.a = 0.38
	var mode_ind_style: LabelSettings = LabelSettings.new()
	mode_ind_style.font_size = 11
	mode_ind_style.font_color = Color(0.72, 0.66, 0.88)
	mode_ind_style.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	mode_ind_style.shadow_offset = Vector2(1, 1)
	mode_indicator_label.label_settings = mode_ind_style
	mode_indicator_label.text = "S A N C T U A R Y"
	settings_canvas.add_child(mode_indicator_label)

	# First-launch onboarding hint label (fades in after 2s, dismisses on first voice input)
	hint_label = Label.new()
	hint_label.position = Vector2(scr_sz2.x * 0.5 - 120, scr_sz2.y - 56)
	hint_label.size = Vector2(240, 20)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.modulate.a = 0.0
	var hint_style: LabelSettings = LabelSettings.new()
	hint_style.font_size = 11
	hint_style.font_color = Color(0.85, 0.80, 0.95)
	hint_style.shadow_color = Color(0.0, 0.0, 0.0, 0.8)
	hint_style.shadow_offset = Vector2(1, 1)
	hint_label.label_settings = hint_style
	hint_label.text = "HOLD SPACE TO SPEAK"
	settings_canvas.add_child(hint_label)

func _dismiss_hint() -> void:
	if not hint_shown and hint_label:
		hint_shown = true
		var ht = create_tween()
		ht.tween_property(hint_label, "modulate:a", 0.0, 0.25)
		ht.tween_callback(func(): hint_label.visible = false)

func _on_viewport_resize() -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	if subtitle_panel:
		subtitle_panel.position = Vector2(screen_size.x * 0.12, screen_size.y * 0.82)
		subtitle_panel.size = Vector2(screen_size.x * 0.76, screen_size.y * 0.13)
	if settings_panel:
		settings_panel.size.y = screen_size.y
		if not settings_open:
			settings_panel.position.x = -340
		else:
			settings_panel.position.x = 0
	if mode_indicator_label:
		mode_indicator_label.position = Vector2(screen_size.x * 0.5 - 80, screen_size.y - 32)
	if hint_label:
		hint_label.position = Vector2(screen_size.x * 0.5 - 120, screen_size.y - 56)

func _process(delta: float) -> void:
	var volume: float = 0.0
	var bass: float = 0.0
	var treble: float = 0.0
	if spectrum:
		var magnitude: float = spectrum.get_magnitude_for_frequency_range(20, 20000).length()
		volume = clamp(magnitude, 0.0, 1.0)
		bass = spectrum.get_magnitude_for_frequency_range(80, 250).length()
		treble = spectrum.get_magnitude_for_frequency_range(1000, 4000).length()

	aura.set_volume(volume * 15.0)

	var is_pushing_to_talk: bool = Input.is_physical_key_pressed(KEY_SPACE)

	# Strict PTT Speech Interruption handling (also interrupts during THINKING state)
	if cipher_speaking or aura.active_state == THINKING:
		if is_pushing_to_talk:
			_dismiss_hint()
			_interrupt_cipher()
		return

	# Strict PTT recording check (Spacebar hold to record, release to submit)
	if is_pushing_to_talk:
		_dismiss_hint()
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
				var ratio: float = treble / bass
				aura.target_tension = clamp((ratio - 0.5) / 1.5, 0.0, 1.0)
	else:
		if recording:
			recording = false
			aura.target_tension = 0.0
			if effect:
				effect.set_recording_active(false)
				var audio_data: AudioStreamWAV = effect.get_recording()
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
			var pulse: float = sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5
			aura.target_tension = pulse
		elif long_silence_timer >= silence_check_in_seconds:
			long_silence_timer = 0.0
			aura.target_tension = 0.0
			_cipher_checks_in()

	tts.set_vocal_tension(aura.current_tension)

	# Pulse Aura to Cipher's own voice during SPEAKING state
	if cipher_speaking and tts_spectrum:
		var tts_mag: float = tts_spectrum.get_magnitude_for_frequency_range(200, 4000).length()
		aura.set_volume(clamp(tts_mag * 10.0, 0.0, 1.0))

	# Update background shader parameters smoothly
	var bg = get_node_or_null("Background")
	if bg and bg.material:
		bg.material.set_shader_parameter("valence", session_valence)
		bg.material.set_shader_parameter("amplitude", 0.75 + aura.current_tension * 0.35)

func _interrupt_cipher() -> void:
	if tts.speech_finished.is_connected(_on_speech_done):
		tts.speech_finished.disconnect(_on_speech_done)

	cipher_speaking = false
	llm.interrupt()
	tts.interrupt()

	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
	subtitle_label.visible_characters = -1

	recording = true
	record_timer = 0.0
	long_silence_timer = 0.0
	if effect:
		effect.set_recording_active(true)
	aura.set_state(LISTENING)

func _show_subtitles(text: String) -> void:
	last_subtitle_text = text
	if subtitle_panel.modulate.a > 0.05:
		_drift_out_subtitles(func(): _begin_typewriter(text))
	else:
		_begin_typewriter(text)

## Reveals subtitles with smooth, natural typewriter reveal and auto-scrolling
func _begin_typewriter(text: String) -> void:
	subtitle_panel.position.y = subtitle_base_y
	subtitle_label.text = text
	subtitle_label.visible_characters = 0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(subtitle_panel, "modulate:a", 1.0, 0.25)

	var char_count: int = text.length()
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
	subtitle_tween = create_tween()
	# Readable, constant character reveal speed (~32 chars per second)
	var reveal_duration: float = clamp(float(char_count) / 32.0, 0.8, 8.0)
	subtitle_tween.tween_property(subtitle_label, "visible_characters", char_count, reveal_duration)

func _on_speech_started(_duration: float) -> void:
	pass

func _on_voice_unavailable() -> void:
	pass

func _drift_out_subtitles(on_complete: Callable) -> void:
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_y: float = subtitle_base_y - 38.0
	tween.tween_property(subtitle_panel, "position:y", target_y, 0.45)
	tween.tween_property(subtitle_panel, "modulate:a", 0.0, 0.45)

	tween.chain().tween_callback(func():
		on_complete.call()
	)

func _hide_subtitles() -> void:
	var tween = create_tween()
	tween.tween_property(subtitle_panel, "modulate:a", 0.0, 0.5)

func _cipher_checks_in() -> void:
	aura.set_state(THINKING)
	if llm and llm.has_method("check_in_silently"):
		llm.check_in_silently()
	else:
		llm.say_silently("The user has been quiet for a while. Gently check in with one short, warm sentence.")

func _on_transcription_metrics(text: String, _filler_count: int, wpm: float) -> void:
	print("You said: " + text)
	_dismiss_hint()

	last_wpm = wpm
	var temp: float = clamp(remap(wpm, 110.0, 160.0, 0.70, 1.0), 0.60, 1.05)
	if llm and llm.has_method("set_temperature"):
		llm.set_temperature(temp)

	session_utterance_count += 1
	_update_mode_indicator()

	# Send clean user speech directly to the LLM
	llm.ask(text)

func _on_transcription_failed() -> void:
	recording = false
	last_pitch_ratio = 1.0
	aura.set_state(IDLE)

func _on_response(reply: String) -> void:
	print("Cipher: " + reply)
	cipher_speaking = true
	aura.set_state(SPEAKING)

	var lower_rep: String = reply.to_lower()
	if lower_rep.contains("great") or lower_rep.contains("good") or lower_rep.contains("calm"):
		session_valence = clamp(session_valence + 0.08, 0.1, 1.0)
	elif lower_rep.contains("hard") or lower_rep.contains("stress") or lower_rep.contains("stuck"):
		session_valence = clamp(session_valence - 0.08, 0.1, 1.0)

	_show_subtitles(reply)

	if not tts.speech_finished.is_connected(_on_speech_done):
		tts.speech_finished.connect(_on_speech_done, CONNECT_ONE_SHOT)
	tts.speak(reply)

func _on_speech_done() -> void:
	if cipher_speaking:
		cipher_speaking = false
		aura.set_state(IDLE)

func _toggle_settings() -> void:
	if settings_open:
		_close_settings()
	else:
		_open_settings()

func _open_settings() -> void:
	settings_open = true
	var tween = create_tween()
	tween.tween_property(settings_panel, "position:x", 0.0, 0.3)

func _close_settings() -> void:
	settings_open = false
	var tween = create_tween()
	tween.tween_property(settings_panel, "position:x", -340.0, 0.3)
	get_viewport().gui_release_focus()

func _on_mode_selected(index: int) -> void:
	if index == 0:
		llm.set_mode("Sanctuary")
		tts.set_voice_parameters(0.42, 0.75, 0.3)
		silence_warning_seconds = 30.0
		silence_check_in_seconds = 35.0
		if tts and tts.has_method("set_reverb_mode"): tts.set_reverb_mode("Sanctuary")
	else:
		llm.set_mode("Scenario")
		tts.set_voice_parameters(0.75, 0.85, 0.1)
		silence_warning_seconds = 15.0
		silence_check_in_seconds = 20.0
		if tts and tts.has_method("set_reverb_mode"): tts.set_reverb_mode("Scenario")

	_update_mode_indicator()

	if settings_stab_slider and settings_stab_label:
		settings_stab_slider.value = tts.voice_stability
		settings_stab_label.text = "stability  " + ("%.2f" % tts.voice_stability)
	if settings_sim_slider and settings_sim_label:
		settings_sim_slider.value = tts.voice_similarity_boost
		settings_sim_label.text = "similarity  " + ("%.2f" % tts.voice_similarity_boost)
	_save_settings()

func _on_voice_selected(index: int) -> void:
	var voice_ids: Array[String] = [
		"EXAVITQu4vr4xnSDxMaL",
		"IKne3meq5aSn9XLyUdCD",
		"iP95p4xoKVk53GoZ742B",
		"SAz9YHcvj6GT2YYXdXww",
		"ErXwobaYiN019PkySvjV",
	]
	tts.set_voice_id(voice_ids[index])
	_save_settings()

func _on_mic_selected(index: int) -> void:
	var device_name: String = mic_dropdown.get_item_text(index)
	AudioServer.input_device = device_name
	_save_settings()
	await get_tree().create_timer(0.2).timeout
	_reboot_mic_stream()

func _reboot_mic_stream() -> void:
	var player = $AudioStreamPlayer
	if player:
		player.stop()
		player.stream = AudioStreamMicrophone.new()
		player.play()

const SETTINGS_PASS: String = "CipherSanctuaryPass2026"

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "input_device", AudioServer.input_device)
	if mode_dropdown:
		config.set_value("session", "conversational_mode", mode_dropdown.selected)
	if voice_dropdown:
		config.set_value("session", "voice_profile", voice_dropdown.selected)
	config.set_value("session", "voice_stability", tts.voice_stability)
	config.set_value("session", "voice_similarity", tts.voice_similarity_boost)

	if last_subtitle_text != "":
		config.set_value("session", "last_topic", last_subtitle_text.substr(0, 60))

	config.save_encrypted_pass("user://settings.enc", SETTINGS_PASS)

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load_encrypted_pass("user://settings.enc", SETTINGS_PASS)
	if err != OK:
		err = config.load("user://settings.cfg")

	if err == OK:
		var last_topic: String = config.get_value("session", "last_topic", "")
		if last_topic != "" and llm:
			llm.say_silently("The user previously spoke about: " + last_topic)
		var saved_device: String = config.get_value("audio", "input_device", "")
		var devices: PackedStringArray = AudioServer.get_input_device_list()
		if saved_device != "" and saved_device in devices:
			AudioServer.input_device = saved_device
			if mic_dropdown:
				for i in range(mic_dropdown.item_count):
					if mic_dropdown.get_item_text(i) == saved_device:
						mic_dropdown.select(i)
						break

		var saved_mode: int = config.get_value("session", "conversational_mode", 0)
		if mode_dropdown:
			mode_dropdown.select(saved_mode)
			_on_mode_selected(saved_mode)

		var saved_voice: int = config.get_value("session", "voice_profile", 0)
		if voice_dropdown:
			voice_dropdown.select(saved_voice)
			_on_voice_selected(saved_voice)

		var saved_stab: float = config.get_value("session", "voice_stability", -1.0)
		if saved_stab >= 0.0:
			tts.voice_stability = saved_stab
			if settings_stab_slider:
				settings_stab_slider.value = saved_stab
			if settings_stab_label:
				settings_stab_label.text = "stability  " + ("%.2f" % saved_stab)

		var saved_sim: float = config.get_value("session", "voice_similarity", -1.0)
		if saved_sim >= 0.0:
			tts.voice_similarity_boost = saved_sim
			if settings_sim_slider:
				settings_sim_slider.value = saved_sim
			if settings_sim_label:
				settings_sim_label.text = "similarity  " + ("%.2f" % saved_sim)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.pressed:
			if event.physical_keycode == KEY_M:
				mic_muted = !mic_muted
				if mic_muted:
					if recording:
						recording = false
						if effect:
							effect.set_recording_active(false)
					aura.set_state(IDLE)
				_update_mode_indicator()
			elif event.physical_keycode == KEY_R and not cipher_speaking and not recording:
				if last_subtitle_text != "":
					if subtitle_tween and subtitle_tween.is_valid():
						subtitle_tween.kill()
					subtitle_panel.position.y = subtitle_base_y
					subtitle_label.text = last_subtitle_text
					subtitle_label.visible_characters = -1
					subtitle_panel.modulate.a = 0.72
		else:
			if event.physical_keycode == KEY_R and not cipher_speaking:
				_hide_subtitles()

func _update_mode_indicator() -> void:
	if not mode_indicator_label:
		return
	var base: String = "S A N C T U A R Y" if (mode_dropdown and mode_dropdown.selected == 0) else "S C E N A R I O"
	if mic_muted:
		base += "   ·   [MUTED]"
	elif session_utterance_count > 0:
		base += "   ·   %d" % session_utterance_count
	mode_indicator_label.text = base
