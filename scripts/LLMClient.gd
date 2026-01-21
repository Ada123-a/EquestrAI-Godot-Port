extends Node

signal response_received(response_text)
signal error_occurred(error_msg)

var settings_manager

@export var api_url: String = "api"
@export var api_key: String = "api key"
@export var model: String = "model-name"

func send_request(system_prompt: String, user_prompt: String):
	print("\n--- [LLM REQUEST] ---")
	print(system_prompt)
	print(user_prompt)
	print("---------------------\n")
	
	var provider = "openai"
	if settings_manager:
		provider = settings_manager.get_setting("provider")
	
	if provider == "gemini":
		_send_gemini_request(system_prompt, user_prompt)
	else:
		_send_openai_request(system_prompt, user_prompt)

func _send_openai_request(system_prompt: String, user_prompt: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_openai_request_completed.bind(http_request))

	var url = api_url
	var key = api_key
	var mdl = model
	var temp = 0.7
	var top_p_val = 1.0
	var top_k_val = 0
	var max_tokens = 2000

	if settings_manager:
		url = settings_manager.get_setting("api_url")
		key = settings_manager.get_setting("api_key")
		mdl = settings_manager.get_setting("model")
		temp = settings_manager.get_setting("temperature")
		top_p_val = settings_manager.get_setting("top_p")
		top_k_val = settings_manager.get_setting("top_k")
		max_tokens = settings_manager.get_setting("max_response_length")

	url = _ensure_chat_completions_endpoint(url)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	
	var body_dict = {
		"model": mdl,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt}
		],
		"temperature": temp,
		"top_p": top_p_val,
		"max_tokens": max_tokens
	}
	
	if top_k_val > 0:
		body_dict["top_k"] = top_k_val
	
	var body = JSON.stringify(body_dict)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		emit_signal("error_occurred", "Failed to create OpenAI request")
		http_request.queue_free()

func _send_gemini_request(system_prompt: String, user_prompt: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_gemini_request_completed.bind(http_request))
	
	var key = ""
	var mdl = "gemini-pro"
	var temp = 0.7
	var top_p_val = 1.0
	var top_k_val = 40
	var max_tokens = 2000
	
	if settings_manager:
		key = settings_manager.get_setting("gemini_key")
		mdl = settings_manager.get_setting("gemini_model")
		temp = settings_manager.get_setting("temperature")
		top_p_val = settings_manager.get_setting("top_p")
		top_k_val = settings_manager.get_setting("top_k")
		max_tokens = settings_manager.get_setting("max_response_length")
	
	var url = "https://generativelanguage.googleapis.com/v1beta/models/" + mdl + ":generateContent?key=" + key
	
	var headers = [
		"Content-Type: application/json"
	]
	
	# Construct body
	var body_dict = {
		"contents": [
			{
				"parts": [
					{"text": user_prompt}
				]
			}
		],
		"system_instruction": {
			"parts": [
				{"text": system_prompt}
			]
		},
		"generationConfig": {
			"temperature": temp,
			"topP": top_p_val,
			"maxOutputTokens": max_tokens
		}
	}
	
	if top_k_val > 0:
		body_dict["generationConfig"]["topK"] = top_k_val
	
	var body = JSON.stringify(body_dict)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		emit_signal("error_occurred", "Failed to create Gemini request")
		http_request.queue_free()

func _on_openai_request_completed(result, response_code, headers, body, http_request):
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	if error == OK:
		var response = json.get_data()
		if response.has("choices") and response["choices"].size() > 0:
			var content = response["choices"][0]["message"]["content"]
			emit_signal("response_received", content)
		elif response.has("error"):
			emit_signal("error_occurred", str(response["error"]))
		else:
			emit_signal("error_occurred", "Unknown OpenAI response format")
	else:
		emit_signal("error_occurred", "Failed to parse OpenAI JSON")
	
	http_request.queue_free()

func _on_gemini_request_completed(result, response_code, headers, body, http_request):
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	if error == OK:
		var response = json.get_data()
		if response.has("candidates") and response["candidates"].size() > 0:
			var candidate = response["candidates"][0]
			if candidate.has("content") and candidate["content"].has("parts") and candidate["content"]["parts"].size() > 0:
				var content = candidate["content"]["parts"][0]["text"]
				emit_signal("response_received", content)
			else:
				emit_signal("error_occurred", "Gemini response blocked or empty")
		elif response.has("error"):
			emit_signal("error_occurred", str(response["error"]))
		else:
			emit_signal("error_occurred", "Unknown Gemini response format")
	else:
		emit_signal("error_occurred", "Failed to parse Gemini JSON")

	http_request.queue_free()

# Ensures the URL ends with /v1/chat/completions for OpenAI-compatible APIs.
# If you provide a base URL like "https://example.com/api", this will automatically
# append "/v1/chat/completions" to make it "https://example.com/api/v1/chat/completions".
func _ensure_chat_completions_endpoint(url: String) -> String:
	var original_url = url

	url = url.rstrip("/")

	# Check if URL already ends with the chat completions path
	if url.ends_with("/v1/chat/completions"):
		print("[LLMClient] URL already has /v1/chat/completions endpoint: ", url)
		return url

	# Check if it ends with just /chat/completions (some APIs use this)
	if url.ends_with("/chat/completions"):
		print("[LLMClient] URL already has /chat/completions endpoint: ", url)
		return url

	# Auto-append the endpoint
	var final_url = url + "/v1/chat/completions"
	print("[LLMClient] Auto-appended /v1/chat/completions to base URL")
	print("[LLMClient]   Original: ", original_url)
	print("[LLMClient]   Final:    ", final_url)
	return final_url
