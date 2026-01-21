extends Node
class_name SettingsManager

# Settings storage with defaults
const PERSONA_SLOT_COUNT := 10
const AUTO_SUMMARY_GAP := 10000

# Persona field options - SINGLE SOURCE OF TRUTH for all persona dropdowns
# Format: Array of {id: "internal_value", label: "Display Name"}
# Add new options here and they will appear everywhere in the game

const SEX_OPTIONS := [
	{"id": "", "label": "Not Specified"},
	{"id": "male", "label": "Male"},
	{"id": "female", "label": "Female"}
]

const SPECIES_OPTIONS := [
	{"id": "", "label": "Not Specified"},
	{"id": "human", "label": "Human"},
	{"id": "pony", "label": "Pony"},
	{"id": "griffon", "label": "Griffon"},
	{"id": "changeling", "label": "Changeling"},
	{"id": "zebra", "label": "Zebra"},
	{"id": "dragon", "label": "Dragon"}
]

# Race options - only applies to pony species
const RACE_OPTIONS := [
	{"id": "", "label": "Not Specified"},
	{"id": "unicorn", "label": "Unicorn"},
	{"id": "pegasus", "label": "Pegasus"},
	{"id": "earth_pony", "label": "Earth Pony"},
	{"id": "bat_pony", "label": "Bat Pony"}
]

# === Persona Field Helper Functions ===
# These provide index lookups so other scripts don't need to duplicate logic

static func get_sex_index(sex_id: String) -> int:
	for i in range(SEX_OPTIONS.size()):
		if SEX_OPTIONS[i]["id"] == sex_id.to_lower():
			return i
	return 0

static func get_sex_id(index: int) -> String:
	if index >= 0 and index < SEX_OPTIONS.size():
		return SEX_OPTIONS[index]["id"]
	return ""

static func get_species_index(species_id: String) -> int:
	for i in range(SPECIES_OPTIONS.size()):
		if SPECIES_OPTIONS[i]["id"] == species_id.to_lower():
			return i
	return 0

static func get_species_id(index: int) -> String:
	if index >= 0 and index < SPECIES_OPTIONS.size():
		return SPECIES_OPTIONS[index]["id"]
	return ""

static func get_race_index(race_id: String) -> int:
	for i in range(RACE_OPTIONS.size()):
		if RACE_OPTIONS[i]["id"] == race_id.to_lower():
			return i
	return 0

static func get_race_id(index: int) -> String:
	if index >= 0 and index < RACE_OPTIONS.size():
		return RACE_OPTIONS[index]["id"]
	return ""

# Populate an OptionButton with options from an array
static func populate_option_button(option_button: OptionButton, options: Array) -> void:
	option_button.clear()
	for i in range(options.size()):
		option_button.add_item(options[i]["label"], i)

var settings = {
	"api_url": "api_url",
	"api_key": "",
	"model": "model_name",
	"provider": "openai", # openai, gemini
	"gemini_key": "",
	"gemini_model": "gemini-3-pro-preview",
	"temperature": 0.7,
	"max_context": 50000,
	"auto_summary_context": 40000,
	"max_response_length": 8000,
	"top_p": 1.0,
	"top_k": 0,
	"system_prompt": "You are roleplaying characters in a My Little Pony visual novel. Write narration as plain lines with no character tag. Use tag \"...\" for each character's dialogue (no p/player dialogue). Parse and follow [sprite: tag emotion] and [location: id] commands. Keep tone warm, descriptive, and reactive.",
	"scene_prompt": "",
	"summary_prompt": "Summarize the recent story events for continuity. Focus on key relationships and revelations.",
	"impersonate_prompt": "Write for the user and only the user for this turn based upon the user's prior interactions and known persona. Output exactly one line that starts with player \"...\" to represent the player's dialogue. Do not include narrator lines, NPC dialogue, or sprite commands for the player. The user does not have sprites, so never emit [sprite: player emotion]. Convey any body language or internal thoughts within the same quoted line if needed.",
	"travel_prompt": "Write 2-4 lines of narration (no character tag) describing what you feel and notice while traveling from the starting point to the destination. Use second-person narration (you/your). Keep it narration-only (no character prefixes, sprite commands, or [location] tags). End with arrival, ready for the next interaction.",
	"persona_profiles": [],  # Now stores structured Dictionaries: {name, sex, species, race, appearance}
	"active_persona_index": 0
}

