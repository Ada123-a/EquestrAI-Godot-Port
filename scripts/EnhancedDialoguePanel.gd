extends Panel
class_name EnhancedDialoguePanel

## Enhanced dialogue panel that displays structured dialogue
## Supports speaker names, character colors, typing animation, and dialogue history

signal continue_pressed
signal nevermind_pressed
signal user_input_submitted(text: String)
signal interrupt_requested
signal edit_requested
signal edit_saved(edited_text: String)
signal edit_cancelled
signal impersonate_requested
signal user_turn_started
signal user_turn_ended
signal choice_selected(index: int)

@onready var dialogue_label: RichTextLabel = %DialogueLabel
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var continue_button: Button = %ContinueButton
@onready var input_area: HBoxContainer = %InputArea
@onready var input_field: TextEdit = %InputField  # EnhancedTextInput (TextEdit with spell check)
@onready var clickable_area: Control = %ClickableArea
@onready var impersonate_button: Button = %ImpersonateButton
@onready var status_label: Label = %StatusLabel

var choices_container: VBoxContainer


var typing_speed: float = 0.03  # Seconds per character
var is_typing: bool = false
var current_text: String = ""  # BBCode version (final target)
var current_text_plain: String = ""  # Plain text version (for typing animation)
var typing_timer: float = 0.0
var char_index: int = 0
@export var user_input_min_height: float = 40.0

var dialogue_history: Array[String] = []  # Full BBCode history
var displayed_bbcode: String = ""  # Current BBCode string shown in the label
var max_history_lines: int = 50  # Prevent infinite growth

var is_displaying: bool = false  # Prevents overlapping display_line calls
var sequence_active: bool = false  # Set by DialogueDisplayManager when a sequence is playing
var allow_click_to_continue: bool = true  # When false, clicking dialogue box won't emit continue_pressed

# Edit mode support
var edit_mode: bool = false
var edit_input: EnhancedTextInput = null  # For editing raw LLM response
var save_edit_button: Button = null
var cancel_edit_button: Button = null
var edit_button_container: HBoxContainer = null
var enter_edit_button: Button = null  # Button to enter edit mode
var stored_raw_text: String = ""  # The raw text being edited
var clickable_area_previous_mouse_filter: int = Control.MOUSE_FILTER_STOP
var waiting_indicator_active: bool = false
var waiting_timer: float = 0.0
var waiting_dot_count: int = 0
const THINKING_INTERVAL := 0.4
var waiting_base_text: String = "Thinking"

# State preservation for edit mode
var _prev_continue_visible: bool = false
var _prev_input_field_visible: bool = false
var _prev_input_area_visible: bool = false
var _prev_edit_btn_visible: bool = false
var _prev_impersonate_visible: bool = false

func _ready() -> void:
	continue_button.pressed.connect(_on_interrupt_pressed)
	input_field.text_committed.connect(_on_input_submitted)
	if dialogue_label:
		dialogue_label.bbcode_enabled = true
	if impersonate_button:
		impersonate_button.visible = false
		impersonate_button.pressed.connect(_on_impersonate_button_pressed)
	if status_label:
		status_label.visible = false
	
	# Setup Choices Container
	choices_container = VBoxContainer.new()
	choices_container.name = "ChoicesContainer"
	choices_container.visible = false
	choices_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_container.add_theme_constant_override("separation", 10)
	
	# Insert into layout (assume inside the main VBox, probably before InputArea)
	# Finding a good place: preferably at the bottom of the scroll container content
	# But scroll container content is a VBox or MarginContainer usually.
	# Let's inspect: The main structure is likely not fully visible here. 
	# Safest bet: Add to the same parent as input_area, but above it.
	if input_area:
		var parent = input_area.get_parent()
		if parent:
			parent.add_child(choices_container)
			parent.move_child(choices_container, input_area.get_index())
	
	_apply_user_input_min_height()

	# Update button text to "Interrupt"
	continue_button.text = "Interrupt"

	# Connect clickable area for click-to-continue
	if clickable_area:
		clickable_area.gui_input.connect(_on_clickable_area_input)
		# Set to STOP so it receives clicks, but handle scroll events specially
		clickable_area.mouse_filter = Control.MOUSE_FILTER_STOP
		clickable_area_previous_mouse_filter = Control.MOUSE_FILTER_STOP

	# Set ScrollContainer to allow scrolling but not duplicate click handling
	if scroll_container:
		scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS

	# CRITICAL: Allow dialogue label to pass mouse events through
	if dialogue_label:
		dialogue_label.mouse_filter = Control.MOUSE_FILTER_PASS
		if not dialogue_label.meta_clicked.is_connected(_on_dialogue_meta_clicked):
			dialogue_label.meta_clicked.connect(_on_dialogue_meta_clicked)

	# Setup edit mode UI
	_setup_edit_mode_ui()
	
	# Ensure ClickableArea is on top so it catches clicks
	if clickable_area:
		clickable_area.move_to_front()
	
	# Move the edit button to front AFTER clickable_area so it's on top and can receive clicks
	if enter_edit_button:
		enter_edit_button.move_to_front()

	# Set initial state
	clear_dialogue()

