extends Control

signal closed
signal add_character_requested(tag: String)
signal add_random_character_requested

@onready var navigation_narration_check: CheckBox = %NavigationNarrationCheck
@onready var debug_commands_check: CheckBox = %DebugCommandsCheck
@onready var add_character_button: Button = %AddCharacterButton
@onready var close_button: Button = %CloseButton

## Available characters for selection (set by Main.gd)
var available_characters: Array = []

## Reference to the character selector popup
var character_selector: Control = null

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	navigation_narration_check.toggled.connect(_on_navigation_narration_toggled)
	debug_commands_check.toggled.connect(_on_debug_commands_toggled)
	add_character_button.pressed.connect(_on_add_character_pressed)

	# Initialize checkboxes from current settings
	var debug_settings = DebugSettings.get_instance()
	if debug_settings:
		navigation_narration_check.button_pressed = debug_settings.navigation_narration_enabled
		debug_commands_check.button_pressed = debug_settings.debug_commands_enabled

## Set available characters that can be added (should exclude already present characters)
func set_available_characters(characters: Array) -> void:
	available_characters = characters.duplicate(true)

func _on_navigation_narration_toggled(enabled: bool) -> void:
	var debug_settings = DebugSettings.get_instance()
	if debug_settings:
		debug_settings.navigation_narration_enabled = enabled

func _on_debug_commands_toggled(enabled: bool) -> void:
	var debug_settings = DebugSettings.get_instance()
	if debug_settings:
		debug_settings.debug_commands_enabled = enabled

func _on_add_character_pressed() -> void:
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
	add_child(character_selector)
	
	character_selector.set_available_characters(available_characters)
	character_selector.show_popup()

func _on_character_selected(tag: String) -> void:
	add_character_requested.emit(tag)
	_cleanup_selector()

func _on_random_character_selected() -> void:
	add_random_character_requested.emit()
	_cleanup_selector()

func _on_selector_cancelled() -> void:
	_cleanup_selector()

func _cleanup_selector() -> void:
	if character_selector != null:
		character_selector.queue_free()
		character_selector = null

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	# Don't process input if character selector is open
	if character_selector != null and character_selector.visible:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
