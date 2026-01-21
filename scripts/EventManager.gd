extends Node
class_name EventManager

var location_manager
var character_manager
var dialogue_display_manager
var sprite_manager
var llm_client
var main_node

# Event Data
var events: Dictionary = {}

var current_event_sequence: Array = []
var current_action_index: int = 0
var is_event_running: bool = false
var waiting_for_dialogue: bool = false
var waiting_for_choice: bool = false
var waiting_for_continue: bool = false  # Waiting for user to click Continue button
var skip_branch_prompt: bool = false
var pending_branch_options: Array = []  # Options to show after branch prompt finishes typing
var event_vars_local: Dictionary = {} 
var event_history: Array = [] # Stores context: {type: "dialogue"|"choice"|"action", text: "..."}

signal event_started(event_id)
signal event_finished(event_id)
signal request_branch(options) # Emitted when a branch action needs UI
signal request_persona_editor() # Emitted when edit_persona with show_editor mode is triggered

const PromptBuilderUtils = preload("res://scripts/PromptBuilder.gd")

func _ready():
	_load_events()

func _load_events():
	var path = "res://assets/Events/events.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			var data = json.get_data()
			if data.has("events"):
				events = data["events"]
		file.close()

func start_event(event_id: String) -> void:
	if not events.has(event_id):
		print("Error: Event not found: ", event_id)
		return
	
	print("Starting event: ", event_id)
	is_event_running = true
	# Reset all waiting flags
	waiting_for_dialogue = false
	waiting_for_choice = false
	waiting_for_continue = false
	var event_def = events[event_id]
	current_event_sequence = event_def.get("actions", [])
	current_action_index = 0
	event_history.clear()
	
	if dialogue_display_manager:
		dialogue_display_manager.set_input_mode(false)
		
	event_started.emit(event_id)
	_process_next_action()

func _process_next_action():
	if current_action_index >= current_event_sequence.size():
		_end_event()
		return
	
	var action = current_event_sequence[current_action_index]
	current_action_index += 1
	_execute_action(action)