func _setup_edit_mode_ui() -> void:
	# Create edit input that will replace the DialogueLabel in the SAME scroll container
	# This makes it look exactly like the dialogue panel, just editable
	edit_input = EnhancedTextInput.new()
	edit_input.expand_with_content = true
	edit_input.name = "EditInput"
	edit_input.visible = false
	edit_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Match DialogueLabel's layout settings exactly
	edit_input.layout_mode = 2  # Container layout mode (same as DialogueLabel)
	edit_input.size_flags_horizontal = 3  # SIZE_FILL | SIZE_EXPAND (same as DialogueLabel)
	# Let it grow with content but don't enable internal scrolling
	edit_input.scroll_fit_content_height = true
	# No custom minimum size - let it fill the container naturally
	# Let scroll events bubble up to the ScrollContainer so long responses stay reachable
	edit_input.mouse_filter = Control.MOUSE_FILTER_PASS
	edit_input.gui_input.connect(_on_edit_input_gui_input)
	edit_input.caret_changed.connect(_on_edit_input_caret_changed)

	# Ensure text is visible
	edit_input.add_theme_color_override("font_color", Color.WHITE)

	# Add it to the same scroll container as DialogueLabel
	scroll_container.add_child(edit_input)

	# Create "Edit History" button (shown during user's turn)
	# Place it in the top-right corner of the dialogue container
	var dialogue_container: Control = scroll_container.get_parent()
	enter_edit_button = Button.new()
	enter_edit_button.text = "✏"
	enter_edit_button.tooltip_text = "Edit History"
	enter_edit_button.visible = false
	enter_edit_button.custom_minimum_size = Vector2(40, 40)
	enter_edit_button.pressed.connect(_on_enter_edit_button_pressed)
	# Anchor to top-right corner
	enter_edit_button.anchor_left = 1.0
	enter_edit_button.anchor_right = 1.0
	enter_edit_button.anchor_top = 0.0
	enter_edit_button.anchor_bottom = 0.0
	enter_edit_button.offset_left = -50
	enter_edit_button.offset_right = -5
	enter_edit_button.offset_top = 5
	enter_edit_button.offset_bottom = 50
	enter_edit_button.grow_horizontal = Control.GROW_DIRECTION_END
	enter_edit_button.z_index = 10  # On top
	dialogue_container.add_child(enter_edit_button)
	
	# Adjust ScrollContainer margins to make room for the button
	var scroll_margin_right: int = 55  # Space for the edit button when visible
	scroll_container.add_theme_constant_override("margin_right", 0)  # Default: no extra margin

	# Create button container for save/cancel (next to the input section)
	var input_parent = input_field.get_parent()
	var button_parent: Node = input_parent
	var insert_index: int = 0
	if input_parent:
		if input_parent is HBoxContainer and input_parent.get_parent():
			button_parent = input_parent.get_parent()
			insert_index = input_parent.get_index()
		else:
			button_parent = input_parent
			insert_index = input_field.get_index()

	edit_button_container = HBoxContainer.new()
	edit_button_container.visible = false
	edit_button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	if button_parent:
		button_parent.add_child(edit_button_container)
		button_parent.move_child(edit_button_container, insert_index)

	# Create Save button
	save_edit_button = Button.new()
	save_edit_button.text = "Save Changes"
	save_edit_button.pressed.connect(_on_save_edit_pressed)
	edit_button_container.add_child(save_edit_button)

	# Add spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	edit_button_container.add_child(spacer)

	# Create Cancel button
	cancel_edit_button = Button.new()
	cancel_edit_button.text = "Cancel"
	cancel_edit_button.pressed.connect(_on_cancel_edit_pressed)
	edit_button_container.add_child(cancel_edit_button)

