extends Node
class_name LocationManager

const LOCATION_ROOTS: Array[String] = ["res://assets/Locations"]

class LocationData:
	var id: String
	var identifier: String
	var name: String
	var region: String
	var region_id: String = ""
	var background_path: String
	var music_path: String
	var description: String
	var map_rect: Rect2 = Rect2()
	var has_map_rect: bool = false
	
	func _init(p_id: String, p_identifier: String, p_name: String, p_region: String, p_bg: String, p_music: String, p_desc: String):
		id = p_id
		identifier = p_identifier
		name = p_name
		region = p_region
		background_path = p_bg
		music_path = p_music
		description = p_desc

var locations: Dictionary = {}
var location_aliases: Dictionary = {}
var current_location_id: String = "" # Default

func _ready():
	_load_locations()

func _load_locations():
	locations.clear()
	location_aliases.clear()
	for root_path in LOCATION_ROOTS:
		_scan_location_root(root_path)
	_create_aliases()
	print("Total locations loaded: ", locations.size())

func _scan_location_root(root_path: String):
	var dir = DirAccess.open(root_path)
	if not dir:
		print("Info: Skipping missing location root: ", root_path)
		return

	dir.list_dir_begin()
	var region_name = dir.get_next()
	while region_name != "":
		if dir.current_is_dir() and not region_name.begins_with("."):
			_scan_region_locations(root_path, region_name)
		region_name = dir.get_next()
	dir.list_dir_end()

func _scan_region_locations(root_path: String, region: String):
	var region_path = _join_paths(root_path, region)
	var dir = DirAccess.open(region_path)
	if not dir:
		return

	dir.list_dir_begin()
	var location_name = dir.get_next()

	while location_name != "":
		if dir.current_is_dir() and not location_name.begins_with("."):
			_add_location_from_folder(root_path, region, location_name)
		location_name = dir.get_next()

	dir.list_dir_end()

func _add_location_from_folder(root_path: String, region: String, location_id: String, fallback_name: String = ""):
	var location_base = _join_paths(_join_paths(root_path, region), location_id)
	var location_path = _ensure_trailing_slash(location_base)
	
	# Check if location.json exists
	var json_path = location_path + "location.json"
	var name = fallback_name if fallback_name != "" else location_id.replace("_", " ").capitalize()
	var description: String = ""
	var description_from_json: String = ""
	var json_data = null
	
	if FileAccess.file_exists(json_path):
		var file = FileAccess.open(json_path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(json_text)
			if error == OK:
				json_data = json.get_data()
				if json_data.has("name"):
					name = json_data["name"]
				if json_data.has("description"):
					description_from_json = str(json_data["description"])
	
	var bg_path = _find_background_image(location_path)
	var music_path = _find_music_file(location_path)
	var region_label = _format_region_name(region)
	if description_from_json != "":
		description = description_from_json
	elif description == "":
		description = name + " located in " + region_label + "."

	var identifier: String = _build_location_identifier(region, location_id, description_from_json)

	if bg_path != "":
		var loc: LocationData = LocationData.new(location_id, identifier, name, region_label, bg_path, music_path, description)
		loc.region_id = region.to_lower()
		if json_data and json_data.has("pos"):
			var pos_data = json_data["pos"]
			if typeof(pos_data) == TYPE_ARRAY and pos_data.size() >= 4:
				loc.map_rect = Rect2(float(pos_data[0]), float(pos_data[1]), float(pos_data[2]), float(pos_data[3]))
				loc.has_map_rect = true
		if locations.has(location_id):
			print("Info: Overriding location definition for ", location_id, " from ", root_path)
		locations[location_id] = loc
		
		# Only print for non-empty locations (reduces spam)
		if description != "":
			print("Loaded: ", name)
	else:
		print("Warning: No background found for ", region, "/", location_id)

func _create_aliases():
	# Create useful aliases for common locations
	location_aliases.clear()
	var aliases: Dictionary = {
		"golden_oak_library": "golden_oak_guestroom",
		"library": "golden_oak_guestroom",
		"fluttershy_cottage": "fluttershy_cottage_inside",
		"main_square": "ponyville_main_square",
		"town_square": "ponyville_main_square"
	}
	
	for alias in aliases.keys():
		var target: String = str(aliases[alias])
		if locations.has(target):
			location_aliases[alias] = target
		else:
			print("Info: Alias target missing for ", alias, " -> ", target)

func resolve_location_id(id: String) -> String:
	var trimmed: String = id.strip_edges()
	if trimmed == "":
		return ""
	if locations.has(trimmed):
		return trimmed
	if location_aliases.has(trimmed):
		return location_aliases[trimmed]
	return trimmed

func get_location_identifier(id: String) -> String:
	var resolved: String = resolve_location_id(id)
	if resolved != "" and locations.has(resolved):
		var loc: LocationData = locations[resolved]
		return loc.identifier
	return resolved

func get_location(id):
	var resolved: String = resolve_location_id(id)
	return locations.get(resolved)

func set_location(id):
	var resolved: String = resolve_location_id(id)
	if locations.has(resolved):
		current_location_id = resolved
		print("Location changed to: ", locations[resolved].name)
		return true
	print("Location not found: ", id)
	return false

func get_all_regions() -> Array:
	var regions: Array = []
	for loc_id in locations.keys():
		var loc: LocationData = locations[loc_id]
		if loc.region not in regions:
			regions.append(loc.region)
	return regions

func get_locations_in_region(region: String) -> Array:
	var result: Array = []
	for loc_id in locations.keys():
		var loc: LocationData = locations[loc_id]
		if loc.region == region:
			result.append(loc)
	return result

func _find_background_image(location_path: String) -> String:
	var extensions = [".png", ".jpg", ".jpeg", ".webp"]
	for ext in extensions:
		var test_path = location_path + "background" + ext
		if FileAccess.file_exists(test_path):
			return test_path
	var dir = DirAccess.open(location_path)
	if not dir:
		return ""
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() or entry.begins_with("."):
			entry = dir.get_next()
			continue
		var ext = "." + entry.get_extension().to_lower()
		if ext in extensions:
			dir.list_dir_end()
			return location_path + entry
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _find_music_file(location_path: String) -> String:
	var preferred = ["bgm.mp3", "bgm.wav", "bgm.ogg"]
	for filename in preferred:
		var test_path = location_path + filename
		if FileAccess.file_exists(test_path):
			return test_path
	var dir = DirAccess.open(location_path)
	if not dir:
		return ""
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() or entry.begins_with("."):
			entry = dir.get_next()
			continue
		var name_lower = entry.to_lower()
		if name_lower.begins_with("bgm") and entry.get_extension().to_lower() in ["mp3", "wav", "ogg"]:
			dir.list_dir_end()
			return location_path + entry
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _join_paths(base: String, child: String) -> String:
	if base.ends_with("/"):
		return base + child
	return base + "/" + child

func _ensure_trailing_slash(path: String) -> String:
	return path if path.ends_with("/") else path + "/"

func _format_region_name(region_id: String) -> String:
	var cleaned = region_id.replace("_", " ").strip_edges()
	if cleaned == "":
		return "Unknown"
	var parts = cleaned.split(" ", false)
	for i in range(parts.size()):
		var part = parts[i]
		if part.length() == 0:
			continue
		parts[i] = part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return " ".join(parts)

func _build_location_identifier(region: String, location_id: String, description_from_json: String) -> String:
	var base: String = "%s/%s" % [region, location_id]
	var trimmed_desc: String = description_from_json.strip_edges()
	if trimmed_desc != "":
		return "%s %s" % [base, trimmed_desc]
	return base
