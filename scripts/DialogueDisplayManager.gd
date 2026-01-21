class_name DialogueDisplayManager
extends Node

signal dialogue_sequence_started
signal dialogue_line_displayed(line: DialogueParser.DialogueLine)
signal dialogue_sequence_finished
signal waiting_for_continue
signal dialogue_interrupted
signal location_changed(location_id: String)
signal raw_response_updated(text: String)
signal dialogue_choice_selected(index: int, options: Array)
signal continue_pressed

var dialogue_panel: EnhancedDialoguePanel
var sprite_manager: Node
var character_manager: Node
var location_manager: Node
var music_manager: Node

# Persisted commands during edit
var preserved_head_commands: Array[String] = []
var preserved_tail_commands: Array[String] = []

var current_sequence: DialogueParser.ParsedDialogue
var current_line_index: int = 0
var is_playing: bool = false
var auto_advance: bool = false
var auto_advance_delay: float = 2.0

var advance_timer: float = 0.0
var preserve_history: bool = false  # Don't clear dialogue on next sequence
var skip_next_user_prompt: bool = false

# Chat history editing support
var raw_response_history: Array[String] = []  # Store all raw LLM responses
var current_raw_response: String = ""  # Current response being displayed
var edit_mode_enabled: bool = false
var preserved_user_input_text: String = ""
var auto_show_input: bool = true
var last_sequence_was_merge: bool = false

func _init(p_dialogue_panel: EnhancedDialoguePanel, p_sprite_manager: Node, p_character_manager: Node):
	dialogue_panel = p_dialogue_panel
	sprite_manager = p_sprite_manager
	character_manager = p_character_manager

func _ready() -> void:
	if dialogue_panel:
		dialogue_panel.continue_pressed.connect(_on_continue_pressed)
		dialogue_panel.interrupt_requested.connect(_on_interrupt_requested)
		dialogue_panel.edit_requested.connect(_on_edit_requested)
		dialogue_panel.edit_saved.connect(_on_edit_saved)
		dialogue_panel.edit_cancelled.connect(_on_edit_cancelled)
		dialogue_panel.choice_selected.connect(_on_panel_choice_selected)

func _process(delta: float) -> void:
	if auto_advance and is_playing and not dialogue_panel.is_animating():
		advance_timer += delta
		if advance_timer >= auto_advance_delay:
			advance_timer = 0.0
			_advance_to_next_line()

## Set whether user input should effectively appear after sequences
## Also manages visibility of the input field
func set_input_mode(enabled: bool, keep_edit_button: bool = false) -> void:
	auto_show_input = enabled
	if not enabled and dialogue_panel:
		dialogue_panel.hide_input(keep_edit_button)
		dialogue_panel.set_interrupt_button_visible(false)

func set_edit_button_visible(visible: bool) -> void:
	if dialogue_panel:
		dialogue_panel.set_edit_button_visible(visible)

## Explicitly request to show the user input field
func show_user_input(placeholder: String = "What do you say or do?", default_text: String = "", show_continue_button: bool = true, button_text: String = "Continue") -> void:
	if dialogue_panel:
		# If we are manually showing input, we probably want to preserve history so it doesn't vanish
		preserve_history = true
		dialogue_panel.show_input(placeholder, default_text, show_continue_button, button_text)
		
		# If input is shown, we usually want to allow interruption or editing?
		# Context dependent, but generally yes.