func _process(delta: float) -> void:
	if is_typing:
		typing_timer += delta
		var scrolled_this_frame: bool = false

		while typing_timer >= typing_speed and char_index < current_text_plain.length():
			char_index += 1
			# Use BBCode text but show up to char_index of plain text
			_set_display_text(_get_partial_bbcode(current_text, current_text_plain, char_index))
			typing_timer -= typing_speed
			scrolled_this_frame = true

		# Auto-scroll to bottom as text appears (once per frame)
		if scrolled_this_frame:
			scroll_to_bottom()

		if char_index >= current_text_plain.length():
			is_typing = false
			continue_button.disabled = false
			_set_display_text(current_text)  # Show final BBCode version
			scroll_to_bottom()

	if waiting_indicator_active and status_label:
		waiting_timer += delta
		if waiting_timer >= THINKING_INTERVAL:
			waiting_timer = 0.0
			waiting_dot_count = (waiting_dot_count + 1) % 4
			var dots = ""
			for i in range(waiting_dot_count):
				dots += "."
			var base_text: String = waiting_base_text
			status_label.text = base_text + dots

var last_speaker_name: String = ""

## Clear all dialogue and reset to initial state
func clear_dialogue() -> void:
	_set_display_text("")
	dialogue_history.clear()
	continue_button.disabled = true
	is_typing = false
	last_speaker_name = ""

## Remove the last block of text (used for reverting prompts)
func remove_last_block() -> void:
	if dialogue_history.is_empty():
		return
		
	dialogue_history.pop_back()
	
	# If history is empty now, clear display
	if dialogue_history.is_empty():
		_set_display_text("")
		current_text = ""
		current_text_plain = ""
		dialogue_label.text = ""
		return

	var new_full_text = ""

	for block in dialogue_history:
		if new_full_text != "":
			# Check for "seamless merge" markers if we had them.
			# Without them, we might get extra newlines.
			if block.begins_with("[color") and block.contains(" \""):
				new_full_text += "" # potential merge
			else:
				new_full_text += "\n\n"
		new_full_text += block
		
	_set_display_text(new_full_text)
	current_text = new_full_text
	current_text_plain = _strip_bbcode(new_full_text)
	scroll_to_bottom()

## Display a single line of dialogue with typing animation
func display_line(speaker_name: String, text: String, color: Color = Color.WHITE, animate: bool = true, allow_bbcode: bool = false) -> void:
	# Wait if already displaying a line or currently typing previous line
	while is_displaying or is_typing:
		await get_tree().process_frame

	is_displaying = true
	
	# Determine if we should merge with previous line
	var is_merge: bool = (speaker_name == last_speaker_name) and (dialogue_history.size() > 0)
	
	# Manual break check: if text starts with newline, force break
	if text.begins_with("\n"):
		is_merge = false
		text = text.substr(1) # Remove the newline char as we'll allow separator to handle spacing

	# Prepare the new line with color coding (BBCode version)
	var is_narration: bool = speaker_name.strip_edges().is_empty()
	var clean_text: String = text if allow_bbcode else _sanitize_text_content(text)
	var clean_speaker: String = _sanitize_text_content(speaker_name)
	var new_line_bbcode: String
	var new_line_plain: String
	
	if is_narration:
		# Narration: plain italic text
		new_line_bbcode = "[color=#%s][i]%s[/i][/color]" % [color.to_html(false), clean_text]
		new_line_plain = clean_text
	else:
		# Dialogue: bold speaker name with quoted text
		if is_merge:
			# If merging dialogue, don't repeat speaker name.
			# Format: "Text"
			new_line_bbcode = "[color=#%s] \"%s\"[/color]" % [color.to_html(false), clean_text] # Add space padding?
			new_line_plain = " \"%s\"" % [clean_text]
		else:
			new_line_bbcode = "[color=#%s][b]%s:[/b] \"%s\"[/color]" % [color.to_html(false), clean_speaker, clean_text]
			new_line_plain = "%s: \"%s\"" % [speaker_name, clean_text]

	# Add to history
	dialogue_history.append(new_line_bbcode)

	# Trim history if too long
	if dialogue_history.size() > max_history_lines:
		dialogue_history.pop_front()

	# Get current displayed text
	var existing_text_bbcode = displayed_bbcode
	# Note: retrieving existing plain text from bbcode is expensive/lossy if we reconstruct.
	# Better to assume `displayed_bbcode` is correct.
	var existing_text_plain = _strip_bbcode(existing_text_bbcode)

	# Define separator
	var separator = ""
	if not existing_text_bbcode.is_empty():
		if is_merge:
			separator = "" # Seamless merge
		else:
			separator = "\n\n"

	if animate:
		# Start typing animation for ONLY the new line
		current_text = existing_text_bbcode + separator + new_line_bbcode
		current_text_plain = existing_text_plain + separator + new_line_plain
		char_index = existing_text_plain.length() + separator.length()  # Start from end of existing text
		typing_timer = 0.0
		is_typing = true
		continue_button.disabled = true
		# Keep existing text, don't clear it
		_set_display_text(existing_text_bbcode + separator)
	else:
		# Display immediately
		_set_display_text(existing_text_bbcode + separator + new_line_bbcode)
		is_typing = false
		continue_button.disabled = false
	
	# Update last speaker
	last_speaker_name = speaker_name

	# Scroll to bottom
	await get_tree().process_frame
	scroll_to_bottom()

	is_displaying = false

