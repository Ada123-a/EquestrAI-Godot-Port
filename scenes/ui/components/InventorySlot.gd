extends PanelContainer

signal slot_clicked(slot_data)
signal item_dropped(source_index, target_index)

@onready var icon_rect = $Margin/Icon
@onready var stack_label = $StackLabel
@onready var button = $Button

var slot_data: Dictionary = {}
var slot_index: int = -1

func _ready():
	button.gui_input.connect(_on_button_gui_input)
	button.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)
	button.focus_mode = Control.FOCUS_NONE
	
	# Pass-through mouse for non-interactive visual elements
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_apply_styling()

func _apply_styling():
	# Make slots rounded like theme buttons
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.25) # Lighter, matching theme ethos
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	
	# Apply to button states
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	
	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0, 0, 0, 0.1) # Very subtle for empty slots
	button.add_theme_stylebox_override("disabled", disabled_style)
	
func set_empty():
	slot_data = {}
	icon_rect.texture = null
	button.text = ""
	button.tooltip_text = ""
	stack_label.visible = false
	button.disabled = true # Disable button interaction for empty slots, but allow drop via PanelContainer
	
func set_item(data: Dictionary):
	button.disabled = false
	slot_data = data
	var amount = data.get("amount", 1)
	var item_id = data.get("id", "unknown")
	var item_meta = data.get("data", {})
	
	# Try to load icon
	var icon_path = "res://assets/Items/%s.webp" % item_id
	if FileAccess.file_exists(icon_path):
		icon_rect.texture = load(icon_path)
		button.text = ""
	else:
		# Fallback
		icon_rect.texture = null
		button.text = item_id.substr(0, 2).capitalize()
		
	# Stack Size
	if amount > 1:
		stack_label.text = str(amount)
		stack_label.visible = true
	else:
		stack_label.visible = false
	
	# Tooltip
	var dname = item_id.capitalize()
	if item_meta.has("name"): dname = item_meta["name"]
	if item_meta.has("description"):
		button.tooltip_text = "%s\n%s\nAmount: %d" % [dname, item_meta["description"], amount]
	else:
		button.tooltip_text = "%s\nAmount: %d" % [dname, amount]

func _on_button_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not slot_data.is_empty():
				slot_clicked.emit(slot_data)

func _get_drag_data(at_position):
	if slot_data.is_empty():
		return null
		
	var data = {
		"index": slot_index,
		"item": slot_data
	}
	
	# Create drag preview
	# Create drag preview centered on mouse
	var preview_control = Control.new()
	preview_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var preview_icon = TextureRect.new()
	preview_icon.texture = icon_rect.texture
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.size = Vector2(50, 50)
	preview_icon.position = -preview_icon.size / 2 # Center the icon
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	preview_control.add_child(preview_icon)
	set_drag_preview(preview_control)
	
	# Hide visuals to simulate "lifting" the item
	icon_rect.modulate.a = 0.0
	stack_label.modulate.a = 0.0
	
	# Temporarily disable tooltip to prevent artifacts
	button.tooltip_text = ""
	
	return data

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		# Restore visuals
		if is_instance_valid(icon_rect): icon_rect.modulate.a = 1.0
		if is_instance_valid(stack_label): stack_label.modulate.a = 1.0
		
		# Restore tooltip if data exists
		if is_instance_valid(button) and not slot_data.is_empty():
			var item_id = slot_data.get("id", "unknown")
			var item_meta = slot_data.get("data", {})
			var amount = slot_data.get("amount", 1)
			
			var dname = item_id.capitalize()
			if item_meta.has("name"): dname = item_meta["name"]
			if item_meta.has("description"):
				button.tooltip_text = "%s\n%s\nAmount: %d" % [dname, item_meta["description"], amount]
			else:
				button.tooltip_text = "%s\nAmount: %d" % [dname, amount]

func _can_drop_data(at_position, data):
	return typeof(data) == TYPE_DICTIONARY and data.has("index")

func _drop_data(at_position, data):
	item_dropped.emit(data["index"], slot_index)