func _execute_action(action: Dictionary):
	var type = action.get("type", "")
	
	match type:
		"change_location":
			var loc_id = _resolve_vars(action.get("location_id", ""))
			
			if main_node and main_node.has_method("change_location_with_groups"):
				# Automatically preserves groups via logic in TravelManager
				main_node.change_location_with_groups(loc_id)
			elif main_node and main_node.has_method("change_location"):
				main_node.change_location(loc_id)
			elif location_manager:
				location_manager.set_location(loc_id)
			
			if dialogue_display_manager:
				# Append as separate history entry
				dialogue_display_manager.append_to_history("[Location: %s]" % loc_id)
			_process_next_action()
			
		"character_enter":
			# Character enter now just shows the sprite - no separate [Enter:] tracking needed
			var char_id = _resolve_vars(action.get("character_id", ""))
			var emotion = _resolve_vars(action.get("emotion", "neutral"))
			# Treat "default" as "neutral" since that's the standard sprite name
			if emotion == "default" or emotion == "":
				emotion = "neutral"
			print("DEBUG character_enter: char_id=%s, emotion=%s" % [char_id, emotion])
			print("DEBUG character_enter: character_manager=%s, sprite_manager=%s" % [character_manager, sprite_manager])
			if character_manager:
				character_manager.add_active_character(char_id)
				print("DEBUG character_enter: added to active characters")
			if sprite_manager:
				var result = sprite_manager.show_sprite(char_id, emotion, character_manager)
				print("DEBUG character_enter: show_sprite result=%s" % result)
			# No history append - sprite commands are sufficient context for the LLM
			_process_next_action()
			
		"character_leave":
			var char_id = _resolve_vars(action.get("character_id", ""))
			if character_manager:
				character_manager.remove_active_character(char_id)
			if sprite_manager:
				sprite_manager.hide_sprite(char_id)
				# Remove from group
				if sprite_manager.current_group_map.has(char_id):
					sprite_manager.current_group_map.erase(char_id)
			# No history append - the LLM sees active characters in the prompt context
			_process_next_action()
			
		"change_sprite":
			var char_id = _resolve_vars(action.get("character_id", ""))
			var emotion = _resolve_vars(action.get("emotion", "neutral"))
			if emotion == "default" or emotion == "":
				emotion = "neutral"
			if sprite_manager:
				sprite_manager.show_sprite(char_id, emotion, character_manager)
			# No history append - sprite states are tracked elsewhere
			_process_next_action()
			
		"dialogue":
			var speaker = _resolve_vars(action.get("speaker_id", "narrator"))
			var text = _resolve_vars(action.get("text", ""))
			var emotion = _resolve_vars(action.get("emotion", ""))
			var seamless = action.get("seamless", false)  # Option to merge with prior choice
			
			# Record context
			event_history.append({"type": "dialogue", "speaker": speaker, "text": text})

			if dialogue_display_manager:
				waiting_for_dialogue = true
				
				# Split text by double-newlines into separate typing beats
				# Each paragraph becomes its own line but under the same speaker (merged visually)
				var paragraphs: Array[String] = []
				for part in text.split("\n\n"):
					# Keep the original text with its spacing, only skip empty paragraphs
					if part.strip_edges() != "":
						paragraphs.append(part)
				
				# If no paragraphs after splitting, use original text
				if paragraphs.is_empty():
					paragraphs.append(text)
				
				var pd = DialogueParser.ParsedDialogue.new()
				var is_first_line: bool = true
				
				# Check if previous event was a choice - if so, force newline for first paragraph
				# UNLESS "seamless" option is enabled (for continuing from choice smoothly)
				var force_newline_first: bool = false
				if not seamless and event_history.size() > 1:
					var prev = event_history[event_history.size() - 2]
					if prev.get("type", "") == "choice":
						force_newline_first = true
				
				for para in paragraphs:
					var line = DialogueParser.DialogueLine.new()
					# Prepend newline for visual separation (subsequent paragraphs, or first after a choice)
					var needs_newline = (not is_first_line) or force_newline_first
					var display_text = ("\n" + para) if needs_newline else para
					if speaker == "narrator" or speaker == "":
						line.type = "narrator"
						line.text = display_text
					else:
						line.type = "dialogue"
						line.speaker_tag = speaker
						if character_manager:
							var c = character_manager.get_character(speaker)
							line.speaker_name = c.name if c else speaker
							line.color = c.color if c else Color.WHITE
						else:
							line.speaker_name = speaker
							line.color = Color.WHITE
						line.text = display_text
						line.emotion = emotion if is_first_line else ""  # Only show emotion on first line
					pd.add_line(line)
					is_first_line = false
				
				var raw_line = ""
				if speaker == "narrator" or speaker == "":
					raw_line = text
				else:
					raw_line = '%s: "%s"' % [speaker, text]

				var merge_history = seamless
				
				# Implicit merge logic: If visual history ends with a space, it implies a split sentence.
				if not merge_history and dialogue_display_manager:
					var last_vis = dialogue_display_manager.get_current_raw_response()
					# Merge if last visual content ends with space (continuation) and isn't a tag
					if last_vis.ends_with(" ") and not last_vis.strip_edges().begins_with("["):
						merge_history = true

				dialogue_display_manager.preserve_history = true
				# Enable auto-advance so dialogue flows smoothly without clicks
				dialogue_display_manager.set_auto_advance(true, 0.1)
				dialogue_display_manager.play_sequence(pd, raw_line, false, merge_history)
				if not dialogue_display_manager.dialogue_sequence_finished.is_connected(_on_dialogue_finished):
					dialogue_display_manager.dialogue_sequence_finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
			else:
				print(speaker, ": ", text)
				_process_next_action()

		"set_variable":
			var var_name = action.get("var_name", "")
			var val = action.get("value")
			var operation = action.get("operation", "set") # set, merge, add_key, remove_key
			
			if main_node and var_name != "":
				var current_val = main_node.global_vars.get(var_name)
				
				match operation:
					"set":
						main_node.global_vars[var_name] = val
					
					"merge":
						if typeof(current_val) == TYPE_DICTIONARY and typeof(val) == TYPE_DICTIONARY:
							current_val.merge(val, true)
						elif typeof(current_val) != TYPE_DICTIONARY:
							# If not a dict, overwrite as dict
							main_node.global_vars[var_name] = val
							
					"add_key":
						# Expect val to be a dictionary with one key-value pair or array of keys
						if typeof(current_val) != TYPE_DICTIONARY:
							current_val = {}
							main_node.global_vars[var_name] = current_val
							
						if typeof(val) == TYPE_DICTIONARY:
							current_val.merge(val, true)
						
					"remove_key":
						if typeof(current_val) == TYPE_DICTIONARY:
							var keys_to_remove = []
							if typeof(val) == TYPE_ARRAY:
								keys_to_remove = val
							elif typeof(val) == TYPE_STRING:
								keys_to_remove.append(val)
							
							for k in keys_to_remove:
								current_val.erase(k)
				
				# Sync persona fields when setting sex, species, or race
				if var_name in ["sex", "species", "race"] and main_node.settings_manager:
					main_node.settings_manager.update_active_persona_field(var_name, str(val))
					print("Event: Updated active persona %s to: %s" % [var_name, str(val)])

			_process_next_action()

		"branch":
			var prompt = _resolve_vars(action.get("prompt", ""))
			if skip_branch_prompt:
				prompt = ""
				skip_branch_prompt = false
				
			var options = action.get("options", [])
			var valid_options = [] # Array of option dictionaries
			
			for opt in options:
				var cond = opt.get("condition")
				# Fallback logic handled by simple order checking effectively
				# If we want explicit fallback, we should check it.
				# For now, just show all valid options.
				if _check_condition(cond):
					valid_options.append(opt)
			
			if valid_options.is_empty():
				_process_next_action()
				return
			
			# Resolve labels in options
			var resolved_options = []
			for opt in valid_options:
				var new_opt = opt.duplicate()
				new_opt["label"] = _resolve_vars(opt.get("label", "Choice"))
				resolved_options.append(new_opt)

			# Display prompt if present
			if prompt != "" and dialogue_display_manager:
				var line = DialogueParser.DialogueLine.new()
				line.type = "narrator"
				line.text = prompt
				var pd = DialogueParser.ParsedDialogue.new()
				pd.add_line(line)
				dialogue_display_manager.preserve_history = true
				# Enable auto-advance so prompt types and then shows choices
				dialogue_display_manager.set_auto_advance(true, 0.1)
				dialogue_display_manager.play_sequence(pd, prompt, false)
				
				# Record prompt in history so LLM knows context
				event_history.append({"type": "dialogue", "speaker": "narrator", "text": prompt})
				
				# Wait for typing to finish before showing choices
				waiting_for_choice = true
				pending_branch_options = resolved_options
				if not dialogue_display_manager.dialogue_sequence_finished.is_connected(_on_branch_prompt_finished):
					dialogue_display_manager.dialogue_sequence_finished.connect(_on_branch_prompt_finished, CONNECT_ONE_SHOT)
			else:
				# No prompt - show choices immediately
				waiting_for_choice = true
				request_branch.emit(resolved_options)
			# We WAIT here. The UI (Main -> DialogueDisplayManager) must call `select_branch_option` on us.

		"conditional_branch":
			var options = action.get("options", [])
			var matched = false
			var fallback_option = null
			
			# First pass: check non-fallback conditions
			for opt in options:
				var cond = opt.get("condition")
				# Check if this is a fallback option
				if cond != null and typeof(cond) == TYPE_DICTIONARY and cond.get("is_fallback", false):
					fallback_option = opt
					continue # Skip fallback options in first pass
				
				# Check regular condition
				if _check_condition(cond):
					# Found a match!
					var branch_actions = opt.get("actions", [])
					# Insert actions into sequence
					for i in range(branch_actions.size() -1, -1, -1):
						current_event_sequence.insert(current_action_index, branch_actions[i])
					
					matched = true
					break # Only execute the first matching branch
			
			# If no regular conditions matched, use fallback if available
			if not matched and fallback_option != null:
				var branch_actions = fallback_option.get("actions", [])
				for i in range(branch_actions.size() -1, -1, -1):
					current_event_sequence.insert(current_action_index, branch_actions[i])
				matched = true
			
			if not matched:
				print("Conditional Branch: No conditions met and no fallback, continuing.")
				
			_process_next_action()

		"create_checkpoint":
			_process_next_action()

		"return_to_checkpoint":
			var target_id = _resolve_vars(action.get("checkpoint_id", ""))
			var found_idx = -1
			for i in range(current_event_sequence.size()):
				var seq_action = current_event_sequence[i]
				if seq_action.get("type") == "create_checkpoint":
					var c_id = _resolve_vars(seq_action.get("checkpoint_id", ""))
					if c_id == target_id:
						found_idx = i
						break
			
			if found_idx != -1:
				current_action_index = found_idx + 1
				_process_next_action()
			else:
				_process_next_action()

		"create_group":
			var group_id = _resolve_vars(action.get("group_id", ""))
			var members: Array = action.get("members", [])
			
			if sprite_manager and group_id != "" and members.size() > 0:
				# Update the group map in sprite manager
				for member_tag in members:
					sprite_manager.current_group_map[member_tag] = group_id
				
				# Rebuild the layout with new grouping
				sprite_manager.update_layout()
			
			_process_next_action()

		"advance_time":
			var mode = action.get("mode", "next_day_morning")
			var target_slot_name = action.get("target_slot", "morning")
			
			# Fade Out
			if main_node:
				var tween = main_node.fade_screen(false, 1.0)
				if tween: await tween.finished

			var current_day = int(main_node.global_vars.get("day_index", 0))
			var current_slot = int(main_node.global_vars.get("time_slot", 0))
			
			if mode == "next_day_morning":
				current_day += 1
				current_slot = 0 # Morning
				
			elif mode == "next_time_slot":
				current_slot += 1
				if current_slot > 2: # Night -> Next Morning
					current_slot = 0
					current_day += 1
					
			elif mode == "specific_time":
				# Map target name to int
				var t_int = 0
				if target_slot_name == "day": t_int = 1
				elif target_slot_name == "night": t_int = 2
				
				# If target is earlier or same as current, assume next day
				if t_int <= current_slot:
					current_day += 1
				current_slot = t_int
			
			# Update Globals
			main_node.global_vars["day_index"] = current_day
			main_node.global_vars["time_slot"] = current_slot
			
			# Refresh Stats (Visuals)
			if main_node.stats_manager:
				main_node.stats_manager.update_stat("day_index", current_day)
				main_node.stats_manager.update_stat("time_slot", current_slot)
				
			# Refresh Schedule/World
			if main_node.has_method("_handle_schedule_for_location"):
				var loc_id = main_node.global_vars.get("current_location_id", "")
				if loc_id != "":
					main_node._handle_schedule_for_location(loc_id)
			
			# Fade In
			if main_node:
				var tween = main_node.fade_screen(true, 1.0)
				if tween: await tween.finished
				
			_process_next_action()

		"end_event":
			_end_event()

		"llm_prompt":
			_execute_llm_prompt(action)


		"modify_inventory":
			var op = action.get("operation", "add")
			var item_id = _resolve_vars(action.get("item_id", ""))
			var amount = int(_resolve_vars(str(action.get("amount", 1))))
			
			if main_node:
				var inv_mgr = main_node.game_manager.get_meta("inventory_manager")
				if not inv_mgr:
					inv_mgr = main_node.get_node_or_null("InventoryManager")
				
				if inv_mgr:
					if op == "add":
						inv_mgr.add_item(item_id, amount)
					elif op == "remove":
						inv_mgr.remove_item(item_id, amount)
				else:
					print("EventManager: InventoryManager not found for modify_inventory.")
			
			_process_next_action()
		
		"edit_persona":
			# Two modes:
			# 1. Direct edit: {"type": "edit_persona", "field": "sex", "value": "male"}
			# 2. Show editor: {"type": "edit_persona", "show_editor": true} or just {"type": "edit_persona"}
			
			# Determine mode: if field is specified, it's a direct edit. Otherwise show editor.
			var field = action.get("field", "")
			var show_editor_val = action.get("show_editor")
			
			# Logic:
			# 1. If field is empty, we MUST show editor (implicit true)
			# 2. If field is present, we default to FALSE (direct edit), unless show_editor is explicitly TRUE
			
			var show_editor = true # Default for empty field
			
			if field != "":
				# Field is present. Default to false.
				show_editor = false
				
				# Check explicit override
				if show_editor_val != null:
					if typeof(show_editor_val) == TYPE_BOOL:
						show_editor = show_editor_val
					elif typeof(show_editor_val) == TYPE_STRING:
						show_editor = show_editor_val.to_lower() == "true"
			
			if show_editor:
				# Emit signal to show the persona editor popup
				# The event will wait until the editor is closed
				waiting_for_dialogue = true
				request_persona_editor.emit()
			else:
				# Direct field edit
				var value = _resolve_vars(str(action.get("value", "")))
				
				if field != "" and main_node and main_node.settings_manager:
					main_node.settings_manager.update_active_persona_field(field, value)
				_process_next_action()
			
		_:
			_process_next_action()