var config_path = "user://equestr_ai_settings.json"

func _ready():
	load_settings()

func load_settings():
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(json_text)
			if error == OK:
				var loaded_settings = json.get_data()
				# Merge loaded settings with defaults
				for key in loaded_settings.keys():
					if settings.has(key):
						settings[key] = loaded_settings[key]
					elif key == "conversation_template":
						settings["scene_prompt"] = loaded_settings[key]
				
				# Check if we need to migrate old defaults to file-based prompts
				_check_and_migrate_prompts()
				_migrate_instruction_keys()
				var migrated_narration: bool = _migrate_narration_format()
				var migrated_format_rules: bool = _migrate_scene_prompt_format_rules()
				var migrated_header: bool = _migrate_scene_prompt_header()
				var migrated_player_tag: bool = _migrate_player_tag()
				var migrated_summary: bool = _migrate_summary_prompt_format()
				_ensure_persona_slots()
				var updated_prompts := _ensure_prompt_defaults()
				_enforce_context_limits()
				if updated_prompts or migrated_narration or migrated_format_rules or migrated_header or migrated_player_tag or migrated_summary:
					save_settings()
				
				print("Settings loaded from: ", config_path)
			else:
				print("Failed to parse settings JSON")
	else:
		_ensure_persona_slots()
		_enforce_context_limits()
		var migrated_narration: bool = _migrate_narration_format()
		var migrated_format_rules: bool = _migrate_scene_prompt_format_rules()
		var migrated_header: bool = _migrate_scene_prompt_header()
		var updated_prompts := _ensure_prompt_defaults()
		if updated_prompts or migrated_narration or migrated_format_rules or migrated_header:
			save_settings()

func _check_and_migrate_prompts():
	var old_defaults = {
		"scene_prompt": "",
		"summary_prompt": ""
	}
	
	var updated = false
	for key in old_defaults:
		if settings[key] == old_defaults[key]:
			print("Migrating old default for ", key)
			_load_single_prompt_from_file(key)
			updated = true
	
	if updated:
		save_settings()

func _load_single_prompt_from_file(key: String):
	var path = ""
	match key:
		"scene_prompt": path = "res://prompts/scene_prompt.json"

	if path != "" and FileAccess.file_exists(path):
		settings[key] = FileAccess.get_file_as_string(path)
	else:
		print("No saved settings found, using defaults")
		# Try to load defaults from JSON files if available
		_load_defaults_from_files()
		save_settings()  # Create default settings file

func _load_defaults_from_files():
	# Load scene prompt
	var scene_path = "res://prompts/scene_prompt.json"
	if FileAccess.file_exists(scene_path):
		var content = FileAccess.get_file_as_string(scene_path)
		settings["scene_prompt"] = content

func _migrate_instruction_keys() -> void:
	# Migrate legacy interrupt/formatting prompt into system prompt if it looks empty
	if str(settings.get("system_prompt", "")).strip_edges() == "":
		var legacy_interrupt: String = str(settings.get("interrupt_instructions", ""))
		if legacy_interrupt.strip_edges() != "":
			settings["system_prompt"] = legacy_interrupt

	# Migrate impersonate instructions
	if str(settings.get("impersonate_prompt", "")).strip_edges() == "":
		var legacy_imp: String = str(settings.get("impersonate_instructions", ""))
		if legacy_imp.strip_edges() != "":
			settings["impersonate_prompt"] = legacy_imp

	# Migrate travel instructions
	if str(settings.get("travel_prompt", "")).strip_edges() == "":
		var legacy_travel: String = str(settings.get("travel_instructions", ""))
		if legacy_travel.strip_edges() != "":
			settings["travel_prompt"] = legacy_travel

