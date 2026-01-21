extends Control

signal sprite_clicked(tag: String)

# Container for sprite nodes
var sprite_container: Control

# Map tag -> TextureRect
var active_sprites: Dictionary = {}

# 3-lane layout: foreground anchors at 25/50/75 with a staggered back row for crowd staging
const SLOT_POSITIONS: Dictionary = {
	"front_left": 0.25,
	"front_center": 0.50,
	"front_right": 0.75,
	"back_left": 0.18,
	"back_center": 0.50,
	"back_right": 0.82
}

const SLOT_VERTICAL_OFFSETS: Dictionary = {
	"front_left": 0.0,
	"front_center": 0.0,
	"front_right": 0.0,
	"back_left": -40.0,
	"back_center": -55.0,
	"back_right": -40.0
}

const SLOT_DEPTH_BIAS: Dictionary = {
	"front_left": 3,
	"front_center": 3,
	"front_right": 3,
	"back_left": -3,
	"back_center": -3,
	"back_right": -3
}

const SLOT_ORDER: Array[String] = [
	"front_left",
	"front_center",
	"front_right",
	"back_left",
	"back_center",
	"back_right"
]

var slot_assignments: Dictionary = {
	"front_left": "",
	"front_center": "",
	"front_right": "",
	"back_left": "",
	"back_center": "",
	"back_right": ""
}

var character_slots: Dictionary = {}

# Track speaking order for z-index layering
var speaking_order: Array[String] = []  # Most recent speaker at end
var last_clicked_tag: String = "" # Tag of the last clicked sprite for pass-through logic
var base_z_index: int = -100  # Negative to stay behind UI elements

# Group clustering settings (legacy, may be removed)
const GROUP_CLUSTER_OFFSET: float = 40.0
var group_cluster_offsets: Dictionary = {}
var current_group_map: Dictionary = {}  # tag -> group_id

# Hybrid row scaling system
# Multi-row scaling system
# Dynamic capacity: 3 for front row, 4 for others
const ROW_SCALE_FACTOR: float = 0.85  # Scale reduces by this factor for each row back
const ROW_Y_OFFSET_STEP: float = -120.0  # Pixels up for each row back
var sprite_scales: Dictionary = {}  # tag -> scale factor
var sprite_rows: Dictionary = {}  # tag -> row index (0=front, 1=back1, 2=back2, etc)
var sprite_x_positions: Dictionary = {}  # tag -> x position ratio (0.0-1.0)
var sprite_names: Dictionary = {}  # tag -> current sprite/emotion name (e.g., "laughing")

# User-defined sprite sizes from editor
const SPRITE_SIZE_FILE_PATH := "res://assets/Schedules/sprite_sizes.json"
const GLOBAL_BASE_SIZE_KEY := "_global_base_size"
var user_sprite_scales: Dictionary = {}  # tag -> user-defined base scale
var global_base_sprite_size: float = 1.0  # Global multiplier for all sprites

# Per-sprite overrides: {tag: {sprite_name: {"scale": float, "clip_left": float, "clip_right": float}}}
var per_sprite_overrides: Dictionary = {}

# Cache for sprite content bounds (non-transparent area)
# "tag_spritename" -> {"left": float, "right": float} as ratios 0.0-1.0
var sprite_content_bounds: Dictionary = {}

func _ready() -> void:
	sprite_container = Control.new()
	sprite_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ensure sprites are behind the UI (dialogue box) but in front of background
	# We'll assume this node is placed correctly in the scene tree
	add_child(sprite_container)
	# Load user-defined sprite sizes
	_load_user_sprite_scales()

