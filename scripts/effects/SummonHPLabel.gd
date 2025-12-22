extends Node2D

# Draws HP text centered on summon HP bar - same as EnemyHPLabel but for allies

var _current_hp: int = 1
var _max_hp: int = 1
var _owner_node: Node = null

func setup(summon_owner: Node) -> void:
	_owner_node = summon_owner
	if summon_owner:
		if summon_owner.has_method("get") and summon_owner.get("current_hp") != null:
			_current_hp = summon_owner.current_hp
			_max_hp = summon_owner.max_hp
	
	# Apply unshaded material to prevent night darkening
	var unshaded_mat := CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_mat
	
	queue_redraw()

func update_values(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum
	queue_redraw()

func _process(_delta: float) -> void:
	# Counter-scale to compensate for parent scaling (keeps text crisp)
	if _owner_node and is_instance_valid(_owner_node):
		var parent_scale: Vector2 = _owner_node.scale
		if parent_scale.x > 0 and parent_scale.y > 0:
			scale = Vector2.ONE / parent_scale

func _draw() -> void:
	var text := "%d/%d" % [_current_hp, _max_hp]
	var font := ThemeDB.fallback_font
	var font_size := 10  # Slightly smaller for summons
	
	# Get text size for centering
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	# Center horizontally and vertically
	var draw_pos := Vector2(
		-text_size.x * 0.5,
		font_size * 0.4
	)
	
	# Draw black outline for readability
	var shadow_color := Color(0, 0, 0, 1.0)
	var offsets := [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
	]
	for offset in offsets:
		draw_string(font, draw_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
	
	# Draw white text
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
