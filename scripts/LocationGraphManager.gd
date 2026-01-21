extends Node

# Location graph defining which locations connect to which neighbors
# This allows the LLM to get a focused list of reachable locations
# and enables pathfinding for travel between distant locations

const NEIGHBOR_GRAPH_PATH := "res://location_graph.json"

# Dictionary mapping location_id -> Array of neighbor location_ids
var location_graph = {}

func _ready():
	_load_location_graph()

func _load_location_graph():
	"""
	Load the location graph from centralized JSON file.
	Falls back to empty graph if file doesn't exist.
	"""
	location_graph.clear()

	if not FileAccess.file_exists(NEIGHBOR_GRAPH_PATH):
		print("LocationGraphManager: No neighbor graph file found, starting with empty graph")
		return

	var file = FileAccess.open(NEIGHBOR_GRAPH_PATH, FileAccess.READ)
	if file == null:
		push_warning("LocationGraphManager: Could not open neighbor graph file")
		return

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(content)
	if parse_result != OK:
		push_warning("LocationGraphManager: Failed to parse neighbor graph JSON")
		return

	var data = json.data
	if typeof(data) == TYPE_DICTIONARY and data.has("neighbors"):
		location_graph = data["neighbors"].duplicate(true)
		print("LocationGraphManager: Loaded neighbor graph with %d locations" % location_graph.size())
	else:
		print("LocationGraphManager: Invalid neighbor graph format")