## Start displaying a parsed dialogue sequence
func play_sequence(parsed_dialogue: DialogueParser.ParsedDialogue, raw_response: String = "", allow_interrupt: bool = true, merge_history: bool = false) -> void:
	current_sequence = parsed_dialogue
	current_line_index = 0
	is_playing = true
	advance_timer = 0.0

	# Store raw response for editing
	last_sequence_was_merge = merge_history
	if raw_response != "":
		if merge_history and not raw_response_history.is_empty():
			var last_idx = raw_response_history.size() - 1
			var prev_text = raw_response_history[last_idx]
			var prev_ends_with_space = prev_text.ends_with(" ") or prev_text.ends_with("\t")
			var text_to_merge = raw_response
			if prev_ends_with_space:
				text_to_merge = raw_response.strip_edges(true, false)  # Strip left only
			
			# Smart spacing logic - add space if needed
			var separator = ""
			if text_to_merge != "":
				var stripped_prev = prev_text.strip_edges()
				# If prev ends with sentence punctuation and new text doesn't start with space, add space
				if stripped_prev.ends_with(".") or stripped_prev.ends_with("!") or stripped_prev.ends_with("?") or stripped_prev.ends_with("\""):
					if not text_to_merge.begins_with(" "):
						separator = " "
				# If prev doesn't end with space and new text doesn't start with space, we may need one
			
			raw_response_history[last_idx] += separator + text_to_merge
			current_raw_response = raw_response_history[last_idx]
			
			# Update current raw response to reflect the merged result
		else:
			raw_response_history.append(raw_response)
			current_raw_response = raw_response

	# Show interrupt button when sequence starts and hide input
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(false)  # Response received, stop "Thinking..." indicator
		dialogue_panel.set_interrupt_button_visible(allow_interrupt)
		dialogue_panel.sequence_active = true
		# Hide input area during playback (will be shown again in _finish_sequence if needed)
		dialogue_panel.hide_input(false)

	dialogue_sequence_started.emit()

	# Clear previous dialogue only if we're not preserving history
	if not preserve_history:
		dialogue_panel.clear_dialogue()
	preserve_history = false  # Reset flag

	# Character and location commands are processed inline to preserve ordering.

	# Start displaying from first line
	_display_current_line()

## Display the current line based on index
func _display_current_line() -> void:
	if not current_sequence or current_line_index >= current_sequence.lines.size():
		_finish_sequence()
		return

	var line = current_sequence.lines[current_line_index]
	print("Displaying line %d/%d: %s - %s" % [current_line_index + 1, current_sequence.lines.size(), line.type, line.speaker_tag])

	# Handle different line types
	match line.type:
		"narrator":
			_display_narrator_line(line)

		"dialogue":
			_display_dialogue_line(line)

		"sprite_command":
			_display_sprite_command(line)

		"location_command":
			_display_location_command(line)

		"character_command":
			_display_character_command(line)

		"group_command":
			_display_group_command(line)

		_:
			# Unknown type, skip to next
			print("Warning: Unknown dialogue line type: ", line.type)
			current_line_index += 1
			_display_current_line()

## Process a character command from dictionary (used at sequence start)
func _process_character_command_dict(cmd: Dictionary) -> void:
	if not sprite_manager:
		return

	var command_type = cmd.get("type", "")
	var tag = cmd.get("tag", "")

	match command_type:
		"character_exit", "exit":
			if sprite_manager.has_method("hide_sprite"):
				sprite_manager.hide_sprite(tag, true)
			elif sprite_manager.has_method("exit_character"):
				sprite_manager.exit_character(tag)
			# Remove from group
			if sprite_manager.current_group_map.has(tag):
				sprite_manager.current_group_map.erase(tag)
			# Also remove from active characters
			if character_manager and character_manager.has_method("remove_active_character"):
				character_manager.remove_active_character(tag)

func _display_character_command(line: DialogueParser.DialogueLine) -> void:
	if line == null:
		current_line_index += 1
		_display_current_line()
		return
	var cmd: Dictionary = {
		"type": line.command_type,
		"tag": line.speaker_tag
	}
	_process_character_command_dict(cmd)
	# Break merge so next narrator line doesn't merge with previous
	if dialogue_panel and dialogue_panel.has_method("break_merge"):
		dialogue_panel.break_merge()
	current_line_index += 1
	_display_current_line()

func _display_sprite_command(line: DialogueParser.DialogueLine) -> void:
	if sprite_manager and sprite_manager.has_method("show_sprite"):
		var emotion: String = line.emotion if line.emotion.strip_edges() != "" else "neutral"
		sprite_manager.show_sprite(line.speaker_tag, emotion, character_manager)
	# Break merge so next narrator line doesn't merge with previous
	if dialogue_panel and dialogue_panel.has_method("break_merge"):
		dialogue_panel.break_merge()
	current_line_index += 1
	_display_current_line()

