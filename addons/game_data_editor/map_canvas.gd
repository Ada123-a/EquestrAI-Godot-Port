@tool
class_name MapPointerCanvas
extends Control

signal pointer_clicked(location_id)
signal pointer_rect_changed(location_id, rect)
signal pointer_created(location_id, rect)

const BACKGROUND_COLOR := Color(0.1, 0.1, 0.1, 1.0)
const POINTER_COLOR := Color(0.2, 0.7, 1.0, 0.95)
const POINTER_COLOR_HOVER := Color(0.3, 0.9, 1.0, 0.95)
const POINTER_COLOR_SELECTED := Color(1.0, 0.65, 0.0, 0.95)

var map_texture: Texture2D
var pointer_data: Dictionary = {}
var label_lookup: Dictionary = {}
var selected_location_id := ""
var new_marker_size := Vector2(0.05, 0.05)

var _dragging := false
var _drag_location_id := ""
var _drag_offset := Vector2.ZERO
var _hover_location_id := ""

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(720, 420)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func set_map_texture(texture: Texture2D):
	map_texture = texture
	queue_redraw()

func set_pointer_dataset(pointer_dict: Dictionary, labels: Dictionary):
	pointer_data = pointer_dict.duplicate(true)
	label_lookup = labels.duplicate(true)
	_hover_location_id = ""
	_dragging = false
	queue_redraw()

func update_pointer_rect(location_id: String, rect: Rect2):
	pointer_data[location_id] = Rect2(rect.position, rect.size)
	queue_redraw()

func remove_pointer(location_id: String):
	pointer_data.erase(location_id)
	if selected_location_id == location_id:
		_dragging = false
	if _hover_location_id == location_id:
		_hover_location_id = ""
	queue_redraw()

func set_selected_location(location_id: String):
	selected_location_id = location_id
	queue_redraw()

func set_label_for_location(location_id: String, label: String):
	label_lookup[location_id] = label
	queue_redraw()

func clear_all():
	pointer_data.clear()
	label_lookup.clear()
	selected_location_id = ""
	_dragging = false
	_hover_location_id = ""
	queue_redraw()

func set_default_marker_size(size: Vector2):
	new_marker_size = size

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_press(event.position)
		else:
			_stop_drag()
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_to(event.position)
		else:
			var hovered = _get_location_at_pos(event.position)
			if hovered != _hover_location_id:
				_hover_location_id = hovered
				queue_redraw()

func _handle_left_press(pos: Vector2):
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var clicked = _get_location_at_pos(pos)
	if clicked != "":
		if clicked != selected_location_id:
			pointer_clicked.emit(clicked)
		_start_drag(clicked, pos)
		return
	if selected_location_id == "":
		return
	if pointer_data.has(selected_location_id):
		return
	var rect = _rect_from_click(pos)
	pointer_data[selected_location_id] = rect
	pointer_created.emit(selected_location_id, rect)
	queue_redraw()

func _start_drag(location_id: String, mouse_pos: Vector2):
	if not pointer_data.has(location_id):
		return
	var pixel_rect = _rect_to_pixels(pointer_data[location_id])
	_dragging = true
	_drag_location_id = location_id
	_drag_offset = mouse_pos - pixel_rect.position

func _drag_to(mouse_pos: Vector2):
	if not _dragging or not pointer_data.has(_drag_location_id):
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect = pointer_data[_drag_location_id]
	var new_top_left = mouse_pos - _drag_offset
	var normalized = Vector2(new_top_left.x / size.x, new_top_left.y / size.y)
	normalized.x = clampf(normalized.x, 0.0, 1.0 - rect.size.x)
	normalized.y = clampf(normalized.y, 0.0, 1.0 - rect.size.y)
	rect.position = normalized
	pointer_data[_drag_location_id] = rect
	pointer_rect_changed.emit(_drag_location_id, rect)
	queue_redraw()

func _stop_drag():
	_dragging = false
	_drag_location_id = ""

func _get_location_at_pos(pos: Vector2) -> String:
	for loc_id in pointer_data.keys():
		var rect = _rect_to_pixels(pointer_data[loc_id])
		if rect.has_point(pos):
			return loc_id
	return ""

func _rect_from_click(pos: Vector2) -> Rect2:
	var safe_size = Vector2(
		max(0.005, min(new_marker_size.x, 1.0)),
		max(0.005, min(new_marker_size.y, 1.0))
	)
	var normalized = Vector2(pos.x / max(1.0, size.x), pos.y / max(1.0, size.y))
	var top_left = normalized - (safe_size * 0.5)
	top_left.x = clampf(top_left.x, 0.0, 1.0 - safe_size.x)
	top_left.y = clampf(top_left.y, 0.0, 1.0 - safe_size.y)
	return Rect2(top_left, safe_size)

func _rect_to_pixels(rect: Rect2) -> Rect2:
	return Rect2(
		Vector2(rect.position.x * size.x, rect.position.y * size.y),
		Vector2(rect.size.x * size.x, rect.size.y * size.y)
	)

func _draw():
	if map_texture:
		draw_texture_rect(map_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
		var font = get_theme_default_font()
		if font:
			var text = "No map texture assigned."
			draw_string(font, Vector2(10, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16.0, Color(0.8, 0.8, 0.8))
	for loc_id in pointer_data.keys():
		var rect = _rect_to_pixels(pointer_data[loc_id])
		var color = POINTER_COLOR
		if loc_id == selected_location_id:
			color = POINTER_COLOR_SELECTED
		elif loc_id == _hover_location_id:
			color = POINTER_COLOR_HOVER
		draw_rect(rect, color, false, 2.0)
		var label = label_lookup.get(loc_id, loc_id)
		var font = get_theme_default_font()
		if font and label != "":
			var text = label
			var text_pos = rect.position + Vector2(4, min(rect.size.y, 20))
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14.0, color)
