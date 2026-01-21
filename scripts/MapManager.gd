extends Node

const MAPS_PATH = "res://assets/Maps"
const IMAGE_EXTS = ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXTS = ["mp3", "wav", "ogg"]

class MapData:
	var id: String
	var display_name: String
	var texture_path: String
	var music_path: String = ""

var maps := {}
var default_map_id := ""

func _ready():
	_scan_maps()

func _scan_maps():
	maps.clear()
	default_map_id = ""
	var dir = DirAccess.open(MAPS_PATH)
	if not dir:
		print("MapManager: No Maps directory found at ", MAPS_PATH)
		return
	var audio_lookup := {}
	var texture_files: Array = []
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() or entry.begins_with("."):
			entry = dir.get_next()
			continue
		var ext = entry.get_extension().to_lower()
		if ext in IMAGE_EXTS:
			texture_files.append(entry)
		elif ext in AUDIO_EXTS:
			audio_lookup[entry.get_basename().to_lower()] = MAPS_PATH + "/" + entry
		entry = dir.get_next()
	dir.list_dir_end()
	for texture_file in texture_files:
		var base_name = texture_file.get_basename()
		var normalized = _normalize_id(base_name)
		var map_data = MapData.new()
		map_data.id = normalized
		map_data.display_name = _format_display_name(base_name)
		map_data.texture_path = MAPS_PATH + "/" + texture_file
		map_data.music_path = _match_audio(base_name, normalized, audio_lookup)
		maps[normalized] = map_data
		if default_map_id == "":
			default_map_id = normalized

func _match_audio(base_name: String, normalized: String, audio_lookup: Dictionary) -> String:
	var base_lower = base_name.to_lower()
	if audio_lookup.has(base_lower):
		return audio_lookup[base_lower]
	if audio_lookup.has(normalized):
		return audio_lookup[normalized]
	return ""

func get_map_for_region(region_name: String):
	if maps.is_empty():
		return null
	var normalized = _normalize_id(region_name)
	if maps.has(normalized):
		return maps[normalized]
	return maps.get(default_map_id)

func get_available_map_ids() -> Array:
	return maps.keys()

func _normalize_id(text: String) -> String:
	var cleaned = text.to_lower()
	cleaned = cleaned.replace(" ", "_")
	cleaned = cleaned.replace("_map", "")
	cleaned = cleaned.replace(" map", "")
	return cleaned

func _format_display_name(base_name: String) -> String:
	var cleaned = base_name
	cleaned = cleaned.replace("_map", "")
	cleaned = cleaned.replace(".png", "")
	cleaned = cleaned.replace(".jpg", "")
	var parts = cleaned.replace("_", " ").split(" ", false)
	for i in range(parts.size()):
		var part = parts[i]
		if part.length() == 0:
			continue
		parts[i] = part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return " ".join(parts)
