extends PanelContainer

signal speak_requested(tags: Array)
signal add_character_requested(current_tags: Array, new_tag: String)
signal add_random_character_requested(current_tags: Array)
signal dismissed

@onready var speak_button: TextureButton = %SpeakButton
@onready var button_container: VBoxContainer = $MarginContainer/VBoxContainer

var target_tags: Array[String] = []
var target_position: Vector2 = Vector2.ZERO
var debug_add_button: Button = null
var character_selector: Control = null

## Available characters for selection (set externally)
var available_characters: Array = []

func _ready() -> void:
	speak_button.pressed.connect(_on_speak_pressed)
	visible = false

## Set available characters that can be added
func set_available_characters(characters: Array) -> void:
	available_characters = characters.duplicate(true)

## Show panel for a single character (legacy compatibility)
func show_for_character(tag: String, character_name: String, sprite_position: Vector2, sprite_size: Vector2) -> void:
	show_for_group([tag], [character_name], sprite_position, sprite_size)

## Show panel for a group of characters in conversation
func show_for_group(tags: Array, names: Array, sprite_position: Vector2, sprite_size: Vector2) -> void:
	target_tags.clear()
	for t in tags:
		target_tags.append(str(t))
	
	# Build button text based on group size
	if names.size() == 1:
		speak_button.tooltip_text = "Speak to %s" % names[0]
	elif names.size() == 2:
		speak_button.tooltip_text = "Join %s and %s" % [names[0], names[1]]
	else:
		# 3+ characters: "Join X, Y, and Z"
		var last_name: String = str(names[names.size() - 1])
		var other_names: Array[String] = []
		for i in range(names.size() - 1):
			other_names.append(str(names[i]))
		speak_button.tooltip_text = "Join %s, and %s" % [", ".join(other_names), last_name]
	
	# Check if debug commands are enabled
	_update_debug_button()
	
	# Position above the sprite, centered
	var panel_size = get_combined_minimum_size()
	var viewport_size = get_viewport_rect().size
	
	# Center horizontally on sprite, position above
	var x_pos = sprite_position.x + sprite_size.x / 2.0 - panel_size.x / 2.0
	var y_pos = sprite_position.y - panel_size.y - 10.0
	
	# Clamp to viewport
	x_pos = clampf(x_pos, 10.0, viewport_size.x - panel_size.x - 10.0)
	y_pos = clampf(y_pos, 10.0, viewport_size.y - panel_size.y - 10.0)
	
	position = Vector2(x_pos, y_pos)
	target_position = position
	visible = true
	
	# Grab focus for keyboard dismissal
	speak_button.grab_focus()

func _update_debug_button() -> void:
	# Remove existing debug button if any
	if debug_add_button != null:
		debug_add_button.queue_free()
		debug_add_button = null
	
	# Check if debug commands are enabled
	var debug_settings = DebugSettings.get_instance()
	if debug_settings == null or not debug_settings.debug_commands_enabled:
		return
	
	# Create debug button
	debug_add_button = Button.new()
	debug_add_button.text = "[Debug] Add Character..."
	debug_add_button.pressed.connect(_on_debug_add_pressed)
	button_container.add_child(debug_add_button)

func _on_debug_add_pressed() -> void:
	_show_character_selector()

func _show_character_selector() -> void:
	# Remove existing selector if present
	if character_selector != null:
		character_selector.queue_free()
		character_selector = null
	
	var selector_scene = load("res://scenes/ui/components/CharacterSelectorPopup.tscn")
	character_selector = selector_scene.instantiate()
	character_selector.character_selected.connect(_on_character_selected)
	character_selector.random_character_requested.connect(_on_random_character_selected)
	character_selector.cancelled.connect(_on_selector_cancelled)
	
	# Add to root so it's centered properly
	var root = get_tree().root
	root.add_child(character_selector)
	
	character_selector.set_available_characters(available_characters)
	character_selector.show_popup()

func _on_character_selected(tag: String) -> void:
	add_character_requested.emit(target_tags.duplicate(), tag)
	_cleanup_selector()

func _on_random_character_selected() -> void:
	add_random_character_requested.emit(target_tags.duplicate())
	_cleanup_selector()

func _on_selector_cancelled() -> void:
	_cleanup_selector()

func _cleanup_selector() -> void:
	if character_selector != null:
		character_selector.queue_free()
		character_selector = null

func hide_panel() -> void:
	visible = false
	target_tags.clear()
	if debug_add_button != null:
		debug_add_button.queue_free()
		debug_add_button = null
	_cleanup_selector()

func _on_speak_pressed() -> void:
	speak_requested.emit(target_tags.duplicate())
	hide_panel()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	# Don't process input if character selector is open
	if character_selector != null and character_selector.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			hide_panel()
			dismissed.emit()
			get_viewport().set_input_as_handled()

	# Dismiss if clicking elsewhere
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = get_local_mouse_position()
			var rect = Rect2(Vector2.ZERO, size)
			if not rect.has_point(local_pos):
				hide_panel()
				dismissed.emit()
