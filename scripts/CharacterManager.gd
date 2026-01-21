extends Node
class_name CharacterManager

const CORE_CHAR_PATH = "res://assets/CoreCharacters"
const CUSTOM_CHAR_PATH = "res://assets/CustomCharacters"

class CharacterConfig:
	var tag: String
	var name: String
	var color: Color
	var folder_path: String
	var sprites: Array = []
	var description: String = ""
	var character_type: String = ""
	var location_data: Dictionary = {}
	var icon_path: String = ""
	var is_custom: bool = false
	
	func _init(p_tag, p_name, p_color, p_folder):
		tag = p_tag
		name = p_name
		color = _convert_to_color(p_color)
		folder_path = _ensure_trailing_slash(p_folder)
	
	func _convert_to_color(value):
		if typeof(value) == TYPE_COLOR:
			return value
		return Color.from_string(str(value), Color.WHITE)
	
	func _ensure_trailing_slash(path: String) -> String:
		if path == "":
			return path
		return path if path.ends_with("/") else path + "/"

var characters = {}
var active_characters = [] # List of tags

func _ready():
	_load_core_characters()
	_load_custom_characters()

func _load_core_characters():
	# Define the Mane 6 + key NPCs bundled with the game
	var base_path = CORE_CHAR_PATH + "/"
	add_character("twi", "Twilight Sparkle", "#9B4BA9", base_path + "Twilight/sprites/")
	add_character("spike", "Spike", "#7FBF00", base_path + "Spike/sprites/")
	add_character("rarity", "Rarity", "#FFFFFF", base_path + "Rarity/sprites/")
	add_character("shy", "Fluttershy", "#FAE194", base_path + "Fluttershy/sprites/")
	add_character("aj", "Applejack", "#F5A347", base_path + "Applejack/sprites/")
	add_character("pinkie", "Pinkie Pie", "#F5A9C5", base_path + "Pinkie/sprites/")
	add_character("dash", "Rainbow Dash", "#99CCFF", base_path + "Rainbow/sprites/")
	add_character("trixie", "Trixie Lulamoon", "#6CA6E8", base_path + "Trixie/sprites/")
	add_character("zecora", "Zecora", "#7C7C7C", base_path + "Zecora/sprites/")
	add_character("luna", "Princess Luna", "#AFEEEE", base_path + "Luna/sprites/")
	add_character("chrys", "Queen Chrysalis", "#00FF00", base_path + "Chrysalis/sprites/")
	add_character("cel", "Princess Celestia", "#FFD700", base_path + "Celestia/sprites/")

func _load_custom_characters():
	var custom_dir = CUSTOM_CHAR_PATH
	var dir = DirAccess.open(custom_dir)
	if not dir:
		print("Custom character directory not found: ", custom_dir)
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var loaded = 0
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			if _load_custom_character_folder(custom_dir, folder_name):
				loaded += 1
		folder_name = dir.get_next()
	dir.list_dir_end()
	print("Custom characters loaded: ", loaded)

func _load_custom_character_folder(base_dir: String, folder_name: String) -> bool:
	var folder_path = base_dir.path_join(folder_name)
	var meta_path = folder_path.path_join("character.json")
	if not FileAccess.file_exists(meta_path):
		print("[CustomChar] Missing character.json in ", folder_path)
		return false
	
	var meta_data = _read_json(meta_path)
	if typeof(meta_data) != TYPE_DICTIONARY:
		print("[CustomChar] Invalid metadata in ", meta_path)
		return false
	
	var tag = _sanitize_tag(str(meta_data.get("tag", folder_name)))
	var name = str(meta_data.get("name", folder_name))
	var color_hex = str(meta_data.get("color", "#FFFFFF"))
	var sprite_path = _find_sprite_folder(folder_path)
	if sprite_path == "":
		print("[CustomChar] No sprites folder found for ", folder_name)
		return false
	
	var metadata = {
		"description": meta_data.get("description", ""),
		"type": meta_data.get("type", ""),
		"location": _build_location_metadata(folder_path, meta_data.get("location", {})),
		"is_custom": true
	}

	var config = add_character(tag, name, color_hex, sprite_path, metadata)
	if config:
		return true
	return false

