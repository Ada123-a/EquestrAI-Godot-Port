extends TextureButton

func _ready():
	# Set pivot to center for correct scaling
	pivot_offset = size / 2
	# Connect signals
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	# Update pivot if size changes (e.g. layout update)
	resized.connect(func(): pivot_offset = size / 2)

func _on_hover():
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_exit():
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
