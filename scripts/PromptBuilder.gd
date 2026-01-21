extends RefCounted

class_name PromptBuilder

# =============================================================================
# CONSOLIDATED PROMPT BUILDER
# Handles all prompt types: Scene/LLM Response, Planning, Impersonation
# =============================================================================

const SPRITE_LIMIT: int = 20

# =============================================================================
# MAIN PROMPT BUILDERS
# =============================================================================

## Build a comprehensive world context string from managers
static func build_world_context(
	location_manager = null,
	stats_manager = null, 
	location_graph_manager = null,
	character_manager = null,
	memory_manager = null,
	settings_manager = null,
	include_mechanics: bool = true
) -> Dictionary:
	var prompt_parts: Array = []
	var active_chars: Array = []

	# Base instruction
	# Base instruction removed from context building to avoid duplication 
	# (specific prompt builders like build_scene_prompt add their own headers).

	# Current location context
	# Note: StatsManager usually includes "Current Location: Name", so we only add description here.
	if location_manager:
		var current_location = location_manager.get_location(location_manager.current_location_id)
		if current_location:
			# Name is covered by stats_manager below
			if current_location.description != "":
				prompt_parts.append("Location Description: %s" % current_location.description)

	# Game stats (location, day, time)
	if stats_manager:
		var stats_str = stats_manager.get_stats_string()
		prompt_parts.append(stats_str)

	# Add neighboring locations context
	if location_graph_manager and location_manager:
		var neighbors = location_graph_manager.get_neighbors_with_names(location_manager.current_location_id, location_manager)
		if neighbors.size() > 0:
			prompt_parts.append("\nAvailable Nearby Locations:")
			for neighbor in neighbors:
				prompt_parts.append("- %s (use [location: %s])" % [neighbor["name"], neighbor["id"]])
			
			if include_mechanics:
				prompt_parts.append("\nIMPORTANT: You can change locations during dialogue by placing [location: location_id] AFTER the narration or dialogue that describes moving there.")
				prompt_parts.append("Example flow:")
				prompt_parts.append("Twilight gestures toward the door.")
				prompt_parts.append('twi "Let\'s head to my bedroom, I have something to show you."')
				prompt_parts.append("You follow Twilight up the stairs and into her personal quarters.")
				prompt_parts.append("[location: twilight_bedroom]")
				prompt_parts.append("Books and scrolls are scattered across every surface.")

	# Active characters are collected but not appended to context string here
	# They should be passed to specific prompt builders (scene, impersonate) to be formatted correctly
	if character_manager:
		for tag in character_manager.active_characters:
			var char = character_manager.get_character(tag)
			if char:
				active_chars.append(char)

	# Persona Context
	_append_persona_context(prompt_parts, settings_manager)
	
	# Memory Context
	if memory_manager:
		var memory_context: String = memory_manager.build_context_block()
		if memory_context.strip_edges() != "":
			prompt_parts.append("\nStory so far:")
			prompt_parts.append(memory_context)
			
	return {
		"context_string": "\n".join(prompt_parts),
		"characters": active_chars,
		"parts": prompt_parts
	}


## Build a scene prompt for LLM story generation
static func build_scene_prompt(characters: Array, context: String, task: String = "", settings_manager = null) -> Dictionary:
	var sections: Array = []
	
	# 1. Header
	sections.append(_get_header(settings_manager))
	
	# 2. Character Appearance (the good format)
	if not characters.is_empty():
		sections.append(_build_character_appearance_section(characters))
	
	# 3. Context (location, time, history, etc.)
	if context.strip_edges() != "":
		sections.append(context)
	
	# 4. Task instruction
	if task.strip_edges() != "":
		sections.append("Task: " + task)
	
	# 5. Format rules
	sections.append(_build_format_rules_section(characters))
	
	return {
		"system_prompt": "\n\n".join(sections),
		"post_story_instructions": ""
	}

## Build a planning prompt for Custom Start beat planning
static func build_planning_prompt(
	characters: Array, 
	locations: Array, 
	start_location_id: String,
	start_location_display: String,
	scene_request: String,
	persona_lines: Array = []
) -> String:
	var lines: Array = []
	
	# Header
	lines.append("You are planning an opening scene for a MLP FIM visual novel with parsable formatting.")
	lines.append("")
	
	# Available Characters
	lines.append("AVAILABLE CHARACTERS:")
	for char_config in characters:
		lines.append(_format_planning_character(char_config))
	lines.append("")
	
	# Available Locations
	lines.append("AVAILABLE LOCATIONS:")
	for loc in locations:
		lines.append("- %s (%s)" % [loc.display, loc.id])
	lines.append("")
	
	# Start Location
	lines.append("START LOCATION:")
	lines.append("- Anchor the scene with [location: %s] (%s) within the opening beats." % [start_location_id, start_location_display])
	lines.append("")
	
	# Player Persona
	if persona_lines.size() > 0:
		lines.append("PLAYER PERSONA DETAILS:")
		for entry in persona_lines:
			lines.append(entry)
		lines.append("")
	
	# Scene Request
	lines.append("PLAYER'S SCENE REQUEST:")
	lines.append(scene_request.strip_edges())
	lines.append("")
	
	# Plan Guidelines
	lines.append("PLAN GUIDELINES:")
	lines.append("- Return ONLY a short numbered plan (no dialogue).")
	lines.append("- List each beat with: location_id, what happens, which characters are visible, sprite/emotion suggestions.")
	lines.append("- Keep 6–12 beats. Keep the player silent (tag 'player' never speaks).")
	lines.append("- Use [sprite: TAG emotion] to show characters. Use [exit: TAG] when a character leaves.")
	lines.append("- You can use [group: tag1 tag2] to make characters follow the player between locations.")
	lines.append("")
	
	# Example
	lines.append("Example plan snippet:")
	lines.append("1) [location: inside_train] Narration of rain; Twilight waiting; [sprite: twi smile]; player approaches.")
	lines.append("2) [location: train_station] Twilight greets; Spike joins with [sprite: spike neutral]; set warm tone.")
	
	return "\n".join(lines)