func _build_location_graph():
	"""
	DEPRECATED: This function is kept for reference but is no longer used.
	Neighbor relationships are now managed through the Location Editor UI
	and stored in location_graph.json.
	"""
	location_graph.clear()

	# === PONYVILLE REGION ===

	# Main hub - Ponyville Main Square connects to major landmarks
	_add_bidirectional("ponyville_main_square", [
		"ponyville_market",
		"sugarcube_corner",
		"carousel_boutique",
		"ponyville_town_hall",
		"schoolhouse",
		"hay_burger",
		"ponyville_hospital",
		"tea_shop",
		"ponyville_outskirts",
		"train_station"
	])

	# Market area
	_add_bidirectional("ponyville_market", [
		"ponyville_main_square"
	])

	# Sweet Apple Acres area (outside Ponyville proper)
	_add_bidirectional("ponyville_outskirts", [
		"ponyville_main_square",
		"sweet_apple_acres",
		"fluttershy_cottage",
		"lake",
		"cmc_clubhouse",
		"everfree_forest"  # Gateway to Everfree region
	])

	_add_bidirectional("sweet_apple_acres", [
		"ponyville_outskirts",
		"barn",
		"row_of_apple_trees",
		"apple_family_room"
	])

	_add_bidirectional("barn", [
		"sweet_apple_acres"
	])

	_add_bidirectional("row_of_apple_trees", [
		"sweet_apple_acres"
	])

	# Apple Family House interior
	_add_bidirectional("apple_family_room", [
		"sweet_apple_acres",
		"applejack_bedroom",
		"apple_family_farm_bathtub"
	])

	_add_bidirectional("applejack_bedroom", [
		"apple_family_room"
	])

	_add_bidirectional("apple_family_farm_bathtub", [
		"apple_family_room"
	])

	# Fluttershy's Cottage
	_add_bidirectional("fluttershy_cottage", [
		"ponyville_outskirts",
		"fluttershy_cottage_inside"
	])

	_add_bidirectional("fluttershy_cottage_inside", [
		"fluttershy_cottage",
		"fluttershy_bedroom",
		"fluttershy_bathroom"
	])

	_add_bidirectional("fluttershy_bedroom", [
		"fluttershy_cottage_inside"
	])

	_add_bidirectional("fluttershy_bathroom", [
		"fluttershy_cottage_inside"
	])

	# Golden Oak Library (Twilight's home)
	_add_bidirectional("golden_oak_guestroom", [
		"ponyville_main_square",
		"twilight_bedroom",
		"golden_oak_bathtub"
	])

	_add_bidirectional("twilight_bedroom", [
		"golden_oak_guestroom"
	])

	_add_bidirectional("golden_oak_bathtub", [
		"golden_oak_guestroom"
	])

	# Carousel Boutique (Rarity's home/shop)
	_add_bidirectional("carousel_boutique", [
		"ponyville_main_square",
		"rarity_bedroom",
		"rarity_bathroom"
	])

	_add_bidirectional("rarity_bedroom", [
		"carousel_boutique"
	])

	_add_bidirectional("rarity_bathroom", [
		"carousel_boutique"
	])

	# Sugarcube Corner (Pinkie's home/bakery)
	_add_bidirectional("sugarcube_corner", [
		"ponyville_main_square",
		"pinkie_pie_bedroom",
		"pinkie_pie_bathroom"
	])

	_add_bidirectional("pinkie_pie_bedroom", [
		"sugarcube_corner"
	])

	_add_bidirectional("pinkie_pie_bathroom", [
		"sugarcube_corner"
	])

	# Rainbow Dash's Cloudominium
	_add_bidirectional("evening_sky_front_of_cloudominium", [
		"ponyville_main_square",
		"rainbow_dash_living_room"
	])

	_add_bidirectional("rainbow_dash_living_room", [
		"evening_sky_front_of_cloudominium",
		"rainbow_dash_bedroom"
	])

	_add_bidirectional("rainbow_dash_bedroom", [
		"rainbow_dash_living_room"
	])

	# Other Ponyville buildings
	_add_bidirectional("schoolhouse", [
		"ponyville_main_square",
		"schoolhouse_inside"
	])

	_add_bidirectional("schoolhouse_inside", [
		"schoolhouse"
	])

	_add_bidirectional("ponyville_town_hall", [
		"ponyville_main_square"
	])

	_add_bidirectional("hay_burger", [
		"ponyville_main_square"
	])

	_add_bidirectional("ponyville_hospital", [
		"ponyville_main_square"
	])

	_add_bidirectional("tea_shop", [
		"ponyville_main_square"
	])

	# User's house
	_add_bidirectional("user_house", [
		"ponyville_main_square"
	])

	# Trixie's wagon (mobile, but usually near town)
	_add_bidirectional("trixie_wagon", [
		"ponyville_main_square"
	])

	# CMC Clubhouse
	_add_bidirectional("cmc_clubhouse", [
		"ponyville_outskirts",
		"sweet_apple_acres"
	])

	# Lake area
	_add_bidirectional("lake", [
		"ponyville_outskirts"
	])

	# Train Station - gateway to other regions
	_add_bidirectional("train_station", [
		"ponyville_main_square",
		"train"
	])

	_add_bidirectional("train", [
		"train_station",
		"canterlot_train_station"  # Inter-region travel
	])

	# Hot air balloon (special travel)
	_add_bidirectional("hot_air_balloon_flying", [
		"ponyville_main_square",
		"canterlot_plaza"  # Can fly to Canterlot
	])

	# === CANTERLOT REGION ===

	# Canterlot Train Station - arrival point
	_add_bidirectional("canterlot_train_station", [
		"train",
		"canterlot_plaza"
	])

	# Canterlot Plaza - main hub
	_add_bidirectional("canterlot_plaza", [
		"canterlot_train_station",
		"canterlot_cafe",
		"donut_joe_shop",
		"shopping_alley",
		"royal_garden",
		"airship_harbor",
		"canterlot_throne_room"
	])

	_add_bidirectional("canterlot_cafe", [
		"canterlot_plaza"
	])

	_add_bidirectional("donut_joe_shop", [
		"canterlot_plaza"
	])

	_add_bidirectional("shopping_alley", [
		"canterlot_plaza"
	])

	# Royal Castle area
	_add_bidirectional("royal_garden", [
		"canterlot_plaza",
		"canterlot_throne_room"
	])

	_add_bidirectional("canterlot_throne_room", [
		"canterlot_plaza",
		"royal_garden",
		"celestia_bedroom",
		"luna_bedroom"
	])

	_add_bidirectional("celestia_bedroom", [
		"canterlot_throne_room"
	])

	_add_bidirectional("luna_bedroom", [
		"canterlot_throne_room"
	])

	# Airship Harbor
	_add_bidirectional("airship_harbor", [
		"canterlot_plaza",
		"badlands"  # Can fly to Badlands
	])

	# === EVERFREE FOREST REGION ===

	_add_bidirectional("everfree_forest", [
		"ponyville_outskirts",
		"zecora_hut"
	])

	_add_bidirectional("zecora_hut", [
		"everfree_forest"
	])

	# === BADLANDS REGION ===

	_add_bidirectional("badlands", [
		"airship_harbor",
		"changeling_hive"
	])

	_add_bidirectional("changeling_hive", [
		"badlands",
		"changeling_hive_throne_room",
		"changeling_hive_nursery"
	])

	_add_bidirectional("changeling_hive_throne_room", [
		"changeling_hive"
	])

	_add_bidirectional("changeling_hive_nursery", [
		"changeling_hive"
	])

	# === DREAM REALM ===
	# Dream realm is special - accessible from anywhere when sleeping
	# Not adding automatic connections since it's a magical realm
	_add_location("dream_realm", [])

	# Add aliases to match LocationManager aliases
	_add_alias("golden_oak_library", "golden_oak_guestroom")
	_add_alias("library", "golden_oak_guestroom")
	_add_alias("fluttershy_cottage", "fluttershy_cottage_inside")
	_add_alias("main_square", "ponyville_main_square")
	_add_alias("town_square", "ponyville_main_square")

	print("Location graph built with ", location_graph.size(), " locations")

