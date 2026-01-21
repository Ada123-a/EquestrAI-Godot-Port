extends Node
class_name InventoryManager

# Dependencies
var main_node: Node # Reference to Main.gd

# Constants
const DEFAULT_MAX_STACK = 99

# Function to initialize inventory in global vars if not present
func initialize_inventory() -> void:
	if not main_node: return
	
	if not main_node.global_vars.has("inventory"):
		var items = []
		items.resize(30) # Default inventory size
		items[0] = { "id": "Apple", "amount": 1, "data": { "name": "Apple", "description": "A juicy red apple.", "max_stack": 5 } }
		main_node.global_vars["inventory"] = {
			"items": items
		}
	else:
		# Validate inventory size
		var items = main_node.global_vars["inventory"]["items"]
		if items.size() < 30:
			items.resize(30)
			
		# For current testing ensuring apple is there if list is empty (check first slot)
		if items[0] == null:
			add_item("Apple", 1, { "name": "Apple", "description": "A juicy red apple.", "max_stack": 5 })
		
		# Migration: Update existing Apples to have max_stack 5
		for slot in items:
			if slot != null and slot["id"] == "Apple":
				if not slot["data"].has("max_stack"):
					slot["data"]["max_stack"] = 5

# Helper to get the inventory array reference
func _get_items() -> Array:
	if not main_node or not main_node.global_vars.has("inventory"):
		return []
	return main_node.global_vars["inventory"]["items"]

# Helper to save/notify (placeholder for now, can emit signals later)
func _on_inventory_changed():
	# Potential signal emission here if we add signals to Main or this manager
	pass

## Add an item to the inventory
## Returns the amount that was successfully added
func add_item(item_id: String, amount: int, item_data: Dictionary = {}) -> int:
	if amount <= 0: return 0
	
	var items = _get_items()
	var remaining = amount
	var max_stack = item_data.get("max_stack", DEFAULT_MAX_STACK)
	
	# 1. Try to stack with existing items
	for i in range(items.size()):
		var slot = items[i]
		if slot != null and slot["id"] == item_id:
			var current_amount = slot["amount"]
			var space = max_stack - current_amount
			
			if space > 0:
				var to_add = min(remaining, space)
				slot["amount"] += to_add
				remaining -= to_add
				
				if remaining <= 0:
					_on_inventory_changed()
					return amount
	
	# 2. Add to first empty slot
	while remaining > 0:
		var empty_index = -1
		for i in range(items.size()):
			if items[i] == null:
				empty_index = i
				break
		
		# If inventory full, return what we managed to add
		if empty_index == -1:
			_on_inventory_changed()
			return amount - remaining

		var to_add = min(remaining, max_stack)
		var new_slot = {
			"id": item_id,
			"amount": to_add,
			"data": item_data.duplicate()
		}
		
		items[empty_index] = new_slot
		remaining -= to_add
	
	_on_inventory_changed()
	return amount

## Remove an item from the inventory
## Returns true if the full amount was removed, false otherwise
func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0: return true
	if not has_item(item_id, amount): return false
	
	var items = _get_items()
	var remaining = amount
	
	# Iterate backwards to safely remove empty slots
	# Iterate to find and remove
	for i in range(items.size() - 1, -1, -1):
		var slot = items[i]
		if slot != null and slot["id"] == item_id:
			var take = min(remaining, slot["amount"])
			slot["amount"] -= take
			remaining -= take
			
			if slot["amount"] <= 0:
				items[i] = null
			
			if remaining <= 0:
				break
				
	_on_inventory_changed()
	return true # We checked has_item first, so this should always be true

## Check if inventory has at least this amount of item
func has_item(item_id: String, amount: int = 1) -> bool:
	var count = 0
	var items = _get_items()
	if not items: return false
	for slot in items:
		if slot != null and slot["id"] == item_id:
			count += slot["amount"]
	return count >= amount

## Get full inventory state
func get_inventory() -> Dictionary:
	if not main_node or not main_node.global_vars.has("inventory"):
		return {"items": []}
	return main_node.global_vars["inventory"]

## Debug: Clear inventory
func clear_inventory() -> void:
	if not main_node: return
	main_node.global_vars["inventory"] = { "items": [] }
	_on_inventory_changed()

## Move item from one slot to another (swap or stack)
func move_item(from_index: int, to_index: int) -> void:
	var items = _get_items()
	if from_index < 0 or from_index >= items.size(): return
	if to_index < 0 or to_index >= items.size(): return
	if from_index == to_index: return
	
	var from_slot = items[from_index]
	var to_slot = items[to_index]
	
	if from_slot == null: return # Nothing to move
	
	if to_slot == null:
		# Simple move
		items[to_index] = from_slot
		items[from_index] = null
	else:
		# Check if stackable
		if from_slot["id"] == to_slot["id"]:
			var max_stack = to_slot["data"].get("max_stack", DEFAULT_MAX_STACK)
			var space = max_stack - to_slot["amount"]
			
			if space > 0:
				var to_add = min(from_slot["amount"], space)
				to_slot["amount"] += to_add
				from_slot["amount"] -= to_add
				
				if from_slot["amount"] <= 0:
					items[from_index] = null
				
				_on_inventory_changed()
				return

		# Swap
		items[from_index] = to_slot
		items[to_index] = from_slot
	
	_on_inventory_changed()
