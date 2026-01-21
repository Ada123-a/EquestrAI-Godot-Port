extends Node
class_name SpeakController

## Handles speak-to-character panel management and group conversations
## Extracted from Main.gd to consolidate conversation initiation logic

# Signals
signal speak_conversation_started(tags: Array, names: Array)
signal scene_mode_requested(active: bool)

# Dependencies (set by parent)
var character_manager = null
var sprite_manager = null
var dialogue_panel = null

# State
var speak_to_character_panel = null
var pending_speak_tags: Array = []

# References to external state (set by parent)
var last_schedule_assignments: Array = []
var schedule_sprite_tags: Array = []

func _ready() -> void:
	pass

# =============================================================================
# SPRITE CLICK HANDLING
# =============================================================================

## Handle sprite click - show speak panel or initiate conversation
func on_sprite_clicked(tag: String, is_scene_active: bool, travel_request_active: bool) -> void:
	# Only allow clicking sprites in free roam mode
	if is_scene_active or travel_request_active:
		return

	# Get character info
	if character_manager == null:
		return
	var char_config = character_manager.get_character(tag)
	if char_config == null:
		return

	# Get sprite position and size
	if sprite_manager == null or not sprite_manager.active_sprites.has(tag):
		return
	var sprite_node: TextureRect = sprite_manager.active_sprites[tag]
	var sprite_pos: Vector2 = sprite_node.position
	var sprite_size: Vector2 = sprite_node.size

	# Check if this character is in a conversation group
	var group_tags: Array = [tag]
	var group_names: Array = [char_config.name]
	
	for assignment in last_schedule_assignments:
		if str(assignment.get("tag", "")) == tag:
			var group_members: Array = assignment.get("group_members", [])
			if group_members.size() > 1:
				group_tags.clear()
				group_names.clear()
				for member in group_members:
					var member_tag: String = str(member.get("tag", ""))
					var member_name: String = str(member.get("name", member_tag))
					group_tags.append(member_tag)
					group_names.append(member_name)
			break
	
	# Calculate center position for groups
	var panel_pos: Vector2 = sprite_pos
	var panel_size: Vector2 = sprite_size
	
	if group_tags.size() > 1:
		# Find bounds of all group member sprites
		var min_x: float = sprite_pos.x
		var max_x: float = sprite_pos.x + sprite_size.x
		var min_y: float = sprite_pos.y
		
		for group_tag in group_tags:
			var gtag: String = str(group_tag)
			if sprite_manager.active_sprites.has(gtag):
				var member_sprite: TextureRect = sprite_manager.active_sprites[gtag]
				var member_pos: Vector2 = member_sprite.position
				var member_size: Vector2 = member_sprite.size
				min_x = minf(min_x, member_pos.x)
				max_x = maxf(max_x, member_pos.x + member_size.x)
				min_y = minf(min_y, member_pos.y)
		
		# Use the center of the group bounds
		panel_pos = Vector2(min_x, min_y)
		panel_size = Vector2(max_x - min_x, sprite_size.y)

	# Create or show the speak panel
	show_speak_panel(group_tags, group_names, panel_pos, panel_size)

# =============================================================================
# SPEAK PANEL MANAGEMENT
# =============================================================================

## Show the speak-to-character panel
func show_speak_panel(tags: Array, names: Array, sprite_pos: Vector2, sprite_size: Vector2) -> void:
	# Hide existing panel if showing for different character
	dismiss_panel()

	var panel_scene = load("res://scenes/ui/components/SpeakToCharacterPanel.tscn")
	speak_to_character_panel = panel_scene.instantiate()
	speak_to_character_panel.speak_requested.connect(_on_speak_requested)
	speak_to_character_panel.add_character_requested.connect(_on_add_specific_character)
	speak_to_character_panel.add_random_character_requested.connect(_on_add_random_character)
	speak_to_character_panel.dismissed.connect(_on_panel_dismissed)
	get_parent().add_child(speak_to_character_panel)
	
	# Pass available characters
	speak_to_character_panel.set_available_characters(_get_available_characters_for_group(tags))
	speak_to_character_panel.show_for_group(tags, names, sprite_pos, sprite_size)

## Dismiss the speak panel
func dismiss_panel() -> void:
	if speak_to_character_panel != null:
		speak_to_character_panel.queue_free()
		speak_to_character_panel = null

func _on_panel_dismissed() -> void:
	dismiss_panel()

