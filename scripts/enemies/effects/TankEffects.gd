extends Node2D
class_name TankEffects

## Visual effects for Tank enemies: shadow only

var _enemy: Node2D = null
var _shadow: Node2D = null

func _ready() -> void:
	_enemy = get_parent()
	_setup_shadow()
	_setup_hp_bar_color()
	z_index = -1

func _setup_hp_bar_color() -> void:
	# Make tank HP bar yellow
	if _enemy and _enemy.has_node("ProgressBar"):
		var hp_bar: ProgressBar = _enemy.get_node("ProgressBar")
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = Color(0.95, 0.85, 0.2, 1.0)  # Yellow
		hp_bar.add_theme_stylebox_override("fill", fill_style)

func _setup_shadow() -> void:
	# Shadow underneath tank - positioned at sprite feet
	_shadow = Node2D.new()
	_shadow.name = "TankShadow"
	_shadow.z_index = -3
	var script := GDScript.new()
	script.source_code = """
extends Node2D

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Get sprite info for proper feet positioning
	var parent := get_parent().get_parent()
	var sprite = parent.get_node_or_null("AnimatedSprite2D") if parent else null
	var feet_offset: float = 20.0  # Default
	if sprite and sprite.sprite_frames:
		var anim = sprite.animation
		if sprite.sprite_frames.has_animation(anim) and sprite.sprite_frames.get_frame_count(anim) > 0:
			var tex = sprite.sprite_frames.get_frame_texture(anim, 0)
			if tex:
				feet_offset = tex.get_height() * sprite.scale.y * 0.4
	
	var shadow_color := Color(0.0, 0.0, 0.0, 0.4)
	draw_set_transform(Vector2(0, feet_offset), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 28.0, shadow_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
"""
	script.reload()
	_shadow.set_script(script)
	add_child(_shadow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()