func _execute_llm_prompt(action: Dictionary):
	var usr_prompt = _resolve_vars(action.get("user_prompt", ""))
	
	# Managers
	var settings_mgr = main_node.settings_manager if main_node else null
	var loc_mgr = location_manager
	var stats_mgr = main_node.stats_manager if main_node else null
	var loc_graph_mgr = main_node.location_graph_manager if main_node else null
	var mem_mgr = main_node.memory_manager if main_node else null
	var char_mgr = character_manager
	
	# Build Context - memory_manager provides "Story so far:" context
	var context_data = PromptBuilderUtils.build_world_context(loc_mgr, stats_mgr, loc_graph_mgr, char_mgr, mem_mgr, settings_mgr)
	var full_context_string = context_data.context_string
	
	# Note: We don't append DDM history separately - memory_manager already provides conversation context
	# This avoids duplication between "Story so far:" and "Recent Event History:"
	
	# Determine characters (override or use all active)
	var specified_tags = action.get("characters", [])
	var chars = []
	if specified_tags.size() > 0 and char_mgr:
		for tag in specified_tags:
			var c = char_mgr.get_character(tag)
			if c: chars.append(c)
	else:
		chars = context_data.characters # Use all active
	
	# Build Scene Prompt
	# Note: build_scene_prompt handles adding Format Rules and Character Appearance
	var prompt_info = PromptBuilderUtils.build_scene_prompt(chars, full_context_string, usr_prompt, settings_mgr)
	
	var system_prompt = prompt_info.get("system_prompt", "")
	var post_instructions = prompt_info.get("post_story_instructions", "")
	
	# Determine if we have meaningful conversation history (actual dialogue, not just setup)
	var has_meaningful_history: bool = false
	for item in event_history:
		if item.type == "dialogue" and item.speaker != "" and item.speaker != "ALL":
			has_meaningful_history = true
			break
		if item.type == "choice":
			has_meaningful_history = true
			break
	
	var final_user_prompt: String
	if has_meaningful_history:
		final_user_prompt = "Continuing the story based on the context."
	else:
		final_user_prompt = "Begin the scene based on the context provided."
		
	if post_instructions != "":
		final_user_prompt += "\n" + post_instructions

	if llm_client:
		waiting_for_dialogue = true
		if not llm_client.response_received.is_connected(_on_llm_response_received):
			llm_client.response_received.connect(_on_llm_response_received, CONNECT_ONE_SHOT)
		
		# DEBUG: Print context
		print("\n--- DEBUG: LLM Prompt Context ---")
		print("SYSTEM PROMPT:\n", system_prompt)
		print("\n", final_user_prompt)
		print("---------------------------------\n")

		if dialogue_display_manager and dialogue_display_manager.dialogue_panel:
			dialogue_display_manager.dialogue_panel.set_waiting_for_response(true)
		
		llm_client.send_request(system_prompt, final_user_prompt)
	else:
		_process_next_action()

