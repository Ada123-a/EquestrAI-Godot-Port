extends Node
class_name LLMController

## Handles all LLM request/response integration, prompt construction, and response parsing
## Extracted from Main.gd to consolidate LLM-related logic

# Signals to notify parent of state changes
signal llm_response_received(text: String, response_type: String)
signal llm_error_occurred(error: String)
signal impersonation_completed(cleaned_line: String)
signal memory_summary_completed(summary: String)

# Dependencies (set by parent after instantiation)
var llm_client: Node = null
var settings_manager = null
var location_manager = null
var location_graph_manager = null
var character_manager = null
var memory_manager = null
var stats_manager = null
var dialogue_panel = null
var event_manager = null  # To check if an event is handling dialogue

const PromptBuilder = preload("res://scripts/PromptBuilder.gd")

# State
var pending_impersonation_request: bool = false
var memory_summary_request_active: bool = false
var end_scene_request_active: bool = false
var travel_request_active: bool = false
var custom_generation_active: bool = false
var current_sequence_label: String = "scene"

func _ready() -> void:
	pass

## Connect to the LLM client signals
func connect_llm_client(client: Node) -> void:
	llm_client = client
	if llm_client:
		if not llm_client.response_received.is_connected(_on_llm_response):
			llm_client.response_received.connect(_on_llm_response)
		if not llm_client.error_occurred.is_connected(_on_llm_error):
			llm_client.error_occurred.connect(_on_llm_error)

# =============================================================================
# REQUEST METHODS
# =============================================================================

## Send a user interrupt/input to continue the conversation
func send_user_input(text: String) -> void:
	if memory_summary_request_active:
		print("Memory summary in progress; waiting before sending new user input.")
		return
	
	var context_data = PromptBuilder.build_world_context(
		location_manager, stats_manager, location_graph_manager, 
		character_manager, memory_manager, settings_manager
	)
	var prompt_info = PromptBuilder.build_scene_prompt(
		context_data.characters, 
		context_data.context_string, 
		"", # No task string in system prompt for interrupt
		settings_manager
	)
	
	# PromptBuilder doesn't add "Continue the scene naturally" by default if task is empty,
	# but build_scene_prompt is robust.
	var system_prompt = prompt_info.system_prompt
	system_prompt += "\nContinue the scene naturally."
	
	llm_client.send_request(system_prompt, text)

## Request impersonation (write player's dialogue)
func request_impersonation() -> void:
	if pending_impersonation_request or memory_summary_request_active:
		return
	
	pending_impersonation_request = true
	var context_data = PromptBuilder.build_world_context(
		location_manager, stats_manager, location_graph_manager, 
		character_manager, memory_manager, settings_manager,
		false # include_mechanics = false for impersonation
	)
	var system_prompt = PromptBuilder.build_impersonate_prompt(
		context_data.parts,
		context_data.characters,
		"" # Custom instruction
	)
	llm_client.send_request(system_prompt, "Please write the player's next line now.")

## Request end scene narration
func request_end_scene(history_text: String) -> void:
	if end_scene_request_active:
		return
	
	end_scene_request_active = true
	var context_data = PromptBuilder.build_world_context(
		location_manager, stats_manager, location_graph_manager, 
		character_manager, memory_manager, settings_manager
	)
	var system_prompt = PromptBuilder.build_end_scene_prompt(
		context_data.context_string,
		history_text,
		context_data.characters,
		memory_manager
	)
	llm_client.send_request(system_prompt, "Please conclude the current scene now.")

## Request travel narration
func request_travel_narration(previous_location_id: String, destination_id: String, history_text: String, schedule_assignments: Array) -> void:
	travel_request_active = true
	var system_prompt = PromptBuilder.build_travel_prompt(
		previous_location_id, destination_id, history_text, schedule_assignments,
		location_manager, stats_manager, location_graph_manager, settings_manager, memory_manager
	)
	llm_client.send_request(system_prompt, "Please write the travel narration.")

## Request memory summary
func request_memory_summary() -> void:
	if memory_manager == null or llm_client == null:
		return
	if memory_summary_request_active:
		return
	
	var summary_request: Dictionary = memory_manager.build_summary_request()
	var system_prompt: String = summary_request.get("system_prompt", "")
	var user_prompt: String = summary_request.get("user_prompt", "")
	
	if system_prompt.strip_edges() == "" or user_prompt.strip_edges() == "":
		return
	
	memory_summary_request_active = true
	llm_client.send_request(system_prompt, user_prompt)

