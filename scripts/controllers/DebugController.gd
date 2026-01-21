extends Node
class_name DebugController

## Handles debug menu, context debug label, and character manipulation
## Extracted from Main.gd to consolidate debug-related logic

# Signals
signal character_added(tag: String)

# Dependencies (set by parent)
var character_manager = null
var sprite_manager = null

# UI state
var current_debug_menu = null

# References to external state (set by parent - arrays are passed by reference)
var schedule_sprite_tags: Array = []
var last_schedule_assignments: Array = []

func _ready() -> void:
	pass

# =============================================================================
# INPUT HANDLING
# =============================================================================

## Handle F1 key to toggle debug menu
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			toggle_debug_menu()
			return true
	return false

# =============================================================================
# DEBUG MENU
# =============================================================================

## Toggle the debug menu visibility
func toggle_debug_menu() -> void:
	if current_debug_menu != null:
		current_debug_menu.queue_free()
		current_debug_menu = null
		return

	var debug_menu_scene = load("res://scenes/ui/DebugMenuUI.tscn")
	current_debug_menu = debug_menu_scene.instantiate()
	current_debug_menu.closed.connect(_on_debug_menu_closed)
	current_debug_menu.add_character_requested.connect(_on_add_character)
	current_debug_menu.add_random_character_requested.connect(_on_add_random_character)
	
	# Pass available characters to the menu
	current_debug_menu.set_available_characters(_get_available_characters_for_location())
	get_parent().add_child(current_debug_menu)

func _on_debug_menu_closed() -> void:
	current_debug_menu = null

## Check if debug menu is open
func is_debug_menu_open() -> bool:
	return current_debug_menu != null

# =============================================================================
# CHARACTER MANIPULATION
# =============================================================================

## Get a list of characters not currently at this location
func _get_available_characters_for_location() -> Array:
	if character_manager == null:
		return []
	
	var result: Array = []
	var all_characters: Array = character_manager.get_all_characters(true)  # sorted
	
	for char_config in all_characters:
		var tag: String = str(char_config.tag)
		if tag == "p":  # Exclude player
			continue
		if tag in schedule_sprite_tags:  # Already at location
			continue
		result.append({"tag": tag, "name": char_config.name})
	
	return result

## Add a specific character (called from debug menu)
func _on_add_character(tag: String) -> void:
	_add_solo_character_to_location(tag)

## Add a random character (called from debug menu)
func _on_add_random_character() -> void:
	var available := _get_available_characters_for_location()
	if available.is_empty():
		print("DEBUG: No available characters to add")
		return
	
	# Pick a random character
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var random_index: int = rng.randi_range(0, available.size() - 1)
	var new_tag: String = str(available[random_index].get("tag", ""))
	
	_add_solo_character_to_location(new_tag)

## Add a solo character to the current location
func _add_solo_character_to_location(tag: String) -> void:
	if character_manager == null or sprite_manager == null:
		return
	
	var char_config = character_manager.get_character(tag)
	if char_config == null:
		return
	
	print("DEBUG: Adding solo character: %s (%s)" % [char_config.name, tag])
	
	# Create a solo assignment entry
	var new_assignment: Dictionary = {
		"tag": tag,
		"name": char_config.name,
		"group_id": "",
		"group_members": []
	}
	last_schedule_assignments.append(new_assignment)
	schedule_sprite_tags.append(tag)
	
	# Re-display all sprites with updated assignments
	sprite_manager.display_grouped_assignments(last_schedule_assignments, character_manager)
	
	# Emit signal so parent can update schedule label
	character_added.emit(tag)