func _on_dialogue_finished():
	waiting_for_dialogue = false
	if dialogue_display_manager:
		dialogue_display_manager.set_auto_advance(false)
	
	# Check if next action is a location change - if so, pause for user click
	if current_action_index < current_event_sequence.size():
		var next_action = current_event_sequence[current_action_index]
		if next_action.get("type", "") == "change_location":
			# Show Continue button and wait for click before location change
			waiting_for_continue = true  # Indicate we're waiting for user click
			if dialogue_display_manager and dialogue_display_manager.dialogue_panel:
				dialogue_display_manager.dialogue_panel.continue_button.visible = true
				dialogue_display_manager.dialogue_panel.continue_button.text = "Continue"
				dialogue_display_manager.dialogue_panel.continue_button.disabled = false
			# Don't auto-advance - wait for user to click Continue
			# _process_next_action() will be called from Main._on_end_scene_pressed()
			return
	
	# Auto-advance to next action - dialogue flows like LLM responses
	# Branches/choices will still pause naturally since they set waiting_for_choice
	_process_next_action()

## Called when a branch prompt finishes typing - now show the choices
func _on_branch_prompt_finished():
	if not pending_branch_options.is_empty():
		# Disable auto-advance - choices require user selection
		if dialogue_display_manager:
			dialogue_display_manager.set_auto_advance(false)
		request_branch.emit(pending_branch_options)
		pending_branch_options = []