func _add_location(location_id: String, neighbors: Array):
	"""Add a location with its neighbors (one-way)"""
	if not location_graph.has(location_id):
		location_graph[location_id] = []
	for neighbor in neighbors:
		if neighbor not in location_graph[location_id]:
			location_graph[location_id].append(neighbor)

func _add_bidirectional(location_id: String, neighbors: Array):
	"""Add bidirectional connections between a location and its neighbors"""
	_add_location(location_id, neighbors)
	for neighbor in neighbors:
		_add_location(neighbor, [location_id])

func _add_alias(alias: String, target: String):
	"""Add an alias that points to another location's neighbors"""
	if location_graph.has(target):
		location_graph[alias] = location_graph[target]

func get_neighbors(location_id: String) -> Array:
	"""
	Get the list of directly connected neighboring locations.
	Returns empty array if location not found.
	"""
	# First check if this location_id exists in the graph
	if location_graph.has(location_id):
		return location_graph[location_id]

	# If not found, it might be an alias - try common aliases
	var alias_mappings = {
		"golden_oak_library": "golden_oak_guestroom",
		"library": "golden_oak_guestroom",
		"fluttershy_cottage": "fluttershy_cottage_inside",
		"main_square": "ponyville_main_square",
		"town_square": "ponyville_main_square"
	}

	if alias_mappings.has(location_id):
		var real_id = alias_mappings[location_id]
		return location_graph.get(real_id, [])

	return []

func find_path(start_id: String, end_id: String) -> Array:
	"""
	Find the shortest path between two locations using BFS.
	Returns an array of location_ids representing the path from start to end.
	Returns empty array if no path exists.

	Example:
		find_path("apple_family_farm_bathtub", "canterlot_throne_room")
		Returns: ["apple_family_farm_bathtub", "apple_family_room", "sweet_apple_acres",
		          "ponyville_outskirts", "ponyville_main_square", "train_station",
		          "train", "canterlot_train_station", "canterlot_plaza", "canterlot_throne_room"]
	"""
	if start_id == end_id:
		return [start_id]

	if not location_graph.has(start_id) or not location_graph.has(end_id):
		return []

	# BFS to find shortest path
	var queue = [[start_id]]  # Queue of paths
	var visited = {start_id: true}

	while queue.size() > 0:
		var path = queue.pop_front()
		var current = path[-1]

		# Check all neighbors
		var neighbors = get_neighbors(current)
		for neighbor in neighbors:
			if neighbor == end_id:
				# Found the destination!
				path.append(neighbor)
				return path

			if not visited.has(neighbor):
				visited[neighbor] = true
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)

	# No path found
	return []