## Build an impersonation prompt (speak as the player for one sentence)
static func build_impersonate_prompt(context_parts: Array, characters: Array, custom_instruction: String = "") -> String:
	var parts: Array = context_parts.duplicate()
	
	if characters.size() > 0:
		parts.append("\nPresent Characters:")
		for char in characters:
			parts.append("- %s (%s)" % [char.name, char.tag])
	
	parts.append("\nFormat rules:")
	parts.append("- Write the player's dialogue using the prefix: player \"...\"")
	
	if custom_instruction.strip_edges() != "":
		parts.append("\n" + custom_instruction)
	else:
		parts.append("\nWrite for the player and only the player for this turn.")
		parts.append("Do not include narrator lines, NPC dialogue, or sprite commands for the player. The player does not have sprites, so never emit [sprite: player emotion].")
	
	return "\n".join(parts)

## Build an end scene prompt
static func build_end_scene_prompt(
	context_string: String,
	history_text: String,
	characters: Array,
	memory_manager = null
) -> String:
	var prompt_parts: Array = [context_string]
	
	prompt_parts.append(_build_format_rules_section(characters))
	
	if history_text.strip_edges() != "":
		prompt_parts.append("\nConversation So Far:")
		prompt_parts.append(history_text)

	prompt_parts.append("Bring this scene to a satisfying stopping point so the story can progress.")
	prompt_parts.append("Include any final dialogue or narration needed to wrap up current tensions, then hand control back to the player.")
	prompt_parts.append("Do not start a brand new storyline; simply conclude the current moment gracefully.")

	return _finalize_prompt(prompt_parts, "END SCENE PROMPT")

## Build a travel narration prompt
static func build_travel_prompt(
	previous_location_id: String,
	destination_id: String,
	history_text: String,
	schedule_assignments: Array,
	location_manager = null,
	stats_manager = null,
	location_graph_manager = null,
	settings_manager = null,
	memory_manager = null
) -> String:
	var prompt_parts: Array = []
	prompt_parts.append("You are writing a brief travel interlude for a My Little Pony visual novel in second person.")

	if stats_manager:
		var stats_str: String = stats_manager.get_stats_string()
		prompt_parts.append("Current time of day and context: %s" % stats_str)

	if location_manager:
		var previous_location = location_manager.get_location(previous_location_id)
		if previous_location:
			prompt_parts.append("Starting location: %s" % previous_location.name)

		var destination = location_manager.get_location(destination_id)
		if destination:
			prompt_parts.append("Destination: %s" % destination.name)
			if destination.description != "":
				prompt_parts.append("Destination description: %s" % destination.description)

	if location_graph_manager and location_manager:
		var neighbors = location_graph_manager.get_neighbors_with_names(destination_id, location_manager)
		if neighbors.size() > 0:
			prompt_parts.append("Nearby locations after arrival:")
			for neighbor in neighbors:
				prompt_parts.append("- %s" % str(neighbor.get("name", "")))

	# Include characters present at the destination
	if schedule_assignments.size() > 0:
		prompt_parts.append("Characters present at the destination:")
		for assignment in schedule_assignments:
			var char_name: String = str(assignment.get("name", ""))
			var char_note: String = str(assignment.get("note", ""))
			if char_name != "":
				if char_note != "":
					prompt_parts.append("- %s (%s)" % [char_name, char_note])
				else:
					prompt_parts.append("- %s" % char_name)

	_append_persona_context(prompt_parts, settings_manager)

	# Use memory OR history, not both (to avoid duplication)
	# Prefer history_text if available as it's the most recent conversation
	if history_text.strip_edges() != "":
		prompt_parts.append("\nRecent conversation before leaving:\n" + history_text)
	elif memory_manager:
		var memory_context: String = memory_manager.build_context_block()
		if memory_context.strip_edges() != "":
			prompt_parts.append("\nStory context so far:\n" + memory_context)

	_append_custom_instruction(prompt_parts, settings_manager, "travel_prompt", [
		"Write 2-4 lines of narration (no character tags) that describe what the player feels and notices while traveling from the starting point to the destination.",
		"Use second-person narration (you/your). Keep it narration-only (no sprite commands or [location] tags)."
	])

	# Add character instruction after custom prompt (always applied when characters present)
	if schedule_assignments.size() > 0:
		prompt_parts.append("IMPORTANT: End the narration by noting the character(s) present at the destination as part of the arrival scene.")

	return "\n\n".join(prompt_parts)  # Use double newlines for proper paragraph breaks