func _load_user_sprite_scales() -> void:
	user_sprite_scales.clear()
	per_sprite_overrides.clear()
	global_base_sprite_size = 1.0
	if not FileAccess.file_exists(SPRITE_SIZE_FILE_PATH):
		return
	var file := FileAccess.open(SPRITE_SIZE_FILE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Failed to parse sprite sizes: %s" % json.get_error_message())
		return
	var data = json.get_data()
	if typeof(data) == TYPE_DICTIONARY:
		# Extract global base size if present
		if data.has(GLOBAL_BASE_SIZE_KEY):
			global_base_sprite_size = clampf(float(data[GLOBAL_BASE_SIZE_KEY]), 0.1, 2.0)
			print("SpriteManager: Global base sprite size set to %.2f" % global_base_sprite_size)
		for key in data.keys():
			if key == GLOBAL_BASE_SIZE_KEY:
				continue
			var value = data[key]
			# New format: {"scale": 1.5, "sprites": {"laughing": {"scale": 1.2, "clip_left": 0.1, "clip_right": 0.9}}}
			if typeof(value) == TYPE_DICTIONARY:
				user_sprite_scales[key] = float(value.get("scale", 1.0))
				if value.has("sprites") and typeof(value["sprites"]) == TYPE_DICTIONARY:
					per_sprite_overrides[key] = value["sprites"]
			else:
				# Old format: simple float
				user_sprite_scales[key] = float(value)
		print("SpriteManager: Loaded %d user sprite scales, %d with per-sprite overrides (global base: %.2f)" % [user_sprite_scales.size(), per_sprite_overrides.size(), global_base_sprite_size])

## Reload user sprite scales from file (call after changing sizes in editor)
func reload_sprite_scales() -> void:
	_load_user_sprite_scales()
	# Re-apply scales to active sprites
	# Re-apply scales to active sprites
	for tag in active_sprites.keys():
		if sprite_rows.has(tag):
			var row_idx: int = sprite_rows[tag]
			var user_scale: float = user_sprite_scales.get(tag, 1.0)
			
			var row_scale_mult: float = pow(ROW_SCALE_FACTOR, row_idx)
			sprite_scales[tag] = global_base_sprite_size * user_scale * row_scale_mult
	update_layout()

## Get the user-defined scale for a character (1.0 if not set)
func get_user_sprite_scale(tag: String) -> float:
	return user_sprite_scales.get(tag, 1.0)

## Get the global base sprite size (1.0 if not set)
func get_global_base_sprite_size() -> float:
	return global_base_sprite_size

func show_sprite(tag: String, emotion: String, character_manager: CharacterManager) -> bool:
	var char_config: CharacterManager.CharacterConfig = character_manager.get_character(tag)
	if not char_config:
		print("Error: Character not found: ", tag)
		return false

	# Store the sprite name for per-sprite overrides
	sprite_names[tag] = emotion

	# Only use old slot system if we don't have a pre-assigned position
	if not sprite_x_positions.has(tag):
		if not _ensure_slot_for_character(tag):
			print("SpriteManager: No available slot for ", tag)
			return false
		
		# Sync slot assignment to new system properties
		var slot: String = character_slots[tag]
		sprite_x_positions[tag] = SLOT_POSITIONS.get(slot, 0.5)
		
		var row_idx: int = 0
		if slot.begins_with("back"):
			row_idx = 1
		sprite_rows[tag] = row_idx
	
	# Calculate scale - check for per-sprite override first
	var row_idx: int = sprite_rows.get(tag, 0)
	var row_scale_mult: float = pow(ROW_SCALE_FACTOR, row_idx)
	var per_sprite_scale = get_per_sprite_scale(tag, emotion)
	
	if per_sprite_scale != null:
		# Per-sprite scale overrides global base size
		sprite_scales[tag] = float(per_sprite_scale) * row_scale_mult
	else:
		# Use character scale with global base
		var user_scale: float = get_user_sprite_scale(tag)
		sprite_scales[tag] = global_base_sprite_size * user_scale * row_scale_mult

	# Construct path
	# Try png, then webp, etc.
	var path: String = char_config.folder_path + emotion + ".png"
	if not FileAccess.file_exists(path):
		# Try fallback extensions or emotions
		path = char_config.folder_path + emotion + ".webp"
		if not FileAccess.file_exists(path):
			print("Error: Sprite not found: ", path)
			return false

	var texture: Texture2D = load_external_texture(path)
	if not texture:
		print("Error: Failed to load texture: ", path)
		return false

	var is_new_character: bool = not active_sprites.has(tag)
	var sprite_node: TextureRect
	if active_sprites.has(tag):
		sprite_node = active_sprites[tag]
	else:
		sprite_node = TextureRect.new()
		# Use EXPAND_IGNORE_SIZE to allow manual scaling
		sprite_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite_node.mouse_filter = Control.MOUSE_FILTER_STOP
		sprite_node.gui_input.connect(_on_sprite_gui_input.bind(tag))
		sprite_container.add_child(sprite_node)
		active_sprites[tag] = sprite_node
	
	sprite_node.texture = texture

	# Don't set anchors preset - we'll position manually
	if is_new_character:
		update_layout()
	else:
		# Just update this sprite's geometry/flip without moving others
		_update_single_sprite_geometry(tag)

	# Bring this character to front (they're speaking)
	bring_to_front(tag)
	return true

func hide_sprite(tag: String, release_slot: bool = false) -> void:
	if active_sprites.has(tag):
		var node: TextureRect = active_sprites[tag]
		node.queue_free()
		active_sprites.erase(tag)

	# Remove from speaking order
	if tag in speaking_order:
		speaking_order.erase(tag)

	if release_slot:
		_release_slot(tag)
	update_layout()

func update_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	
	# Group sprite info by row index
	var rows_info: Dictionary = {}  # row_index (int) -> Array[Dictionary]
	
	for tag in active_sprites.keys():
		if not active_sprites.has(tag):
			continue
		var node: TextureRect = active_sprites[tag]
		var texture: Texture2D = node.texture
		if texture == null:
			continue
		
		var scale: float = sprite_scales.get(tag, 1.0)
		var row_idx: int = sprite_rows.get(tag, 0)
		var x_ratio: float = sprite_x_positions.get(tag, 0.5)
		
		var tex_width: float = float(texture.get_width()) * scale
		var tex_height: float = float(texture.get_height()) * scale
		
		# Get content bounds (pass sprite name for per-sprite overrides)
		var current_sprite_name: String = sprite_names.get(tag, "")
		var content_bounds: Dictionary = get_sprite_content_bounds(tag, texture, current_sprite_name)
		var left_content: float = content_bounds.get("left", 0.0)
		var right_content: float = content_bounds.get("right", 1.0)
		
		var info: Dictionary = {
			"tag": tag,
			"node": node,
			"texture": texture,
			"scale": scale,
			"row_idx": row_idx,
			"x_ratio": x_ratio,
			"tex_width": tex_width,
			"tex_height": tex_height,
			"left_content": left_content,
			"right_content": right_content,
			"final_x": 0.0  # Will be set later
		}
		
		if not rows_info.has(row_idx):
			var new_list: Array[Dictionary] = []
			rows_info[row_idx] = new_list
		rows_info[row_idx].append(info)
	
	# Process each row
	var all_info: Array[Dictionary] = []
	
	for row_idx in rows_info.keys():
		var row_list: Array[Dictionary] = rows_info[row_idx]
		# Sort by x_ratio (left to right)
		row_list.sort_custom(func(a, b): return a["x_ratio"] < b["x_ratio"])
		
		# Process row - spread characters evenly
		var positions: Array[float] = _calculate_spread_positions(row_list, viewport_size.x)
		
		for i in range(row_list.size()):
			row_list[i]["final_x"] = positions[i]
		
		all_info.append_array(row_list)
	
	# Apply final positions
	for info in all_info:
		var x_pos: float = info["final_x"]
		var tex_width: float = info["tex_width"]
		var tex_height: float = info["tex_height"]
		var row_idx: int = info["row_idx"]
		
		# Apply group clustering offset if present
		var cluster_offset: float = group_cluster_offsets.get(info["tag"], 0.0)
		x_pos += cluster_offset * info["scale"]
		
		# Clamp with relaxed constraints
		var min_x: float = -tex_width * 0.50
		var max_x: float = viewport_size.x - tex_width * 0.50
		x_pos = clampf(x_pos, min_x, max_x)
		
		# Y position: apply offset based on row index
		var y_offset: float = float(row_idx) * ROW_Y_OFFSET_STEP
		var y_pos: float = viewport_size.y - tex_height + y_offset
		info["node"].position = Vector2(x_pos, y_pos)
		
		# Reset orientation
		info["node"].flip_h = false
		
		# Check if this is the rightmost character in its row
		var is_rightmost: bool = false
		var row_list: Array = rows_info[row_idx]
		if not row_list.is_empty() and row_list.back()["tag"] == info["tag"]:
			is_rightmost = true
			
		# Flip if needed
		if is_rightmost:
			var visual_right = x_pos + (tex_width * info["right_content"])
			if visual_right > viewport_size.x:
				info["node"].flip_h = true
		
		# Update node size
		info["node"].custom_minimum_size = Vector2(tex_width, tex_height)
		info["node"].size = Vector2(tex_width, tex_height)
	
	_update_z_indices()

## Calculate evenly distributed positions using content-aware spacing
## Maximizes spread while preventing visual overlap
func _calculate_spread_positions(row_info: Array[Dictionary], viewport_width: float) -> Array[float]:
	var positions: Array[float] = []
	if row_info.is_empty():
		return positions
	
	var count: int = row_info.size()
	positions.resize(count)
	
	# Single character: Center visually
	if count == 1:
		var info = row_info[0]
		var w = info["tex_width"]
		var v_left = w * info["left_content"]
		var v_right = w * info["right_content"]
		var v_width = v_right - v_left
		
		# Position so visual center aligns with screen center
		# Sprite X + v_left + v_width/2 = Screen/2
		positions[0] = (viewport_width / 2.0) - v_left - (v_width / 2.0)
		return positions
	
	# Multiple: Distribute to fill available space
	# 1. Calculate visual metrics
	var visuals: Array[Dictionary] = []
	var total_visual_width: float = 0.0
	
	for info in row_info:
		var w = info["tex_width"]
		var v_left = w * info["left_content"]
		var v_right = w * info["right_content"]
		var v_width = v_right - v_left
		
		visuals.append({
			"v_left": v_left,
			"v_width": v_width
		})
		total_visual_width += v_width
	
	# 2. Determine available width and gap
	# Use smaller margin (2%) to maximize space
	var margin: float = viewport_width * 0.02
	var usable_width: float = viewport_width - (margin * 2.0)
	
	# Calculate gap needed to fill the usable width
	# total_visual + (count-1) * gap = usable_width
	var gap: float = (usable_width - total_visual_width) / float(count - 1)
	
	# Enforce constraints on gap
	# Minimum gap: Limit overlap. e.g. -20px overlap allowed at most
	# If characters are huge, gap calculation might return -200. We clamp it to -20
	# This forces the group to be wider than the screen, but preserves legibility
	var min_gap: float = -20.0
	if gap < min_gap:
		gap = min_gap
	
	# Maximum gap: Don't spread too far if characters are small
	var max_gap: float = viewport_width * 0.25
	if gap > max_gap:
		gap = max_gap
	
	# Re-calculate total width with the finalized gap
	var final_group_width: float = total_visual_width + (float(count - 1) * gap)
	var start_visual_x: float = (viewport_width - final_group_width) / 2.0
	
	# 3. Assign positions
	var current_visual_x: float = start_visual_x
	for i in range(count):
		# Position such that visual left edge is at current_visual_x
		positions[i] = current_visual_x - visuals[i]["v_left"]
		
		# Advance by visual width + gap
		current_visual_x += visuals[i]["v_width"] + gap
		
	return positions

func load_external_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null

	# Use ResourceLoader for proper import handling (works in export)
	var texture: Texture2D = ResourceLoader.load(path, "Texture2D")
	if texture:
		return texture

	# Fallback to Image.load_from_file for runtime-only scenarios
	# Note: This won't work in exported builds
	var img: Image = Image.load_from_file(path)
	if img:
		return ImageTexture.create_from_image(img)
	return null

## Calculate the non-transparent content bounds of a texture
## Returns {"left": ratio, "right": ratio} where ratios are 0.0-1.0 relative to texture width
## Checks for custom clip overrides first, then falls back to auto-detection
## Caches results by tag+sprite_name for performance
func get_sprite_content_bounds(tag: String, texture: Texture2D, sprite_name: String = "") -> Dictionary:
	# Check for custom clip override first
	if sprite_name != "" and per_sprite_overrides.has(tag):
		var sprite_overrides: Dictionary = per_sprite_overrides[tag]
		if sprite_overrides.has(sprite_name):
			var override: Dictionary = sprite_overrides[sprite_name]
			if override.has("clip_left") or override.has("clip_right"):
				var custom_bounds: Dictionary = {
					"left": float(override.get("clip_left", 0.0)),
					"right": float(override.get("clip_right", 1.0))
				}
				print("SpriteManager: Using custom clip for %s/%s: left=%.2f right=%.2f" % [tag, sprite_name, custom_bounds["left"], custom_bounds["right"]])
				return custom_bounds
	
	# Use composite cache key for per-sprite caching
	var cache_key: String = tag if sprite_name == "" else "%s_%s" % [tag, sprite_name]
	
	# Return cached bounds if available
	if sprite_content_bounds.has(cache_key):
		return sprite_content_bounds[cache_key]
	
	# Default bounds (full texture)
	var bounds: Dictionary = {"left": 0.0, "right": 1.0}
	
	if texture == null:
		return bounds
	
	# Get image data from texture
	var image: Image = texture.get_image()
	if image == null:
		return bounds
	
	var width: int = image.get_width()
	var height: int = image.get_height()
	
	if width == 0 or height == 0:
		return bounds
	
	# Find leftmost non-transparent column (sample every 4th row for speed)
	var left_col: int = width
	for x in range(width):
		var found_content: bool = false
		for y in range(0, height, 4):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.1:  # Alpha threshold
				found_content = true
				break
		if found_content:
			left_col = x
			break
	
	# Find rightmost non-transparent column
	var right_col: int = 0
	for x in range(width - 1, -1, -1):
		var found_content: bool = false
		for y in range(0, height, 4):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.1:
				found_content = true
				break
		if found_content:
			right_col = x
			break
	
	# Convert to ratios
	bounds["left"] = float(left_col) / float(width)
	bounds["right"] = float(right_col + 1) / float(width)
	
	# Cache the result
	sprite_content_bounds[cache_key] = bounds
	print("SpriteManager: Content bounds for %s: left=%.2f right=%.2f (visual width=%.0f%%)" % [cache_key, bounds["left"], bounds["right"], (bounds["right"] - bounds["left"]) * 100])
	
	return bounds

## Get per-sprite scale override if set, otherwise returns null
func get_per_sprite_scale(tag: String, sprite_name: String) -> Variant:
	if per_sprite_overrides.has(tag):
		var sprite_overrides: Dictionary = per_sprite_overrides[tag]
		if sprite_overrides.has(sprite_name) and sprite_overrides[sprite_name].has("scale"):
			return float(sprite_overrides[sprite_name]["scale"])
	return null

func enter_character(tag: String, character_manager_ref: CharacterManager = null) -> bool:
	if active_sprites.has(tag):
		return true

	# Construct a list of current + new characters to run full layout pass
	var assignments: Array = []
	for t in active_sprites.keys():
		assignments.append({"tag": t, "group_id": current_group_map.get(t, "")})
	
	# Add new character (solo by default)
	assignments.append({"tag": tag, "group_id": ""})
	
	display_grouped_assignments(assignments, character_manager_ref)
	return true

func step_aside(tag: String) -> void:
	hide_sprite(tag, true)

func exit_character(tag: String) -> void:
	hide_sprite(tag, true)

func clear_all_sprites() -> void:
	for tag in active_sprites.keys():
		var node: TextureRect = active_sprites[tag]
		node.queue_free()
	active_sprites.clear()
	for slot in slot_assignments.keys():
		slot_assignments[slot] = ""
	character_slots.clear()
	speaking_order.clear()
	last_clicked_tag = ""
	sprite_scales.clear()
	sprite_rows.clear()
	sprite_x_positions.clear()
	sprite_names.clear()
	group_cluster_offsets.clear()
	current_group_map.clear()

func _ensure_slot_for_character(tag: String) -> bool:
	if character_slots.has(tag):
		return true

	var empty_slots: Array[String] = []
	for slot in SLOT_ORDER:
		if slot_assignments[slot] == "":
			empty_slots.append(slot)
	if empty_slots.is_empty():
		return false

	# Always prioritize front-row slots before filling the back row
	var front_candidate: String = ""
	for slot in empty_slots:
		if slot.begins_with("front_"):
			front_candidate = slot
			break

	var chosen: String = front_candidate if front_candidate != "" else empty_slots[0]
	slot_assignments[chosen] = tag
	character_slots[tag] = chosen
	return true

func _release_slot(tag: String) -> void:
	if not character_slots.has(tag):
		return
	var slot: String = character_slots[tag]
	character_slots.erase(tag)
	if slot_assignments.has(slot):
		slot_assignments[slot] = ""

## Mark a character as speaking (brings them to front)
func bring_to_front(tag: String) -> void:
	if not active_sprites.has(tag):
		return

	# Remove from current position in speaking order
	if tag in speaking_order:
		speaking_order.erase(tag)

	# Add to end (most recent speaker)
	speaking_order.append(tag)

	# Update z-indices for all sprites
	_update_z_indices()

## Update z-indices based on x-position (left characters in front of right)
## Since all ponies face right, left characters need higher z-index so their faces
## are visible above the tails of characters to their right
## The most recent speaker gets priority and appears on top of their row
func _update_z_indices() -> void:
	# Determine who the current speaker is
	var current_speaker: String = ""
	if speaking_order.size() > 0:
		current_speaker = speaking_order[speaking_order.size() - 1]
	
	# Group characters by row
	var rows_chars: Dictionary = {} # row_idx -> Array[String]
	
	for tag in active_sprites.keys():
		var row_idx: int = sprite_rows.get(tag, 0)
		if not rows_chars.has(row_idx):
			rows_chars[row_idx] = []
		rows_chars[row_idx].append(tag)
	
	# Process each row
	for row_idx in rows_chars.keys():
		var char_list: Array = rows_chars[row_idx]
		# Sort by right-to-left
		char_list.sort_custom(_compare_by_x_position_descending)
		
		# Assign z-indices
		# Base z-index for row 0 is -50
		# Base z-index for row 1 is -100
		# Base z-index for row K is -50 - (K * 50)
		var base_z: int = -50 - (row_idx * 50)
		
		for i in range(char_list.size()):
			var tag: String = char_list[i]
			if active_sprites.has(tag):
				var sprite_node: TextureRect = active_sprites[tag]
				
				# Normal z-index logic
				sprite_node.z_index = base_z + (i * 2)
				
				# If this is the current speaker, force them to the front!
				# Override row depth logic to ensure visibility
				if tag == current_speaker:
					sprite_node.z_index = -5 # Just behind UI (0), but ahead of all rows (-50+)

## Update geometry for a single sprite without affecting global layout
## Used when changing emotions to prevent jarring movement of other characters
func _update_single_sprite_geometry(tag: String) -> void:
	if not active_sprites.has(tag):
		return
		
	var node: TextureRect = active_sprites[tag]
	var texture: Texture2D = node.texture
	if texture == null:
		return
		
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = sprite_scales.get(tag, 1.0)
	var row_idx: int = sprite_rows.get(tag, 0)
	
	var tex_width: float = float(texture.get_width()) * scale
	var tex_height: float = float(texture.get_height()) * scale
	
	# Update size
	node.custom_minimum_size = Vector2(tex_width, tex_height)
	node.size = Vector2(tex_width, tex_height)
	
	# Update Y position (X stays same)
	var y_offset: float = float(row_idx) * ROW_Y_OFFSET_STEP
	var y_pos: float = viewport_size.y - tex_height + y_offset
	node.position.y = y_pos
	
	# Check flip logic
	# We need to check if we are the rightmost in our row
	var my_x_ratio: float = sprite_x_positions.get(tag, 0.5)
	var is_rightmost: bool = true
	
	for other_tag in active_sprites.keys():
		if other_tag == tag: continue
		if sprite_rows.get(other_tag, -1) == row_idx:
			var other_x: float = sprite_x_positions.get(other_tag, 0.5)
			if other_x > my_x_ratio:
				is_rightmost = false
				break
	
	node.flip_h = false
	if is_rightmost:
		var current_sprite_name: String = sprite_names.get(tag, "")
		var content_bounds = get_sprite_content_bounds(tag, texture, current_sprite_name)
		var visual_right = node.position.x + (tex_width * content_bounds.get("right", 1.0))
		if visual_right > viewport_size.x:
			node.flip_h = true

## Compare function for sorting by x-position (descending - rightmost first)
func _compare_by_x_position_descending(a: String, b: String) -> bool:
	var x_a: float = sprite_x_positions.get(a, 0.5)
	var x_b: float = sprite_x_positions.get(b, 0.5)
	return x_a > x_b  # Higher x-position first (rightmost)

func _on_sprite_gui_input(event: InputEvent, tag: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var global_pos = mouse_event.global_position
			
			# Check for overlapping sprites using manual Z-sort to ensure correct front-to-back logic
			var candidates = _get_sprites_at_position(global_pos)
			
			var selected_tag = tag
			
			if not candidates.is_empty():
				# Default to the absolute front-most sprite visually
				selected_tag = candidates[0]
				
				# If we clicked the same stack/character again, cycle through candidates
				if last_clicked_tag in candidates:
					var current_idx = candidates.find(last_clicked_tag)
					var next_index = (current_idx + 1) % candidates.size()
					selected_tag = candidates[next_index]
					print("SpriteManager: Cycling overlap %d -> %d (%s -> %s)" % [current_idx, next_index, last_clicked_tag, selected_tag])
			
			last_clicked_tag = selected_tag
			sprite_clicked.emit(selected_tag)
			bring_to_front(selected_tag)
			get_viewport().set_input_as_handled()

## Get all sprites under the given global position, sorted by Z-index (descending)
func _get_sprites_at_position(global_pos: Vector2) -> Array[String]:
	var hit_list: Array[Dictionary] = []
	
	for t in active_sprites.keys():
		var node: TextureRect = active_sprites[t]
		if not node.visible:
			continue
			
		if node.get_global_rect().has_point(global_pos):
			hit_list.append({
				"tag": t,
				"z": node.z_index
			})
	
	# Sort by Z-index descending (front to back)
	hit_list.sort_custom(func(a, b): return a["z"] > b["z"])
	
	var result: Array[String] = []
	for hit in hit_list:
		result.append(hit["tag"])
	
	return result

## Get current grouping state (used by TravelManager)
## Returns { "grouped_chars": Array[String], "group_map": Dictionary }
func get_current_group_state() -> Dictionary:
	var grouped_chars: Array[String] = []
	var active_group_map: Dictionary = current_group_map.duplicate()
	
	for char_tag in active_group_map.keys():
		if active_group_map[char_tag] != "":
			grouped_chars.append(char_tag)
			
	return {
		"grouped_chars": grouped_chars,
		"group_map": active_group_map
	}

## Display characters with group-aware positioning and hybrid scaling
## Front row: up to 3 characters at 100% scale
## Back row: overflow at 70% scale, evenly distributed
func display_grouped_assignments(assignments: Array, character_manager: CharacterManager) -> void:
	# Clear existing state
	clear_all_sprites()
	group_cluster_offsets.clear()
	current_group_map.clear()
	sprite_scales.clear()
	sprite_rows.clear()
	
	if assignments.is_empty():
		return
	
	# Build group map and collect all tags
	var groups: Dictionary = {}  # group_id -> [tags]
	var solo_tags: Array[String] = []
	var all_tags: Array[String] = []
	
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		if tag == "":
			continue
		all_tags.append(tag)
		var group_id: String = str(entry.get("group_id", ""))
		current_group_map[tag] = group_id
		
		if group_id == "":
			solo_tags.append(tag)
		else:
			if not groups.has(group_id):
				groups[group_id] = []
			groups[group_id].append(tag)
	
	var total_chars: int = all_tags.size()
	if total_chars == 0:
		return
	
	# -------------------------------------------------------------------------
	# NOTE: Shuffling disabled to keep stable positions when adding new characters
	# The user can still control order by passing assignments in desired order
	# -------------------------------------------------------------------------
	# var rng := RandomNumberGenerator.new()
	# rng.randomize()
	# ... shuffling code removed ...
	
	# Distribute characters into rows
	var rows_tags: Dictionary = {}  # row_idx -> Array[String] of tags
	
	# Order: Groups first, then solos (as constructed in ordered_tags)
	var ordered_tags: Array[String] = []
	
	# Add grouped characters first
	for group_id in groups.keys():
		var group_tags: Array = groups[group_id]
		for t in group_tags:
			ordered_tags.append(str(t))
	
	# Then add solo characters
	for tag in solo_tags:
		ordered_tags.append(tag)
	
	# Assign specific rows based on dynamic capacity/visual width
	# Row 0: Max 3 chars
	# Row 1+: Fill until screen width is reached (considering overlap)
	var current_tag_idx: int = 0
	var current_row_idx: int = 0
	var current_row_width: float = 0.0
	var current_row_count: int = 0
	
	var viewport_width: float = get_viewport_rect().size.x
	# Target max width: 95% of screen to leave slight margins
	var max_row_visual_width: float = viewport_width * 0.95
	
	# Pre-load needed data for width calculation
	for tag in ordered_tags:
		# Determine row index for this tag based on current accumulation
		if current_row_idx == 0:
			# Front row: Strict limit of 3
			if current_row_count >= 3:
				current_row_idx += 1
				current_row_count = 0
				current_row_width = 0.0
		else:
			# Back rows: Width-based limit
			# Estimate size at current row scale
			var config = character_manager.get_character(tag)
			var visual_w: float = 0.0
			
			if config:
				# Try to load neutral sprite to gauge width
				var path = config.folder_path + "neutral.png"
				if not FileAccess.file_exists(path):
					path = config.folder_path + "neutral.webp"
				
				var tex = load_external_texture(path)
				if tex:
					var bounds = get_sprite_content_bounds(tag, tex, "neutral")
					var row_scale_mult = pow(ROW_SCALE_FACTOR, current_row_idx)
					var user_scale = user_sprite_scales.get(tag, 1.0)
					var final_scale = global_base_sprite_size * user_scale * row_scale_mult
					
					var tex_w = float(tex.get_width()) * final_scale
					var content_ratio = bounds["right"] - bounds["left"]
					visual_w = tex_w * content_ratio
			
			# Use a default if texture load failed (e.g. 200px)
			if visual_w == 0.0:
				visual_w = 200.0 * pow(ROW_SCALE_FACTOR, current_row_idx)
				
			# Check if fits
			# Allow a standard overlap of ~10% per character (0.9 multiplier for added width)
			var effective_added_width: float = visual_w * 0.9
			
			if current_row_count > 0 and (current_row_width + effective_added_width) > max_row_visual_width:
				# Full, move to next row
				current_row_idx += 1
				current_row_count = 0
				current_row_width = 0.0
			
			current_row_width += effective_added_width
		
		# Assign
		sprite_rows[tag] = current_row_idx
		
		if not rows_tags.has(current_row_idx):
			rows_tags[current_row_idx] = []
		rows_tags[current_row_idx].append(tag)
		
		current_row_count += 1

	
	# Store row and scale info for each character
	for tag in all_tags:
		var row_idx: int = sprite_rows.get(tag, 0)
		var user_scale: float = user_sprite_scales.get(tag, 1.0)
		
		var row_scale_mult: float = pow(ROW_SCALE_FACTOR, row_idx)
		sprite_scales[tag] = global_base_sprite_size * user_scale * row_scale_mult

	# Calculate positions with group clustering
	# Assign each group to a zone (left, center, right)
	var group_zones: Dictionary = {}  # group_id -> zone (0=left, 1=center, 2=right)
	var group_ids: Array = groups.keys()
	
	print("DEBUG: Groups found: %d - %s" % [group_ids.size(), str(group_ids)])
	
	if group_ids.size() == 1:
		group_zones[group_ids[0]] = 1  # Single group in center
	elif group_ids.size() == 2:
		group_zones[group_ids[0]] = 0  # First group on left
		group_zones[group_ids[1]] = 2  # Second group on right
	elif group_ids.size() >= 3:
		for i in range(group_ids.size()):
			group_zones[group_ids[i]] = i % 3  # Distribute across zones
	
	print("DEBUG: Group zones: %s" % str(group_zones))
	print("DEBUG: Current group map: %s" % str(current_group_map))
	
	# Calculate positions for each row
	for row_idx in rows_tags.keys():
		var current_row_tags: Array = rows_tags[row_idx]
		# We need to pass types correctly - this cast works because elements are strings
		var row_tags_str: Array[String] = []
		for t in current_row_tags:
			row_tags_str.append(str(t))
			
		var positions: Array[float] = _calculate_grouped_positions(row_tags_str, groups, group_zones, solo_tags)
		
		for i in range(row_tags_str.size()):
			var tag: String = row_tags_str[i]
			sprite_x_positions[tag] = positions[i]
			character_slots[tag] = "row%d_%d" % [row_idx, i]

	# Now display all sprites
	
	# Now display all sprites
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		if tag == "" or not sprite_x_positions.has(tag):
			continue
		print("DEBUG: Showing sprite %s at x_ratio=%s, row=%s, scale=%s" % [tag, sprite_x_positions.get(tag, "?"), sprite_rows.get(tag, "?"), sprite_scales.get(tag, "?")])
		show_sprite(tag, "neutral", character_manager)
	
	# Clear speaking order to prevent load-order from determining Z-index bias
	# This ensures that upon entering a location, Z-index is determined purely by row depth
	speaking_order.clear()

	# Final layout pass to ensure all positions and flips are correct
	update_layout()

## Calculate positions keeping groups clustered together
## Each group gets a zone on the screen (left, center, right)
func _calculate_grouped_positions(row_tags: Array[String], groups: Dictionary, group_zones: Dictionary, solo_tags: Array[String]) -> Array[float]:
	if row_tags.is_empty():
		return []
	
	var positions: Array[float] = []
	positions.resize(row_tags.size())
	
	# Count how many characters from each group are in this row
	var group_counts_in_row: Dictionary = {}  # group_id -> count
	var solo_count_in_row: int = 0
	var solos_in_row: Array[String] = []
	var grouped_in_row: Dictionary = {}  # group_id -> [tags]
	
	for tag in row_tags:
		var group_id: String = current_group_map.get(tag, "")
		if group_id == "":
			solo_count_in_row += 1
			solos_in_row.append(tag)
		else:
			if not group_counts_in_row.has(group_id):
				group_counts_in_row[group_id] = 0
				grouped_in_row[group_id] = []
			group_counts_in_row[group_id] += 1
			grouped_in_row[group_id].append(tag)
	
	# Build sorted order: groups first (keeping members together), then solos
	var sorted_tags: Array[String] = []
	for group_id in grouped_in_row.keys():
		for tag in grouped_in_row[group_id]:
			sorted_tags.append(tag)
	for tag in solos_in_row:
		sorted_tags.append(tag)
	
	# Calculate evenly distributed positions across the full screen width
	# Use aggressive spacing to spread characters out and avoid clustering
	var sorted_positions: Array[float] = []
	var margin: float = 0.08  # Small margin to push sprites toward edges
	if sorted_tags.size() == 1:
		sorted_positions.append(0.5)
	elif sorted_tags.size() == 2:
		# Wide spread for two characters
		sorted_positions.append(0.20)
		sorted_positions.append(0.80)
	elif sorted_tags.size() == 3:
		# Spread across the full width for three characters
		# Positions will be adjusted dynamically based on content bounds in update_layout
		sorted_positions.append(0.08)
		sorted_positions.append(0.50)
		sorted_positions.append(0.88)
	else:
		# For 4+, distribute evenly with small margins
		var spacing: float = (1.0 - 2 * margin) / float(sorted_tags.size() - 1)
		for i in range(sorted_tags.size()):
			sorted_positions.append(margin + spacing * float(i))
	
	# Map sorted positions back to original row_tags order
	var tag_to_position: Dictionary = {}
	for i in range(sorted_tags.size()):
		tag_to_position[sorted_tags[i]] = sorted_positions[i]
	
	for i in range(row_tags.size()):
		positions[i] = tag_to_position[row_tags[i]]
	
	return positions
	


## Calculate evenly distributed positions for a row
## is_back_row: if true, offset positions to be between front row slots
func _calculate_row_positions(count: int, scale: float, y_offset: float, is_back_row: bool = false) -> Dictionary:
	if count == 0:
		return {"positions": [], "y_offset": y_offset}
	
	var positions: Array[float] = []
	
	# Back row uses offset positions (between front row slots)
	if is_back_row:
		# Offset to be between front row positions
		if count == 1:
			positions.append(0.5)  # Center
		elif count == 2:
			positions.append(0.375)  # Between left and center
			positions.append(0.625)  # Between center and right
		elif count == 3:
			positions.append(0.15)   # Far left
			positions.append(0.5)    # Center
			positions.append(0.85)   # Far right
		else:
			# 4+ characters: offset from front row positions
			var margin: float = 0.08
			var spacing: float = (1.0 - 2 * margin) / float(count - 1) if count > 1 else 0
			for i in range(count):
				positions.append(margin + spacing * float(i))
	else:
		# Front row - spread out to use more screen
		if count == 1:
			positions.append(0.5)  # Center
		elif count == 2:
			positions.append(0.25)
			positions.append(0.75)
		elif count == 3:
			positions.append(0.12)
			positions.append(0.50)
			positions.append(0.88)
		else:
			# 4+ characters: evenly distribute with small margins
			var margin: float = 0.08
			var spacing: float = (1.0 - 2 * margin) / float(count - 1) if count > 1 else 0
			for i in range(count):
				positions.append(margin + spacing * float(i))
	
	return {"positions": positions, "y_offset": y_offset}

## Get the group ID for a character tag (empty string if solo)
func get_character_group_id(tag: String) -> String:
	return current_group_map.get(tag, "")