func _on_llm_response_received(text: String):
	# Display via Main/DialogueDisplayManager
	# Since EventManager is running, we want to pipe this through the dialogue system
	if dialogue_display_manager:
		if dialogue_display_manager.dialogue_panel:
			dialogue_display_manager.dialogue_panel.set_waiting_for_response(false)
			
		# Parse and Play
		var parsed = DialogueParser.parse(text, character_manager)
		# Add to history
		event_history.append({"type": "dialogue", "speaker": "ALL", "text": text}) # Abstracted for block
		
		# Add all mentioned characters to active list (ensures they are in context for next turn)
		var mentioned_chars = DialogueParser.get_mentioned_characters(text)
		for tag in mentioned_chars:
			if character_manager.get_character(tag):
				character_manager.add_active_character(tag)
		
		waiting_for_dialogue = true
		dialogue_display_manager.preserve_history = true
		dialogue_display_manager.play_sequence(parsed, text, false)
		# Connect to interactive finish handler instead of auto-advance
		if not dialogue_display_manager.dialogue_sequence_finished.is_connected(_on_llm_turn_finished_interactive):
			dialogue_display_manager.dialogue_sequence_finished.connect(_on_llm_turn_finished_interactive, CONNECT_ONE_SHOT)
	else:
		_process_next_action()

func _on_llm_turn_finished_interactive():
	# Allow user to respond (multi-turn)
	waiting_for_dialogue = false
	
	# Check if any characters are still present
	var has_characters = false
	if character_manager:
		has_characters = character_manager.get_active_characters().size() > 0
	
	print("DEBUG: _on_llm_turn_finished_interactive - has_characters=%s" % has_characters)
	
	if has_characters:
		# Characters present - show input for user interaction
		if dialogue_display_manager:
			dialogue_display_manager.set_auto_advance(false)
			dialogue_display_manager.show_user_input("What do you say or do?", "", true)
		# User must press "Continue" to advance event
	else:
		# No characters - auto-continue to next action
		print("DEBUG: No characters present, auto-continuing event")
		if dialogue_display_manager and dialogue_display_manager.dialogue_panel:
			dialogue_display_manager.dialogue_panel.hide_input()
		_process_next_action()

