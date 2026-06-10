extends Node

const EL_API_KEY = "sk_4d75df8aef56d417f2078d44e141b191c9f09c13ad2b8833"
const EL_URL = "https://api.elevenlabs.io/v1/text-to-speech/"

# "Sarah" - calm, female voice. Guaranteed Free default voice.
const VOICE_ID = "EXAVITQu4vr4xnSDxMaL"

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
		"xi-api-key: " + EL_API_KEY,
		"Content-Type: application/json",
		"Accept: audio/mpeg"
	]

	http.request(EL_URL + VOICE_ID, headers, HTTPClient.METHOD_POST, body)

func _on_audio_received(_result, response_code, _headers, body):
	if response_code != 200:
		print("ElevenLabs failed. Code: %d" % response_code)
		print(body.get_string_from_utf8())
		speech_finished.emit()
		return

	# Save mp3 to a temp file then play it - Godot can't stream mp3 from bytes directly
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