# =============================================================================
# SECTION BUILDERS
# =============================================================================

static func _get_header(settings_manager) -> String:
	# Try to load from settings, fall back to default
	var template_data = _load_template(settings_manager)
	return template_data.get("header", "You are writing a My Little Pony visual novel scene. Follow the rules below and focus on accurate characterization.")

static func _build_character_appearance_section(characters: Array) -> String:
	var lines: Array = []
	lines.append("CHARACTER APPEARANCE:")
	lines.append("Characters do NOT appear automatically. You MUST use [sprite: tag emotion] to make a character visible before they speak.")
	
	for char_config in characters:
		var emotions = _get_sprite_list(char_config)
		lines.append("- [sprite: %s emotion] to show %s (emotions: %s)" % [char_config.tag, char_config.name, ", ".join(emotions)])
	
	return "\n".join(lines)

static func _build_format_rules_section(characters: Array) -> String:
	var lines: Array = []
	lines.append("FORMAT RULES:")
	
	# Dialogue formatting
	lines.append("Dialogue:")
	for char_config in characters:
		lines.append("- Use %s \"...\" for %s's dialogue" % [char_config.tag, char_config.name])
	lines.append("- Narration must be plain text with no tag.")
	
	# Commands
	lines.append("")
	lines.append("Commands:")
	lines.append("- Use [sprite: tag emotion] to set a character's sprite before they speak")
	lines.append("- Use [location: location_id] to change to a new location")
	lines.append("- Use [exit: tag] when a character leaves the scene")
	lines.append("- You can use [group: tag1 tag2] to make characters follow the player between locations")
	
	# Writing guidelines
	lines.append("")
	lines.append("Writing:")
	lines.append("- Show clear physicality, senses, and emotion")
	lines.append("- Let characters react to each other; avoid monologues")
	lines.append("- Do NOT speak as the player")
	
	return "\n".join(lines)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

static func _get_sprite_list(char_config) -> Array:
	var sprite_list: Array = []
	if char_config and char_config.sprites:
		var limit: int = min(char_config.sprites.size(), SPRITE_LIMIT)
		for i in range(limit):
			sprite_list.append(str(char_config.sprites[i]))
	if sprite_list.is_empty():
		sprite_list.append("neutral")
	return sprite_list

static func _format_planning_character(char_config) -> String:
	var sprite_text: Array = []
	if char_config.sprites and char_config.sprites.size() > 0:
		var limit: int = min(char_config.sprites.size(), SPRITE_LIMIT)
		for i in range(limit):
			sprite_text.append(str(char_config.sprites[i]))
	
	var summary: String = "- %s (tag: %s)" % [char_config.name, char_config.tag]
	if not sprite_text.is_empty():
		summary += ": " + ", ".join(sprite_text)
	if char_config.description and str(char_config.description).strip_edges() != "":
		summary += "\n  Description: " + str(char_config.description)
	
	return summary

static func _load_template(settings_manager) -> Dictionary:
	var raw_text: String = ""
	if settings_manager != null:
		raw_text = str(settings_manager.get_setting("scene_prompt"))
	return _parse_json(raw_text, "res://prompts/scene_prompt.json")

static func _parse_json(raw_text: String, fallback_path: String) -> Dictionary:
	var text_to_parse: String = raw_text
	if text_to_parse.strip_edges() == "" and fallback_path != "" and FileAccess.file_exists(fallback_path):
		text_to_parse = FileAccess.get_file_as_string(fallback_path)
	if text_to_parse.strip_edges() == "":
		return {}
	var json: JSON = JSON.new()
	var err: int = json.parse(text_to_parse)
	if err != OK:
		print("PromptBuilder: Failed to parse JSON (", json.get_error_message(), ")")
		return {}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data

static func _append_persona_context(prompt_parts: Array, settings_manager) -> void:
	if settings_manager == null:
		return

	var persona_lines = settings_manager.get_active_persona_context_lines()
	if persona_lines.size() == 0:
		return

	prompt_parts.append("\nPlayer Persona Details:")
	for line in persona_lines:
		prompt_parts.append(line)
	prompt_parts.append("The player character's physical description and / or other details.")

static func _finalize_prompt(parts: Array, title: String) -> String:
	var final_prompt = "\n".join(parts)
	print("=== %s ===" % title)
	print(final_prompt)
	print("=== END PROMPT ===")
	return final_prompt

static func _append_custom_instruction(prompt_parts: Array, settings_manager, setting_key: String, default_lines: Array) -> void:
	var instructions: String = ""
	if settings_manager:
		instructions = str(settings_manager.get_setting(setting_key))
	if instructions.strip_edges() != "":
		prompt_parts.append(instructions)
		return
	for line in default_lines:
		prompt_parts.append(line)