func _display_group_command(line: DialogueParser.DialogueLine) -> void:
	if not sprite_manager:
		current_line_index += 1
		_display_current_line()
		return
		
	var tags_str = line.text # We stored "tag1 tag2" here
	var tags = tags_str.split(" ", false)
	var group_id = "llm_dynamic_group"
	
	print("Processing group command: ", tags)
	
	if sprite_manager.current_group_map == null:
		sprite_manager.current_group_map = {}
		
	# Overwrite existing dynamic group to avoid endless stacking? 
	for tag in tags:
		sprite_manager.current_group_map[tag] = group_id
		
	# Rebuild layout
	if sprite_manager.has_method("update_layout"):
		sprite_manager.update_layout()

	# Break merge
	if dialogue_panel and dialogue_panel.has_method("break_merge"):
		dialogue_panel.break_merge()
		
	current_line_index += 1
	_display_current_line()

## Display a location command
func _display_location_command(line: DialogueParser.DialogueLine) -> void:
	if not location_manager:
		print("Warning: Cannot change location - location_manager not set")
		current_line_index += 1
		_display_current_line()
		return

	var location_id = line.location_id
	print("Processing location command inline: ", location_id)

	# Change the location
	if location_manager.set_location(location_id):
		# Location changed successfully - emit signal so Main can update background/music
		location_changed.emit(location_id)
	else:
		print("Warning: Failed to change to location: ", location_id)

	# Location commands don't display anything, just advance to next line
	# Break merge so next narrator line doesn't merge with previous
	if dialogue_panel and dialogue_panel.has_method("break_merge"):
		dialogue_panel.break_merge()
	current_line_index += 1
	_display_current_line()

## Display a narrator line
func _display_narrator_line(line: DialogueParser.DialogueLine) -> void:
	await dialogue_panel.display_narration(
		line.text,
		true
	)

	dialogue_line_displayed.emit(line)
	waiting_for_continue.emit()

## Display a character dialogue line
func _display_dialogue_line(line: DialogueParser.DialogueLine) -> void:
	# Update sprite if we have emotion info
	if not line.emotion.is_empty() and sprite_manager:
		if sprite_manager.has_method("show_sprite"):
			sprite_manager.show_sprite(line.speaker_tag, line.emotion, character_manager)

	# Display the dialogue
	await dialogue_panel.display_line(
		line.speaker_name,
		line.text,
		line.color,
		true
	)

	dialogue_line_displayed.emit(line)
	waiting_for_continue.emit()

## Advance to the next line in the sequence
func _advance_to_next_line() -> void:
	if not is_playing:
		return

	current_line_index += 1
	_display_current_line()



## Finish the current dialogue sequence
func _finish_sequence() -> void:
	print("Dialogue sequence finished")
	is_playing = false
	current_sequence = null
	current_line_index = 0
	advance_timer = 0.0

	# Hide interrupt button when sequence finishes
	if dialogue_panel:
		dialogue_panel.set_interrupt_button_visible(false)
		dialogue_panel.sequence_active = false

	# Capture state before emitting signal
	var should_show_input = auto_show_input

	dialogue_sequence_finished.emit()

	# Automatically show input field for user to continue the conversation
	if dialogue_panel and should_show_input:
		preserve_history = true
		if skip_next_user_prompt:
			skip_next_user_prompt = false
			return
		dialogue_panel.show_input("What do you say or do?", "", true)

func _on_continue_pressed() -> void:
	if dialogue_panel.is_animating():
		# Currently animating: skip to show full line immediately
		dialogue_panel.skip_typing()
		return
	
	if is_playing:
		# Not animating, but sequence is playing. 
		# Advance to next line (or finish sequence).
		# We do NOT want to emit continue_pressed, as that triggers "End Scene" logic.
		_advance_to_next_line()
		return

	# If we are here, it means we were NOT playing (e.g. input mode / idle).
	# This is an explicit "Continue/End Scene" request.
	continue_pressed.emit()

