class_name DialogueParser
extends RefCounted

## Parses LLM responses into structured dialogue data
## Handles narrator text, character dialogue, and sprite commands

# Data classes for structured representation
class DialogueLine:
	var type: String  # "narrator", "dialogue", "sprite_command", "character_command", "location_command"
	var speaker_tag: String  # Character tag (e.g., "twi") or "narrator"
	var speaker_name: String  # Display name (e.g., "Twilight Sparkle")
	var text: String  # The actual dialogue or narration text
	var emotion: String  # Current emotion if sprite command encountered
	var color: Color  # Speaker color for UI
	var command_type: String  # For character commands: "enter", "exit", "step_aside"
	var location_id: String  # For location commands: the target location_id

	func _init(p_type: String = "", p_speaker_tag: String = "", p_text: String = ""):
		type = p_type
		speaker_tag = p_speaker_tag
		text = p_text
		emotion = ""
		color = Color.WHITE
		command_type = ""
		location_id = ""

class ParsedDialogue:
	var lines: Array[DialogueLine] = []  # All dialogue lines in order
	var sprite_commands: Dictionary = {}  # tag -> emotion mapping
	var character_commands: Array = []  # Array of {type, tag} dictionaries
	var location_commands: Array = []  # Array of location_id strings

	func add_line(line: DialogueLine) -> void:
		lines.append(line)

	func add_sprite_command(tag: String, emotion: String) -> void:
		sprite_commands[tag] = emotion

	func add_character_command(command_type: String, tag: String) -> void:
		character_commands.append({"type": command_type, "tag": tag})

	func add_location_command(location_id: String) -> void:
		location_commands.append(location_id)

# Regex patterns (compiled once for performance)
static var _sprite_regex: RegEx = null
static var _dialogue_regex: RegEx = null
static var _character_command_regex: RegEx = null
static var _group_command_regex: RegEx = null
static var _location_command_regex: RegEx = null
static var _narrator_regex: RegEx = null
static func _clean_narration_text(text: String) -> String:
	var cleaned: String = text.strip_edges()
	while cleaned.begins_with("."):
		cleaned = cleaned.substr(1, cleaned.length() - 1).strip_edges()
	return cleaned

## Strip malformed commands and stray BBCode tags that the LLM might emit
static func _strip_malformed_commands(text: String) -> String:
	var cleaned: String = text
	
	# Remove any malformed sprite commands (including ones with weird emotion names)
	# This catches [sprite: tag emotion] even if emotion has weird characters
	var sprite_broad_regex: RegEx = RegEx.new()
	sprite_broad_regex.compile("\\[sprite:[^\\]]*\\]")
	cleaned = sprite_broad_regex.sub(cleaned, "", true)
	
	# Remove stray BBCode closing tags (orphaned [/tag] without opening)
	var bbcode_close_regex: RegEx = RegEx.new()
	bbcode_close_regex.compile("\\[/[^\\]]+\\]")
	cleaned = bbcode_close_regex.sub(cleaned, "", true)
	
	# Remove common stray BBCode opening tags that aren't properly formatted
	# This catches things like [color=#...] without matching closing tags
	var bbcode_open_regex: RegEx = RegEx.new()
	bbcode_open_regex.compile("\\[(color|b|i|u|s|code|center|right|left|url|img|font|table|cell)=[^\\]]*\\]")
	cleaned = bbcode_open_regex.sub(cleaned, "", true)
	
	# Remove simple BBCode tags like [b], [i], [u]
	var simple_bbcode_regex: RegEx = RegEx.new()
	simple_bbcode_regex.compile("\\[(b|i|u|s|code|center|right|left)\\]")
	cleaned = simple_bbcode_regex.sub(cleaned, "", true)
	
	return cleaned.strip_edges()

