extends PanelContainer

signal closed

const InventorySlotClass = preload("res://scenes/ui/components/InventorySlot.tscn")

@onready var grid = %GridContainer
@onready var close_button = $Margin/VBox/HeaderBox/CloseButton
@onready var context_menu = %ContextMenu
@onready var empty_label = %EmptyLabel
@onready var header = $Margin/VBox/HeaderBox
@onready var scroll_container = $Margin/VBox/ScrollContainer

var inventory_manager: InventoryManager
var current_selected_slot_data = null

var dragging = false
var drag_start_pos = Vector2()
var scroll_speed = 300.0
var scroll_threshold = 50.0

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	context_menu.id_pressed.connect(_on_context_menu_action)
	
	# Initialize context menu
	context_menu.clear()
	context_menu.add_item("Eat", 0)
	context_menu.add_item("Discard", 1)
	context_menu.add_item("Cancel", 2)
	
	# Ensure we can catch input
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Adjust margins to fit rounded corners
	var margin = $Margin
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_is_dragging():
			return # Item is being dragged, don't close
			
		# Check if click is outside the panel
		# using global coordinates
		if not get_global_rect().has_point(event.global_position):
			get_viewport().set_input_as_handled()
			_on_close_pressed()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start_pos = event.position
			else:
				dragging = false
	
	if event is InputEventMouseMotion and dragging:
		position += event.position - drag_start_pos

func _process(delta):
	# Auto-scroll when dragging an item
	if get_viewport().gui_is_dragging():
		var mouse_pos = scroll_container.get_local_mouse_position()
		var rect = scroll_container.get_rect()
		var height = rect.size.y
		
		# Only scroll if mouse is roughly horizontally within the container
		if mouse_pos.x >= 0 and mouse_pos.x <= rect.size.x:
			if mouse_pos.y < scroll_threshold:
				# Scroll up
				# Factor is 0.0 at threshold, 1.0 at top
				var factor = 1.0 - (max(0, mouse_pos.y) / scroll_threshold) 
				scroll_container.scroll_vertical -= int(scroll_speed * factor * delta)
				
			elif mouse_pos.y > height - scroll_threshold:
				# Scroll down
				# Factor is 0.0 at threshold, 1.0 at bottom
				var factor = (min(height, mouse_pos.y) - (height - scroll_threshold)) / scroll_threshold
				scroll_container.scroll_vertical += int(scroll_speed * factor * delta)

func _can_drop_data(_at_position, data):
	# Accept drop to prevent "Forbidden" cursor, but do nothing
	return typeof(data) == TYPE_DICTIONARY and data.has("index")

func _drop_data(_at_position, _data):
	# Do nothing, item returns to slot via drag_end notification
	pass

func initialize(manager: InventoryManager):
	inventory_manager = manager
	refresh()

func refresh():
	# Clear existing slots
	for child in grid.get_children():
		child.queue_free()
	
	# Always hide empty label since we show empty slots
	empty_label.visible = false

	var items = []
	if inventory_manager:
		var data = inventory_manager.get_inventory()
		items = data.get("items", [])
	
	# Define grid capacity (e.g., 3 columns * 5 rows = 15 slots minimum)
	var min_slots = 15
	var slot_count = max(min_slots, items.size())
	
	# Ensure complete rows (assuming 3 columns from earlier tscn inspection)
	var columns = 3
	if slot_count % columns != 0:
		slot_count += columns - (slot_count % columns)

	for i in range(slot_count):
		var slot = InventorySlotClass.instantiate()
		grid.add_child(slot)
		
		slot.slot_index = i
		
		if i < items.size() and items[i] != null:
			slot.set_item(items[i])
		else:
			slot.set_empty()
			
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.item_dropped.connect(_on_item_dropped)

func _on_slot_clicked(slot_data):
	current_selected_slot_data = slot_data
	context_menu.position = get_viewport().get_mouse_position()
	context_menu.popup()

func _on_context_menu_action(id):
	if current_selected_slot_data == null: return
	
	match id:
		0: # Eat
			print("Eat item: ", current_selected_slot_data.get("id"))
			inventory_manager.remove_item(current_selected_slot_data.get("id"), 1)
			refresh()
		1: # Discard
			print("Discard item: ", current_selected_slot_data.get("id"))
			inventory_manager.remove_item(current_selected_slot_data.get("id"), 1)
			refresh()
		2: # Cancel
			pass

func _on_close_pressed():
	closed.emit()

func _on_item_dropped(from_index: int, to_index: int):
	if inventory_manager:
		inventory_manager.move_item(from_index, to_index)
		refresh()