# Handle interrupt request from dialogue panel
func _on_interrupt_requested() -> void:
	# Allow interrupt even when sequence is finished
	if is_playing:
		print("Dialogue interrupted at line %d/%d" % [current_line_index + 1, current_sequence.lines.size()])
	else:
		print("User wants to add input after dialogue finished")

	is_playing = false
	advance_timer = 0.0

	# Preserve dialogue history for the next sequence
	preserve_history = true

	# Emit signal so Main.gd can prompt user for their input
	dialogue_interrupted.emit()

	# Show input field for user response
	dialogue_panel.show_input("What do you say or do?")

## Set auto-advance mode (automatically progress through dialogue)
func set_auto_advance(enabled: bool, delay: float = 2.0) -> void:
	auto_advance = enabled
	auto_advance_delay = max(0.0, delay)
	advance_timer = 0.0

## Stop the current sequence
func stop() -> void:
	is_playing = false
	advance_timer = 0.0

## Pause the current sequence
func pause() -> void:
	is_playing = false

## Resume the paused sequence
func resume() -> void:
	if current_sequence and current_line_index < current_sequence.lines.size():
		is_playing = true

## Skip to the end of the sequence
func skip_to_end() -> void:
	_finish_sequence()

func skip_prompt_after_next_sequence() -> void:
	skip_next_user_prompt = true

## Get the current line being displayed
func get_current_line() -> DialogueParser.DialogueLine:
	if current_sequence and current_line_index < current_sequence.lines.size():
		return current_sequence.lines[current_line_index]
	return null

## Check if a sequence is currently playing
func is_sequence_playing() -> bool:
	return is_playing

## Get progress through current sequence (0.0 to 1.0)
func get_progress() -> float:
	if not current_sequence or current_sequence.lines.is_empty():
		return 0.0
	return float(current_line_index) / float(current_sequence.lines.size())

## Get the current raw response for editing
func get_current_raw_response() -> String:
	return current_raw_response

## Get the full raw response history (for editing or debugging)
func get_raw_response_history() -> Array[String]:
	return raw_response_history.duplicate()

## Get the full raw response history as a single string
func get_full_history_text() -> String:
	return build_clean_history_text()

## Manually append text to the history (e.g. for choices)
func append_to_history(text: String) -> void:
	raw_response_history.append(text)
	current_raw_response = text

func append_to_last_history_entry(text: String) -> void:
	if raw_response_history.is_empty():
		append_to_history(text)
	else:
		raw_response_history[raw_response_history.size() - 1] += text
		current_raw_response = raw_response_history[raw_response_history.size() - 1]

func build_clean_history_text() -> String:
	if raw_response_history.is_empty():
		return current_raw_response.strip_edges()
	
	# Clean entries - only strip leading/trailing NEWLINES, preserve intentional spaces
	var cleaned_entries: Array[String] = []
	for entry in raw_response_history:
		# Strip only newlines from edges, not spaces
		var cleaned = entry.strip_edges()
		# But we need spacing for prose flow, so preserve if entry had trailing content
		if not cleaned.is_empty():
			cleaned_entries.append(cleaned)
	
	var result = "\n\n".join(cleaned_entries)
	
	# Collapse any triple (or more) newlines down to double newlines
	var regex = RegEx.new()
	regex.compile("\\n{3,}")
	result = regex.sub(result, "\n\n", true)
	
	return result