func add_character(tag, name, color_hex, folder, metadata: Dictionary = {}):
	var config = CharacterConfig.new(tag, name, color_hex, folder)
	if characters.has(tag):
		print("Warning: Character tag already registered, overriding: ", tag)
	if metadata.has("description"):
		config.description = metadata["description"]
	if metadata.has("type"):
		config.character_type = metadata["type"]
	if metadata.has("location") and typeof(metadata["location"]) == TYPE_DICTIONARY:
		config.location_data = metadata["location"].duplicate(true)
		if config.location_data.has("icon_path"):
			config.icon_path = config.location_data["icon_path"]
	if metadata.get("is_custom", false):
		config.is_custom = true
	if metadata.has("icon_path") and config.icon_path == "":
		config.icon_path = metadata["icon_path"]

	# Capture the sprite list so prompts/UI can describe valid emotions
	if folder != "":
		config.sprites = _scan_available_sprites(folder)
	characters[tag] = config
	print("Registered character: ", name, " (", tag, ")")
	return config

func get_all_characters(sorted: bool = false) -> Array:
	var result: Array = []
	for tag in characters.keys():
		result.append(characters[tag])
	if sorted:
		result.sort_custom(Callable(self, "_compare_character_names"))
	return result

func get_all_character_tags() -> Array:
	return characters.keys()

func _compare_character_names(a, b):
	if typeof(a) != TYPE_OBJECT or typeof(b) != TYPE_OBJECT:
		return false
	return a.name.nocasecmp_to(b.name) < 0

func get_character(tag):
	return characters.get(tag)

func add_active_character(tag):
	if characters.has(tag) and not tag in active_characters:
		active_characters.append(tag)
		return true
	return false

func remove_active_character(tag):
	if tag in active_characters:
		active_characters.erase(tag)
		return true
	return false

func get_active_characters() -> Array:
	var result: Array = []
	for tag in active_characters:
		var cfg = get_character(tag)
		if cfg:
			result.append(cfg)
	return result

func clear_active_characters() -> void:
	active_characters.clear()

func _read_json(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		print("[CustomChar] Failed to parse JSON: ", path, " (", json.get_error_message(), ")")
		return null
	return json.get_data()

func _find_sprite_folder(character_folder: String) -> String:
	var dir = DirAccess.open(character_folder)
	if not dir:
		return ""
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		if dir.current_is_dir() and entry.to_lower() == "sprites":
			var sprites_path = character_folder.path_join(entry)
			dir.list_dir_end()
			return sprites_path if sprites_path.ends_with("/") else sprites_path + "/"
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _scan_available_sprites(folder_path: String) -> Array:
	var result = []
	var dir = DirAccess.open(folder_path)
	if not dir:
		return result
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and not entry.begins_with("."):
			var ext = entry.get_extension().to_lower()
			if ext in ["png", "webp", "jpg", "jpeg"]:
				result.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	return result

func _build_location_metadata(character_folder: String, raw_location_data) -> Dictionary:
	if typeof(raw_location_data) != TYPE_DICTIONARY:
		return {}
	var location_data = raw_location_data.duplicate(true)
	if location_data.has("icon"):
		var icon_rel_path = str(location_data["icon"])
		location_data["icon_path"] = character_folder.path_join(icon_rel_path)
	return location_data

func _sanitize_tag(raw_tag: String) -> String:
	var regex = RegEx.new()
	regex.compile("[^a-z]")
	var sanitized = regex.sub(raw_tag.to_lower(), "", true)
	if sanitized == "":
		return "oc"
	return sanitized
