## CIPHER - Text-to-Speech (TTS) Manager
## Coordinates real-time speech synthesis via ElevenLabs v3 REST API.
## Implements multi-key failover rotation, memory-safe MP3 decoding, and dynamic reverb modulation.
extends Node

const EL_URL: String = "https://api.elevenlabs.io/v1/text-to-speech/"

## Multi-key rotation pool with fresh zero-character accounts prioritized
var api_keys: Array[String] = [
	"sk_4d75df8aef56d417f2078d44e141b191c9f09c13ad2b8833",
	"sk_fcc25ed68c142fa251694f81ce42addb70852d490e32de96",
	"sk_d995f1796d3704f8cc778895b0abf5640a0782a6a14b98b9",
	"sk_0475daf16a29c9bde0384fee862d1b77469494fbeb814ce1"
]
var current_key_idx: int = 0
var last_text_spoken: String = ""
var key_attempts_count: int = 0

## Voice parameters (Bella - warm, natural female profile default)
var active_voice_id: String = "EXAVITQu4vr4xnSDxMaL"
var voice_stability: float = 0.55
var voice_similarity_boost: float = 0.75
var voice_style: float = 0.15

var http: HTTPRequest
var player: AudioStreamPlayer
var reverb: AudioEffectReverb
var current_tension: float = 0.0

signal speech_started(duration: float)
signal speech_finished
signal voice_unavailable

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_audio_received)

	player = AudioStreamPlayer.new()
	if AudioServer.get_bus_index("TTS_Voice") != -1:
		player.bus = "TTS_Voice"
	else:
		player.bus = "Master"
	player.volume_db = 0.0
	add_child(player)
	player.finished.connect(_on_playback_done)

## Initiates streaming text-to-speech generation for AI responses.
func speak(text: String) -> void:
	last_text_spoken = text
	key_attempts_count = 0
	_send_tts_request()

func _send_tts_request() -> void:
	if key_attempts_count >= api_keys.size():
		voice_unavailable.emit()
		var est_len: float = clamp(float(last_text_spoken.length()) * 0.06, 1.5, 7.0)
		speech_started.emit(est_len)
		speech_finished.emit()
		return

	var body = JSON.stringify({
		"text": last_text_spoken,
		"model_id": "eleven_v3",
		"voice_settings": {
			"stability": voice_stability,
			"similarity_boost": voice_similarity_boost,
			"style": voice_style,
			"use_speaker_boost": true
		}
	})

	var headers: PackedStringArray = [
		"xi-api-key: " + api_keys[current_key_idx],
		"Content-Type: application/json",
		"Accept: audio/mpeg"
	]

	http.request(EL_URL + active_voice_id, headers, HTTPClient.METHOD_POST, body)

func _on_audio_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		if response_code in [401, 403, 429]:
			current_key_idx = (current_key_idx + 1) % api_keys.size()
			key_attempts_count += 1
			_send_tts_request()
			return

		voice_unavailable.emit()
		var est_len: float = clamp(float(last_text_spoken.length()) * 0.06, 1.5, 7.0)
		speech_started.emit(est_len)
		speech_finished.emit()
		return

	key_attempts_count = 0

	# Direct in-memory byte buffer decoding into Godot AudioStreamMP3
	var stream: AudioStreamMP3 = AudioStreamMP3.new()
	stream.data = body

	if AudioServer.get_bus_index("TTS_Voice") != -1:
		player.bus = "TTS_Voice"
	else:
		player.bus = "Master"

	player.volume_db = 0.0
	player.stream = stream
	player.play()

	var audio_len: float = stream.get_length()
	if audio_len <= 0.1:
		audio_len = clamp(float(last_text_spoken.length()) * 0.06, 1.5, 7.0)
	speech_started.emit(audio_len)

func _on_playback_done() -> void:
	speech_finished.emit()

func set_voice_parameters(stability: float, similarity: float, style: float) -> void:
	voice_stability = clamp(stability, 0.0, 1.0)
	voice_similarity_boost = clamp(similarity, 0.0, 1.0)
	voice_style = clamp(style, 0.0, 1.0)

func set_voice_id(voice_id: String) -> void:
	active_voice_id = voice_id

func get_reverb_effect() -> AudioEffectReverb:
	if reverb:
		return reverb
	var bus_idx: int = AudioServer.get_bus_index("TTS_Voice")
	if bus_idx != -1:
		reverb = AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectReverb
	return reverb

## Dynamically scales the acoustic reverb parameters based on user vocal tension (0.0 to 1.0).
func set_vocal_tension(tension: float) -> void:
	current_tension = clamp(tension, 0.0, 1.0)
	var rev: AudioEffectReverb = get_reverb_effect()
	if rev:
		rev.room_size = lerp(0.15, 0.75, current_tension)
		rev.wet = lerp(0.0, 0.45, current_tension)

func interrupt() -> void:
	if player and player.playing:
		player.stop()
	if http:
		http.cancel_request()
