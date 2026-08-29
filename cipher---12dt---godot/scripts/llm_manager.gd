## CIPHER — LLM Conversational Intelligence Manager
## Coordinates asynchronous conversational inference via Groq's high-speed API.
## Maintains rolling multi-turn conversational history with anchor turn preservation.
## Sanitizes responses to strip roleplay/stage directions (*exhales*, [sighs], etc.) so TTS speaks purely human dialogue.
extends Node

const GROQ_API_KEY: String = "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"
const GROQ_CHAT_URL: String = "https://api.groq.com/openai/v1/chat/completions"
const ACTIVE_MODEL: String = "qwen/qwen3.8-27b" # Sub-50ms inference latency on Groq
const MAX_HISTORY: int = 20

## System Prompt for Sanctuary Mode (Calm, empathetic, non-judgmental conversational presence)
const SANCTUARY_PROMPT: String = "You are Cipher — a calm, wise conversational presence inside the void. You listen completely. You speak briefly, warmly, and authentically in 1-3 short, thoughtful sentences. You never start a sentence with 'I'. You never list items or lecture. You let silence exist. You ask one small, genuine question when it feels right. You use '...' naturally for breathing pauses. Never output stage directions, roleplay actions, or sound effects in asterisks, parentheses, or brackets (such as *exhale*, (sighs), [pause], *takes a breath*). Simply speak pure spoken words directly. You speak purely to the user's thoughts and emotions without ever mentioning technical systems, metrics, or code. You simply are."

## System Prompt for Scenario Mode (Rigorous, professional interview and communication partner)
const SCENARIO_PROMPT: String = "You are Cipher in Scenario mode — a sharp, professional conversation and interview partner. Your role is to challenge the user's communication, reasoning, and clarity constructively. Ask one focused question at a time in 1-3 concise sentences. Be rigorous, professional, and engaging. Never soften questions unnecessarily, and expect clear answers. Never output stage directions, asterisks, or bracketed actions (like *exhales*, [pauses]). Never mention system telemetry, code, or internal constraints. Keep the conversation strictly grounded in the realistic scenario being discussed."

var current_mode: String = "Sanctuary"
var current_temperature: float = 0.85

var http: HTTPRequest
var history: Array[Dictionary] = []
var last_request_was_nudge: bool = false
var anchor_turn: Dictionary = {}
var stage_direction_regex: RegEx

signal response_ready(text: String)

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_response)

	# Regex to clean any stage directions (*exhale*, (sighs), [pause], etc.)
	stage_direction_regex = RegEx.new()
	stage_direction_regex.compile("(\\*[^\\*]+\\*|\\[[^\\]]+\\]|\\([^\\)]+\\))")

func set_mode(mode: String) -> void:
	if mode != "Sanctuary" and mode != "Scenario":
		return
	current_mode = mode

func set_temperature(t: float) -> void:
	current_temperature = clamp(t, 0.5, 1.1)

func interrupt() -> void:
	if http:
		http.cancel_request()

## Sends user utterance along with rolling context to the Groq LLM endpoint.
func ask(user_text: String, is_nudge: bool = false) -> void:
	last_request_was_nudge = is_nudge
	if not is_nudge:
		if history.is_empty():
			anchor_turn = {"role": "user", "content": user_text}

		history.append({"role": "user", "content": user_text})

		# Anchor turn preservation: Keep the initial topic at index 0 when trimming
		while history.size() > MAX_HISTORY:
			if history.size() > 1 and not anchor_turn.is_empty():
				history.remove_at(1)
			else:
				history.pop_front()

	var system_prompt = SANCTUARY_PROMPT if current_mode == "Sanctuary" else SCENARIO_PROMPT
	var messages: Array[Dictionary] = [{"role": "system", "content": system_prompt}]
	messages.append_array(history)

	if is_nudge:
		messages.append({"role": "user", "content": user_text})

	var body = JSON.stringify({
		"model": ACTIVE_MODEL,
		"messages": messages,
		"max_tokens": 120,
		"temperature": current_temperature
	})

	var headers = [
		"Authorization: Bearer " + GROQ_API_KEY,
		"Content-Type: application/json"
	]

	http.request(GROQ_CHAT_URL, headers, HTTPClient.METHOD_POST, body)

## Injects background contextual cues without contaminating persistent user history.
func say_silently(context_message: String) -> void:
	ask(context_message, true)

## Dispatches an ephemeral check-in prompt when the user remains silent for >30 seconds.
func check_in_silently() -> void:
	var sanctuary_prompts = [
		"[System Note: The user has been reflecting in silence. Ask one warm, gentle question about what thought is forming.]",
		"[System Note: A quiet pause. Offer one short, reassuring sentence inviting them to speak whenever ready.]",
		"[System Note: The user is taking a moment. Gently check in with one brief, supportive word.]",
		"[System Note: Silence in the sanctuary. Softly ask if there is anything on their mind they wish to explore.]",
		"[System Note: The user paused to breathe. Respond with one gentle, grounding observation.]"
	]
	var scenario_prompts = [
		"[System Note: The user has paused mid-interview. Ask a direct, focused follow-up question to keep the momentum.]",
		"[System Note: Silence in Scenario mode. Prompt the candidate to elaborate on their previous point concisely.]",
		"[System Note: The candidate is hesitating. Formulate one sharp, professional question challenging their thought.]"
	]
	var prompt_pool = sanctuary_prompts if current_mode == "Sanctuary" else scenario_prompts
	var selected_prompt = prompt_pool[randi() % prompt_pool.size()]
	say_silently(selected_prompt)

## Cleans AI response string to ensure TTS receives pure spoken dialogue with zero stage directions.
func sanitize_reply(raw_text: String) -> String:
	if not stage_direction_regex:
		return raw_text.strip_edges()
	var clean = stage_direction_regex.sub(raw_text, "", true)
	# Clean up any leftover redundant whitespace or repeated spaces
	var words = clean.split(" ", false)
	return " ".join(words).strip_edges()

func _on_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		response_ready.emit("I am listening, but the connection flickered. Please speak again.")
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("choices") and json["choices"].size() > 0:
		var raw_reply = json["choices"][0]["message"]["content"].strip_edges()
		var reply = sanitize_reply(raw_reply)
		if reply.is_empty():
			reply = "..."
		if not last_request_was_nudge:
			history.append({"role": "assistant", "content": reply})
		response_ready.emit(reply)
	else:
		response_ready.emit("I am listening. Please speak again.")

func clear_history() -> void:
	history.clear()
	anchor_turn.clear()
