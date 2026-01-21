extends Control

signal location_selected(location_id)
signal map_closed

var location_manager
var map_manager
var schedule_manager
var character_manager
var main_node # For accessing global_vars
var current_region := ""

var header_label: Label

var map_texture_rect: TextureRect
var marker_layer: Control
var list_container: VBoxContainer
var audio_player: AudioStreamPlayer
var info_label: Label
var current_marker_specs: Array = []
var music_path: String = ""

const MAX_MAP_ICONS = 4
const ICON_SIZE = Vector2(40, 40) # Target size for map icons

func initialize(p_location_manager, p_map_manager, p_schedule_manager, p_character_manager, p_main_node):
	location_manager = p_location_manager
	map_manager = p_map_manager
	schedule_manager = p_schedule_manager
	character_manager = p_character_manager
	main_node = p_main_node

func _ready():
	_build_ui()
	_load_current_region()

func _build_ui():
	# Clear any existing children (from Tscn or previous builds)
	for child in get_children():
		child.queue_free()
		
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 1. Background Dim - Darker and more opaque for better focus
	var dim = ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.95)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# 2. Main Layout Container
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 30)
	main_margin.add_theme_constant_override("margin_right", 30)
	main_margin.add_theme_constant_override("margin_top", 30)
	main_margin.add_theme_constant_override("margin_bottom", 30)
	add_child(main_margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 20)
	main_margin.add_child(content_vbox)

	# 3. Upper Area: Map + Sidebar
	var split_hbox = HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 20)
	content_vbox.add_child(split_hbox)

	# Map Section (Left, takes 3.5 flex)
	var map_wrapper = Control.new()
	map_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_wrapper.size_flags_stretch_ratio = 3.5
	map_wrapper.clip_contents = true
	split_hbox.add_child(map_wrapper)

	# Visual border for map
	var map_bg_panel = Panel.new()
	map_bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3)
	map_bg_panel.add_theme_stylebox_override("panel", style)
	map_wrapper.add_child(map_bg_panel)

	map_texture_rect = TextureRect.new()
	map_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_texture_rect.resized.connect(func():
		if current_region != "":
			call_deferred("_render_markers", current_region)
	)
	map_wrapper.add_child(map_texture_rect)

	marker_layer = Control.new()
	marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	map_wrapper.add_child(marker_layer)

	# Sidebar Section (Right, takes 1 flex)
	var sidebar_panel = PanelContainer.new()
	sidebar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_panel.size_flags_stretch_ratio = 1.0
	split_hbox.add_child(sidebar_panel)

	var sidebar_margin = MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 15)
	sidebar_margin.add_theme_constant_override("margin_right", 15)
	sidebar_margin.add_theme_constant_override("margin_top", 15)
	sidebar_margin.add_theme_constant_override("margin_bottom", 15)
	sidebar_panel.add_child(sidebar_margin)

	var sidebar_vbox = VBoxContainer.new()
	sidebar_vbox.add_theme_constant_override("separation", 10)
	sidebar_margin.add_child(sidebar_vbox)

	var title_lbl = Label.new()
	title_lbl.text = "LOCATIONS"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sidebar_vbox.add_child(title_lbl)

	header_label = Label.new()
	header_label.text = "Region"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 24)
	header_label.add_theme_color_override("font_color", Color(1, 1, 1))
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar_vbox.add_child(header_label)

	sidebar_vbox.add_child(HSeparator.new())

	info_label = Label.new()
	info_label.text = "Select a location."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	sidebar_vbox.add_child(info_label)

	var list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	sidebar_vbox.add_child(list_scroll)

	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 8)
	list_scroll.add_child(list_container)

	# 4. Bottom Area: Close Button
	var bottom_center = CenterContainer.new()
	bottom_center.custom_minimum_size = Vector2(0, 80)
	content_vbox.add_child(bottom_center)

	var close_btn = Button.new()
	close_btn.text = "EXIT MAP"
	close_btn.custom_minimum_size = Vector2(200, 50)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_on_close_pressed)
	bottom_center.add_child(close_btn)

	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Master"
	add_child(audio_player)

func _load_current_region():
	if location_manager == null:
		return
	
	var cur_loc_id = location_manager.current_location_id
	var loc_data = location_manager.get_location(cur_loc_id)
	
	if loc_data:
		_show_region(loc_data.region)
	else:
		info_label.text = "Could not determine current region."



func _show_region(region_name: String):
	current_region = region_name
	header_label.text = region_name + " Map"
	var map_data = null
	if map_manager != null:
		map_data = map_manager.get_map_for_region(region_name)
	if map_data and map_data.texture_path != "":
		var texture = load(map_data.texture_path)
		if texture:
			map_texture_rect.texture = texture
	else:
		map_texture_rect.texture = null
	call_deferred("_render_markers", region_name)
	
	music_path = ""
	if map_data and map_data.music_path != "":
		music_path = map_data.music_path

func _render_markers(region_name: String):
	current_marker_specs.clear()
	for child in list_container.get_children():
		child.queue_free()
	var locations = location_manager.get_locations_in_region(region_name)
	if locations.is_empty():
		info_label.text = "No locations available in this region."
		return
	info_label.text = "Select a location to travel."
	for loc in locations:
		var entry = Button.new()
		entry.text = loc.name
		entry.tooltip_text = loc.description
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.clip_text = false
		# Make text visible with better styling
		entry.add_theme_font_size_override("font_size", 14)
		entry.custom_minimum_size = Vector2(0, 40)
		entry.pressed.connect(_on_location_pressed.bind(loc.id))
		list_container.add_child(entry)
		if loc.has_map_rect:
			current_marker_specs.append({
				"id": loc.id,
				"rect": loc.map_rect,
				"name": loc.name
			})
	_update_marker_zones()