## Request a normal scene turn with user input
func request_scene(user_input: String) -> void:
	if memory_summary_request_active:
		print("Memory summary in progress; waiting before sending new user input.")
		return
	
	var context_data = PromptBuilder.build_world_context(
		location_manager, stats_manager, location_graph_manager, 
		character_manager, memory_manager, settings_manager
	)
	var prompt_info = PromptBuilder.build_scene_prompt(
		context_data.characters, 
		context_data.context_string, 
		"", 
		settings_manager
	)
	var system_prompt = prompt_info.system_prompt
	system_prompt += "\nContinue the scene naturally."
	
	llm_client.send_request(system_prompt, user_input)

## Request a custom generation with explicit prompts (e.g. for Start Flows)
func request_custom_generation(system_prompt: String, user_prompt: String) -> void:
	if llm_client:
		custom_generation_active = true
		llm_client.send_request(system_prompt, user_prompt)

## Check if a memory summary should be triggered
func should_trigger_memory_summary() -> bool:
	if memory_manager == null:
		return false
	return memory_manager.should_summarize()

# =============================================================================
# RESPONSE HANDLERS
# =============================================================================

func _on_llm_response(text: String) -> void:
	# If EventManager is handling an LLM request (e.g. from LLM Prompt action),
	# let it handle the response exclusively - don't process here.
	if event_manager and event_manager.waiting_for_dialogue:
		return
	
	# Route based on current request type
	if memory_summary_request_active:
		_handle_memory_summary_response(text)
		return
	
	if travel_request_active:
		travel_request_active = false
		llm_response_received.emit(text, "travel")
		return
	
	if pending_impersonation_request:
		_handle_impersonation_response(text)
		return
	
	if end_scene_request_active:
		end_scene_request_active = false
		llm_response_received.emit(text, "end_scene")
		return
	
	if custom_generation_active:
		custom_generation_active = false
		llm_response_received.emit(text, "custom")
		return

	# Default: normal LLM response
	llm_response_received.emit(text, "scene")

func _on_llm_error(error) -> void:
	if memory_summary_request_active:
		memory_summary_request_active = false
		print("Memory summary request failed: ", error)
		llm_error_occurred.emit(str(error))
		return
	
	print("LLM Error: ", error)
	
	if pending_impersonation_request:
		pending_impersonation_request = false
	
	end_scene_request_active = false
	travel_request_active = false
	
	llm_error_occurred.emit(str(error))

func _handle_memory_summary_response(summary_text: String) -> void:
	memory_summary_request_active = false
	var trimmed: String = summary_text.strip_edges()
	
	if trimmed == "":
		print("Memory summary response was empty; keeping existing context.")
	else:
		if memory_manager:
			memory_manager.apply_summary(trimmed)
		print("Memory summary updated; rolling summary length: %d" % trimmed.length())
	
	memory_summary_completed.emit(trimmed)

func _handle_impersonation_response(text: String) -> void:
	pending_impersonation_request = false
	
	var user_line = _extract_impersonated_line(text).strip_edges()
	if user_line.is_empty():
		print("Warning: Failed to parse impersonated player line.")
		impersonation_completed.emit("")
		return
	
	var cleaned_line = _strip_player_prefix(user_line)
	impersonation_completed.emit(cleaned_line)


# =============================================================================
# PARSING HELPERS
# =============================================================================

func _extract_impersonated_line(raw_text: String) -> String:
	var trimmed = raw_text.strip_edges()
	if trimmed.is_empty():
		return ""

	var parsed = DialogueParser.parse(trimmed, character_manager)
	for line in parsed.lines:
		if line.type == "dialogue" and line.speaker_tag == "player":
			return line.text

	var regex = RegEx.new()
	regex.compile("player\\s+\"([^\"]+)\"")
	var match = regex.search(trimmed)
	if match:
		return match.get_string(1)

	return trimmed

func _strip_player_prefix(line: String) -> String:
	var trimmed = line.strip_edges()
	if trimmed.begins_with("player "):
		trimmed = trimmed.substr(7).strip_edges()
	elif trimmed.begins_with("player:"):
		trimmed = trimmed.substr(7).strip_edges()
	elif trimmed.begins_with("You:"):
		trimmed = trimmed.substr(4).strip_edges()
	elif trimmed.begins_with("You "):
		trimmed = trimmed.substr(3).strip_edges()

	if trimmed.length() >= 2 and trimmed.begins_with("\"") and trimmed.ends_with("\""):
		trimmed = trimmed.substr(1, trimmed.length() - 2).strip_edges()

	return trimmed

# =============================================================================
# STATE ACCESSORS
# =============================================================================

func is_impersonation_pending() -> bool:
	return pending_impersonation_request

func is_memory_summary_active() -> bool:
	return memory_summary_request_active

func is_travel_active() -> bool:
	return travel_request_active

func is_end_scene_active() -> bool:
	return end_scene_request_active

func reset_end_scene_state() -> void:
	end_scene_request_active = false
