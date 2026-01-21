extends Node
class_name TravelManager

## Handles location transitions, travel narration, and route logic
## Extracted from Main.gd to consolidate travel-related logic

# Signals
signal travel_started(previous_location_id: String, destination_id: String)
signal travel_completed()
signal location_changed(location_id: String, preserve_characters: bool)
signal enter_free_roam_requested()

# Dependencies (set by parent)
var location_manager = null
var location_graph_manager = null
var character_manager = null
var sprite_manager = null
var stats_manager = null
var music_manager = null
var memory_controller = null  # For recording location memory

# UI references (set by parent)
var background_rect: TextureRect = null

# State
var travel_request_active: bool = false
var was_map_travel: bool = false

# Reference to global vars (set by parent)
var global_vars: Dictionary = {}

func _ready() -> void:
	pass

# =============================================================================
# LOCATION CHANGE METHODS
# =============================================================================

## Change location, clearing all active characters
func change_location(loc_id: String) -> bool:
	if location_manager == null:
		return false
	
	var previous_location_id: String = location_manager.current_location_id
	if location_manager.set_location(loc_id):
		if character_manager:
			character_manager.clear_active_characters()
		if sprite_manager:
			sprite_manager.clear_all_sprites()
		
		var loc = location_manager.get_location(loc_id)
		global_vars["current_location_id"] = loc_id
		if stats_manager:
			stats_manager.update_stat("location", loc.name)

		# Load background image
		_load_background(loc.background_path)
		
		# Play location music
		if music_manager:
			if loc.music_path != "":
				music_manager.play_music(loc.music_path)
			else:
				music_manager.stop_music()

		# Record to memory
		if memory_controller:
			memory_controller.record_location_memory(previous_location_id, loc_id)
		
		location_changed.emit(loc_id, false)
		return true

	return false

## Change location while preserving active characters (used during events)
func change_location_preserve_characters(loc_id: String) -> bool:
	if location_manager == null:
		return false
	
	var previous_location_id: String = location_manager.current_location_id
	if location_manager.set_location(loc_id):
		# Don't clear active characters - they follow us
		# Don't clear sprites - just update the background
		
		var loc = location_manager.get_location(loc_id)
		global_vars["current_location_id"] = loc_id
		if stats_manager:
			stats_manager.update_stat("location", loc.name)

		# Load background image
		_load_background(loc.background_path)
		
		# Play location music
		if music_manager:
			if loc.music_path != "":
				music_manager.play_music(loc.music_path)
			else:
				music_manager.stop_music()

		# Record to memory
		if memory_controller:
			memory_controller.record_location_memory(previous_location_id, loc_id)
		
		location_changed.emit(loc_id, true)
		return true

	return false

## Change location preserving ONLY grouped characters
func change_location_preserve_grouped(loc_id: String, grouped_chars: Array, group_map: Dictionary) -> bool:
	# First, clear characters that are NOT in the group
	if character_manager:
		var all_active = character_manager.active_characters.duplicate()
		for tag in all_active:
			if tag not in grouped_chars:
				character_manager.remove_active_character(tag)
				if sprite_manager:
					sprite_manager.hide_sprite(tag, true)
					# Also remove from group_map to prevent ghosts
					sprite_manager.current_group_map.erase(tag)
	
	# Perform the move using the preserve logic
	var success = change_location_preserve_characters(loc_id)
	
	# Restore group map ONLY for grouped characters (not the whole map)
	if success and sprite_manager:
		# Clear map and only restore entries for grouped chars
		var filtered_group_map: Dictionary = {}
		for char_tag in grouped_chars:
			if group_map.has(char_tag):
				filtered_group_map[char_tag] = group_map[char_tag]
		sprite_manager.current_group_map = filtered_group_map
		sprite_manager.update_layout()
		
	return success

## Change location automatically preserving any currently grouped characters
## Queries SpriteManager for group state
func change_location_with_groups(loc_id: String) -> bool:
	if sprite_manager == null:
		print("DEBUG change_location_with_groups: no sprite_manager, using regular change_location")
		return change_location(loc_id)
		
	var group_state = sprite_manager.get_current_group_state()
	var grouped_chars = group_state.get("grouped_chars", [])
	var group_map = group_state.get("group_map", {})
	
	print("DEBUG change_location_with_groups: grouped_chars=%s, group_map=%s" % [grouped_chars, group_map])
	print("DEBUG change_location_with_groups: current_group_map=%s" % sprite_manager.current_group_map)
	
	if grouped_chars.is_empty():
		print("DEBUG change_location_with_groups: no grouped chars, using regular change_location")
		return change_location(loc_id)
		
	print("DEBUG change_location_with_groups: preserving %d grouped chars" % grouped_chars.size())
	return change_location_preserve_grouped(loc_id, grouped_chars, group_map)

# =============================================================================
# TRAVEL NARRATION
# =============================================================================

## Request travel narration for a navigation target
func on_navigation_target_selected(location_id: String) -> void:
	if location_id == "" or travel_request_active:
		return

	if location_manager == null:
		return

	var previous_location_id: String = location_manager.current_location_id
	if previous_location_id == location_id:
		return

	var changed: bool = change_location(location_id)
	if not changed:
		return

	# Check if navigation narration is enabled
	var debug_settings = DebugSettings.get_instance()
	if debug_settings and not debug_settings.navigation_narration_enabled:
		# Skip narration, just enter free roam
		enter_free_roam_requested.emit()
		return

	_request_travel_narration(previous_location_id, location_id)

func _request_travel_narration(previous_location_id: String, destination_id: String) -> void:
	travel_request_active = true
	travel_started.emit(previous_location_id, destination_id)

signal travel_narration_generated(text: String)

## Handle travel narration response (called by parent after LLM responds)
func on_travel_response_received(text: String) -> void:
	travel_request_active = false
	travel_narration_generated.emit(text)
	travel_completed.emit()

## Mark that the last navigation came from the map
func set_map_travel(value: bool) -> void:
	was_map_travel = value

## Check if last travel was from map
func was_last_travel_from_map() -> bool:
	return was_map_travel

## Clear the map travel flag
func clear_map_travel_flag() -> void:
	was_map_travel = false

# =============================================================================
# HELPERS
# =============================================================================

func _load_background(background_path: String) -> void:
	if background_rect == null:
		return
	
	if FileAccess.file_exists(background_path):
		var texture = ResourceLoader.load(background_path, "Texture2D")
		if texture:
			background_rect.texture = texture
		else:
			# Fallback to Image.load_from_file for runtime-only scenarios
			var img = Image.load_from_file(background_path)
			if img:
				background_rect.texture = ImageTexture.create_from_image(img)
	else:
		print("Background not found: ", background_path)
		background_rect.texture = null

## Check if travel is currently active
func is_travel_active() -> bool:
	return travel_request_active

## Get the current location ID  
func get_current_location_id() -> String:
	if location_manager == null:
		return ""
	return location_manager.current_location_id

## Get location info by ID
func get_location(location_id: String):
	if location_manager == null:
		return null
	return location_manager.get_location(location_id)

## Get neighbors with names for the current location
func get_current_neighbors_with_names() -> Array:
	if location_graph_manager == null or location_manager == null:
		return []
	return location_graph_manager.get_neighbors_with_names(
		location_manager.current_location_id,
		location_manager
	)