func _extract_and_preserve_commands(text: String) -> String:
	preserved_head_commands.clear()
	preserved_tail_commands.clear()

	var lines = text.split("\n")
	var content_lines: Array[String] = []

	var location_regex = RegEx.new()
	location_regex.compile("^\\[\\s*(?i:location):\\s*([a-zA-Z0-9_]+)\\]$")
	
	var char_cmd_regex = RegEx.new()
	char_cmd_regex.compile("^\\[\\s*((?i:character_exit|exit|enter|step_aside)):\\s*([a-zA-Z0-9_]+)\\]$")
	
	# Determine content boundaries
	var first_content_idx = -1
	var last_content_idx = -1
	
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.is_empty(): continue
		
		var is_cmd = location_regex.search(line) or char_cmd_regex.search(line)
		
		if not is_cmd:
			if first_content_idx == -1: first_content_idx = i
			last_content_idx = i
	
	# If no content, treat everything as head commands
	if first_content_idx == -1:
		for line in lines:
			var stripped = line.strip_edges()
			if not stripped.is_empty():
				preserved_head_commands.append(stripped)
		return ""

	# Process lines
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		
		if i < first_content_idx:
			# Head block: only save non-empty commands
			if not line.is_empty():
				preserved_head_commands.append(line)
		elif i > last_content_idx:
			# Tail block: only save non-empty commands
			if not line.is_empty():
				preserved_tail_commands.append(line)
		else:
			# Content block (inclusive)
			# Check if it's an embedded command
			var loc_match = location_regex.search(line)
			var char_match = char_cmd_regex.search(line)
			
			if loc_match or char_match:
				# Distribute to head or tail, but DON'T add blank line placeholder
				if loc_match:
					preserved_head_commands.append(line)
				elif char_match:
					var type = char_match.get_string(1).to_lower()
					if type == "enter":
						preserved_head_commands.append(line)
					else:
						preserved_tail_commands.append(line)
			else:
				# It's content or a blank line - preserve it
				content_lines.append(line)

	# Trim leading empty lines
	while not content_lines.is_empty() and content_lines.front().is_empty():
		content_lines.pop_front()
		
	# Trim trailing empty lines
	while not content_lines.is_empty() and content_lines.back().is_empty():
		content_lines.pop_back()

	var result = "\n".join(content_lines)
	
	# Collapse any triple (or more) newlines down to double newlines
	# This handles the gap left when a command was removed
	var collapse_regex = RegEx.new()
	collapse_regex.compile("\\n{3,}")
	result = collapse_regex.sub(result, "\n\n", true)
	
	return result

func _restore_preserved_commands(text: String) -> String:
	var result_lines: Array[String] = []
	
	# Add head commands
	result_lines.append_array(preserved_head_commands)
	
	# Add content (ensure we don't add extra newlines if empty)
	if not text.strip_edges().is_empty():
		result_lines.append(text)
		
	# Add tail commands
	result_lines.append_array(preserved_tail_commands)
	
	return "\n".join(result_lines)

## Enable edit mode
func enable_edit_mode() -> void:
	edit_mode_enabled = true
	if dialogue_panel:
		preserved_user_input_text = dialogue_panel.get_input_text()
	
	var full_text = build_clean_history_text()
	var clean_text = _extract_and_preserve_commands(full_text)
	dialogue_panel.enter_edit_mode(clean_text)

## Disable edit mode
func disable_edit_mode() -> void:
	edit_mode_enabled = false
	dialogue_panel.exit_edit_mode()
	# Clear preserved commands on cancel
	preserved_head_commands.clear()
	preserved_tail_commands.clear()