## Initialize regex patterns
static func _init_regex() -> void:
	if _sprite_regex != null:
		return  # Already initialized

	# Match: [sprite: tag emotion] - emotion can contain underscores, apostrophes, dashes
	_sprite_regex = RegEx.new()
	_sprite_regex.compile("\\[sprite:\\s*(\\w+)\\s+([\\w'\\-]+)\\]")

	# Match: tag "dialogue text" - supports both plain tags (twi) and braced tags ({twi}), optional colon
	_dialogue_regex = RegEx.new()
	_dialogue_regex.compile('\\{?(\\w+)\\}?:?\\s+"([^"]+)"')

	# Match: [character_exit: tag] or [exit: tag]
	_character_command_regex = RegEx.new()
	_character_command_regex.compile("\\[\\s*((?i:character_exit|exit)):\\s*([a-zA-Z0-9_]+)\\]")

	# Match: [group: tag1 tag2 ...]
	_group_command_regex = RegEx.new()
	_group_command_regex.compile("\\[\\s*(?i:group):\\s*([a-zA-Z0-9_\\s]+)\\]")

	# Match: [location: location_id]
	_location_command_regex = RegEx.new()
	_location_command_regex.compile("\\[\\s*(?i:location):\\s*([a-zA-Z0-9_]+)\\]")

	# Match: narrator "text"
	_narrator_regex = RegEx.new()
	_narrator_regex.compile('narrator\\s+"([^"]+)"')

## Main parsing function
## Returns a ParsedDialogue object containing all structured data
static func parse(raw_text: String, character_manager = null) -> ParsedDialogue:
	_init_regex()

	var result = ParsedDialogue.new()
	var current_emotions: Dictionary = {}  # Track current emotion per character

	# Pre-process: Ensure dialog lines are separated by newlines
	# Catches cases like: twi: "Text"spike: "Text"
	var split_regex = RegEx.new()
	split_regex.compile('(")\\s*(\\w+:?\\s*")')
	var processed_text = split_regex.sub(raw_text, "$1\n$2", true)

	# Split into lines for processing
	var lines = processed_text.split("\n")

	var previous_line_type = ""
	var last_displayable_type = ""  # Tracks last narrator/dialogue, not commands

	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.is_empty():
			continue

		# Check for sprite commands first (these modify state but don't display)
		var sprite_match = _sprite_regex.search(trimmed)
		if sprite_match:
			var tag = sprite_match.get_string(1).to_lower()
			var emotion = sprite_match.get_string(2).to_lower()
			current_emotions[tag] = emotion
			result.add_sprite_command(tag, emotion)
			# Record as a line so sprite-only entries still render
			var sprite_line = DialogueLine.new("sprite_command", tag, "")
			sprite_line.emotion = emotion
			result.add_line(sprite_line)
			previous_line_type = "sprite_command"
			continue
		# Check for character commands (exit only)
		var char_cmd_match = _character_command_regex.search(trimmed)
		if char_cmd_match:
			var command_type = char_cmd_match.get_string(1).to_lower()
			var tag = char_cmd_match.get_string(2).to_lower()
			result.add_character_command(command_type, tag)
			var command_line = DialogueLine.new("character_command", tag, "")
			command_line.command_type = command_type
			result.add_line(command_line)
			previous_line_type = "character_command"
			continue

		# Check for group commands
		var group_cmd_match = _group_command_regex.search(trimmed)
		if group_cmd_match:
			var tags_str = group_cmd_match.get_string(1).strip_edges()
			var tags = tags_str.split(" ", false)
			var group_line = DialogueLine.new("group_command", "system", "")
			# Store tags in text field for simplicity, or add a proper field
			group_line.text = tags_str 
			result.add_line(group_line)
			previous_line_type = "group_command"
			continue

		# Check for location commands
		var location_cmd_match = _location_command_regex.search(trimmed)
		if location_cmd_match:
			var location_id = location_cmd_match.get_string(1).to_lower()
			result.add_location_command(location_id)
			# Create a DialogueLine for inline processing
			var location_line = DialogueLine.new("location_command", "", "")
			location_line.location_id = location_id
			result.add_line(location_line)
			previous_line_type = "location_command"
			continue

		# Check for narrator text
		var narrator_match = _narrator_regex.search(trimmed)
		if narrator_match:
			var text = _clean_narration_text(narrator_match.get_string(1))
			
			# Force newline separation for LLM responses if consecutive narration
			if previous_line_type == "narrator":
				text = "\n" + text
				
			var narrator_line = DialogueLine.new("narrator", "narrator", text)
			narrator_line.speaker_name = "Narrator"
			narrator_line.color = Color(0.8, 0.8, 0.8)  # Light gray for narrator
			result.add_line(narrator_line)
			previous_line_type = "narrator"
			last_displayable_type = "narrator"
			continue

		# Check for character dialogue
		var dialogue_match = _dialogue_regex.search(trimmed)
		if dialogue_match:
			var tag = dialogue_match.get_string(1).to_lower()
			var text = dialogue_match.get_string(2)

			var dialogue_line = DialogueLine.new("dialogue", tag, text)

			# Get character info if manager available
			if character_manager and character_manager.has_method("get_character"):
				var char_config = character_manager.get_character(tag)
				if char_config:
					dialogue_line.speaker_name = char_config.name
					dialogue_line.color = char_config.color
				else:
					dialogue_line.speaker_name = tag.capitalize()
					dialogue_line.color = Color.WHITE
			else:
				dialogue_line.speaker_name = tag.capitalize()
				dialogue_line.color = Color.WHITE

			# Set emotion if we have one tracked
			if tag in current_emotions:
				dialogue_line.emotion = current_emotions[tag]

			result.add_line(dialogue_line)
			previous_line_type = "dialogue"
			last_displayable_type = "dialogue"
			continue

		# Fallback: any non-tagged line is treated as narration
		var narration_text: String = trimmed
		if narration_text.length() >= 2 and narration_text.begins_with("\"") and narration_text.ends_with("\""):
			narration_text = narration_text.substr(1, narration_text.length() - 2).strip_edges()
		
		# Strip any malformed sprite commands, BBCode tags, and other commands
		narration_text = _strip_malformed_commands(narration_text)
		narration_text = _clean_narration_text(narration_text)
		
		# Skip empty lines after cleanup
		if narration_text.strip_edges().is_empty():
			continue
		
		# Force newline separation for LLM narration if last displayable was narrator
		# This handles cases where sprite commands appear between narrator lines
		if last_displayable_type == "narrator":
			narration_text = "\n" + narration_text
			
		var narration_line = DialogueLine.new("narrator", "narrator", narration_text)
		narration_line.speaker_name = ""
		narration_line.color = Color(0.8, 0.8, 0.8)
		result.add_line(narration_line)
		previous_line_type = "narrator"
		last_displayable_type = "narrator"

	return result