## Called when the persona editor popup is closed
func on_persona_editor_closed() -> void:
	waiting_for_dialogue = false
	_process_next_action()

func _end_event():
	is_event_running = false
	# Reset all waiting flags
	waiting_for_dialogue = false
	waiting_for_choice = false
	waiting_for_continue = false
	
	# Clear group map so grouped characters don't persist after event
	if sprite_manager:
		sprite_manager.current_group_map.clear()
	
	if dialogue_display_manager:
		# Use consolidated method to disable input
		dialogue_display_manager.set_input_mode(false)
	event_finished.emit()

func _check_condition(cond) -> bool:
	if cond == null: return true
	if typeof(cond) != TYPE_DICTIONARY: return true
	
	if cond.has("list") and typeof(cond["list"]) == TYPE_ARRAY:
		var mode = cond.get("mode", "ALL")
		var req_count = int(cond.get("count", 1))
		var passed = 0
		var list = cond["list"]
		
		for sub in list:
			if _check_condition(sub):
				passed += 1
		
		if mode == "ALL":
			return passed == list.size()
		elif mode == "AT_LEAST":
			return passed >= req_count
		else:
			return passed == list.size()

	var passed_var_check = true
	var passed_item_check = true
	var has_var_check = false
	var has_item_check = false

	var var_name = cond.get("var_name", "")
	if var_name != "":
		has_var_check = true
		if not main_node:
			passed_var_check = false
		else:
			var current_val = null
			# Check for persona fields first
			var persona_fields = ["sex", "species", "race", "name", "appearance"]
			if var_name in persona_fields and main_node.settings_manager:
				var persona = main_node.settings_manager.get_active_persona()
				current_val = str(persona.get(var_name, ""))
			elif var_name == "player_location" or var_name == "location":
				# Map legacy location check to global_vars ID
				current_val = main_node.global_vars.get("current_location_id", "")
			else:
				current_val = main_node.global_vars.get(var_name)
			
			var target_val = cond.get("value")
			
			# Resolve placeholders {{var}}
			var _resolve_ph = func(v):
				if typeof(v) != TYPE_STRING: return v
				if not "{{" in v: return v
				var regex = RegEx.new()
				regex.compile("\\{\\{(.+?)\\}\\}")
				var res_str = v
				var match_r = regex.search(res_str)
				while match_r:
					var tag = match_r.get_string(1).strip_edges()
					var sub = str(main_node.global_vars.get(tag, ""))
					res_str = res_str.replace(match_r.get_string(0), sub)
					match_r = regex.search(res_str)
				return res_str
			
			if typeof(target_val) == TYPE_STRING:
				target_val = _resolve_ph.call(target_val)
			elif typeof(target_val) == TYPE_DICTIONARY and target_val.has("values"):
				# Duplicate to avoid mutating shared data
				target_val = target_val.duplicate(true)
				var new_vals = []
				for item in target_val["values"]:
					if typeof(item) == TYPE_STRING:
						new_vals.append(_resolve_ph.call(item))
					else:
						new_vals.append(item)
				target_val["values"] = new_vals

			var op = cond.get("operator", "==")
			
			match op:
				"is_true": passed_var_check = (bool(current_val) == true)
				"is_false": passed_var_check = (bool(current_val) == false)
				"==": passed_var_check = (str(current_val) == str(target_val))
				"!=": passed_var_check = (str(current_val) != str(target_val))
				">": passed_var_check = (float(current_val) > float(target_val))
				"<": passed_var_check = (float(current_val) < float(target_val))
				">=": passed_var_check = (float(current_val) >= float(target_val))
				"<=": passed_var_check = (float(current_val) <= float(target_val))
				"has": 
					if typeof(current_val) != TYPE_ARRAY: passed_var_check = false
					else:
						if typeof(target_val) == TYPE_DICTIONARY and target_val.has("values"):
							var t_list = target_val["values"]
							var mode = target_val.get("mode", "ANY")
							var req = int(target_val.get("count", 1))
							var matches = 0
							for t in t_list:
								for item in current_val:
									if str(item) == str(t):
										matches += 1
										break
							
							if mode == "ALL": passed_var_check = (matches == t_list.size())
							elif mode == "AT_LEAST": passed_var_check = (matches >= req)
							else: passed_var_check = (matches > 0)
						else:
							passed_var_check = false
							for item in current_val:
								if str(item) == str(target_val): 
									passed_var_check = true
									break
				"does_not_have":
					if typeof(current_val) != TYPE_ARRAY: passed_var_check = true
					else:
						if typeof(target_val) == TYPE_DICTIONARY and target_val.has("values"):
							var t_list = target_val["values"]
							var mode = target_val.get("mode", "ANY")
							var req = int(target_val.get("count", 1))
							var matches = 0
							for t in t_list:
								for item in current_val:
									if str(item) == str(t):
										matches += 1
										break
							
							if mode == "ALL": passed_var_check = not (matches == t_list.size())
							elif mode == "AT_LEAST": passed_var_check = not (matches >= req)
							else: passed_var_check = not (matches > 0)
						else:
							passed_var_check = true
							for item in current_val:
								if str(item) == str(target_val): 
									passed_var_check = false
									break
				"is_empty":
					if typeof(current_val) == TYPE_ARRAY: passed_var_check = current_val.is_empty()
					elif typeof(current_val) == TYPE_DICTIONARY: passed_var_check = current_val.is_empty()
					elif typeof(current_val) == TYPE_STRING: passed_var_check = (current_val == "")
					else: passed_var_check = (current_val == null)
				"is_not_empty":
					if typeof(current_val) == TYPE_ARRAY: passed_var_check = not current_val.is_empty()
					elif typeof(current_val) == TYPE_DICTIONARY: passed_var_check = not current_val.is_empty()
					elif typeof(current_val) == TYPE_STRING: passed_var_check = (current_val != "")
					else: passed_var_check = (current_val != null)
				"has_key":
					if typeof(current_val) != TYPE_DICTIONARY: passed_var_check = false
					else: passed_var_check = current_val.has(str(target_val))
				"does_not_have_key":
					if typeof(current_val) != TYPE_DICTIONARY: passed_var_check = true
					else: passed_var_check = not current_val.has(str(target_val))
				"value_equals":
					# target_val should be { "key": "k", "value": "v" }
					if typeof(current_val) != TYPE_DICTIONARY: passed_var_check = false
					elif typeof(target_val) != TYPE_DICTIONARY: passed_var_check = false
					else:
						var key = target_val.get("key")
						var val = target_val.get("value")
						if not current_val.has(key): passed_var_check = false
						else: passed_var_check = (str(current_val[key]) == str(val))
				"value_not_equals":
					if typeof(current_val) != TYPE_DICTIONARY: passed_var_check = true
					elif typeof(target_val) != TYPE_DICTIONARY: passed_var_check = true
					else:
						var key = target_val.get("key")
						var val = target_val.get("value")
						if not current_val.has(key): passed_var_check = true # Key missing implies not equal
						else: passed_var_check = (str(current_val[key]) != str(val))
				_:
					print("EventManager: Unknown operator or failed check: ", var_name, " ", op, " ", target_val)
					passed_var_check = false
	
	# Item Check
	var items = cond.get("items", [])
	# Backward Compatibility
	if items.is_empty():
		var s_id = cond.get("item_id", "")
		if s_id != "":
			items.append({ "item_id": s_id, "amount": int(cond.get("item_amount", 1)), "not_has": false })

	if not items.is_empty():
		has_item_check = true
		if not main_node:
			passed_item_check = false
		else:
			var inv_mgr = main_node.game_manager.get_meta("inventory_manager")
			if not inv_mgr:
				inv_mgr = main_node.get_node_or_null("InventoryManager")
				
			if inv_mgr:
				var passed_count = 0
				var required_count = 0
				var mode = cond.get("item_mode", "ALL")
				var req_n = int(cond.get("item_min_count", 1))
				
				# Filter valid checks first to know total size for ALL check
				var valid_checks = []
				for item in items:
					if item.get("item_id", "") != "":
						valid_checks.append(item)
				
				for item in valid_checks:
					var i_id = item.get("item_id", "")
					var amt = int(item.get("amount", 1))
					var not_has = item.get("not_has", false)
					
					var has = inv_mgr.has_item(i_id, amt)
					var check_passed = false
					
					if not_has:
						if not has: check_passed = true
					else:
						if has: check_passed = true
					
					if check_passed:
						passed_count += 1
				
				if mode == "ALL":
					passed_item_check = (passed_count == valid_checks.size())
				elif mode == "ANY":
					passed_item_check = (passed_count > 0)
				elif mode == "AT_LEAST":
					passed_item_check = (passed_count >= req_n)
				else:
					passed_item_check = (passed_count == valid_checks.size())

			else:
				print("EventManager: InventoryManager not found for check.")
				passed_item_check = false
	
	# Persona Check
	var passed_persona_check = true
	var has_persona_check = false
	var persona_cond = cond.get("persona", {})
	
	if not persona_cond.is_empty():
		has_persona_check = true
		if not main_node or not main_node.settings_manager:
			passed_persona_check = false
		else:
			var persona = main_node.settings_manager.get_active_persona()
			# All specified fields must match
			for field in persona_cond.keys():
				var required_val = str(persona_cond[field])
				var actual_val = str(persona.get(field, ""))
				if actual_val.to_lower() != required_val.to_lower():
					passed_persona_check = false
					break
	
	if not has_var_check and not has_item_check and not has_persona_check:
		return false # Empty condition is fail (unless handled elsewhere, but assuming empty means unconfigured)

	return passed_var_check and passed_item_check and passed_persona_check

