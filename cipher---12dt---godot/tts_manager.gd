extends Node

const EL_URL = "https://api.elevenlabs.io/v1/text-to-speech/"

# Dictionary of available voice IDs
var voices = {
	"Bella (Default)": "EXAVITQu4vr4xnSDxMaL"
}

# Active voice profile, defaults to Sarah
var active_voice_id = "EXAVITQu4vr4xnSDxMaL"

# Fault-tolerant API key array rotation
var api_keys = [
	"sk_d995f1796d3704f8cc778895b0abf5640a0782a6a14b98b9", # Asfan 87 11labs key
	"sk_4d75df8aef56d417f2078d44e141b191c9f09c13ad2b8833"  # Backup key
]
var active_key_index = 0

var http: HTTPRequest
var player: AudioStreamPlayer
var last_requested_text = ""

signal speech_finished

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_received)

	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_on_playback_done)

func speak(text: String):
	last_requested_text = text
	var body = JSON.stringify({
		"text": text,
		"model_id": "eleven_multilingual_v2",
		"voice_settings": {
			"stability": 0.6,
			"similarity_boost": 0.8,
			"style": 0.2,
			"use_speaker_boost": true
		}
	})

	var headers = [
		"xi-api-key: " + api_keys[active_key_index],
		"Content-Type: application/json",
		"Accept: audio/mpeg"
	]

	http.request(EL_URL + active_voice_id, headers, HTTPClient.METHOD_POST, body)

func interrupt():
	if player.is_playing():
		player.stop()
	http.cancel_request()

func _on_audio_received(_result, response_code, _headers, body):
	# Handle key rotation on HTTP failure codes (e.g. rate limit 429, unauthorized 401, quota 403)
	if response_code != 200:
		print("ElevenLabs request failed. Code: %d" % response_code)
		print(body.get_string_from_utf8())

		if active_key_index < api_keys.size() - 1:
			active_key_index += 1
			print("Rotating ElevenLabs API Key to fallback index: %d" % active_key_index)
			speak(last_requested_text) # Retry request with next key
			return
		else:
			print("All ElevenLabs keys exhausted. Cannot play speech.")
			speech_finished.emit()
			return

	# Save mp3 to a temp file then play it
	var path = "user://cipher_reply.mp3"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(body)
	file.close()

	var stream = AudioStreamMP3.new()
	var read_file = FileAccess.open(path, FileAccess.READ)
	stream.data = read_file.get_buffer(read_file.get_length())
	read_file.close()

	player.stream = stream
	player.play()

func _on_playback_done():
	speech_finished.emit()
