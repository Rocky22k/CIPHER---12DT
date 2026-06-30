extends Node

const EL_URL = "https://api.elevenlabs.io/v1/text-to-speech/"

# Key rotation pool
var api_keys = [
	"sk_d995f1796d3704f8cc778895b0abf5640a0782a6a14b98b9",
	"sk_0475daf16a29c9bde0384fee862d1b77469494fbeb814ce1",
	"sk_4d75df8aef56d417f2078d44e141b191c9f09c13ad2b8833",
	"sk_fcc25ed68c142fa251694f81ce42addb70852d490e32de96"
]
var current_key_idx = 0
var last_text_spoken = ""
var retry_active = false

# Voice settings (class-level so speak() and external callers can access them)
var active_voice_id = "EXAVITQu4vr4xnSDxMaL"  # "Sarah" - calm, female voice
var voice_stability = 0.6
var voice_similarity_boost = 0.8
var voice_style = 0.2

var http: HTTPRequest
var player: AudioStreamPlayer

signal speech_finished

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_received)

	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_on_playback_done)

func speak(text: String):
	retry_active = false
	last_text_spoken = text
	var body = JSON.stringify({
		"text": text,
		"model_id": "eleven_multilingual_v2",
		"voice_settings": {
			"stability": voice_stability,
			"similarity_boost": voice_similarity_boost,
			"style": voice_style,
			"use_speaker_boost": true
		}
	})

	var headers = [
		"xi-api-key: " + api_keys[current_key_idx],
		"Content-Type: application/json",
		"Accept: audio/mpeg"
	]

	http.request(EL_URL + active_voice_id, headers, HTTPClient.METHOD_POST, body)

func _on_audio_received(_result, response_code, _headers, body):
	if response_code != 200:
		print("ElevenLabs failed with code: %d" % response_code)
		if (response_code == 401 or response_code == 403 or response_code == 429) and not retry_active:
			current_key_idx = (current_key_idx + 1) % api_keys.size()
			print("Rotating ElevenLabs API Key to index: ", current_key_idx)
			retry_active = true
			speak(last_text_spoken)
			return

		retry_active = false
		print(body.get_string_from_utf8())
		speech_finished.emit()
		return

	retry_active = false

	# Save mp3 to a temp file then play it - Godot can't stream mp3 from bytes directly
	var path = "user://cipher_reply.mp3"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(body)
	file.close()

	var stream = AudioStreamMP3.new()
	var read_file = FileAccess.open(path, FileAccess.READ)
	stream.data = read_file.get_buffer(read_file.get_length())
	read_file.close()

	# Clean up the file immediately - we have the bytes in memory now
	DirAccess.remove_absolute(path)

	player.stream = stream
	player.play()

func _on_playback_done():
	speech_finished.emit()

func set_voice_parameters(stability: float, similarity: float, style: float):
	voice_stability = clamp(stability, 0.0, 1.0)
	voice_similarity_boost = clamp(similarity, 0.0, 1.0)
	voice_style = clamp(style, 0.0, 1.0)
	print("TTS parameters updated - stability: ", voice_stability, ", similarity: ", voice_similarity_boost, ", style: ", voice_style)

func set_voice_id(voice_id: String):
	active_voice_id = voice_id
	print("TTS Voice ID updated: ", voice_id)

func interrupt() -> void:
	if player and player.playing:
		player.stop()
	if http:
		http.cancel_request()