func _on_location_pressed(loc_id: String):
	emit_signal("location_selected", loc_id)
	_close_overlay()

func _update_marker_zones():
	if marker_layer == null:
		return
	for child in marker_layer.get_children():
		child.queue_free()
	if current_marker_specs.is_empty():
		return
	var size = marker_layer.size
	if size.x <= 0 or size.y <= 0:
		call_deferred("_update_marker_zones")
		return
	
	# Fetch schedule info if available
	var day = 0
	var slot = "morning"
	if main_node and main_node.global_vars:
		day = int(main_node.global_vars.get("day_index", 0))
		# time_slot enum 0=morning, 1=day, 2=night
		var slot_idx = int(main_node.global_vars.get("time_slot", 0))
		match slot_idx:
			0: slot = "morning"
			1: slot = "day"
			2: slot = "night"
	
	# Determine characters for each location BEFORE drawing
	# We want to know where they are
	
	for spec in current_marker_specs:
		var rect: Rect2 = spec["rect"]
		# Skip invalid/unset map rects
		if rect.has_area() == false or rect.size.x <= 0 or rect.size.y <= 0:
			continue
			
		var px_pos = Vector2(rect.position.x * size.x, rect.position.y * size.y)
		var px_size = Vector2(rect.size.x * size.x, rect.size.y * size.y)
		var loc_id = spec["id"]
		
		var zone = ColorRect.new()
		zone.color = Color(0, 0, 0, 0) # Fully transparent
		zone.mouse_filter = Control.MOUSE_FILTER_STOP
		zone.focus_mode = Control.FOCUS_NONE
		zone.tooltip_text = spec["name"]
		zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
		zone.position = px_pos
		zone.size = px_size
		zone.gui_input.connect(_on_map_zone_input.bind(loc_id))
		
		# --- Add Character Icons ---
		var characters_at_loc = []
		if schedule_manager:
			characters_at_loc = schedule_manager.roll_location_assignments(loc_id, day, slot)
		
		if not characters_at_loc.is_empty():
			# Use CenterContainer to align icons within the zone, fully transparent
			var center_con = CenterContainer.new()
			center_con.set_anchors_preset(Control.PRESET_FULL_RECT)
			center_con.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			# Grid for icons
			var icon_container = GridContainer.new()
			# Determine columns based on Aspect Ratio of the click zone
			var aspect = px_size.x / max(1.0, px_size.y)
			if aspect > 2.0:
				icon_container.columns = 4 # Flat row for very wide zones
			else:
				icon_container.columns = 2 # 2x2 Box for roughly square/tall zones
				
			icon_container.add_theme_constant_override("h_separation", 2)
			icon_container.add_theme_constant_override("v_separation", 2)
			icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var shown_count = 0
			for assignment in characters_at_loc:
				if shown_count >= MAX_MAP_ICONS: 
					break
				
				var tag = assignment["tag"]
				var tex = _get_character_icon_texture(tag)
				if tex:
					var icon_rect = TextureRect.new()
					icon_rect.texture = tex
					icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					icon_rect.custom_minimum_size = Vector2(32, 32)
					icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
					icon_container.add_child(icon_rect)
					shown_count += 1
			
			if shown_count > 0:
				center_con.add_child(icon_container)
				zone.add_child(center_con)
				
		marker_layer.add_child(zone)

func _get_character_icon_texture(tag: String) -> Texture2D:
	if not character_manager:
		return null
	var config = character_manager.get_character(tag)
	if not config:
		return null
		
	# 1. Try "icon/icon.png" or similar relative to char folder
	# Config.folder_path usually ends with '/'
	# Normal Mane 6 structure: res://assets/CoreCharacters/Twilight/sprites/
	# We need to peek at parent folder structure if necessary, depending on how folder_path is set.
	# CharacterManager.add_character says it captures the sprite folder.
	
	var base_folder = config.folder_path
	# If folder ends in "sprites/", go up one level
	if base_folder.strip_edges().ends_with("/sprites/"):
		base_folder = base_folder.strip_edges().trim_suffix("sprites/")
	
	# Check icon folder
	var icon_candidates = [
		base_folder.path_join("icon/icon.png"),
		base_folder.path_join("icon/icon.webp"),
		base_folder.path_join("icon/icon.jpg")
	]
	
	for path in icon_candidates:
		if FileAccess.file_exists(path):
			return load(path)
			
	# 2. Check for "icon.png" in base folder
	var base_icon_candidates = [
		base_folder.path_join("icon.png"),
		base_folder.path_join("icon.webp")
	]
	for path in base_icon_candidates:
		if FileAccess.file_exists(path):
			return load(path)
			
	# 3. Fallback: sprites/neutral.png
	var sprite_candidates = [
		config.folder_path.path_join("neutral.png"),
		config.folder_path.path_join("neutral.webp"),
		base_folder.path_join("sprites/neutral.png"),
		base_folder.path_join("sprites/neutral.webp")
	]
	
	for path in sprite_candidates:
		if FileAccess.file_exists(path):
			return load(path)
			
	return null

func _on_map_zone_input(event: InputEvent, location_id: String):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_location_pressed(location_id)

func _on_close_pressed():
	_close_overlay()

func _close_overlay():
	emit_signal("map_closed")