## Handle edited response - reparse and display (without replaying animation)
func apply_edited_response(edited_text: String) -> void:
	print("Applying edited response...")
	
	# Restore protected commands
	var final_text = _restore_preserved_commands(edited_text)

	# Parse the edited text
	var parsed = DialogueParser.parse(final_text, character_manager)

	# Update raw response tracking
	current_raw_response = final_text
	raw_response_history.clear()
	raw_response_history.append(final_text)
	raw_response_updated.emit(current_raw_response)

	# Update current sequence
	current_sequence = parsed
	current_line_index = 0

	# Clear dialogue panel
	dialogue_panel.clear_dialogue()

	# Display all lines without animation (just parse and show)
	# Must await each line since display_line/display_narration are async
	for line in parsed.lines:
		match line.type:

			"narrator":
				await dialogue_panel.display_narration(line.text, false)
			"dialogue":
				if sprite_manager and sprite_manager.has_method("show_sprite"):
					var emotion: String = line.emotion if line.emotion.strip_edges() != "" else "neutral"
					sprite_manager.show_sprite(line.speaker_tag, emotion, character_manager)
				await dialogue_panel.display_line(line.speaker_name, line.text, line.color, false)
			"sprite_command":
				if sprite_manager and sprite_manager.has_method("show_sprite"):
					var sprite_emotion: String = line.emotion if line.emotion.strip_edges() != "" else "neutral"
					sprite_manager.show_sprite(line.speaker_tag, sprite_emotion, character_manager)
			"character_command":
				var cmd: Dictionary = {
					"type": line.command_type,
					"tag": line.speaker_tag
				}
				_process_character_command_dict(cmd)
			"group_command":
				_display_group_command(line)
			_:
				# Skip other command types (location handled below)
				pass

	# Process location commands to get final location
	var final_location = _get_final_location_from_parsed(parsed)
	if final_location != "":
		print("Switching to final location after edit: ", final_location)
		location_changed.emit(final_location)

	# Exit edit mode and return to user input mode
	edit_mode_enabled = false
	dialogue_panel.exit_edit_mode()

	# Preserve history
	preserve_history = true
	var restored_text = preserved_user_input_text
	preserved_user_input_text = ""
	
	# Only force input if auto-show is on, otherwise respect the restored state from exit_edit_mode
	if auto_show_input:
		dialogue_panel.show_input("What do you say or do?", restored_text)
	elif dialogue_panel.input_field.visible:
		dialogue_panel.input_field.text = restored_text

	# Scroll to bottom after layout updates (deferred to ensure content is rendered)
	# Wait several frames to ensure RichTextLabel has fully calculated its size
	for i in range(5):
		await dialogue_panel.get_tree().process_frame
	dialogue_panel.scroll_to_bottom()
	
	# Restore choices if they were active (prevent them from being lost on edit)
	if not current_options_context.is_empty() and dialogue_panel:
		dialogue_panel.show_choices(current_options_context)

## Extract the final location from parsed dialogue
func _get_final_location_from_parsed(parsed: DialogueParser.ParsedDialogue) -> String:
	# Find the last location command in the sequence
	for i in range(parsed.lines.size() - 1, -1, -1):
		var line = parsed.lines[i]
		if line.type == "location_command":
			return line.location_id
	return ""

## Handle edit mode request from dialogue panel
func _on_edit_requested() -> void:
	print("Edit mode requested")
	enable_edit_mode()

## Handle save from edit mode
func _on_edit_saved(edited_text: String) -> void:
	print("Edit saved, applying changes...")
	apply_edited_response(edited_text)

## Handle cancel from edit mode
func _on_edit_cancelled() -> void:
	print("Edit cancelled")
	disable_edit_mode()
	preserved_user_input_text = ""

## Display a list of choices via the panel
var current_options_context: Array = []

## Remove the last entry from history (used for cancelling prompts)
func pop_last_history_entry() -> void:
	if not raw_response_history.is_empty():
		raw_response_history.pop_back()
		if raw_response_history.is_empty():
			current_raw_response = ""
		else:
			current_raw_response = raw_response_history [raw_response_history.size() - 1]
	
	# Attempt to visually remove the last block from the panel if supported
	# We call this TWICE because visually there are two blocks: 
	# 1. The selected choice text (e.g. "Cancel")
	# 2. The prompt text (e.g. "You find a moment to rest.")
	if dialogue_panel and dialogue_panel.has_method("remove_last_block"):
		dialogue_panel.remove_last_block()
		dialogue_panel.remove_last_block()
		
func display_choices(options: Array) -> void:
	current_options_context = options
	if dialogue_panel:
		dialogue_panel.show_choices(options)

func _on_panel_choice_selected(index: int) -> void:
	print("DialogueDisplayManager: choice selected index=", index)
	var options = current_options_context
	current_options_context = [] # Clear state so we don't restore them inappropriately
	dialogue_choice_selected.emit(index, options)