## Display narration without a speaker label (plain text)
func display_narration(text: String, animate: bool = true) -> void:
	var formatted_text: String = text
	await display_line("", formatted_text, Color(0.8, 0.8, 0.8), animate)

## Break the merge tracking so the next line won't merge with previous
## Call this after processing commands to ensure proper line separation
func break_merge() -> void:
	last_speaker_name = "__break__"

## Skip the current typing animation and show full text
func skip_typing() -> void:
	if is_typing:
		_set_display_text(current_text)  # Show full BBCode version
		char_index = current_text_plain.length()  # Set to end of plain text
		is_typing = false
		continue_button.disabled = false
		scroll_to_bottom()
		_deferred_scroll_to_bottom()

## Scroll the dialogue container to the bottom
func scroll_to_bottom() -> void:
	if scroll_container:
		# Use call_deferred to ensure layout is updated first
		scroll_container.set_deferred("scroll_vertical", scroll_container.get_v_scroll_bar().max_value)

## Show the input field for user responses
## show_continue_button: if true, show the Continue button
## button_text: text for the button (e.g. "Continue", "Nevermind")
func show_input(placeholder: String = "Type your response...", prefill_text: String = "", show_continue_button: bool = false, button_text: String = "Continue") -> void:
	set_waiting_for_response(false)
	if input_area:
		input_area.visible = true
	input_field.visible = true
	input_field.placeholder_text = placeholder
	input_field.text = prefill_text
	input_field.grab_focus()
	
	# Show button with custom text
	continue_button.visible = show_continue_button
	if show_continue_button:
		continue_button.text = button_text
		continue_button.disabled = false 
	
	if impersonate_button:
		impersonate_button.visible = true
		impersonate_button.disabled = false
	_apply_user_input_min_height()

	# Show the "Edit History" button in the top-right corner
	if enter_edit_button:
		enter_edit_button.visible = true

	# Clickable area stays enabled (scroll handled manually in handler)
	user_turn_started.emit()

	# Scroll to bottom after input area appears (it changes layout)
	_deferred_scroll_to_bottom()

## Hide the input field
func hide_input(keep_edit_button: bool = false) -> void:
	if input_area:
		input_area.visible = false
	input_field.visible = false
	# Don't automatically show interrupt button - let set_interrupt_button_visible control it
	if impersonate_button:
		impersonate_button.visible = false

	# Hide the "Edit History" button when not user's turn
	if enter_edit_button and not keep_edit_button:
		enter_edit_button.visible = false

	# Clickable area stays enabled (scroll handled manually in handler)
	user_turn_ended.emit()
	_deferred_scroll_to_bottom()

## Show or hide the interrupt button
## Since ContinueButton is now inside InputArea, we need to show the container too
func set_interrupt_button_visible(visible: bool) -> void:
	if visible:
		# Show the InputArea container but hide the input field itself
		if input_area:
			input_area.visible = true
		input_field.visible = false
		if impersonate_button:
			impersonate_button.visible = false
		continue_button.visible = true
		continue_button.text = "Interrupt"
		continue_button.disabled = false
	else:
		# Just hide the button, don't affect InputArea visibility
		# (InputArea visibility is controlled by show_input/hide_input)
		continue_button.visible = false