## Handle speak request from panel
func _on_speak_requested(tags: Array) -> void:
	dismiss_panel()

	if character_manager == null or tags.is_empty():
		return
	
	# Get names for the input placeholder
	var names: Array[String] = []
	
	# Add all characters to active characters for the conversation
	for tag in tags:
		var tag_str: String = str(tag)
		var char_config = character_manager.get_character(tag_str)
		if char_config != null:
			character_manager.add_active_character(tag_str)
			names.append(char_config.name)
			# Bring their sprite to front
			if sprite_manager:
				sprite_manager.bring_to_front(tag_str)

	# Request scene mode
	scene_mode_requested.emit(true)
	
	# Emit signal for parent to handle dialogue setup
	speak_conversation_started.emit(tags, names)

# =============================================================================
# CHARACTER ADDITION
# =============================================================================

## Get a list of characters not in a specific group (for the speak panel)
func _get_available_characters_for_group(current_tags: Array) -> Array:
	if character_manager == null:
		return []
	
	# Combine current group tags with all location tags
	var present_tags: Array[String] = []
	for tag in current_tags:
		present_tags.append(str(tag))
	for tag in schedule_sprite_tags:
		if str(tag) not in present_tags:
			present_tags.append(str(tag))
	
	var result: Array = []
	var all_characters: Array = character_manager.get_all_characters(true)  # sorted
	
	for char_config in all_characters:
		var tag: String = str(char_config.tag)
		if tag == "p":  # Exclude player
			continue
		if tag in present_tags:  # Already present
			continue
		result.append({"tag": tag, "name": char_config.name})
	
	return result

## Add a specific character to the current group
func _on_add_specific_character(current_tags: Array, new_tag: String) -> void:
	_add_character_to_group(current_tags, new_tag)

## Add a random character to the current group
func _on_add_random_character(current_tags: Array) -> void:
	var available := _get_available_characters_for_group(current_tags)
	if available.is_empty():
		print("DEBUG: No available characters to add")
		return
	
	# Pick a random character
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var random_index: int = rng.randi_range(0, available.size() - 1)
	var new_tag: String = str(available[random_index].get("tag", ""))
	
	_add_character_to_group(current_tags, new_tag)

## Add a character to a group and refresh the panel
func _add_character_to_group(current_tags: Array, new_tag: String) -> void:
	if character_manager == null or sprite_manager == null:
		return
	
	var char_config = character_manager.get_character(new_tag)
	if char_config == null:
		return
	
	print("DEBUG: Adding character to group: %s (%s)" % [char_config.name, new_tag])
	
	# Add sprite for the new character
	sprite_manager.show_sprite(new_tag, "neutral", character_manager)
	schedule_sprite_tags.append(new_tag)
	
	# Create a fake assignment entry for the schedule
	var new_assignment: Dictionary = {
		"tag": new_tag,
		"name": char_config.name,
		"group_id": "",
		"group_members": []
	}
	last_schedule_assignments.append(new_assignment)
	
	# Build updated group tags and names
	var updated_tags: Array = current_tags.duplicate()
	var updated_names: Array = []
	
	for tag in updated_tags:
		var tag_str: String = str(tag)
		var cfg = character_manager.get_character(tag_str)
		if cfg:
			updated_names.append(cfg.name)
		else:
			updated_names.append(tag_str)
	
	# Add the new character
	updated_tags.append(new_tag)
	updated_names.append(char_config.name)
	
	# Update the assignment's group_members to include the new character
	for assignment in last_schedule_assignments:
		var a_tag: String = str(assignment.get("tag", ""))
		if a_tag in current_tags or a_tag == new_tag:
			var group_members: Array = []
			for t in updated_tags:
				var t_str: String = str(t)
				var cfg = character_manager.get_character(t_str)
				group_members.append({
					"tag": t_str,
					"name": cfg.name if cfg else t_str
				})
			assignment["group_id"] = "debug_group"
			assignment["group_members"] = group_members
	
	# Re-display sprites with updated grouping
	sprite_manager.display_grouped_assignments(last_schedule_assignments, character_manager)
	
	# Recalculate panel position for the expanded group
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var first_size: Vector2 = Vector2.ZERO
	
	for tag in updated_tags:
		var tag_str: String = str(tag)
		if sprite_manager.active_sprites.has(tag_str):
			var sprite_node: TextureRect = sprite_manager.active_sprites[tag_str]
			var pos: Vector2 = sprite_node.position
			var sz: Vector2 = sprite_node.size
			min_x = minf(min_x, pos.x)
			max_x = maxf(max_x, pos.x + sz.x)
			min_y = minf(min_y, pos.y)
			if first_size == Vector2.ZERO:
				first_size = sz
	
	var panel_pos: Vector2 = Vector2(min_x, min_y)
	var panel_size: Vector2 = Vector2(max_x - min_x, first_size.y)
	
	# Refresh the panel
	show_speak_panel(updated_tags, updated_names, panel_pos, panel_size)
