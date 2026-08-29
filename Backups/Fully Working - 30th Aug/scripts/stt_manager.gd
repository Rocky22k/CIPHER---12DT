## CIPHER — Speech-to-Text (STT) Manager
## Handles microphone audio capture, local amplitude noise-gating, WAV formatting,
## and multipart HTTP streaming to Groq Whisper STT API with hallucination filtering.
extends Node

const GROQ_API_KEY: String = "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"
const GROQ_STT_URL: String = "https://api.groq.com/openai/v1/audio/transcriptions"

var http: HTTPRequest
var filler_regex: RegEx
var last_audio_duration: float = 1.0

## Whisper hallucination filter list: Intercepts phantom text returned from background silence
const HALLUCINATION_PHRASES: Array[String] = [
	"thank you.", "thank you", "thanks for watching.",
	"thanks for watching", "you", "bye.", "bye",
	".", ",", "...", "please subscribe.",
	"like and subscribe.", "see you next time."
]

signal transcription_ready_with_metrics(text: String, filler_count: int, wpm: float)
signal transcription_failed()

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_request_done)
	filler_regex = RegEx.new()
	filler_regex.compile("\\b(um|uh|like)\\b")

## Calculates the peak normalized amplitude across audio sample buffers.
func get_max_amplitude(audio: AudioStreamWAV) -> float:
	if not audio:
		return 0.0
	var data_bytes: PackedByteArray = audio.data
	if data_bytes.is_empty():
		return 0.0
	var max_val: float = 0.0
	var step: int = 2 # 16-bit PCM default
	if audio.format == AudioStreamWAV.FORMAT_8_BITS:
		step = 1

	var sample_interval: int = 50
	var data_size: int = data_bytes.size()
	for i in range(0, data_size - step, step * sample_interval):
		var val: float = 0.0
		if step == 2:
			var low: int = data_bytes[i]
			var high: int = data_bytes[i + 1]
			var signed_int: int = low | (high << 8)
			if signed_int & 0x8000:
				signed_int -= 0x10000
			val = abs(float(signed_int) / 32768.0)
		else:
			val = abs(float(data_bytes[i] - 128) / 128.0)
		if val > max_val:
			max_val = val
	return max_val

## Packages and dispatches captured audio to the Groq Whisper STT cloud endpoint.
func send_audio(audio: AudioStreamWAV) -> void:
	if not audio or audio.data.is_empty():
		transcription_failed.emit()
		return

	# Local amplitude noise gate: Discards silent audio before calling API to conserve quota
	var peak: float = get_max_amplitude(audio)
	if peak < 0.005:
		transcription_failed.emit()
		return

	# Calculate exact duration for user speaking pace (WPM) computation
	var step: int = 2
	if audio.format == AudioStreamWAV.FORMAT_8_BITS:
		step = 1
	var byte_rate: int = audio.mix_rate * step * (2 if audio.stereo else 1)
	last_audio_duration = max(0.5, float(audio.data.size()) / float(byte_rate))

	var temp_path: String = "user://stt_temp_audio.wav"
	audio.save_to_wav(temp_path)
	var wav_bytes: PackedByteArray = FileAccess.get_file_as_bytes(temp_path)
	DirAccess.remove_absolute(temp_path)

	var boundary: String = "CipherBoundary1234"
	var body: PackedByteArray = _build_multipart(wav_bytes, boundary)

	var headers: PackedStringArray = [
		"Authorization: Bearer " + GROQ_API_KEY,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]

	http.request_raw(GROQ_STT_URL, headers, HTTPClient.METHOD_POST, body)

func _on_request_done(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		transcription_failed.emit()
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("text"):
		var text: String = json["text"].strip_edges()

		# Confidence gating: Verify segment probability of no speech
		if json.has("segments") and json["segments"].size() > 0:
			var no_speech_prob: float = json["segments"][0].get("no_speech_prob", 0.0)
			if no_speech_prob > 0.6:
				transcription_failed.emit()
				return

		# Hallucination filter pattern verification
		var lower_text: String = text.to_lower()
		for phrase in HALLUCINATION_PHRASES:
			if lower_text == phrase or lower_text.begins_with(phrase + " "):
				transcription_failed.emit()
				return
		if lower_text.contains("amara.org"):
			transcription_failed.emit()
			return

		if text.length() > 1 and text.split(" ", false).size() >= 1:
			var word_count: int = text.split(" ", false).size()
			var wpm: float = (float(word_count) / last_audio_duration) * 60.0

			var matches = filler_regex.search_all(lower_text)
			var filler_count: int = matches.size()

			transcription_ready_with_metrics.emit(text, filler_count, wpm)
		else:
			transcription_failed.emit()
	else:
		transcription_failed.emit()

func _build_multipart(wav_bytes: PackedByteArray, boundary: String) -> PackedByteArray:
	var output: PackedByteArray = PackedByteArray()
	var part_header: String = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
	output.append_array(part_header.to_utf8_buffer())
	output.append_array(wav_bytes)

	var model_field: String = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo"
	output.append_array(model_field.to_utf8_buffer())

	var lang_field: String = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nen"
	output.append_array(lang_field.to_utf8_buffer())

	var prompt_field: String = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nUmm, let's see, uh, yes, like..."
	output.append_array(prompt_field.to_utf8_buffer())

	var format_field: String = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json"
	output.append_array(format_field.to_utf8_buffer())

	var close: String = "\r\n--" + boundary + "--\r\n"
	output.append_array(close.to_utf8_buffer())
	return output