## Set whether clicking the dialogue box area should trigger continue/advance
## Used to prevent accidental triggers in free roam mode
func set_click_to_continue_enabled(enabled: bool) -> void:
	allow_click_to_continue = enabled

## Set typing speed (seconds per character)
func set_typing_speed(speed: float) -> void:
	typing_speed = max(0.001, speed)

## Enable or disable typing animation
func set_typing_enabled(enabled: bool) -> void:
	if not enabled and is_typing:
		skip_typing()

func _on_clickable_area_input(event: InputEvent) -> void:
	# Handle click-to-continue on the text box area
	if event is InputEventMouseButton:
		# Handle scroll wheel events by manually scrolling the ScrollContainer
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if scroll_container:
				scroll_container.scroll_vertical -= 30
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if scroll_container:
				scroll_container.scroll_vertical += 30
			return

		# Handle left clicks for continue/skip
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_typing:
				# Currently typing animation - skip to full text
				skip_typing()
			elif sequence_active:
				# A dialogue sequence is playing - clicking should advance it
				continue_pressed.emit()
			elif allow_click_to_continue:
				# Not in sequence, but click-to-continue is allowed (active conversation)
				# Don't emit continue_pressed if input area is visible and user is typing
				# Allow it if input is read-only (e.g. exit confirmation)
				if input_area and input_area.visible and input_field.editable:
					# Just focus the input field instead
					input_field.grab_focus()
				else:
					continue_pressed.emit()
			# else: In free roam mode, clicking does nothing (just scrolls/views history)
			# Accept this event so it doesn't propagate
			get_viewport().set_input_as_handled()

func _on_edit_input_gui_input(event: InputEvent) -> void:
	if scroll_container == null:
		return
	if not edit_mode:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_container.scroll_vertical -= 30
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_container.scroll_vertical += 30
			accept_event()

func _on_edit_input_caret_changed() -> void:
	if not edit_mode or edit_input == null or scroll_container == null:
		return
	# Defer the scroll to next frame so layout has time to update (important for Enter key)
	_scroll_to_edit_caret.call_deferred()

func _scroll_to_edit_caret() -> void:
	if not edit_mode or edit_input == null or scroll_container == null:
		return

	# Use get_caret_draw_pos() which gives the actual pixel position of the caret
	var caret_pos: Vector2 = edit_input.get_caret_draw_pos()
	var line_height: float = edit_input.get_line_height()

	# Get scroll container's visible area
	var scroll_top: float = scroll_container.scroll_vertical
	var scroll_height: float = scroll_container.size.y
	var scroll_bottom: float = scroll_top + scroll_height

	# The caret's absolute Y position within the scrollable content
	var caret_y: float = caret_pos.y

	# Add padding so caret isn't at the very edge
	var padding: float = line_height

	# Scroll down if caret is below visible area
	if caret_y + padding > scroll_bottom:
		scroll_container.scroll_vertical = int(caret_y + padding - scroll_height + line_height)

	# Scroll up if caret is above visible area
	elif caret_y < scroll_top + padding:
		scroll_container.scroll_vertical = int(max(0, caret_y - padding))

func _on_interrupt_pressed() -> void:
	# If button says "Nevermind", user wants to cancel
	if continue_button.text == "Nevermind":
		nevermind_pressed.emit()
		return
	
	# If input is visible and button says "Continue", it's behaving as an "End Scene" / "Advance" button
	if input_area and input_area.visible and continue_button.text == "Continue":
		continue_pressed.emit()
		return

	# Otherwise, it's an interrupt button
	# Interrupt button stops the dialogue and requests user input
	interrupt_requested.emit()

func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return

	user_input_submitted.emit(text)
	hide_input()

## Get the current speaker name (deprecated - speaker shown inline)
func get_current_speaker() -> String:
	return ""

## Check if currently animating text
func is_animating() -> bool:
	return is_typing or is_displaying

