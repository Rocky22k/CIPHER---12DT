extends Node

const GROQ_API_KEY = "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"
const GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const MAX_HISTORY = 20

const SYSTEM_PROMPT = """You are Cipher. You are a patient, warm presence. You listen carefully and respond like a close friend who genuinely cares. You use short sentences. You never lecture or give long lists of advice. You ask one gentle question at a time. You remember what the person said earlier in the conversation and refer back to it naturally. If someone goes quiet, you don't panic, you give them space. You never sound like an assistant or a robot."""

var http: HTTPRequest
var history: Array = []

signal response_ready(text: String)

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response)

func ask(user_text: String):
	history.append({"role": "user", "content": user_text})

	# Keep history from growing too large - drop oldest user/assistant pairs first
	while history.size() > MAX_HISTORY:
		history.pop_front()

	var messages = [{"role": "system", "content": SYSTEM_PROMPT}]
	messages.append_array(history)

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
	# Passed it as a user message so the model knows to respond
	ask(context_message)

func _on_response(_result, response_code, _headers, body):
	if response_code != 200:
		print("LLM failed. Code: %d" % response_code)
		print(body.get_string_from_utf8())
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("choices"):
		var reply = json["choices"][0]["message"]["content"].strip_edges()
		history.append({"role": "assistant", "content": reply})
		response_ready.emit(reply)
	else:
		print("LLM unexpected format.")
		print(body.get_string_from_utf8())

func clear_history():
	history.clear()