func _ensure_prompt_defaults() -> bool:
	var changed: bool = false
	if str(settings.get("scene_prompt", "")).strip_edges() == "":
		if FileAccess.file_exists("res://prompts/scene_prompt.json"):
			settings["scene_prompt"] = FileAccess.get_file_as_string("res://prompts/scene_prompt.json")
			changed = true
	if str(settings.get("summary_prompt", "")).strip_edges() == "":
		settings["summary_prompt"] = "Summarize the recent story events for continuity. Focus on key relationships and revelations."
		changed = true
	return changed

func _migrate_narration_format() -> bool:
	var changed: bool = false

	var sys_prompt: String = str(settings.get("system_prompt", ""))

	if sys_prompt.find("Use narrator \"...\" for narration") != -1:
		sys_prompt = sys_prompt.replace(
			"Use narrator \"...\" for narration",
			"Write narration as plain lines with no character tag."
		)
		settings["system_prompt"] = sys_prompt
		changed = true

	var travel_prompt: String = str(settings.get("travel_prompt", ""))
	if travel_prompt.find("format narrator \"...\"") != -1:
		travel_prompt = travel_prompt.replace(
			"Write 2-4 lines using the format narrator \"...\" that describe what you feel and notice while traveling from the starting point to the destination.",
			"Write 2-4 lines of narration (no character tag) describing what you feel and notice while traveling from the starting point to the destination."
		)
		travel_prompt = travel_prompt.replace(
			"Use second-person narration (you/your). Do not include other characters' dialogue, sprite commands, or [location] tags. End with you arriving at the destination and feeling ready for the next interaction.",
			"Use second-person narration (you/your). Keep it narration-only (no character prefixes, sprite commands, or [location] tags). End with you arriving at the destination and feeling ready for the next interaction."
		)
		settings["travel_prompt"] = travel_prompt
		changed = true

	return changed

func _migrate_summary_prompt_format() -> bool:
	var current_prompt = str(settings.get("summary_prompt", "")).strip_edges()
	var changed = false
	
	# If it looks like the old JSON, reset it
	if current_prompt.begins_with("{") or current_prompt.find("\"json_format\"") != -1 or current_prompt.find("\"header\"") != -1:
		settings["summary_prompt"] = "Summarize the recent story events for continuity. Focus on key relationships and revelations."
		changed = true
		print("Migrated summary prompt to plain text.")

	return changed

## Migrate 'p' player tag to 'player' in impersonate_prompt
func _migrate_player_tag() -> bool:
	var changed: bool = false
	var impersonate_prompt: String = str(settings.get("impersonate_prompt", ""))
	
	# Replace old 'p "..."' format with 'player "..."'
	if impersonate_prompt.find("starts with p \"") != -1:
		impersonate_prompt = impersonate_prompt.replace("starts with p \"", "starts with player \"")
		settings["impersonate_prompt"] = impersonate_prompt
		changed = true
	
	if impersonate_prompt.find("[sprite: p ") != -1:
		impersonate_prompt = impersonate_prompt.replace("[sprite: p ", "[sprite: player ")
		settings["impersonate_prompt"] = impersonate_prompt
		changed = true
	
	return changed