## Strip BBCode tags from text to get plain version
func _strip_bbcode(bbcode_text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(bbcode_text, "", true)

func _sanitize_text_content(text: String) -> String:
	var cleaned: String = text
	var patterns: Array[String] = [
		"\\[color=[^\\]]*\\]",
		"\\[/color\\]",
		"\\[b\\]",
		"\\[/b\\]",
		"\\[i\\]",
		"\\[/i\\]",
		"\\[u\\]",
		"\\[/u\\]"
	]

	for pattern in patterns:
		var regex: RegEx = RegEx.new()
		regex.compile(pattern)
		cleaned = regex.sub(cleaned, "", true)

	# cleaned = cleaned.strip_edges() # REMOVED: Preserve whitespace for seamless merging
	if cleaned.is_empty() and not text.is_empty():
		return text # Return original if stripping made it empty but it wasn't
	return cleaned

func _set_display_text(bbcode_text: String) -> void:
	displayed_bbcode = bbcode_text
	if dialogue_label:
		# In Godot 4.x, set the text property directly when bbcode_enabled is true
		dialogue_label.text = bbcode_text

## Get partial BBCode text that shows up to char_count of plain text
## This prevents showing incomplete BBCode tags during typing
func _get_partial_bbcode(bbcode_text: String, plain_text: String, char_count: int) -> String:
	if char_count >= plain_text.length():
		return bbcode_text

	# Build a mapping of plain text position to BBCode position
	# Also track open tags so we can close them properly
	var plain_index: int = 0
	var bbcode_index: int = 0
	var in_tag: bool = false
	var current_tag: String = ""
	var open_tags: Array[String] = []

	while bbcode_index < bbcode_text.length() and plain_index < char_count:
		var c = bbcode_text[bbcode_index]

		if c == '[':
			in_tag = true
			current_tag = ""
		elif c == ']':
			in_tag = false
			# Check if this is an opening or closing tag
			if current_tag.begins_with("/"):
				# Closing tag - remove from open_tags
				var tag_name = current_tag.substr(1)
				# Find and remove the matching open tag (from the end)
				for i in range(open_tags.size() - 1, -1, -1):
					if open_tags[i] == tag_name:
						open_tags.remove_at(i)
						break
			elif not current_tag.is_empty() and not current_tag.contains("="):
				# Simple opening tag like [b] or [i]
				open_tags.append(current_tag)
			elif current_tag.contains("="):
				# Tag with value like [color=#fff]
				var tag_name = current_tag.split("=")[0]
				open_tags.append(tag_name)
			bbcode_index += 1
			continue
		elif in_tag:
			current_tag += c
		else:
			plain_index += 1

		bbcode_index += 1

	# Move past any incomplete tag
	while bbcode_index < bbcode_text.length() and in_tag:
		if bbcode_text[bbcode_index] == ']':
			bbcode_index += 1
			break
		bbcode_index += 1

	var result = bbcode_text.substr(0, bbcode_index)

	# Close any open tags in reverse order
	for i in range(open_tags.size() - 1, -1, -1):
		result += "[/" + open_tags[i] + "]"

	return result

## Enter edit mode - show raw LLM response for editing
func enter_edit_mode(raw_text: String) -> void:
	if edit_mode:
		return  # Already in edit mode

	print("Entering edit mode with raw text: ", raw_text.substr(0, 100), "...")

	edit_mode = true
	stored_raw_text = raw_text

	# Capture current visibility state
	_prev_continue_visible = continue_button.visible
	if input_area:
		_prev_input_area_visible = input_area.visible
	else:
		_prev_input_area_visible = false
	_prev_input_field_visible = input_field.visible
	if enter_edit_button:
		_prev_edit_btn_visible = enter_edit_button.visible
	else:
		_prev_edit_btn_visible = false
	if impersonate_button:
		_prev_impersonate_visible = impersonate_button.visible
	else:
		_prev_impersonate_visible = false

	# Hide continue button, input field, and edit history button
	continue_button.visible = false
	if input_area:
		input_area.visible = false
	input_field.visible = false
	if enter_edit_button:
		enter_edit_button.visible = false
	if impersonate_button:
		impersonate_button.visible = false
	user_turn_ended.emit()

	# CRITICAL: Disable clickable area so edit input can receive mouse events
	if clickable_area:
		clickable_area_previous_mouse_filter = clickable_area.mouse_filter
		clickable_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Swap DialogueLabel for EditInput in the same scroll container
	dialogue_label.visible = false
	if edit_input:
		edit_input.text = raw_text
		edit_input.visible = true

	# Show save/cancel buttons
	if edit_button_container:
		edit_button_container.visible = true

	# Wait for layout to update, then scroll to bottom and place caret at end
	for i in range(3):
		await get_tree().process_frame

	if edit_input:
		var last_line = max(0, edit_input.get_line_count() - 1)
		edit_input.set_caret_line(last_line)
		edit_input.set_caret_column(edit_input.get_line(last_line).length())
		edit_input.grab_focus()

	# Scroll the scroll container to the bottom
	if scroll_container:
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

	print("Edit mode enabled")

## Exit edit mode - return to normal display
func exit_edit_mode() -> void:
	if not edit_mode:
		return

	print("Exiting edit mode")

	edit_mode = false

	# Restore clickable area interaction so the user can click to advance again
	if clickable_area:
		clickable_area.mouse_filter = clickable_area_previous_mouse_filter

	# Swap back: hide EditInput, show DialogueLabel
	if edit_input:
		edit_input.visible = false
	dialogue_label.visible = true

	# Hide edit buttons
	if edit_button_container:
		edit_button_container.visible = false

	# Restore previous state
	if input_area:
		input_area.visible = _prev_input_area_visible
	input_field.visible = _prev_input_field_visible
	continue_button.visible = _prev_continue_visible
	if enter_edit_button:
		enter_edit_button.visible = _prev_edit_btn_visible
	if impersonate_button:
		impersonate_button.visible = _prev_impersonate_visible
		
	if input_field.visible:
		input_field.grab_focus()
		user_turn_started.emit()

	# Scroll to bottom after layout updates
	_deferred_scroll_to_bottom()

	print("Edit mode disabled")

func _deferred_scroll_to_bottom() -> void:
	for i in range(3):
		await get_tree().process_frame
	scroll_to_bottom()

## Handle save button in edit mode
func _on_save_edit_pressed() -> void:
	if not edit_mode or not edit_input:
		return

	var edited_text = edit_input.text
	print("Saving edited text: ", edited_text.substr(0, 100), "...")

	# Emit signal with edited text
	edit_saved.emit(edited_text)

	# Exit edit mode will be handled by the display manager

## Handle cancel button in edit mode
func _on_cancel_edit_pressed() -> void:
	print("Edit cancelled")

	# Emit cancel signal
	edit_cancelled.emit()

	# Exit edit mode
	exit_edit_mode()
	scroll_to_bottom()

## Handle "Edit History" button press
func _on_enter_edit_button_pressed() -> void:
	print("Edit History button pressed")
	edit_requested.emit()

func _on_impersonate_button_pressed() -> void:
	print("Impersonate button pressed")
	if impersonate_button:
		impersonate_button.disabled = true
	impersonate_requested.emit()

func _apply_user_input_min_height() -> void:
	if input_field == null:
		return

	var min_size: Vector2 = input_field.custom_minimum_size
	min_size.y = user_input_min_height
	input_field.custom_minimum_size = min_size

func set_edit_button_visible(visible: bool) -> void:
	if enter_edit_button:
		enter_edit_button.visible = visible

func set_impersonate_button_enabled(enabled: bool) -> void:
	if impersonate_button:
		impersonate_button.disabled = not enabled

func set_waiting_for_response(waiting: bool, message: String = "Thinking") -> void:
	waiting_indicator_active = waiting
	waiting_timer = 0.0
	waiting_dot_count = 0
	if waiting:
		waiting_base_text = message
	else:
		waiting_base_text = "Thinking"
	if status_label:
		if waiting:
			status_label.text = waiting_base_text
		else:
			status_label.text = ""
		status_label.visible = waiting
	
	# Hide input elements while waiting for response
	if waiting:
		if input_area:
			input_area.visible = false
		input_field.visible = false
		continue_button.visible = false
		continue_button.disabled = true
		if impersonate_button:
			impersonate_button.visible = false
		if enter_edit_button:
			enter_edit_button.visible = false
	else:
		continue_button.disabled = is_typing

func get_input_text() -> String:
	if input_field:
		return input_field.text
	return ""

func set_input_text(text: String) -> void:
	if not input_field:
		return

	if input_area:
		input_area.visible = true
	input_field.visible = true
	input_field.text = text

	var last_line = max(0, input_field.get_line_count() - 1)
	input_field.set_caret_line(last_line)
	var line_text = input_field.get_line(last_line)
	input_field.set_caret_column(line_text.length())
	input_field.grab_focus()

func get_transcript_text() -> String:
	var lines: Array[String] = []
	for entry in dialogue_history:
		lines.append(_strip_bbcode(entry))
	return "\n".join(lines)

var pending_choices: Array = []
var active_choice_link_index: int = -1

## Show a list of choices inline
func show_choices(options: Array) -> void:
	# Hide input
	hide_input()
	continue_button.visible = false
	
	# Clear container-based choices if any (legacy cleanup)
	for child in choices_container.get_children():
		child.queue_free()
	choices_container.visible = false

	# CRITICAL: Disable clickable area so the RichTextLabel link can receive mouse events
	if clickable_area:
		clickable_area_previous_mouse_filter = clickable_area.mouse_filter
		clickable_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	pending_choices = options
	if options.is_empty():
		return

	# Default to first option
	var default_label = options[0].get("label", "Choice")
	
	# Determine if we need a space prefix
	
	# Wait for any active display/typing to finish so we can correctly detect spacing
	while is_typing or is_displaying:
		await get_tree().process_frame

	var current_plain = _strip_bbcode(displayed_bbcode)
	var prefix = ""
	if not current_plain.is_empty() and not current_plain.ends_with(" ") and not current_plain.ends_with("\n"):
		prefix = " "
	
	# Construct clickable link with "Choice" style
	# We use a custom blue color and underline to indicate interactivity
	var link_color = "44AAFF" # Soft Blue
	var link_text = prefix + "[url=choice_select][color=#%s]%s[/color][/url]" % [link_color, default_label]
	
	# Append this link to the dialogue history seamlessly
	# Treat it as part of the current speaker's text (likely narrator)
	# Pass allow_bbcode=true so the URL tag works
	await display_line(last_speaker_name, link_text, Color.WHITE, true, true)
	
	# Verify history index for later update
	# Since display_line is async and modifies history immediately:
	active_choice_link_index = dialogue_history.size() - 1

func _on_dialogue_meta_clicked(meta) -> void:
	if str(meta) == "choice_select":
		_show_choice_popup()

func _show_choice_popup() -> void:
	if pending_choices.is_empty():
		return
		
	var popup = PopupMenu.new()
	popup.name = "ChoicePopup"
	add_child(popup)
	
	for i in range(pending_choices.size()):
		var label = pending_choices[i].get("label", "Option")
		popup.add_item(label, i)
	
	popup.id_pressed.connect(func(id): _on_popup_choice_selected(id, popup))
	popup.popup_hide.connect(func(): popup.queue_free())
	
	# Position at mouse
	popup.position = Vector2(get_viewport().get_mouse_position())
	popup.popup()

func _on_popup_choice_selected(id: int, popup: PopupMenu) -> void:
	if id < 0 or id >= pending_choices.size():
		return
	
	var selected_label = pending_choices[id].get("label", "Choice")
	print("Popup option selected: index=", id, " label=", selected_label)
	
	# Clear pending choices immediately so the logic link is broken
	# This prevents clicking an "unreplaced" link from showing stale or wrong options
	pending_choices = []

	# Define the regex that finds our specific choice link format
	# Pattern: [url=choice_select]...content...[/url]
	var regex = RegEx.new()
	regex.compile("\\[url=choice_select\\](.*?)\\[/url\\]")
	
	# Define the replacement text (Static blue text, no URL)
	var repl = "[color=#44AAFF]%s[/color]" % [selected_label]
	
	# 1. Update the currently displayed text GLOBALLY
	# This catches the link regardless of where it is or if tracking failed
	var new_display = regex.sub(displayed_bbcode, repl, true)
	_set_display_text(new_display)
	
	# Force stop typing and update internal state to match the new text
	# This prevents the new text from being overwritten by old typing state
	# and ensures subsequent display_line calls don't hang waiting for is_typing
	is_typing = false
	current_text = new_display
	current_text_plain = _strip_bbcode(new_display)

	# 2. Update the dialogue history GLOBALLY
	# Iterate all lines to ensure history is consistent with display
	for i in range(dialogue_history.size()):
		dialogue_history[i] = regex.sub(dialogue_history[i], repl, true)
		
	# Restore clickable area interaction
	if clickable_area:
		clickable_area.mouse_filter = clickable_area_previous_mouse_filter
		
	# Force reset display state to ensure next line can play
	if is_displaying:
		print("WARNING: is_displaying was true in choice selection, forcing false")
		is_displaying = false

	# Emit signal
	print("Popup option selected: index=", id, " label=", selected_label)
	choice_selected.emit(id)
	
	active_choice_link_index = -1

func _on_choice_button_pressed(index: int) -> void:
	# Keep legacy method if needed, or redirect
	pass