# Called by UI when a branch option is clicked
func select_branch_option(option_index: int, options_list: Array):
	print("EventManager: select_branch_option index=", option_index)
	waiting_for_choice = false
	if option_index < 0 or option_index >= options_list.size():
		print("EventManager: Invalid option index")
		return
	
	var option = options_list[option_index]
	var label = option.get("label", "Choice")
	var reverts_prompt = option.get("reverts_prompt", false)
	
	if reverts_prompt:
		# Remove the previous prompt from history
		if not event_history.is_empty():
			var last = event_history.back()
			# Verify it's the prompt we expect (narrator)
			if last.type == "dialogue" and (last.speaker == "narrator" or last.speaker == ""):
				event_history.pop_back()
		
		# Also revert via DDM
		if dialogue_display_manager and dialogue_display_manager.has_method("pop_last_history_entry"):
			dialogue_display_manager.pop_last_history_entry()
		
		# Also revert from memory
		if main_node and main_node.memory_manager and main_node.memory_manager.has_method("pop_last_entry"):
			main_node.memory_manager.pop_last_entry()
			
	else:
		event_history.append({"type": "choice", "text": label})
		
		# Manually append choice to dialogue display history so it appears in edit mode
		if dialogue_display_manager:
			# Check if the VISUAL history ends with a space (split sentence continuation)
			var last_vis = dialogue_display_manager.get_current_raw_response()
			var merged_into_last = false
			if last_vis.ends_with(" "):
				# Continue the sentence seamlessly - label WITHOUT extra leading space
				dialogue_display_manager.append_to_last_history_entry(label)
				merged_into_last = true
			elif event_history.size() > 1:
				var prev = event_history[event_history.size() - 2]
				if prev.type == "dialogue" and (prev.speaker == "narrator" or prev.speaker == ""):
					# Previous was narration but didn't end with space - add space before label
					dialogue_display_manager.append_to_last_history_entry(" " + label)
					merged_into_last = true
				else:
					# Not narration - add as new entry
					dialogue_display_manager.append_to_history(label)
			else:
				dialogue_display_manager.append_to_history(label)
			
			# Sync memory with DDM - update the last memory entry if we merged
			if merged_into_last and main_node and main_node.memory_manager:
				var updated_text = dialogue_display_manager.get_current_raw_response()
				var loc_mgr = main_node.location_manager if main_node else null
				if loc_mgr:
					var loc_id = loc_mgr.current_location_id
					var loc_name = ""
					var loc = loc_mgr.get_location(loc_id)
					if loc:
						loc_name = loc.name
					main_node.memory_manager.replace_last_entry(updated_text, loc_id, loc_name, "scene")
	
	var branch_actions = option.get("actions", [])
	# Insert branch actions
	for i in range(branch_actions.size() -1, -1, -1):
		current_event_sequence.insert(current_action_index, branch_actions[i])
	
	_process_next_action()

