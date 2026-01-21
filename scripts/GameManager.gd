extends Node

signal scene_started
signal scene_ended

var current_characters = []
var daily_visits_count = 0
var max_daily_visits = 2

# References to other managers (injected from Main)
var stats_manager
var location_manager
var location_graph_manager
var character_manager
var llm_client
var sprite_manager
var relationship_manager
var settings_manager
var schedule_manager

func _ready():
	pass

func start_visit(location_id, characters):
	print("Starting visit to: ", location_id)
	current_characters = characters
	
	# Update location
	location_manager.set_location(location_id)
	stats_manager.update_stat("location", location_manager.get_location(location_id).name)
	
	# Generate Prompt
	var prompt = _create_sandbox_prompt(characters, location_manager.get_location(location_id))
	
	# Send to LLM
	emit_signal("scene_started")
	llm_client.send_request(prompt, "Start the scene.")

func _create_sandbox_prompt(characters, location):
	var char_names = ""
	for c in characters:
		if char_names != "":
			char_names += " and "
		char_names += c.name

	var time_info = stats_manager.get_stats_string()

	var prompt = "You are generating a short, self-contained scene for a My Little Pony visual novel.\n"
	prompt += "The player is visiting " + char_names + " at " + location.name + ".\n"
	prompt += "Location Description: " + location.description + "\n"
	prompt += "Current Game Stats: " + time_info + "\n"
	if relationship_manager:
		prompt += _build_relationship_context(characters)
		prompt += "Use these relationship levels to adjust greetings, tone, and stakes. Negative numbers mean they distrust or dislike the player; positive numbers mean warmth or affection.\n"

	if settings_manager:
		var persona_lines: Array[String] = settings_manager.get_active_persona_context_lines()
		if persona_lines.size() > 0:
			prompt += "\nPlayer Persona:\n"
			for line in persona_lines:
				prompt += "- " + line + "\n"
			prompt += "Reflect these traits whenever narration references the player.\n"

	# Add neighboring locations context
	if location_graph_manager:
		print("DEBUG GameManager: Building location context for: ", location_manager.current_location_id)
		var neighbors = location_graph_manager.get_neighbors_with_names(location_manager.current_location_id, location_manager)
		print("DEBUG GameManager: Found %d neighbors" % neighbors.size())
		if neighbors.size() > 0:
			prompt += "\nAvailable Nearby Locations:\n"
			for neighbor in neighbors:
				prompt += "- " + neighbor["name"] + " (use [location: " + neighbor["id"] + "])\n"
				print("DEBUG GameManager: Neighbor: %s (%s)" % [neighbor["name"], neighbor["id"]])
			prompt += "\nIMPORTANT: You can change locations during the scene by placing [location: location_id] AFTER the narration or dialogue that describes moving there.\n"
			prompt += "Example flow:\n"
			prompt += "Twilight gestures toward the door.\n"
			prompt += 'twi "Let\'s head downstairs to the main library."\n'
			prompt += "You follow her down the wooden staircase.\n"
			prompt += "[location: ponyville_main_square]\n"
			prompt += "The afternoon sun warms the town square.\n"
		else:
			print("DEBUG GameManager: No neighbors found for: ", location_manager.current_location_id)
	else:
		print("DEBUG GameManager: location_graph_manager is null!")

	prompt += "\nCreate a cute, interesting scene. \n"
	prompt += "Format rules:\n"
	prompt += "Narration: write plain lines with no character tag\n"
	for c in characters:
		prompt += c.tag + " \"...\"\n"
		prompt += "- Sprites: [sprite: " + c.tag + " emotion]\n"

	prompt += "Do NOT include dialogue for the player ('p'). Focus on the NPCs.\n"
	prompt += "End the scene naturally."

	return prompt

func _build_relationship_context(characters: Array) -> String:
	var lines = "Character Relationship Context:\n"
	for c in characters:
		var rel_value = relationship_manager.get_relationship_value(c.tag)
		var descriptor = relationship_manager.get_relationship_descriptor(rel_value)
		lines += "- %s (%s): %.1f — %s\n" % [c.name, c.tag, rel_value, descriptor]
		var history = relationship_manager.get_recent_dialogue_summary(c.tag)
		if history != "":
			lines += "  Recent memories: " + history + "\n"
	return lines

func advance_time():
	stats_manager.advance_time()
	# Logic for day cycle
	if stats_manager.stats["time_slot"] == stats_manager.MORNING:
		daily_visits_count = 0
		print("New Day Started")
	else:
		daily_visits_count += 1