## Migrate scene_prompt to include location and exit format rules if missing
func _migrate_scene_prompt_format_rules() -> bool:
	var scene_prompt_str: String = str(settings.get("scene_prompt", ""))
	if scene_prompt_str.strip_edges() == "":
		return false
	
	var changed: bool = false
	
	# Check if location rule is missing (or if we need to force an update for narrator rule)
	# logic simplified: we parse if there's any chance we need to migrate
	var needs_check = false
	if scene_prompt_str.find("[location:") == -1 and scene_prompt_str.find("location_id]") == -1:
		needs_check = true
	if scene_prompt_str.find("narrator") != -1:
		needs_check = true

	if needs_check:
		# Try to parse and update the JSON
		var json = JSON.new()
		var err = json.parse(scene_prompt_str)
		if err == OK:
			var data = json.get_data()
			if typeof(data) == TYPE_DICTIONARY and data.has("format_rules"):
				var rules: Array = data["format_rules"]
				var has_location = false
				var has_exit = false
				var rules_changed = false
				
				# 1. Start Migration: Fix Narrator Rule
				for i in range(rules.size()):
					var r = str(rules[i])
					if r.find("Use narrator \"...\"") != -1 or r.find("Use narrator") != -1:
						rules[i] = "Write narration as plain lines with no character tag"
						rules_changed = true
						changed = true
				
				for rule in rules:
					if str(rule).find("[location:") != -1:
						has_location = true
					if str(rule).find("[exit:") != -1:
						has_exit = true
				
				if not has_location:
					# Insert before "Keep formatting BBCode-free" if present
					var insert_idx = rules.size()
					for i in range(rules.size()):
						if str(rules[i]).find("BBCode-free") != -1:
							insert_idx = i
							break
					rules.insert(insert_idx, "Use [location: location_id] to change to a new location")
					changed = true
					rules_changed = true
				
				if not has_exit:
					var insert_idx = rules.size()
					for i in range(rules.size()):
						if str(rules[i]).find("BBCode-free") != -1:
							insert_idx = i
							break
					rules.insert(insert_idx, "Use [exit: tag] when a character leaves the scene")
					changed = true
					rules_changed = true
				
				if changed or rules_changed:
					data["format_rules"] = rules
			
			if data.has("scene_template") and str(data["scene_template"]).begins_with("Scene premise:"):
				data["scene_template"] = "{scene_prompt}"
				changed = true

			if changed:
				settings["scene_prompt"] = JSON.stringify(data, "    ")
	
	# Fallback: simple string replacement if JSON parsing failed or wasn't needed but conflict exists
	if not changed and scene_prompt_str.find("Use narrator \"...\"") != -1:
		scene_prompt_str = scene_prompt_str.replace("Use narrator \"...\" for narration", "Write narration as plain lines with no character tag")
		# Handle variant without 'for narration'
		scene_prompt_str = scene_prompt_str.replace("Use narrator \"...\"", "Write narration as plain lines with no character tag")
		settings["scene_prompt"] = scene_prompt_str
		changed = true

	return changed

## Migrate scene_prompt header to focus on accurate characterization
func _migrate_scene_prompt_header() -> bool:
	var scene_prompt_str: String = str(settings.get("scene_prompt", ""))
	if scene_prompt_str.strip_edges() == "":
		return false
	
	var changed: bool = false
	
	# List of old headers to migrate
	var old_headers = [
		"You are writing a My Little Pony visual novel scene. Follow the rules below and keep the tone warm, characterful, and playful.",
		"You are roleplaying characters in a My Little Pony visual novel scene. Follow the rules below.",
		"You are writing a Ren'Py scene."
	]
	var new_header = "You are writing a My Little Pony visual novel scene. Follow the rules below and focus on accurate characterization."
	
	# Try to parse as JSON
	var json = JSON.new()
	var err = json.parse(scene_prompt_str)
	if err == OK:
		var data = json.get_data()
		if typeof(data) == TYPE_DICTIONARY and data.has("header"):
			var current_header = str(data["header"])
			for old in old_headers:
				if current_header == old:
					data["header"] = new_header
					settings["scene_prompt"] = JSON.stringify(data, "    ")
					changed = true
					print("Migrated scene_prompt header to new format")
					break
	
	return changed

func save_settings():
	_enforce_context_limits()
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		var json_text = JSON.stringify(settings, "\t")
		file.store_string(json_text)
		file.close()
		print("Settings saved to: ", config_path)
		return true
	else:
		print("Failed to save settings")
		return false

func get_setting(key: String, default = null):
	return settings.get(key, default)

func set_setting(key: String, value):
	if settings.has(key):
		settings[key] = value
		if key == "max_context" or key == "auto_summary_context":
			_enforce_context_limits()
		return true
	return false

func get_all_settings():
	return settings.duplicate()