## Extract just the displayable text (without commands)
## Useful for fallback or simple text display
static func extract_clean_text(raw_text: String) -> String:
	_init_regex()

	var clean = raw_text

	# Remove sprite commands
	clean = _sprite_regex.sub(clean, "", true)

	# Remove character commands
	clean = _character_command_regex.sub(clean, "", true)
	
	# Remove group commands
	clean = _group_command_regex.sub(clean, "", true)

	# Remove location commands
	clean = _location_command_regex.sub(clean, "", true)

	# Clean up extra whitespace
	var lines = clean.split("\n")
	var filtered_lines: Array[String] = []
	for line in lines:
		var trimmed = line.strip_edges()
		if not trimmed.is_empty():
			filtered_lines.append(trimmed)

	return "\n".join(filtered_lines)

## Get all unique character tags mentioned in the text
static func get_mentioned_characters(raw_text: String) -> Array[String]:
	_init_regex()

	var characters: Array[String] = []
	var seen: Dictionary = {}

	# From sprite commands
	for match in _sprite_regex.search_all(raw_text):
		var tag = match.get_string(1).to_lower()
		if tag not in seen:
			characters.append(tag)
			seen[tag] = true

	# From dialogue (tag is in capture group 1, already strips braces via regex)
	for match in _dialogue_regex.search_all(raw_text):
		var tag = match.get_string(1).to_lower()
		if tag != "narrator" and tag not in seen:
			characters.append(tag)
			seen[tag] = true

	# From character commands
	for match in _character_command_regex.search_all(raw_text):
		var tag = match.get_string(2).to_lower()
		if tag not in seen:
			characters.append(tag)
			seen[tag] = true

	return characters
