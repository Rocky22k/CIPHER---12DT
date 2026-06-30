extends Node

const GROQ_API_KEY = "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"
const GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const MAX_HISTORY = 20

const SANCTUARY_PROMPT = "You are Cipher. You are a patient, warm presence. You listen carefully and respond like a close friend who genuinely cares. You use short sentences. You never lecture or give long lists of advice. You ask one gentle question at a time. You remember what the person said earlier in the conversation and refer back to it naturally. If someone goes quiet, you don't panic, you give them space. You can use pauses like '...' or fillers like 'uh' or 'well' to sound natural. You never sound like an assistant or a robot."
const SCENARIO_PROMPT = "You are Cipher, a professional and rigorous job interviewer. You ask challenging, analytical questions to test the user's communication under pressure. You speak clearly, concisely, and formally. Do not use filler words. Ask one formal question at a time."

var current_mode: String = "Sanctuary"

var http: HTTPRequest
var history: Array = []
var last_request_was_nudge = false

signal response_ready(text: String)

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response)

func set_mode(mode: String):
	if mode != "Sanctuary" and mode != "Scenario":
		push_warning("Unknown conversational mode: " + mode)
		return
	current_mode = mode
	print("LLM mode updated: ", current_mode)

func interrupt() -> void:
	if http:
		http.cancel_request()

func ask(user_text: String, is_nudge: bool = false):
	last_request_was_nudge = is_nudge
	if not is_nudge:
		history.append({"role": "user", "content": user_text})

		# Keep history from growing too large - drop oldest user/assistant pairs first
		while history.size() > MAX_HISTORY:
			history.pop_front()

	var system_prompt = SANCTUARY_PROMPT if current_mode == "Sanctuary" else SCENARIO_PROMPT
	var messages = [{"role": "system", "content": system_prompt}]
	messages.append_array(history)

	if is_nudge:
		messages.append({"role": "user", "content": user_text})

	var body = JSON.stringify({
		"model": "llama-3.3-70b-versatile",
		"messages": messages,
		"max_tokens": 140,
		"temperature": 0.9
	})

	var headers = [
		"Authorization: Bearer " + GROQ_API_KEY,
		"Content-Type: application/json"
	]

	http.request(GROQ_CHAT_URL, headers, HTTPClient.METHOD_POST, body)

func say_silently(context_message: String):
	# Used to send a nudge without the user having spoken, after silence
	# Passed as is_nudge=true so it does not contaminate conversational history
	ask(context_message, true)

func _on_response(_result, response_code, _headers, body):
	if response_code != 200:
		print("LLM failed. Code: %d" % response_code)
		print(body.get_string_from_utf8())
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("choices"):
		var reply = json["choices"][0]["message"]["content"].strip_edges()
		if not last_request_was_nudge:
			history.append({"role": "assistant", "content": reply})
		response_ready.emit(reply)
	else:
		print("LLM unexpected format.")
		print(body.get_string_from_utf8())

func clear_history():
	history.clear()