func _resolve_vars(text: String) -> String:
	if not main_node: return text
	var result = text
	var regex = RegEx.new()
	regex.compile("\\{\\{([^}]+)\\}\\}")
	
	var matches = regex.search_all(text)
	for m in matches:
		var var_key = m.get_string(1).strip_edges()
		var val = ""

		# Special context vars
		if var_key == "EVENT_CONTEXT":
			val = _get_event_context_string()
		elif var_key == "last_choice":
			val = _get_last_choice_text()
		elif var_key == "location":
			# Derive location name from ID
			var loc_id = main_node.global_vars.get("current_location_id", "")
			if main_node.location_manager:
				var loc = main_node.location_manager.get_location(loc_id)
				val = loc.name if loc else loc_id
			else:
				val = loc_id
		elif var_key in ["sex", "species", "race", "name", "appearance"]:
			# Check persona fields
			if main_node.settings_manager:
				var persona = main_node.settings_manager.get_active_persona()
				val = str(persona.get(var_key, ""))
		else:
			# Check global vars
			val = main_node.global_vars.get(var_key, "")
		
		result = result.replace(m.get_string(0), str(val))
		
	return result

func _get_last_choice_text() -> String:
	for i in range(event_history.size() - 1, -1, -1):
		var item = event_history[i]
		if item.type == "choice":
			return item.text
	return ""

func _get_event_context_string() -> String:
	var lines = []
	for item in event_history:
		if item.type == "choice":
			lines.append("Player chose: " + item.text)
		elif item.type == "dialogue":
			lines.append(item.text)
	return "\n".join(lines)
