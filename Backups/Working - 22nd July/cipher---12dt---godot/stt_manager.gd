extends Node

const GROQ_API_KEY = "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"
const GROQ_STT_URL = "https://api.groq.com/openai/v1/audio/transcriptions"

var http: HTTPRequest
var filler_regex: RegEx

signal transcription_ready_with_metrics(text: String, filler_count: int, wpm: float)
signal transcription_failed()

var last_audio_duration = 1.0

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_done)
	filler_regex = RegEx.new()
	filler_regex.compile("\\b(um|uh|like)\\b")

func get_max_amplitude(audio: AudioStreamWAV) -> float:
	if not audio:
		return 0.0
	var data_bytes = audio.data
	if data_bytes.is_empty():
		return 0.0
	var max_val = 0.0
	var step = 2 # 16-bit default
	if audio.format == AudioStreamWAV.FORMAT_8_BITS:
		step = 1

	var sample_interval = 50
	var data_size = data_bytes.size()
	for i in range(0, data_size - step, step * sample_interval):
		var val = 0.0
		if step == 2:
			var low = data_bytes[i]
			var high = data_bytes[i + 1]
			var signed_int = low | (high << 8)
			if signed_int & 0x8000:
				signed_int -= 0x10000
			val = abs(float(signed_int) / 32768.0)
		else:
			val = abs(float(data_bytes[i] - 128) / 128.0)
		if val > max_val:
			max_val = val
	return max_val

func send_audio(audio: AudioStreamWAV):
	if not audio or audio.data.is_empty():
		print("STT err: Audio data is empty!")
		transcription_failed.emit()
		return

	var peak = get_max_amplitude(audio)
	print("Audio Peak Amplitude Check: ", peak)
	if peak < 0.005:
		print("Local Silence Gated: Discarding request.")
		transcription_failed.emit()
		return

	# Calculate audio duration for WPM computation
	var step = 2
	if audio.format == AudioStreamWAV.FORMAT_8_BITS:
		step = 1
	var byte_rate = audio.mix_rate * step * (2 if audio.stereo else 1)
	last_audio_duration = max(0.5, float(audio.data.size()) / float(byte_rate))

	var temp_path = "user://stt_temp_audio.wav"
	audio.save_to_wav(temp_path)
	var wav_bytes = FileAccess.get_file_as_bytes(temp_path)
	DirAccess.remove_absolute(temp_path)

	var boundary = "CipherBoundary1234"
	var body = _build_multipart(wav_bytes, boundary)

	var headers = [
		"Authorization: Bearer " + GROQ_API_KEY,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]

	http.request_raw(GROQ_STT_URL, headers, HTTPClient.METHOD_POST, body)

func _on_request_done(_result, response_code, _headers, body):
	if response_code != 200:
		print("STT failed. Code: %d" % response_code)
		transcription_failed.emit()
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("text"):
		var text = json["text"].strip_edges()

		# Confidence gate: if Whisper itself says no speech was likely present, discard immediately
		if json.has("segments") and json["segments"].size() > 0:
			var no_speech_prob = json["segments"][0].get("no_speech_prob", 0.0)
			if no_speech_prob > 0.6:
				print("Whisper confidence too low (no_speech_prob: %.2f). Discarding." % no_speech_prob)
				transcription_failed.emit()
				return

		# Filter out known Whisper silence hallucination phrases
		var lower_text = text.to_lower()
		if lower_text == "thank you." or lower_text == "thank you" or lower_text == "thanks for watching." or lower_text.contains("amara.org"):
			print("Whisper hallucinated silence. The microphone captured nothing.")
			transcription_failed.emit()
			return

		if text.length() > 1:
			# Count words and compute WPM
			var word_count = text.split(" ", false).size()
			var wpm = (float(word_count) / last_audio_duration) * 60.0

			# Count filler words using RegEx
			var matches = filler_regex.search_all(lower_text)
			var filler_count = matches.size()

			transcription_ready_with_metrics.emit(text, filler_count, wpm)
		else:
			print("Empty transcription.")
			transcription_failed.emit()
	else:
		print("STT gave unexpected format.")
		transcription_failed.emit()

func _build_multipart(wav_bytes: PackedByteArray, boundary: String) -> PackedByteArray:
	var output = PackedByteArray()
	var part_header = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
	output.append_array(part_header.to_utf8_buffer())
	output.append_array(wav_bytes)

	var model_field = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo"
	output.append_array(model_field.to_utf8_buffer())

	var lang_field = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nen"
	output.append_array(lang_field.to_utf8_buffer())

	var prompt_field = "\r\n--" + boundary + "\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nUmm, let's see, uh, yes, like..."
	output.append_array(prompt_field.to_utf8_buffer())

	var close = "\r\n--" + boundary + "--\r\n"
	output.append_array(close.to_utf8_buffer())
	return output
