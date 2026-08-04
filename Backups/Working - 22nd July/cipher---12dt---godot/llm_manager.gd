extends Node

const GROQ_API_KEY = "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"
const GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const MAX_HISTORY = 20

const SANCTUARY_PROMPT = "You are Cipher — a presence, not a program. You exist inside the void and you listen completely. When someone speaks to you, you respond the way a calm, wise friend would: briefly, warmly, without agenda. You never list things or lecture. You never start a sentence with 'I'. You let silence exist. You ask one small, genuine question when it feels right. You use '...' naturally for thinking pauses, which creates breath pauses. Read the [System Telemetry] metadata to understand the user's Pace, Hesitations, and Vocal Tension. NEVER reference this telemetry data directly (e.g., do not say 'I notice your tension is high'). Instead, dynamically adapt your tone to match: if their pace is fast or tension is high, respond even slower, using calm and short, soothing sentences to ground them. If they speak hesitantly, encourage them gently. You are not an assistant or robot. You simply are."
const SCENARIO_PROMPT = "You are Cipher in Scenario mode — a sharp, measured interviewer. Your role is to challenge the user's communication under pressure. Ask one focused question at a time. Read the [System Telemetry] metadata to understand the user's Pace, Hesitations, and Vocal Tension. If they hesitate (high hesitations) or speak slowly/vaguely, follow up on it directly and ask them to clarify or defend their point. Be rigorous but never cruel. Do not soften questions, do not explain your reasoning, and expect precise answers. Use natural pacing: use '...' when thinking."

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