func _enforce_context_limits() -> void:
	var max_context_value: int = int(settings.get("max_context", 0))
	var auto_summary_value: int = int(settings.get("auto_summary_context", 0))
	max_context_value = max(max_context_value, AUTO_SUMMARY_GAP)
	var allowed_auto: int = max_context_value - AUTO_SUMMARY_GAP
	if allowed_auto < 0:
		allowed_auto = 0
	if auto_summary_value > allowed_auto:
		auto_summary_value = allowed_auto
	if auto_summary_value < 0:
		auto_summary_value = 0
	settings["max_context"] = max_context_value
	settings["auto_summary_context"] = auto_summary_value

func _ensure_persona_slots() -> void:
	if typeof(settings.get("persona_profiles")) != TYPE_ARRAY:
		settings["persona_profiles"] = []

	# Migrate old string-based personas to new structured format
	var needs_migration: bool = false
	for i in range(settings["persona_profiles"].size()):
		var profile = settings["persona_profiles"][i]
		if typeof(profile) == TYPE_STRING:
			needs_migration = true
			settings["persona_profiles"][i] = _migrate_string_to_persona(profile, i)
		elif typeof(profile) != TYPE_DICTIONARY:
			settings["persona_profiles"][i] = _create_empty_persona(i)

	# Ensure we have enough slots
	while settings["persona_profiles"].size() < PERSONA_SLOT_COUNT:
		var idx = settings["persona_profiles"].size()
		settings["persona_profiles"].append(_create_empty_persona(idx))

	if settings["persona_profiles"].size() > PERSONA_SLOT_COUNT:
		settings["persona_profiles"] = settings["persona_profiles"].slice(0, PERSONA_SLOT_COUNT)

	# Ensure each slot has all required fields
	for i in range(settings["persona_profiles"].size()):
		var profile = settings["persona_profiles"][i]
		if typeof(profile) != TYPE_DICTIONARY:
			settings["persona_profiles"][i] = _create_empty_persona(i)
		else:
			# Ensure all fields exist
			if not profile.has("name"):
				profile["name"] = "Persona %d" % (i + 1)
			if not profile.has("sex"):
				profile["sex"] = ""
			if not profile.has("species"):
				profile["species"] = ""
			if not profile.has("race"):
				profile["race"] = ""
			if not profile.has("appearance"):
				profile["appearance"] = ""

	if typeof(settings.get("active_persona_index")) != TYPE_INT:
		settings["active_persona_index"] = 0

	settings["active_persona_index"] = clampi(settings["active_persona_index"], 0, PERSONA_SLOT_COUNT - 1)

	if needs_migration:
		save_settings()

## Create an empty persona dictionary
func _create_empty_persona(index: int) -> Dictionary:
	return {
		"name": "Persona %d" % (index + 1),
		"sex": "",
		"species": "",
		"race": "",
		"appearance": ""
	}

## Migrate old string description to new structured format
func _migrate_string_to_persona(old_desc: String, index: int) -> Dictionary:
	var persona = _create_empty_persona(index)
	if old_desc.strip_edges() != "":
		# Put the old description into appearance field
		persona["appearance"] = old_desc.strip_edges()
		# Try to detect sex/species/race from common patterns
		var lower_desc = old_desc.to_lower()
		if "male" in lower_desc and "female" not in lower_desc:
			persona["sex"] = "male"
		elif "female" in lower_desc or "mare" in lower_desc:
			persona["sex"] = "female"
		if "human" in lower_desc:
			persona["species"] = "human"
		elif "pony" in lower_desc or "unicorn" in lower_desc or "pegasus" in lower_desc or "earth pony" in lower_desc:
			persona["species"] = "pony"
			if "unicorn" in lower_desc:
				persona["race"] = "unicorn"
			elif "pegasus" in lower_desc:
				persona["race"] = "pegasus"
			elif "earth pony" in lower_desc:
				persona["race"] = "earth_pony"
			elif "alicorn" in lower_desc:
				persona["race"] = "alicorn"
	return persona

func get_persona_profiles() -> Array:
	_ensure_persona_slots()
	return settings["persona_profiles"].duplicate(true)

