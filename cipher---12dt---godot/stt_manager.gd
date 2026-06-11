extends Node

const GROQ_API_KEY = "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"
const GROQ_STT_URL = "https://api.groq.com/openai/v1/audio/transcriptions"

var http: HTTPRequest

signal transcription_ready(text: String)
signal transcription_failed()

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_done)

func send_audio(audio: AudioStreamWAV):
	if not audio or audio.data.is_empty():
		print("STT err: Audio data is empty!")
		transcription_failed.emit()
		return

	var temp_path = "user://stt_temp_audio.wav"
	audio.save_to_wav(temp_path)
	var wav_bytes = FileAccess.get_file_as_bytes(temp_path)

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

		# Filter out Whisper's silence hallucinations, do Remove LATER 
		var lower_text = text.to_lower()
		if lower_text == "thank you." or lower_text == "thank you" or lower_text == "thanks for watching." or lower_text.contains("amara.org"):
			print("Whisper hallucinated silence. The microphone captured nothing.")
			transcription_failed.emit()
			return

		if text.length() > 1:
			print("You said: " + text)
			transcription_ready.emit(text)
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

	var close = "\r\n--" + boundary + "--\r\n"
	output.append_array(close.to_utf8_buffer())
	return output