func get_next_location(start_id: String, destination_id: String) -> String:
	"""
	Get the next location to travel to on the path from start to destination.
	Returns empty string if no path exists or if already at destination.

	Example:
		get_next_location("apple_family_farm_bathtub", "canterlot_throne_room")
		Returns: "apple_family_room" (the next step in the journey)
	"""
	var path = find_path(start_id, destination_id)
	if path.size() <= 1:
		return ""
	return path[1]  # Return the second element (first step after start)

func get_neighbors_with_names(location_id: String, location_manager) -> Array:
	"""
	Get neighbors with their display names for LLM context.
	Returns array of dictionaries with 'id' and 'name' keys.
	Requires LocationManager reference to look up names.

	Example return:
		[
			{"id": "sweet_apple_acres", "name": "Sweet Apple Acres"},
			{"id": "applejack_bedroom", "name": "Applejack Bedroom"}
		]
	"""
	var neighbors = get_neighbors(location_id)
	var result = []
	for neighbor_id in neighbors:
		var loc_data = location_manager.get_location(neighbor_id)
		if loc_data:
			result.append({
				"id": neighbor_id,
				"name": loc_data.name
			})
		else:
			result.append({
				"id": neighbor_id,
				"name": neighbor_id.replace("_", " ").capitalize()
			})
	return result

func format_neighbors_for_llm(location_id: String, location_manager) -> String:
	"""
	Format the list of neighboring locations as a string for LLM prompts.

	Example output:
		"From here you can travel to: Sweet Apple Acres, Applejack Bedroom, Apple Family Farm Bathtub"
	"""
	var neighbors = get_neighbors_with_names(location_id, location_manager)
	if neighbors.size() == 0:
		return "This location has no direct exits."

	var names = []
	for neighbor in neighbors:
		names.append(neighbor["name"])

	return "From here you can travel to: " + ", ".join(names)

func format_path_for_llm(start_id: String, destination_id: String, location_manager) -> String:
	"""
	Format a path description for the LLM.

	Example output:
		"To reach Canterlot Throne Room from Apple Family Farm Bathtub, travel through:
		 Apple Family Room -> Sweet Apple Acres -> Ponyville Outskirts -> ..."
	"""
	var path = find_path(start_id, destination_id)
	if path.size() == 0:
		return "No path found between these locations."

	if path.size() == 1:
		return "Already at the destination."

	var start_loc = location_manager.get_location(start_id)
	var end_loc = location_manager.get_location(destination_id)

	var start_name = start_loc.name if start_loc else start_id
	var end_name = end_loc.name if end_loc else destination_id

	var path_names = []
	for loc_id in path:
		var loc = location_manager.get_location(loc_id)
		path_names.append(loc.name if loc else loc_id)

	return "To reach %s from %s, travel through:\n%s" % [
		end_name,
		start_name,
		" -> ".join(path_names)
	]

func is_neighbor(location_id: String, potential_neighbor: String) -> bool:
	"""Check if two locations are directly connected"""
	return potential_neighbor in get_neighbors(location_id)

func get_all_reachable_locations(start_id: String) -> Array:
	"""
	Get all locations reachable from a starting location.
	Useful for determining what's accessible in a region.
	"""
	if not location_graph.has(start_id):
		return []

	var reachable = []
	var visited = {}
	var queue = [start_id]
	visited[start_id] = true

	while queue.size() > 0:
		var current = queue.pop_front()
		reachable.append(current)

		for neighbor in get_neighbors(current):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	return reachable