## Set an entire persona profile at the given index
func set_persona_slot(index: int, persona: Variant) -> void:
	_ensure_persona_slots()
	if index < 0 or index >= PERSONA_SLOT_COUNT:
		return

	# Handle backwards compatibility - if a string is passed, convert it
	if typeof(persona) == TYPE_STRING:
		var new_persona = get_persona_at_index(index)
		new_persona["appearance"] = persona.strip_edges()
		settings["persona_profiles"][index] = new_persona
	elif typeof(persona) == TYPE_DICTIONARY:
		settings["persona_profiles"][index] = persona.duplicate()
	else:
		settings["persona_profiles"][index] = _create_empty_persona(index)

## Get persona at specific index
func get_persona_at_index(index: int) -> Dictionary:
	_ensure_persona_slots()
	if index < 0 or index >= PERSONA_SLOT_COUNT:
		return _create_empty_persona(0)
	var profile = settings["persona_profiles"][index]
	if typeof(profile) != TYPE_DICTIONARY:
		return _create_empty_persona(index)
	return profile.duplicate()

## Set a specific field on a persona
func set_persona_field(index: int, field: String, value: String) -> void:
	_ensure_persona_slots()
	if index < 0 or index >= PERSONA_SLOT_COUNT:
		return
	var profile = settings["persona_profiles"][index]
	if typeof(profile) != TYPE_DICTIONARY:
		profile = _create_empty_persona(index)
		settings["persona_profiles"][index] = profile
	profile[field] = value.strip_edges()

## Get a specific field from a persona
func get_persona_field(index: int, field: String) -> String:
	_ensure_persona_slots()
	if index < 0 or index >= PERSONA_SLOT_COUNT:
		return ""
	var profile = settings["persona_profiles"][index]
	if typeof(profile) != TYPE_DICTIONARY:
		return ""
	return str(profile.get(field, ""))

## Update the active persona's field (used by event system)
func update_active_persona_field(field: String, value: String) -> void:
	var active_idx = get_active_persona_index()
	set_persona_field(active_idx, field, value)
	save_settings()

## Get the active persona as a Dictionary
func get_active_persona() -> Dictionary:
	return get_persona_at_index(get_active_persona_index())

func get_active_persona_index() -> int:
	_ensure_persona_slots()
	return settings["active_persona_index"]

func set_active_persona_index(index: int) -> void:
	_ensure_persona_slots()
	settings["active_persona_index"] = clampi(index, 0, PERSONA_SLOT_COUNT - 1)

## Legacy compatibility - returns the appearance field
func get_active_persona_description() -> String:
	var persona = get_active_persona()
	return str(persona.get("appearance", ""))

## Build context lines from structured persona data
func get_active_persona_context_lines() -> Array[String]:
	var result: Array[String] = []
	var persona = get_active_persona()

	var sex = str(persona.get("sex", "")).strip_edges()
	var species = str(persona.get("species", "")).strip_edges()
	var race = str(persona.get("race", "")).strip_edges()
	var appearance = str(persona.get("appearance", "")).strip_edges()

	# Build structured context
	if sex != "":
		result.append("Sex: %s" % sex)
	if species != "":
		if species == "pony" and race != "":
			result.append("Species: %s (%s)" % [race.replace("_", " "), species])
		else:
			result.append("Species: %s" % species)
	elif race != "":
		result.append("Race: %s" % race.replace("_", " "))

	# Add appearance description
	if appearance != "":
		result.append("Appearance: %s" % appearance)

	return result

## Get display name for a persona (for UI)
func get_persona_display_name(index: int) -> String:
	var persona = get_persona_at_index(index)
	var name = str(persona.get("name", "")).strip_edges()
	if name == "" or name.begins_with("Persona "):
		# Build a descriptive name from fields
		var parts: Array[String] = []
		var sex = str(persona.get("sex", "")).strip_edges()
		var species = str(persona.get("species", "")).strip_edges()
		var race = str(persona.get("race", "")).strip_edges()
		if sex != "":
			parts.append(sex.capitalize())
		if species == "pony" and race != "":
			parts.append(race.replace("_", " ").capitalize())
		elif species != "":
			parts.append(species.capitalize())
		if parts.is_empty():
			return "Persona %d" % (index + 1)
		return " ".join(parts)
	return name
